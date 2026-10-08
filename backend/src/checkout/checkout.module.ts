import { Module } from '@nestjs/common';
import { APP_CONFIG, AppConfig } from '../config/app-config';
import { MapsModule } from '../maps/maps.module';
import { OrdersModule } from '../orders/orders.module';
import { PaymentGateway, RazorpayGateway } from '../payment/payment-gateway';
import { PaymentService } from '../payment/payment.service';
import { DevPaymentsController, TestPaymentGateway } from '../payment/test-gateway';
import { WebhookController } from '../payment/webhook.controller';
import { CheckoutController } from './checkout.controller';
import { CheckoutService } from './checkout.service';

@Module({
  imports: [MapsModule, OrdersModule],
  controllers: [CheckoutController, WebhookController, DevPaymentsController],
  providers: [
    CheckoutService,
    PaymentService,
    {
      provide: PaymentGateway,
      inject: [APP_CONFIG],
      useFactory: ({ payment }: AppConfig) =>
        payment.provider === 'test'
          ? new TestPaymentGateway()
          : new RazorpayGateway(payment.razorpayKeyId, payment.razorpayKeySecret, payment.razorpayWebhookSecret),
    },
  ],
})
export class CheckoutModule {}
