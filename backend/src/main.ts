import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { configureApp } from './app.setup';
import { loadConfig } from './config/app-config';

export async function bootstrap() {
  const config = loadConfig();
  // rawBody is needed to check the payment webhook signature.
  const app = await NestFactory.create(AppModule, { rawBody: true });
  configureApp(app);
  if (config.corsOrigins.length) {
    app.enableCors({ origin: config.corsOrigins, allowedHeaders: ['authorization', 'content-type', 'idempotency-key'] });
  }
  app.enableShutdownHooks();
  await app.listen(config.port);
  new Logger('Bootstrap').log(`API ready on http://localhost:${config.port}/api/v1`);
}

if (require.main === module) bootstrap();
