import 'package:flutter/material.dart';

import 'format.dart';
import 'theme.dart';

/// Order status lifecycle (requirement.md §5.2).
enum OrderStatus { placed, outForDelivery, delivered, undelivered }

OrderStatus orderStatus(String value) => switch (value) {
  'PLACED' => OrderStatus.placed,
  'OUT_FOR_DELIVERY' => OrderStatus.outForDelivery,
  'DELIVERED' => OrderStatus.delivered,
  _ => OrderStatus.undelivered,
};

extension OrderStatusView on OrderStatus {
  String get label => switch (this) {
    OrderStatus.placed => 'Placed',
    OrderStatus.outForDelivery => 'On the way for delivery',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.undelivered => 'Undelivered',
  };

  /// Short label for chips and progress steps.
  String get shortLabel => switch (this) {
    OrderStatus.placed => 'Placed',
    OrderStatus.outForDelivery => 'On the way',
    OrderStatus.delivered => 'Delivered',
    OrderStatus.undelivered => 'Undelivered',
  };

  bool get isClosed => this == OrderStatus.delivered || this == OrderStatus.undelivered;

  IconData get icon => switch (this) {
    OrderStatus.placed => Icons.receipt_long_rounded,
    OrderStatus.outForDelivery => Icons.delivery_dining_rounded,
    OrderStatus.delivered => Icons.check_circle_rounded,
    OrderStatus.undelivered => Icons.assignment_return_rounded,
  };

  Color color(BuildContext context) {
    final colors = AppColors.of(context);
    return switch (this) {
      OrderStatus.placed => colors.info,
      OrderStatus.outForDelivery => colors.warning,
      OrderStatus.delivered => colors.success,
      OrderStatus.undelivered => Theme.of(context).colorScheme.error,
    };
  }

  Color container(BuildContext context) {
    final colors = AppColors.of(context);
    return switch (this) {
      OrderStatus.placed => colors.infoContainer,
      OrderStatus.outForDelivery => colors.warningContainer,
      OrderStatus.delivered => colors.successContainer,
      OrderStatus.undelivered => Theme.of(context).colorScheme.errorContainer,
    };
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.short = false});

  final OrderStatus status;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final color = status.color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: status.container(context), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            short ? status.shortLabel : status.label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Horizontal Placed → On the way → Delivered / Undelivered tracker, with the time of each step.
class StatusProgress extends StatelessWidget {
  const StatusProgress({super.key, required this.timeline, required this.current});

  final List<({OrderStatus status, DateTime at})> timeline;
  final OrderStatus current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = current == OrderStatus.undelivered ? OrderStatus.undelivered : OrderStatus.delivered;
    final steps = [OrderStatus.placed, OrderStatus.outForDelivery, last];
    final reachedIndex = steps.indexOf(current);

    Widget dot(int i) {
      final step = steps[i];
      final reached = i <= reachedIndex;
      final isCurrent = i == reachedIndex && !current.isClosed;
      final color = reached ? step.color(context) : scheme.outlineVariant;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: reached ? color : scheme.surface,
          border: Border.all(color: color, width: 2),
          boxShadow: isCurrent ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, spreadRadius: 2)] : null,
        ),
        child: Icon(step.icon, size: 18, color: reached ? Colors.white : scheme.outline),
      );
    }

    Widget line(int i) => Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: i < reachedIndex ? steps[i + 1].color(context) : scheme.outlineVariant,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    return Column(
      children: [
        Row(children: [dot(0), line(0), dot(1), line(1), dot(2)]),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Column(
                  crossAxisAlignment: switch (i) {
                    0 => CrossAxisAlignment.start,
                    2 => CrossAxisAlignment.end,
                    _ => CrossAxisAlignment.center,
                  },
                  children: [
                    Text(
                      steps[i].shortLabel,
                      style: TextStyle(
                        fontWeight: i <= reachedIndex ? FontWeight.w700 : FontWeight.w500,
                        color: i <= reachedIndex ? scheme.onSurface : scheme.outline,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _timeOf(steps[i]),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _timeOf(OrderStatus step) {
    final at = timeline.where((t) => t.status == step).firstOrNull?.at;
    return at == null ? ' ' : dateTime(at);
  }
}

List<({OrderStatus status, DateTime at})> parseTimeline(Object? raw) => [
  for (final t in (raw as List? ?? const []))
    (status: orderStatus(t['status'] as String), at: DateTime.parse(t['at'] as String).toLocal()),
];
