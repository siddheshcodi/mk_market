import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../config.dart';
import '../core/api_client.dart';
import '../core/format.dart';

/// What the payment screen (Razorpay, or the local test sheet) handed back.
sealed class PaymentResult {}

class PaymentSucceeded extends PaymentResult {
  PaymentSucceeded(this.gatewayOrderId, this.gatewayPaymentId, this.signature);
  final String gatewayOrderId;
  final String gatewayPaymentId;
  final String signature;

  Map<String, String> toJson() => {
    'gatewayOrderId': gatewayOrderId,
    'gatewayPaymentId': gatewayPaymentId,
    'signature': signature,
  };
}

class PaymentFailed extends PaymentResult {
  PaymentFailed([this.details]);

  /// Present when the gateway still returned ids, so the server can confirm the failure.
  final PaymentSucceeded? details;
}

class PaymentCancelled extends PaymentResult {}

/// Opens Razorpay checkout on Android / iOS, or the Success / Fail sheet in local mode.
Future<PaymentResult> launchPayment(
  BuildContext context,
  ApiClient api, {
  required String gatewayOrderId,
  required String gatewayKey,
  required int amountPaise,
  required String customerMobile,
}) {
  if (AppConfig.localMode) return _testPayment(context, api, gatewayOrderId, amountPaise);
  if (kIsWeb) {
    throw ApiException(0, 'UNSUPPORTED', 'Online payment is available in the Android and iOS app.');
  }
  return _razorpay(gatewayOrderId, gatewayKey, amountPaise, customerMobile);
}

Future<PaymentResult> _razorpay(String orderId, String key, int amountPaise, String mobile) {
  final completer = Completer<PaymentResult>();
  final razorpay = Razorpay();
  razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
    completer.complete(PaymentSucceeded(r.orderId ?? orderId, r.paymentId!, r.signature!));
  });
  razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
    completer.complete(r.code == Razorpay.PAYMENT_CANCELLED ? PaymentCancelled() : PaymentFailed());
  });
  razorpay.open({
    'key': key,
    'order_id': orderId,
    'amount': amountPaise,
    'currency': 'INR',
    'name': 'MK Market',
    'description': 'Order payment',
    'prefill': {'contact': '+91$mobile'},
    // BR-09: UPI, cards and net banking.
    'method': {'upi': true, 'card': true, 'netbanking': true, 'wallet': false, 'emi': false, 'paylater': false},
  });
  return completer.future.whenComplete(razorpay.clear);
}

/// Local mode stand-in for Razorpay checkout.
Future<PaymentResult> _testPayment(BuildContext context, ApiClient api, String orderId, int amountPaise) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Test payment', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            const Text('Local mode stands in for Razorpay. No real money is involved.'),
            const SizedBox(height: 16),
            Text('Amount: ${rupees(amountPaise)}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, 'success'),
              icon: const Icon(Icons.check),
              label: const Text('Pay successfully'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'failure'),
              icon: const Icon(Icons.close),
              label: const Text('Fail the payment'),
            ),
            TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: const Text('Cancel')),
          ],
        ),
      ),
    ),
  );
  if (choice == null || choice == 'cancel') return PaymentCancelled();

  final res = await api.post('/dev/payments/complete', body: {'gatewayOrderId': orderId, 'outcome': choice});
  final ids = PaymentSucceeded(
    res['gatewayOrderId'] as String,
    res['gatewayPaymentId'] as String,
    res['signature'] as String,
  );
  return choice == 'success' ? ids : PaymentFailed(ids);
}
