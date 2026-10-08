import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/order_status.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'assign_sheet.dart';
import 'store_widgets.dart';

/// FR-S-04, FR-S-05: order details with the placed time, and the one-step assign action.
/// There is no reject or cancel option (FR-S-06).
class StoreOrderDetailsScreen extends StatefulWidget {
  const StoreOrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<StoreOrderDetailsScreen> createState() => _StoreOrderDetailsScreenState();
}

class _StoreOrderDetailsScreenState extends State<StoreOrderDetailsScreen> with Polling {
  Map<String, dynamic>? _order;
  Object? _error;

  /// Packing checklist; on this device only, to help the manager pack the order.
  final Set<int> _packed = {};

  @override
  void initState() {
    super.initState();
    _load();
    startPolling(const Duration(seconds: 15), _load);
  }

  Future<void> _load() async {
    try {
      final order = await context.read<ApiClient>().get('/store/orders/${widget.orderId}') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _order = order;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _order == null) setState(() => _error = e);
    }
  }

  Future<void> _assign() async {
    final order = _order!;
    final done = await showAssignSheet(
      context,
      orderId: widget.orderId,
      displayOrderId: order['displayOrderId'] as String,
    );
    if (done && mounted) showSuccess(context, 'Order sent for delivery.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final placed = order != null && order['status'] == 'PLACED';
    final items = (order?['items'] as List?)?.length ?? 0;
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
          : RefreshIndicator(onRefresh: _load, child: _details(order)),
      bottomNavigationBar: placed
          ? BottomActionBar(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_packed.isNotEmpty && _packed.length < items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${_packed.length} of $items items packed',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ),
                  PrimaryButton(label: 'Assign delivery boy', icon: Icons.delivery_dining_rounded, onPressed: _assign),
                ],
              ),
            )
          : null,
    );
  }

  Widget _details(Map<String, dynamic> order) {
    final status = orderStatus(order['status'] as String);
    final placedAt = parseTime(order['placedAt'])!;
    final serverNow = parseTime(order['serverTime']) ?? DateTime.now();
    final customer = order['customer'] as Map<String, dynamic>;
    final address = order['address'] as Map<String, dynamic>;
    final items = (order['items'] as List).cast<Map<String, dynamic>>();
    final deliveryBoy = order['deliveryBoy'] as Map<String, dynamic>?;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // D4: "check order time" – the most prominent thing on the screen.
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: status.container(context),
                  borderRadius: BorderRadius.circular(AppTheme.radius + 4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'ORDER PLACED',
                          style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1, fontWeight: FontWeight.w800),
                        ),
                        const Spacer(),
                        StatusChip(status, short: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      friendlyDateTime(placedAt, serverNow),
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    if (status == OrderStatus.placed)
                      WaitBadge(placedAt: placedAt, now: serverNow, large: true)
                    else
                      Text(ago(placedAt, serverNow), style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (order['undeliveredReason'] != null)
                InfoBanner(
                  tone: Tone.error,
                  icon: Icons.assignment_return_rounded,
                  title: 'Returned to store – refund handled manually',
                  message: '${undeliveredReason(order['undeliveredReason'] as String)}.',
                ),
              SectionCard(
                title: 'Customer',
                icon: Icons.person_outline_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        InitialsAvatar(customer['name'] as String),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(customer['name'] as String, style: theme.textTheme.titleMedium),
                              Text(
                                mobileDisplay(customer['mobile'] as String),
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        // EX-10: the store calls the customer, e.g. when an item is out of stock.
                        IconButton.filledTonal(
                          tooltip: 'Call customer',
                          icon: const Icon(Icons.call_rounded),
                          onPressed: () => callNumber(context, customer['mobile'] as String),
                        ),
                      ],
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.place_outlined, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(child: Text(addressLine(address), style: const TextStyle(height: 1.4))),
                        IconButton(
                          tooltip: 'View on map',
                          icon: const Icon(Icons.map_outlined),
                          onPressed: () => openMap(context, query: addressLine(address)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SectionCard(
                title: status == OrderStatus.placed ? 'Packing list · ${itemsLabel(items.length)}' : 'Items',
                icon: Icons.inventory_2_outlined,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      _ItemRow(
                        item: items[i],
                        checkable: status == OrderStatus.placed,
                        checked: _packed.contains(i),
                        onToggle: () => setState(() => _packed.contains(i) ? _packed.remove(i) : _packed.add(i)),
                      ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider()),
                    Row(
                      children: [
                        Icon(Icons.verified_rounded, size: 18, color: colors.success),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text('Paid in advance', style: TextStyle(fontWeight: FontWeight.w800)),
                        ),
                        Text(
                          rupees(order['totalPaise'] as int),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Payment ref …${order['payment']['gatewayReference']}',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                      ),
                    ),
                  ],
                ),
              ),
              if (deliveryBoy != null)
                SectionCard(
                  title: 'Delivery boy',
                  icon: Icons.delivery_dining_outlined,
                  child: Row(
                    children: [
                      InitialsAvatar(deliveryBoy['name'] as String),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(deliveryBoy['name'] as String, style: theme.textTheme.titleMedium),
                            Text(
                              mobileDisplay(deliveryBoy['mobile'] as String),
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Call delivery boy',
                        icon: const Icon(Icons.call_rounded),
                        onPressed: () => callNumber(context, deliveryBoy['mobile'] as String),
                      ),
                    ],
                  ),
                ),
              SectionCard(
                title: 'Status',
                child: StatusProgress(timeline: parseTimeline(order['timeline']), current: status),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.checkable, required this.checked, required this.onToggle});

  final Map<String, dynamic> item;
  final bool checkable;
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (checkable) ...[
            Icon(
              checked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              color: checked ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 10),
          ],
          Container(
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
            child: Text('${item['qty']}×', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['name']}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    decoration: checked ? TextDecoration.lineThrough : null,
                    color: checked ? scheme.outline : null,
                  ),
                ),
                Text('${item['unit']}', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Text(rupees(item['lineTotalPaise'] as int)),
        ],
      ),
    );
    return checkable ? InkWell(borderRadius: BorderRadius.circular(8), onTap: onToggle, child: content) : content;
  }
}
