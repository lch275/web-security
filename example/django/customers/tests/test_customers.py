"""실제 MySQL(django_customer_test_db)을 사용하는 통합 테스트"""

import os
from datetime import datetime, timezone

import MySQLdb
from django.conf import settings
from django.db import DataError, connection, transaction
from django.test import TestCase, TransactionTestCase

from customers import queries
from customers.models import Customer

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
INJECTION_PAYLOADS = [
    "' OR '1'='1",
    "O'Connor' OR '1'='1",
    "x'; DROP TABLE customers; --",
    "O'Connor' -- ",
    "O'Connor'#",
    "O'Connor'/* comment */",
    "' UNION SELECT id FROM customers -- ",
]


def direct_connection(user=None, password=None):
    db = settings.DATABASES["default"]
    return MySQLdb.connect(
        host=db["HOST"], port=int(db["PORT"]), database=db["NAME"],
        user=user or db["USER"], password=password or db["PASSWORD"], charset="utf8mb4",
    )


class CustomerApiTests(TestCase):
    """각 테스트는 트랜잭션 안에서 실행되고 끝나면 롤백된다."""

    @classmethod
    def setUpTestData(cls):
        Customer.objects.all().delete()
        cls.by_name: dict[str, list[int]] = {}
        cls.inserted: list[int] = []
        for last_name, created_at in FIXTURES:
            c = Customer.objects.create(
                last_name=last_name,
                created_at=datetime.fromisoformat(created_at).replace(tzinfo=timezone.utc),
            )
            cls.by_name.setdefault(last_name, []).append(c.id)
            cls.inserted.append(c.id)

    # --- 값 바인딩 ---
    def test_oconnor_returns_only_that_customer(self):
        res = self.client.get("/customers/search", {"last_name": "O'Connor"})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json(), self.by_name["O'Connor"])

    def test_unknown_last_name_returns_empty(self):
        self.assertEqual(self.client.get("/customers/search", {"last_name": "Nobody"}).json(), [])

    def test_injection_payloads_are_values(self):
        for payload in INJECTION_PAYLOADS:
            with self.subTest(payload=payload):
                res = self.client.get("/customers/search", {"last_name": payload})
                self.assertEqual(res.status_code, 200)
                self.assertEqual(res.json(), [])
        self.assertEqual(Customer.objects.count(), len(FIXTURES))

    def test_raw_sql_matches_orm(self):
        """Django.md: 직접 작성한 SQL은 같은 입력으로 ORM 조회와 결과를 비교한다."""
        for value in ["O'Connor", "Smith", "Nobody", *INJECTION_PAYLOADS]:
            with self.subTest(value=value):
                orm = sorted(queries.search_ids(value))
                self.assertEqual(queries.search_ids_raw(value), orm)
                self.assertEqual([c.id for c in queries.search_customers_raw(value)], orm)

    def test_sort_keys(self):
        older, newer = self.by_name["Smith"]
        self.assertEqual(self.client.get("/customers/search?last_name=Smith&sort=name").json(), [older, newer])
        self.assertEqual(self.client.get("/customers/search?last_name=Smith&sort=recent").json(), [newer, older])

    def test_invalid_search_returns_400(self):
        for url in [
            "/customers/search",
            "/customers/search?last_name=",
            "/customers/search?last_name=%20%20",
            "/customers/search?last_name=" + "a" * 101,
            "/customers/search?last_name=Kim&sort=last_name",
        ]:
            with self.subTest(url=url):
                res = self.client.get(url)
                self.assertEqual(res.status_code, 400)
                self.assertIn("errors", res.json())

    # --- 정렬, LIKE, IN ---
    def test_sorted(self):
        n = self.by_name
        expected = [*n["Bang!Name"], *n["Kim"], *n["O'Connor"], *n["Percent%Sign"], *n["PercentXSign"],
                    *n["Smith"], *n["Under_Score"], *n["UnderXScore"]]
        self.assertEqual(self.client.get("/customers/sorted?sort=name").json(), expected)
        self.assertEqual(self.client.get("/customers/sorted?sort=recent").json(), list(reversed(self.inserted)))
        self.assertEqual(self.client.get("/customers/sorted").status_code, 400)
        self.assertEqual(self.client.get("/customers/sorted?sort=-id").status_code, 400)

    def test_contains_escapes_wildcards(self):
        cases = [("r_S", "Under_Score"), ("_", "Under_Score"), ("t%S", "Percent%Sign"), ("%", "Percent%Sign"),
                 ("g!N", "Bang!Name"), ("mit", "Smith")]
        for keyword, name in cases:
            with self.subTest(keyword=keyword):
                self.assertEqual(self.client.get("/customers/contains", {"keyword": keyword}).json(), self.by_name[name])

    def test_contains_is_case_sensitive_on_mysql(self):
        """MySQL 백엔드의 contains는 LIKE BINARY 이므로 콜레이션과 무관하게 대소문자를 구분한다."""
        self.assertEqual(self.client.get("/customers/contains", {"keyword": "smith"}).json(), [])
        icontains = list(Customer.objects.filter(last_name__icontains="smith").order_by("id").values_list("id", flat=True))
        self.assertEqual(icontains, self.by_name["Smith"])

    def test_in_query(self):
        wanted = sorted([self.by_name["Kim"][0], self.by_name["O'Connor"][0]])
        self.assertEqual(self.client.get("/customers/by-ids", {"ids": ",".join(map(str, wanted))}).json(), wanted)
        self.assertEqual(self.client.get("/customers/by-ids?ids=").json(), [])
        for url in ["/customers/by-ids", "/customers/by-ids?ids=1,abc", "/customers/by-ids?ids=1%20OR%201%3D1"]:
            with self.subTest(url=url):
                self.assertEqual(self.client.get(url).status_code, 400)

    # --- CRUD ---
    def test_crud(self):
        created = self.client.post("/customers", {"last_name": "  Tester  "}, content_type="application/json")
        self.assertEqual(created.status_code, 201)
        body = created.json()
        self.assertEqual(body["last_name"], "Tester")
        self.assertTrue(body["created_at"])
        cid = body["id"]

        self.assertEqual(self.client.get(f"/customers/{cid}").json()["last_name"], "Tester")
        self.assertEqual(len(self.client.get("/customers?limit=2").json()), 2)

        updated = self.client.put(f"/customers/{cid}", {"last_name": "D'Angelo"}, content_type="application/json")
        self.assertEqual(updated.json()["last_name"], "D'Angelo")

        self.assertEqual(self.client.delete(f"/customers/{cid}").status_code, 204)
        self.assertEqual(self.client.get(f"/customers/{cid}").status_code, 404)
        self.assertEqual(self.client.delete(f"/customers/{cid}").status_code, 404)

    def test_invalid_input(self):
        post = lambda data: self.client.post("/customers", data, content_type="application/json")  # noqa: E731
        self.assertEqual(post({"last_name": "  "}).status_code, 400)
        self.assertEqual(post({"last_name": ["a"]}).status_code, 400)
        self.assertEqual(post("{bad").status_code, 400)
        self.assertEqual(self.client.get("/customers/abc").status_code, 400)
        self.assertEqual(self.client.get("/customers?limit=1000").status_code, 400)

    # --- 트랜잭션 ---
    def test_batch_commits_all(self):
        res = self.client.post("/customers/batch", {"last_names": ["Batch-A", "Batch-B"]}, content_type="application/json")
        self.assertEqual(res.status_code, 201)
        self.assertEqual([c["last_name"] for c in res.json()], ["Batch-A", "Batch-B"])
        self.assertEqual(Customer.objects.count(), len(FIXTURES) + 2)

    def test_db_error_rolls_back_atomic_block(self):
        with self.assertRaises(DataError):
            queries.create_all(["Rollback-A", "x" * 101])
        self.assertFalse(Customer.objects.filter(last_name="Rollback-A").exists())
        self.assertEqual(Customer.objects.count(), len(FIXTURES))

    def test_batch_validation_failure_saves_nothing(self):
        res = self.client.post("/customers/batch", {"last_names": ["Ok", ""]}, content_type="application/json")
        self.assertEqual(res.status_code, 400)
        self.assertEqual(Customer.objects.count(), len(FIXTURES))

    def test_health_up(self):
        self.assertEqual(self.client.get("/health").json(), {"status": "UP"})


