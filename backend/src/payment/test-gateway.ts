import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { createHmac, randomBytes } from 'crypto';
import { IsIn, IsString } from 'class-validator';
import { Errors } from '../common/errors';
import { GatewayPayment, PaymentGateway } from './payment-gateway';

const SECRET = 'local-test-gateway-secret';

function sign(data: string) {
  return createHmac('sha256', SECRET).update(data).digest('hex');
}

/**
 * Local development only (refused in production by loadConfig). Behaves like Razorpay, but the
 * "payment screen" is the app's Success / Fail buttons, which call DevPaymentsController.
 */
export class TestPaymentGateway extends PaymentGateway {
  readonly keyId = 'rzp_test_local';
  private readonly orders = new Map<string, number>();
  private readonly payments = new Map<string, GatewayPayment>();

  async createOrder(amountPaise: number) {
    const id = `order_test_${randomBytes(7).toString('hex')}`;
    this.orders.set(id, amountPaise);
    return id;
  }

  async fetchPayment(id: string) {
    const payment = this.payments.get(id);
    if (!payment) throw Errors.notFound('Payment');
    return payment;
  }

  verifyCheckoutSignature(gatewayOrderId: string, gatewayPaymentId: string, signature: string) {
    return signature === sign(`${gatewayOrderId}|${gatewayPaymentId}`);
  }

  verifyWebhookSignature() {
    return false;
  }

  /** What Razorpay's checkout hands back to the app after the customer pays (or fails to). */
  complete(gatewayOrderId: string, outcome: 'success' | 'failure') {
    const amountPaise = this.orders.get(gatewayOrderId);
    if (amountPaise === undefined) throw Errors.notFound('Payment');
    const id = `pay_test_${randomBytes(7).toString('hex')}`;
    this.payments.set(id, {
      id,
      gatewayOrderId,
      amountPaise,
      currency: 'INR',
      status: outcome === 'success' ? 'captured' : 'failed',
    });
    return { gatewayOrderId, gatewayPaymentId: id, signature: sign(`${gatewayOrderId}|${id}`) };
  }
}

export class CompleteTestPaymentDto {
  @IsString()
  gatewayOrderId!: string;

  @IsIn(['success', 'failure'])
  outcome!: 'success' | 'failure';
}

/** Stands in for Razorpay's checkout screen when PAYMENT_PROVIDER=test. */
@Controller('dev/payments')
export class DevPaymentsController {
  constructor(private readonly gateway: PaymentGateway) {}

  @Post('complete')
  @HttpCode(200)
  complete(@Body() dto: CompleteTestPaymentDto) {
    if (!(this.gateway instanceof TestPaymentGateway)) throw Errors.notFound('Page');
    return this.gateway.complete(dto.gatewayOrderId, dto.outcome);
  }
}
