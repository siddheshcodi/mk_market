import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/order_status.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'delivery_otp_screen.dart';

/// FR-D-03, FR-D-04: customer details while on the way, and the "Delivered" action that sends the OTP.
class DeliveryOrderDetailsScreen extends StatefulWidget {
  const DeliveryOrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<DeliveryOrderDetailsScreen> createState() => _DeliveryOrderDetailsScreenState();
}

class _DeliveryOrderDetailsScreenState extends State<DeliveryOrderDetailsScreen> {
  Map<String, dynamic>? _order;
  Object? _error;
  bool _sending = false;
  final Set<int> _checked = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await context.read<ApiClient>().get('/delivery/orders/${widget.orderId}') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _order = order;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _delivered() async {
    final ok = await confirmSheet(
      context,
      title: 'Mark as delivered?',
      message: "Are you at the customer's location? An OTP will be sent to the customer.",
      confirmLabel: 'Send OTP',
      cancelLabel: 'Not yet',
      icon: Icons.sms_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      await context.read<ApiClient>().post('/delivery/orders/${widget.orderId}/delivery-otp');
      await _openOtp();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openOtp() async {
    final closed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DeliveryOtpScreen(orderId: widget.orderId, displayOrderId: _order!['displayOrderId'] as String),
      ),
    );
    if (!mounted) return;
    if (closed == true) {
      Navigator.of(context).pop();
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final otp = order?['deliveryOtp'] as Map<String, dynamic>?;
    final otpSent = otp != null && (otp['status'] == 'ACTIVE' || otp['status'] == 'EXPIRED');
    final onTheWay = order?['status'] == 'OUT_FOR_DELIVERY';
    return Scaffold(
      appBar: AppBar(title: Text(order?['displayOrderId'] as String? ?? 'Order')),
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : order == null
          ? const SkeletonList(count: 4, height: 140)
          : RefreshIndicator(onRefresh: _load, child: _details(order)),
      bottomNavigationBar: onTheWay
          ? BottomActionBar(
              child: PrimaryButton(
                label: otpSent ? 'Enter OTP' : 'Delivered',
                icon: otpSent ? Icons.pin_rounded : Icons.check_circle_rounded,
                busy: _sending,
                onPressed: otpSent ? _openOtp : _delivered,
              ),
            )
          : null,
    );
  }

  Widget _details(Map<String, dynamic> order) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final customer = order['customer'] as Map<String, dynamic>?;
    final address = order['address'] as Map<String, dynamic>;
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    final status = orderStatus(order['status'] as String);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (customer == null)
                // NFR-04: customer details are hidden once the order is closed.
                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: status.container(context),
                    borderRadius: BorderRadius.circular(AppTheme.radius + 4),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: status.color(context),
                        child: Icon(status.icon, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              status.label,
                              style: theme.textTheme.titleLarge?.copyWith(color: status.color(context)),
                            ),
                            Text('${address['area']}, ${address['pincode']}'),
                            Text(
                              'Closed ${friendlyDateTime(parseTime(order['closedAt']))}',
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                            ),
                            if (status == OrderStatus.undelivered)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                  'Please return this order to the store.',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                InfoBanner(
                  tone: Tone.success,
                  icon: Icons.verified_rounded,
                  title: 'Paid in advance – do not collect money',
                  message: '${rupees(order['totalPaise'] as int)} was paid online by the customer.',
                ),
                SectionCard(
                  title: 'Deliver to',
                  icon: Icons.person_pin_circle_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          InitialsAvatar(customer['name'] as String, radius: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(customer['name'] as String, style: theme.textTheme.titleLarge),
                                Text(
                                  mobileDisplay(customer['mobile'] as String),
                                  style: TextStyle(color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.place_rounded, color: scheme.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${address['house']}, ${address['street']}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, height: 1.3),
                                  ),
                                  if ((address['landmark'] as String?)?.isNotEmpty ?? false)
                                    Text('Near ${address['landmark']}', style: const TextStyle(height: 1.3)),
                                  Text(
                                    '${address['city']} ${address['pincode']}',
                                    style: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => callNumber(context, customer['mobile'] as String),
                              icon: const Icon(Icons.call_rounded),
                              label: const Text('Call'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () => openMap(
                                context,
                                lat: (address['lat'] as num?)?.toDouble(),
                                lng: (address['lng'] as num?)?.toDouble(),
                                query: addressLine(address),
                              ),
                              icon: const Icon(Icons.navigation_rounded),
                              label: const Text('Open in Maps'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              SectionCard(
                title: 'Items to hand over · ${itemsLabel(items.length)}',
                icon: Icons.inventory_2_outlined,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: customer == null
                            ? null
                            : () => setState(() => _checked.contains(i) ? _checked.remove(i) : _checked.add(i)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              if (customer != null) ...[
                                Icon(
                                  _checked.contains(i)
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  color: _checked.contains(i) ? colors.success : scheme.outline,
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${items[i]['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(
                                      '${items[i]['unit']}',
                                      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '× ${items[i]['qty']}',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SectionCard(
                title: 'Pick up from',
                icon: Icons.storefront_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order['store']['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (order['store']['address'] != null)
                      Text('${order['store']['address']}', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
