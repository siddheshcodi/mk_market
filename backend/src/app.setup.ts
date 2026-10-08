import { INestApplication } from '@nestjs/common';
import { AllExceptionsFilter } from './common/http-exception.filter';
import { createValidationPipe } from './common/validation';

/** Shared by main.ts and the tests so both run the same pipeline. */
export function configureApp(app: INestApplication) {
  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(createValidationPipe());
  app.useGlobalFilters(new AllExceptionsFilter());
  return app;
}
