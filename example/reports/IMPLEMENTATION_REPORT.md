# 구현 결과 보고서 (IMPLEMENTATION_REPORT)

작성일: 2026-11-27 · 계획: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) · 비교: [FRAMEWORK_COMPARISON.md](FRAMEWORK_COMPARISON.md)

## 1. 요약

`SQL Injection/` 문서에 정의된 5개 프레임워크(Spring Boot, NestJS, Express, FastAPI, Django)를 `example/` 하위에 독립 실행 가능한 프로젝트로 구현했습니다. 공통 MySQL 8.4 컨테이너(`example/dbms/mysql/`)를 사용하며 프레임워크별 DB와 최소 권한 계정이 분리되어 있습니다. 5개 프레임워크 모두 **호스트 실행**과 **Docker 컨테이너 실행** 두 환경에서 실제 MySQL에 연결해 통합 테스트, 스모크 테스트, DB 장애, 정상 종료를 검증했고 모두 통과했습니다.

## 2. 분석한 Markdown 문서

| 문서 | 내용 | 구현 대상 |
| --- | --- | --- |
| `SQL Injection/README.md` | 원인, 공통 방어(바인딩, 검증, 허용 목록, 최소 권한), 프레임워크 목록 | 공통 요구사항 |
| `SQL Injection/Spring.md` | MySQL 환경/DDL, JdbcTemplate, PreparedStatement, NamedParameterJdbcTemplate, JPA, 정렬, LIKE | `example/spring-boot` |
| `SQL Injection/NestJS.md` | DTO + ValidationPipe, mysql2 execute, IN, 정렬, LIKE | `example/nestjs` |
| `SQL Injection/Express.md` | Express 5 요청 검증, mysql2, `/customers/sorted`, IN, LIKE | `example/express` |
| `SQL Injection/FastAPI.md` | Pydantic 쿼리 모델, 준비된 커서, 정렬 Literal, LIKE | `example/fastapi` |
| `SQL Injection/Django.md` | Django 5.2 모델/폼, ORM, raw SQL, order_by, `__in`, `__contains` | `example/django` |

작업 지침 파일(`AGENTS.md`, `CLAUDE.md`)과 기존 예제 소스/빌드 설정은 없었습니다. 문서의 코드 스니펫을 구현에 그대로 재사용했습니다(라이선스/저작권 표기 대상 없음).

## 3. 식별한 프레임워크와 구현 버전

| 프레임워크 | 문서 명시 버전 | 구현 버전 | 런타임 |
| --- | --- | --- | --- |
| Spring Boot | 없음 | 4.0.10 (Spring 7.0.11, Hibernate 7.2.25, Connector/J 26.10.0) | Java 21, Maven 3.9.11 |
| NestJS | 없음 | 11.2.12, class-validator 0.15.1, mysql2 3.24.6 | Node.js 24 (컨테이너) / 26 (호스트), TS 5.9.3 |
| Express | 5 | 5.3.0, mysql2 3.24.6 | Node.js 24 / 26 |
| FastAPI | ≥ 0.115, Pydantic 2 | 0.165.0, Pydantic 2.14.4, mysql-connector-python 26.10.0 | Python 3.13 (컨테이너) / 3.15 (호스트) |
| Django | 5.2 | 5.2.19, mysqlclient 2.3.2 | Python 3.13 / 3.15 |
| MySQL | 8.4 | `mysql:8.4.13` | - |

각 문서가 단일 버전만 정의하므로 버전별 하위 디렉터리는 만들지 않았습니다.

## 4. 생성 및 수정 파일

**수정한 기존 파일: 없음.** 생성한 파일은 모두 `example/` 하위입니다 (Git 추적 대상 116개, 빌드 산출물 제외).

