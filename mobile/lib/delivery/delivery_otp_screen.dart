import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

/// FR-D-06 to FR-D-10: enter the customer's OTP. 3 attempts and 2 resends per order; the OTP is never shown here.
/// Pops true when the order is closed (Delivered or Undelivered).
class DeliveryOtpScreen extends StatefulWidget {
  const DeliveryOtpScreen({super.key, required this.orderId, required this.displayOrderId});

  final String orderId;
  final String displayOrderId;

  @override
  State<DeliveryOtpScreen> createState() => _DeliveryOtpScreenState();
}

class _DeliveryOtpScreenState extends State<DeliveryOtpScreen> {
  final _otp = TextEditingController();
  Map<String, dynamic>? _state;
  Timer? _ticker;
  String? _error;
  bool _busy = false;
  bool _resending = false;

  /// Set once the order is closed: true = Delivered, false = Undelivered.
  bool? _result;

  /// EX-17: kept until the server answers, so a retry after a network drop doesn't use another attempt.
  String? _pendingKey;
  String? _pendingOtp;

  String get _base => '/delivery/orders/${widget.orderId}/delivery-otp';

  @override
  void initState() {
    super.initState();
    _loadState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _result == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final order = await context.read<ApiClient>().get('/delivery/orders/${widget.orderId}');
      if (mounted) setState(() => _state = order['deliveryOtp'] as Map<String, dynamic>?);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _verify() async {
    final otp = _otp.text;
    if (otp.length != 4 || _busy) return;
    if (_pendingOtp != otp) {
      _pendingKey = const Uuid().v4();
      _pendingOtp = otp;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().post(
        '$_base/verify',
        body: {'otp': otp},
        headers: {'idempotency-key': _pendingKey!},
      ) as Map<String, dynamic>;
      _pendingKey = null;
      _pendingOtp = null;
      final delivered = res['result'] == 'DELIVERED';
      HapticFeedback.mediumImpact();
      setState(() => _result = delivered);
    } on ApiException catch (e) {
      if (e.code == 'NETWORK') {
        // Keep the same key; tapping Submit again replays this attempt.
        setState(() => _error = 'No connection. Your entry is kept – tap Submit to retry.');
        return;
      }
      _pendingKey = null;
      _pendingOtp = null;
      if (e.code == 'ORDER_STATE_CHANGED') {
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      HapticFeedback.vibrate();
      setState(() {
        _error = e.message;
        _otp.clear();
      });
      await _loadState();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      final state = await context.read<ApiClient>().post('$_base/resend') as Map<String, dynamic>;
      setState(() {
        _state = state;
        _error = null;
        _otp.clear();
      });
      if (mounted) showSuccess(context, 'A new OTP was sent to the customer. The old one no longer works.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    if (result != null) return _ResultView(delivered: result, displayOrderId: widget.displayOrderId);

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final state = _state;
    final now = DateTime.now();
    final expiresAt = parseTime(state?['expiresAt']);
    final expired = expiresAt != null && now.isAfter(expiresAt);
    final nextResendAt = parseTime(state?['nextResendAt']);
    final resendWait = nextResendAt?.difference(now);
    final resendsLeft = state?['resendsLeft'] as int? ?? 0;
    final attemptsLeft = state?['attemptsLeft'] as int?;
    final canResend = resendsLeft > 0 && (resendWait == null || resendWait.isNegative);

    return Scaffold(
      appBar: AppBar(title: Text(widget.displayOrderId)),
      body: SingleChildScrollView(
        child: PageBody(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (AppConfig.localMode)
                const LocalModeBanner("Local backend: the customer's OTP is 1234. It is also printed in the backend window."),
              const Center(child: IconBadge(icon: Icons.sms_rounded, size: 80)),
              const SizedBox(height: 16),
              Text('Enter delivery OTP', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                "OTP sent to the customer's phone. Ask the customer to share it.",
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 28),
              OtpInput(
                length: 4,
                controller: _otp,
                enabled: !expired && !_busy,
                error: _error,
                onChanged: (_) => setState(() {}),
                onCompleted: (_) {},
              ),
              const SizedBox(height: 24),
              if (state != null)
                Row(
                  children: [
                    _Stat(
                      label: 'Attempts left',
                      value: '${attemptsLeft ?? '-'}',
                      warn: attemptsLeft != null && attemptsLeft <= 1,
                    ),
                    const SizedBox(width: 10),
                    _Stat(label: 'Resends left', value: '$resendsLeft', warn: resendsLeft == 0),
                    const SizedBox(width: 10),
                    _Stat(
                      label: expired ? 'OTP' : 'Expires in',
                      value: expiresAt == null ? '-' : (expired ? 'Expired' : countdown(expiresAt.difference(now))),
                      warn: expired,
                    ),
                  ],
                ),
              if (expired)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: InfoBanner(
                    tone: Tone.warning,
                    icon: Icons.timer_off_outlined,
                    title: 'OTP has expired',
                    message: resendsLeft > 0 ? 'Tap Resend to send a new one.' : 'No resends left.',
                    margin: EdgeInsets.zero,
                  ),
                ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'Submit',
                icon: Icons.check_rounded,
                busy: _busy,
                onPressed: expired || _otp.text.length != 4 ? null : _verify,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: canResend && !_resending ? _resend : null,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  resendsLeft == 0
                      ? 'No resends left'
                      : canResend
                      ? 'Resend OTP'
                      : 'Resend OTP in ${resendWait?.inSeconds ?? 0}s',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: colors.info),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hand over the items first. The order closes as Delivered only when the OTP matches.',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = warn ? scheme.error : scheme.onSurface;
    return Expanded(
      child: Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: warn ? scheme.errorContainer.withValues(alpha: 0.5) : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: warn ? scheme.error.withValues(alpha: 0.4) : scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen outcome after the server closes the order.
class _ResultView extends StatelessWidget {
  const _ResultView({required this.delivered, required this.displayOrderId});

  final bool delivered;
  final String displayOrderId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final color = delivered ? colors.success : scheme.error;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: PageBody(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.4, end: 1),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.elasticOut,
                        builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                        child: CircleAvatar(
                          radius: 56,
                          backgroundColor: delivered ? colors.successContainer : scheme.errorContainer,
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: color,
                            child: Icon(
                              delivered ? Icons.check_rounded : Icons.assignment_return_rounded,
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      delivered ? 'Order delivered' : 'Delivery failed',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(color: color),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      delivered
                          ? '$displayOrderId is closed as Delivered. Great job!'
                          : 'Delivery failed after 3 incorrect OTPs. Please return this order to the store.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 32),
                    PrimaryButton(
                      label: 'Back to my orders',
                      icon: Icons.list_alt_rounded,
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
