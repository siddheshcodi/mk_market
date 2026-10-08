import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, Matches, Max, Min } from 'class-validator';
import { Auth, CurrentAuth } from '../auth/auth.guard';
import { AuthContext } from '../auth/auth.types';
import { Errors } from '../common/errors';
import { IdempotencyKey } from '../common/idempotency';
import { DeliveryService, DeliveryTab } from './delivery.service';

export class DeliveryOrdersQuery {
  @IsOptional()
  @IsIn(['ACTIVE', 'COMPLETED'])
  tab: DeliveryTab = 'ACTIVE';

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  size = 20;
}

export class VerifyDeliveryOtpDto {
  // A badly formatted OTP is rejected here and doesn't use up an attempt.
  @Matches(/^\d{4}$/)
  otp!: string;
}

const orderId = new ParseUUIDPipe({ exceptionFactory: () => Errors.notFound('Order') });

/** Delivery boy APIs. The delivery boy always comes from the login token (BR-17). */
@Controller('delivery/orders')
@Auth('DELIVERY_BOY')
export class DeliveryController {
  constructor(private readonly delivery: DeliveryService) {}

  @Get()
  list(@CurrentAuth() auth: AuthContext, @Query() query: DeliveryOrdersQuery) {
    return this.delivery.list(auth.subjectId, query.tab, query.page, query.size);
  }

  @Get(':orderId')
  get(@CurrentAuth() auth: AuthContext, @Param('orderId', orderId) id: string) {
    return this.delivery.get(auth.subjectId, id);
  }

  @Post(':orderId/delivery-otp')
  @HttpCode(200)
  sendOtp(@CurrentAuth() auth: AuthContext, @Param('orderId', orderId) id: string) {
    return this.delivery.sendOtp(auth.subjectId, id);
  }

  @Post(':orderId/delivery-otp/resend')
  @HttpCode(200)
  resendOtp(@CurrentAuth() auth: AuthContext, @Param('orderId', orderId) id: string) {
    return this.delivery.resendOtp(auth.subjectId, id);
  }

  @Post(':orderId/delivery-otp/verify')
  @HttpCode(200)
  verifyOtp(
    @CurrentAuth() auth: AuthContext,
    @Param('orderId', orderId) id: string,
    @Body() dto: VerifyDeliveryOtpDto,
    @IdempotencyKey() key: string,
  ) {
    return this.delivery.verifyOtp(auth.subjectId, id, dto.otp, key);
  }
}
