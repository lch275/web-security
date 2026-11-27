"""mysql-connector-python 연결 풀.

FastAPI.md는 요청마다 connect()를 호출한다. 이 예제는 연결 재사용을 위해 MySQLConnectionPool을 사용하고,
준비된 커서(cursor(prepared=True))와 튜플 바인딩은 문서와 동일하게 유지한다.
"""

import logging
import threading
from collections.abc import Iterator
from contextlib import contextmanager

import mysql.connector
from mysql.connector import errors
from mysql.connector.pooling import MySQLConnectionPool, PooledMySQLConnection

from .config import Settings

logger = logging.getLogger(__name__)

# 연결 실패/장애로 분류하는 MySQL 클라이언트/서버 오류 번호
UNAVAILABLE_ERRNOS = {1040, 1045, 1129, 2002, 2003, 2005, 2006, 2013, 2055, 3024}


class DatabaseUnavailable(Exception):
    """DB 연결을 얻을 수 없거나 연결이 끊긴 경우"""


def is_unavailable(exc: BaseException) -> bool:
    if isinstance(exc, (DatabaseUnavailable, errors.PoolError, errors.InterfaceError)):
        return True
    return isinstance(exc, errors.Error) and exc.errno in UNAVAILABLE_ERRNOS


class Database:
    def __init__(self, settings: Settings):
        self.settings = settings
        self._pool: MySQLConnectionPool | None = None
        self._lock = threading.Lock()
        # MySQLConnectionPool은 풀이 비면 대기하지 않고 즉시 오류를 낸다.
        # 세마포어로 대기 시간을 두어 동시 요청이 풀 크기를 넘을 때도 안정적으로 처리한다.
        self._slots = threading.BoundedSemaphore(settings.pool_size)

    def _get_pool(self) -> MySQLConnectionPool:
        # DB가 내려간 상태에서도 앱이 기동되도록 첫 사용 시점에 풀을 만든다.
        if self._pool is None:
            with self._lock:
                if self._pool is None:
                    s = self.settings
                    self._pool = MySQLConnectionPool(
                        pool_name=f"{s.db_name}_pool",
                        pool_size=s.pool_size,
                        pool_reset_session=True,
                        host=s.db_host,
                        port=s.db_port,
                        database=s.db_name,
                        user=s.db_username,
                        password=s.db_password,
                        charset="utf8mb4",
                        collation="utf8mb4_0900_ai_ci",
                        time_zone="+00:00",
                        autocommit=False,
                        connection_timeout=s.connect_timeout_seconds,
                        use_pure=True,
                    )
        return self._pool

    @contextmanager
    def connection(self) -> Iterator[PooledMySQLConnection]:
        """풀에서 연결을 빌려 작업 후 commit, 예외 시 rollback 하고 항상 반환한다."""
        if not self._slots.acquire(timeout=self.settings.pool_wait_seconds):
            raise DatabaseUnavailable("connection pool wait timeout")
        connection = None
        try:
            connection = self._get_pool().get_connection()
            # 풀 반환 시 세션이 초기화되므로 빌릴 때마다 SELECT 실행 시간 제한을 설정한다.
            with connection.cursor() as cursor:
                cursor.execute("SET SESSION MAX_EXECUTION_TIME = %s", (self.settings.query_timeout_ms,))
            yield connection
            connection.commit()
        except BaseException:
            if connection is not None:
                try:
                    connection.rollback()
                except errors.Error:
                    pass
            raise
        finally:
            if connection is not None:
                connection.close()  # PooledMySQLConnection.close()는 풀에 반환한다.
            self._slots.release()

    def close(self) -> None:
        if self._pool is not None:
            self._pool._remove_connections()  # 공개 종료 API가 없어 내부 메서드를 사용한다.
            logger.info("MySQL pool closed")


def connect_direct(settings: Settings, **overrides) -> mysql.connector.MySQLConnection:
    """테스트 준비용 단일 연결"""
    params = dict(
        host=settings.db_host,
        port=settings.db_port,
        database=settings.db_name,
        user=settings.db_username,
        password=settings.db_password,
        charset="utf8mb4",
        time_zone="+00:00",
        connection_timeout=settings.connect_timeout_seconds,
        use_pure=True,
    )
    params.update(overrides)
    return mysql.connector.connect(**params)
