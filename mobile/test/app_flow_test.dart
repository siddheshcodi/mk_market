import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mk_market/core/api_client.dart';
import 'package:mk_market/core/session.dart';
import 'package:mk_market/core/theme.dart';
import 'package:mk_market/customer/cart.dart';
import 'package:mk_market/customer/order_details_screen.dart';
import 'package:mk_market/delivery/delivery_otp_screen.dart';
import 'package:mk_market/main.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

const milk = {'id': 'p1', 'name': 'Milk 1L', 'unit': '1 L', 'pricePaise': 6800, 'imageUrl': null};

Widget appWith(FakeApi api, Session session) => MultiProvider(
  providers: [
    Provider<ApiClient>.value(value: api),
    ChangeNotifierProvider.value(value: session),
    ChangeNotifierProvider(create: (_) => Cart()),
  ],
  child: const MkMarketApp(),
);

Future<Session> loggedInCustomer(FakeApi api, MemoryTokenStore tokens) async {
  final session = Session(api, tokens);
  await tokens.saveLogin('access', 'refresh', 'USER', {'id': 'u1', 'mobile': '9876543210', 'role': 'USER'});
  await session.restore();
  return session;
}

void main() {
  setUp(() {
    // Phone-sized screen.
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first.physicalSize = const Size(1080, 2400);
  });

  testWidgets('customer logs in with mobile number and OTP (US-01)', (tester) async {
    final tokens = MemoryTokenStore();
    final api = FakeApi((method, path, body, query) {
      if (path == '/auth/otp/request') return {'requestId': 'r1', 'resendAfterSec': 30, 'expiresInSec': 300};
      if (path == '/auth/otp/verify') {
        if ((body as Map)['otp'] != '123456') {
          throw apiError(400, 'OTP_INVALID', 'Incorrect OTP. Please check and try again, or tap Resend.');
        }
        return {
          'accessToken': 'a',
          'refreshToken': 'r',
          'user': {'id': 'u1', 'mobile': '9876543210', 'role': 'USER'},
        };
      }
      throw StateError('unexpected $method $path');
    }, tokens);
    final session = Session(api, tokens);
    await session.restore();
    await tester.pumpWidget(appWith(api, session));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Customer'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.text('Get OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid 10-digit mobile number'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.tap(find.text('Get OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Sent to +91 9876543210'), findsOneWidget);
    expect(find.text('Resend OTP in 30s'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.pumpAndSettle();
    expect(find.text('Incorrect OTP. Please check and try again, or tap Resend.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();
    expect(find.text('Search for products by name'), findsOneWidget);
    expect(session.role, Role.user);
  });

  testWidgets('customer searches, picks, gives an address, pays and gets an order ID (US-02 to US-04)', (tester) async {
    final tokens = MemoryTokenStore();
    Object? checkoutBody;
    final api = FakeApi((method, path, body, query) {
      switch ((method, path)) {
        case ('GET', '/products/search'):
          return {
            'items': query!['q'] == 'milk' ? [milk] : [],
            'page': 1,
            'hasMore': false,
          };
        case ('POST', '/checkout'):
          checkoutBody = body;
          return {
            'checkoutId': 'c1',
            'storeId': 's1',
            'roadDistanceMeters': 2500,
            'items': [
              {
                'productId': 'p1',
                'name': 'Milk 1L',
                'unit': '1 L',
                'unitPricePaise': 6800,
                'qty': 2,
                'lineTotalPaise': 13600,
              },
            ],
            'totalPaise': 13600,
            'currency': 'INR',
            'expiresAt': DateTime.now().add(const Duration(minutes: 15)).toUtc().toIso8601String(),
          };
        case ('POST', '/checkout/c1/payment'):
          return {'gatewayOrderId': 'order_1', 'gatewayKey': 'rzp_test', 'amountPaise': 13600, 'currency': 'INR'};
        case ('POST', '/dev/payments/complete'):
          return {'gatewayOrderId': 'order_1', 'gatewayPaymentId': 'pay_1', 'signature': 'sig'};
        case ('POST', '/checkout/c1/payment/confirm'):
          return {'orderId': 'o1', 'displayOrderId': 'MK261008ABC234', 'status': 'PLACED'};
      }
      throw StateError('unexpected $method $path');
    }, tokens);
    final session = await loggedInCustomer(api, tokens);
    await tester.pumpWidget(appWith(api, session));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('No products found'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'milk');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
    expect(find.text('₹136'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // BR-07: every missing field is highlighted at once.
    await tester.ensureVisible(find.text('Continue to payment'));
    await tester.tap(find.text('Continue to payment'));
    await tester.pumpAndSettle();
    expect(find.text('Full name is required'), findsOneWidget);
    expect(find.text('City is required'), findsOneWidget);
    expect(find.text('Enter a valid 6-digit pincode'), findsOneWidget);

    Future<void> fill(String label, String value) => tester.enterText(find.widgetWithText(TextFormField, label), value);
    await fill('Full name', 'Asha Kulkarni');
    await fill('House / flat number', 'Flat 12');
    await fill('Street / area', 'Paud Road');
    await fill('City', 'Pune');
    await fill('Pincode', '411038');
    await tester.ensureVisible(find.text('Continue to payment'));
    await tester.tap(find.text('Continue to payment'));
    // The payment screen shows a 1-second countdown, so it never "settles".
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect((checkoutBody as Map)['items'], [
      {'productId': 'p1', 'qty': 2},
    ]);

    expect(find.text('Pay ₹136'), findsOneWidget);
    expect(find.text('2.5 km away by road'), findsOneWidget);
    await tester.tap(find.text('Pay ₹136'));
    // The Pay button shows a spinner while the payment sheet is open, so wait a fixed time.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Pay successfully'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Thank you! Your order is placed.'), findsOneWidget);
    expect(find.text('₹136 paid in advance.'), findsOneWidget);
    expect(find.text('MK261008ABC234'), findsOneWidget);
  });

  testWidgets('no store within 4 km blocks payment (US-03)', (tester) async {
    final tokens = MemoryTokenStore();
    final api = FakeApi((method, path, body, query) {
      if (path == '/products/search') {
        return {
          'items': [milk],
          'page': 1,
          'hasMore': false,
        };
      }
      if (path == '/checkout') {
        throw apiError(422, 'NO_STORE_AVAILABLE', 'Currently no store is available in your area');
      }
      throw StateError('unexpected $method $path');
    }, tokens);
    final session = await loggedInCustomer(api, tokens);
    await tester.pumpWidget(appWith(api, session));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'milk');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    Future<void> fill(String label, String value) => tester.enterText(find.widgetWithText(TextFormField, label), value);
    await fill('Full name', 'Asha');
    await fill('House / flat number', '1');
    await fill('Street / area', 'Marine Drive');
    await fill('City', 'Mumbai');
    await fill('Pincode', '400001');
    await tester.ensureVisible(find.text('Continue to payment'));
    await tester.tap(find.text('Continue to payment'));
    await tester.pumpAndSettle();

    expect(find.text('Currently no store is available in your area'), findsOneWidget);
    expect(find.textContaining('Pay '), findsNothing);
  });

  testWidgets('delivery boy enters a wrong then the correct OTP (US-11)', (tester) async {
    final semantics = tester.ensureSemantics();
    final tokens = MemoryTokenStore();
    var attemptsLeft = 3;
    final keys = <String>[];
    final api = FakeApi((method, path, body, query) {
      if (method == 'GET') {
        return {
          'deliveryOtp': {
            'status': 'ACTIVE',
            'expiresAt': DateTime.now().add(const Duration(minutes: 10)).toUtc().toIso8601String(),
            'attemptsLeft': attemptsLeft,
            'resendsLeft': 2,
            'nextResendAt': DateTime.now().add(const Duration(seconds: 30)).toUtc().toIso8601String(),
          },
        };
      }
      if (path.endsWith('/verify')) {
        keys.add('k');
        if ((body as Map)['otp'] != '4321') {
          attemptsLeft--;
          throw apiError(400, 'OTP_INCORRECT', 'Incorrect OTP. $attemptsLeft attempts left.', {
            'attemptsLeft': attemptsLeft,
          });
        }
        return {'result': 'DELIVERED', 'orderId': 'o1'};
      }
      throw StateError('unexpected $method $path');
    }, tokens);
    final session = Session(api, tokens);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider.value(value: session),
        ],
        child: const MaterialApp(
          home: DeliveryOtpScreen(orderId: 'o1', displayOrderId: 'MK261008ABC234'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel('Attempts left: 3'), findsOneWidget);
    expect(
      find.text('Resend OTP in 30s').evaluate().isNotEmpty || find.text('Resend OTP in 29s').evaluate().isNotEmpty,
      isTrue,
    );

    await tester.enterText(find.byType(TextField), '1111');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Incorrect OTP. 2 attempts left.'), findsOneWidget);
    expect(find.bySemanticsLabel('Attempts left: 2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4321');
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Order delivered'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('unregistered number cannot log in as store manager (US-06)', (tester) async {
    final tokens = MemoryTokenStore();
    final api = FakeApi((method, path, body, query) {
      if (path == '/auth/otp/request') {
        throw apiError(403, 'NUMBER_NOT_REGISTERED', 'This number is not registered');
      }
      throw StateError('unexpected $method $path');
    }, tokens);
    final session = Session(api, tokens);
    await session.restore();
    await tester.pumpWidget(appWith(api, session));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Store manager'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9123456789');
    await tester.tap(find.text('Get OTP'));
    await tester.pumpAndSettle();

    expect(find.text('This number is not registered'), findsOneWidget);
    expect(find.text('Verify your number'), findsNothing);
  });

  testWidgets('customer sees the share-OTP prompt and no cancel option (US-05, U-T18)', (tester) async {
    final tokens = MemoryTokenStore();
    final api = FakeApi((method, path, body, query) {
      if (path == '/orders/o1') {
        return {
          'orderId': 'o1',
          'displayOrderId': 'MK261008ABC234',
          'status': 'OUT_FOR_DELIVERY',
          'placedAt': '2026-10-08T05:00:00Z',
          'totalPaise': 13600,
          'storeName': 'MK Market - Kothrud',
          'deliveryOtpActive': true,
          'items': [
            {'name': 'Milk 1L', 'unit': '1 L', 'qty': 2, 'unitPricePaise': 6800, 'lineTotalPaise': 13600},
          ],
          'address': {'name': 'Asha', 'house': 'Flat 12', 'street': 'Paud Road', 'city': 'Pune', 'pincode': '411038'},
          'timeline': [
            {'status': 'PLACED', 'at': '2026-10-08T05:00:00Z'},
            {'status': 'OUT_FOR_DELIVERY', 'at': '2026-10-08T05:10:00Z'},
          ],
        };
      }
      throw StateError('unexpected $method $path');
    }, tokens);
    final session = await loggedInCustomer(api, tokens);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider.value(value: session),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const OrderDetailsScreen(orderId: 'o1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your order is at your door'), findsOneWidget);
    expect(find.text('On the way for delivery'), findsOneWidget);
    expect(find.textContaining(RegExp('cancel', caseSensitive: false)), findsNothing);
  });

  testWidgets('store manager assigns a delivery boy in one step (US-07, US-08)', (tester) async {
    final tokens = MemoryTokenStore();
    Object? dispatchBody;
    var dispatched = false;
    final api = FakeApi((method, path, body, query) {
      switch ((method, path)) {
        case ('GET', '/store/orders'):
          final placed = query!['status'] == 'PLACED' && !dispatched;
          return {
            'serverTime': DateTime.now().toUtc().toIso8601String(),
            'items': [
              if (placed)
                {
                  'orderId': 'o1',
                  'displayOrderId': 'MK261008ABC234',
                  'status': 'PLACED',
                  'placedAt': DateTime.now().subtract(const Duration(minutes: 12)).toUtc().toIso8601String(),
                  'itemCount': 2,
                  'totalPaise': 13600,
                  'area': 'Paud Road',
                  'pincode': '411038',
                },
            ],
            'page': 1,
            'hasMore': false,
          };
        case ('GET', '/store/delivery-boys'):
          return {
            'items': [
              {'id': 'd1', 'code': 'DB001', 'name': 'Ravi Patil', 'mobile': '9000000001', 'activeOrders': 1},
              {'id': 'd2', 'code': 'DB002', 'name': 'Sunil More', 'mobile': '9000000002', 'activeOrders': 0},
            ],
          };
        case ('POST', '/store/orders/o1/dispatch'):
          dispatchBody = body;
          dispatched = true;
          return {'orderId': 'o1', 'status': 'OUT_FOR_DELIVERY'};
      }
      throw StateError('unexpected $method $path');
    }, tokens);
    final session = Session(api, tokens);
    await tokens.saveLogin('a', 'r', 'STORE_MANAGER', {'id': 'm1', 'name': 'Meera', 'storeName': 'MK Market - Kothrud'});
    await session.restore();
    await tester.pumpWidget(appWith(api, session));
    await tester.pumpAndSettle();

    // D4: the placed time and how long the order has waited are on the card. No reject option (FR-S-06).
    expect(find.text('MK261008ABC234'), findsOneWidget);
    expect(find.text('Waiting 12 min'), findsOneWidget);
    expect(find.textContaining(RegExp('reject', caseSensitive: false)), findsNothing);

    await tester.tap(find.text('Assign'));
    await tester.pumpAndSettle();
    expect(find.text('Least busy'), findsOneWidget);
    await tester.tap(find.text('Sunil More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm – Send for delivery'));
    await tester.pumpAndSettle();

    expect(dispatchBody, {'deliveryBoyId': 'd2'});
    expect(find.text('MK261008ABC234 sent for delivery'), findsOneWidget);
    expect(find.text('No new orders'), findsOneWidget);
  });
}
