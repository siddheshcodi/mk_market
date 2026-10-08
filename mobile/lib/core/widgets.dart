import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';
import 'theme.dart';

/// Keeps content readable on wide screens (web) while filling phones.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.maxWidth = 640});

  final Widget child;
  final EdgeInsets padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    // Only as tall as the content, so it also works inside bottom bars.
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      // Fill the available width so content lines up with the screen edges.
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------------------------
// Feedback

String errorMessage(Object error) =>
    error is ApiException ? error.message : 'Something went wrong. Please try again.';

void _snack(BuildContext context, String message, IconData icon, Color? background) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: background,
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

void showError(BuildContext context, Object error) =>
    _snack(context, errorMessage(error), Icons.error_outline_rounded, Theme.of(context).colorScheme.error);

void showInfo(BuildContext context, String message) => _snack(context, message, Icons.info_outline_rounded, null);

void showSuccess(BuildContext context, String message) =>
    _snack(context, message, Icons.check_circle_rounded, AppColors.of(context).success);

enum Tone { info, success, warning, error, neutral }

/// Inline message box: what happened and what to do next (NFR-12).
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.tone,
    required this.title,
    this.message,
    this.icon,
    this.action,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  final Tone tone;
  final String title;
  final String? message;
  final IconData? icon;
  final Widget? action;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final (bg, fg, defaultIcon) = switch (tone) {
      Tone.info => (colors.infoContainer, colors.onInfoContainer, Icons.info_outline_rounded),
      Tone.success => (colors.successContainer, colors.onSuccessContainer, Icons.check_circle_outline_rounded),
      Tone.warning => (colors.warningContainer, colors.onWarningContainer, Icons.warning_amber_rounded),
      Tone.error => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline_rounded),
      Tone.neutral => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant, Icons.info_outline_rounded),
    };
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, color: fg, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14.5)),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: TextStyle(color: fg, fontSize: 13.5, height: 1.35)),
                ],
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Big icon in a soft circle, used by empty, error and result states.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.background, this.size = 88});

  final IconData icon;
  final Color? color;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: background ?? scheme.primaryContainer.withValues(alpha: 0.6)),
      child: Icon(icon, size: size * 0.48, color: color ?? scheme.primary),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final offline = error is ApiException && (error as ApiException).code == 'NETWORK';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(
              icon: offline ? Icons.wifi_off_rounded : Icons.cloud_off_rounded,
              color: scheme.error,
              background: scheme.errorContainer.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 20),
            Text(
              offline ? "You're offline" : "Couldn't load this",
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.message, this.title, this.action});

  final IconData icon;
  final String? title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon: icon),
            const SizedBox(height: 20),
            if (title != null) ...[
              Text(title!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: title == null
                  ? Theme.of(context).textTheme.titleMedium
                  : TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Grey placeholder cards shown while a list loads.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 5, this.height = 104});

  final int count;
  final double height;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.count,
        itemBuilder: (_, _) => PageBody(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Layout pieces

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[Icon(icon, size: 18, color: scheme.primary), const SizedBox(width: 8)],
                  Expanded(
                    child: Text(
                      title!.toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Label on the left, value on the right; used for bills and item lists.
class ValueRow extends StatelessWidget {
  const ValueRow(this.label, this.value, {super.key, this.bold = false, this.valueColor, this.subtitle});

  final String label;
  final String value;
  final String? subtitle;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 16 : 14.5);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: style),
                if (subtitle != null)
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: style.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}

/// Small centred icon + text hint that wraps on narrow screens.
class HintLine extends StatelessWidget {
  const HintLine({super.key, required this.icon, required this.text, this.color, this.fontSize = 13});

  final IconData icon;
  final String text;
  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: fontSize + 3, color: c),
        const SizedBox(width: 6),
        Flexible(child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: c, fontSize: fontSize))),
      ],
    );
  }
}

/// Sticky area at the bottom of a screen for its main action.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: PageBody(padding: const EdgeInsets.fromLTRB(16, 12, 16, 12), child: child),
      ),
    );
  }
}

