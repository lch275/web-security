# Express 예제

[`SQL Injection/Express.md`](../../Express.md)를 실행 가능한 프로젝트로 구현했습니다.

| 항목 | 값 |
| --- | --- |
| 런타임 | Node.js 22 이상 (Docker: `node:24.11.1-alpine3.22`) |
| 프레임워크 | Express 5.3.0 (ES 모듈) |
| 드라이버 | mysql2 3.24.6 (`mysql2/promise`, `execute()` 준비된 문) |
| 테스트 | Node.js 내장 `node:test` + supertest 7.3.2 |
| 포트 | 8083 |
| DB | `express_customer_db` (실행) / `express_customer_test_db` (테스트), 계정 `express_app` |

## 구조

```
express/
├── package.json, package-lock.json   # 의존성 버전 고정
├── src/
│   ├── server.js                     # 진입점: listen, SIGINT/SIGTERM 시 풀 종료
│   ├── app.js                        # createApp(db): 미들웨어, /health, 오류 처리(400/503/500)
│   ├── config.js                     # 환경변수 → 설정
│   ├── db.js                         # mysql2 풀(multipleStatements:false, bigNumberStrings 등)
│   └── customers/
│       ├── routes.js                 # REST 라우트
│       ├── repository.js             # SQL (바인딩, 정렬 허용 목록, LIKE 이스케이프, IN, 트랜잭션)
│       └── validation.js             # 요청값 검증
├── test/customers.test.js            # 실제 MySQL 통합 테스트 23건
└── Dockerfile                        # test / runtime 스테이지
```

## 실행

아래 명령은 `SQL Injection` 디렉터리에서 실행합니다.

MySQL을 먼저 기동합니다: `example/scripts/mysql.sh up` (PowerShell: `.\example\scripts\mysql.ps1 up`)

```bash
example/scripts/example.sh build express    # npm ci + 구문 검사
example/scripts/example.sh test express     # 통합 테스트 (express_customer_test_db)
example/scripts/example.sh run express      # http://127.0.0.1:8083
example/scripts/example.sh docker-test express
example/scripts/example.sh docker-run express && example/scripts/example.sh smoke express
```

스크립트 없이 직접 실행할 때는 환경변수를 설정합니다(비밀번호는 `example/dbms/mysql/.env`의 `EXPRESS_DB_PASSWORD`).

```bash
cd example/express
npm ci
export DB_HOST=127.0.0.1 DB_PORT=3306 DB_NAME=express_customer_db DB_USERNAME=express_app DB_PASSWORD='<EXPRESS_DB_PASSWORD>'
npm start
```

| 환경변수 | 기본값 | 설명 |
| --- | --- | --- |
| `DB_HOST` / `DB_PORT` | `localhost` / `3306` | 컨테이너에서는 `mysql` / `3306` |
| `DB_NAME` | `express_customer_db` | 테스트는 `*_test_db`만 허용 |
| `DB_USERNAME` / `DB_PASSWORD` | `express_app` / (필수) | |
| `APP_PORT` | `8083` | |
| `DB_POOL_SIZE` | `10` | `connectionLimit` |
| `DB_CONNECT_TIMEOUT_MS` | `5000` | 연결 타임아웃 |
| `DB_QUERY_TIMEOUT_MS` | `10000` | `execute({ sql, timeout })` 쿼리 타임아웃 |
| `DB_READER_USERNAME` / `DB_READER_PASSWORD` | - | 테스트의 SELECT 전용 계정 검증용 |

## API와 예상 결과 (데모 DB 시드 기준)

```bash
curl -G http://127.0.0.1:8083/customers/search --data-urlencode "lastName=O'Connor"      # ["4"]
curl -G http://127.0.0.1:8083/customers/search --data-urlencode "lastName=' OR '1'='1"   # []
curl "http://127.0.0.1:8083/customers/search?lastName=Kim&lastName=Lee"                  # 400 (중복 파라미터)
curl "http://127.0.0.1:8083/customers/sorted?sort=recent"                                # ["9","8",...]
curl "http://127.0.0.1:8083/customers/sorted?sort=id"                                    # 400
curl -G http://127.0.0.1:8083/customers/contains --data-urlencode "keyword=%"            # ["8"] (Percent%Sign)
curl "http://127.0.0.1:8083/customers/by-ids?ids=1,2"                                    # ["1","2"]
curl -X POST http://127.0.0.1:8083/customers -H 'Content-Type: application/json' -d '{"lastName":"Tester"}'   # 201
curl -X POST http://127.0.0.1:8083/customers/batch -H 'Content-Type: application/json' -d '{"lastNames":["A","B"]}'
curl http://127.0.0.1:8083/health                                                        # {"status":"UP"} / DB 장애 시 503
```

ID는 문서대로 `bigNumberStrings`에 의해 문자열로 반환됩니다. 실제 ID 값은 시드 순서에 따릅니다.

## 문서 요구사항 구현 위치

| Express.md | 구현 |
| --- | --- |
| `req.query.lastName` 단일 문자열 확인, 공백/100자(코드 포인트) 검사 | `validation.js` `requireLastName` |
| `execute()`에 값 배열 전달 | `repository.js` 전체 |
| `multipleStatements:false`, `supportBigNumbers`, `bigNumberStrings` | `db.js` |
| `sortOrders` Map 허용 목록, `/customers/sorted` | `repository.js`, `routes.js` |
| `IN` 자리표시자 생성, 빈 목록 단락 | `repository.js` `findIds` |
| `LIKE ? ESCAPE '!'` | `repository.js` `escapeLike` |
| 누락/빈 값/중복 파라미터 400, 정렬 순서, `%`/`_` 일반 문자 테스트 | `test/customers.test.js` |
