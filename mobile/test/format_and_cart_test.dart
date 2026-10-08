import 'package:flutter_test/flutter_test.dart';
import 'package:mk_market/core/format.dart';
import 'package:mk_market/customer/cart.dart';

void main() {
  test('money is shown in rupees from paise', () {
    expect(rupees(18100), '₹181');
    expect(rupees(6850), '₹68.50');
    expect(rupees(12345600), '₹1,23,456');
  });

  test('time since an order was placed', () {
    final now = DateTime(2026, 10, 8, 12);
    expect(ago(now.subtract(const Duration(seconds: 20)), now), 'just now');
    expect(ago(now.subtract(const Duration(minutes: 18)), now), '18 min ago');
    expect(ago(now.subtract(const Duration(hours: 3)), now), '3 h ago');
  });

  test('cart limits quantity to 10 per product and totals in paise', () {
    final cart = Cart();
    final milk = Product(id: 'm', name: 'Milk 1L', unit: '1 L', pricePaise: 6800);
    cart.setQty(milk, 12);
    expect(cart.qtyOf('m'), 10);
    cart.setQty(milk, 2);
    expect(cart.totalPaise, 13600);
    expect(cart.toRequest(), [
      {'productId': 'm', 'qty': 2},
    ]);
    cart.setQty(milk, 0);
    expect(cart.isEmpty, isTrue);
  });
}
