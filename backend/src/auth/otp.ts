import { createHmac, randomInt, timingSafeEqual } from 'crypto';

/** Local testing only (DEV_FIXED_OTP=true): login OTP is 123456 and delivery OTP is 1234. */
export const DEV_FIXED_OTP = '123456';

export function generateOtp(length: number, fixed = false): string {
  if (fixed) return DEV_FIXED_OTP.slice(0, length);
  return randomInt(0, 10 ** length)
    .toString()
    .padStart(length, '0');
}

/** OTPs are stored only as an HMAC, salted with the record id (NFR-02). */
export function hashOtp(secret: string, salt: string, otp: string): string {
  return createHmac('sha256', secret).update(`${salt}:${otp}`).digest('hex');
}

export function otpMatches(secret: string, salt: string, otp: string, storedHash: string): boolean {
  const actual = Buffer.from(hashOtp(secret, salt, otp), 'hex');
  const expected = Buffer.from(storedHash, 'hex');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
