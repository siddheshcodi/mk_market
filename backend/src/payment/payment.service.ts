import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { addSeconds, Clock } from '../common/clock';
import { AppError, Errors } from '../common/errors';
import { PAYMENT_WINDOW_SEC } from '../common/rules';
import { Db, Queryable } from '../database/db';
import { OrdersService, PaidCheckout, PlacedOrder } from '../orders/orders.service';
import { GatewayPayment, GatewayUnavailableError, PaymentGateway } from './payment-gateway';

interface PaymentRow {
  id: string;
  checkout_id: string;
  gateway_order_id: string;
  amount_paise: number;
  status: 'CREATED' | 'FAILED' | 'CAPTURED' | 'CAPTURED_ORPHAN';
  window_ends_at: Date;
}

type CaptureResult = { kind: 'ORDER'; order: PlacedOrder } | { kind: 'ORPHAN' };

@Injectable()
export class PaymentService {
  private readonly logger = new Logger(PaymentService.name);

  constructor(
    private readonly db: Db,
    private readonly gateway: PaymentGateway,
    private readonly orders: OrdersService,
    private readonly clock: Clock,
  ) {}

  /** FR-U-09: full advance payment. The amount is the one locked on the checkout. */
  async start(userId: string, checkoutId: string) {
    const [checkout] = await this.db.query(
      `SELECT id, status, total_paise, expires_at FROM checkouts WHERE id = $1 AND user_id = $2`,
      [checkoutId, userId],
    );
    if (!checkout) throw Errors.notFound('Checkout');
    if (checkout.status === 'PAID') {
      const [order] = await this.db.query(`SELECT id FROM orders WHERE checkout_id = $1`, [checkoutId]);
      throw Errors.alreadyPaid(order.id);
    }
    const now = this.clock.now();
    if (now > checkout.expires_at) throw Errors.checkoutExpired();

    let gatewayOrderId: string;
    try {
      gatewayOrderId = await this.gateway.createOrder(checkout.total_paise, checkoutId);
    } catch (err) {
      if (err instanceof GatewayUnavailableError) throw Errors.paymentGatewayUnavailable();
      throw err;
    }
    await this.db.query(
      `INSERT INTO payments (id, checkout_id, gateway_order_id, amount_paise, status, window_ends_at, created_at, updated_at)
       VALUES ($1, $2, $3, $4, 'CREATED', $5, $6, $6)`,
      [randomUUID(), checkoutId, gatewayOrderId, checkout.total_paise, addSeconds(now, PAYMENT_WINDOW_SEC), now],
    );
    return { gatewayOrderId, gatewayKey: this.gateway.keyId, amountPaise: checkout.total_paise, currency: 'INR' };
  }

  /** The app reports a successful payment. The signature and the gateway's own record are both checked. */
  async confirmFromApp(
    userId: string,
    checkoutId: string,
    input: { gatewayOrderId: string; gatewayPaymentId: string; signature: string },
  ) {
    const [payment] = await this.db.query<PaymentRow>(
      `SELECT p.* FROM payments p JOIN checkouts c ON c.id = p.checkout_id
       WHERE p.gateway_order_id = $1 AND c.id = $2 AND c.user_id = $3`,
      [input.gatewayOrderId, checkoutId, userId],
    );
    if (!payment) throw Errors.notFound('Payment');
    if (!this.gateway.verifyCheckoutSignature(input.gatewayOrderId, input.gatewayPaymentId, input.signature)) {
      throw Errors.paymentVerificationFailed();
    }

    let gp: GatewayPayment;
    try {
      gp = await this.gateway.fetchPayment(input.gatewayPaymentId);
    } catch (err) {
      if (err instanceof GatewayUnavailableError) throw Errors.paymentGatewayUnavailable();
      throw err;
    }
    if (gp.gatewayOrderId !== input.gatewayOrderId) throw Errors.paymentVerificationFailed();
    if (gp.status === 'failed') throw Errors.paymentFailed();
    if (gp.status !== 'captured') {
      // Usually captured within seconds; the webhook finishes the job and the app polls GET /checkout/:id.
      throw new AppError(HttpStatus.ACCEPTED, 'PAYMENT_PENDING', "We're confirming your payment. This can take a few seconds.");
    }

    const result = await this.recordCapture(payment.id, gp);
    if (result.kind === 'ORPHAN') throw Errors.paymentVerificationFailed();
    return result.order;
  }

