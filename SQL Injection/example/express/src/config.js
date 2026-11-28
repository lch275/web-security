// 환경변수 기반 설정. 인증정보 기본값은 두지 않는다.
export function loadConfig(env = process.env) {
  const password = env.DB_PASSWORD;
  if (!password) {
    throw new Error('DB_PASSWORD 환경변수가 필요합니다.');
  }

  return {
    port: toInt(env.APP_PORT, 8083),
    db: {
      host: env.DB_HOST || 'localhost',
      port: toInt(env.DB_PORT, 3306),
      database: env.DB_NAME || 'express_customer_db',
      user: env.DB_USERNAME || 'express_app',
      password,
      connectionLimit: toInt(env.DB_POOL_SIZE, 10),
      connectTimeoutMs: toInt(env.DB_CONNECT_TIMEOUT_MS, 5000),
      queryTimeoutMs: toInt(env.DB_QUERY_TIMEOUT_MS, 10000),
    },
  };
}

function toInt(value, fallback) {
  if (value === undefined || value === '') {
    return fallback;
  }
  const parsed = Number.parseInt(value, 10);
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new Error(`정수 설정값이 올바르지 않습니다: ${value}`);
  }
  return parsed;
}
