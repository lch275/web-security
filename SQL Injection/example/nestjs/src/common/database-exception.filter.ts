import { ArgumentsHost, Catch, ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import type { Response } from 'express';

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

export function isDatabaseUnavailable(err: unknown): boolean {
  const e = err as { code?: string; message?: string } | undefined;
  return Boolean(e && ((e.code && UNAVAILABLE_CODES.has(e.code)) || e.message === 'Query inactivity timeout'));
}

// HttpException은 그대로 응답하고, DB 오류는 상세 정보를 숨긴 채 503/500으로 변환한다.
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost): void {
    const res = host.switchToHttp().getResponse<Response>();

    if (exception instanceof HttpException) {
      res.status(exception.getStatus()).json(exception.getResponse());
      return;
    }

    const err = exception as { code?: string; name?: string; message?: string; sqlMessage?: string };
    if (isDatabaseUnavailable(err)) {
      this.logger.error(`database unavailable: ${err.code ?? err.message}`);
      res.status(503).json({ statusCode: 503, message: '데이터베이스를 사용할 수 없습니다.' });
      return;
    }

    this.logger.error(`unhandled error: ${err.code ?? err.name}: ${err.sqlMessage ?? err.message}`);
    res.status(500).json({ statusCode: 500, message: '요청을 처리하지 못했습니다.' });
  }
}
