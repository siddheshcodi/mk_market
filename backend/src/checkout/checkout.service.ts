import { HttpStatus, Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { addSeconds, Clock } from '../common/clock';
import { AppError, Errors } from '../common/errors';
import { CHECKOUT_TTL_SEC } from '../common/rules';
import { Db } from '../database/db';
import { ServiceabilityService } from '../maps/serviceability.service';
import { OrderLine } from '../orders/orders.service';
import { AddressDto, CreateCheckoutDto } from './checkout.dto';

@Injectable()
export class CheckoutService {
  constructor(
    private readonly db: Db,
    private readonly serviceability: ServiceabilityService,
    private readonly clock: Clock,
  ) {}

  /**
   * FR-U-05 to FR-U-08. Prices come from the catalogue, never from the app, and the chosen store
   * and total are locked for CHECKOUT_TTL_SEC so the order goes to the store that was checked (BR-14).
   */
  async create(userId: string, dto: CreateCheckoutDto) {
    if (!dto.items.length) throw Errors.emptyOrder();
    const pin = this.pin(dto.address);

    const ids = dto.items.map((i) => i.productId);
    const placeholders = ids.map((_, i) => `$${i + 1}`).join(', ');
    const products = await this.db.query(
      `SELECT id, name, unit, price_paise FROM products WHERE is_active AND id IN (${placeholders})`,
      ids,
    );
    const byId = new Map(products.map((p) => [p.id, p]));
    const missing = ids.filter((id) => !byId.has(id));
    if (missing.length) throw Errors.productUnavailable(missing);

    const items: OrderLine[] = dto.items.map(({ productId, qty }) => {
      const p = byId.get(productId);
      return {
        productId,
        name: p.name,
        unit: p.unit,
        unitPricePaise: p.price_paise,
        qty,
        lineTotalPaise: p.price_paise * qty,
      };
    });
    // BR-23: no delivery charge and no minimum order value.
    const totalPaise = items.reduce((sum, line) => sum + line.lineTotalPaise, 0);

    const point = await this.serviceability.locate(addressText(dto.address), pin);
    const store = await this.serviceability.nearestStore(point);

    const id = randomUUID();
    const now = this.clock.now();
    const expiresAt = addSeconds(now, CHECKOUT_TTL_SEC);
    const { lat, lng, ...address } = dto.address;
    await this.db.query(
      `INSERT INTO checkouts (id, user_id, store_id, address, lat, lng, road_distance_m, items, total_paise, status, expires_at, created_at)
       VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7, $8::jsonb, $9, 'OPEN', $10, $11)`,
      [id, userId, store.storeId, JSON.stringify(address), point.lat, point.lng, store.roadDistanceMeters, JSON.stringify(items), totalPaise, expiresAt, now],
    );

    return {
      checkoutId: id,
      storeId: store.storeId,
      roadDistanceMeters: store.roadDistanceMeters,
      items,
      totalPaise,
      currency: 'INR',
      expiresAt,
    };
  }

  /** Lets the app find out what happened to a payment, e.g. after losing network or being closed (EX-09). */
  async status(userId: string, checkoutId: string) {
    const [checkout] = await this.db.query(`SELECT id, status, expires_at FROM checkouts WHERE id = $1 AND user_id = $2`, [
      checkoutId,
      userId,
    ]);
    if (!checkout) throw Errors.notFound('Checkout');

    if (checkout.status === 'PAID') {
      const [order] = await this.db.query(`SELECT id, display_id FROM orders WHERE checkout_id = $1`, [checkoutId]);
      return { checkoutId, status: 'PAID', orderId: order.id, displayOrderId: order.display_id };
    }

    const payments = await this.db.query<{ status: string; window_ends_at: Date }>(
      `SELECT status, window_ends_at FROM payments WHERE checkout_id = $1`,
      [checkoutId],
    );
    if (payments.some((p) => p.status === 'CAPTURED_ORPHAN')) {
      // Money was taken but no order was created; support refunds it manually (BR-12).
      return { checkoutId, status: 'REFUND_PENDING' };
    }
    const now = this.clock.now();
    const paymentOpen = payments.some((p) => p.status !== 'CAPTURED' && now <= p.window_ends_at);
    return { checkoutId, status: now > checkout.expires_at && !paymentOpen ? 'EXPIRED' : 'OPEN' };
  }

  private pin(address: AddressDto) {
    const hasLat = address.lat !== undefined;
    const hasLng = address.lng !== undefined;
    if (hasLat !== hasLng) {
      throw new AppError(HttpStatus.BAD_REQUEST, 'INVALID_ADDRESS', 'Please drop the pin on the map again.', {
        fields: [hasLat ? 'lng' : 'lat'],
      });
    }
    return hasLat ? { lat: address.lat!, lng: address.lng! } : undefined;
  }
}

function addressText(a: AddressDto) {
  return [a.house, a.street, a.landmark, `${a.city} ${a.pincode}`, 'India'].filter(Boolean).join(', ');
}
