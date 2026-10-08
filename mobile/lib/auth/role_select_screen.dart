import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'mobile_screen.dart';

/// First screen: one app, a separate view for each role after login (A13).
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.brand, Color.lerp(AppTheme.brand, const Color(0xFF0B5D8C), 0.55)!],
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: SafeArea(
                bottom: false,
                child: PageBody(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.storefront_rounded, size: 36, color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'MK Market',
                        style: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Groceries from your nearest store,\ndelivered to your door.',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: PageBody(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('How are you using MK Market?', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 14),
                  const _RoleCard(
                    role: Role.user,
                    icon: Icons.shopping_basket_rounded,
                    subtitle: 'Search products, pay and track your order',
                    highlighted: true,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'MK Market staff',
                          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _RoleCard(
                    role: Role.storeManager,
                    icon: Icons.store_rounded,
                    subtitle: 'Receive orders and assign delivery',
                  ),
                  const SizedBox(height: 10),
                  const _RoleCard(
                    role: Role.deliveryBoy,
                    icon: Icons.delivery_dining_rounded,
                    subtitle: 'Deliver orders and confirm with OTP',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.icon, required this.subtitle, this.highlighted = false});

  final Role role;
  final IconData icon;
  final String subtitle;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: highlighted ? scheme.primaryContainer.withValues(alpha: 0.55) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: BorderSide(color: highlighted ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MobileScreen(role: role))),
        child: Padding(
          padding: EdgeInsets.all(highlighted ? 20 : 16),
          child: Row(
            children: [
              Container(
                width: highlighted ? 56 : 48,
                height: highlighted ? 56 : 48,
                decoration: BoxDecoration(
                  color: highlighted ? scheme.primary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: highlighted ? scheme.onPrimary : scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: highlighted ? 18 : 16),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 16, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
