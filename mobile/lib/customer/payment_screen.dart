import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import 'cart.dart';
import 'order_confirmation_screen.dart';
import 'payment_launcher.dart';
import 'shop_widgets.dart';

/// FR-U-09 to FR-U-11: full advance payment; the order exists only after the server confirms it.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.checkout, this.address});

  final Map<String, dynamic> checkout;
  final Map<String, dynamic>? address;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _busy = false;
  bool _confirming = false;
  ({String title, String message})? _failure;
  Timer? _ticker;

  String get _checkoutId => widget.checkout['checkoutId'] as String;
  int get _total => widget.checkout['totalPaise'] as int;
  DateTime? get _expiresAt => parseTime(widget.checkout['expiresAt']);

  @override
  void initState() {
    super.initState();
    // Price and store are held for 15 minutes (spec §6.5); show how long is left.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final api = context.read<ApiClient>();
    final mobile = context.read<Session>().profile['mobile'] as String? ?? '';
    try {
      final start = await api.post('/checkout/$_checkoutId/payment') as Map<String, dynamic>;
      if (!mounted) return;
      final result = await launchPayment(
        context,
        api,
        gatewayOrderId: start['gatewayOrderId'] as String,
        gatewayKey: start['gatewayKey'] as String,
        amountPaise: start['amountPaise'] as int,
        customerMobile: mobile,
      );
      switch (result) {
        case PaymentSucceeded():
          setState(() => _confirming = true);
          await _confirm(api, result);
        case PaymentFailed(:final details):
          if (details != null) await _confirm(api, details);
          _fail('Payment failed', 'No order was placed. Please try again.');
        case PaymentCancelled():
          _fail('Payment cancelled', 'No order was placed. You can try again when ready.');
      }
    } on ApiException catch (e) {
      switch (e.code) {
        case 'PAYMENT_PENDING':
        case 'ALREADY_PAID':
          await _waitForConfirmation(api);
        case 'CHECKOUT_EXPIRED':
          _fail('Checkout expired', e.message);
        default:
          _fail('Payment failed', e.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  /// Throws ApiException for a failed or pending payment; on success opens the confirmation.
  Future<void> _confirm(ApiClient api, PaymentSucceeded payment) async {
    try {
      final order = await api.post('/checkout/$_checkoutId/payment/confirm', body: payment.toJson());
      _placed(order as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.code == 'PAYMENT_FAILED') return; // reported by the caller
      rethrow;
    }
  }

  /// EX-09: the gateway is still confirming. Poll for up to 2 minutes.
  Future<void> _waitForConfirmation(ApiClient api) async {
    setState(() => _confirming = true);
    for (var i = 0; i < 40 && mounted; i++) {
      final status = await api.get('/checkout/$_checkoutId') as Map<String, dynamic>;
      switch (status['status']) {
        case 'PAID':
          final order = await api.get('/orders/${status['orderId']}') as Map<String, dynamic>;
          return _placed(order);
        case 'REFUND_PENDING':
          return _notConfirmed();
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    _notConfirmed();
  }

  void _notConfirmed() => _fail(
    "We couldn't confirm your payment",
    'If money was debited, it will be refunded. Please contact support.',
  );

  void _placed(Map<String, dynamic> order) {
    if (!mounted) return;
    final items = (widget.checkout['items'] as List).cast<Map<String, dynamic>>();
    context.read<Cart>().clear();
    orderPlaced.value++;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => OrderConfirmationScreen(
          order: order,
          totalPaise: _total,
          itemCount: items.length,
          address: widget.address,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  void _fail(String title, String message) {
    if (mounted) setState(() => _failure = (title: title, message: message));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = AppColors.of(context);
    final items = (widget.checkout['items'] as List).cast<Map<String, dynamic>>();
    final left = _expiresAt?.difference(DateTime.now());
    final expired = left != null && left.isNegative;
    final address = widget.address;
    final failure = _failure;

    return PopScope(
      canPop: !_confirming,
      child: Scaffold(
        appBar: AppBar(title: const Text('Review and pay')),
        body: Stack(
          children: [
            ListView(
              children: [
                const PageBody(padding: EdgeInsets.zero, child: CheckoutSteps(current: 2)),
                PageBody(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (failure != null)
                        InfoBanner(tone: Tone.error, title: failure.title, message: failure.message),
                      if (expired)
                        const InfoBanner(
                          tone: Tone.warning,
                          icon: Icons.timer_off_outlined,
                          title: 'Prices are no longer held',
                          message: 'Go back and tap "Continue to payment" again to recheck prices and the store.',
                        )
                      else if (left != null)
                        InfoBanner(
                          tone: Tone.info,
                          icon: Icons.timer_outlined,
                          title: 'Price and store held for ${countdown(left)}',
                          message: 'Complete the payment before the timer ends.',
                        ),
                      SectionCard(
                        title: 'Delivery',
                        icon: Icons.local_shipping_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: colors.successContainer,
                                  child: Icon(Icons.storefront_rounded, color: colors.success),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'From your nearest store',
                                        style: TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                      Text(
                                        '${km(widget.checkout['roadDistanceMeters'] as int)} away by road',
                                        style: TextStyle(color: scheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (address != null) ...[
                              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: scheme.primaryContainer,
                                    child: Icon(Icons.home_rounded, color: scheme.onPrimaryContainer),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'To ${address['name']}',
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        Text(addressLine(address), style: TextStyle(color: scheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      SectionCard(
                        title: 'Your order · ${itemsLabel(items.length)}',
                        icon: Icons.shopping_bag_outlined,
                        child: Column(
                          children: [
                            for (final item in items)
                              ValueRow(
                                '${item['name']}',
                                rupees(item['lineTotalPaise'] as int),
                                subtitle: '${item['unit']} · ${item['qty']} × ${rupees(item['unitPricePaise'] as int)}',
                              ),
                          ],
                        ),
                      ),
                      SectionCard(
                        title: 'Bill details',
                        icon: Icons.receipt_outlined,
                        child: Column(
                          children: [
                            ValueRow('Item total', rupees(_total)),
                            ValueRow('Delivery fee', 'FREE', valueColor: colors.success),
                            const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider()),
                            ValueRow('To pay', rupees(_total), bold: true),
                          ],
                        ),
                      ),
                      const Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          TagPill(icon: Icons.qr_code_2_rounded, label: 'UPI'),
                          TagPill(icon: Icons.credit_card_rounded, label: 'Debit / credit card'),
                          TagPill(icon: Icons.account_balance_rounded, label: 'Net banking'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InfoBanner(
                        tone: Tone.neutral,
                        icon: Icons.lock_outline_rounded,
                        title: 'Secure advance payment',
                        message:
                            'Full payment is taken now through a secure payment gateway. Orders cannot be cancelled after payment.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_confirming) const _ConfirmingOverlay(),
          ],
        ),
        bottomNavigationBar: BottomActionBar(
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rupees(_total), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text('TOTAL', style: theme.textTheme.labelSmall?.copyWith(color: scheme.outline, letterSpacing: 1)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: expired
                    ? FilledButton.tonal(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Go back and recheck'),
                      )
                    : PrimaryButton(
                        label: failure == null ? 'Pay ${rupees(_total)}' : 'Try again – pay ${rupees(_total)}',
                        icon: Icons.lock_rounded,
                        busy: _busy,
                        onPressed: _pay,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmingOverlay extends StatelessWidget {
  const _ConfirmingOverlay();

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(32),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 48, height: 48, child: CircularProgressIndicator(strokeWidth: 4)),
                const SizedBox(height: 20),
                Text('Confirming your payment…', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text("Please don't close the app.", textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
