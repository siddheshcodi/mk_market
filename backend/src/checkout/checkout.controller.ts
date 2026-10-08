import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post } from '@nestjs/common';
import { Auth, CurrentAuth } from '../auth/auth.guard';
import { AuthContext } from '../auth/auth.types';
import { Errors } from '../common/errors';
import { PaymentService } from '../payment/payment.service';
import { ConfirmPaymentDto, CreateCheckoutDto } from './checkout.dto';
import { CheckoutService } from './checkout.service';

const checkoutId = new ParseUUIDPipe({ exceptionFactory: () => Errors.notFound('Checkout') });

@Controller('checkout')
@Auth('USER')
export class CheckoutController {
  constructor(
    private readonly checkout: CheckoutService,
    private readonly payment: PaymentService,
  ) {}

  @Post()
  create(@CurrentAuth() auth: AuthContext, @Body() dto: CreateCheckoutDto) {
    return this.checkout.create(auth.subjectId, dto);
  }

  @Get(':id')
  status(@CurrentAuth() auth: AuthContext, @Param('id', checkoutId) id: string) {
    return this.checkout.status(auth.subjectId, id);
  }

  @Post(':id/payment')
  @HttpCode(200)
  startPayment(@CurrentAuth() auth: AuthContext, @Param('id', checkoutId) id: string) {
    return this.payment.start(auth.subjectId, id);
  }

  @Post(':id/payment/confirm')
  @HttpCode(200)
  confirmPayment(@CurrentAuth() auth: AuthContext, @Param('id', checkoutId) id: string, @Body() dto: ConfirmPaymentDto) {
    return this.payment.confirmFromApp(auth.subjectId, id, dto);
  }
}
