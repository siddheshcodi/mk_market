import { Module } from '@nestjs/common';
import { APP_CONFIG, AppConfig } from '../config/app-config';
import { DevMapsProvider, GoogleMapsProvider, MapsProvider } from './maps-provider';
import { ServiceabilityService } from './serviceability.service';

@Module({
  providers: [
    {
      provide: MapsProvider,
      inject: [APP_CONFIG],
      useFactory: ({ maps }: AppConfig) =>
        maps.provider === 'google' ? new GoogleMapsProvider(maps.googleApiKey!) : new DevMapsProvider(),
    },
    ServiceabilityService,
  ],
  exports: [MapsProvider, ServiceabilityService],
})
export class MapsModule {}
