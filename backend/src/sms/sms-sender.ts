import { Logger } from '@nestjs/common';
import { Errors } from '../common/errors';

/** SMS is used only for OTPs (A9). */
export abstract class SmsSender {
  abstract sendLoginOtp(mobile: string, otp: string): Promise<void>;
  abstract sendDeliveryOtp(mobile: string, orderDisplayId: string, otp: string): Promise<void>;
}

/** Development only: prints OTPs to the log instead of sending them. Refused in production by loadConfig. */
export class ConsoleSmsSender extends SmsSender {
  private readonly logger = new Logger('ConsoleSms');

  async sendLoginOtp(mobile: string, otp: string) {
    this.logger.warn(`[DEV] Login OTP for ${mobile}: ${otp}`);
  }

  async sendDeliveryOtp(mobile: string, orderDisplayId: string, otp: string) {
    this.logger.warn(`[DEV] Delivery OTP for ${mobile}, order ${orderDisplayId}: ${otp}`);
  }
}

/** MSG91 Flow API with DLT-approved templates. Template variables: ##otp## and ##order##. */
export class Msg91SmsSender extends SmsSender {
  private static readonly URL = 'https://control.msg91.com/api/v5/flow';

  constructor(
    private readonly authKey: string,
    private readonly loginTemplateId: string,
    private readonly deliveryTemplateId?: string,
  ) {
    super();
  }

  sendLoginOtp(mobile: string, otp: string) {
    return this.send(this.loginTemplateId, mobile, { otp });
  }

  sendDeliveryOtp(mobile: string, orderDisplayId: string, otp: string) {
    if (!this.deliveryTemplateId) throw new Error('MSG91_DELIVERY_OTP_TEMPLATE_ID is not set');
    return this.send(this.deliveryTemplateId, mobile, { otp, order: orderDisplayId });
  }

  private async send(templateId: string, mobile: string, vars: Record<string, string>) {
    let res: Response;
    try {
      res = await fetch(Msg91SmsSender.URL, {
        method: 'POST',
        headers: { authkey: this.authKey, 'content-type': 'application/json' },
        body: JSON.stringify({ template_id: templateId, short_url: '0', recipients: [{ mobiles: `91${mobile}`, ...vars }] }),
        signal: AbortSignal.timeout(10_000),
      });
    } catch {
      throw Errors.smsSendFailed();
    }
    if (!res.ok) throw Errors.smsSendFailed();
  }
}
