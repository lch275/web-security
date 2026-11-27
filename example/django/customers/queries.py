"""ORM 조회와 직접 작성한 SQL 조회. 직접 작성한 SQL은 params 인자로만 값을 전달한다."""

from django.db import connection, transaction

from .forms import ORDERINGS
from .models import Customer


def search_ids(last_name: str, sort: str = "name") -> list[int]:
    return list(Customer.objects.filter(last_name=last_name).order_by(*ORDERINGS[sort]).values_list("id", flat=True))


def search_ids_raw(last_name: str) -> list[int]:
    """Django.md: cursor.execute(sql, params). %s는 따옴표 없이 작성한다."""
    with connection.cursor() as cursor:
        cursor.execute("SELECT id FROM customers WHERE last_name = %s ORDER BY id", [last_name])
        return [row[0] for row in cursor.fetchall()]


def search_customers_raw(last_name: str) -> list[Customer]:
    """Customer.objects.raw()에도 params를 전달한다. 모델 생성을 위해 기본 키를 포함한다."""
    return list(
        Customer.objects.raw(
            "SELECT id, last_name, created_at FROM customers WHERE last_name = %s ORDER BY id",
            [last_name],
        )
    )


def contains_ids(keyword: str) -> list[int]:
    # contains 룩업은 LIKE 와일드카드(%, _)를 이스케이프한다.
    return list(Customer.objects.filter(last_name__contains=keyword).order_by("id").values_list("id", flat=True))


def sorted_ids(sort: str) -> list[int]:
    return list(Customer.objects.order_by(*ORDERINGS[sort]).values_list("id", flat=True))


def ids_in(ids: list[int]) -> list[int]:
    if not ids:
        return []
    return list(Customer.objects.filter(id__in=ids).order_by("id").values_list("id", flat=True))


def create(last_name: str) -> Customer:
    customer = Customer.objects.create(last_name=last_name)
    customer.refresh_from_db(fields=["created_at"])  # MySQL은 RETURNING이 없어 DB 기본값을 다시 읽는다.
    return customer


def create_all(last_names: list[str]) -> list[Customer]:
    """하나의 트랜잭션으로 생성한다. 중간에 예외가 발생하면 atomic 블록 전체가 롤백된다."""
    with transaction.atomic():
        return [create(last_name) for last_name in last_names]
