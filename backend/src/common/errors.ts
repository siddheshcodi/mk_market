import { HttpException, HttpStatus } from '@nestjs/common';

/** Every API error has the shape { error: { code, message, ...details } } (spec §8). */
export class AppError extends HttpException {
  constructor(status: HttpStatus, readonly code: string, message: string, details: Record<string, unknown> = {}) {
    super({ error: { code, message, ...details } }, status);
  }
}

// Messages follow NFR-12: say what went wrong and what to do next.
export const Errors = {
  invalidMobile: () => new AppError(HttpStatus.BAD_REQUEST, 'INVALID_MOBILE', 'Enter a valid 10-digit mobile number'),
  numberNotRegistered: () => new AppError(HttpStatus.FORBIDDEN, 'NUMBER_NOT_REGISTERED', 'This number is not registered'),
  otpResendTooSoon: (waitSec: number) =>
    new AppError(HttpStatus.TOO_MANY_REQUESTS, 'OTP_RESEND_TOO_SOON', `You can resend the OTP in ${waitSec} seconds.`, {
      retryAfterSec: waitSec,
    }),
  otpRateLimit: () =>
    new AppError(HttpStatus.TOO_MANY_REQUESTS, 'OTP_RATE_LIMIT', 'Too many OTP requests. Please try again in a while.'),
  otpInvalid: () =>
    new AppError(HttpStatus.BAD_REQUEST, 'OTP_INVALID', 'Incorrect OTP. Please check and try again, or tap Resend.'),
  otpExpired: () => new AppError(HttpStatus.BAD_REQUEST, 'OTP_EXPIRED', 'This OTP has expired. Tap Resend to get a new one.'),
  sessionExpired: () =>
    new AppError(HttpStatus.UNAUTHORIZED, 'SESSION_EXPIRED', 'Your session has ended. Please log in again.'),
  unauthorized: () => new AppError(HttpStatus.UNAUTHORIZED, 'UNAUTHORIZED', 'Please log in to continue.'),
  forbidden: () => new AppError(HttpStatus.FORBIDDEN, 'FORBIDDEN', 'You do not have access to this page.'),
  notFound: (what = 'Item') => new AppError(HttpStatus.NOT_FOUND, 'NOT_FOUND', `${what} not found.`),

  emptyOrder: () => new AppError(HttpStatus.BAD_REQUEST, 'EMPTY_ORDER', 'Add at least one product to continue.'),
  productUnavailable: (productIds: string[]) =>
    new AppError(
      HttpStatus.UNPROCESSABLE_ENTITY,
      'PRODUCT_UNAVAILABLE',
      'Some products are no longer available. Please remove them and try again.',
      { productIds },
    ),
  addressNotFound: () =>
    new AppError(
      HttpStatus.UNPROCESSABLE_ENTITY,
      'ADDRESS_NOT_FOUND',
      "We couldn't find this address. Please check it or drop a pin on the map.",
    ),
  noStoreAvailable: () =>
    new AppError(HttpStatus.UNPROCESSABLE_ENTITY, 'NO_STORE_AVAILABLE', 'Currently no store is available in your area'),
  serviceabilityUnavailable: () =>
    new AppError(
      HttpStatus.SERVICE_UNAVAILABLE,
      'SERVICEABILITY_UNAVAILABLE',
      "We couldn't check delivery to this address right now. Please try again.",
    ),

  checkoutExpired: () =>
    new AppError(
      HttpStatus.CONFLICT,
      'CHECKOUT_EXPIRED',
      'This checkout has expired. Please check your address again to continue.',
    ),
  alreadyPaid: (orderId: string) =>
    new AppError(HttpStatus.CONFLICT, 'ALREADY_PAID', 'This order is already paid.', { orderId }),
  paymentVerificationFailed: () =>
    new AppError(
      HttpStatus.BAD_REQUEST,
      'PAYMENT_VERIFICATION_FAILED',
      "We couldn't confirm your payment. If money was debited, it will be refunded. Please contact support.",
    ),
  paymentFailed: () =>
    new AppError(HttpStatus.PAYMENT_REQUIRED, 'PAYMENT_FAILED', 'Payment failed. No order was placed. Please try again.'),
  paymentGatewayUnavailable: () =>
    new AppError(HttpStatus.BAD_GATEWAY, 'PAYMENT_GATEWAY_UNAVAILABLE', 'Payment service is not responding. Please try again.'),
  smsSendFailed: () => new AppError(HttpStatus.BAD_GATEWAY, 'SMS_SEND_FAILED', "Couldn't send the OTP. Please try again."),

  orderStateChanged: (currentStatus: string) =>
    new AppError(HttpStatus.CONFLICT, 'ORDER_STATE_CHANGED', 'This order was already updated. Showing the latest status.', {
      currentStatus,
    }),
  deliveryBoyNotInStore: () =>
    new AppError(
      HttpStatus.UNPROCESSABLE_ENTITY,
      'DELIVERY_BOY_NOT_IN_STORE',
      'This delivery boy is not part of your store. Please choose another.',
    ),
  deliveryOtpIncorrect: (attemptsLeft: number) =>
    new AppError(
      HttpStatus.BAD_REQUEST,
      'OTP_INCORRECT',
      `Incorrect OTP. ${attemptsLeft} ${attemptsLeft === 1 ? 'attempt' : 'attempts'} left. Ask the customer to use the latest SMS.`,
      { attemptsLeft },
    ),
  deliveryOtpExpired: () =>
    new AppError(HttpStatus.BAD_REQUEST, 'OTP_EXPIRED', 'OTP has expired. Tap Resend to send a new one.'),
  deliveryOtpNotActive: () =>
    new AppError(HttpStatus.CONFLICT, 'OTP_NOT_ACTIVE', 'There is no OTP to check for this order. Tap Delivered to send one.'),
  resendLimitReached: () => new AppError(HttpStatus.CONFLICT, 'RESEND_LIMIT_REACHED', 'No resends left.'),
  resendTooSoon: (waitSec: number) =>
    new AppError(HttpStatus.TOO_MANY_REQUESTS, 'RESEND_TOO_SOON', `You can resend the OTP in ${waitSec} seconds.`, {
      retryAfterSec: waitSec,
    }),
  deliveryBoyInactive: () =>
    new AppError(
      HttpStatus.UNPROCESSABLE_ENTITY,
      'DELIVERY_BOY_INACTIVE',
      'This delivery boy is no longer available. Please choose another.',
    ),
};
