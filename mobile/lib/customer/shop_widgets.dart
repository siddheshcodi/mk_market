import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'cart.dart';

/// Product photo, or a tinted icon picked from the name when the catalog has no image.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.product, this.size, this.radius = 12});

  final Product product;
  final double? size;
  final double radius;

  static const _palette = [
    (Color(0xFFE6F4EA), Color(0xFF1E7B45)),
    (Color(0xFFFFF1DB), Color(0xFFB0640A)),
    (Color(0xFFE5EEFD), Color(0xFF2659B8)),
    (Color(0xFFFCE7EC), Color(0xFFB0315A)),
    (Color(0xFFEFE8FB), Color(0xFF6B43B5)),
    (Color(0xFFE2F5F5), Color(0xFF16807F)),
  ];

  static IconData iconFor(String name) {
    final n = name.toLowerCase();
    bool has(List<String> words) => words.any(n.contains);
    if (has(['milk', 'curd', 'dahi', 'paneer', 'butter', 'ghee', 'cheese', 'lassi'])) return Icons.local_drink_rounded;
    if (has(['bread', 'bun', 'pav', 'cake', 'biscuit', 'cookie', 'rusk'])) return Icons.bakery_dining_rounded;
    if (has(['rice', 'dal', 'atta', 'flour', 'poha', 'rava', 'sooji', 'grain', 'wheat'])) return Icons.rice_bowl_rounded;
    if (has(['egg'])) return Icons.egg_rounded;
    if (has(['apple', 'banana', 'mango', 'fruit', 'orange', 'grape'])) return Icons.apple_rounded;
    if (has(['onion', 'potato', 'tomato', 'vegetable', 'veg', 'carrot', 'spinach'])) return Icons.eco_rounded;
    if (has(['tea', 'coffee', 'chai'])) return Icons.coffee_rounded;
    if (has(['oil', 'sugar', 'salt', 'masala', 'spice'])) return Icons.soup_kitchen_rounded;
    if (has(['soap', 'shampoo', 'detergent', 'clean', 'wash'])) return Icons.clean_hands_rounded;
    if (has(['juice', 'water', 'drink', 'cola', 'soda'])) return Icons.local_bar_rounded;
    if (has(['chips', 'snack', 'namkeen', 'chocolate'])) return Icons.cookie_rounded;
    return Icons.shopping_bag_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = _palette[product.name.hashCode.abs() % _palette.length];
    final placeholder = Container(
      width: size,
      height: size,
      color: dark ? fg.withValues(alpha: 0.18) : bg,
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, c) => Icon(
          iconFor(product.name),
          color: dark ? bg : fg,
          size: (c.biggest.shortestSide.isFinite ? c.biggest.shortestSide : 48) * 0.45,
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: product.imageUrl == null
          ? placeholder
          : Image.network(
              product.imageUrl!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

/// "Add" button that turns into a − qty + stepper (quantity 1 to 10, spec §6.3).
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.qty, required this.onChanged, this.compact = false});

  final int qty;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = compact ? 34.0 : 38.0;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
      child: qty == 0
          ? SizedBox(
              key: const ValueKey('add'),
              height: height,
              child: OutlinedButton(
                onPressed: () => onChanged(1),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(compact ? 72 : 84, height),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  foregroundColor: scheme.primary,
                  side: BorderSide(color: scheme.primary, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Add'),
              ),
            )
          : Container(
              key: const ValueKey('stepper'),
              height: height,
              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _btn(context, Icons.remove, 'Decrease quantity', () => onChanged(qty - 1)),
                  SizedBox(
                    width: 26,
                    child: Text(
                      '$qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                  _btn(
                    context,
                    Icons.add,
                    'Increase quantity',
                    qty >= Cart.maxQty ? null : () => onChanged(qty + 1),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _btn(BuildContext context, IconData icon, String tooltip, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: tooltip,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 20,
        child: SizedBox(
          width: compact ? 30 : 34,
          height: double.infinity,
          child: Icon(icon, size: 18, color: onTap == null ? scheme.onPrimary.withValues(alpha: 0.4) : scheme.onPrimary),
        ),
      ),
    );
  }
}

/// Cart → Address → Pay progress shown at the top of the checkout screens.
class CheckoutSteps extends StatelessWidget {
  const CheckoutSteps({super.key, required this.current});

  /// 1 = address, 2 = payment.
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = ['Cart', 'Address', 'Payment'];
    Widget step(int i) {
      final done = i < current;
      final active = i == current;
      final color = done || active ? scheme.primary : scheme.outlineVariant;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? color : (active ? scheme.primaryContainer : scheme.surface),
              border: Border.all(color: color, width: 2),
            ),
            alignment: Alignment.center,
            child: done
                ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
                : Text(
                    '${i + 1}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: active ? scheme.primary : scheme.outline),
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            labels[i],
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              color: active || done ? scheme.onSurface : scheme.outline,
            ),
          ),
        ],
      );
    }

    Widget bar(int i) => Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 18, left: 6, right: 6),
        color: i < current ? scheme.primary : scheme.outlineVariant,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
      child: Row(children: [step(0), bar(0), step(1), bar(1), step(2)]),
    );
  }
}

/// Small "₹ secure payment" style tag.
class TagPill extends StatelessWidget {
  const TagPill({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
