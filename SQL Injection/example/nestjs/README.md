# NestJS 예제

[`SQL Injection/NestJS.md`](../../NestJS.md)를 실행 가능한 프로젝트로 구현했습니다.

| 항목 | 값 |
| --- | --- |
| 런타임 | Node.js 22 이상 (Docker: `node:24.11.1-alpine3.22`), TypeScript 5.9.3 |
| 프레임워크 | NestJS 11.2.12 (`@nestjs/platform-express`) |
| 검증 | class-validator 0.15.1, class-transformer 0.5.1 (`ValidationPipe`) |
| 드라이버 | mysql2 3.24.6 |
| 테스트 | Jest 30.2.0 + ts-jest 29.4.15 + supertest |
| 포트 | 8082 |
| DB | `nestjs_customer_db` (실행) / `nestjs_customer_test_db` (테스트), 계정 `nestjs_app` |

## 구조

```
nestjs/
├── package.json, package-lock.json, tsconfig*.json, nest-cli.json
├── src/
│   ├── main.ts                         # 진입점: enableShutdownHooks(), 본문 16KB 제한
│   ├── app.module.ts                   # 루트 모듈, /health, 요청 로그, configureApp(ValidationPipe, 필터)
│   ├── database/database.module.ts     # 'CUSTOMER_DB' 풀 provider, 종료 시 pool.end()
│   ├── common/database-exception.filter.ts  # DB 장애 503, 기타 500 (상세 비노출)
│   └── customers/
│       ├── customers.module.ts / customers.controller.ts / customers.repository.ts
│       └── dto/customer-queries.dto.ts # 문서의 CustomerSearchDto 등
├── test/customers.e2e.spec.ts          # 실제 MySQL 통합 테스트 34건
└── Dockerfile                          # build / test / runtime 스테이지
```

## 실행

아래 명령은 `SQL Injection` 디렉터리에서 실행합니다.

```bash
example/scripts/mysql.sh up
example/scripts/example.sh build nestjs     # npm ci + nest build
example/scripts/example.sh test nestjs
example/scripts/example.sh run nestjs       # http://127.0.0.1:8082
example/scripts/example.sh docker-test nestjs
```

직접 실행:

```bash
cd example/nestjs && npm ci && npm run build
export DB_HOST=127.0.0.1 DB_PORT=3306 DB_NAME=nestjs_customer_db DB_USERNAME=nestjs_app DB_PASSWORD='<NESTJS_DB_PASSWORD>'
npm start
```

환경변수는 Express 예제와 같습니다(`DB_*`, `APP_PORT`, `DB_POOL_SIZE`, `DB_CONNECT_TIMEOUT_MS`, `DB_QUERY_TIMEOUT_MS`).

## API와 예상 결과

```bash
curl -G http://127.0.0.1:8082/customers/search --data-urlencode "lastName=O'Connor"   # ["4"]
curl -G http://127.0.0.1:8082/customers/search --data-urlencode "lastName=x'; DROP TABLE customers; --"  # []
curl "http://127.0.0.1:8082/customers/search?lastName=Kim&sort=last_name"   # 400 {"message":["sort must be one of ..."]}
curl "http://127.0.0.1:8082/customers/search?lastName=Kim&debug=1"          # 400 (forbidNonWhitelisted)
```

나머지 엔드포인트(`/customers/contains`, `/sorted`, `/by-ids`, CRUD, `/batch`, `/health`)는 [example/README.md](../README.md#rest-api-contract)의 공통 계약을 따릅니다.

## 문서 요구사항 구현 위치

| NestJS.md | 구현 |
| --- | --- |
| `CustomerSearchDto` (`@IsString @Length(1,100) @Matches(/\S/)`) | `dto/customer-queries.dto.ts` |
| `ValidationPipe` | `app.module.ts` `configureApp` (전역 등록, `whitelist`/`forbidNonWhitelisted`) |
| `execute()` 바인딩, `'CUSTOMER_DB'` provider, `multipleStatements:false`, `bigNumberStrings` | `customers.repository.ts`, `database.module.ts` |
| `@IsIn(['name','recent'])` → `ORDER_BY` 매핑 | DTO + `customers.repository.ts` |
| LIKE `!` 이스케이프, `findIds` 빈 목록 단락 | `customers.repository.ts` |
| 문서의 `host: 'localhost'` 하드코딩 | `DB_HOST` 환경변수로 대체(컨테이너 실행 지원) |

중복 파라미터(`lastName=a&lastName=b`)는 배열이 되어 `@IsString`에서 400으로 거부됩니다.
