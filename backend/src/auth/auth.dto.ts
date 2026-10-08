import { IsIn, IsString, IsUUID, Matches } from 'class-validator';
import { Role, ROLES } from '../common/rules';

export class RequestOtpDto {
  // Format is checked in the service so the app gets INVALID_MOBILE (EX-01).
  @IsString()
  mobile!: string;

  @IsIn(ROLES)
  role!: Role;
}

export class VerifyOtpDto {
  @IsUUID()
  requestId!: string;

  @Matches(/^\d{6}$/)
  otp!: string;
}

export class RefreshTokenDto {
  @IsString()
  refreshToken!: string;
}
