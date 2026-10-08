import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { createHmac } from 'crypto';
import { newDb } from 'pg-mem';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { configureApp } from '../src/app.setup';
import { addSeconds, Clock } from '../src/common/clock';
import { APP_CONFIG, AppConfig } from '../src/config/app-config';
import { Db } from '../src/database/db';
import { migrate } from '../src/database/migrate';
import { loadProducts, loadStaff } from '../src/database/seed';
import { LatLng } from '../src/maps/geo';
import { MapsProvider, MapsUnavailableError } from '../src/maps/maps-provider';
import { GatewayPayment, PaymentGateway } from '../src/payment/payment-gateway';
import { SmsSender } from '../src/sms/sms-sender';
import { Errors } from '../src/common/errors';

export class FakeClock extends Clock {
  current = new Date('2026-10-08T05:30:00.000Z');
  now() {
    return new Date(this.current);
  }
  advance(seconds: number) {
    this.current = addSeconds(this.current, seconds);
  }
}

export class FakeSms extends SmsSender {
  sent: { mobile: string; otp: string; kind: 'login' | 'delivery' }[] = [];
  fail = false;

  async sendLoginOtp(mobile: string, otp: string) {
    if (this.fail) throw Errors.smsSendFailed();
    this.sent.push({ mobile, otp, kind: 'login' });
  }
  async sendDeliveryOtp(mobile: string, _order: string, otp: string) {
    if (this.fail) throw Errors.smsSendFailed();
    this.sent.push({ mobile, otp, kind: 'delivery' });
  }
  lastOtp(mobile: string, kind: 'login' | 'delivery' = 'login') {
    return [...this.sent].reverse().find((s) => s.mobile === mobile && s.kind === kind)!.otp;
  }
  count(kind: 'login' | 'delivery') {
    return this.sent.filter((s) => s.kind === kind).length;
  }
}

/** Road distances per address, keyed by store code. Missing store = no route. */
export class FakeMaps extends MapsProvider {
  roads = new Map<string, Record<string, number>>();
  geocoded = new Map<string, LatLng>();
  storeCodeByPoint = new Map<string, string>();
  down = false;
  calls = 0;

  async geocode(address: string) {
    if (this.down) throw new MapsUnavailableError('down');
    return this.geocoded.get(address) ?? null;
  }
  async roadDistancesMeters(origins: LatLng[], destination: LatLng) {
    this.calls++;
    if (this.down) throw new MapsUnavailableError('down');
    const roads = this.roads.get(key(destination)) ?? {};
    return origins.map((o) => roads[this.storeCodeByPoint.get(key(o))!] ?? null);
  }
}

export const WEBHOOK_SECRET = 'test_webhook_secret';
const KEY_SECRET = 'test_key_secret';

export class FakeGateway extends PaymentGateway {
  readonly keyId = 'rzp_test_fake';
  orders = new Map<string, number>();
  payments = new Map<string, GatewayPayment>();
  private seq = 0;

  async createOrder(amountPaise: number) {
    const id = `order_${++this.seq}`;
    this.orders.set(id, amountPaise);
    return id;
  }
  async fetchPayment(id: string) {
    const p = this.payments.get(id);
    if (!p) throw new Error(`unknown payment ${id}`);
    return p;
  }
  verifyCheckoutSignature(orderId: string, paymentId: string, signature: string) {
    return signature === sign(KEY_SECRET, `${orderId}|${paymentId}`);
  }
  verifyWebhookSignature(rawBody: Buffer, signature: string) {
    return signature === sign(WEBHOOK_SECRET, rawBody);
  }

  /** Simulates the customer completing (or failing) payment in the gateway screen. */
  pay(gatewayOrderId: string, status = 'captured', amountPaise = this.orders.get(gatewayOrderId)!) {
    const id = `pay_${++this.seq}`;
    this.payments.set(id, { id, gatewayOrderId, amountPaise, currency: 'INR', status });
    return { gatewayOrderId, gatewayPaymentId: id, signature: sign(KEY_SECRET, `${gatewayOrderId}|${id}`) };
  }
}

export function sign(secret: string, data: string | Buffer) {
  return createHmac('sha256', secret).update(data).digest('hex');
}

export const key = (p: LatLng) => `${p.lat.toFixed(5)},${p.lng.toFixed(5)}`;

export const STORE_A = { code: 'STR001', lat: 18.5074, lng: 73.8077 };
export const STORE_B = { code: 'STR002', lat: 18.53, lng: 73.8077 };

export const PRODUCTS = {
  milk1l: '6f1b0a52-0001-4d7e-9a11-000000000001',
  milk500: '6f1b0a52-0002-4d7e-9a11-000000000002',
  bread: '6f1b0a52-0003-4d7e-9a11-000000000003',
  rice: '6f1b0a52-0004-4d7e-9a11-000000000004',
  discontinued: '6f1b0a52-0005-4d7e-9a11-000000000005',
};

export const STAFF = {
  managerA: '9000000001',
  managerB: '9000000002',
  deliveryA1: '9000000011',
  deliveryA2: '9000000012',
  deliveryAInactive: '9000000019',
  deliveryB1: '9000000021',
};

