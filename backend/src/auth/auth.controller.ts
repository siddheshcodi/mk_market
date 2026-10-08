import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { Auth, CurrentAuth } from './auth.guard';
import { RefreshTokenDto, RequestOtpDto, VerifyOtpDto } from './auth.dto';
import { AuthService } from './auth.service';
import { AuthContext } from './auth.types';

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('otp/request')
  @HttpCode(200)
  requestOtp(@Body() dto: RequestOtpDto) {
    return this.auth.requestOtp(dto.mobile, dto.role);
  }

  @Post('otp/verify')
  @HttpCode(200)
  verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.auth.verifyOtp(dto.requestId, dto.otp);
  }

  @Post('token/refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshTokenDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  @Post('logout')
  @HttpCode(204)
  @Auth()
  async logout(@CurrentAuth() auth: AuthContext) {
    await this.auth.logout(auth.sessionId);
  }
}
