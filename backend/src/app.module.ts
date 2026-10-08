import { Module } from '@nestjs/common';
import { AuthModule } from './auth/auth.module';
import { CatalogModule } from './catalog/catalog.module';
import { CheckoutModule } from './checkout/checkout.module';
import { CoreModule } from './core.module';
import { DatabaseModule } from './database/database.module';
import { DeliveryModule } from './delivery/delivery.module';
import { OrdersModule } from './orders/orders.module';
import { SmsModule } from './sms/sms.module';
import { StoreModule } from './store/store.module';

@Module({
  imports: [CoreModule, DatabaseModule, SmsModule, AuthModule, CatalogModule, CheckoutModule, OrdersModule, StoreModule, DeliveryModule],
})
export class AppModule {}
