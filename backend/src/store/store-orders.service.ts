import { Injectable } from '@nestjs/common';
import { addSeconds, Clock } from '../common/clock';
import { Errors } from '../common/errors';
import { IdempotencyScope, savedResponse, saveResponse } from '../common/idempotency';
import { HISTORY_DAYS } from '../common/rules';
import { Db, Queryable } from '../database/db';
import { OrderStatus, transitionOrder } from '../orders/order-status';
import { OrdersService } from '../orders/orders.service';

const TAB_ORDER: Record<OrderStatus, string> = {
  // Oldest first, so orders that have waited longest are seen first (EX-11).
  PLACED: 'o.placed_at ASC, o.id',
  OUT_FOR_DELIVERY: 'o.assigned_at DESC, o.id',
  UNDELIVERED: 'o.closed_at DESC, o.id',
  DELIVERED: 'o.closed_at DESC, o.id',
};

export interface DispatchResult {
  orderId: string;
  displayOrderId: string;
  status: OrderStatus;
  deliveryBoy: { id: string; name: string; mobile: string };
  assignedAt: string;
}

/**
 * Store manager order APIs. Every query is limited to the manager's own store (BR-15, NFR-03).
 * The only change a manager can make is dispatch; there is no reject or cancel (FR-S-06, BR-13).
 */
@Injectable()
export class StoreOrdersService {
  constructor(
    private readonly db: Db,
    private readonly orders: OrdersService,
    private readonly clock: Clock,
  ) {}

