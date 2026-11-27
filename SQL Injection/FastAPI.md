# FastAPI에서 MySQL을 사용할 때의 SQL Injection 방어

## MySQL 예제 환경

[Java와 Spring 예제](Spring.md#mysql-예제-환경)와 같은 MySQL 8.4의 `customer_db.customers` 테이블을 사용한다. FastAPI 0.115 이상, Pydantic 2, `mysql-connector-python`을 사용한다. 예제는 동기 MySQL 드라이버를 사용하므로 라우트 함수를 `def`로 선언한다. [FastAPI 쿼리 파라미터 모델](https://fastapi.tiangolo.com/tutorial/query-param-models/) · [FastAPI 동기 및 비동기 처리](https://fastapi.tiangolo.com/async/)

## 요청 모델 검증과 값 바인딩

Pydantic 모델에서 `last_name`의 앞뒤 공백을 제거한 뒤 길이가 1~100자인지 확인한다. `sort`는 `name`과 `recent`만 허용한다. `cursor(prepared=True)`로 준비된 문을 사용하고, `%s`에 넣을 값을 튜플로 전달한다. 원소가 하나인 튜플에도 쉼표를 붙이며 SQL의 `%s`에는 따옴표를 쓰지 않는다. [Connector/Python 준비된 커서](https://dev.mysql.com/doc/connector-python/en/connector-python-api-mysqlcursorprepared.html)

```python
import os
from typing import Annotated, Literal

import mysql.connector
from fastapi import FastAPI, Query
from pydantic import BaseModel, StringConstraints

app = FastAPI()
ORDER_BY = {
    "name": "last_name ASC, id ASC",
    "recent": "created_at DESC, id DESC",
}


class CustomerSearch(BaseModel):
    last_name: Annotated[
        str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)
    ]
    sort: Literal["name", "recent"] = "name"


@app.get("/customers/search")
def search_customers(query: Annotated[CustomerSearch, Query()]) -> list[int]:
    sql = (
        "SELECT id FROM customers WHERE last_name = %s ORDER BY "
        + ORDER_BY[query.sort]
    )
    with mysql.connector.connect(
        host="localhost",
        database="customer_db",
        user=os.environ["MYSQL_USER"],
        password=os.environ["MYSQL_PASSWORD"],
    ) as connection:
        with connection.cursor(prepared=True) as cursor:
            cursor.execute(sql, (query.last_name,))
            return [row[0] for row in cursor.fetchall()]
```

`/customers/search?last_name=O%27Connor`에서 작은따옴표는 성의 일부로 처리된다. 세미콜론이나 SQL 주석 표기가 포함된 값도 하나의 검색값으로 바인딩된다. 기존 조회 조건이 유지되며 일치하는 성이 없으면 빈 목록을 반환한다. [MySQL 준비된 문](https://dev.mysql.com/doc/refman/8.4/en/prepare.html)

## 동적 정렬과 검색 조건

`ORDER BY` 뒤에는 `ORDER_BY`에 정의된 표현식만 붙인다. `IN` 조회에는 검증한 ID 수만큼 `%s`를 만들고 ID 튜플을 별도로 전달한다. ID가 없으면 빈 결과를 반환한다.

`LIKE`에서 `%`와 `_`를 일반 문자로 처리하려면 이스케이프 문자를 지정하고 패턴 전체를 바인딩한다. 다음 코드는 준비된 커서로 실행한다. [MySQL `LIKE`](https://dev.mysql.com/doc/refman/8.4/en/string-comparison-functions.html)

```python
literal = search_text.replace("!", "!!").replace("%", "!%").replace("_", "!_")
cursor.execute(
    "SELECT id FROM customers WHERE last_name LIKE %s ESCAPE '!'",
    (f"%{literal}%",),
)
```

## 운영과 검증

- 조회 계정에는 필요한 테이블이나 뷰의 `SELECT` 권한만 부여한다. 스키마 변경에는 별도 계정을 사용한다. [MySQL `GRANT`](https://dev.mysql.com/doc/refman/8.4/en/grant.html)
- MySQL 통합 테스트에서 `O'Connor` 검색은 해당 고객만 반환하고, 일치하지 않는 주석 표기 포함 문자열은 빈 결과를 반환하는지 확인한다. `last_name` 누락, 공백만 있는 값, 길이 초과와 미등록 정렬 키에는 HTTP 422를 반환하는지 확인한다. 허용한 정렬 순서와 `LIKE`의 일반 문자 검색도 검증한다.
