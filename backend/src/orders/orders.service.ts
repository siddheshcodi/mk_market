import { Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { Clock } from '../common/clock';
import { Errors } from '../common/errors';
import { Db, Queryable } from '../database/db';
import { newDisplayOrderId } from './display-id';
import { OrderStatus, recordStatus } from './order-status';

/** A priced order line as stored on the checkout. */
export interface OrderLine {
  productId: string;
  name: string;
  unit: string;
  unitPricePaise: number;
  qty: number;
  lineTotalPaise: number;
}

export interface PaidCheckout {
  id: string;
  user_id: string;
  store_id: string;
  address: Record<string, unknown>;
  items: OrderLine[];
  total_paise: number;
}

const placeholders = (values: unknown[]) => values.map((_, i) => `$${i + 1}`).join(', ');

const LIFECYCLE: OrderStatus[] = ['PLACED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'UNDELIVERED'];

export interface PlacedOrder {
  orderId: string;
  displayOrderId: string;
  status: OrderStatus;
}

@Injectable()
export class OrdersService {
  constructor(
    private readonly db: Db,
    private readonly clock: Clock,
  ) {}

  /** FR-U-10: called only inside the payment transaction, after the gateway confirmed the payment. */
  async createPlacedOrder(q: Queryable, checkout: PaidCheckout, paymentId: string, at: Date): Promise<PlacedOrder> {
    const orderId = randomUUID();
    const displayOrderId = newDisplayOrderId(at);
    await q.query(
      `INSERT INTO orders (id, display_id, user_id, store_id, checkout_id, payment_id, delivery_address, total_paise, status, placed_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, 'PLACED', $9)`,
      [orderId, displayOrderId, checkout.user_id, checkout.store_id, checkout.id, paymentId, JSON.stringify(checkout.address), checkout.total_paise, at],
    );
    for (const line of checkout.items) {
      await q.query(
        `INSERT INTO order_items (id, order_id, product_id, name_snapshot, unit_snapshot, unit_price_paise, qty, line_total_paise)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [randomUUID(), orderId, line.productId, line.name, line.unit, line.unitPricePaise, line.qty, line.lineTotalPaise],
      );
    }
    await recordStatus(q, orderId, null, 'PLACED', 'SYSTEM', at);
    return { orderId, displayOrderId, status: 'PLACED' };
  }

  async findByPayment(q: Queryable, paymentId: string): Promise<PlacedOrder | undefined> {
    const [row] = await q.query(`SELECT id, display_id, status FROM orders WHERE payment_id = $1`, [paymentId]);
    return row && { orderId: row.id, displayOrderId: row.display_id, status: row.status };
  }

  /** FR-U-12: the customer's own orders only, newest first. */
  async listForUser(userId: string, page: number, size: number) {
    const rows = await this.db.query(
      `SELECT o.id, o.display_id, o.placed_at, o.total_paise, o.status, COUNT(i.id) AS item_count
       FROM orders o LEFT JOIN order_items i ON i.order_id = o.id
       WHERE o.user_id = $1
       GROUP BY o.id, o.display_id, o.placed_at, o.total_paise, o.status
       ORDER BY o.placed_at DESC, o.id
       LIMIT $2 OFFSET $3`,
      [userId, size + 1, (page - 1) * size],
    );
    return {
      items: rows.slice(0, size).map((o) => ({
        orderId: o.id,
        displayOrderId: o.display_id,
        placedAt: o.placed_at,
        itemCount: Number(o.item_count),
        totalPaise: o.total_paise,
        status: o.status,
      })),
      page,
      hasMore: rows.length > size,
    };
  }

  /** Another customer's order looks the same as a missing one, so order IDs can't be probed (NFR-03). */
  async getForUser(userId: string, orderId: string) {
    const [order] = await this.db.query(
      `SELECT o.*, s.name AS store_name FROM orders o JOIN stores s ON s.id = o.store_id
       WHERE o.id = $1 AND o.user_id = $2`,
      [orderId, userId],
    );
    if (!order) throw Errors.notFound('Order');

    const [items, timeline, otpActive] = await Promise.all([
      this.items(orderId),
      this.timeline(orderId),
      this.activeDeliveryOtps([orderId], this.clock.now()),
    ]);
    return {
      orderId: order.id,
      displayOrderId: order.display_id,
      status: order.status as OrderStatus,
      placedAt: order.placed_at,
      storeName: order.store_name,
      totalPaise: order.total_paise,
      paidInAdvance: true,
      address: order.delivery_address,
      items,
      timeline,
      // FR-U-13: the app asks the customer to share the OTP sent by SMS. The OTP itself is never returned.
      deliveryOtpActive: otpActive.has(orderId),
    };
  }

  /** Lines as priced when the order was paid. Callers must already have checked access to the order. */
  async items(orderId: string) {
    const rows = await this.db.query(
      `SELECT product_id, name_snapshot, unit_snapshot, unit_price_paise, qty, line_total_paise
       FROM order_items WHERE order_id = $1 ORDER BY name_snapshot`,
      [orderId],
    );
    return rows.map((i) => ({
      productId: i.product_id,
      name: i.name_snapshot,
      unit: i.unit_snapshot,
      unitPricePaise: i.unit_price_paise,
      qty: i.qty,
      lineTotalPaise: i.line_total_paise,
    }));
  }

  /** Number of product lines per order. */
  async itemCounts(orderIds: string[]) {
    if (!orderIds.length) return new Map<string, number>();
    const rows = await this.db.query(
      `SELECT order_id, COUNT(*) AS n FROM order_items WHERE order_id IN (${placeholders(orderIds)}) GROUP BY order_id`,
      orderIds,
    );
    return new Map(rows.map((r) => [r.order_id as string, Number(r.n)]));
  }

  /** Orders whose delivery OTP has been sent and can still be used. */
  async activeDeliveryOtps(orderIds: string[], now: Date) {
    if (!orderIds.length) return new Set<string>();
    const rows = await this.db.query(
      `SELECT order_id FROM delivery_otps
       WHERE order_id IN (${placeholders(orderIds)}) AND status = 'ACTIVE' AND expires_at >= $${orderIds.length + 1}`,
      [...orderIds, now],
    );
    return new Set(rows.map((r) => r.order_id as string));
  }

  /** Status changes in time order; changes at the same instant follow the lifecycle. */
  async timeline(orderId: string) {
    const rows = await this.db.query<{ to_status: OrderStatus; at: Date }>(
      `SELECT to_status, at FROM order_status_history WHERE order_id = $1`,
      [orderId],
    );
    return rows
      .sort((a, b) => a.at.getTime() - b.at.getTime() || LIFECYCLE.indexOf(a.to_status) - LIFECYCLE.indexOf(b.to_status))
      .map((t) => ({ status: t.to_status, at: t.at }));
  }
}