export async function createTestApp() {
  const mem = newDb();
  const { Pool } = mem.adapters.createPg();
  const db = new Db(new Pool());
  // 002 needs pg_trgm, which pg-mem doesn't have.
  await migrate(db, (f) => f !== "002_search_index.sql", () => {});
  await loadStaff(db, {
    stores: [
      {
        ...STORE_A,
        name: 'MK Market - Kothrud',
        manager: { name: 'Manager A', mobile: STAFF.managerA },
        deliveryBoys: [
          { code: 'DB001', name: 'Delivery A1', mobile: STAFF.deliveryA1 },
          { code: 'DB002', name: 'Delivery A2', mobile: STAFF.deliveryA2 },
          { code: 'DB009', name: 'Delivery A9 (left)', mobile: STAFF.deliveryAInactive, active: false },
        ],
      },
      {
        ...STORE_B,
        name: 'MK Market - Aundh',
        manager: { name: 'Manager B', mobile: STAFF.managerB },
        deliveryBoys: [{ code: 'DB003', name: 'Delivery B1', mobile: STAFF.deliveryB1 }],
      },
    ],
  });
  await loadProducts(db, {
    products: [
      { id: PRODUCTS.milk1l, name: 'Milk 1L', unit: '1 L', pricePaise: 6800 },
      { id: PRODUCTS.milk500, name: 'Milk 500ml', unit: '500 ml', pricePaise: 3500 },
      { id: PRODUCTS.bread, name: 'Bread', unit: '400 g', pricePaise: 4500 },
      { id: PRODUCTS.rice, name: 'Rice 5kg', unit: '5 kg', pricePaise: 42000 },
      { id: PRODUCTS.discontinued, name: 'Old Biscuits', unit: '100 g', pricePaise: 1000, active: false },
    ],
  });

  const config: AppConfig = {
    env: 'test',
    port: 0,
    databaseUrl: 'pg-mem',
    jwtSecret: 'test-jwt-secret-that-is-long-enough-0000',
    otpSecret: 'test-otp-secret-that-is-long-enough-0000',
    devFixedOtp: false,
    maps: { provider: 'dev' },
    sms: { provider: 'console' },
    corsOrigins: [],
    payment: { provider: 'razorpay', razorpayKeyId: 'x', razorpayKeySecret: KEY_SECRET, razorpayWebhookSecret: WEBHOOK_SECRET },
  };
  const clock = new FakeClock();
  const sms = new FakeSms();
  const maps = new FakeMaps();
  maps.storeCodeByPoint.set(key(STORE_A), STORE_A.code);
  maps.storeCodeByPoint.set(key(STORE_B), STORE_B.code);
  const gateway = new FakeGateway();

  const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
    .overrideProvider(APP_CONFIG)
    .useValue(config)
    .overrideProvider(Db)
    .useValue(db)
    .overrideProvider(Clock)
    .useValue(clock)
    .overrideProvider(SmsSender)
    .useValue(sms)
    .overrideProvider(MapsProvider)
    .useValue(maps)
    .overrideProvider(PaymentGateway)
    .useValue(gateway)
    .compile();

  const app = configureApp(moduleRef.createNestApplication({ rawBody: true, logger: false }));
  await app.init();
  return { app, db, clock, sms, maps, gateway, http: () => request(app.getHttpServer()) };
}

export type TestContext = Awaited<ReturnType<typeof createTestApp>>;

export async function login(ctx: TestContext, mobile: string, role = 'USER') {
  const req = await ctx.http().post('/api/v1/auth/otp/request').send({ mobile, role }).expect(200);
  const res = await ctx
    .http()
    .post('/api/v1/auth/otp/verify')
    .send({ requestId: req.body.requestId, otp: ctx.sms.lastOtp(mobile) })
    .expect(200);
  // Next login for the same number must wait out the resend gap.
  ctx.clock.advance(31);
  return res.body as { accessToken: string; refreshToken: string; user?: { id: string } };
}

/** A pin with known road distances (metres) to each store. */
export function addressAt(ctx: TestContext, pin: LatLng, roads: Record<string, number>) {
  ctx.maps.roads.set(key(pin), roads);
  return {
    name: 'Asha Kulkarni',
    house: 'Flat 12',
    street: 'Paud Road',
    city: 'Pune',
    pincode: '411038',
    lat: pin.lat,
    lng: pin.lng,
  };
}

/** About 0.85 km straight-line from store A and 1.7 km from store B. */
export const NEAR_BOTH = { lat: 18.515, lng: 73.8077 };

/**
 * Places and pays for an order as the given customer. Road distances decide the store
 * (default: store A at 2.5 km, store B at 3.8 km).
 */
export async function placeOrder(
  ctx: TestContext,
  customerToken: string,
  roads: Record<string, number> = { STR001: 2500, STR002: 3800 },
) {
  const authHeader = { authorization: `Bearer ${customerToken}` };
  const checkout = await ctx
    .http()
    .post('/api/v1/checkout')
    .set(authHeader)
    .send({
      items: [
        { productId: PRODUCTS.milk1l, qty: 2 },
        { productId: PRODUCTS.bread, qty: 1 },
      ],
      address: addressAt(ctx, NEAR_BOTH, roads),
    })
    .expect(201);
  const checkoutId = checkout.body.checkoutId;
  const started = await ctx.http().post(`/api/v1/checkout/${checkoutId}/payment`).set(authHeader).expect(200);
  const order = await ctx
    .http()
    .post(`/api/v1/checkout/${checkoutId}/payment/confirm`)
    .set(authHeader)
    .send(ctx.gateway.pay(started.body.gatewayOrderId))
    .expect(200);
  return order.body as { orderId: string; displayOrderId: string };
}

export async function deliveryBoyId(ctx: TestContext, code: string) {
  return (await ctx.db.query(`SELECT id FROM delivery_boys WHERE code = $1`, [code]))[0].id as string;
}

/** Store manager assigns the order to the delivery boy with this code. */
export async function dispatchTo(ctx: TestContext, managerToken: string, orderId: string, code: string) {
  await ctx
    .http()
    .post(`/api/v1/store/orders/${orderId}/dispatch`)
    .set({ authorization: `Bearer ${managerToken}` })
    .set('idempotency-key', `dispatch-${orderId}`)
    .send({ deliveryBoyId: await deliveryBoyId(ctx, code) })
    .expect(200);
}
