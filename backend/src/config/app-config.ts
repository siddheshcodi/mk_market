export interface AppConfig {
  env: string;
  port: number;
  /** A postgres:// URL, or "memory" for the local demo database (not allowed in production). */
  databaseUrl: string;
  jwtSecret: string;
  otpSecret: string;
  /** Local testing only: every OTP is 123456 (login) / 1234 (delivery). Not allowed in production. */
  devFixedOtp: boolean;
  /** Browser origins allowed to call the API (the Flutter web app). Mobile apps don't need this. */
  corsOrigins: string[];
  maps: { provider: 'google' | 'dev'; googleApiKey?: string };
  sms: {
    provider: 'msg91' | 'console';
    msg91AuthKey?: string;
    msg91LoginOtpTemplateId?: string;
    msg91DeliveryOtpTemplateId?: string;
  };
  payment: {
    /** "test" shows Success / Fail buttons in the app instead of Razorpay (not allowed in production). */
    provider: 'razorpay' | 'test';
    razorpayKeyId: string;
    razorpayKeySecret: string;
    razorpayWebhookSecret: string;
  };
}

export const APP_CONFIG = Symbol('APP_CONFIG');

export const MEMORY_DATABASE = 'memory';

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  const required = (name: string): string => {
    const value = env[name];
    if (!value) throw new Error(`Missing required environment variable ${name}`);
    return value;
  };
  const secret = (name: string): string => {
    const value = required(name);
    if (value.length < 32) throw new Error(`${name} must be at least 32 characters`);
    return value;
  };
  const testPayments = env.PAYMENT_PROVIDER === 'test';

  const config: AppConfig = {
    env: env.NODE_ENV ?? 'development',
    port: Number(env.PORT ?? 3000),
    databaseUrl: required('DATABASE_URL'),
    jwtSecret: secret('JWT_SECRET'),
    otpSecret: secret('OTP_SECRET'),
    devFixedOtp: env.DEV_FIXED_OTP === 'true',
    corsOrigins: (env.CORS_ORIGINS ?? '')
      .split(',')
      .map((o) => o.trim())
      .filter(Boolean),
    maps: {
      provider: env.MAPS_PROVIDER === 'google' ? 'google' : 'dev',
      googleApiKey: env.GOOGLE_MAPS_API_KEY,
    },
    sms: {
      provider: env.SMS_PROVIDER === 'msg91' ? 'msg91' : 'console',
      msg91AuthKey: env.MSG91_AUTH_KEY,
      msg91LoginOtpTemplateId: env.MSG91_LOGIN_OTP_TEMPLATE_ID,
      msg91DeliveryOtpTemplateId: env.MSG91_DELIVERY_OTP_TEMPLATE_ID,
    },
    payment: testPayments
      ? { provider: 'test', razorpayKeyId: 'rzp_test_local', razorpayKeySecret: '', razorpayWebhookSecret: '' }
      : {
          provider: 'razorpay',
          razorpayKeyId: required('RAZORPAY_KEY_ID'),
          razorpayKeySecret: required('RAZORPAY_KEY_SECRET'),
          razorpayWebhookSecret: required('RAZORPAY_WEBHOOK_SECRET'),
        },
  };

  if (config.maps.provider === 'google' && !config.maps.googleApiKey) {
    throw new Error('GOOGLE_MAPS_API_KEY is required when MAPS_PROVIDER=google');
  }
  if (config.sms.provider === 'msg91' && !(config.sms.msg91AuthKey && config.sms.msg91LoginOtpTemplateId)) {
    throw new Error('MSG91_AUTH_KEY and MSG91_LOGIN_OTP_TEMPLATE_ID are required when SMS_PROVIDER=msg91');
  }
  if (
    config.env === 'production' &&
    (config.maps.provider !== 'google' ||
      config.sms.provider !== 'msg91' ||
      config.payment.provider !== 'razorpay' ||
      config.databaseUrl === MEMORY_DATABASE ||
      config.devFixedOtp)
  ) {
    // The local providers measure straight-line distance, print OTPs to the log, fake payments and lose data.
    throw new Error(
      'Production needs MAPS_PROVIDER=google, SMS_PROVIDER=msg91, Razorpay payments, a PostgreSQL DATABASE_URL and no DEV_FIXED_OTP',
    );
  }
  return config;
}
