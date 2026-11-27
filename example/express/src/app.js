import express from 'express';

import { isDatabaseUnavailable } from './db.js';
import { createCustomerRepository } from './customers/repository.js';
import { customerRoutes } from './customers/routes.js';
import { ValidationError } from './customers/validation.js';

export function createApp(db, logger = console) {
  const repository = createCustomerRepository(db);
  const app = express();

  app.disable('x-powered-by');
  app.use(express.json({ limit: '16kb' }));

  // 요청 로그에는 쿼리 문자열과 본문(검색값 등)을 남기지 않는다.
  app.use((req, res, next) => {
    const started = process.hrtime.bigint();
    res.on('finish', () => {
      const ms = Number(process.hrtime.bigint() - started) / 1e6;
      logger.info(`${req.method} ${req.path} ${res.statusCode} ${ms.toFixed(1)}ms`);
    });
    next();
  });

  app.get('/health', async (req, res) => {
    try {
      await repository.ping();
      res.json({ status: 'UP' });
    } catch (err) {
      logger.warn(`health check failed: ${err.code ?? err.name}`);
      res.status(503).json({ status: 'DOWN' });
    }
  });

  app.use('/customers', customerRoutes(repository));

  app.use((req, res) => {
    res.status(404).json({ error: '요청한 경로를 찾을 수 없습니다.' });
  });

  // Express 5는 async 핸들러의 거부를 이 오류 처리기로 전달한다.
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err instanceof ValidationError) {
      return res.status(400).json({ error: err.message });
    }
    if (err.type === 'entity.parse.failed' || err.type === 'entity.too.large') {
      return res.status(err.status ?? 400).json({ error: '요청 본문이 올바르지 않습니다.' });
    }
    if (isDatabaseUnavailable(err)) {
      logger.error(`database unavailable: ${err.code ?? err.message}`);
      return res.status(503).json({ error: '데이터베이스를 사용할 수 없습니다.' });
    }
    // SQL 오류 상세나 입력값은 응답에 노출하지 않는다.
    logger.error(`unhandled error: ${err.code ?? err.name}: ${err.sqlMessage ?? err.message}`);
    return res.status(500).json({ error: '요청을 처리하지 못했습니다.' });
  });

  return app;
}