class PrivilegeTests(TestCase):
    """DDL은 암묵적 커밋을 일으키므로 테스트 트랜잭션과 분리된 연결에서 확인한다."""

    def test_app_account_cannot_run_ddl(self):
        conn = direct_connection()
        try:
            with self.assertRaises(MySQLdb.OperationalError) as ctx:
                conn.cursor().execute("DROP TABLE customers")
            self.assertEqual(ctx.exception.args[0], 1142)
        finally:
            conn.close()

    def test_reader_account_cannot_insert(self):
        password = os.environ.get("DB_READER_PASSWORD")
        if not password:
            self.skipTest("DB_READER_PASSWORD 미설정")
        conn = direct_connection(os.environ.get("DB_READER_USERNAME", "django_reader"), password)
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM customers")
            with self.assertRaises(MySQLdb.OperationalError) as ctx:
                cursor.execute("INSERT INTO customers (last_name) VALUES (%s)", ["Denied"])
            self.assertEqual(ctx.exception.args[0], 1142)
        finally:
            conn.close()


class DatabaseFailureTests(TransactionTestCase):
    """연결 설정을 바꿔 DB 장애를 재현한다. 테이블을 비우는 기본 teardown(flush)은 사용하지 않는다."""

    def _fixture_teardown(self):
        pass

    def test_unreachable_database_returns_503(self):
        original = dict(connection.settings_dict)
        connection.close()
        connection.settings_dict.update(HOST="127.0.0.1", PORT="1")
        try:
            self.assertEqual(self.client.get("/health").status_code, 503)
            res = self.client.get("/customers/search", {"last_name": "Kim"})
            self.assertEqual(res.status_code, 503)
            self.assertNotIn("2003", res.content.decode())
        finally:
            connection.close()
            connection.settings_dict.clear()
            connection.settings_dict.update(original)
        with transaction.atomic():
            self.assertGreaterEqual(Customer.objects.count(), 0)  # 원래 설정으로 복구되었는지 확인