/// Full-width main button with a loading state.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.busy = false, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: busy
            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    ),
  );
}

class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.radius = 22});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : parts.take(2).map((p) => p[0].toUpperCase()).join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        initials,
        style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: radius * 0.7),
      ),
    );
  }
}

/// Round action with a caption, e.g. Call / Navigate.
class CircleAction extends StatelessWidget {
  const CircleAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the backend runs in local mode, so testers know where OTPs are.
class LocalModeBanner extends StatelessWidget {
  const LocalModeBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) =>
      InfoBanner(tone: Tone.warning, icon: Icons.science_outlined, title: 'Test mode', message: message);
}

// ---------------------------------------------------------------------------------------------
// OTP boxes

/// One box per digit over a single hidden text field, so paste, autofill and the keyboard all work.
class OtpInput extends StatefulWidget {
  const OtpInput({
    super.key,
    required this.length,
    required this.controller,
    this.onChanged,
    this.onCompleted,
    this.error,
    this.enabled = true,
    this.autofocus = true,
  });

  final int length;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final String? error;
  final bool enabled;
  final bool autofocus;

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(OtpInput old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focus.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = widget.controller.text;
    final hasError = widget.error != null;
    final boxSize = widget.length > 4 ? 50.0 : 64.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.length; i++)
                  Flexible(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      constraints: BoxConstraints(maxWidth: boxSize),
                      height: boxSize + 6,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.enabled ? scheme.surface : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          width: 2,
                          color: hasError
                              ? scheme.error
                              : _focus.hasFocus && i == text.length.clamp(0, widget.length - 1)
                              ? scheme.primary
                              : i < text.length
                              ? scheme.primary.withValues(alpha: 0.5)
                              : scheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        i < text.length ? text[i] : '',
                        style: TextStyle(fontSize: widget.length > 4 ? 24 : 30, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
            Positioned.fill(
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                maxLength: widget.length,
                showCursor: false,
                enableInteractiveSelection: false,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  counterText: '',
                ),
                onChanged: (value) {
                  widget.onChanged?.call(value);
                  if (value.length == widget.length) widget.onCompleted?.call(value);
                },
                onSubmitted: (value) {
                  if (value.length == widget.length) widget.onCompleted?.call(value);
                },
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          child: hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 18, color: scheme.error),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// Dialogs

/// Bottom sheet asking the user to confirm an action. Resolves true on confirm.
Future<bool> confirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: IconBadge(
                icon: icon,
                size: 72,
                color: destructive ? scheme.error : null,
                background: destructive ? scheme.errorContainer.withValues(alpha: 0.6) : null,
              ),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton(
              style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error) : null,
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

Future<bool> confirmLogout(BuildContext context) => confirmSheet(
  context,
  title: 'Log out?',
  message: "You'll need your mobile number and an OTP to log in again.",
  confirmLabel: 'Log out',
  icon: Icons.logout_rounded,
  destructive: true,
);

// ---------------------------------------------------------------------------------------------
// Device actions

Future<void> callNumber(BuildContext context, String mobile) async {
  if (!await launchUrl(Uri.parse('tel:+91$mobile'))) {
    if (context.mounted) showInfo(context, 'Call +91 $mobile');
  }
}

Future<void> openMap(BuildContext context, {double? lat, double? lng, String? query}) async {
  final q = lat != null && lng != null ? '$lat,$lng' : Uri.encodeComponent(query ?? '');
  final ok = await launchUrl(
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) showInfo(context, "Couldn't open maps.");
}

Future<void> copyText(BuildContext context, String text, String what) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showInfo(context, '$what copied');
}

/// Refreshes a screen on a timer while it is the visible route (no push notifications, A9).
mixin Polling<T extends StatefulWidget> on State<T> {
  Timer? _timer;

  void startPolling(Duration every, Future<void> Function() refresh) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true) && TickerMode.valuesOf(context).enabled) refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
