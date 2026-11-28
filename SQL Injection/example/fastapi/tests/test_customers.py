"""실제 MySQL(fastapi_customer_test_db)을 사용하는 통합 테스트"""

import os

import pytest
from fastapi.testclient import TestClient
from mysql.connector import errors

from app.customers import create_all
from app.db import connect_direct
from app.main import create_app

from .conftest import FIXTURES

INJECTION_PAYLOADS = [
    "' OR '1'='1",
    "O'Connor' OR '1'='1",
    "x'; DROP TABLE customers; --",
    "O'Connor' -- ",
    "O'Connor'#",
    "O'Connor'/* comment */",
    "' UNION SELECT id FROM customers -- ",
]


class TestSearch:
    def test_oconnor_returns_only_that_customer(self, client, ids):
        res = client.get("/customers/search", params={"last_name": "O'Connor"})
        assert res.status_code == 200
        assert res.json() == ids["by_name"]["O'Connor"]

    def test_unknown_last_name_returns_empty(self, client, ids):
        assert client.get("/customers/search", params={"last_name": "Nobody"}).json() == []

    @pytest.mark.parametrize("payload", INJECTION_PAYLOADS)
    def test_injection_payload_is_bound_as_value(self, client, ids, count_rows, payload):
        res = client.get("/customers/search", params={"last_name": payload})
        assert res.status_code == 200
        assert res.json() == []
        assert count_rows() == len(FIXTURES)

    def test_whitespace_is_stripped(self, client, ids):
        assert client.get("/customers/search", params={"last_name": "  Kim  "}).json() == ids["by_name"]["Kim"]

    def test_sort_keys(self, client, ids):
        older, newer = ids["by_name"]["Smith"]
        assert client.get("/customers/search?last_name=Smith&sort=name").json() == [older, newer]
        assert client.get("/customers/search?last_name=Smith&sort=recent").json() == [newer, older]

    @pytest.mark.parametrize(
        "url",
        [
            "/customers/search",
            "/customers/search?last_name=",
            "/customers/search?last_name=%20%20",
            "/customers/search?last_name=" + "a" * 101,
            "/customers/search?last_name=Kim&sort=last_name",
        ],
    )
    def test_invalid_input_returns_422(self, client, url):
        assert client.get(url).status_code == 422


class TestSortLikeIn:
    def test_sorted(self, client, ids):
        n = ids["by_name"]
        expected = [*n["Bang!Name"], *n["Kim"], *n["O'Connor"], *n["Percent%Sign"], *n["PercentXSign"],
                    *n["Smith"], *n["Under_Score"], *n["UnderXScore"]]
        assert client.get("/customers/sorted?sort=name").json() == expected
        assert client.get("/customers/sorted?sort=recent").json() == list(reversed(ids["inserted"]))
        assert client.get("/customers/sorted").status_code == 422
        assert client.get("/customers/sorted?sort=id;DROP").status_code == 422

    @pytest.mark.parametrize(
        ("keyword", "name"),
        [("r_S", "Under_Score"), ("_", "Under_Score"), ("t%S", "Percent%Sign"), ("%", "Percent%Sign"),
         ("g!N", "Bang!Name"), ("mit", "Smith")],
    )
    def test_like_wildcards_are_literal(self, client, ids, keyword, name):
        assert client.get("/customers/contains", params={"keyword": keyword}).json() == ids["by_name"][name]

    def test_in_query(self, client, ids):
        wanted = sorted([ids["by_name"]["Kim"][0], ids["by_name"]["O'Connor"][0]])
        assert client.get("/customers/by-ids", params={"ids": ",".join(map(str, wanted))}).json() == wanted
        assert client.get("/customers/by-ids?ids=").json() == []
        for url in ["/customers/by-ids", "/customers/by-ids?ids=1,abc", "/customers/by-ids?ids=1%20OR%201%3D1"]:
            assert client.get(url).status_code == 422, url


