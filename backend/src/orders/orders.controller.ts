import { Controller, Get, Param, ParseUUIDPipe, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';
import { Auth, CurrentAuth } from '../auth/auth.guard';
import { AuthContext } from '../auth/auth.types';
import { Errors } from '../common/errors';
import { OrdersService } from './orders.service';

export class PageQuery {
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

/** Customer order APIs. There is deliberately no cancel, edit or delete endpoint (FR-U-14, BR-13). */
@Controller('orders')
@Auth('USER')
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  @Get()
  list(@CurrentAuth() auth: AuthContext, @Query() query: PageQuery) {
    return this.orders.listForUser(auth.subjectId, query.page, query.size);
  }

  @Get(':orderId')
  get(
    @CurrentAuth() auth: AuthContext,
    @Param('orderId', new ParseUUIDPipe({ exceptionFactory: () => Errors.notFound('Order') })) orderId: string,
  ) {
    return this.orders.getForUser(auth.subjectId, orderId);
  }
}