  /** FR-S-03: the store's orders for one tab. */
  async list(storeId: string, status: OrderStatus, page: number, size: number, since?: Date) {
    const now = this.clock.now();
    const params: unknown[] = [storeId, status];
    let filter = '';
    if (status === 'PLACED' && since) {
      params.push(since);
      filter = `AND o.placed_at > $${params.length}`;
    }
    if (status === 'DELIVERED') {
      params.push(addSeconds(now, -HISTORY_DAYS * 24 * 3600));
      filter = `AND o.closed_at >= $${params.length}`;
    }
    params.push(size + 1, (page - 1) * size);

    const rows = await this.db.query(
      `SELECT o.id, o.display_id, o.placed_at, o.assigned_at, o.closed_at, o.total_paise, o.status,
              o.delivery_address, o.undelivered_reason, d.name AS delivery_boy_name
       FROM orders o LEFT JOIN delivery_boys d ON d.id = o.delivery_boy_id
       WHERE o.store_id = $1 AND o.status = $2 ${filter}
       ORDER BY ${TAB_ORDER[status]}
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params,
    );
    const page_ = rows.slice(0, size);
    const counts = await this.orders.itemCounts(page_.map((o) => o.id));

    return {
      // Lets the app show "x min ago" without trusting the phone's clock.
      serverTime: now,
      items: page_.map((o) => ({
        orderId: o.id,
        displayOrderId: o.display_id,
        status: o.status,
        placedAt: o.placed_at,
        assignedAt: o.assigned_at,
        closedAt: o.closed_at,
        itemCount: counts.get(o.id) ?? 0,
        totalPaise: o.total_paise,
        area: o.delivery_address.street,
        pincode: o.delivery_address.pincode,
        deliveryBoyName: o.delivery_boy_name,
        undeliveredReason: o.undelivered_reason,
      })),
      page,
      hasMore: rows.length > size,
    };
  }

  /** FR-S-04, D4: full details including the order placed time and the customer's contact. */
  async get(storeId: string, orderId: string) {
    const [order] = await this.db.query(
      `SELECT o.*, u.mobile AS customer_mobile, p.gateway_payment_id,
              d.id AS db_id, d.name AS db_name, d.mobile AS db_mobile
       FROM orders o
       JOIN users u ON u.id = o.user_id
       JOIN payments p ON p.id = o.payment_id
       LEFT JOIN delivery_boys d ON d.id = o.delivery_boy_id
       WHERE o.id = $1 AND o.store_id = $2`,
      [orderId, storeId],
    );
    // Another store's order looks the same as a missing one.
    if (!order) throw Errors.notFound('Order');

    const [items, timeline] = await Promise.all([this.orders.items(orderId), this.orders.timeline(orderId)]);
    return {
      orderId: order.id,
      displayOrderId: order.display_id,
      status: order.status as OrderStatus,
      placedAt: order.placed_at,
      assignedAt: order.assigned_at,
      closedAt: order.closed_at,
      serverTime: this.clock.now(),
      totalPaise: order.total_paise,
      customer: { name: order.delivery_address.name, mobile: order.customer_mobile },
      address: order.delivery_address,
      items,
      payment: { paidInAdvance: true, gatewayReference: String(order.gateway_payment_id ?? '').slice(-6) },
      deliveryBoy: order.db_id ? { id: order.db_id, name: order.db_name, mobile: order.db_mobile } : null,
      undeliveredReason: order.undelivered_reason,
      timeline,
    };
  }

  /** FR-S-05, BR-16, A7: active delivery boys of this store, with how many orders each is carrying. */
  async deliveryBoys(storeId: string) {
    const boys = await this.db.query(
      `SELECT id, code, name, mobile FROM delivery_boys WHERE store_id = $1 AND is_active ORDER BY name, code`,
      [storeId],
    );
    const active = await this.db.query<{ delivery_boy_id: string }>(
      `SELECT delivery_boy_id FROM orders WHERE store_id = $1 AND status = 'OUT_FOR_DELIVERY'`,
      [storeId],
    );
    return {
      items: boys.map((b) => ({
        id: b.id,
        code: b.code,
        name: b.name,
        mobile: b.mobile,
        activeOrders: active.filter((o) => o.delivery_boy_id === b.id).length,
      })),
    };
  }

  /**
   * FR-S-05, A8: assigning a delivery boy and moving the order to "On the way for delivery" is one action.
   * Only the first of two simultaneous dispatches wins (EX-18); a retry with the same key gets the same result.
   */
  async dispatch(storeId: string, managerId: string, orderId: string, deliveryBoyId: string, key: string) {
    const scope: IdempotencyScope = { actorId: managerId, endpoint: `dispatch:${orderId}`, key };
    const now = this.clock.now();

    return this.db.tx(async (q) => {
      const saved = await savedResponse<DispatchResult>(q, scope, now);
      if (saved) return saved;

      const [order] = await q.query(`SELECT id, display_id, status FROM orders WHERE id = $1 AND store_id = $2`, [
        orderId,
        storeId,
      ]);
      if (!order) throw Errors.notFound('Order');

      const [boy] = await q.query(`SELECT id, store_id, name, mobile, is_active FROM delivery_boys WHERE id = $1`, [
        deliveryBoyId,
      ]);
      if (!boy || boy.store_id !== storeId) throw Errors.deliveryBoyNotInStore();
      if (!boy.is_active) throw Errors.deliveryBoyInactive();

      if (order.status !== 'PLACED') return this.lostRace(q, scope, orderId, now);
      const moved = await transitionOrder(q, {
        orderId,
        from: 'PLACED',
        to: 'OUT_FOR_DELIVERY',
        actorRole: 'STORE_MANAGER',
        actorId: managerId,
        at: now,
        set: { delivery_boy_id: deliveryBoyId, assigned_at: now },
      });
      if (!moved) return this.lostRace(q, scope, orderId, now);

      const result: DispatchResult = {
        orderId,
        displayOrderId: order.display_id,
        status: 'OUT_FOR_DELIVERY',
        deliveryBoy: { id: boy.id, name: boy.name, mobile: boy.mobile },
        assignedAt: now.toISOString(),
      };
      await saveResponse(q, scope, result, now);
      return result;
    });
  }

  /** A same-key retry that lost the race still gets the winner's result; anyone else sees the new status. */
  private async lostRace(q: Queryable, scope: IdempotencyScope, orderId: string, now: Date): Promise<DispatchResult> {
    const saved = await savedResponse<DispatchResult>(q, scope, now);
    if (saved) return saved;
    const [current] = await q.query(`SELECT status FROM orders WHERE id = $1`, [orderId]);
    throw Errors.orderStateChanged(current.status);
  }
}
