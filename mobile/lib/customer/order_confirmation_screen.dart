import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'order_details_screen.dart';

/// FR-U-11: confirmation with the order ID, and what happens next.
class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key, required this.order, this.totalPaise, this.itemCount, this.address});

  final Map<String, dynamic> order;
  final int? totalPaise;
  final int? itemCount;
  final Map<String, dynamic>? address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final displayId = order['displayOrderId'] as String;
    final total = totalPaise ?? order['totalPaise'] as int?;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            PageBody(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.4, end: 1),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.elasticOut,
                      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                      child: Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: colors.successContainer),
                        child: Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.success),
                            child: const Icon(Icons.check_rounded, size: 52, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Thank you! Your order is placed.', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    total == null ? 'Paid in advance.' : '${rupees(total)} paid in advance.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ORDER ID', style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1, color: scheme.outline)),
                                const SizedBox(height: 2),
                                Text(
                                  displayId,
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1),
                                ),
                                if (itemCount != null)
                                  Text(itemsLabel(itemCount!), style: TextStyle(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy order ID',
                            icon: const Icon(Icons.copy_rounded),
                            onPressed: () => copyText(context, displayId, 'Order ID'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'What happens next',
                    child: Column(
                      children: [
                        _NextStep(
                          icon: Icons.storefront_rounded,
                          title: 'The nearest store packs your order',
                          subtitle: address == null ? null : 'Delivering to ${addressLine(address!)}',
                        ),
                        const _NextStep(icon: Icons.delivery_dining_rounded, title: 'A delivery person brings it to you'),
                        const _NextStep(
                          icon: Icons.sms_rounded,
                          title: 'Share the OTP sent to your phone',
                          subtitle: 'Give the 4-digit code only to the delivery person at your door.',
                          last: true,
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
      bottomNavigationBar: BottomActionBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PrimaryButton(
              label: 'Track order',
              icon: Icons.near_me_rounded,
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => OrderDetailsScreen(orderId: order['orderId'] as String)),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Continue shopping')),
          ],
        ),
      ),
    );
  }
}

class _NextStep extends StatelessWidget {
  const _NextStep({required this.icon, required this.title, this.subtitle, this.last = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              CircleAvatar(radius: 18, backgroundColor: scheme.primaryContainer, child: Icon(icon, size: 18, color: scheme.primary)),
              if (!last) Expanded(child: Container(width: 2, color: scheme.outlineVariant)),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 8, bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.35)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
