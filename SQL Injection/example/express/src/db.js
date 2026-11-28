import { createPool } from 'mysql2/promise';

// Express.md의 풀 설정에 연결 자원/타임아웃 설정을 더했다.
export function createDb(dbConfig) {
  const pool = createPool({
    host: dbConfig.host,
    port: dbConfig.port,
    database: dbConfig.database,
    user: dbConfig.user,
    password: dbConfig.password,
    multipleStatements: false,
    supportBigNumbers: true,
    bigNumberStrings: true,
    timezone: 'Z',
    charset: 'utf8mb4',
    connectionLimit: dbConfig.connectionLimit,
    maxIdle: dbConfig.connectionLimit,
    idleTimeout: 60_000,
    queueLimit: 100,
    waitForConnections: true,
    connectTimeout: dbConfig.connectTimeoutMs,
    enableKeepAlive: true,
  });

  return { pool, queryTimeoutMs: dbConfig.queryTimeoutMs };
}

// 연결 실패/장애로 분류되는 mysql2 오류 코드
const UNAVAILABLE_CODES = new Set([
  'ECONNREFUSED',
  'ECONNRESET',
  'ETIMEDOUT',
  'ENOTFOUND',
  'EAI_AGAIN',
  'EHOSTUNREACH',
  'PROTOCOL_CONNECTION_LOST',
  'PROTOCOL_SEQUENCE_TIMEOUT',
  'ER_CON_COUNT_ERROR',
  'ER_ACCESS_DENIED_ERROR',
  'POOL_ENQUEUELIMIT',
  'POOL_CLOSED',
]);

export function isDatabaseUnavailable(err) {
  return Boolean(err && (UNAVAILABLE_CODES.has(err.code) || err.message === 'Query inactivity timeout'));
}
