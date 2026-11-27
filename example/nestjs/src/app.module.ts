import {
  Controller,
  Get,
  HttpStatus,
  INestApplication,
  Logger,
  MiddlewareConsumer,
  Module,
  NestModule,
  Res,
  ValidationPipe,
} from '@nestjs/common';
import type { NextFunction, Request, Response } from 'express';

import { AllExceptionsFilter } from './common/database-exception.filter';
import { CustomersModule } from './customers/customers.module';
import { CustomersRepository } from './customers/customers.repository';
import { DatabaseModule } from './database/database.module';

@Controller('health')
class HealthController {
  private readonly logger = new Logger(HealthController.name);

  constructor(private readonly customers: CustomersRepository) {}

  @Get()
  async health(@Res({ passthrough: true }) res: Response): Promise<{ status: string }> {
    try {
      await this.customers.ping();
      return { status: 'UP' };
    } catch (err) {
      this.logger.warn(`health check failed: ${(err as { code?: string }).code ?? 'unknown'}`);
      res.status(HttpStatus.SERVICE_UNAVAILABLE);
      return { status: 'DOWN' };
    }
  }
}

@Module({
  imports: [DatabaseModule, CustomersModule],
  controllers: [HealthController],
})
export class AppModule implements NestModule {
  // 요청 로그에는 쿼리 문자열과 본문을 남기지 않는다.
  configure(consumer: MiddlewareConsumer): void {
    const logger = new Logger('HTTP');
    consumer
      .apply((req: Request, res: Response, next: NextFunction) => {
        const started = process.hrtime.bigint();
        res.on('finish', () => {
          const ms = Number(process.hrtime.bigint() - started) / 1e6;
          logger.log(`${req.method} ${req.path} ${res.statusCode} ${ms.toFixed(1)}ms`);
        });
        next();
      })
      .forRoutes('*path');
  }
}

// main.ts와 테스트가 같은 설정을 사용하도록 분리했다.
export function configureApp(app: INestApplication): INestApplication {
  app.useGlobalPipes(
    new ValidationPipe({
      transform: true,
      whitelist: true,
      forbidNonWhitelisted: true,
    }),
  );
  app.useGlobalFilters(new AllExceptionsFilter());
  return app;
}
