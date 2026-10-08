import { randomUUID } from 'crypto';
import { loadStaff, StaffFile } from '../src/database/seed';
import { transitionOrder } from '../src/orders/order-status';
import {
  addressAt,
  createTestApp,
  deliveryBoyId,
  login,
  NEAR_BOTH,
  placeOrder,
  PRODUCTS,
  STAFF,
  STORE_A,
  STORE_B,
  TestContext,
} from './helpers';

describe('Store module (FR-S-01 to FR-S-06)', () => {
  let ctx: TestContext;
  let customer: string;
  let managerA: string;
  let managerB: string;

  beforeEach(async () => {
    ctx = await createTestApp();
    customer = (await login(ctx, '9876543210')).accessToken;
    managerA = (await login(ctx, STAFF.managerA, 'STORE_MANAGER')).accessToken;
    managerB = (await login(ctx, STAFF.managerB, 'STORE_MANAGER')).accessToken;
  });
  afterEach(() => ctx.app.close());

  const as = (token: string) => ({ authorization: `Bearer ${token}` });
  const tab = (token: string, status = 'PLACED', extra: Record<string, string> = {}) =>
    ctx.http().get('/api/v1/store/orders').query({ status, ...extra }).set(as(token)).expect(200);
  const details = (token: string, orderId: string) => ctx.http().get(`/api/v1/store/orders/${orderId}`).set(as(token));
  const dispatch = (token: string, orderId: string, deliveryBoyId: string, key: string = randomUUID()) =>
    ctx
      .http()
      .post(`/api/v1/store/orders/${orderId}/dispatch`)
      .set(as(token))
      .set('idempotency-key', key)
      .send({ deliveryBoyId });

  describe('Receiving orders (FR-S-02, FR-S-03, BR-14)', () => {
    it("TC-S-010, TC-S-011, TC-S-015: an order shows only in the nearest store's New tab", async () => {
      const order = await placeOrder(ctx, customer);
      const a = (await tab(managerA)).body;
      expect(a.items).toEqual([
        expect.objectContaining({
          orderId: order.orderId,
          displayOrderId: order.displayOrderId,
          status: 'PLACED',
          itemCount: 2,
          totalPaise: 18100,
          area: 'Paud Road',
          pincode: '411038',
        }),
      ]);
      expect((await tab(managerB)).body.items).toEqual([]);
    });

    it('routes to store B when B is nearer by road', async () => {
      await placeOrder(ctx, customer, { STR001: 3900, STR002: 1200 });
      expect((await tab(managerA)).body.items).toHaveLength(0);
      expect((await tab(managerB)).body.items).toHaveLength(1);
    });

    it('TC-S-013, TC-S-014: unpaid and failed payments never reach the store', async () => {
      const startCheckout = async () => {
        const checkout = await ctx
          .http()
          .post('/api/v1/checkout')
          .set(as(customer))
          .send({ items: [{ productId: PRODUCTS.bread, qty: 1 }], address: addressAt(ctx, NEAR_BOTH, { STR001: 2500 }) })
          .expect(201);
        const id = checkout.body.checkoutId;
        const started = await ctx.http().post(`/api/v1/checkout/${id}/payment`).set(as(customer)).expect(200);
        return { id, gatewayOrderId: started.body.gatewayOrderId };
      };

      await startCheckout(); // customer leaves the payment screen
      const failed = await startCheckout();
      await ctx
        .http()
        .post(`/api/v1/checkout/${failed.id}/payment/confirm`)
        .set(as(customer))
        .send(ctx.gateway.pay(failed.gatewayOrderId, 'failed'))
        .expect(402);

      expect((await tab(managerA)).body.items).toEqual([]);
    });

    it('TC-S-016, EX-11: the New tab lists every waiting order, oldest first', async () => {
      const first = await placeOrder(ctx, customer);
      ctx.clock.advance(60);
      const second = await placeOrder(ctx, customer);
      ctx.clock.advance(60);
      const third = await placeOrder(ctx, customer);
      const ids = (await tab(managerA)).body.items.map((o: any) => o.orderId);
      expect(ids).toEqual([first.orderId, second.orderId, third.orderId]);
    });

    it('NFR-08: polling with "since" returns only orders placed after the last check', async () => {
      await placeOrder(ctx, customer);
      const { serverTime } = (await tab(managerA)).body;
      ctx.clock.advance(5);
      const newer = await placeOrder(ctx, customer);
      const res = (await tab(managerA, 'PLACED', { since: serverTime })).body;
      expect(res.items.map((o: any) => o.orderId)).toEqual([newer.orderId]);
    });
  });

  describe('Order details and time (FR-S-04, D4)', () => {
    it('TC-S-017 to TC-S-020: shows items, address, customer contact and the order placed time', async () => {
      const placedAt = ctx.clock.now().toISOString();
      const order = await placeOrder(ctx, customer);
      const { body } = await details(managerA, order.orderId).expect(200);
      expect(body).toMatchObject({
        displayOrderId: order.displayOrderId,
        status: 'PLACED',
        placedAt,
        totalPaise: 18100,
        customer: { name: 'Asha Kulkarni', mobile: '9876543210' },
        address: { house: 'Flat 12', street: 'Paud Road', city: 'Pune', pincode: '411038' },
        payment: { paidInAdvance: true },
        deliveryBoy: null,
        timeline: [{ status: 'PLACED', at: placedAt }],
      });
      const [payment] = await ctx.db.query(`SELECT gateway_payment_id FROM payments`);
      expect(body.payment.gatewayReference).toBe(payment.gateway_payment_id.slice(-6));
      expect(body.items.map((i: any) => [i.name, i.qty, i.lineTotalPaise])).toEqual([
        ['Bread', 1, 4500],
        ['Milk 1L', 2, 13600],
      ]);
    });

    it("TC-S-030, TC-S-044: another store's order returns 404", async () => {
      const order = await placeOrder(ctx, customer);
      await details(managerB, order.orderId).expect(404);
      await details(managerB, 'not-a-uuid').expect(404);
    });
  });

  describe('Delivery boys list (FR-S-05, BR-16, A7)', () => {
    it('TC-S-024: lists only active delivery boys of my store with their current order count', async () => {
      const order = await placeOrder(ctx, customer);
      await dispatch(managerA, order.orderId, await deliveryBoyId(ctx, 'DB001')).expect(200);

      const { body } = await ctx.http().get('/api/v1/store/delivery-boys').set(as(managerA)).expect(200);
      expect(body.items.map((b: any) => [b.code, b.activeOrders])).toEqual([
        ['DB001', 1],
        ['DB002', 0],
      ]);
    });
  });

  describe('Dispatch: assign and send out in one step (FR-S-05, A8)', () => {
    it('TC-S-021, TC-S-022: assigning sets "On the way for delivery" at once and records who did it', async () => {
      const order = await placeOrder(ctx, customer);
      ctx.clock.advance(10 * 60);
      const db001 = await deliveryBoyId(ctx, 'DB001');

      const { body } = await dispatch(managerA, order.orderId, db001).expect(200);
      expect(body).toMatchObject({
        orderId: order.orderId,
        status: 'OUT_FOR_DELIVERY',
        deliveryBoy: { id: db001, name: 'Delivery A1', mobile: STAFF.deliveryA1 },
      });

      expect((await tab(managerA)).body.items).toEqual([]);
      const onTheWay = (await tab(managerA, 'OUT_FOR_DELIVERY')).body.items;
      expect(onTheWay).toEqual([expect.objectContaining({ orderId: order.orderId, deliveryBoyName: 'Delivery A1' })]);

      const history = await ctx.db.query(`SELECT to_status, actor_role FROM order_status_history WHERE to_status = 'OUT_FOR_DELIVERY'`);
      expect(history).toEqual([{ to_status: 'OUT_FOR_DELIVERY', actor_role: 'STORE_MANAGER' }]);

      const customerView = await ctx.http().get(`/api/v1/orders/${order.orderId}`).set(as(customer)).expect(200);
      expect(customerView.body.status).toBe('OUT_FOR_DELIVERY');
    });

    it("TC-S-025: a delivery boy from another store can't be assigned", async () => {
      const order = await placeOrder(ctx, customer);
      const res = await dispatch(managerA, order.orderId, await deliveryBoyId(ctx, 'DB003')).expect(422);
      expect(res.body.error.code).toBe('DELIVERY_BOY_NOT_IN_STORE');
    });

    it("an inactive delivery boy can't be assigned", async () => {
      const order = await placeOrder(ctx, customer);
      const res = await dispatch(managerA, order.orderId, await deliveryBoyId(ctx, 'DB009')).expect(422);
      expect(res.body.error.code).toBe('DELIVERY_BOY_INACTIVE');
    });

    it('TC-S-027: a delivery boy must be chosen', async () => {
      const order = await placeOrder(ctx, customer);
      const res = await ctx
        .http()
        .post(`/api/v1/store/orders/${order.orderId}/dispatch`)
        .set(as(managerA))
        .set('idempotency-key', randomUUID())
        .send({})
        .expect(400);
      expect(res.body.error.fields).toEqual(['deliveryBoyId']);
    });

    it('an Idempotency-Key is required', async () => {
      const order = await placeOrder(ctx, customer);
      await ctx
        .http()
        .post(`/api/v1/store/orders/${order.orderId}/dispatch`)
        .set(as(managerA))
        .send({ deliveryBoyId: await deliveryBoyId(ctx, 'DB001') })
        .expect(400);
    });

    it('TC-S-028, TC-S-035: an order already on the way cannot be assigned again', async () => {
      const order = await placeOrder(ctx, customer);
      await dispatch(managerA, order.orderId, await deliveryBoyId(ctx, 'DB001')).expect(200);
      const res = await dispatch(managerA, order.orderId, await deliveryBoyId(ctx, 'DB002')).expect(409);
      expect(res.body.error).toMatchObject({ code: 'ORDER_STATE_CHANGED', currentStatus: 'OUT_FOR_DELIVERY' });
    });

    it('TC-S-029: there is no limit on orders per delivery boy', async () => {
      const db001 = await deliveryBoyId(ctx, 'DB001');
      for (let i = 0; i < 6; i++) {
        const order = await placeOrder(ctx, customer);
        await dispatch(managerA, order.orderId, db001).expect(200);
      }
    });

    it("TC-S-030: another store's manager can't assign the order", async () => {
      const order = await placeOrder(ctx, customer);
      await dispatch(managerB, order.orderId, await deliveryBoyId(ctx, 'DB003')).expect(404);
    });

    it('TC-S-031, EX-18: two simultaneous dispatches save only the first', async () => {
      const order = await placeOrder(ctx, customer);
      const [r1, r2] = await Promise.all([
        dispatch(managerA, order.orderId, await deliveryBoyId(ctx, 'DB001')),
        dispatch(managerA, order.orderId, await deliveryBoyId(ctx, 'DB002')),
      ]);
      expect([r1.status, r2.status].sort()).toEqual([200, 409]);
      const history = await ctx.db.query(`SELECT id FROM order_status_history WHERE to_status = 'OUT_FOR_DELIVERY'`);
      expect(history).toHaveLength(1);
    });

    it('TC-S-032: a double tap with the same key returns the same result and changes the order once', async () => {
      const order = await placeOrder(ctx, customer);
      const db001 = await deliveryBoyId(ctx, 'DB001');
      const key = randomUUID();
      const first = (await dispatch(managerA, order.orderId, db001, key).expect(200)).body;
      ctx.clock.advance(2);
      const second = (await dispatch(managerA, order.orderId, db001, key).expect(200)).body;
      expect(second).toEqual(first);
      const [row] = await ctx.db.query(`SELECT version FROM orders WHERE id = $1`, [order.orderId]);
      expect(row.version).toBe(2);
    });
  });

  describe('No reject or cancel (FR-S-06, BR-13)', () => {
    it.each([
      ['post', 'reject'],
      ['post', 'cancel'],
      ['post', 'status'],
      ['patch', ''],
      ['delete', ''],
    ])('TC-S-033 to TC-S-036: %s /store/orders/:id/%s does not exist', async (method, action) => {
      const order = await placeOrder(ctx, customer);
      const path = `/api/v1/store/orders/${order.orderId}${action ? `/${action}` : ''}`;
      await (ctx.http() as any)[method](path).set(as(managerA)).send({ status: 'DELIVERED' }).expect(404);
    });
  });

  describe('Waiting and returned orders (EX-11, EX-12, BR-21)', () => {
    it('TC-S-037, TC-S-038: an order nobody acts on stays Placed', async () => {
      const order = await placeOrder(ctx, customer);
      ctx.clock.advance(6 * 3600);
      expect((await details(managerA, order.orderId).expect(200)).body.status).toBe('PLACED');
    });

    it('TC-S-040: an undelivered order shows in the Returned tab with the reason', async () => {
      const order = await placeOrder(ctx, customer);
      await dispatch(managerA, order.orderId, await deliveryBoyId(ctx, 'DB001')).expect(200);
      await transitionOrder(ctx.db, {
        orderId: order.orderId,
        from: 'OUT_FOR_DELIVERY',
        to: 'UNDELIVERED',
        actorRole: 'SYSTEM',
        reason: 'OTP_ATTEMPTS_EXCEEDED',
        at: ctx.clock.now(),
        set: { closed_at: ctx.clock.now(), undelivered_reason: 'OTP_ATTEMPTS_EXCEEDED' },
      });
      const returned = (await tab(managerA, 'UNDELIVERED')).body.items;
      expect(returned).toEqual([
        expect.objectContaining({ orderId: order.orderId, undeliveredReason: 'OTP_ATTEMPTS_EXCEEDED' }),
      ]);
      expect((await details(managerA, order.orderId).expect(200)).body.undeliveredReason).toBe('OTP_ATTEMPTS_EXCEEDED');
    });

    it('the Delivered tab shows the last 7 days', async () => {
      const order = await placeOrder(ctx, customer);
      await dispatch(managerA, order.orderId, await deliveryBoyId(ctx, 'DB001')).expect(200);
      await transitionOrder(ctx.db, {
        orderId: order.orderId,
        from: 'OUT_FOR_DELIVERY',
        to: 'DELIVERED',
        actorRole: 'SYSTEM',
        at: ctx.clock.now(),
        set: { closed_at: ctx.clock.now() },
      });
      expect((await tab(managerA, 'DELIVERED')).body.items).toHaveLength(1);
      ctx.clock.advance(8 * 24 * 3600);
      expect((await tab(managerA, 'DELIVERED')).body.items).toHaveLength(0);
    });
  });

  describe('Access (NFR-03, A15)', () => {
    it('TC-S-042, TC-S-043: managers and customers only reach their own module', async () => {
      await ctx.http().get('/api/v1/orders').set(as(managerA)).expect(403);
      await ctx.http().get('/api/v1/store/orders').set(as(customer)).expect(403);
      const delivery = (await login(ctx, STAFF.deliveryA1, 'DELIVERY_BOY')).accessToken;
      await ctx.http().get('/api/v1/store/orders').set(as(delivery)).expect(403);
    });

    it('a manager removed from staff.yaml loses access at the next token refresh', async () => {
      const tokens = await login(ctx, STAFF.managerA, 'STORE_MANAGER');
      const staff: StaffFile = {
        stores: [
          { ...STORE_A, name: 'MK Market - Kothrud', manager: { name: 'New Manager', mobile: '9000000099' } },
          { ...STORE_B, name: 'MK Market - Aundh', manager: { name: 'Manager B', mobile: STAFF.managerB } },
        ],
      };
      await loadStaff(ctx.db, staff);
      await ctx.http().post('/api/v1/auth/token/refresh').send({ refreshToken: tokens.refreshToken }).expect(401);
      await ctx.http().post('/api/v1/auth/otp/request').send({ mobile: STAFF.managerA, role: 'STORE_MANAGER' }).expect(403);
    });
  });
});
