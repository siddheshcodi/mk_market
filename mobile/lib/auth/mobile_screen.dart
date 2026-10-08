import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../core/session.dart';
import '../core/widgets.dart';
import 'otp_screen.dart';

/// BR-01: 10-digit Indian mobile number; +91 is fixed.
final mobilePattern = RegExp(r'^[6-9]\d{9}$');

class MobileScreen extends StatefulWidget {
  const MobileScreen({super.key, required this.role});

  final Role role;

  @override
  State<MobileScreen> createState() => _MobileScreenState();
}

class _MobileScreenState extends State<MobileScreen> {
  final _mobile = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final mobile = _mobile.text.trim();
    if (!mobilePattern.hasMatch(mobile)) {
      setState(() => _error = 'Enter a valid 10-digit mobile number');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final request = await context.read<Session>().requestOtp(mobile, widget.role);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(mobile: mobile, role: widget.role, initialRequest: request),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final staff = widget.role != Role.user;
    return Scaffold(
      appBar: AppBar(),
      body: SingleChildScrollView(
        child: PageBody(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  avatar: Icon(_roleIcon, size: 18, color: scheme.primary),
                  label: Text('${widget.role.label} login'),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(height: 16),
              Text('Enter your mobile number', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                staff
                    ? 'Use the number registered for you by MK Market.'
                    : "We'll send you a one-time password (OTP). No password needed.",
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _mobile,
                autofocus: true,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                autofillHints: const [AutofillHints.telephoneNumberNational],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1.5),
                decoration: InputDecoration(
                  labelText: 'Mobile number',
                  hintText: '98765 43210',
                  hintStyle: TextStyle(color: scheme.outline, fontWeight: FontWeight.w400),
                  prefixIcon: Container(
                    margin: const EdgeInsets.only(left: 12, right: 8),
                    padding: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(border: Border(right: BorderSide(color: scheme.outlineVariant))),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🇮🇳', style: TextStyle(fontSize: 18)),
                        SizedBox(width: 6),
                        Text('+91', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  errorText: _error,
                  errorMaxLines: 2,
                  counterText: '',
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              PrimaryButton(label: 'Get OTP', onPressed: _submit, busy: _busy),
              if (AppConfig.localMode) ...[
                const SizedBox(height: 20),
                LocalModeBanner(switch (widget.role) {
                  Role.user => 'Use any number, e.g. 9999999999. OTP: 123456',
                  Role.storeManager => 'Kothrud store: 9000000001 · Aundh store: 9000000002. OTP: 123456',
                  Role.deliveryBoy => 'Kothrud: 9000000011 or 9000000012 · Aundh: 9000000021. OTP: 123456',
                }),
              ],
              const SizedBox(height: 20),
              const HintLine(icon: Icons.lock_outline_rounded, text: 'Your number is only used to log you in.'),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _roleIcon => switch (widget.role) {
    Role.user => Icons.shopping_basket_rounded,
    Role.storeManager => Icons.store_rounded,
    Role.deliveryBoy => Icons.delivery_dining_rounded,
  };
}
