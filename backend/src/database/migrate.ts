import { readdirSync, readFileSync } from 'fs';
import { join, resolve } from 'path';
import { Pool } from 'pg';
import { Db } from './db';

export const MIGRATIONS_DIR = resolve(__dirname, '../../migrations');

/** Applies .sql files in name order, once each. */
export async function migrate(db: Db, only?: (file: string) => boolean, log: (msg: string) => void = console.log) {
  const files = readdirSync(MIGRATIONS_DIR)
    .filter((f) => f.endsWith('.sql') && (!only || only(f)))
    .sort();
  const hasTable = await db.query(`SELECT 1 FROM information_schema.tables WHERE table_name = 'schema_migrations'`);
  const applied = new Set(
    hasTable.length ? (await db.query<{ name: string }>('SELECT name FROM schema_migrations')).map((r) => r.name) : [],
  );

  for (const file of files) {
    if (applied.has(file)) continue;
    await db.tx(async (q) => {
      await q.query(readFileSync(join(MIGRATIONS_DIR, file), 'utf8'));
      await q.query('INSERT INTO schema_migrations (name, applied_at) VALUES ($1, $2)', [file, new Date()]);
    });
    log(`Applied ${file}`);
  }
}

if (require.main === module) {
  const db = new Db(new Pool({ connectionString: process.env.DATABASE_URL }));
  migrate(db)
    .then(() => db.close())
    .catch((err) => {
      console.error(err);
      process.exit(1);
    });
}
