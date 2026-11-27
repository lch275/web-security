# 구현 계획 (IMPLEMENTATION_PLAN)

작성일: 2026-11-27

## 1. Repository 분석 결과

| 항목 | 결과 |
| --- | --- |
| 추적 파일 | `SQL Injection/` 하위 Markdown 6개 (README, Spring, NestJS, Express, FastAPI, Django) |
| 작업 지침 | `AGENTS.md`, `CLAUDE.md` 없음 |
| 기존 예제 코드 | 별도 소스 파일 없음. Markdown 내 코드 스니펫만 존재 |
| 기존 빌드 설정 | 없음 (`pom.xml`, `package.json` 등 없음) → 예제 프로젝트를 편입시킬 대상 없음 |
| 기존 `example/` | 없음 (신규 생성) |
| 공통 DB | MySQL 8.4, `customer_db.customers(id BIGINT AI PK, last_name VARCHAR(100), created_at TIMESTAMP)` |
| 문서 주제 | SQL Injection 방어 (값 바인딩, 입력값 검증, 허용 목록, 최소 권한) |

### 문서별 추출 요구사항

| 문서 | 프레임워크/버전 | 드라이버 | 핵심 요구사항 |
| --- | --- | --- | --- |
| Spring.md | Spring Boot (버전 미지정), Java | Connector/J | `@RequestParam lastName` + `JdbcTemplate` 바인딩, `PreparedStatement`, `NamedParameterJdbcTemplate`(`IN (:ids)`, 빈 목록 단락), Spring Data JPA `findByLastName` / native `@Query ?1`, 정렬 허용 목록(`switch`), `LIKE ... ESCAPE '!'`, `allowMultiQueries=false` |
| NestJS.md | NestJS (버전 미지정) | mysql2 | `ValidationPipe` + DTO(`@IsString @Length(1,100) @Matches(/\S/)`), `execute()` 바인딩, `supportBigNumbers/bigNumberStrings`(ID 문자열), `multipleStatements:false`, `@IsIn(['name','recent'])`, LIKE 이스케이프, `IN` 자리표시자 생성, 누락/길이 초과 400 |
| Express.md | Express 5, ES 모듈 | mysql2 | `req.query.lastName` 문자열 타입 확인(배열/객체 거부), 코드 포인트 기준 100자, `/customers/sorted` Map 허용 목록, `IN`, LIKE 이스케이프, 누락/빈 값/중복 파라미터 400 |
| FastAPI.md | FastAPI ≥ 0.115, Pydantic 2 | mysql-connector-python | 쿼리 파라미터 모델(`strip_whitespace`, 1~100), `sort: Literal`, `def` 라우트, `cursor(prepared=True)`, 튜플 바인딩, 누락/공백/길이 초과/미등록 정렬 422 |
| Django.md | Django 5.2 | mysqlclient | `managed=False` 모델, `forms.CharField(max_length=100)`, ORM `filter`, `cursor.execute(sql, params)`, `raw()`, `order_by` 매핑, `id__in`, `__contains` 와일드카드 이스케이프, 400 응답, ORM과 raw SQL 결과 비교 |

### 문서와 실제 구성의 상충/보완 사항

1. **DB 이름**: 문서는 모든 예제가 `customer_db`를 사용한다. 프롬프트는 프레임워크별 데이터 격리를 요구하므로 `{framework}_customer_db`로 분리하고 `DB_NAME` 환경변수로 주입한다. (스키마 DDL은 문서와 동일)
2. **접속 정보 환경변수**: 문서는 `MYSQL_USER`/`MYSQL_PASSWORD`와 하드코딩된 `localhost`를 사용한다. 컨테이너 실행을 지원하기 위해 `DB_HOST/DB_PORT/DB_NAME/DB_USERNAME/DB_PASSWORD`로 통일한다.
3. **최소 권한 vs CRUD**: 문서는 "조회 계정에는 SELECT만" 부여하도록 한다. 프롬프트의 공통 기능(생성/수정/삭제/트랜잭션)을 위해 애플리케이션 계정에 `customers` 테이블 한정 DML(SELECT/INSERT/UPDATE/DELETE)만 부여하고, DDL(CREATE/DROP/ALTER)은 부여하지 않는다. 추가로 문서 그대로의 **SELECT 전용 계정**(`{framework}_reader`)을 생성하여 권한 분리를 검증한다. 스키마 변경은 MySQL 초기화 스크립트(관리자 계정)만 수행한다.
4. **FastAPI 연결 방식**: 문서는 요청마다 `mysql.connector.connect()`를 호출한다. 프롬프트의 Connection Pool 요구사항에 따라 `MySQLConnectionPool`을 사용하되 준비된 커서(`prepared=True`)와 튜플 바인딩은 문서 그대로 유지한다.
5. **Python 런타임**: 호스트 Python은 3.15.2이며 Django 5.2 공식 지원 범위(3.10~3.14) 밖이다. Python 예제의 기준 런타임은 3.13으로 정하고 Docker(`python:3.13.9-slim-bookworm`)에서 빌드/테스트한다. 호스트 실행은 가능한 범위에서 시도하고 결과를 기록한다.
6. **Java 런타임**: 호스트 기본 Java는 1.8이다. 문서의 `switch` 식은 Java 14+이 필요하므로 JDK 21(`~/.jdks/corretto-21.0.7`)을 `JAVA_HOME`으로 지정하거나 Docker(`maven:3.9.11-eclipse-temurin-21`)로 빌드한다.

