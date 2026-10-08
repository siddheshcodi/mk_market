import { createHmac, timingSafeEqual } from 'crypto';

export class GatewayUnavailableError extends Error {}

export interface GatewayPayment {
  id: string;
  gatewayOrderId: string;
  amountPaise: number;
  currency: string;
  /** Razorpay values: created | authorized | captured | refunded | failed */
  status: string;
}

/** Card, UPI and bank details stay with the gateway; the backend never sees them (NFR-05). */
export abstract class PaymentGateway {
  abstract readonly keyId: string;
  abstract createOrder(amountPaise: number, receipt: string): Promise<string>;
  abstract fetchPayment(gatewayPaymentId: string): Promise<GatewayPayment>;
  abstract verifyCheckoutSignature(gatewayOrderId: string, gatewayPaymentId: string, signature: string): boolean;
  abstract verifyWebhookSignature(rawBody: Buffer, signature: string): boolean;
}

function hmacEquals(secret: string, data: string | Buffer, signature: string) {
  const expected = Buffer.from(createHmac('sha256', secret).update(data).digest('hex'));
  const actual = Buffer.from(signature);
  return expected.length === actual.length && timingSafeEqual(expected, actual);
}

/** Razorpay Orders API. Turn on auto-capture in the dashboard so successful payments arrive as "captured". */
export class RazorpayGateway extends PaymentGateway {
  private static readonly API = 'https://api.razorpay.com/v1';

  constructor(
    readonly keyId: string,
    private readonly keySecret: string,
    private readonly webhookSecret: string,
  ) {
    super();
  }

  async createOrder(amountPaise: number, receipt: string) {
    const body = await this.call('POST', '/orders', { amount: amountPaise, currency: 'INR', receipt });
    return body.id as string;
  }

  async fetchPayment(gatewayPaymentId: string): Promise<GatewayPayment> {
    const p = await this.call('GET', `/payments/${encodeURIComponent(gatewayPaymentId)}`);
    return { id: p.id, gatewayOrderId: p.order_id, amountPaise: p.amount, currency: p.currency, status: p.status };
  }

  verifyCheckoutSignature(gatewayOrderId: string, gatewayPaymentId: string, signature: string) {
    return hmacEquals(this.keySecret, `${gatewayOrderId}|${gatewayPaymentId}`, signature);
  }

  verifyWebhookSignature(rawBody: Buffer, signature: string) {
    return hmacEquals(this.webhookSecret, rawBody, signature);
  }

  private async call(method: 'GET' | 'POST', path: string, body?: unknown) {
    const auth = Buffer.from(`${this.keyId}:${this.keySecret}`).toString('base64');
    let res: Response;
    try {
      res = await fetch(`${RazorpayGateway.API}${path}`, {
        method,
        headers: { authorization: `Basic ${auth}`, 'content-type': 'application/json' },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(10_000),
      });
    } catch (err) {
      throw new GatewayUnavailableError(String(err));
    }
    if (!res.ok) throw new GatewayUnavailableError(`Razorpay ${method} ${path} returned ${res.status}`);
    return (await res.json()) as any;
  }
}
