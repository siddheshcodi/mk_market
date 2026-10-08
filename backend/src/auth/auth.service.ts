import { Inject, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { randomUUID } from 'crypto';
import { addSeconds, Clock } from '../common/clock';
import { Errors } from '../common/errors';
import { ACCESS_TOKEN_TTL_SEC, LOGIN_OTP, MOBILE_PATTERN, Role, SESSION_IDLE_SEC } from '../common/rules';
import { APP_CONFIG, AppConfig } from '../config/app-config';
import { Db } from '../database/db';
import { SmsSender } from '../sms/sms-sender';
import { AccessTokenClaims, RefreshTokenClaims } from './auth.types';
import { generateOtp, hashOtp, otpMatches } from './otp';

interface OtpRow {
  id: string;
  mobile: string;
  role: Role;
  otp_hash: string;
  status: string;
  attempts: number;
  expires_at: Date;
  created_at: Date;
}

interface SessionRow {
  id: string;
  subject_id: string;
  role: Role;
  store_id: string | null;
  mobile: string | null;
  last_used_at: Date;
  revoked_at: Date | null;
}

/** The logged-in account: a customer, or a staff member from the hardcoded staff list. */
interface Subject {
  id: string;
  mobile: string;
  storeId?: string;
  profile: Record<string, unknown>;
}

@Injectable()
export class AuthService {
  constructor(
    private readonly db: Db,
    private readonly jwt: JwtService,
    private readonly sms: SmsSender,
    private readonly clock: Clock,
    @Inject(APP_CONFIG) private readonly config: AppConfig,
  ) {}

  /** FR-U-01, FR-S-01, FR-D-01, EX-01, EX-03, EX-04. */
  async requestOtp(mobile: string, role: Role) {
    if (!MOBILE_PATTERN.test(mobile)) throw Errors.invalidMobile();
    if (role !== 'USER' && !(await this.findStaff(mobile, role))) throw Errors.numberNotRegistered();

    const now = this.clock.now();
    const recent = await this.db.query<{ created_at: Date }>(
      `SELECT created_at FROM otp_requests WHERE mobile = $1 AND role = $2 AND created_at > $3 ORDER BY created_at DESC`,
      [mobile, role, addSeconds(now, -3600)],
    );
    if (recent.length) {
      const waitSec = Math.ceil(LOGIN_OTP.resendAfterSec - (now.getTime() - recent[0].created_at.getTime()) / 1000);
      if (waitSec > 0) throw Errors.otpResendTooSoon(waitSec);
    }
    if (recent.length >= LOGIN_OTP.maxSendsPerHour) throw Errors.otpRateLimit();

    const id = randomUUID();
    const otp = generateOtp(LOGIN_OTP.length, this.config.devFixedOtp);
    await this.db.tx(async (q) => {
      await q.query(`UPDATE otp_requests SET status = 'REPLACED' WHERE mobile = $1 AND role = $2 AND status = 'ACTIVE'`, [
        mobile,
        role,
      ]);
      await q.query(
        `INSERT INTO otp_requests (id, mobile, role, otp_hash, status, attempts, expires_at, created_at)
         VALUES ($1, $2, $3, $4, 'ACTIVE', 0, $5, $6)`,
        [id, mobile, role, hashOtp(this.config.otpSecret, id, otp), addSeconds(now, LOGIN_OTP.ttlSec), now],
      );
    });

    try {
      await this.sms.sendLoginOtp(mobile, otp);
    } catch (err) {
      // A failed send must not start the resend timer.
      await this.db.query(`DELETE FROM otp_requests WHERE id = $1`, [id]);
      throw err;
    }
    return { requestId: id, resendAfterSec: LOGIN_OTP.resendAfterSec, expiresInSec: LOGIN_OTP.ttlSec };
  }

  /** FR-U-02, BR-02, BR-03 (wrong OTP never locks the account). */
  async verifyOtp(requestId: string, otp: string) {
    const [row] = await this.db.query<OtpRow>(`SELECT * FROM otp_requests WHERE id = $1`, [requestId]);
    if (!row || row.status !== 'ACTIVE') throw Errors.otpInvalid();
    if (this.clock.now() > row.expires_at) throw Errors.otpExpired();
    // After too many guesses this code stops working; the user simply requests a new one.
    if (row.attempts >= LOGIN_OTP.maxVerifyAttempts) throw Errors.otpInvalid();

    if (!otpMatches(this.config.otpSecret, row.id, otp, row.otp_hash)) {
      await this.db.query(`UPDATE otp_requests SET attempts = attempts + 1 WHERE id = $1`, [row.id]);
      throw Errors.otpInvalid();
    }

    const used = await this.db.query(
      `UPDATE otp_requests SET status = 'USED' WHERE id = $1 AND status = 'ACTIVE' RETURNING id`,
      [row.id],
    );
    if (!used.length) throw Errors.otpInvalid();

    const subject = await this.loginSubject(row.mobile, row.role);
    const tokens = await this.startSession(subject, row.role);
    return { ...tokens, [row.role === 'USER' ? 'user' : 'staff']: subject.profile };
  }

  async refresh(refreshToken: string) {
    let claims: RefreshTokenClaims;
    try {
      claims = this.jwt.verify<RefreshTokenClaims>(refreshToken);
    } catch {
      throw Errors.sessionExpired();
    }
    if (claims.typ !== 'refresh') throw Errors.sessionExpired();

    const [session] = await this.db.query<SessionRow>(`SELECT * FROM sessions WHERE id = $1`, [claims.sid]);
    const now = this.clock.now();
    if (!session || session.revoked_at) throw Errors.sessionExpired();
    if (now > addSeconds(session.last_used_at, SESSION_IDLE_SEC[session.role])) throw Errors.sessionExpired();
    // A15: staff removed from config/staff.yaml lose access at their next refresh, not up to 12 hours later.
    if (session.role !== 'USER' && !(await this.staffStillActive(session))) {
      await this.logout(session.id);
      throw Errors.sessionExpired();
    }

    await this.db.query(`UPDATE sessions SET last_used_at = $2 WHERE id = $1`, [session.id, now]);
    return this.issueTokens(session.id, session.subject_id, session.role, session.store_id ?? undefined);
  }

  async logout(sessionId: string) {
    await this.db.query(`UPDATE sessions SET revoked_at = $2 WHERE id = $1 AND revoked_at IS NULL`, [
      sessionId,
      this.clock.now(),
    ]);
  }

  /** BR-04: staff log in only with numbers from the hardcoded staff list. */
  private async findStaff(mobile: string, role: Role): Promise<Subject | undefined> {
    if (role === 'STORE_MANAGER') {
      const [m] = await this.db.query(
        `SELECT m.id, m.name, s.id AS store_id, s.name AS store_name
         FROM store_managers m JOIN stores s ON s.id = m.store_id
         WHERE m.mobile = $1 AND m.is_active AND s.is_active`,
        [mobile],
      );
      return m && { id: m.id, mobile, storeId: m.store_id, profile: { id: m.id, name: m.name, storeId: m.store_id, storeName: m.store_name } };
    }
    if (role === 'DELIVERY_BOY') {
      const [d] = await this.db.query(
        `SELECT d.id, d.name, s.id AS store_id, s.name AS store_name
         FROM delivery_boys d JOIN stores s ON s.id = d.store_id
         WHERE d.mobile = $1 AND d.is_active AND s.is_active`,
        [mobile],
      );
      return d && { id: d.id, mobile, storeId: d.store_id, profile: { id: d.id, name: d.name, storeId: d.store_id, storeName: d.store_name } };
    }
    return undefined;
  }

  private async staffStillActive(session: SessionRow) {
    const table = session.role === 'STORE_MANAGER' ? 'store_managers' : 'delivery_boys';
    const rows = await this.db.query(
      `SELECT 1 FROM ${table} t JOIN stores s ON s.id = t.store_id
       WHERE t.id = $1 AND t.mobile = $2 AND t.is_active AND s.is_active`,
      [session.subject_id, session.mobile],
    );
    return rows.length > 0;
  }

  private async loginSubject(mobile: string, role: Role): Promise<Subject> {
    if (role !== 'USER') {
      const staff = await this.findStaff(mobile, role);
      // The number was removed from the staff list between OTP request and verify.
      if (!staff) throw Errors.numberNotRegistered();
      return staff;
    }
    const now = this.clock.now();
    // A customer account is created on first successful login.
    const [user] = await this.db.query<{ id: string }>(
      `INSERT INTO users (id, mobile, created_at, last_login_at) VALUES ($1, $2, $3, $3)
       ON CONFLICT (mobile) DO UPDATE SET last_login_at = EXCLUDED.last_login_at
       RETURNING id`,
      [randomUUID(), mobile, now],
    );
    return { id: user.id, mobile, profile: { id: user.id, mobile, role } };
  }

  private async startSession(subject: Subject, role: Role) {
    const sessionId = randomUUID();
    const now = this.clock.now();
    await this.db.query(
      `INSERT INTO sessions (id, subject_id, role, store_id, mobile, created_at, last_used_at) VALUES ($1, $2, $3, $4, $5, $6, $6)`,
      [sessionId, subject.id, role, subject.storeId ?? null, subject.mobile, now],
    );
    return this.issueTokens(sessionId, subject.id, role, subject.storeId);
  }

  private issueTokens(sessionId: string, subjectId: string, role: Role, storeId?: string) {
    const access: AccessTokenClaims = { typ: 'access', sub: subjectId, role, sid: sessionId, ...(storeId && { storeId }) };
    const refresh: RefreshTokenClaims = { typ: 'refresh', sid: sessionId };
    return {
      accessToken: this.jwt.sign(access, { expiresIn: ACCESS_TOKEN_TTL_SEC }),
      refreshToken: this.jwt.sign(refresh, { expiresIn: SESSION_IDLE_SEC[role] }),
    };
  }
}