## 2. 구현 대상 프레임워크

문서에 정의된 5개만 구현한다. 각 문서는 단일 버전만 정의하므로 버전별 하위 디렉터리는 만들지 않는다.

| 디렉터리 | 프레임워크 | 언어/런타임 | 빌드 도구 | 포트 |
| --- | --- | --- | --- | --- |
| `example/spring-boot/` | Spring Boot 4.0.10 (Spring Framework 7, Hibernate 7) | Java 21 | Maven 3.9 | 8081 |
| `example/nestjs/` | NestJS 11.2.x | TypeScript 5.9 / Node.js 24 | npm | 8082 |
| `example/express/` | Express 5.3 | JavaScript ESM / Node.js 24 | npm | 8083 |
| `example/fastapi/` | FastAPI 0.165 / Pydantic 2.14 | Python 3.13 | pip (requirements) | 8084 |
| `example/django/` | Django 5.2.x LTS | Python 3.13 | pip (requirements) | 8085 |

버전 선택 근거: 문서에 명시된 메이저 버전(Express 5, Django 5.2, FastAPI ≥0.115, Pydantic 2, MySQL 8.4)을 지키고, 명시되지 않은 경우 현재 패치가 배포되는 안정 라인(Spring Boot 4.0, NestJS 11)을 사용한다. 모든 의존성은 정확한 버전으로 고정한다.

## 3. 공통 REST API Contract

| Method | Path | 설명 | 문서 근거 |
| --- | --- | --- | --- |
| GET | `/health` | DB ping. 정상 200 `{"status":"UP"}`, 장애 503 | 프롬프트(장애 처리) |
| GET | `/customers/search?lastName=&sort=` | 성 완전 일치 검색(바인딩), `sort`=name\|recent(기본 name) | 전 문서 |
| GET | `/customers/contains?keyword=` | `LIKE ? ESCAPE '!'` 부분 검색 | 전 문서 |
| GET | `/customers/sorted?sort=` | 허용 목록 정렬, 미등록 키 거부 | Express/Spring |
| GET | `/customers/by-ids?ids=1,2,3` | `IN` 조회, 빈 목록은 DB 호출 없이 `[]` | 전 문서 |
| GET | `/customers?limit=&offset=` | 목록 조회 (limit 1~100) | 프롬프트 공통 기능 |
| GET | `/customers/{id}` | 단건 조회, 없으면 404 | 프롬프트 공통 기능 |
| POST | `/customers` | 생성 → 201 | 프롬프트 공통 기능 |
| PUT | `/customers/{id}` | 수정 → 200/404 | 프롬프트 공통 기능 |
| DELETE | `/customers/{id}` | 삭제 → 204/404 | 프롬프트 공통 기능 |
| POST | `/customers/batch` | 여러 건을 하나의 트랜잭션으로 생성(all-or-nothing) | 프롬프트 트랜잭션 |

프레임워크별 차이(문서 우선): Python 예제는 문서대로 `last_name`(snake_case) 파라미터를 사용한다. 검증 실패 코드는 FastAPI만 422, 나머지는 400. Node 예제의 ID는 문서대로 문자열이다.

## 4. DBMS 구성 (`example/dbms/mysql/`)

