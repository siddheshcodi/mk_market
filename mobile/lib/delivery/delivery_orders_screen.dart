import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/order_status.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'delivery_order_details_screen.dart';

/// FR-D-02: orders assigned to me. Active polls while open (no push notifications, A9).
class DeliveryOrdersScreen extends StatefulWidget {
  const DeliveryOrdersScreen({super.key});

  @override
  State<DeliveryOrdersScreen> createState() => _DeliveryOrdersScreenState();
}

class _DeliveryOrdersScreenState extends State<DeliveryOrdersScreen> {
  int? _activeCount;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = session.profile['name'] as String? ?? 'there';
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              InitialsAvatar(name, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hi, $name', style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                    Text(
                      session.profile['storeName'] as String? ?? 'Delivery',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
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
            tabAlignment: TabAlignment.fill,
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              Tab(text: _activeCount == null || _activeCount == 0 ? 'Active' : 'Active ($_activeCount)'),
              const Tab(text: 'Completed'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OrderList(
              tab: 'ACTIVE',
              every: const Duration(seconds: 10),
              emptyTitle: 'No deliveries right now',
              empty: 'New orders from your store appear here automatically.',
              onCount: (n) {
                if (n != _activeCount) setState(() => _activeCount = n);
              },
            ),
            const _OrderList(
              tab: 'COMPLETED',
              every: Duration(seconds: 30),
              emptyTitle: 'Nothing completed yet',
              empty: 'Orders you closed in the last 7 days show here.',
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderList extends StatefulWidget {
  const _OrderList({required this.tab, required this.every, required this.emptyTitle, required this.empty, this.onCount});

  final String tab;
  final Duration every;
  final String emptyTitle;
  final String empty;
  final ValueChanged<int>? onCount;

  @override
  State<_OrderList> createState() => _OrderListState();
}

class _OrderListState extends State<_OrderList> with Polling, AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _orders;
  Object? _error;

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
      final res = await context.read<ApiClient>().get('/delivery/orders', query: {'tab': widget.tab, 'size': '50'});
      if (mounted) {
        final orders = (res['items'] as List).cast<Map<String, dynamic>>();
        setState(() {
          _orders = orders;
          _error = null;
        });
        widget.onCount?.call(orders.length);
      }
    } catch (e) {
      if (mounted && _orders == null) setState(() => _error = e);
    }
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
    if (orders == null) return const SkeletonList(height: 120);
    final active = widget.tab == 'ACTIVE';
    return RefreshIndicator(
      onRefresh: _load,
      child: orders.isEmpty
          ? ListView(
              children: [
                EmptyView(
                  icon: active ? Icons.two_wheeler_rounded : Icons.task_alt_rounded,
                  title: widget.emptyTitle,
                  message: widget.empty,
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: orders.length,
              itemBuilder: (context, i) => PageBody(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                child: active
                    ? _ActiveCard(order: orders[i], onReturn: _load)
                    : _CompletedCard(order: orders[i], onReturn: _load),
              ),
            ),
    );
  }
}

Future<void> _openOrder(BuildContext context, Map<String, dynamic> order, VoidCallback onReturn) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => DeliveryOrderDetailsScreen(orderId: order['orderId'] as String)),
  );
  onReturn();
}

class _ActiveCard extends StatelessWidget {
  const _ActiveCard({required this.order, required this.onReturn});

  final Map<String, dynamic> order;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final otpSent = order['deliveryOtpActive'] == true;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openOrder(context, order, onReturn),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InitialsAvatar(order['customerName'] as String),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['customerName'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                        ),
                        Text(
                          order['displayOrderId'] as String,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (otpSent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: colors.infoContainer, borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sms_rounded, size: 14, color: colors.onInfoContainer),
                          const SizedBox(width: 4),
                          Text(
                            'OTP sent',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.onInfoContainer),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.place_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${order['area']}, ${order['pincode']}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(itemsLabel(order['itemCount'] as num), style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 16),
                  Icon(Icons.schedule_rounded, size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Assigned ${friendlyDateTime(parseTime(order['assignedAt']))}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openOrder(context, order, onReturn),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                  icon: Icon(otpSent ? Icons.pin_rounded : Icons.arrow_forward_rounded, size: 20),
                  label: Text(otpSent ? 'Enter OTP' : 'Open delivery'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  const _CompletedCard({required this.order, required this.onReturn});

  final Map<String, dynamic> order;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = orderStatus(order['status'] as String);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openOrder(context, order, onReturn),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: status.container(context), borderRadius: BorderRadius.circular(12)),
                child: Icon(status.icon, color: status.color(context)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order['displayOrderId'] as String, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      '${order['area']}, ${order['pincode']} · ${itemsLabel(order['itemCount'] as num)}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                    Text(
                      'Closed ${friendlyDateTime(parseTime(order['closedAt']))}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
              StatusChip(status, short: true),
            ],
          ),
        ),
      ),
    );
  }
}
