"""환경변수 기반 설정. 인증정보 기본값은 두지 않는다."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    db_host: str
    db_port: int
    db_name: str
    db_username: str
    db_password: str
    pool_size: int = 10
    pool_wait_seconds: float = 5.0
    connect_timeout_seconds: int = 5
    query_timeout_ms: int = 10000

    @classmethod
    def from_env(cls, env: dict[str, str] | None = None) -> "Settings":
        env = os.environ if env is None else env
        password = env.get("DB_PASSWORD")
        if not password:
            raise RuntimeError("DB_PASSWORD 환경변수가 필요합니다.")
        return cls(
            db_host=env.get("DB_HOST") or "localhost",
            db_port=int(env.get("DB_PORT") or 3306),
            db_name=env.get("DB_NAME") or "fastapi_customer_db",
            db_username=env.get("DB_USERNAME") or "fastapi_app",
            db_password=password,
            pool_size=int(env.get("DB_POOL_SIZE") or 10),
            connect_timeout_seconds=int(env.get("DB_CONNECT_TIMEOUT_SECONDS") or 5),
            query_timeout_ms=int(env.get("DB_QUERY_TIMEOUT_MS") or 10000),
        )

    def __repr__(self) -> str:  # 비밀번호가 로그에 출력되지 않도록 한다.
        return f"Settings(db={self.db_host}:{self.db_port}/{self.db_name}, user={self.db_username})"
