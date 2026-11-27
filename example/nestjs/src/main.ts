import 'reflect-metadata';

import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';

import { AppModule, configureApp } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  app.disable('x-powered-by');
  app.useBodyParser('json', { limit: '16kb' });
  configureApp(app);
  // SIGTERM/SIGINT 수신 시 onApplicationShutdown 훅(풀 종료)을 실행한다.
  app.enableShutdownHooks();

  const port = Number.parseInt(process.env.APP_PORT ?? '8082', 10);
  await app.listen(port);
  Logger.log(
    `nestjs example listening on :${port} (db=${process.env.DB_HOST || 'localhost'}:${process.env.DB_PORT || 3306}/${process.env.DB_NAME || 'nestjs_customer_db'})`,
    'Bootstrap',
  );
}

void bootstrap();
