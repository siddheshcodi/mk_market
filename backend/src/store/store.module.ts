import { Module } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { StoreController } from './store.controller';
import { StoreOrdersService } from './store-orders.service';

@Module({
  imports: [OrdersModule],
  controllers: [StoreController],
  providers: [StoreOrdersService],
})
export class StoreModule {}
