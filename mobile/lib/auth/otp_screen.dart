import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../core/session.dart';
import '../core/widgets.dart';

/// FR-U-02, BR-02, BR-03: 6-digit OTP, resend after 30 seconds, no account lock.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.mobile, required this.role, required this.initialRequest});

  final String mobile;
  final Role role;
  final OtpRequest initialRequest;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otp = TextEditingController();
  late OtpRequest _request = widget.initialRequest;
  late int _resendIn = widget.initialRequest.resendAfterSec;
  Timer? _timer;
  String? _error;
  bool _busy = false;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 0) {
        t.cancel();
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  Future<void> _verify() async {
    if (_otp.text.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<Session>();
    final navigator = Navigator.of(context);
    try {
      await session.verifyOtp(_request.requestId, _otp.text, widget.role);
      // The app home switches to the role's module; close the login screens.
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _otp.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      final request = await context.read<Session>().requestOtp(widget.mobile, widget.role);
      setState(() {
        _request = request;
        _resendIn = request.resendAfterSec;
        _error = null;
        _otp.clear();
      });
      _startTimer();
      if (mounted) showSuccess(context, 'A new OTP has been sent.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        child: PageBody(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (AppConfig.localMode) const LocalModeBanner('Local backend: enter 123456. The OTP is also printed in the backend window.'),
              Text('Verify your number', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Sent to +91 ${widget.mobile}',
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('Change'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Enter the 6-digit OTP', style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              OtpInput(
                length: 6,
                controller: _otp,
                error: _error,
                enabled: !_busy,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onCompleted: (_) => _verify(),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'Verify',
                busy: _busy,
                onPressed: _otp.text.length == 6 ? _verify : null,
              ),
              const SizedBox(height: 16),
              Center(
                child: _resendIn > 0
                    ? HintLine(icon: Icons.timer_outlined, text: 'Resend OTP in ${_resendIn}s', fontSize: 14)
                    : TextButton.icon(
                        onPressed: _resending ? null : _resend,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Resend OTP'),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                "Didn't get it? Check the number above, then wait for the timer to resend.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
