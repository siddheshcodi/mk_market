import { createTestApp, login, STAFF, TestContext } from './helpers';

describe('Login (FR-U-01, FR-U-02, BR-01 to BR-04)', () => {
  let ctx: TestContext;
  const otpRequest = (mobile: string, role = 'USER') =>
    ctx.http().post('/api/v1/auth/otp/request').send({ mobile, role });
  const verify = (requestId: string, otp: string) => ctx.http().post('/api/v1/auth/otp/verify').send({ requestId, otp });

  beforeEach(async () => {
    ctx = await createTestApp();
  });
  afterEach(() => ctx.app.close());

  it('TC-U-001: new number logs in with the correct OTP and an account is created', async () => {
    const res = await otpRequest('9876543210').expect(200);
    expect(res.body).toMatchObject({ resendAfterSec: 30, expiresInSec: 300 });
    expect(ctx.sms.lastOtp('9876543210')).toMatch(/^\d{6}$/);

    const body = (await verify(res.body.requestId, ctx.sms.lastOtp('9876543210')).expect(200)).body;
    expect(body.accessToken).toBeDefined();
    expect(body.user).toMatchObject({ mobile: '9876543210', role: 'USER' });
    expect(await ctx.db.query(`SELECT id FROM users WHERE mobile = '9876543210'`)).toHaveLength(1);
  });

  it('TC-U-002: an existing customer keeps the same account', async () => {
    const first = await login(ctx, '9123456780');
    const second = await login(ctx, '9123456780');
    expect(second.user!.id).toBe(first.user!.id);
  });

  it.each(['987654321', '98765432101', '98765abc10', '', '5876543210'])(
    'TC-U-003 to TC-U-006: invalid mobile "%s" is rejected and no SMS is sent',
    async (mobile) => {
      const res = await otpRequest(mobile).expect(400);
      expect(res.body.error).toEqual({ code: 'INVALID_MOBILE', message: 'Enter a valid 10-digit mobile number' });
      expect(ctx.sms.sent).toHaveLength(0);
    },
  );

  it('TC-U-008, TC-U-009: wrong OTPs show an error but never lock the account', async () => {
    const { requestId } = (await otpRequest('9876543210').expect(200)).body;
    const otp = ctx.sms.lastOtp('9876543210');
    const wrong = otp === '000000' ? '111111' : '000000';
    for (let i = 0; i < 5; i++) {
      expect((await verify(requestId, wrong).expect(400)).body.error.code).toBe('OTP_INVALID');
    }
    await verify(requestId, otp).expect(200);
  });

  it('TC-U-010, TC-U-011: the OTP works until 5 minutes and expires after', async () => {
    const first = (await otpRequest('9876543210').expect(200)).body;
    ctx.clock.advance(5 * 60 + 10);
    expect((await verify(first.requestId, ctx.sms.lastOtp('9876543210')).expect(400)).body.error.code).toBe('OTP_EXPIRED');

    const second = (await otpRequest('9876543210').expect(200)).body;
    ctx.clock.advance(4 * 60 + 50);
    await verify(second.requestId, ctx.sms.lastOtp('9876543210')).expect(200);
  });

  it('TC-U-013 to TC-U-015: resend waits 30 seconds and only the newest OTP works', async () => {
    const first = (await otpRequest('9876543210').expect(200)).body;
    const firstOtp = ctx.sms.lastOtp('9876543210');

    ctx.clock.advance(10);
    const tooSoon = (await otpRequest('9876543210').expect(429)).body.error;
    expect(tooSoon).toMatchObject({ code: 'OTP_RESEND_TOO_SOON', retryAfterSec: 20 });

    ctx.clock.advance(20);
    const second = (await otpRequest('9876543210').expect(200)).body;
    expect((await verify(first.requestId, firstOtp).expect(400)).body.error.code).toBe('OTP_INVALID');
    await verify(second.requestId, ctx.sms.lastOtp('9876543210')).expect(200);
  });

  it('TC-U-016: an OTP can be used only once', async () => {
    const { requestId } = (await otpRequest('9876543210').expect(200)).body;
    const otp = ctx.sms.lastOtp('9876543210');
    await verify(requestId, otp).expect(200);
    await verify(requestId, otp).expect(400);
  });

  it('stores only a hash of the OTP (NFR-02)', async () => {
    await otpRequest('9876543210').expect(200);
    const [row] = await ctx.db.query(`SELECT otp_hash FROM otp_requests`);
    expect(row.otp_hash).not.toContain(ctx.sms.lastOtp('9876543210'));
    expect(row.otp_hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('limits OTP SMS to 5 per hour per number (SMS throttling, not an account lock)', async () => {
    for (let i = 0; i < 5; i++) {
      await otpRequest('9876543210').expect(200);
      ctx.clock.advance(31);
    }
    expect((await otpRequest('9876543210').expect(429)).body.error.code).toBe('OTP_RATE_LIMIT');
    ctx.clock.advance(3600);
    await otpRequest('9876543210').expect(200);
  });

  it('a failed SMS send does not start the resend timer', async () => {
    ctx.sms.fail = true;
    expect((await otpRequest('9876543210').expect(502)).body.error.code).toBe('SMS_SEND_FAILED');
    ctx.sms.fail = false;
    await otpRequest('9876543210').expect(200);
  });

  it('TC-S-001, TC-D-001: hardcoded staff numbers log in to their own role with their store', async () => {
    const manager = await login(ctx, STAFF.managerA, 'STORE_MANAGER');
    expect((manager as any).staff).toMatchObject({ name: 'Manager A', storeName: 'MK Market - Kothrud' });
    const delivery = await login(ctx, STAFF.deliveryA1, 'DELIVERY_BOY');
    expect((delivery as any).staff).toMatchObject({ name: 'Delivery A1' });
  });

  it.each([
    ['TC-S-002: unregistered number', '9111111111', 'STORE_MANAGER'],
    ['TC-S-003: customer number as store manager', '9876543210', 'STORE_MANAGER'],
    ['TC-S-004: delivery boy number as store manager', STAFF.deliveryA1, 'STORE_MANAGER'],
    ['TC-D-002: unregistered number', '9111111111', 'DELIVERY_BOY'],
    ['TC-D-004: store manager number as delivery boy', STAFF.managerA, 'DELIVERY_BOY'],
  ])('%s gets "This number is not registered" and no SMS', async (_name, mobile, role) => {
    const res = await otpRequest(mobile, role).expect(403);
    expect(res.body.error).toEqual({ code: 'NUMBER_NOT_REGISTERED', message: 'This number is not registered' });
    expect(ctx.sms.sent).toHaveLength(0);
  });

  it('TC-U-018: logout ends the session', async () => {
    const tokens = await login(ctx, '9876543210');
    await ctx.http().post('/api/v1/auth/token/refresh').send({ refreshToken: tokens.refreshToken }).expect(200);
    await ctx.http().post('/api/v1/auth/logout').set('authorization', `Bearer ${tokens.accessToken}`).expect(204);
    const res = await ctx.http().post('/api/v1/auth/token/refresh').send({ refreshToken: tokens.refreshToken }).expect(401);
    expect(res.body.error.code).toBe('SESSION_EXPIRED');
  });

  it('TC-U-019: the session ends after 30 days without use', async () => {
    const tokens = await login(ctx, '9876543210');
    ctx.clock.advance(29 * 24 * 3600);
    const refreshed = (await ctx.http().post('/api/v1/auth/token/refresh').send({ refreshToken: tokens.refreshToken }).expect(200)).body;
    ctx.clock.advance(31 * 24 * 3600);
    await ctx.http().post('/api/v1/auth/token/refresh').send({ refreshToken: refreshed.refreshToken }).expect(401);
  });

  it('TC-U-082, TC-S-042: each role reaches only its own module', async () => {
    const manager = await login(ctx, STAFF.managerA, 'STORE_MANAGER');
    const res = await ctx
      .http()
      .get('/api/v1/products/search?q=milk')
      .set('authorization', `Bearer ${manager.accessToken}`)
      .expect(403);
    expect(res.body.error.code).toBe('FORBIDDEN');
    await ctx.http().get('/api/v1/products/search?q=milk').expect(401);
  });
});
