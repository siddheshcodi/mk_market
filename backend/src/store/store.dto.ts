import { Type } from 'class-transformer';
import { IsDate, IsIn, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { OrderStatus } from '../orders/order-status';

export const STORE_TABS: OrderStatus[] = ['PLACED', 'OUT_FOR_DELIVERY', 'UNDELIVERED', 'DELIVERED'];

export class StoreOrdersQuery {
  @IsOptional()
  @IsIn(STORE_TABS)
  status: OrderStatus = 'PLACED';

  /** New tab polling: only orders placed after this time. */
  @IsOptional()
  @Type(() => Date)
  @IsDate()
  since?: Date;

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

export class DispatchDto {
  @IsUUID()
  deliveryBoyId!: string;
}