  /** Gateway webhook: the second path to the same result, for when the app never reports back. */
  async handleWebhook(rawBody: Buffer | undefined, signature: string | undefined) {
    if (!rawBody || !signature || !this.gateway.verifyWebhookSignature(rawBody, signature)) throw Errors.unauthorized();

    const event = JSON.parse(rawBody.toString('utf8'));
    const entity = event?.payload?.payment?.entity;
    if (!entity) return;

    const [payment] = await this.db.query<PaymentRow>(`SELECT * FROM payments WHERE gateway_order_id = $1`, [entity.order_id]);
    if (!payment) {
      this.logger.warn(`Webhook for unknown gateway order ${entity.order_id}`);
      return;
    }

    if (event.event === 'payment.captured') {
      await this.recordCapture(payment.id, {
        id: entity.id,
        gatewayOrderId: entity.order_id,
        amountPaise: entity.amount,
        currency: entity.currency,
        status: entity.status,
      });
    } else if (event.event === 'payment.failed') {
      // A later attempt on the same gateway order can still succeed, so FAILED is not final.
      await this.db.query(`UPDATE payments SET status = 'FAILED', updated_at = $2 WHERE id = $1 AND status = 'CREATED'`, [
        payment.id,
        this.clock.now(),
      ]);
    }
  }

  /**
   * FR-U-10, BR-10, NFR-11: creates the order exactly once, whichever of app confirm and webhook arrives
   * first. Money that can't become an order (paid too late, wrong amount, or the checkout was already
   * paid) is marked CAPTURED_ORPHAN for a manual refund (EX-09, BR-12).
   */
  private recordCapture(paymentId: string, gp: GatewayPayment): Promise<CaptureResult> {
    const now = this.clock.now();
    return this.db.tx(async (q) => {
      const [payment] = await q.query<PaymentRow>(`SELECT * FROM payments WHERE id = $1`, [paymentId]);
      if (payment.status === 'CAPTURED') return this.existingOrder(q, payment.id);
      if (payment.status === 'CAPTURED_ORPHAN') return { kind: 'ORPHAN' };

      const valid = gp.amountPaise === payment.amount_paise && gp.currency === 'INR' && now <= payment.window_ends_at;
      // Claim the payment first: only one caller gets past this update.
      const claimed = await q.query(
        `UPDATE payments SET status = $2, gateway_payment_id = $3, updated_at = $4
         WHERE id = $1 AND status IN ('CREATED', 'FAILED') RETURNING id`,
        [payment.id, valid ? 'CAPTURED' : 'CAPTURED_ORPHAN', gp.id, now],
      );
      if (!claimed.length) return this.existingOrder(q, payment.id);
      if (!valid) return this.orphan(payment, gp, 'late or mismatched payment');

      const [checkout] = await q.query<PaidCheckout>(
        `UPDATE checkouts SET status = 'PAID' WHERE id = $1 AND status = 'OPEN'
         RETURNING id, user_id, store_id, address, items, total_paise`,
        [payment.checkout_id],
      );
      if (!checkout) {
        // Another payment for this checkout already created the order.
        await q.query(`UPDATE payments SET status = 'CAPTURED_ORPHAN' WHERE id = $1`, [payment.id]);
        return this.orphan(payment, gp, 'checkout already paid');
      }
      return { kind: 'ORDER', order: await this.orders.createPlacedOrder(q, checkout, payment.id, now) };
    });
  }

  private async existingOrder(q: Queryable, paymentId: string): Promise<CaptureResult> {
    const order = await this.orders.findByPayment(q, paymentId);
    return order ? { kind: 'ORDER', order } : { kind: 'ORPHAN' };
  }

  private orphan(payment: PaymentRow, gp: GatewayPayment, reason: string): CaptureResult {
    this.logger.warn(`Payment ${gp.id} for checkout ${payment.checkout_id} needs a manual refund: ${reason}`);
    return { kind: 'ORPHAN' };
  }
}
