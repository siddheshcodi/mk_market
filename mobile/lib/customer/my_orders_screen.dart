import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/order_status.dart';
import '../core/widgets.dart';
import 'cart.dart';
import 'order_details_screen.dart';

/// FR-U-12: my orders with their current status, newest first. Orders still in progress are grouped on top.
class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key, this.onStartShopping});

  final VoidCallback? onStartShopping;

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> with Polling {
  List<Map<String, dynamic>>? _orders;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
    startPolling(const Duration(seconds: 15), _load);
    orderPlaced.addListener(_load);
  }

  @override
  void dispose() {
    orderPlaced.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<ApiClient>().get('/orders', query: {'size': '50'});
      if (mounted) {
        setState(() {
          _orders = (res['items'] as List).cast<Map<String, dynamic>>();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _orders == null) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orders;
    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: _error != null
          ? ErrorView(
              error: _error!,
              onRetry: () {
                setState(() => _error = null);
                _load();
              },
            )
          : orders == null
          ? const SkeletonList()
          : orders.isEmpty
          ? EmptyView(
              icon: Icons.receipt_long_rounded,
              title: 'No orders yet',
              message: "You haven't placed any orders yet. Your orders and their status will show here.",
              action: widget.onStartShopping == null
                  ? null
                  : FilledButton.icon(
                      onPressed: widget.onStartShopping,
                      icon: const Icon(Icons.storefront_rounded),
                      label: const Text('Start shopping'),
                    ),
            )
          : RefreshIndicator(onRefresh: _load, child: _list(orders)),
    );
  }

  Widget _list(List<Map<String, dynamic>> orders) {
    final active = orders.where((o) => !orderStatus(o['status'] as String).isClosed).toList();
    final past = orders.where((o) => orderStatus(o['status'] as String).isClosed).toList();
    Widget header(String text) => PageBody(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (active.isNotEmpty) ...[header('In progress'), for (final o in active) _OrderCard(order: o, onReturn: _load)],
        if (past.isNotEmpty) ...[header('Past orders'), for (final o in past) _OrderCard(order: o, onReturn: _load)],
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onReturn});

  final Map<String, dynamic> order;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = orderStatus(order['status'] as String);
    return PageBody(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => OrderDetailsScreen(orderId: order['orderId'] as String)),
            );
            onReturn();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: status.container(context), borderRadius: BorderRadius.circular(14)),
                  child: Icon(status.icon, color: status.color(context)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              order['displayOrderId'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                          Text(rupees(order['totalPaise'] as int), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${friendlyDateTime(parseTime(order['placedAt']))} · ${itemsLabel(order['itemCount'] as num)}',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      StatusChip(status),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