| 영역 | 파일 |
| --- | --- |
| 공통 | `README.md`, `.gitignore`, `.gitattributes` |
| DBMS | `dbms/mysql/{compose.yaml, Dockerfile, .env.example, README.md, provision.sh, conf/my.cnf, init/01-schema.sql, init/02-seed.sql, init/03-users.sh}` |
| 스크립트 | `scripts/{lib, mysql, example, frameworks, smoke}.{sh,ps1}` (10개) |
| spring-boot | `pom.xml`, `mvnw`, `mvnw.cmd`, `.mvn/wrapper/maven-wrapper.properties`, `Dockerfile`, `.dockerignore`, `README.md`, `src/main/resources/application.yml`, `src/main/java/.../` 13개, `src/test/java/.../` 2개 |
| nestjs | `package.json`, `package-lock.json`, `tsconfig.json`, `tsconfig.build.json`, `nest-cli.json`, `Dockerfile`, `.dockerignore`, `README.md`, `src/` 7개, `test/customers.e2e.spec.ts` |
| express | `package.json`, `package-lock.json`, `Dockerfile`, `.dockerignore`, `README.md`, `src/` 7개, `test/customers.test.js` |
| fastapi | `requirements.txt`, `requirements-dev.txt`, `constraints.txt`, `pytest.ini`, `Dockerfile`, `.dockerignore`, `README.md`, `app/` 6개, `tests/` 3개 |
| django | `manage.py`, `requirements.txt`, `requirements-dev.txt`, `constraints.txt`, `Dockerfile`, `.dockerignore`, `README.md`, `config/` 5개, `customers/` 10개 |
| 보고서 | `reports/IMPLEMENTATION_PLAN.md`, `reports/IMPLEMENTATION_REPORT.md`, `reports/FRAMEWORK_COMPARISON.md` |

Git 제외(생성되지만 추적하지 않음): `dbms/mysql/.env`, `*/node_modules`, `*/.venv`, `*/dist`, `*/target`, `reports/test-results/`.

## 5. 요구사항과 구현 매핑

| 요구사항 (출처) | spring-boot | nestjs | express | fastapi | django |
| --- | --- | --- | --- | --- | --- |
| 값 바인딩 (전 문서) | JdbcTemplate `?`, Named `:lastName`, PreparedStatement, JPA | `execute(sql, [v])` | `execute(sql, [v])` | `cursor(prepared=True)` `%s` | ORM, `cursor.execute(sql, params)`, `raw()` |
| 입력값 검증 (전 문서) | `@NotBlank @Size(max=100)` | DTO `@IsString @Length @Matches` | `typeof`/코드 포인트 검사 | `StringConstraints` | `forms.CharField(max_length=100)` |
| 정렬 허용 목록 | `switch` | `@IsIn` + Record | `Map` | `Literal` + dict | `ChoiceField` + `order_by` |
| LIKE `ESCAPE '!'` | ✓ | ✓ | ✓ | ✓ | `__contains` (Django 이스케이프) |
| IN + 빈 목록 단락 | `IN (:ids)` | `?` 생성 | `?` 생성 | `%s` 생성 | `id__in` |
| 다중 문 비활성화 | `allowMultiQueries=false` | `multipleStatements:false` | `multipleStatements:false` | 드라이버 기본(준비된 문) | 드라이버 기본 |
| BIGINT 문자열 | - | `bigNumberStrings` | `bigNumberStrings` | - | - |
| 최소 권한 (README) | 테이블 단위 DML 계정 + SELECT 전용 계정, DDL 거부 테스트 | 동일 | 동일 | 동일 | 동일 |
| CRUD, 트랜잭션 commit/rollback (프롬프트 §8) | `@Transactional` | 연결 단위 트랜잭션 | 연결 단위 트랜잭션 | 컨텍스트 매니저 | `transaction.atomic()` |
| DB 장애 예외 처리 | 503 ProblemDetail | 503 | 503 | 503 | 503 |
| 로깅 (민감정보 제외) | 경로/상태/시간 | 동일 | 동일 | 동일 (uvicorn 접근 로그 off) | 동일 |
| 문서의 통합 테스트 항목 | 29 tests | 34 tests | 23 tests | 33 tests | 19 tests |

## 6. MySQL Docker 구성 결과

