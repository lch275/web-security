import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { createDb } from './db.js';

const config = loadConfig();
const db = createDb(config.db);
const app = createApp(db);

const server = app.listen(config.port, () => {
  // 비밀번호는 로그에 남기지 않는다.
  console.info(`express example listening on :${config.port} (db=${config.db.host}:${config.db.port}/${config.db.database})`);
});

// 종료 신호를 받으면 새 연결을 막고 풀의 연결을 모두 반환한 뒤 종료한다.
let closing = false;
function shutdown(signal) {
  if (closing) {
    return;
  }
  closing = true;
  console.info(`${signal} received, shutting down`);
  server.close(async () => {
    await db.pool.end().catch((err) => console.error(`pool close failed: ${err.code ?? err.message}`));
    console.info('shutdown complete');
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
