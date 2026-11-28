# FastAPI 예제

[`SQL Injection/FastAPI.md`](../../FastAPI.md)를 실행 가능한 프로젝트로 구현했습니다.

| 항목 | 값 |
| --- | --- |
| 런타임 | Python 3.12 이상 (기준: Docker `python:3.13.9-slim-bookworm`, 호스트 3.15.2에서도 검증) |
| 프레임워크 | FastAPI 0.165.0, Pydantic 2.14.4, uvicorn 0.54.0 |
| 드라이버 | mysql-connector-python 26.10.0 (`cursor(prepared=True)`, 순수 Python 구현 사용) |
| 테스트 | pytest 9.2.0 + `fastapi.testclient` (httpx2 2.16.2) |
| 포트 | 8084 |
| DB | `fastapi_customer_db` (실행) / `fastapi_customer_test_db` (테스트), 계정 `fastapi_app` |

## 구조

```
fastapi/
├── requirements.txt / requirements-dev.txt / constraints.txt   # 직접/전이 의존성 고정
├── pytest.ini
├── app/
│   ├── __main__.py     # 진입점: python -m app (uvicorn, 접근 로그 비활성화)
│   ├── main.py         # create_app(): lifespan(풀 종료), 요청 로그, 예외 처리(503/500), /health
│   ├── config.py       # 환경변수 → Settings (repr에 비밀번호 미포함)
│   ├── db.py           # MySQLConnectionPool + 대기 세마포어, commit/rollback/반환 컨텍스트
│   └── customers.py    # 라우터, Pydantic 모델, SQL
├── tests/              # 실제 MySQL 통합 테스트 33건
└── Dockerfile          # test / runtime 스테이지
```

## 실행

아래 명령은 `SQL Injection` 디렉터리에서 실행합니다.

```bash
example/scripts/mysql.sh up
example/scripts/example.sh build fastapi    # .venv 생성 + pip install
example/scripts/example.sh test fastapi
example/scripts/example.sh run fastapi      # http://127.0.0.1:8084 (/docs 에서 OpenAPI 확인)
example/scripts/example.sh docker-test fastapi
```

직접 실행:

```bash
cd example/fastapi
python -m venv .venv && . .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt -c constraints.txt
export DB_HOST=127.0.0.1 DB_PORT=3306 DB_NAME=fastapi_customer_db DB_USERNAME=fastapi_app DB_PASSWORD='<FASTAPI_DB_PASSWORD>'
python -m app
```

| 환경변수 | 기본값 | 설명 |
| --- | --- | --- |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD` | `localhost`, `3306`, `fastapi_customer_db`, `fastapi_app`, (필수) | |
| `APP_HOST` / `APP_PORT` | `127.0.0.1` / `8084` | 컨테이너에서는 `0.0.0.0` |
| `DB_POOL_SIZE` | `10` | 풀 크기 = 동시 대여 상한 |
| `DB_CONNECT_TIMEOUT_SECONDS` | `5` | `connection_timeout` |
| `DB_QUERY_TIMEOUT_MS` | `10000` | 대여 시 `SET SESSION MAX_EXECUTION_TIME` (SELECT에만 적용) |

## API와 예상 결과

파라미터와 JSON 필드는 문서대로 snake_case(`last_name`)이고, 검증 실패는 FastAPI 기본값인 **422**입니다.

```bash
curl -G http://127.0.0.1:8084/customers/search --data-urlencode "last_name=O'Connor"          # [4]
curl -G http://127.0.0.1:8084/customers/search --data-urlencode "last_name=  O'Connor  "      # [4] (strip_whitespace)
curl -G http://127.0.0.1:8084/customers/search --data-urlencode "last_name=O'Connor' -- "     # []
curl "http://127.0.0.1:8084/customers/search?last_name=Kim&sort=id"                            # 422
curl -X POST http://127.0.0.1:8084/customers -H 'Content-Type: application/json' -d '{"last_name":"Tester"}'
```

## 설계 메모

- **연결 풀**: 문서는 요청마다 `connect()`를 호출합니다. 이 예제는 `MySQLConnectionPool`을 쓰되, 이 풀은 비어 있으면 기다리지 않고 즉시 `PoolError`를 내므로 `BoundedSemaphore`(최대 5초 대기)로 대여를 감쌉니다. 풀은 첫 요청 시 생성되어 DB가 내려간 상태에서도 앱이 기동하고 503을 반환합니다.
- **트랜잭션**: `Database.connection()`이 정상 종료 시 `commit`, 예외 시 `rollback` 후 연결을 반환합니다. `/customers/batch`는 하나의 연결/트랜잭션에서 실행됩니다.
- **로그**: uvicorn 접근 로그는 쿼리 문자열(검색값)을 포함하므로 끄고, 경로/상태/소요 시간만 기록합니다.
