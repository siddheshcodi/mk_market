import { randomUUID } from 'crypto';
import { createTestApp, dispatchTo, login, placeOrder, STAFF, TestContext } from './helpers';

const CUSTOMER = '9876543210';

describe('Delivery Boy module (FR-D-01 to FR-D-10)', () => {
  let ctx: TestContext;
  let customer: string;
  let managerA: string;
  let deliveryA1: string;
  let deliveryA2: string;

  beforeEach(async () => {
    ctx = await createTestApp();
    customer = (await login(ctx, CUSTOMER)).accessToken;
    managerA = (await login(ctx, STAFF.managerA, 'STORE_MANAGER')).accessToken;
    deliveryA1 = (await login(ctx, STAFF.deliveryA1, 'DELIVERY_BOY')).accessToken;
    deliveryA2 = (await login(ctx, STAFF.deliveryA2, 'DELIVERY_BOY')).accessToken;
  });
  afterEach(() => ctx.app.close());

  const as = (token: string) => ({ authorization: `Bearer ${token}` });
  const base = (orderId: string) => `/api/v1/delivery/orders/${orderId}`;
  const list = (token: string, tab = 'ACTIVE') =>
    ctx.http().get('/api/v1/delivery/orders').query({ tab }).set(as(token)).expect(200);
  const details = (token: string, orderId: string) => ctx.http().get(base(orderId)).set(as(token));
  const sendOtp = (orderId: string, token = deliveryA1) => ctx.http().post(`${base(orderId)}/delivery-otp`).set(as(token));
  const resend = (orderId: string, token = deliveryA1) =>
    ctx.http().post(`${base(orderId)}/delivery-otp/resend`).set(as(token));
  const verify = (orderId: string, otp: string, key: string = randomUUID(), token = deliveryA1) =>
    ctx.http().post(`${base(orderId)}/delivery-otp/verify`).set(as(token)).set('idempotency-key', key).send({ otp });
  const customerOtp = () => ctx.sms.lastOtp(CUSTOMER, 'delivery');
  const wrong = (otp: string, n = 1) => String((Number(otp) + n) % 10000).padStart(4, '0');
  const customerView = async (orderId: string) =>
    (await ctx.http().get(`/api/v1/orders/${orderId}`).set(as(customer)).expect(200)).body;

  /** A paid order, dispatched by store A to the given delivery boy. */
  async function assigned(code = 'DB001') {
    const { orderId } = await placeOrder(ctx, customer);
    await dispatchTo(ctx, managerA, orderId, code);
    return orderId;
  }

  describe('Assigned orders (FR-D-02, FR-D-03, BR-17, NFR-04)', () => {
    it('TC-D-008, TC-D-009: shows only orders assigned to me', async () => {
      await placeOrder(ctx, customer); // still with the store
      const orderId = await assigned();
      const { body } = await list(deliveryA1);
      expect(body.items).toEqual([
        expect.objectContaining({
          orderId,
          status: 'OUT_FOR_DELIVERY',
          customerName: 'Asha Kulkarni',
          area: 'Paud Road',
          pincode: '411038',
          itemCount: 2,
          deliveryOtpActive: false,
        }),
      ]);
    });

    it("TC-D-010 to TC-D-012: other delivery boys can't see or act on my order", async () => {
      const orderId = await assigned();
      const deliveryB1 = (await login(ctx, STAFF.deliveryB1, 'DELIVERY_BOY')).accessToken;
      expect((await list(deliveryA2)).body.items).toEqual([]);
      expect((await list(deliveryB1)).body.items).toEqual([]);
      await details(deliveryA2, orderId).expect(404);
      await sendOtp(orderId, deliveryA2).expect(404);
      await verify(orderId, '1234', randomUUID(), deliveryA2).expect(404);
      expect(ctx.sms.count('delivery')).toBe(0);
    });

    it("TC-D-013, TC-D-014: shows the customer's name, mobile, full address and map pin", async () => {
      const orderId = await assigned();
      const { body } = await details(deliveryA1, orderId).expect(200);
      expect(body).toMatchObject({
        status: 'OUT_FOR_DELIVERY',
        customer: { name: 'Asha Kulkarni', mobile: CUSTOMER },
        address: { house: 'Flat 12', street: 'Paud Road', city: 'Pune', pincode: '411038', lat: 18.515, lng: 73.8077 },
        store: { name: 'MK Market - Kothrud' },
        paidInAdvance: true,
        deliveryOtp: { status: 'NOT_SENT', attemptsLeft: 3, resendsLeft: 2 },
      });
      expect(body.items).toHaveLength(2);
    });

    it('TC-D-017: several assigned orders are listed, oldest assignment first', async () => {
      const first = await assigned();
      ctx.clock.advance(60);
      const second = await assigned();
      expect((await list(deliveryA1)).body.items.map((o: any) => o.orderId)).toEqual([first, second]);
    });

    it('TC-D-015: customer details are hidden once the order is delivered', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      await verify(orderId, customerOtp()).expect(200);

      const { body } = await details(deliveryA1, orderId).expect(200);
      expect(body.customer).toBeNull();
      expect(body.address).toEqual({ area: 'Paud Road', pincode: '411038' });
      expect(body.deliveryOtp).toBeNull();
      const completed = (await list(deliveryA1, 'COMPLETED')).body.items;
      expect(completed).toHaveLength(1);
      expect(completed[0]).not.toHaveProperty('customerName');
      expect((await list(deliveryA1)).body.items).toEqual([]);
    });

    it('the Completed tab shows the last 7 days', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      await verify(orderId, customerOtp()).expect(200);
      ctx.clock.advance(8 * 24 * 3600);
      expect((await list(deliveryA1, 'COMPLETED')).body.items).toEqual([]);
    });
  });

  describe('Delivered tap sends the OTP (FR-D-04, FR-D-05, BR-18)', () => {
    it('TC-D-018, TC-D-020, TC-D-021: sends a 4-digit OTP to the customer\'s registered number', async () => {
      const orderId = await assigned();
      const { body } = await sendOtp(orderId).expect(200);
      expect(body).toMatchObject({ status: 'ACTIVE', attemptsLeft: 3, resendsLeft: 2 });
      expect(new Date(body.expiresAt).getTime() - ctx.clock.now().getTime()).toBe(10 * 60 * 1000);
      expect(ctx.sms.sent.filter((s) => s.kind === 'delivery')).toEqual([
        { mobile: CUSTOMER, otp: expect.stringMatching(/^\d{4}$/), kind: 'delivery' },
      ]);
    });

    it('TC-D-019, TC-D-056: the OTP is never returned by the API or stored in plain text', async () => {
      const orderId = await assigned();
      const sent = JSON.stringify((await sendOtp(orderId).expect(200)).body);
      const shown = JSON.stringify((await details(deliveryA1, orderId).expect(200)).body);
      const otp = customerOtp();
      expect(sent).not.toMatch(new RegExp(`"${otp}"`));
      expect(shown).not.toMatch(new RegExp(`"${otp}"`));
      const [row] = await ctx.db.query(`SELECT otp_hash FROM delivery_otps`);
      expect(row.otp_hash).toMatch(/^[0-9a-f]{64}$/);
    });

    it('TC-D-024: tapping Delivered alone does not deliver the order', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      const view = await customerView(orderId);
      expect(view).toMatchObject({ status: 'OUT_FOR_DELIVERY', deliveryOtpActive: true });
      expect((await list(deliveryA1)).body.items[0].deliveryOtpActive).toBe(true);
    });

    it('TC-D-025: a double tap sends only one SMS', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      await sendOtp(orderId).expect(200);
      expect(ctx.sms.count('delivery')).toBe(1);
    });

    it('a failed SMS uses up nothing and can be retried', async () => {
      const orderId = await assigned();
      ctx.sms.fail = true;
      expect((await sendOtp(orderId).expect(502)).body.error.code).toBe('SMS_SEND_FAILED');
      ctx.sms.fail = false;
      const { body } = await sendOtp(orderId).expect(200);
      expect(body).toMatchObject({ status: 'ACTIVE', attemptsLeft: 3, resendsLeft: 2 });
      await verify(orderId, customerOtp()).expect(200);
    });

    it('TC-D-023: each order has its own OTP', async () => {
      const first = await assigned();
      const second = await assigned();
      await sendOtp(first).expect(200);
      const firstOtp = customerOtp();
      await sendOtp(second).expect(200);
      if (customerOtp() === firstOtp) return; // 1 in 10,000 chance the codes match
      expect((await verify(second, firstOtp).expect(400)).body.error.code).toBe('OTP_INCORRECT');
    });
  });

  describe('Entering the OTP (FR-D-06 to FR-D-08, FR-D-10, BR-19, BR-20)', () => {
    it('TC-D-026: the correct OTP closes the order as Delivered everywhere', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      const { body } = await verify(orderId, customerOtp()).expect(200);
      expect(body).toMatchObject({ result: 'DELIVERED', orderId });

      expect(await customerView(orderId)).toMatchObject({ status: 'DELIVERED', deliveryOtpActive: false });
      const delivered = await ctx.http().get('/api/v1/store/orders').query({ status: 'DELIVERED' }).set(as(managerA));
      expect(delivered.body.items.map((o: any) => o.orderId)).toEqual([orderId]);
      const [history] = await ctx.db.query(`SELECT actor_role FROM order_status_history WHERE to_status = 'DELIVERED'`);
      expect(history.actor_role).toBe('DELIVERY_BOY');
    });

    it('TC-D-027: a wrong OTP shows attempts left and keeps the order on the way', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      const { body } = await verify(orderId, wrong(customerOtp())).expect(400);
      expect(body.error).toMatchObject({ code: 'OTP_INCORRECT', attemptsLeft: 2 });
      expect(body.error.message).toBe('Incorrect OTP. 2 attempts left. Ask the customer to use the latest SMS.');
      expect((await customerView(orderId)).status).toBe('OUT_FOR_DELIVERY');
    });

    it('TC-D-028: two wrong OTPs, then the correct one, delivers', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      await verify(orderId, wrong(customerOtp(), 1)).expect(400);
      await verify(orderId, wrong(customerOtp(), 2)).expect(400);
      expect((await verify(orderId, customerOtp()).expect(200)).body.result).toBe('DELIVERED');
    });

    it('TC-D-029, TC-D-044, TC-D-046: the 3rd wrong OTP closes it as Undelivered and returns it to the store', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      await verify(orderId, wrong(customerOtp(), 1)).expect(400);
      await verify(orderId, wrong(customerOtp(), 2)).expect(400);
      const { body } = await verify(orderId, wrong(customerOtp(), 3)).expect(200);
      expect(body).toMatchObject({ result: 'UNDELIVERED', reason: 'OTP_ATTEMPTS_EXCEEDED' });

      expect((await customerView(orderId)).status).toBe('UNDELIVERED');
      const returned = await ctx.http().get('/api/v1/store/orders').query({ status: 'UNDELIVERED' }).set(as(managerA));
      expect(returned.body.items).toEqual([
        expect.objectContaining({ orderId, undeliveredReason: 'OTP_ATTEMPTS_EXCEEDED' }),
      ]);
    });

    it('TC-D-030, TC-D-045: after 3 wrong OTPs even the correct one is refused', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      for (let n = 1; n <= 3; n++) await verify(orderId, wrong(customerOtp(), n));
      const res = await verify(orderId, customerOtp()).expect(409);
      expect(res.body.error).toMatchObject({ code: 'ORDER_STATE_CHANGED', currentStatus: 'UNDELIVERED' });
      await sendOtp(orderId).expect(409);
      await resend(orderId).expect(409);
    });

    it.each(['123', '12a4', '12345', ''])('TC-D-031, TC-D-032: "%s" is rejected without using an attempt', async (otp) => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      expect((await verify(orderId, otp).expect(400)).body.error.code).toBe('INVALID_INPUT');
      expect((await details(deliveryA1, orderId)).body.deliveryOtp.attemptsLeft).toBe(3);
    });

    it('TC-D-033, TC-D-034: the OTP works until 10 minutes; after that it is refused without using an attempt', async () => {
      const early = await assigned();
      await sendOtp(early).expect(200);
      ctx.clock.advance(9 * 60 + 50);
      await verify(early, customerOtp()).expect(200);

      const late = await assigned();
      await sendOtp(late).expect(200);
      ctx.clock.advance(10 * 60 + 10);
      expect((await verify(late, customerOtp()).expect(400)).body.error.code).toBe('OTP_EXPIRED');
      expect((await details(deliveryA1, late)).body.deliveryOtp).toMatchObject({ status: 'EXPIRED', attemptsLeft: 3 });
    });

    it('verifying before any OTP was sent is refused', async () => {
      const orderId = await assigned();
      expect((await verify(orderId, '1234').expect(409)).body.error.code).toBe('OTP_NOT_ACTIVE');
    });

    it('TC-D-035: an OTP works only once', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      await verify(orderId, customerOtp()).expect(200);
      await verify(orderId, customerOtp()).expect(409);
    });

    it('TC-D-037: rapid parallel guesses still get only 3 attempts', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      const otp = customerOtp();
      const results = await Promise.all([1, 2, 3, 4, 5, 6].map((n) => verify(orderId, wrong(otp, n))));
      expect(results.map((r) => r.status).sort()).toEqual([200, 400, 400, 409, 409, 409]);
      const [counters] = await ctx.db.query(`SELECT attempts_used FROM delivery_otp_counters`);
      expect(counters.attempts_used).toBe(3);
      expect((await customerView(orderId)).status).toBe('UNDELIVERED');
    });
  });

  describe('Resending the OTP (FR-D-09, EX-14)', () => {
    it('TC-D-038 to TC-D-041: up to 2 resends, 30 seconds apart, each with a new OTP', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);

      const tooSoon = (await resend(orderId).expect(429)).body.error;
      expect(tooSoon).toMatchObject({ code: 'RESEND_TOO_SOON', retryAfterSec: 30 });

      ctx.clock.advance(30);
      expect((await resend(orderId).expect(200)).body).toMatchObject({ status: 'ACTIVE', resendsLeft: 1 });
      ctx.clock.advance(30);
      expect((await resend(orderId).expect(200)).body).toMatchObject({ resendsLeft: 0, nextResendAt: null });
      ctx.clock.advance(30);
      expect((await resend(orderId).expect(409)).body.error.code).toBe('RESEND_LIMIT_REACHED');

      expect(ctx.sms.count('delivery')).toBe(3);
      await verify(orderId, customerOtp()).expect(200);
    });

    it('TC-D-042: the older OTP stops working after a resend', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      const old = customerOtp();
      ctx.clock.advance(30);
      await resend(orderId).expect(200);
      if (customerOtp() === old) return; // 1 in 10,000 chance the codes match
      expect((await verify(orderId, old).expect(400)).body.error.attemptsLeft).toBe(2);
    });

    it('TC-D-043: a resend does not reset the attempts', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      await verify(orderId, wrong(customerOtp(), 1)).expect(400);
      await verify(orderId, wrong(customerOtp(), 2)).expect(400);
      ctx.clock.advance(30);
      expect((await resend(orderId).expect(200)).body.attemptsLeft).toBe(1);
      expect((await verify(orderId, wrong(customerOtp())).expect(200)).body.result).toBe('UNDELIVERED');
    });

    it('an expired OTP can be replaced with a resend', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      ctx.clock.advance(11 * 60);
      await resend(orderId).expect(200);
      await verify(orderId, customerOtp()).expect(200);
    });

    it('a failed resend SMS keeps the previous OTP and gives the resend back', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      const first = customerOtp();
      ctx.clock.advance(30);
      ctx.sms.fail = true;
      await resend(orderId).expect(502);
      ctx.sms.fail = false;
      expect((await details(deliveryA1, orderId)).body.deliveryOtp).toMatchObject({ status: 'ACTIVE', resendsLeft: 2 });
      await verify(orderId, first).expect(200);
    });

    it('resend needs an OTP to have been sent first', async () => {
      const orderId = await assigned();
      expect((await resend(orderId).expect(409)).body.error.code).toBe('OTP_NOT_ACTIVE');
    });
  });

  describe('Network loss and retries (EX-17, NFR-11)', () => {
    it('TC-D-049, TC-D-051: retrying a wrong OTP with the same key does not use a second attempt', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      const key = randomUUID();
      const bad = wrong(customerOtp());
      const first = (await verify(orderId, bad, key).expect(400)).body;
      const retry = (await verify(orderId, bad, key).expect(400)).body;
      expect(retry).toEqual(first);
      expect((await details(deliveryA1, orderId)).body.deliveryOtp.attemptsLeft).toBe(2);
    });

    it('TC-D-050: retrying a successful verify returns the same result', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      const key = randomUUID();
      const first = (await verify(orderId, customerOtp(), key).expect(200)).body;
      const retry = (await verify(orderId, customerOtp(), key).expect(200)).body;
      expect(retry).toEqual(first);
      const history = await ctx.db.query(`SELECT id FROM order_status_history WHERE to_status = 'DELIVERED'`);
      expect(history).toHaveLength(1);
    });

    it('an Idempotency-Key is required to verify', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      await ctx.http().post(`${base(orderId)}/delivery-otp/verify`).set(as(deliveryA1)).send({ otp: '1234' }).expect(400);
    });

    it('TC-D-053: reopening the app shows the saved OTP state', async () => {
      const orderId = await assigned();
      await sendOtp(orderId).expect(200);
      await verify(orderId, wrong(customerOtp())).expect(400);
      ctx.clock.advance(30);
      await resend(orderId).expect(200);
      expect((await details(deliveryA1, orderId)).body.deliveryOtp).toMatchObject({
        status: 'ACTIVE',
        attemptsLeft: 2,
        resendsLeft: 1,
      });
    });
  });

  describe('Access (NFR-03)', () => {
    it('TC-D-054, TC-D-055: delivery boys, managers and customers only reach their own module', async () => {
      const orderId = await assigned();
      await ctx.http().get('/api/v1/products/search?q=milk').set(as(deliveryA1)).expect(403);
      await ctx.http().get('/api/v1/store/orders').set(as(deliveryA1)).expect(403);
      await ctx.http().get('/api/v1/delivery/orders').set(as(customer)).expect(403);
      await ctx.http().post(`${base(orderId)}/delivery-otp`).set(as(managerA)).expect(403);
    });
  });
});
