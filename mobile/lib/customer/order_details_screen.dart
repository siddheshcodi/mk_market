import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/order_status.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// FR-U-12, FR-U-13: live status, the "share your OTP" prompt, items and address.
/// There is no cancel option anywhere (FR-U-14).
class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> with Polling {
  Map<String, dynamic>? _order;
  Object? _error;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _load();
    // No push notifications (A9): refresh every 15 seconds while this screen is open.
    startPolling(const Duration(seconds: 15), _load);
  }

  Future<void> _load() async {
    try {
      final order = await context.read<ApiClient>().get('/orders/${widget.orderId}') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _order = order;
          _error = null;
          _updatedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted && _order == null) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(
        title: Text(order?['displayOrderId'] as String? ?? 'Order'),
        actions: [
          if (order != null)
            IconButton(
              tooltip: 'Copy order ID',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => copyText(context, order['displayOrderId'] as String, 'Order ID'),
            ),
        ],
      ),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : order == null
          ? const SkeletonList(count: 4, height: 140)
          : RefreshIndicator(onRefresh: _load, child: _details(context, order)),
    );
  }

  Widget _details(BuildContext context, Map<String, dynamic> order) {
    final status = orderStatus(order['status'] as String);
    final otpActive = order['deliveryOtpActive'] == true && status == OrderStatus.outForDelivery;
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    final address = order['address'] as Map<String, dynamic>;
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final timeline = parseTimeline(order['timeline']);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusHero(status: status, otpActive: otpActive, timeline: timeline),
              const SizedBox(height: 12),
              if (otpActive)
                InfoBanner(
                  tone: Tone.success,
                  icon: Icons.sms_rounded,
                  title: 'Your order is at your door',
                  message:
                      'Share the OTP sent to your phone with the delivery person. Share it only after you receive your items.',
                ),
              if (status == OrderStatus.undelivered)
                const InfoBanner(
                  tone: Tone.error,
                  icon: Icons.assignment_return_rounded,
                  title: 'Undelivered – returned to store',
                  message: 'Any refund will be processed manually. The store will contact you.',
                ),
              SectionCard(
                title: 'Order status',
                child: StatusProgress(timeline: timeline, current: status),
              ),
              SectionCard(
                title: 'Items · ${itemsLabel(items.length)}',
                icon: Icons.shopping_bag_outlined,
                child: Column(
                  children: [
                    for (final item in items)
                      ValueRow(
                        '${item['name']}',
                        rupees(item['lineTotalPaise'] as int),
                        subtitle: '${item['unit']} · Qty ${item['qty']}',
                      ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider()),
                    ValueRow('Delivery fee', 'FREE', valueColor: colors.success),
                    ValueRow('Paid in advance', rupees(order['totalPaise'] as int), bold: true),
                  ],
                ),
              ),
              SectionCard(
                title: 'Delivery address',
                icon: Icons.home_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${address['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(addressLine(address), style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
                  ],
                ),
              ),
              SectionCard(
                title: 'From',
                icon: Icons.storefront_outlined,
                child: Text(order['storeName'] as String? ?? 'MK Market', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (_updatedAt != null && !status.isClosed)
                const HintLine(
                  icon: Icons.sync_rounded,
                  text: 'Updates automatically · pull down to refresh',
                  fontSize: 12,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Big coloured card with the customer-facing status text (spec §6.7).
class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.status, required this.otpActive, required this.timeline});

  final OrderStatus status;
  final bool otpActive;
  final List<({OrderStatus status, DateTime at})> timeline;

  @override
  Widget build(BuildContext context) {
    final color = status.color(context);
    final at = timeline.where((t) => t.status == status).firstOrNull?.at;
    final (title, subtitle) = switch (status) {
      OrderStatus.placed => ('Order placed', 'The store has your order and will send it out soon.'),
      OrderStatus.outForDelivery when otpActive => (
        'On the way for delivery',
        'Your delivery person has arrived with your order.',
      ),
      OrderStatus.outForDelivery => ('On the way for delivery', 'A delivery person is bringing your order.'),
      OrderStatus.delivered => ('Delivered', 'Your order was delivered. Thank you for shopping with us!'),
      OrderStatus.undelivered => ('Undelivered', 'Returned to store. Any refund will be processed manually.'),
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: status.container(context),
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(otpActive ? Icons.sms_rounded : status.icon, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(height: 1.35)),
                if (at != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    friendlyDateTime(at),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
