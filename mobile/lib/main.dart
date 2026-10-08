import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/role_select_screen.dart';
import 'config.dart';
import 'core/api_client.dart';
import 'core/session.dart';
import 'core/theme.dart';
import 'core/token_store.dart';
import 'customer/cart.dart';
import 'customer/customer_home.dart';
import 'delivery/delivery_orders_screen.dart';
import 'store/store_inbox_screen.dart';

final _navigator = GlobalKey<NavigatorState>();

void main() {
  final tokens = TokenStore();
  final api = ApiClient(AppConfig.apiUrl, tokens);
  final session = Session(api, tokens)..restore();
  // On login, logout or an expired session, close any open screens so the right home is shown.
  Role? lastRole;
  session.addListener(() {
    if (session.role != lastRole) {
      lastRole = session.role;
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
  });
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: api),
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider(create: (_) => Cart()),
      ],
      child: const MkMarketApp(),
    ),
  );
}

class MkMarketApp extends StatelessWidget {
  const MkMarketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MK Market',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const _Home(),
    );
  }
}

/// Shows the login flow, or the module for the logged-in role (requirement.md §2).
class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    if (session.restoring) return const _Splash();
    // A new key per role resets the navigation stack on login and logout.
    return KeyedSubtree(
      key: ValueKey(session.role),
      child: switch (session.role) {
        null => const RoleSelectScreen(),
        Role.user => const CustomerHome(),
        Role.storeManager => const StoreInboxScreen(),
        Role.deliveryBoy => const DeliveryOrdersScreen(),
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppTheme.brand,
    body: Center(child: Icon(Icons.storefront_rounded, size: 72, color: Colors.white)),
  );
}
