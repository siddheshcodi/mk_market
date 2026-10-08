import 'package:flutter/foundation.dart';

class Product {
  Product({required this.id, required this.name, required this.unit, required this.pricePaise, this.imageUrl});

  factory Product.fromJson(Map<String, dynamic> json) => Product(
    id: json['id'] as String,
    name: json['name'] as String,
    unit: json['unit'] as String,
    pricePaise: json['pricePaise'] as int,
    imageUrl: json['imageUrl'] as String?,
  );

  final String id;
  final String name;
  final String unit;
  final int pricePaise;
  final String? imageUrl;
}

/// The products picked for the current order (FR-U-05). Kept on the device only; the server
/// re-prices everything at checkout, so the total here is a preview.
class Cart extends ChangeNotifier {
  static const maxQty = 10;

  final Map<String, ({Product product, int qty})> _lines = {};

  /// The address used for the last order, offered again on the next one (spec §6.4, convenience only).
  Map<String, dynamic>? lastAddress;

  List<({Product product, int qty})> get lines => _lines.values.toList();
  int qtyOf(String productId) => _lines[productId]?.qty ?? 0;
  int get itemCount => _lines.length;
  int get unitCount => _lines.values.fold(0, (sum, l) => sum + l.qty);
  bool get isEmpty => _lines.isEmpty;
  int get totalPaise => _lines.values.fold(0, (sum, l) => sum + l.product.pricePaise * l.qty);

  void setQty(Product product, int qty) {
    if (qty <= 0) {
      _lines.remove(product.id);
    } else {
      _lines[product.id] = (product: product, qty: qty.clamp(1, maxQty));
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  /// On logout: forget the selection and the remembered address.
  void reset() {
    lastAddress = null;
    clear();
  }

  List<Map<String, Object>> toRequest() => [
    for (final l in _lines.values) {'productId': l.product.id, 'qty': l.qty},
  ];
}

/// Bumped when an order is placed, so the home screen refreshes its "active order" card.
final orderPlaced = ValueNotifier<int>(0);
