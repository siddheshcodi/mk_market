import { HttpException, Inject, Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { generateOtp, hashOtp, otpMatches } from '../auth/otp';
import { addSeconds, Clock } from '../common/clock';
import { AppError, Errors } from '../common/errors';
import { IdempotencyScope, savedResponse, saveResponse } from '../common/idempotency';
import { DELIVERY_OTP, HISTORY_DAYS } from '../common/rules';
import { APP_CONFIG, AppConfig } from '../config/app-config';
import { Db, Queryable } from '../database/db';
import { OrderStatus, transitionOrder } from '../orders/order-status';
import { OrdersService } from '../orders/orders.service';
import { SmsSender } from '../sms/sms-sender';

export type DeliveryTab = 'ACTIVE' | 'COMPLETED';
type OtpStatus = 'NOT_SENT' | 'ACTIVE' | 'EXPIRED' | 'USED' | 'REPLACED' | 'EXHAUSTED';

interface AssignedOrder {
  id: string;
  display_id: string;
  status: OrderStatus;
  customer_mobile: string;
}

interface Counters {
  attempts_used: number;
  resends_used: number;
  last_sent_at: Date;
}

/** A verify result that used up an attempt. Saved under the Idempotency-Key so a network retry gets it back. */
interface VerifyOutcome {
  httpStatus: number;
  body: Record<string, unknown>;
}

/** An OTP that has been written but not yet sent; undone if the SMS fails. */
interface PendingSms {
  otp: string;
  otpId: string;
  mobile: string;
  displayId: string;
  undo: (q: Queryable) => Promise<void>;
}

const UNDELIVERED_REASON = 'OTP_ATTEMPTS_EXCEEDED';

/**
 * Delivery boy APIs. A delivery boy sees and acts only on orders assigned to him (BR-17), and sees the
 * customer's details only while the order is on the way (NFR-04). The OTP value is never returned (NFR-02).
 */
@Injectable()
export class DeliveryService {
  constructor(
    private readonly db: Db,
    private readonly orders: OrdersService,
    private readonly sms: SmsSender,
    private readonly clock: Clock,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  /** FR-D-02: Active (on the way, oldest assignment first) or Completed (last 7 days, details hidden). */
  async list(deliveryBoyId: string, tab: DeliveryTab, page: number, size: number) {
    const now = this.clock.now();
    const rows =
      tab === 'ACTIVE'
        ? await this.db.query(
            `SELECT id, display_id, status, assigned_at, closed_at, delivery_address FROM orders
             WHERE delivery_boy_id = $1 AND status = 'OUT_FOR_DELIVERY'
             ORDER BY assigned_at ASC, id LIMIT $2 OFFSET $3`,
            [deliveryBoyId, size + 1, (page - 1) * size],
          )
        : await this.db.query(
            `SELECT id, display_id, status, assigned_at, closed_at, delivery_address, undelivered_reason FROM orders
             WHERE delivery_boy_id = $1 AND status IN ('DELIVERED', 'UNDELIVERED') AND closed_at >= $2
             ORDER BY closed_at DESC, id LIMIT $3 OFFSET $4`,
            [deliveryBoyId, addSeconds(now, -HISTORY_DAYS * 24 * 3600), size + 1, (page - 1) * size],
          );
    const pageRows = rows.slice(0, size);
    const ids = pageRows.map((o) => o.id);
    const [counts, otpActive] = await Promise.all([this.orders.itemCounts(ids), this.orders.activeDeliveryOtps(ids, now)]);

    return {
      items: pageRows.map((o) => ({
        orderId: o.id,
        displayOrderId: o.display_id,
        status: o.status,
        assignedAt: o.assigned_at,
        closedAt: o.closed_at,
        itemCount: counts.get(o.id) ?? 0,
        area: o.delivery_address.street,
        pincode: o.delivery_address.pincode,
        ...(tab === 'ACTIVE'
          ? { customerName: o.delivery_address.name, deliveryOtpActive: otpActive.has(o.id) }
          : { undeliveredReason: o.undelivered_reason }),
      })),
      page,
      hasMore: rows.length > size,
    };
  }

  /** FR-D-03: customer name, mobile and full address with map pin, only while the order is on the way. */
  async get(deliveryBoyId: string, orderId: string) {
    const [order] = await this.db.query(
      `SELECT o.*, u.mobile AS customer_mobile, c.lat, c.lng, s.name AS store_name, s.address AS store_address
       FROM orders o
       JOIN users u ON u.id = o.user_id
       JOIN checkouts c ON c.id = o.checkout_id
       JOIN stores s ON s.id = o.store_id
       WHERE o.id = $1 AND o.delivery_boy_id = $2`,
      [orderId, deliveryBoyId],
    );
    if (!order) throw Errors.notFound('Order');

    const onTheWay = order.status === 'OUT_FOR_DELIVERY';
    const address = order.delivery_address;
    return {
      orderId: order.id,
      displayOrderId: order.display_id,
      status: order.status as OrderStatus,
      assignedAt: order.assigned_at,
      closedAt: order.closed_at,
      store: { name: order.store_name, address: order.store_address },
      items: await this.orders.items(orderId),
      totalPaise: order.total_paise,
      // Paid in advance: nothing to collect at the door (BR-09).
      paidInAdvance: true,
      customer: onTheWay ? { name: address.name, mobile: order.customer_mobile } : null,
      address: onTheWay ? { ...address, lat: order.lat, lng: order.lng } : { area: address.street, pincode: address.pincode },
      deliveryOtp: onTheWay ? await this.otpState(this.db, orderId, this.clock.now()) : null,
      undeliveredReason: order.undelivered_reason,
    };
  }

  /**
   * FR-D-04, FR-D-05, BR-18: "Delivered" sends a 4-digit OTP to the customer's registered mobile.
   * Tapping again doesn't send another SMS; new codes come only from resend.
   */
  async sendOtp(deliveryBoyId: string, orderId: string) {
    const now = this.clock.now();
    const pending = await this.db.tx(async (q): Promise<PendingSms | null> => {
      const order = await this.assignedOrder(q, deliveryBoyId, orderId);
      if (order.status !== 'OUT_FOR_DELIVERY') throw Errors.orderStateChanged(order.status);
      if (await this.lockCounters(q, orderId)) return null;

      // ON CONFLICT covers two first taps arriving together.
      const created = await q.query(
        `INSERT INTO delivery_otp_counters (order_id, attempts_used, resends_used, last_sent_at) VALUES ($1, 0, 0, $2)
         ON CONFLICT (order_id) DO NOTHING RETURNING order_id`,
        [orderId, now],
      );
      if (!created.length) return null;

      const { otp, otpId } = await this.insertOtp(q, orderId, now);
      return {
        otp,
        otpId,
        mobile: order.customer_mobile,
        displayId: order.display_id,
        // A failed SMS uses up nothing: the delivery boy can simply tap Delivered again.
        undo: async (u) => {
          await u.query(`DELETE FROM delivery_otps WHERE id = $1`, [otpId]);
          await u.query(`DELETE FROM delivery_otp_counters WHERE order_id = $1`, [orderId]);
        },
      };
    });

    if (pending) await this.deliver(pending);
    return this.otpState(this.db, orderId, now);
  }

  /** FR-D-09, EX-14: a new OTP, at most 2 times per order and 30 seconds apart. The old OTP stops working. */
  async resendOtp(deliveryBoyId: string, orderId: string) {
    const now = this.clock.now();
    const pending = await this.db.tx(async (q): Promise<PendingSms> => {
      const order = await this.assignedOrder(q, deliveryBoyId, orderId);
      const counters = await this.lockCounters(q, orderId);
      if (order.status !== 'OUT_FOR_DELIVERY') throw Errors.orderStateChanged(order.status);
      if (!counters) throw Errors.deliveryOtpNotActive();
      if (counters.resends_used >= DELIVERY_OTP.maxResends) throw Errors.resendLimitReached();
      const waitSec = Math.ceil(DELIVERY_OTP.resendAfterSec - (now.getTime() - counters.last_sent_at.getTime()) / 1000);
      if (waitSec > 0) throw Errors.resendTooSoon(waitSec);

      const [previous] = await q.query<{ id: string }>(
        `SELECT id FROM delivery_otps WHERE order_id = $1 AND status = 'ACTIVE'`,
        [orderId],
      );
      if (!previous) throw Errors.deliveryOtpNotActive();

      await q.query(`UPDATE delivery_otps SET status = 'REPLACED' WHERE id = $1`, [previous.id]);
      const { otp, otpId } = await this.insertOtp(q, orderId, now);
      await q.query(
        `UPDATE delivery_otp_counters SET resends_used = resends_used + 1, last_sent_at = $2 WHERE order_id = $1`,
        [orderId, now],
      );
      return {
        otp,
        otpId,
        mobile: order.customer_mobile,
        displayId: order.display_id,
        // A failed SMS gives the resend back and keeps the previous OTP working.
        undo: async (u) => {
          await u.query(`DELETE FROM delivery_otps WHERE id = $1`, [otpId]);
          await u.query(`UPDATE delivery_otps SET status = 'ACTIVE' WHERE id = $1`, [previous.id]);
          await u.query(
            `UPDATE delivery_otp_counters SET resends_used = resends_used - 1, last_sent_at = $2 WHERE order_id = $1`,
            [orderId, counters.last_sent_at],
          );
        },
      };
    });

    await this.deliver(pending);
    return this.otpState(this.db, orderId, now);
  }

  /**
   * FR-D-06 to FR-D-08, FR-D-10, BR-20: correct OTP closes the order as Delivered. A wrong OTP uses one of
   * 3 attempts; the 3rd wrong one closes it as Undelivered (returned to store). The order changes only when
   * the server says so, and a retry with the same Idempotency-Key never uses a second attempt (EX-17).
   */
  async verifyOtp(deliveryBoyId: string, orderId: string, otp: string, key: string) {
    const scope: IdempotencyScope = { actorId: deliveryBoyId, endpoint: `delivery-otp-verify:${orderId}`, key };
    const now = this.clock.now();

    const outcome = await this.db.tx(async (q): Promise<VerifyOutcome> => {
      const saved = await savedResponse<VerifyOutcome>(q, scope, now);
      if (saved) return saved;

      // Lock first so parallel submits are checked one at a time and can't exceed 3 attempts.
      const counters = await this.lockCounters(q, orderId);
      const order = await this.assignedOrder(q, deliveryBoyId, orderId);
      if (order.status !== 'OUT_FOR_DELIVERY') throw Errors.orderStateChanged(order.status);

      const [active] = await q.query<{ id: string; otp_hash: string; expires_at: Date }>(
        `SELECT id, otp_hash, expires_at FROM delivery_otps WHERE order_id = $1 AND status = 'ACTIVE'`,
        [orderId],
      );
      if (!counters || !active || counters.attempts_used >= DELIVERY_OTP.maxAttempts) throw Errors.deliveryOtpNotActive();
      // An expired OTP doesn't use up an attempt; the delivery boy resends instead.
      if (now > active.expires_at) throw Errors.deliveryOtpExpired();

      // Counted in one statement as well as under the lock, so the limit holds however requests interleave.
      const [counted] = await q.query<{ attempts_used: number }>(
        `UPDATE delivery_otp_counters SET attempts_used = attempts_used + 1
         WHERE order_id = $1 AND attempts_used < $2 RETURNING attempts_used`,
        [orderId, DELIVERY_OTP.maxAttempts],
      );
      if (!counted) throw Errors.deliveryOtpNotActive();
      const attempts = counted.attempts_used;

      let result: VerifyOutcome;
      if (otpMatches(this.config.otpSecret, active.id, otp, active.otp_hash)) {
        await q.query(`UPDATE delivery_otps SET status = 'USED' WHERE id = $1`, [active.id]);
        await this.close(q, orderId, deliveryBoyId, 'DELIVERED', now);
        result = { httpStatus: 200, body: { result: 'DELIVERED', orderId, deliveredAt: now.toISOString() } };
      } else if (attempts < DELIVERY_OTP.maxAttempts) {
        result = { httpStatus: 400, body: errorBody(Errors.deliveryOtpIncorrect(DELIVERY_OTP.maxAttempts - attempts)) };
      } else {
        await q.query(`UPDATE delivery_otps SET status = 'EXHAUSTED' WHERE id = $1`, [active.id]);
        await this.close(q, orderId, deliveryBoyId, 'UNDELIVERED', now);
        result = {
          httpStatus: 200,
          body: {
            result: 'UNDELIVERED',
            orderId,
            reason: UNDELIVERED_REASON,
            message: 'Delivery failed after 3 incorrect OTPs. Please return this order to the store.',
          },
        };
      }
      await saveResponse(q, scope, result, now);
      return result;
    });

    if (outcome.httpStatus >= 400) throw new HttpException(outcome.body, outcome.httpStatus);
    return outcome.body;
  }

  private async close(q: Queryable, orderId: string, deliveryBoyId: string, to: 'DELIVERED' | 'UNDELIVERED', at: Date) {
    const undelivered = to === 'UNDELIVERED';
    const moved = await transitionOrder(q, {
      orderId,
      from: 'OUT_FOR_DELIVERY',
      to,
      actorRole: 'DELIVERY_BOY',
      actorId: deliveryBoyId,
      reason: undelivered ? UNDELIVERED_REASON : undefined,
      at,
      set: undelivered ? { closed_at: at, undelivered_reason: UNDELIVERED_REASON } : { closed_at: at },
    });
    if (!moved) throw Errors.orderStateChanged(to);
  }

  /** Another delivery boy's order looks the same as a missing one (BR-17). */
  private async assignedOrder(q: Queryable, deliveryBoyId: string, orderId: string): Promise<AssignedOrder> {
    const [order] = await q.query<AssignedOrder>(
      `SELECT o.id, o.display_id, o.status, u.mobile AS customer_mobile
       FROM orders o JOIN users u ON u.id = o.user_id
       WHERE o.id = $1 AND o.delivery_boy_id = $2`,
      [orderId, deliveryBoyId],
    );
    if (!order) throw Errors.notFound('Order');
    return order;
  }

  private async lockCounters(q: Queryable, orderId: string): Promise<Counters | undefined> {
    const [row] = await q.query<Counters>(`SELECT * FROM delivery_otp_counters WHERE order_id = $1 FOR UPDATE`, [orderId]);
    return row;
  }

  private async insertOtp(q: Queryable, orderId: string, now: Date) {
    const otpId = randomUUID();
    const otp = generateOtp(DELIVERY_OTP.length, this.config.devFixedOtp);
    await q.query(
      `INSERT INTO delivery_otps (id, order_id, otp_hash, status, expires_at, created_at) VALUES ($1, $2, $3, 'ACTIVE', $4, $5)`,
      [otpId, orderId, hashOtp(this.config.otpSecret, otpId, otp), addSeconds(now, DELIVERY_OTP.ttlSec), now],
    );
    return { otp, otpId };
  }

  /** BR-18: only to the customer's registered mobile number. */
  private async deliver(pending: PendingSms) {
    try {
      await this.sms.sendDeliveryOtp(pending.mobile, pending.displayId, pending.otp);
    } catch {
      await this.db.tx(pending.undo);
      throw Errors.smsSendFailed();
    }
  }

  /** What the OTP screen shows: never the code itself. */
  private async otpState(q: Queryable, orderId: string, now: Date) {
    const [counters] = await q.query<Counters>(`SELECT * FROM delivery_otp_counters WHERE order_id = $1`, [orderId]);
    if (!counters) {
      return {
        status: 'NOT_SENT' as OtpStatus,
        expiresAt: null,
        attemptsLeft: DELIVERY_OTP.maxAttempts,
        resendsLeft: DELIVERY_OTP.maxResends,
        nextResendAt: null,
      };
    }
    const [latest] = await q.query<{ status: OtpStatus; expires_at: Date }>(
      `SELECT status, expires_at FROM delivery_otps WHERE order_id = $1 ORDER BY created_at DESC LIMIT 1`,
      [orderId],
    );
    const status: OtpStatus = latest.status === 'ACTIVE' && now > latest.expires_at ? 'EXPIRED' : latest.status;
    const resendsLeft = DELIVERY_OTP.maxResends - counters.resends_used;
    const canResend = resendsLeft > 0 && (status === 'ACTIVE' || status === 'EXPIRED');
    return {
      status,
      expiresAt: latest.expires_at,
      attemptsLeft: DELIVERY_OTP.maxAttempts - counters.attempts_used,
      resendsLeft,
      nextResendAt: canResend ? addSeconds(counters.last_sent_at, DELIVERY_OTP.resendAfterSec) : null,
    };
  }
}

function errorBody(error: AppError) {
  return error.getResponse() as Record<string, unknown>;
}
