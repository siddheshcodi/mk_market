import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/order_status.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'address_screen.dart';
import 'cart.dart';
import 'order_details_screen.dart';
import 'shop_widgets.dart';

const _popular = ['Milk', 'Bread', 'Rice', 'Eggs', 'Atta', 'Sugar', 'Oil', 'Tea'];

/// Searches made in this session, newest first.
final _recent = <String>[];

/// Customer home: search products by name and pick quantities (FR-U-03 to FR-U-05).
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.onOpenOrders});

  final VoidCallback? onOpenOrders;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with Polling {
  static const _pageSize = 20;

  final _query = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  List<Product>? _results;
  Object? _error;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _searchId = 0;
  Map<String, dynamic>? _activeOrder;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadActiveOrder();
    startPolling(const Duration(seconds: 30), _loadActiveOrder);
    orderPlaced.addListener(_loadActiveOrder);
  }

  @override
  void dispose() {
    orderPlaced.removeListener(_loadActiveOrder);
    _debounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// The newest order that isn't closed yet, shown as a tracking card above the search tips.
  Future<void> _loadActiveOrder() async {
    try {
      final res = await context.read<ApiClient>().get('/orders', query: {'size': '10'});
      final items = (res['items'] as List).cast<Map<String, dynamic>>();
      final active = items.where((o) => !orderStatus(o['status'] as String).isClosed).firstOrNull;
      if (mounted) setState(() => _activeOrder = active);
    } catch (_) {
      // Optional card; the search still works without it.
    }
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 400 && _hasMore && !_loadingMore && !_loading) _loadMore();
  }

  void _onChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _search);
  }

  void _searchFor(String text) {
    _query.text = text;
    _query.selection = TextSelection.collapsed(offset: text.length);
    FocusScope.of(context).unfocus();
    _search();
  }

  Future<void> _search() async {
    _debounce?.cancel();
    final q = _query.text.trim();
    if (q.length < 2) {
      setState(() {
        _searchId++;
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    final id = ++_searchId;
    setState(() => _loading = true);
    try {
      final res = await context.read<ApiClient>().get(
        '/products/search',
        query: {'q': q, 'page': '1', 'size': '$_pageSize'},
      );
      if (id != _searchId || !mounted) return;
      final items = [for (final p in res['items'] as List) Product.fromJson(p as Map<String, dynamic>)];
      setState(() {
        _results = items;
        _page = 1;
        _hasMore = res['hasMore'] == true;
        _error = null;
        if (items.isNotEmpty) {
          _recent
            ..removeWhere((r) => r.toLowerCase() == q.toLowerCase())
            ..insert(0, q);
          if (_recent.length > 6) _recent.removeLast();
        }
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } catch (e) {
      if (id == _searchId && mounted) setState(() => _error = e);
    } finally {
      if (id == _searchId && mounted) setState(() => _loading = false);
    }
  }

  /// Infinite scroll, 20 per page (spec §6.2).
  Future<void> _loadMore() async {
    final id = _searchId;
    setState(() => _loadingMore = true);
    try {
      final res = await context.read<ApiClient>().get(
        '/products/search',
        query: {'q': _query.text.trim(), 'page': '${_page + 1}', 'size': '$_pageSize'},
      );
      if (id != _searchId || !mounted) return;
      setState(() {
        _results = [..._results ?? [], for (final p in res['items'] as List) Product.fromJson(p as Map<String, dynamic>)];
        _page++;
        _hasMore = res['hasMore'] == true;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _openAccount() {
    final session = context.read<Session>();
    final mobile = session.profile['mobile'] as String? ?? '';
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: IconBadge(icon: Icons.person_rounded, size: 72)),
              const SizedBox(height: 12),
              Text('Logged in as', textAlign: TextAlign.center, style: Theme.of(sheet).textTheme.bodySmall),
              Text(mobileDisplay(mobile), textAlign: TextAlign.center, style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  widget.onOpenOrders?.call();
                },
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('My orders'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Theme.of(sheet).colorScheme.error),
                onPressed: () async {
                  Navigator.pop(sheet);
                  if (await confirmLogout(context) && mounted) {
                    context.read<Cart>().reset();
                    session.logout();
                  }
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageBody(
              maxWidth: 1100,
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MK Market', style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary)),
                        Text('What do you need today?', style: theme.textTheme.titleLarge),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Account',
                    onPressed: _openAccount,
                    icon: const Icon(Icons.person_outline_rounded),
                  ),
                ],
              ),
            ),
            PageBody(
              maxWidth: 1100,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _query,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'Search for products, e.g. milk',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: scheme.outlineVariant),
                  ),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : _query.text.isNotEmpty
                      ? IconButton(
                          tooltip: 'Clear',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _query.clear();
                            _search();
                          },
                        )
                      : null,
                ),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: cart.isEmpty ? const SizedBox(width: double.infinity) : _CartBar(cart: cart),
      ),
    );
  }

  Widget _body() {
    if (_error != null) return ErrorView(error: _error!, onRetry: _search);
    final results = _results;
    if (results == null) {
      if (_loading) return const SkeletonList(count: 4, height: 120);
      return _Idle(activeOrder: _activeOrder, onSearch: _searchFor, onOrderClosed: _loadActiveOrder);
    }
    if (results.isEmpty) {
      return ListView(
        children: [
          EmptyView(
            icon: Icons.search_off_rounded,
            title: 'No products found',
            message: 'Check the spelling or try a shorter name, like "milk" or "rice".',
            action: OutlinedButton(
              onPressed: () {
                _query.clear();
                _search();
              },
              child: const Text('Clear search'),
            ),
          ),
        ],
      );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.sizeOf(context).width > 1132 ? (MediaQuery.sizeOf(context).width - 1100) / 2 : 16,
            vertical: 8,
          ),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 230,
              mainAxisExtent: 262,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: results.length,
            itemBuilder: (context, i) => _ProductCard(product: results[i]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _loadingMore
                  ? const CircularProgressIndicator()
                  : _hasMore
                  ? const SizedBox(height: 24)
                  : Text(
                      results.length > 4 ? "That's everything for this search" : '',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown before the customer types: active order, quick searches and a hint.
class _Idle extends StatelessWidget {
  const _Idle({required this.activeOrder, required this.onSearch, required this.onOrderClosed});

  final Map<String, dynamic>? activeOrder;
  final ValueChanged<String> onSearch;
  final VoidCallback onOrderClosed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget chips(String title, IconData icon, List<String> words) => Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final w in words)
                ActionChip(
                  avatar: Icon(icon, size: 16, color: scheme.primary),
                  label: Text(w),
                  onPressed: () => onSearch(w),
                ),
            ],
          ),
        ],
      ),
    );

    return ListView(
      children: [
        PageBody(
          maxWidth: 1100,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (activeOrder != null) ...[
                _ActiveOrderCard(order: activeOrder!, onReturn: onOrderClosed),
                const SizedBox(height: 20),
              ],
              if (_recent.isNotEmpty) chips('Recent searches', Icons.history_rounded, _recent),
              chips('Popular right now', Icons.trending_up_rounded, _popular),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Row(
                  children: [
                    const IconBadge(icon: Icons.manage_search_rounded, size: 56),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Search for products by name', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(
                            'Pay online and get it from the nearest MK Market store. No delivery charges.',
                            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35),
                          ),
                        ],
                      ),
                    ),
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

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order, required this.onReturn});

  final Map<String, dynamic> order;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final status = orderStatus(order['status'] as String);
    final color = status.color(context);
    return Material(
      color: status.container(context),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
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
              CircleAvatar(backgroundColor: color, child: Icon(status.icon, color: Colors.white)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status == OrderStatus.placed ? 'Your order is placed' : 'Your order is on the way',
                      style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${order['displayOrderId']} · ${itemsLabel(order['itemCount'] as num)}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text('Track', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final qty = cart.qtyOf(product.id);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(color: qty > 0 ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: SizedBox(width: double.infinity, child: ProductImage(product: product))),
            const SizedBox(height: 10),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.2),
            ),
            const SizedBox(height: 2),
            Text(
              product.unit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(rupees(product.pricePaise), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                QtyStepper(qty: qty, compact: true, onChanged: (q) => cart.setQty(product, q)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating summary of the current selection. "Continue" goes to the address step.
class _CartBar extends StatelessWidget {
  const _CartBar({required this.cart});

  final Cart cart;

  void _continue(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddressScreen()));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: PageBody(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Material(
          color: scheme.primary,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _continue(context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      heightFactor: 1,
                      child: Tooltip(
                        message: 'View cart',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => showCartSheet(context, onContinue: () => _continue(context)),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Badge(
                                  label: Text('${cart.unitCount}'),
                                  backgroundColor: scheme.onPrimary,
                                  textColor: scheme.primary,
                                  child: Icon(Icons.shopping_bag_rounded, color: scheme.onPrimary),
                                ),
                                const SizedBox(width: 14),
                                Flexible(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        itemsLabel(cart.itemCount),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.85), fontSize: 12),
                                      ),
                                      Text(
                                        rupees(cart.totalPaise),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: scheme.onPrimary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_up_rounded, color: scheme.onPrimary.withValues(alpha: 0.85)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    'Continue',
                    style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, color: scheme.onPrimary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the customer review and change quantities before checkout.
void showCartSheet(BuildContext context, {required VoidCallback onContinue}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => Consumer<Cart>(
      builder: (sheet, cart, _) {
        if (cart.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(sheet).canPop()) Navigator.of(sheet).pop();
          });
        }
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('Your selection', style: Theme.of(sheet).textTheme.titleLarge),
                ),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const Divider(height: 20),
                    itemBuilder: (_, i) {
                      final line = cart.lines[i];
                      return Row(
                        children: [
                          ProductImage(product: line.product, size: 48, radius: 10),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.product.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(
                                  '${line.product.unit} · ${rupees(line.product.pricePaise)}',
                                  style: Theme.of(sheet).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          QtyStepper(
                            qty: line.qty,
                            compact: true,
                            onChanged: (q) => cart.setQty(line.product, q),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    children: [
                      ValueRow('Item total', rupees(cart.totalPaise)),
                      ValueRow('Delivery', 'FREE', valueColor: AppColors.of(sheet).success),
                      const SizedBox(height: 4),
                      Text(
                        'Final prices are confirmed by the store at checkout.',
                        style: Theme.of(sheet).textTheme.bodySmall?.copyWith(
                          color: Theme.of(sheet).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        label: 'Add delivery address',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () {
                          Navigator.pop(sheet);
                          onContinue();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