| 항목 | 결과 |
| --- | --- |
| 이미지 | `mysql:8.4.13` 기반 로컬 이미지 `web-security-example/mysql:8.4.13` (설정 파일 권한 문제 해결용) |
| 데이터 영속성 | Named Volume `web-security-example-mysql-data`. `down` 후 `up`, Docker Desktop 재시작 후에도 데이터 유지 확인 |
| Health Check | `mysqladmin ping` (비밀번호는 `MYSQL_PWD`), 초기화 완료 후에만 healthy |
| 문자셋/시간대/모드 | `utf8mb4` / `utf8mb4_0900_ai_ci`, `+00:00`, `STRICT_TRANS_TABLES`, `local_infile=0` 적용 확인 |
| 포트 | `127.0.0.1:3306`만 바인딩 |
| DB 분리 | 프레임워크별 데모 DB 5개 + 테스트 DB 5개 |
| 계정 | `{fw}_app`(테이블 단위 SELECT/INSERT/UPDATE/DELETE), `{fw}_reader`(SELECT). `SHOW GRANTS`로 확인 |
| 초기화/종료 분리 | `down`(Volume 유지), `provision`(재적용), `reset --yes`(삭제). 확인 플래그 없는 `reset`은 exit 64로 거부 확인 |
| 기존 Volume 확장 | reader 계정과 테스트 DB를 root로 삭제 → `provision` → 계정/권한/DB 복원, 시드 중복 없음(9건 유지) 확인 |
| 상대 경로 | `--project-directory` 사용, 다른 작업 디렉터리(`/tmp`)에서 스크립트 실행 확인 |

## 7. 빌드 결과

| 프레임워크 | 호스트 빌드 | Docker 이미지 (`runtime`, `test`) |
| --- | --- | --- |
| spring-boot | PASS (`./mvnw package`, JDK 21 자동 탐색, 기본 Java 1.8 환경) | PASS |
| nestjs | PASS (`nest build`) | PASS |
| express | PASS (`node --check`) | PASS |
| fastapi | PASS (`.venv`, Python 3.15.2) | PASS (Python 3.13.9) |
| django | PASS (`manage.py check`, Python 3.15.2, mysqlclient Windows wheel) | PASS (mysqlclient 소스 컴파일) |

## 8. 데이터베이스 연동 결과

| 검증 항목 | spring-boot | nestjs | express | fastapi | django |
| --- | --- | --- | --- | --- | --- |
| 호스트 → MySQL 인증/연결 (`127.0.0.1:3306`) | PASS | PASS | PASS | PASS | PASS |
| 컨테이너 → MySQL (`mysql:3306`, 공통 네트워크) | PASS | PASS | PASS | PASS | PASS |
| 프레임워크별 데이터 격리 (전용 DB/계정, 타 DB 권한 없음) | PASS | PASS | PASS | PASS | PASS |
| 연결 풀 설정 | Hikari 10 | mysql2 10 | mysql2 10 | Pool 10 + 세마포어 | CONN_MAX_AGE 60 |
| 트랜잭션 commit / rollback | PASS | PASS | PASS | PASS | PASS |
| DB 정지 중 요청 → 503, 내부 정보 비노출 | PASS | PASS | PASS | PASS | PASS |
| MySQL 재기동 후 앱 재시작 없이 복구 | PASS | PASS | PASS | PASS | PASS |
| 정상 종료 시 풀 반환 (SIGTERM) | PASS (Hikari "Shutdown completed", exit 143*) | PASS ("MySQL pool closed") | PASS ("shutdown complete") | PASS ("MySQL pool closed") | PASS (gunicorn graceful) |
| 로그의 비밀번호/검색값 노출 | 0건 | 0건 | 0건 | 0건 | 0건 |

\* JVM은 SIGTERM을 받아 셧다운 훅을 정상 수행한 뒤 종료 코드 143(128+15)으로 끝나는 것이 정상 동작입니다.

연결/쿼리 타임아웃은 설정과 장애 시 동작(연결 타임아웃 1~5초 내 503)까지 확인했지만, **장시간 실행 쿼리로 쿼리 타임아웃이 실제 발동하는 것은 재현하지 않았습니다** (11절 참고).

## 9. 테스트 결과와 실제 실행 명령

### 9.1 최종 실행

실행 일시 2026-11-27 21:57~22:06 (KST). 결과 원본은 `reports/test-results/summary.md`와 `{fw}-{host|docker}.log`(Git 제외)에 있습니다.

