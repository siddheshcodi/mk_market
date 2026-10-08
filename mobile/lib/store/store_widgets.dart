import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/theme.dart';

/// "Waiting 18 min" badge for a Placed order, coloured by how long it has waited (D4).
class WaitBadge extends StatelessWidget {
  const WaitBadge({super.key, required this.placedAt, required this.now, this.large = false});

  final DateTime placedAt;
  final DateTime now;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final minutes = now.difference(placedAt).inMinutes;
    final (bg, fg) = minutes < 10
        ? (colors.successContainer, colors.onSuccessContainer)
        : minutes < 30
        ? (colors.warningContainer, colors.onWarningContainer)
        : (scheme.errorContainer, scheme.onErrorContainer);
    final waited = ago(placedAt, now);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 9, vertical: large ? 6 : 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_bottom_rounded, size: large ? 16 : 13, color: fg),
          const SizedBox(width: 4),
          Text(
            waited == 'just now' ? 'Just now' : 'Waiting ${waited.replaceAll(' ago', '')}',
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: large ? 13.5 : 12),
          ),
        ],
      ),
    );
  }
}

/// Icon + text line used on order cards.
class MetaLine extends StatelessWidget {
  const MetaLine({super.key, required this.icon, required this.text, this.color, this.bold = false});

  final IconData icon;
  final String text;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c, fontSize: 13.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

String undeliveredReason(String code) => switch (code) {
  'OTP_ATTEMPTS_EXCEEDED' => 'Delivery failed after 3 incorrect OTPs',
  _ => code.replaceAll('_', ' ').toLowerCase(),
};
