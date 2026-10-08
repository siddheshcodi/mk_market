import { Global, Module } from '@nestjs/common';
import { Clock, SystemClock } from './common/clock';
import { APP_CONFIG, loadConfig } from './config/app-config';

@Global()
@Module({
  providers: [
    { provide: APP_CONFIG, useFactory: () => loadConfig() },
    { provide: Clock, useClass: SystemClock },
  ],
  exports: [APP_CONFIG, Clock],
})
export class CoreModule {}
