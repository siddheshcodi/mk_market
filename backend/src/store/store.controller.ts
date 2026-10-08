import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { Auth, CurrentAuth } from '../auth/auth.guard';
import { AuthContext } from '../auth/auth.types';
import { Errors } from '../common/errors';
import { IdempotencyKey } from '../common/idempotency';
import { DispatchDto, StoreOrdersQuery } from './store.dto';
import { StoreOrdersService } from './store-orders.service';

const orderId = new ParseUUIDPipe({ exceptionFactory: () => Errors.notFound('Order') });

/**
 * Store manager APIs. The store always comes from the login token, never from the request (BR-15).
 * There is deliberately no reject, cancel or free status-change endpoint (FR-S-06, A8).
 */
@Controller('store')
@Auth('STORE_MANAGER')
export class StoreController {
  constructor(private readonly store: StoreOrdersService) {}

  @Get('orders')
  list(@CurrentAuth() auth: AuthContext, @Query() query: StoreOrdersQuery) {
    return this.store.list(storeOf(auth), query.status, query.page, query.size, query.since);
  }

  @Get('orders/:orderId')
  get(@CurrentAuth() auth: AuthContext, @Param('orderId', orderId) id: string) {
    return this.store.get(storeOf(auth), id);
  }

  @Get('delivery-boys')
  deliveryBoys(@CurrentAuth() auth: AuthContext) {
    return this.store.deliveryBoys(storeOf(auth));
  }

  @Post('orders/:orderId/dispatch')
  @HttpCode(200)
  dispatch(
    @CurrentAuth() auth: AuthContext,
    @Param('orderId', orderId) id: string,
    @Body() dto: DispatchDto,
    @IdempotencyKey() key: string,
  ) {
    return this.store.dispatch(storeOf(auth), auth.subjectId, id, dto.deliveryBoyId, key);
  }
}

function storeOf(auth: AuthContext) {
  if (!auth.storeId) throw Errors.forbidden();
  return auth.storeId;
}
