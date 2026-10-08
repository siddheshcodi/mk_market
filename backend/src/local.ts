/**
 * `npm run local`: starts the API with no outside services, for trying the app on this computer.
 * - In-memory database with the stores, staff and products from config/*.example.yaml
 * - OTPs are printed in this window instead of sent by SMS, and are always 123456 (login) / 1234 (delivery)
 * - Test payments (the app shows Success / Fail buttons)
 * - Road distance estimated from the map pin
 * Any of these can be overridden with real environment variables.
 */
const defaults: Record<string, string> = {
  NODE_ENV: 'development',
  PORT: '3000',
  DATABASE_URL: 'memory',
  JWT_SECRET: 'local-only-jwt-secret-not-for-production-0000',
  OTP_SECRET: 'local-only-otp-secret-not-for-production-0000',
  SMS_PROVIDER: 'console',
  MAPS_PROVIDER: 'dev',
  PAYMENT_PROVIDER: 'test',
  DEV_FIXED_OTP: 'true',
  CORS_ORIGINS: 'http://localhost:8080',
};
for (const [key, value] of Object.entries(defaults)) process.env[key] ??= value;

// Imported after the defaults are set, because config is read at start-up.
import('./main').then(({ bootstrap }) => bootstrap());
