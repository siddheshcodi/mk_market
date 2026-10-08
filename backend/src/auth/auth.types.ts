import { Role } from '../common/rules';

/** What the auth guard attaches to each request. */
export interface AuthContext {
  subjectId: string;
  role: Role;
  sessionId: string;
  storeId?: string;
}

export interface AccessTokenClaims {
  typ: 'access';
  sub: string;
  role: Role;
  sid: string;
  storeId?: string;
}

export interface RefreshTokenClaims {
  typ: 'refresh';
  sid: string;
}
