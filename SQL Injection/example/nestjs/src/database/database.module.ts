import { Global, Inject, Logger, Module, OnApplicationShutdown } from '@nestjs/common';
import { createPool, type Pool } from 'mysql2/promise';

export const CUSTOMER_DB = 'CUSTOMER_DB';
export const QUERY_TIMEOUT_MS = 'QUERY_TIMEOUT_MS';

function intEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined || raw === '') {
    return fallback;
  }
  const value = Number.parseInt(raw, 10);
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${name} 환경변수가 올바른 정수가 아닙니다.`);
  }
  return value;
}

// NestJS.md의 createPool 설정에 접속 정보 환경변수, 연결 자원, 타임아웃 설정을 더했다.
export function createCustomerPool(): Pool {
  const password = process.env.DB_PASSWORD;
  if (!password) {
    throw new Error('DB_PASSWORD 환경변수가 필요합니다.');
  }
  const connectionLimit = intEnv('DB_POOL_SIZE', 10);
  return createPool({
    host: process.env.DB_HOST || 'localhost',
    port: intEnv('DB_PORT', 3306),
    database: process.env.DB_NAME || 'nestjs_customer_db',
    user: process.env.DB_USERNAME || 'nestjs_app',
    password,
    multipleStatements: false,
    supportBigNumbers: true,
    bigNumberStrings: true,
    timezone: 'Z',
    charset: 'utf8mb4',
    connectionLimit,
    maxIdle: connectionLimit,
    idleTimeout: 60_000,
    queueLimit: 100,
    waitForConnections: true,
    connectTimeout: intEnv('DB_CONNECT_TIMEOUT_MS', 5000),
    enableKeepAlive: true,
  });
}

@Global()
@Module({
  providers: [
    { provide: CUSTOMER_DB, useFactory: createCustomerPool },
    { provide: QUERY_TIMEOUT_MS, useFactory: () => intEnv('DB_QUERY_TIMEOUT_MS', 10000) },
  ],
  exports: [CUSTOMER_DB, QUERY_TIMEOUT_MS],
})
export class DatabaseModule implements OnApplicationShutdown {
  private readonly logger = new Logger(DatabaseModule.name);

  constructor(@Inject(CUSTOMER_DB) private readonly db: Pool) {}

  // enableShutdownHooks()로 종료 신호를 받으면 풀의 연결을 모두 반환한다.
  async onApplicationShutdown(): Promise<void> {
    await this.db.end();
    this.logger.log('MySQL pool closed');
  }
}
