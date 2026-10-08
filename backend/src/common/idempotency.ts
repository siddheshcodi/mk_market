import { createParamDecorator, ExecutionContext, HttpStatus } from '@nestjs/common';
import { Queryable } from '../database/db';
import { AppError } from './errors';

/** Results are kept for a day; a retry later than that is treated as a new request. */
export const IDEMPOTENCY_TTL_SEC = 24 * 60 * 60;

export interface IdempotencyScope {
  actorId: string;
  endpoint: string;
  key: string;
}

/** Reads the required Idempotency-Key header (8 to 100 characters, e.g. a UUID made per tap). */
export const IdempotencyKey = createParamDecorator((_: unknown, ctx: ExecutionContext): string => {
  const key = ctx.switchToHttp().getRequest().headers['idempotency-key'];
  if (typeof key !== 'string' || key.length < 8 || key.length > 100) {
    throw new AppError(HttpStatus.BAD_REQUEST, 'INVALID_INPUT', 'Please try again.', { fields: ['Idempotency-Key'] });
  }
  return key;
});

export async function savedResponse<T>(q: Queryable, scope: IdempotencyScope, now: Date): Promise<T | undefined> {
  const [row] = await q.query<{ response: T }>(
    `SELECT response FROM idempotency_keys WHERE actor_id = $1 AND endpoint = $2 AND key = $3 AND created_at > $4`,
    [scope.actorId, scope.endpoint, scope.key, new Date(now.getTime() - IDEMPOTENCY_TTL_SEC * 1000)],
  );
  return row?.response;
}

export async function saveResponse(q: Queryable, scope: IdempotencyScope, response: unknown, now: Date) {
  await q.query(
    `INSERT INTO idempotency_keys (actor_id, endpoint, key, response, created_at) VALUES ($1, $2, $3, $4::jsonb, $5)
     ON CONFLICT (actor_id, endpoint, key) DO UPDATE SET response = EXCLUDED.response, created_at = EXCLUDED.created_at`,
    [scope.actorId, scope.endpoint, scope.key, JSON.stringify(response), now],
  );
}
