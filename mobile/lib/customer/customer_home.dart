import 'package:flutter/material.dart';

import 'my_orders_screen.dart';
import 'search_screen.dart';

/// Customer module shell: Shop and My orders tabs.
class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});

  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  int _tab = 0;
  // The orders tab is built the first time it is opened, then kept alive.
  bool _ordersOpened = false;

  void _select(int tab) => setState(() {
    _tab = tab;
    if (tab == 1) _ordersOpened = true;
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(
      index: _tab,
      children: [
        SearchScreen(onOpenOrders: () => _select(1)),
        _ordersOpened ? MyOrdersScreen(onStartShopping: () => _select(0)) : const SizedBox.shrink(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: _select,
      height: 68,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          selectedIcon: Icon(Icons.storefront_rounded),
          label: 'Shop',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: 'My orders',
        ),
      ],
    ),
  );
}
