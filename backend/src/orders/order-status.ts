import { randomUUID } from 'crypto';
import { Queryable } from '../database/db';

/** Order status lifecycle (requirement.md §5.2, spec §7.1). */
export type OrderStatus = 'PLACED' | 'OUT_FOR_DELIVERY' | 'DELIVERED' | 'UNDELIVERED';
export type ActorRole = 'SYSTEM' | 'STORE_MANAGER' | 'DELIVERY_BOY';

const NEXT: Record<OrderStatus, OrderStatus[]> = {
  PLACED: ['OUT_FOR_DELIVERY'],
  OUT_FOR_DELIVERY: ['DELIVERED', 'UNDELIVERED'],
  DELIVERED: [],
  UNDELIVERED: [],
};

/** FR-G-01, BR-22: no going back and no skipping. */
export function canTransition(from: OrderStatus, to: OrderStatus) {
  return NEXT[from].includes(to);
}

export interface Transition {
  orderId: string;
  from: OrderStatus;
  to: OrderStatus;
  actorRole: ActorRole;
  actorId?: string;
  reason?: string;
  at: Date;
  /** Extra columns to set in the same update, e.g. { delivery_boy_id, assigned_at }. */
  set?: Record<string, unknown>;
}

/**
 * Moves an order only if it is still in the expected status, so when two people act at once
 * only the first change is saved (EX-18). Returns false when the order had already changed.
 */
export async function transitionOrder(q: Queryable, t: Transition): Promise<boolean> {
  if (!canTransition(t.from, t.to)) throw new Error(`Order status cannot change from ${t.from} to ${t.to}`);

  const extra = Object.entries(t.set ?? {});
  const assignments = ['status = $3', 'version = version + 1', ...extra.map(([col], i) => `${col} = $${i + 4}`)];
  const updated = await q.query(
    `UPDATE orders SET ${assignments.join(', ')} WHERE id = $1 AND status = $2 RETURNING id`,
    [t.orderId, t.from, t.to, ...extra.map(([, value]) => value)],
  );
  if (!updated.length) return false;

  await recordStatus(q, t.orderId, t.from, t.to, t.actorRole, t.at, t.actorId, t.reason);
  return true;
}

export function recordStatus(
  q: Queryable,
  orderId: string,
  from: OrderStatus | null,
  to: OrderStatus,
  actorRole: ActorRole,
  at: Date,
  actorId?: string,
  reason?: string,
) {
  return q.query(
    `INSERT INTO order_status_history (id, order_id, from_status, to_status, actor_role, actor_id, reason, at)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
    [randomUUID(), orderId, from, to, actorRole, actorId ?? null, reason ?? null, at],
  );
}
