import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/order_status.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'assign_sheet.dart';
import 'store_order_details_screen.dart';
import 'store_widgets.dart';

/// FR-S-03: the store's orders in four tabs. No push notifications (A9), so tabs poll while open.
class StoreInboxScreen extends StatefulWidget {
  const StoreInboxScreen({super.key});

  @override
  State<StoreInboxScreen> createState() => _StoreInboxScreenState();
}

class _StoreInboxScreenState extends State<StoreInboxScreen> {
  final Map<String, int> _counts = {};

  void _setCount(String status, int count) {
    if (_counts[status] != count && mounted) setState(() => _counts[status] = count);
  }

  Tab _tab(String label, String status, {bool alert = false}) {
    final count = _counts[status];
    final scheme = Theme.of(context).colorScheme;
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count != null && count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: alert ? scheme.error : scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count >= 50 ? '50+' : '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: alert ? scheme.onError : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.store_rounded, color: theme.colorScheme.onPrimary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.profile['storeName'] as String? ?? 'Store',
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Store manager · ${session.profile['name'] ?? ''}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                if (await confirmLogout(context)) session.logout();
              },
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              _tab('New', 'PLACED', alert: true),
              _tab('On the way', 'OUT_FOR_DELIVERY'),
              _tab('Returned', 'UNDELIVERED'),
              _tab('Delivered', 'DELIVERED'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OrderList(
              status: 'PLACED',
              every: const Duration(seconds: 5),
              emptyTitle: 'No new orders',
              empty: 'New orders appear here automatically within a few seconds.',
              emptyIcon: Icons.inbox_rounded,
              onCount: _setCount,
            ),
            _OrderList(
              status: 'OUT_FOR_DELIVERY',
              every: const Duration(seconds: 15),
              emptyTitle: 'Nothing on the way',
              empty: 'Orders you send for delivery show here until they are delivered.',
              emptyIcon: Icons.delivery_dining_rounded,
              onCount: _setCount,
            ),
            _OrderList(
              status: 'UNDELIVERED',
              every: const Duration(seconds: 15),
              emptyTitle: 'No returned orders',
              empty: 'Orders that could not be delivered come back here.',
              emptyIcon: Icons.assignment_return_rounded,
              onCount: _setCount,
            ),
            _OrderList(
              status: 'DELIVERED',
              every: const Duration(seconds: 30),
              emptyTitle: 'No deliveries yet',
              empty: 'Orders delivered in the last 7 days show here.',
              emptyIcon: Icons.check_circle_rounded,
              onCount: _setCount,
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderList extends StatefulWidget {
  const _OrderList({
    required this.status,
    required this.every,
    required this.emptyTitle,
    required this.empty,
    required this.emptyIcon,
    required this.onCount,
  });

  final String status;
  final Duration every;
  final String emptyTitle;
  final String empty;
  final IconData emptyIcon;
  final void Function(String status, int count) onCount;

  @override
  State<_OrderList> createState() => _OrderListState();
}

class _OrderListState extends State<_OrderList> with Polling, AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _orders;
  Object? _error;
  DateTime _serverNow = DateTime.now();
  final Set<String> _seen = {};
  final Set<String> _fresh = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    startPolling(widget.every, _load);
  }

  Future<void> _load() async {
    try {
      final res = await context.read<ApiClient>().get('/store/orders', query: {'status': widget.status, 'size': '50'});
      if (!mounted) return;
      final orders = (res['items'] as List).cast<Map<String, dynamic>>();
      final ids = orders.map((o) => o['orderId'] as String).toSet();
      // NFR-08: highlight orders that arrived since the last refresh.
      final arrived = _orders == null ? <String>{} : ids.difference(_seen);
      if (arrived.isNotEmpty && widget.status == 'PLACED') {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        showSuccess(context, arrived.length == 1 ? 'New order received' : '${arrived.length} new orders received');
      }
      setState(() {
        _orders = orders;
        _serverNow = parseTime(res['serverTime']) ?? DateTime.now();
        _fresh
          ..retainAll(ids)
          ..addAll(arrived);
        _seen
          ..clear()
          ..addAll(ids);
        _error = null;
      });
      widget.onCount(widget.status, orders.length);
    } catch (e) {
      if (mounted && _orders == null) setState(() => _error = e);
    }
  }

  Future<void> _open(Map<String, dynamic> order) async {
    setState(() => _fresh.remove(order['orderId']));
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoreOrderDetailsScreen(orderId: order['orderId'] as String)),
    );
    _load();
  }

  Future<void> _assign(Map<String, dynamic> order) async {
    final done = await showAssignSheet(
      context,
      orderId: order['orderId'] as String,
      displayOrderId: order['displayOrderId'] as String,
    );
    if (done && mounted) showSuccess(context, '${order['displayOrderId']} sent for delivery');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final orders = _orders;
    if (_error != null) {
      return ErrorView(
        error: _error!,
        onRetry: () {
          setState(() => _error = null);
          _load();
        },
      );
    }
    if (orders == null) return const SkeletonList(height: 130);
    return RefreshIndicator(
      onRefresh: _load,
      child: orders.isEmpty
          ? ListView(
              children: [EmptyView(icon: widget.emptyIcon, title: widget.emptyTitle, message: widget.empty)],
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: orders.length,
              itemBuilder: (context, i) => PageBody(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: _OrderCard(
                  order: orders[i],
                  serverNow: _serverNow,
                  fresh: _fresh.contains(orders[i]['orderId']),
                  onOpen: () => _open(orders[i]),
                  onAssign: () => _assign(orders[i]),
                ),
              ),
            ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.serverNow,
    required this.fresh,
    required this.onOpen,
    required this.onAssign,
  });

  final Map<String, dynamic> order;
  final DateTime serverNow;
  final bool fresh;
  final VoidCallback onOpen;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placed = parseTime(order['placedAt'])!;
    final status = orderStatus(order['status'] as String);
    final isNew = status == OrderStatus.placed;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(
          color: fresh ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.6),
          width: fresh ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (fresh) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        'NEW',
                        style: TextStyle(color: scheme.onPrimary, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      order['displayOrderId'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  if (isNew) WaitBadge(placedAt: placed, now: serverNow) else StatusChip(status, short: true),
                ],
              ),
              const SizedBox(height: 6),
              // D4: the store manager checks the order placed time.
              MetaLine(icon: Icons.schedule_rounded, text: 'Placed ${friendlyDateTime(placed, serverNow)}'),
              MetaLine(
                icon: Icons.shopping_bag_outlined,
                text: '${itemsLabel(order['itemCount'] as num)} · ${rupees(order['totalPaise'] as int)} paid',
              ),
              MetaLine(icon: Icons.place_outlined, text: '${order['area']}, ${order['pincode']}'),
              if (order['deliveryBoyName'] != null)
                MetaLine(icon: Icons.delivery_dining_outlined, text: order['deliveryBoyName'] as String, bold: true),
              if (order['undeliveredReason'] != null)
                MetaLine(
                  icon: Icons.assignment_return_outlined,
                  text: undeliveredReason(order['undeliveredReason'] as String),
                  color: scheme.error,
                  bold: true,
                ),
              if (isNew) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onOpen,
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        child: const Text('View details'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onAssign,
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                        icon: const Icon(Icons.delivery_dining_rounded, size: 20),
                        label: const Text('Assign'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