- 이미지 `mysql:8.4.13`, 포트 `127.0.0.1:${MYSQL_PORT:-3306}:3306`, Named Volume `web-security-example-mysql-data`, 고정 네트워크 `web-security-example`.
- `conf/my.cnf`: utf8mb4/utf8mb4_0900_ai_ci, UTC, STRICT 모드, `local_infile=0`, 연결 타임아웃.
- `init/01-schema.sql`: 프레임워크별 `{fw}_customer_db`(데모)와 `{fw}_customer_test_db`(테스트) 생성 및 문서의 `customers` DDL.
- `init/02-seed.sql`: 데모 DB에 가상 테스트 데이터 (실제 개인정보 없음).
- `init/03-users.sh`: `.env`의 비밀번호로 `{fw}_app`(DML)과 `{fw}_reader`(SELECT) 생성. 비밀번호 문자 검증 후 사용.
- `provision.sh/ps1`: 기존 Volume에 스키마/사용자를 멱등적으로 재적용(`IF NOT EXISTS`, `CREATE USER IF NOT EXISTS`).
- 초기화(`reset`)는 확인 플래그가 있어야 Volume을 삭제한다. 일반 종료(`down`)는 Volume을 보존한다.

## 5. 빌드/실행/테스트 방식

- `example/scripts/mysql.{sh,ps1}`: `up | wait | status | down | provision | reset --yes`
- `example/scripts/example.{sh,ps1}`: `build | test | run | docker-test | docker-run` × `{framework|all}`
- 프레임워크 등록 정보는 `example/scripts/frameworks.{sh,ps1}` 한 곳에서 관리한다.
- 테스트 결과는 `example/reports/test-results/`(Git 제외)에 로그와 요약으로 수집한다.
- 각 Dockerfile은 `test`와 `runtime` 스테이지를 가지며, 컨테이너는 `DB_HOST=mysql`로 공통 네트워크에 접속한다.

## 6. 테스트 및 검증 계획

각 프레임워크 통합 테스트(실제 MySQL `{fw}_customer_test_db` 대상)는 다음을 검증한다.

1. `O'Connor` 검색 시 해당 고객만 반환, 미등록 성은 빈 결과
2. `' OR '1'='1`, `x'; DROP TABLE customers; --`, `#`, `/* */` 페이로드가 빈 결과이며 테이블이 유지됨
3. 누락/빈 값/공백/길이 초과/중복 파라미터/미등록 정렬 키 → 400(FastAPI 422)
4. 허용된 정렬 키별 순서
5. `%`, `_`, `!` 가 LIKE에서 일반 문자로 처리
6. `IN` 조회 및 빈 목록 처리
7. CRUD 및 404
8. 트랜잭션 commit 및 rollback(중간 실패 시 앞선 INSERT 취소)
9. 최소 권한: 앱 계정의 `DROP TABLE` 거부, reader 계정의 `INSERT` 거부
10. 프레임워크 고유 방식 비교(Spring: PreparedStatement/JdbcTemplate/Named/JPA, Django: ORM vs raw SQL)

추가로 수동 검증: 호스트 실행 + Docker 실행 앱에 대한 스모크 테스트, MySQL 정지 시 503 응답, 정상 종료.

테스트 DB 보호: 테스트는 `DB_NAME`이 `_test_db`로 끝나지 않으면 실행을 거부한다(데모 데이터 보호).

## 7. 예상 호환성 문제

| 문제 | 대응 |
| --- | --- |
| 호스트 Java 8 | 스크립트에서 JDK 21 탐색(`JAVA_HOME`, `~/.jdks`), Docker 대안 |
| 호스트 Python 3.15와 Django 5.2/mysqlclient wheel | Docker 기준 검증, 호스트 결과는 별도 기록 |
| mysqlclient Linux wheel 부재 | Dockerfile에서 `default-libmysqlclient-dev`, `pkg-config`, `gcc` 설치 후 빌드 |
| MySQL init 스크립트는 최초 Volume 생성 시만 실행 | `provision` 명령 제공 |
| 컨테이너 내부 `localhost` 오용 | 컨테이너 실행 시 `DB_HOST=mysql` 강제 |
| `MAX_EXECUTION_TIME`은 SELECT에만 적용 | 드라이버 소켓/읽기 타임아웃 병행, 문서화 |

## 8. 기술적 의사결정

- 과도한 추상화 금지: 공통 라이브러리를 만들지 않고 프레임워크별 프로젝트가 자기 완결적으로 동작한다.
- 문서 코드 재사용: 문서 스니펫의 SQL, 정렬 매핑, 이스케이프 로직을 그대로 사용한다.
- 비밀번호는 `.env`(Git 제외)에서만 읽으며 로그에 출력하지 않는다.
