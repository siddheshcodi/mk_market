import { Pool, PoolClient } from 'pg';

export interface Queryable {
  query<T = any>(sql: string, params?: unknown[]): Promise<T[]>;
}

/** Thin wrapper over pg so services work with plain SQL and explicit transactions. */
export class Db implements Queryable {
  constructor(private readonly pool: Pool) {}

  async query<T = any>(sql: string, params: unknown[] = []): Promise<T[]> {
    return (await this.pool.query(sql, params)).rows as T[];
  }

  async tx<T>(work: (q: Queryable) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await work(clientQueryable(client));
      await client.query('COMMIT');
      return result;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  close() {
    return this.pool.end();
  }
}

function clientQueryable(client: PoolClient): Queryable {
  return { query: async (sql, params = []) => (await client.query(sql, params)).rows };
}