| 프레임워크 | `example.sh test <fw>` (호스트) | `example.sh docker-test <fw>` (컨테이너) | 테스트 수 |
| --- | --- | --- | --- |
| spring-boot | PASS (51s) | PASS (34s) | 29 / 29 |
| nestjs | PASS (66s) | PASS (17s) | 34 / 34 |
| express | PASS (6s) | PASS (5s) | 23 / 23 |
| fastapi | PASS (14s) | PASS (12s) | 33 / 33 |
| django | PASS (8s) | PASS (4s) | 19 / 19 (subTest 포함) |

실행 명령과 종료 코드:

```text
example/scripts/example.sh test all            → exit 0  (호스트: JDK 21, Node 26.13.1, Python 3.15.2)
example/scripts/example.sh docker-test all     → exit 0  (컨테이너: JDK 21, Node 24.11.1, Python 3.13.9)
example/scripts/example.ps1 test express       → exit 0  (Windows PowerShell 5.1)
example/scripts/example.ps1 docker-test fastapi → exit 0  (Windows PowerShell 5.1)
```

호스트와 컨테이너 테스트는 같은 `*_test_db`를 쓰므로 순차적으로 실행했습니다. 개발 중 실패 기록(Express/Spring/Django Docker 테스트)도 `summary.md`에 남아 있으며, 원인과 수정은 10절에 정리했습니다.

### 9.2 추가 수동 검증 (모두 실제 실행)

| 검증 | 명령 | 결과 |
| --- | --- | --- |
| Compose 설정 검증 | `docker compose --project-directory example/dbms/mysql config --quiet` | PASS |
| MySQL 기동/health | `example/scripts/mysql.sh up` | PASS (healthy) |
| 초기 데이터 | `SELECT COUNT(*) FROM {fw}_customer_db.customers` | 각 9건 |
| 설정 적용 | `SELECT @@character_set_server, @@time_zone, @@local_infile, @@sql_mode` | PASS |
| 컨테이너 실행 + 스모크 | `example.sh docker-run all` → `example.sh smoke all` | 5 × 8 항목 PASS |
| 호스트 실행 + 스모크 (PowerShell) | `example.ps1 run <fw>` → `smoke.ps1 <fw>` | 5/5 PASS |
| DB 장애 | `mysql.sh down` 상태에서 `/health`, `/customers/search`, `POST /customers` | 모두 503 |
| 복구 | `mysql.sh up` 후 `/health` | 5/5 UP |
| 정상 종료 | `docker stop -t 15` 후 로그/종료 코드 | 5/5 PASS |
| provision (Bash/PowerShell) | `mysql.sh provision`, `mysql.ps1 provision` | PASS |
| 오류 종료 코드 | 미지정 프레임워크(64), `.env` 없음(2), 확인 없는 reset(64) | 의도대로 반환 |

## 10. 발견한 문제와 해결

