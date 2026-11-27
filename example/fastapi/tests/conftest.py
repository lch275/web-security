import os
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.db import connect_direct
from app.main import create_app

os.environ.setdefault("DB_NAME", "fastapi_customer_test_db")

FIXTURES = [
    ("O'Connor", "2026-01-01 10:00:00"),
    ("Kim", "2026-01-02 10:00:00"),
    ("Smith", "2026-01-03 10:00:00"),
    ("Smith", "2026-01-04 10:00:00"),
    ("Under_Score", "2026-01-05 10:00:00"),
    ("UnderXScore", "2026-01-06 10:00:00"),
    ("Percent%Sign", "2026-01-07 10:00:00"),
    ("PercentXSign", "2026-01-08 10:00:00"),
    ("Bang!Name", "2026-01-09 10:00:00"),
]


@pytest.fixture(scope="session")
def settings() -> Settings:
    s = Settings.from_env()
    if not s.db_name.endswith("_test_db"):
        pytest.exit(f"테스트는 *_test_db 에서만 실행합니다. 현재 DB_NAME={s.db_name}", returncode=2)
    return s


@pytest.fixture(scope="session")
def client(settings):
    with TestClient(create_app(settings)) as c:  # lifespan 종료 시 풀을 닫는다.
        yield c


@pytest.fixture(scope="session")
def raw(settings):
    connection = connect_direct(settings, autocommit=True)
    yield connection
    with connection.cursor() as cursor:
        cursor.execute("DELETE FROM customers")
    connection.close()


@pytest.fixture()
def ids(raw) -> dict:
    """테이블을 비우고 고정 데이터를 넣는다. {'by_name': {...}, 'inserted': [...]}"""
    by_name: dict[str, list[int]] = {}
    inserted: list[int] = []
    with raw.cursor(prepared=True) as cursor:
        cursor.execute("DELETE FROM customers")
        for last_name, created_at in FIXTURES:
            cursor.execute("INSERT INTO customers (last_name, created_at) VALUES (%s, %s)", (last_name, created_at))
            by_name.setdefault(last_name, []).append(cursor.lastrowid)
            inserted.append(cursor.lastrowid)
    return {"by_name": by_name, "inserted": inserted}


@pytest.fixture()
def count_rows(raw):
    def count() -> int:
        with raw.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) FROM customers")
            return cursor.fetchone()[0]

    return count


@pytest.fixture()
def broken_settings(settings) -> Settings:
    return replace(settings, db_host="127.0.0.1", db_port=1, connect_timeout_seconds=1)
