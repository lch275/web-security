"""고객 API. 모든 요청값은 준비된 커서의 튜플 파라미터로 바인딩한다."""

from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Path, Query, Request, Response, status
from pydantic import BaseModel, Field, StringConstraints

from .db import Database

router = APIRouter(prefix="/customers", tags=["customers"])

# FastAPI.md: ORDER BY 뒤에는 이 매핑에 정의된 표현식만 붙인다.
ORDER_BY = {
    "name": "last_name ASC, id ASC",
    "recent": "created_at DESC, id DESC",
}
COLUMNS = "id, last_name, created_at"

LastName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]
CustomerId = Annotated[int, Path(gt=0, le=9_223_372_036_854_775_807)]


class CustomerSearch(BaseModel):
    """FastAPI.md의 쿼리 파라미터 모델"""

    last_name: LastName
    sort: Literal["name", "recent"] = "name"


class CustomerIn(BaseModel):
    last_name: LastName


class CustomerBatchIn(BaseModel):
    last_names: Annotated[list[LastName], Field(min_length=1, max_length=100)]


class Customer(BaseModel):
    id: int
    last_name: str
    created_at: datetime


def escape_like(text: str) -> str:
    return text.replace("!", "!!").replace("%", "!%").replace("_", "!_")


def _db(request: Request) -> Database:
    return request.app.state.db


def _fetch_ids(db: Database, sql: str, params: tuple = ()) -> list[int]:
    with db.connection() as connection:
        with connection.cursor(prepared=True) as cursor:
            cursor.execute(sql, params)
            return [row[0] for row in cursor.fetchall()]


def _to_customer(row) -> Customer:
    return Customer(id=row[0], last_name=row[1], created_at=row[2])


def _find_by_id(cursor, customer_id: int) -> Customer | None:
    cursor.execute(f"SELECT {COLUMNS} FROM customers WHERE id = %s", (customer_id,))
    row = cursor.fetchone()
    return _to_customer(row) if row else None


def _insert(cursor, last_name: str) -> Customer:
    cursor.execute("INSERT INTO customers (last_name) VALUES (%s)", (last_name,))
    return _find_by_id(cursor, cursor.lastrowid)


def create_all(db: Database, last_names: list[str]) -> list[Customer]:
    """하나의 트랜잭션으로 INSERT 한다. 중간에 실패하면 Database.connection()이 롤백한다."""
    with db.connection() as connection:
        with connection.cursor(prepared=True) as cursor:
            return [_insert(cursor, last_name) for last_name in last_names]


# 동기 드라이버를 사용하므로 라우트는 def로 선언한다(스레드 풀에서 실행).
@router.get("/search")
def search_customers(request: Request, query: Annotated[CustomerSearch, Query()]) -> list[int]:
    sql = "SELECT id FROM customers WHERE last_name = %s ORDER BY " + ORDER_BY[query.sort]
    return _fetch_ids(_db(request), sql, (query.last_name,))


@router.get("/contains")
def contains(request: Request, keyword: Annotated[str, Query(min_length=1, max_length=100)]) -> list[int]:
    literal = escape_like(keyword)
    return _fetch_ids(
        _db(request),
        "SELECT id FROM customers WHERE last_name LIKE %s ESCAPE '!' ORDER BY id",
        (f"%{literal}%",),
    )


@router.get("/sorted")
def sorted_ids(request: Request, sort: Literal["name", "recent"]) -> list[int]:
    return _fetch_ids(_db(request), "SELECT id FROM customers ORDER BY " + ORDER_BY[sort])


@router.get("/by-ids")
def by_ids(
    request: Request,
    ids: Annotated[str, Query(max_length=2000, pattern=r"^$|^[1-9][0-9]{0,17}(,[1-9][0-9]{0,17}){0,99}$")],
) -> list[int]:
    id_list = sorted({int(part) for part in ids.split(",")}) if ids else []
    if not id_list:
        return []  # 빈 목록은 DB 호출 없이 빈 결과
    placeholders = ", ".join(["%s"] * len(id_list))
    return _fetch_ids(_db(request), f"SELECT id FROM customers WHERE id IN ({placeholders}) ORDER BY id", tuple(id_list))


@router.get("")
def list_customers(
    request: Request,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0, le=100_000)] = 0,
) -> list[Customer]:
    with _db(request).connection() as connection:
        with connection.cursor(prepared=True) as cursor:
            cursor.execute(f"SELECT {COLUMNS} FROM customers ORDER BY id LIMIT %s OFFSET %s", (limit, offset))
            return [_to_customer(row) for row in cursor.fetchall()]


@router.post("/batch", status_code=status.HTTP_201_CREATED)
def create_batch(request: Request, body: CustomerBatchIn) -> list[Customer]:
    return create_all(_db(request), body.last_names)


@router.post("", status_code=status.HTTP_201_CREATED)
def create_customer(request: Request, body: CustomerIn) -> Customer:
    with _db(request).connection() as connection:
        with connection.cursor(prepared=True) as cursor:
            return _insert(cursor, body.last_name)


@router.get("/{customer_id}")
def get_customer(request: Request, customer_id: CustomerId) -> Customer:
    with _db(request).connection() as connection:
        with connection.cursor(prepared=True) as cursor:
            customer = _find_by_id(cursor, customer_id)
    if customer is None:
        raise HTTPException(status_code=404, detail="고객을 찾을 수 없습니다.")
    return customer


@router.put("/{customer_id}")
def update_customer(request: Request, customer_id: CustomerId, body: CustomerIn) -> Customer:
    with _db(request).connection() as connection:
        with connection.cursor(prepared=True) as cursor:
            cursor.execute("UPDATE customers SET last_name = %s WHERE id = %s", (body.last_name, customer_id))
            customer = _find_by_id(cursor, customer_id) if cursor.rowcount else None
    if customer is None:
        raise HTTPException(status_code=404, detail="고객을 찾을 수 없습니다.")
    return customer


@router.delete("/{customer_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_customer(request: Request, customer_id: CustomerId) -> Response:
    with _db(request).connection() as connection:
        with connection.cursor(prepared=True) as cursor:
            cursor.execute("DELETE FROM customers WHERE id = %s", (customer_id,))
            deleted = cursor.rowcount > 0
    if not deleted:
        raise HTTPException(status_code=404, detail="고객을 찾을 수 없습니다.")
    return Response(status_code=status.HTTP_204_NO_CONTENT)