| # | 문제 | 원인 | 해결 |
| --- | --- | --- | --- |
| 1 | `my.cnf`가 무시됨 (`World-writable config file ... is ignored`) | Windows Docker Desktop 바인드 마운트가 0777로 노출 | `dbms/mysql/Dockerfile`에서 `COPY --chmod=0644`로 포함 |
| 2 | Spring: 미등록 정렬 키가 400이 아닌 500 | `@Repository`의 JPA 예외 변환이 `IllegalArgumentException`을 `InvalidDataAccessApiUsageException`으로 변환 | `RuntimeException` 기반 `UnsupportedSortKeyException` (문서 예제와의 차이로 README에 기록) |
| 3 | Django: `{"last_name": ["a"]}`가 `"['a']"`로 저장됨 | `forms.CharField`가 리스트를 `str()`로 변환 | 문자열이 아닌 JSON 값은 폼에 전달하지 않음 |
| 4 | Django ORM INSERT 시 `created_at` NULL | 문서 모델에 DB 기본값 정보 없음 | `db_default=Now()` 추가 + `refresh_from_db` |
| 5 | Django 테스트 러너가 test DB 생성 시도 | 앱 계정에 CREATE 권한 없음(의도) | 기존 테스트 DB를 쓰는 전용 러너 |
| 6 | Express Docker 테스트 실패 `Cannot find module '/app/test'` | Node 24는 `node --test <디렉터리>` 미지원 (호스트 Node 26은 지원) | glob 패턴 `"test/**/*.test.js"` |
| 7 | Spring Docker 테스트 실패 (offline) | surefire가 JUnit 프로바이더를 실행 시점에 다운로드 | 테스트 스테이지에서 `-o` 제거 |
| 8 | Spring 테스트의 ID 조회 불안정 가능성 | `SELECT LAST_INSERT_ID()`가 풀의 다른 연결에서 실행될 수 있음 | `GeneratedKeyHolder` 사용 |
| 9 | Hibernate `HHH90000025` 경고 | 메타데이터 조회 비활성화와 dialect 명시 방식 | `jakarta.persistence.database-product-name/version` 사용 |
| 10 | FastAPI 테스트 경고 (Starlette: httpx 대신 httpx2) | 최신 Starlette 권고 | `httpx2==2.16.2` 사용 |
| 11 | PowerShell `Write-Log` FormatError | 메서드 인자 안의 `-f` 뒤 쉼표가 인자 구분자로 해석 | 문자열을 먼저 만든 뒤 출력 |
| 12 | PowerShell 함수가 명령 출력을 반환값에 섞음 | PowerShell 출력 스트림 특성 | 출력은 `Out-Host`, 반환은 종료 코드만 |
| 13 | PowerShell 테스트 로그가 UTF-16 | PS 5.1 `Tee-Object` 기본 인코딩 | `Add-Content -Encoding UTF8` |
| 14 | PowerShell 5.1에서 한글 스크립트 해석 문제 가능성 | BOM 없는 UTF-8을 ANSI로 읽음 | `.ps1`을 UTF-8 BOM + CRLF로 저장, `.gitattributes`로 고정 |
| 15 | Git Bash에서 `provision` 실패 | MSYS가 `/opt/...`를 Windows 경로로 변환 | 해당 `docker exec`에 `MSYS_NO_PATHCONV=1` |
| 16 | 작업 중 Docker 빌드가 `read-only file system`으로 실패, MySQL 일시 중단 | 호스트 C: 드라이브 여유 공간 12MB (환경 문제) | 이번 작업 산출물(`spring-boot/target`, 임시 wheel)만 삭제, Docker Desktop/WSL 재시작 → 여유 50GB로 회복, Volume 데이터 유지 확인, 실패 항목 재검증 |
| 17 | PowerShell 로그의 한글/기호 깨짐 | PS 5.1이 네이티브 출력을 콘솔 코드페이지(CP949)로 디코딩 | 네이티브 호출 동안 `[Console]::OutputEncoding`을 UTF-8로 지정 |

## 11. 기술적 의사결정과 근거

| 결정 | 근거 |
| --- | --- |
| DB 이름 `{fw}_customer_db` (문서는 `customer_db`) | 프레임워크별 데이터 격리 요구. DDL은 문서와 동일 |
| 앱 계정에 DML 부여 + 별도 SELECT 전용 계정 | 문서의 "조회 계정 SELECT만"과 CRUD/트랜잭션 요구를 함께 만족. DDL은 어떤 앱 계정에도 없음 |
| 테스트 전용 DB `{fw}_customer_test_db` + `_test_db` 가드 | 테스트가 데모 데이터를 지우지 않도록 보호 |
| Spring Boot 4.0.x | 문서에 버전 없음. 현재 패치가 배포되는 메이저 라인. 3.x API(`javax`)로 내려갈 이유 없음 |
| NestJS 11, TypeScript 5.9 (NestJS 12, TS 7 아님) | NestJS 11.x가 계속 패치되고 있고 ts-jest가 TS 7을 지원하지 않음(`typescript <7`) |
| Python 기준 런타임 3.13 (Docker) | Django 5.2의 공식 지원 범위. 호스트 3.15에서도 테스트 통과했지만 기준은 컨테이너 |
| FastAPI 연결 풀 + 세마포어 | 프롬프트의 풀 요구. `MySQLConnectionPool`이 대기 없이 실패하는 특성 보완 |
| REST 계약 통일, 단 Python은 `last_name`, FastAPI는 422 | 문서 우선 원칙 |
| 공통 라이브러리 미사용 | 과도한 추상화 금지, 프레임워크별 독립성 |
| MySQL 이미지를 로컬 빌드 | 설정 파일 권한 문제를 OS와 무관하게 해결 |
| 스크립트는 `docker run -e NAME`으로 비밀번호 전달 | 프로세스 인자 노출 방지 |
| 의존성 고정: npm lockfile, pip `constraints.txt`, Maven BOM, 이미지 태그 | 재현 가능한 빌드, 패치 시 한 곳만 수정 |

