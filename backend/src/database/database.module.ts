import { Global, Logger, Module } from '@nestjs/common';
import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';
import { Pool } from 'pg';
import { parse } from 'yaml';
import { APP_CONFIG, AppConfig, MEMORY_DATABASE } from '../config/app-config';
import { Db } from './db';
import { migrate } from './migrate';
import { CONFIG_DIR, loadProducts, loadStaff } from './seed';

/**
 * DATABASE_URL=memory: an in-process database for trying the app locally without PostgreSQL.
 * It loads config/staff.yaml and config/products.yaml (or the .example files) and is lost on restart.
 */
async function memoryDb(): Promise<Db> {
  // Loaded only here: pg-mem is a development dependency.
  const { newDb } = require('pg-mem');
  const { Pool: MemPool } = newDb().adapters.createPg();
  const db = new Db(new MemPool());
  await migrate(db, (f) => f !== '002_search_index.sql', () => {});

  const read = (name: string) => {
    const file = resolve(CONFIG_DIR, existsSync(resolve(CONFIG_DIR, `${name}.yaml`)) ? `${name}.yaml` : `${name}.example.yaml`);
    return parse(readFileSync(file, 'utf8'));
  };
  await loadStaff(db, read('staff'));
  await loadProducts(db, read('products'));
  new Logger('Database').warn('Using the in-memory database: data is lost when the server stops.');
  return db;
}

@Global()
@Module({
  providers: [
    {
      provide: Db,
      inject: [APP_CONFIG],
      useFactory: (config: AppConfig) =>
        config.databaseUrl === MEMORY_DATABASE ? memoryDb() : new Db(new Pool({ connectionString: config.databaseUrl })),
    },
  ],
  exports: [Db],
})
export class DatabaseModule {}
