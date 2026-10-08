import {
  applyDecorators,
  CanActivate,
  createParamDecorator,
  ExecutionContext,
  Injectable,
  SetMetadata,
  UseGuards,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { Errors } from '../common/errors';
import { Role } from '../common/rules';
import { AccessTokenClaims, AuthContext } from './auth.types';

const ROLES_KEY = 'roles';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest();
    const header: string | undefined = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) throw Errors.unauthorized();

    let claims: AccessTokenClaims;
    try {
      claims = this.jwt.verify<AccessTokenClaims>(header.slice('Bearer '.length));
    } catch {
      throw Errors.unauthorized();
    }
    if (claims.typ !== 'access') throw Errors.unauthorized();

    // NFR-03: each role reaches only its own module.
    const roles = this.reflector.get<Role[]>(ROLES_KEY, context.getHandler()) ??
      this.reflector.get<Role[]>(ROLES_KEY, context.getClass());
    if (roles?.length && !roles.includes(claims.role)) throw Errors.forbidden();

    const auth: AuthContext = { subjectId: claims.sub, role: claims.role, sessionId: claims.sid, storeId: claims.storeId };
    req.auth = auth;
    return true;
  }
}

/** Requires a valid access token; with roles, only those roles may call the endpoint. */
export const Auth = (...roles: Role[]) => applyDecorators(SetMetadata(ROLES_KEY, roles), UseGuards(AuthGuard));

export const CurrentAuth = createParamDecorator(
  (_: unknown, ctx: ExecutionContext): AuthContext => ctx.switchToHttp().getRequest().auth,
);
