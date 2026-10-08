import { Global, Module } from '@nestjs/common';
import { APP_CONFIG, AppConfig } from '../config/app-config';
import { ConsoleSmsSender, Msg91SmsSender, SmsSender } from './sms-sender';

@Global()
@Module({
  providers: [
    {
      provide: SmsSender,
      inject: [APP_CONFIG],
      useFactory: ({ sms }: AppConfig) =>
        sms.provider === 'msg91'
          ? new Msg91SmsSender(sms.msg91AuthKey!, sms.msg91LoginOtpTemplateId!, sms.msg91DeliveryOtpTemplateId)
          : new ConsoleSmsSender(),
    },
  ],
  exports: [SmsSender],
})
export class SmsModule {}
