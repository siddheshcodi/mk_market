import { transitionOrder } from '../src/orders/order-status';
import { addressAt, createTestApp, login, NEAR_BOTH, PRODUCTS, sign, TestContext, WEBHOOK_SECRET } from './helpers';

describe('Payment, order creation and My Orders', () => {
  let ctx: TestContext;
  let token: string;
  const auth = () => ({ authorization: `Bearer ${token}` });

  beforeEach(async () => {
    ctx = await createTestApp();
    token = (await login(ctx, '9876543210')).accessToken;
  });
  afterEach(() => ctx.app.close());

  async function newCheckout() {
    const res = await ctx
      .http()
      .post('/api/v1/checkout')
      .set(auth())
      .send({
        items: [
          { productId: PRODUCTS.milk1l, qty: 2 },
          { productId: PRODUCTS.bread, qty: 1 },
        ],
        address: addressAt(ctx, NEAR_BOTH, { STR001: 2500, STR002: 3800 }),
      })
      .expect(201);
    return res.body.checkoutId as string;
  }
  const startPayment = (checkoutId: string) => ctx.http().post(`/api/v1/checkout/${checkoutId}/payment`).set(auth());
  const confirm = (checkoutId: string, body: object) =>
    ctx.http().post(`/api/v1/checkout/${checkoutId}/payment/confirm`).set(auth()).send(body);
  const webhook = (event: string, payment: { gatewayOrderId: string; gatewayPaymentId: string }, amount: number) => {
    const raw = JSON.stringify({
      event,
      payload: {
        payment: {
          entity: { id: payment.gatewayPaymentId, order_id: payment.gatewayOrderId, amount, currency: 'INR', status: 'captured' },
        },
      },
    });
    return ctx
      .http()
      .post('/api/v1/webhooks/payment')
      .set('content-type', 'application/json')
      .set('x-razorpay-signature', sign(WEBHOOK_SECRET, raw))
      .send(raw);
  };
  const orderCount = async () => (await ctx.db.query(`SELECT id FROM orders`)).length;

  it('TC-U-054, TC-U-057: a successful payment creates one Placed order for the locked store', async () => {
    const checkoutId = await newCheckout();
    const started = (await startPayment(checkoutId).expect(200)).body;
    expect(started).toMatchObject({ gatewayKey: 'rzp_test_fake', amountPaise: 18100, currency: 'INR' });

    const order = (await confirm(checkoutId, ctx.gateway.pay(started.gatewayOrderId)).expect(200)).body;
    expect(order.status).toBe('PLACED');
    expect(order.displayOrderId).toMatch(/^MK261008[A-HJ-NP-Z2-9]{6}$/);

    const [row] = await ctx.db.query(
      `SELECT s.code, o.total_paise FROM orders o JOIN stores s ON s.id = o.store_id WHERE o.id = $1`,
      [order.orderId],
    );
    expect(row).toEqual({ code: 'STR001', total_paise: 18100 });
  });

  it('TC-U-059: a failed payment creates no order', async () => {
    const checkoutId = await newCheckout();
    const { gatewayOrderId } = (await startPayment(checkoutId).expect(200)).body;
    const res = await confirm(checkoutId, ctx.gateway.pay(gatewayOrderId, 'failed')).expect(402);
    expect(res.body.error.code).toBe('PAYMENT_FAILED');
    expect(await orderCount()).toBe(0);
  });

  it('TC-U-060, TC-U-066: a cancelled payment creates no order and the checkout stays open', async () => {
    const checkoutId = await newCheckout();
    await startPayment(checkoutId).expect(200);
    expect((await ctx.http().get(`/api/v1/checkout/${checkoutId}`).set(auth()).expect(200)).body.status).toBe('OPEN');
    expect(await orderCount()).toBe(0);
  });

  it('TC-U-062: retry after a failure creates exactly one order', async () => {
    const checkoutId = await newCheckout();
    const first = (await startPayment(checkoutId).expect(200)).body;
    await confirm(checkoutId, ctx.gateway.pay(first.gatewayOrderId, 'failed')).expect(402);
    const second = (await startPayment(checkoutId).expect(200)).body;
    await confirm(checkoutId, ctx.gateway.pay(second.gatewayOrderId)).expect(200);
    expect(await orderCount()).toBe(1);
  });

  it('TC-U-064, TC-U-065: app confirm, a repeated confirm and the webhook all give the same single order', async () => {
    const checkoutId = await newCheckout();
    const { gatewayOrderId, amountPaise } = (await startPayment(checkoutId).expect(200)).body;
    const payment = ctx.gateway.pay(gatewayOrderId);

    const a = (await confirm(checkoutId, payment).expect(200)).body;
    const b = (await confirm(checkoutId, payment).expect(200)).body;
    await webhook('payment.captured', payment, amountPaise).expect(200);
    expect(b.orderId).toBe(a.orderId);
    expect(await orderCount()).toBe(1);
  });

  it('the webhook alone creates the order when the app never reports back', async () => {
    const checkoutId = await newCheckout();
    const { gatewayOrderId, amountPaise } = (await startPayment(checkoutId).expect(200)).body;
    await webhook('payment.captured', ctx.gateway.pay(gatewayOrderId), amountPaise).expect(200);

    const status = (await ctx.http().get(`/api/v1/checkout/${checkoutId}`).set(auth()).expect(200)).body;
    expect(status.status).toBe('PAID');
    expect(status.displayOrderId).toMatch(/^MK/);
  });

  it('rejects a forged payment signature', async () => {
    const checkoutId = await newCheckout();
    const { gatewayOrderId } = (await startPayment(checkoutId).expect(200)).body;
    const payment = { ...ctx.gateway.pay(gatewayOrderId), signature: 'forged' };
    expect((await confirm(checkoutId, payment).expect(400)).body.error.code).toBe('PAYMENT_VERIFICATION_FAILED');
    expect(await orderCount()).toBe(0);
  });

  it('rejects a webhook with a bad signature', async () => {
    await ctx
      .http()
      .post('/api/v1/webhooks/payment')
      .set('content-type', 'application/json')
      .set('x-razorpay-signature', 'bad')
      .send('{"event":"payment.captured"}')
      .expect(401);
  });

  it('TC-U-063: money captured after the payment window creates no order and is flagged for refund', async () => {
    const checkoutId = await newCheckout();
    const { gatewayOrderId, amountPaise } = (await startPayment(checkoutId).expect(200)).body;
    ctx.clock.advance(16 * 60);
    await webhook('payment.captured', ctx.gateway.pay(gatewayOrderId), amountPaise).expect(200);

    expect(await orderCount()).toBe(0);
    const status = (await ctx.http().get(`/api/v1/checkout/${checkoutId}`).set(auth()).expect(200)).body;
    expect(status.status).toBe('REFUND_PENDING');
    const [payment] = await ctx.db.query(`SELECT status FROM payments`);
    expect(payment.status).toBe('CAPTURED_ORPHAN');
  });

  it('a second captured payment for an already paid checkout is flagged for refund', async () => {
    const checkoutId = await newCheckout();
    const first = (await startPayment(checkoutId).expect(200)).body;
    const second = (await startPayment(checkoutId).expect(200)).body;
    await confirm(checkoutId, ctx.gateway.pay(first.gatewayOrderId)).expect(200);
    await webhook('payment.captured', ctx.gateway.pay(second.gatewayOrderId), second.amountPaise).expect(200);

    expect(await orderCount()).toBe(1);
    const statuses = (await ctx.db.query(`SELECT status FROM payments ORDER BY gateway_order_id`)).map((p) => p.status);
    expect(statuses).toEqual(['CAPTURED', 'CAPTURED_ORPHAN']);
  });

  it('a payment still being processed asks the app to wait and poll', async () => {
    const checkoutId = await newCheckout();
    const { gatewayOrderId } = (await startPayment(checkoutId).expect(200)).body;
    const res = await confirm(checkoutId, ctx.gateway.pay(gatewayOrderId, 'authorized')).expect(202);
    expect(res.body.error.code).toBe('PAYMENT_PENDING');
  });

  it('a checkout cannot be paid after it expires, or paid twice', async () => {
    const expired = await newCheckout();
    ctx.clock.advance(16 * 60);
    expect((await startPayment(expired).expect(409)).body.error.code).toBe('CHECKOUT_EXPIRED');

    const paid = await newCheckout();
    const { gatewayOrderId } = (await startPayment(paid).expect(200)).body;
    await confirm(paid, ctx.gateway.pay(gatewayOrderId)).expect(200);
    expect((await startPayment(paid).expect(409)).body.error.code).toBe('ALREADY_PAID');
  });

  it("another customer's checkout looks like it does not exist", async () => {
    const checkoutId = await newCheckout();
    token = (await login(ctx, '9123456780')).accessToken;
    await startPayment(checkoutId).expect(404);
    await ctx.http().get(`/api/v1/checkout/${checkoutId}`).set(auth()).expect(404);
  });

  describe('My Orders (FR-U-12, FR-U-14)', () => {
    async function placeOrder() {
      const checkoutId = await newCheckout();
      const { gatewayOrderId } = (await startPayment(checkoutId).expect(200)).body;
      return (await confirm(checkoutId, ctx.gateway.pay(gatewayOrderId)).expect(200)).body.orderId as string;
    }

    it('TC-U-070: lists my orders with their status', async () => {
      const orderId = await placeOrder();
      const { body } = await ctx.http().get('/api/v1/orders').set(auth()).expect(200);
      expect(body.items).toEqual([
        expect.objectContaining({ orderId, itemCount: 2, totalPaise: 18100, status: 'PLACED' }),
      ]);
    });

    it('shows order details with items, address and timeline', async () => {
      const orderId = await placeOrder();
      const { body } = await ctx.http().get(`/api/v1/orders/${orderId}`).set(auth()).expect(200);
      expect(body).toMatchObject({
        status: 'PLACED',
        storeName: 'MK Market - Kothrud',
        paidInAdvance: true,
        address: { pincode: '411038', city: 'Pune' },
        timeline: [{ status: 'PLACED' }],
      });
      expect(body.items.map((i: any) => [i.name, i.qty])).toEqual([
        ['Bread', 1],
        ['Milk 1L', 2],
      ]);
    });

    it('TC-U-071: shows the new status after the store sends the order out', async () => {
      const orderId = await placeOrder();
      await transitionOrder(ctx.db, {
        orderId,
        from: 'PLACED',
        to: 'OUT_FOR_DELIVERY',
        actorRole: 'STORE_MANAGER',
        at: ctx.clock.now(),
      });
      const { body } = await ctx.http().get(`/api/v1/orders/${orderId}`).set(auth()).expect(200);
      expect(body.status).toBe('OUT_FOR_DELIVERY');
      expect(body.timeline.map((t: any) => t.status)).toEqual(['PLACED', 'OUT_FOR_DELIVERY']);
    });

    it("TC-U-076: another customer's order returns 404", async () => {
      const orderId = await placeOrder();
      token = (await login(ctx, '9123456780')).accessToken;
      await ctx.http().get(`/api/v1/orders/${orderId}`).set(auth()).expect(404);
      expect((await ctx.http().get('/api/v1/orders').set(auth()).expect(200)).body.items).toEqual([]);
    });

    it('TC-U-074: there is no way to cancel or change an order', async () => {
      const orderId = await placeOrder();
      await ctx.http().delete(`/api/v1/orders/${orderId}`).set(auth()).expect(404);
      await ctx.http().patch(`/api/v1/orders/${orderId}`).set(auth()).send({ status: 'CANCELLED' }).expect(404);
      await ctx.http().post(`/api/v1/orders/${orderId}/cancel`).set(auth()).expect(404);
    });
  });
});
