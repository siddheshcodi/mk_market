import { Controller, Headers, HttpCode, Post, RawBodyRequest, Req } from '@nestjs/common';
import { Request } from 'express';
import { PaymentService } from './payment.service';

/** Server-to-server only. Authenticated by the gateway's signature, not by a user token. */
@Controller('webhooks')
export class WebhookController {
  constructor(private readonly payment: PaymentService) {}

  @Post('payment')
  @HttpCode(200)
  async receive(@Req() req: RawBodyRequest<Request>, @Headers('x-razorpay-signature') signature?: string) {
    await this.payment.handleWebhook(req.rawBody, signature);
    return { received: true };
  }
}
