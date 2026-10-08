// Business values from requirement.md. Kept in one place so a client change is a one-line edit.

export type Role = 'USER' | 'STORE_MANAGER' | 'DELIVERY_BOY';
export const ROLES: Role[] = ['USER', 'STORE_MANAGER', 'DELIVERY_BOY'];

/** BR-01: 10-digit Indian mobile numbers (+91 is implied). */
export const MOBILE_PATTERN = /^[6-9]\d{9}$/;

/** BR-02, BR-03, EX-03, A11. The send limit is SMS throttling, not an account lock (spec OI-U3). */
export const LOGIN_OTP = {
  length: 6,
  ttlSec: 5 * 60,
  resendAfterSec: 30,
  maxSendsPerHour: 5,
  maxVerifyAttempts: 10,
};

/** BR-08, D2: a store must be within 4 km by road. */
export const SERVICE_RADIUS_M = 4000;

/** spec §6.5: the store and price are locked for this long after the address check. */
export const CHECKOUT_TTL_SEC = 15 * 60;

/** spec §6.6: a payment confirmed after this window creates no order (EX-09). */
export const PAYMENT_WINDOW_SEC = 15 * 60;

/**
 * BR-19, A10. Attempts and resends are per order; a resend does not reset attempts (spec OI-D1).
 * An expired OTP does not use up an attempt.
 */
export const DELIVERY_OTP = {
  length: 4,
  ttlSec: 10 * 60,
  maxAttempts: 3,
  maxResends: 2,
  resendAfterSec: 30,
};

/** Completed tab and store Delivered tab look back this far. */
export const HISTORY_DAYS = 7;

/** spec OI-U5. */
export const MAX_QTY_PER_ITEM = 10;

export const ACCESS_TOKEN_TTL_SEC = 15 * 60;

/** NFR-06 (values proposed in spec OI-U2 and OI-S4). */
export const SESSION_IDLE_SEC: Record<Role, number> = {
  USER: 30 * 24 * 60 * 60,
  STORE_MANAGER: 12 * 60 * 60,
  DELIVERY_BOY: 12 * 60 * 60,
};
