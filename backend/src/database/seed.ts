import { randomUUID } from 'crypto';
import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';
import { Pool } from 'pg';
import { parse } from 'yaml';
import { MOBILE_PATTERN } from '../common/rules';
import { Db } from './db';

export interface StaffFile {
  stores: {
    code: string;
    name: string;
    address?: string;
    lat: number;
    lng: number;
    active?: boolean;
    manager: { name: string; mobile: string; active?: boolean };
    deliveryBoys?: { code: string; name: string; mobile: string; active?: boolean }[];
  }[];
}

export interface ProductsFile {
  products: { id: string; name: string; unit: string; pricePaise: number; imageUrl?: string; active?: boolean }[];
}

export const CONFIG_DIR = resolve(__dirname, '../../config');

/**
 * FR-G-02, A15: stores, store managers and delivery boys come only from config/staff.yaml.
 * Changing a number means editing that file and deploying. Anyone removed from the file can no longer log in.
 */
export async function loadStaff(db: Db, file: StaffFile) {
  const mobiles = file.stores.flatMap((s) => [s.manager.mobile, ...(s.deliveryBoys ?? []).map((d) => d.mobile)]);
  const bad = mobiles.filter((m) => !MOBILE_PATTERN.test(m));
  if (bad.length) throw new Error(`Invalid staff mobile numbers: ${bad.join(', ')}`);
  const duplicate = mobiles.find((m, i) => mobiles.indexOf(m) !== i);
  if (duplicate) throw new Error(`Staff mobile ${duplicate} is used more than once`);

  await db.tx(async (q) => {
    await q.query(`UPDATE stores SET is_active = FALSE`);
    await q.query(`UPDATE store_managers SET is_active = FALSE`);
    await q.query(`UPDATE delivery_boys SET is_active = FALSE`);

    for (const s of file.stores) {
      const [store] = await q.query<{ id: string }>(
        `INSERT INTO stores (id, code, name, address, lat, lng, is_active) VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, address = EXCLUDED.address,
           lat = EXCLUDED.lat, lng = EXCLUDED.lng, is_active = EXCLUDED.is_active
         RETURNING id`,
        [randomUUID(), s.code, s.name, s.address ?? null, s.lat, s.lng, s.active ?? true],
      );
      const m = s.manager;
      await q.query(
        `INSERT INTO store_managers (id, store_id, name, mobile, is_active) VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (store_id) DO UPDATE SET name = EXCLUDED.name, mobile = EXCLUDED.mobile, is_active = EXCLUDED.is_active`,
        [randomUUID(), store.id, m.name, m.mobile, m.active ?? true],
      );
      for (const d of s.deliveryBoys ?? []) {
        await q.query(
          `INSERT INTO delivery_boys (id, store_id, code, name, mobile, is_active) VALUES ($1, $2, $3, $4, $5, $6)
           ON CONFLICT (code) DO UPDATE SET store_id = EXCLUDED.store_id, name = EXCLUDED.name,
             mobile = EXCLUDED.mobile, is_active = EXCLUDED.is_active`,
          [randomUUID(), store.id, d.code, d.name, d.mobile, d.active ?? true],
        );
      }
    }
  });
}

/** A2: products already exist in the client's system. This loads a file export of them. */
export async function loadProducts(db: Db, file: ProductsFile) {
  await db.tx(async (q) => {
    for (const p of file.products) {
      await q.query(
        `INSERT INTO products (id, name, unit, price_paise, image_url, is_active) VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, unit = EXCLUDED.unit, price_paise = EXCLUDED.price_paise,
           image_url = EXCLUDED.image_url, is_active = EXCLUDED.is_active`,
        [p.id, p.name, p.unit, p.pricePaise, p.imageUrl ?? null, p.active ?? true],
      );
    }
  });
}

if (require.main === module) {
  const db = new Db(new Pool({ connectionString: process.env.DATABASE_URL }));
  const read = (name: string) => parse(readFileSync(resolve(CONFIG_DIR, name), 'utf8'));
  (async () => {
    await loadStaff(db, read('staff.yaml'));
    console.log('Loaded config/staff.yaml');
    if (existsSync(resolve(CONFIG_DIR, 'products.yaml'))) {
      await loadProducts(db, read('products.yaml'));
      console.log('Loaded config/products.yaml');
    }
    await db.close();
  })().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