## 12. 미해결 사항

- dev 의존성 경고: `@nestjs/cli`/Jest 경로의 `glob@10` deprecated 경고 (런타임 이미지에는 포함되지 않음).
- Spring Boot 테스트 실행 시 Mockito의 동적 에이전트 로딩 경고(JDK 21). 동작에는 영향 없음.
- Django의 `contains`가 대소문자를 구분하는 점은 문서(Django.md) 설명과 다릅니다. 예제는 Django 실제 동작을 따르고 테스트로 명시했습니다. 문서 수정은 범위 밖이라 하지 않았습니다.
- Spring 문서 예제의 `IllegalArgumentException` 사용도 `@Repository` 환경에서는 500이 될 수 있다는 점을 문서에 반영할지 검토가 필요합니다(문서 미수정).

## 13. 검증하지 못한 사항

| 항목 | 상태 | 사유 |
| --- | --- | --- |
| 장시간 쿼리에 의한 쿼리 타임아웃 실제 발동 (`MAX_EXECUTION_TIME`, `setQueryTimeout`, mysql2 `timeout`) | NOT_RUN | 설정만 적용. 앱 계정으로 `SLEEP()` 장기 쿼리를 유도하는 테스트는 추가하지 않음 |
| 풀 고갈 상황(동시 요청 > 풀 크기)에서의 대기/503 | NOT_RUN | 부하 테스트 미수행 |
| Linux/macOS 호스트에서 `*.sh`, `*.ps1`(PowerShell 7) 실행 | BLOCKED | 작업 환경이 Windows 11 단일 호스트. Bash 스크립트는 Git Bash, PowerShell은 5.1에서만 검증 (컨테이너 내부 Linux 실행은 검증됨) |
| `mysql.sh reset --yes` 실제 실행 | NOT_RUN | "데이터베이스 Volume 임의 삭제 금지" 지침에 따라 확인 플래그 거부 동작만 검증. 최초 Volume 생성 시 초기화 동작은 검증됨 |
| 호스트 실행 앱의 SIGINT 정상 종료 | NOT_RUN | Windows에서 백그라운드 네이티브 프로세스에 SIGINT를 보낼 수 없어 강제 종료로 정리. 정상 종료는 컨테이너(SIGTERM)로 검증 |

## 14. 기존 프로젝트 영향도와 example 외부 변경 여부

- 기존 `SQL Injection/*.md` 6개 파일: **변경 없음** (`git status`로 확인).
- 최상위에 Docker/빌드/환경변수/보고서 파일을 만들지 않았습니다. 예제는 기존 빌드 설정에 편입되지 않습니다(기존 빌드 설정 없음).
- `git status` 결과 `example/` 외부의 추적되지 않은 파일은 루트 `README.md` 하나입니다. 이 파일은 작업 도중(21:56) 생성된 것으로 **이번 작업에서 만들거나 수정하지 않았습니다.** 내용상 `example/` 프로젝트를 링크하는 저장소 소개 문서이며 그대로 두었습니다.
- 작업 디렉터리 외부 영향: Docker 이미지/Volume/네트워크(`web-security-example*`), `~/.m2`, npm/pip 캐시, `example/*/node_modules`·`.venv`(Git 제외). 운영 DB나 외부 시스템에는 접근하지 않았습니다.
- 작업 중 디스크 부족 대응으로 Docker Desktop과 WSL을 재시작했습니다. 이 시점에 다른 컨테이너는 없었습니다.