class TestCrud:
    def test_create_read_update_delete(self, client, ids):
        created = client.post("/customers", json={"last_name": "  Tester  "})
        assert created.status_code == 201
        body = created.json()
        assert body["last_name"] == "Tester"
        assert body["created_at"]
        cid = body["id"]

        assert client.get(f"/customers/{cid}").json()["last_name"] == "Tester"
        assert len(client.get("/customers?limit=2").json()) == 2

        updated = client.put(f"/customers/{cid}", json={"last_name": "D'Angelo"})
        assert updated.json()["last_name"] == "D'Angelo"

        assert client.delete(f"/customers/{cid}").status_code == 204
        assert client.get(f"/customers/{cid}").status_code == 404
        assert client.delete(f"/customers/{cid}").status_code == 404
        assert client.put(f"/customers/{cid}", json={"last_name": "X"}).status_code == 404

    def test_invalid_input(self, client):
        assert client.post("/customers", json={"last_name": "  "}).status_code == 422
        assert client.post("/customers", json={"last_name": ["a"]}).status_code == 422
        assert client.get("/customers/abc").status_code == 422
        assert client.get("/customers?limit=1000").status_code == 422


class TestTransaction:
    def test_batch_commits_all(self, client, ids, count_rows):
        res = client.post("/customers/batch", json={"last_names": ["Batch-A", "Batch-B"]})
        assert res.status_code == 201
        assert [c["last_name"] for c in res.json()] == ["Batch-A", "Batch-B"]
        assert count_rows() == len(FIXTURES) + 2

    def test_db_error_rolls_back_previous_insert(self, client, ids, raw, count_rows):
        with pytest.raises(errors.DataError) as exc_info:
            create_all(client.app.state.db, ["Rollback-A", "x" * 101])
        assert exc_info.value.errno == 1406  # ER_DATA_TOO_LONG
        with raw.cursor(prepared=True) as cursor:
            cursor.execute("SELECT COUNT(*) FROM customers WHERE last_name = %s", ("Rollback-A",))
            assert cursor.fetchone()[0] == 0
        assert count_rows() == len(FIXTURES)

    def test_batch_validation_failure_saves_nothing(self, client, ids, count_rows):
        assert client.post("/customers/batch", json={"last_names": ["Ok", ""]}).status_code == 422
        assert count_rows() == len(FIXTURES)


class TestPrivileges:
    def test_app_account_cannot_run_ddl(self, raw):
        with raw.cursor() as cursor:
            with pytest.raises(errors.ProgrammingError) as exc_info:
                cursor.execute("DROP TABLE customers")
        assert exc_info.value.errno == 1142  # ER_TABLEACCESS_DENIED_ERROR

    @pytest.mark.skipif(not os.environ.get("DB_READER_PASSWORD"), reason="DB_READER_PASSWORD 미설정")
    def test_reader_account_cannot_insert(self, settings, ids):
        reader = connect_direct(
            settings,
            user=os.environ.get("DB_READER_USERNAME", "fastapi_reader"),
            password=os.environ["DB_READER_PASSWORD"],
        )
        try:
            with reader.cursor(prepared=True) as cursor:
                cursor.execute("SELECT COUNT(*) FROM customers")
                assert cursor.fetchone()[0] == len(FIXTURES)
                with pytest.raises(errors.ProgrammingError) as exc_info:
                    cursor.execute("INSERT INTO customers (last_name) VALUES (%s)", ("Denied",))
            assert exc_info.value.errno == 1142
        finally:
            reader.close()


class TestDatabaseFailure:
    def test_unreachable_database_returns_503(self, broken_settings):
        with TestClient(create_app(broken_settings)) as broken:
            assert broken.get("/health").status_code == 503
            res = broken.get("/customers/search", params={"last_name": "Kim"})
            assert res.status_code == 503
            assert "2003" not in res.text

    def test_health_up(self, client):
        res = client.get("/health")
        assert res.status_code == 200
        assert res.json() == {"status": "UP"}
