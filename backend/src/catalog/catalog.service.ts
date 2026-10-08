import { Injectable } from '@nestjs/common';
import { Db } from '../database/db';

export interface ProductRow {
  id: string;
  name: string;
  unit: string;
  price_paise: number;
  image_url: string | null;
}

const MIN_QUERY_LENGTH = 2;

/** LIKE treats % and _ as wildcards; escape them so they match literally. */
function escapeLike(text: string) {
  return text.replace(/[\\%_]/g, (c) => `\\${c}`);
}

@Injectable()
export class CatalogService {
  constructor(private readonly db: Db) {}

  /** FR-U-03, FR-U-04, A4: search by product name only. Names starting with the query come first. */
  async search(rawQuery: string, page: number, size: number) {
    const q = rawQuery.trim().replace(/\s+/g, ' ');
    // An empty list makes the app show "No products found" (EX-05).
    if (q.length < MIN_QUERY_LENGTH) return { items: [], page, hasMore: false };

    const term = escapeLike(q);
    const rows = await this.db.query<ProductRow>(
      `SELECT id, name, unit, price_paise, image_url FROM products
       WHERE is_active AND name ILIKE $1
       ORDER BY (name ILIKE $2) DESC, name, id
       LIMIT $3 OFFSET $4`,
      [`%${term}%`, `${term}%`, size + 1, (page - 1) * size],
    );
    return {
      items: rows.slice(0, size).map((p) => ({
        id: p.id,
        name: p.name,
        unit: p.unit,
        pricePaise: p.price_paise,
        imageUrl: p.image_url,
      })),
      page,
      hasMore: rows.length > size,
    };
  }
}
