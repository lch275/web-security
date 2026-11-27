"""FastAPI 애플리케이션 진입점"""

import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import JSONResponse
from mysql.connector import errors

from . import customers
from .config import Settings
from .db import Database, is_unavailable

logger = logging.getLogger("app")


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        logger.info("fastapi example starting (%r)", settings)
        yield
        app.state.db.close()  # 종료 시 풀의 연결을 모두 닫는다.

    app = FastAPI(title="FastAPI SQL Injection 방어 예제", lifespan=lifespan)
    app.state.db = Database(settings)
    app.include_router(customers.router)

    # 요청 로그에는 쿼리 문자열과 본문을 남기지 않는다.
    @app.middleware("http")
    async def log_requests(request: Request, call_next):
        started = time.perf_counter()
        response = await call_next(request)
        logger.info(
            "%s %s %s %.1fms", request.method, request.url.path, response.status_code,
            (time.perf_counter() - started) * 1000,
        )
        return response

    @app.exception_handler(errors.Error)
    async def handle_mysql_error(request: Request, exc: errors.Error):
        if is_unavailable(exc):
            logger.error("database unavailable: errno=%s", exc.errno)
            return JSONResponse(status_code=503, content={"detail": "데이터베이스를 사용할 수 없습니다."})
        # SQL 오류 상세는 응답에 노출하지 않는다.
        logger.error("database error: errno=%s sqlstate=%s", exc.errno, exc.sqlstate)
        return JSONResponse(status_code=500, content={"detail": "요청을 처리하지 못했습니다."})

    @app.exception_handler(Exception)
    async def handle_unexpected(request: Request, exc: Exception):
        if is_unavailable(exc):
            logger.error("database unavailable: %s", type(exc).__name__)
            return JSONResponse(status_code=503, content={"detail": "데이터베이스를 사용할 수 없습니다."})
        logger.exception("unhandled error")
        return JSONResponse(status_code=500, content={"detail": "요청을 처리하지 못했습니다."})

    @app.get("/health")
    async def health():
        def ping():
            with app.state.db.connection() as connection:
                with connection.cursor() as cursor:
                    cursor.execute("SELECT 1")
                    cursor.fetchall()

        try:
            await run_in_threadpool(ping)
            return {"status": "UP"}
        except Exception as exc:  # noqa: BLE001 - 상태 점검은 모든 오류를 DOWN으로 보고한다.
            logger.warning("health check failed: %s", type(exc).__name__)
            return JSONResponse(status_code=503, content={"status": "DOWN"})

    return app
