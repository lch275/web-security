# SQL Injection 방어 실행 예제

[`SQL Injection/`](../SQL%20Injection/README.md) 문서에 정의된 프레임워크별 MySQL 예제를 **독립적으로 빌드, 실행, 검증할 수 있는 프로젝트**로 구현한 디렉터리입니다. 모든 예제는 하나의 공통 MySQL 8.4 컨테이너를 사용하며, 프레임워크마다 데이터베이스와 계정이 분리되어 있습니다.

기존 문서와 이 디렉터리는 생명주기가 분리되어 있습니다. 예제는 Repository 최상위 빌드 설정에 포함되지 않으며 `example/` 밖의 파일을 읽거나 쓰지 않습니다.

## 디렉터리 구조

```
example/
├── README.md                 # 이 문서
├── .gitignore / .gitattributes
├── dbms/
│   └── mysql/                # 공통 MySQL (compose.yaml, Dockerfile, .env.example, conf/, init/, provision.sh)
├── spring-boot/              # Spring Boot 4.0 / Java 21 / Maven
├── nestjs/                   # NestJS 11 / TypeScript / npm
├── express/                  # Express 5 / Node.js ESM / npm
├── fastapi/                  # FastAPI / Python / pip
├── django/                   # Django 5.2 / Python / pip
├── scripts/                  # 공통 자동화 (Bash: *.sh, PowerShell: *.ps1)
└── reports/
    ├── IMPLEMENTATION_PLAN.md
    ├── IMPLEMENTATION_REPORT.md
    ├── FRAMEWORK_COMPARISON.md
    └── test-results/         # 테스트 실행 시 생성 (Git 제외)
```

## 지원 프레임워크

| 디렉터리                             | 문서       | 프레임워크                      | 언어/런타임                   | 빌드                   | 포트 | 드라이버                       |
| ------------------------------------ | ---------- | ------------------------------- | ----------------------------- | ---------------------- | ---- | ------------------------------ |
| [spring-boot](spring-boot/README.md) | Spring.md  | Spring Boot 4.0.10              | Java 21                       | Maven 3.9.11 (wrapper) | 8081 | Connector/J 26.10.0            |
| [nestjs](nestjs/README.md)           | NestJS.md  | NestJS 11.2.12                  | TypeScript 5.9 / Node.js ≥ 22 | npm                    | 8082 | mysql2 3.24.6                  |
| [express](express/README.md)         | Express.md | Express 5.3.0                   | JavaScript ESM / Node.js ≥ 22 | npm                    | 8083 | mysql2 3.24.6                  |
| [fastapi](fastapi/README.md)         | FastAPI.md | FastAPI 0.165.0 / Pydantic 2.14 | Python ≥ 3.12 (기준 3.13)     | pip                    | 8084 | mysql-connector-python 26.10.0 |
| [django](django/README.md)           | Django.md  | Django 5.2.19                   | Python ≥ 3.12 (기준 3.13)     | pip                    | 8085 | mysqlclient 2.3.2              |

문서마다 하나의 버전만 정의되어 있으므로 버전별 하위 디렉터리는 두지 않았습니다. 버전 선택 근거는 [IMPLEMENTATION_PLAN.md](reports/IMPLEMENTATION_PLAN.md)를 참고하세요.

## 사전 요구사항

| 용도                      | 필요 도구                                                                               |
| ------------------------- | --------------------------------------------------------------------------------------- |
| 공통                      | Docker Engine 24+ 와 Docker Compose v2 (Docker Desktop 포함), Bash 또는 PowerShell 5.1+ |
| 호스트에서 Spring Boot    | JDK 21 이상 (Maven은 wrapper가 내려받음)                                                |
| 호스트에서 NestJS/Express | Node.js 22 이상, npm                                                                    |
| 호스트에서 FastAPI/Django | Python 3.12 이상                                                                        |
| 스모크 테스트             | curl (Windows 10+ 의 `curl.exe` 포함)                                                   |

호스트 도구가 없어도 `docker-test`, `docker-run` 명령은 Docker만으로 빌드와 테스트를 수행합니다.

## 빠른 시작

```bash
# 1) 접속 정보 준비 (최초 1회, 비밀번호 변경 권장)
cp example/dbms/mysql/.env.example example/dbms/mysql/.env

# 2) MySQL 시작
example/scripts/mysql.sh up

# 3) 전체 테스트 (호스트 도구 사용) 또는 Docker에서 전체 테스트
example/scripts/example.sh test all
example/scripts/example.sh docker-test all

# 4) 하나 실행 후 스모크 테스트
example/scripts/example.sh run express          # 다른 터미널에서:
example/scripts/example.sh smoke express

# 5) 종료 (데이터 유지)
example/scripts/mysql.sh down
```

PowerShell:

```powershell
Copy-Item example\dbms\mysql\.env.example example\dbms\mysql\.env
.\example\scripts\mysql.ps1 up
.\example\scripts\example.ps1 test all
.\example\scripts\example.ps1 docker-test all
.\example\scripts\example.ps1 run express
.\example\scripts\example.ps1 smoke express
.\example\scripts\mysql.ps1 down
```

실행 정책 때문에 스크립트가 막히면 `powershell -ExecutionPolicy Bypass -File .\example\scripts\example.ps1 ...`로 실행합니다.

## 스크립트

모든 스크립트는 자신의 위치를 기준으로 경로를 계산하므로 어느 디렉터리에서 실행해도 됩니다. 실패 시 원인을 `[ERROR] ... (exit N)` 형식으로 출력하고 0이 아닌 종료 코드를 반환합니다.

### `scripts/mysql.sh` / `mysql.ps1`

| 명령                         | 설명                                            |
| ---------------------------- | ----------------------------------------------- |
| `up`                         | 이미지 빌드, 컨테이너 시작, healthy 대기        |
| `wait`                       | healthy 대기 (기본 180초, `MYSQL_WAIT_SECONDS`) |
| `status`                     | 컨테이너 상태와 health 출력                     |
| `provision`                  | 기존 Volume에 스키마/계정 재적용 (데이터 유지)  |
| `down`                       | 컨테이너 종료 (Volume 유지)                     |
| `reset --yes` / `reset -Yes` | Volume 삭제 후 재초기화 (**데이터 삭제**)       |

### `scripts/example.sh` / `example.ps1`

| 명령           | 대상           | 설명                                                     |
| -------------- | -------------- | -------------------------------------------------------- |
| `build`        | `<fw>` / `all` | 호스트 도구로 의존성 설치와 빌드                         |
| `test`         | `<fw>` / `all` | 호스트에서 통합 테스트 (`{fw}_customer_test_db`)         |
| `run`          | `<fw>`         | 호스트에서 실행 (`{fw}_customer_db`), Ctrl+C로 정상 종료 |
| `docker-build` | `<fw>` / `all` | `runtime`, `test` 이미지 빌드                            |
| `docker-test`  | `<fw>` / `all` | 컨테이너에서 통합 테스트 (`DB_HOST=mysql`)               |
| `docker-run`   | `<fw>` / `all` | 컨테이너로 백그라운드 실행 (`127.0.0.1:{port}`)          |
| `docker-stop`  | `<fw>` / `all` | 예제 컨테이너 종료                                       |
| `smoke`        | `<fw>` / `all` | 실행 중인 앱에 HTTP 스모크 테스트                        |
| `list`         | -              | 프레임워크, 포트, DB 목록                                |

`test`, `docker-test` 결과는 `reports/test-results/{fw}-{host|docker}.log`와 `reports/test-results/summary.md`에 수집됩니다. `all` 실행 시 하나가 실패해도 나머지를 계속 실행하고, 마지막에 실패 목록과 함께 종료 코드 1을 반환합니다.

## 환경변수

`dbms/mysql/.env` 한 곳에서 관리하며, 스크립트가 프레임워크별 표준 변수로 변환해 전달합니다. 프레임워크 프로젝트에는 DB 설정 파일을 따로 두지 않습니다.

| `.env` 변수                                                                                                         | 설명                                      |
| ------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| `MYSQL_PORT`                                                                                                        | 호스트 포트 (127.0.0.1 바인딩, 기본 3306) |
| `MYSQL_ROOT_PASSWORD`                                                                                               | 관리자 계정. 초기화/스키마 변경 전용      |
| `SPRING_BOOT_DB_PASSWORD`, `NESTJS_DB_PASSWORD`, `EXPRESS_DB_PASSWORD`, `FASTAPI_DB_PASSWORD`, `DJANGO_DB_PASSWORD` | 프레임워크별 앱 계정(`{fw}_app`) 비밀번호 |
| `READER_DB_PASSWORD`                                                                                                | SELECT 전용 계정(`{fw}_reader`) 비밀번호  |

애플리케이션에 전달되는 변수:

| 변수                                        | 호스트 실행                                           | 컨테이너 실행                                                |
| ------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------ |
| `DB_HOST`                                   | `127.0.0.1`                                           | `mysql` (공통 네트워크 `web-security-example`의 서비스 이름) |
| `DB_PORT`                                   | `$MYSQL_PORT`                                         | `3306`                                                       |
| `DB_NAME`                                   | `{fw}_customer_db` (`test`는 `{fw}_customer_test_db`) | 동일                                                         |
| `DB_USERNAME` / `DB_PASSWORD`               | `{fw}_app` / `{FW}_DB_PASSWORD`                       | 동일                                                         |
| `DB_READER_USERNAME` / `DB_READER_PASSWORD` | `{fw}_reader` / `READER_DB_PASSWORD` (테스트 전용)    | 동일                                                         |
| `APP_PORT`                                  | 프레임워크별 포트                                     | 동일                                                         |

컨테이너 안에서 `localhost`는 MySQL이 아니라 컨테이너 자신이므로, 컨테이너 실행 시 `DB_HOST=mysql`을 사용합니다. 스크립트는 비밀번호를 `docker run -e DB_PASSWORD`처럼 변수 이름으로만 넘겨 명령행에 노출하지 않습니다.

## 포트 할당

| 서비스      | 포트                          |
| ----------- | ----------------------------- |
| MySQL       | 127.0.0.1:3306 (`MYSQL_PORT`) |
| spring-boot | 127.0.0.1:8081                |
| nestjs      | 127.0.0.1:8082                |
| express     | 127.0.0.1:8083                |
| fastapi     | 127.0.0.1:8084                |
| django      | 127.0.0.1:8085                |

## REST API Contract

웹 프레임워크 5개가 같은 계약을 사용합니다. Python 예제는 문서대로 snake_case(`last_name`, `last_names`)를 사용합니다.

| Method | Path                                            | 설명                                      | 성공                                            |
| ------ | ----------------------------------------------- | ----------------------------------------- | ----------------------------------------------- |
| GET    | `/health`                                       | DB 연결 확인                              | 200 `{"status":"UP"}` / 503 `{"status":"DOWN"}` |
| GET    | `/customers/search?lastName=&sort=name\|recent` | 성 완전 일치 (바인딩), 정렬 허용 목록     | 200 `[id...]`                                   |
| GET    | `/customers/contains?keyword=`                  | `LIKE` 부분 검색, `%` `_` `!`는 일반 문자 | 200 `[id...]`                                   |
| GET    | `/customers/sorted?sort=name\|recent`           | 허용 목록 정렬 (필수)                     | 200 `[id...]`                                   |
| GET    | `/customers/by-ids?ids=1,2,3`                   | `IN` 조회, `ids=`는 DB 호출 없이 `[]`     | 200 `[id...]`                                   |
| GET    | `/customers?limit=20&offset=0`                  | 목록 (limit 1~100)                        | 200 `[customer...]`                             |
| GET    | `/customers/{id}`                               | 단건                                      | 200 / 404                                       |
| POST   | `/customers` `{"lastName":"..."}`               | 생성                                      | 201                                             |
| PUT    | `/customers/{id}` `{"lastName":"..."}`          | 수정                                      | 200 / 404                                       |
| DELETE | `/customers/{id}`                               | 삭제                                      | 204 / 404                                       |
| POST   | `/customers/batch` `{"lastNames":[...]}`        | 하나의 트랜잭션으로 생성 (all-or-nothing) | 201                                             |

| 오류             | spring-boot       | nestjs     | express    | fastapi | django               |
| ---------------- | ----------------- | ---------- | ---------- | ------- | -------------------- |
| 입력값 검증 실패 | 400 ProblemDetail | 400        | 400        | **422** | 400 `{"errors":...}` |
| DB 연결 불가     | 503               | 503        | 503        | 503     | 503                  |
| 기타 DB 오류     | 500 (상세 비노출) | 500        | 500        | 500     | 500                  |
| ID 타입          | number            | **string** | **string** | number  | number               |

## 데이터베이스 초기화

- MySQL `init/` 스크립트는 **Volume이 처음 만들어질 때만** 실행됩니다.
- 스키마/계정을 추가하거나 `.env` 비밀번호를 바꾼 경우: `mysql.sh down && mysql.sh up && mysql.sh provision` (데이터 유지).
- 처음 상태로 되돌리기: `mysql.sh reset --yes` (데이터 삭제).
- 통합 테스트는 `*_test_db`만 사용하고, 시작할 때 테이블을 비운 뒤 자체 데이터를 넣습니다. `DB_NAME`이 `_test_db`로 끝나지 않으면 테스트가 실행을 거부합니다.

자세한 내용은 [dbms/mysql/README.md](dbms/mysql/README.md)를 참고하세요.

## 신규 프레임워크 추가 방법

예: `koa`를 추가하는 경우

1. `example/koa/`에 독립 프로젝트를 만듭니다. `DB_HOST/DB_PORT/DB_NAME/DB_USERNAME/DB_PASSWORD/APP_PORT`를 읽고, 위 API 계약을 구현하며, `test`/`runtime` 타깃을 가진 `Dockerfile`과 `README.md`를 둡니다. 다른 예제 디렉터리를 참조하지 않습니다.
2. `dbms/mysql/`에 DB와 계정을 추가합니다 ([dbms/mysql/README.md](dbms/mysql/README.md#스키마-관리) 참고): `01-schema.sql`, `02-seed.sql`, `03-users.sh`의 목록, `compose.yaml`과 `.env.example`의 `KOA_DB_PASSWORD`.
3. `scripts/frameworks.sh`의 `FRAMEWORKS`, `fw_meta`, `fw_host_build/test/run`과 `scripts/frameworks.ps1`의 `$Frameworks`, `Invoke-FwHost*`에 항목을 추가합니다. 포트는 다음 번호(8086)를 사용합니다.
4. `mysql.sh down && mysql.sh up && mysql.sh provision` 후 `example.sh docker-test koa`로 검증합니다.

동일 프레임워크의 여러 버전이 필요하면 `example/{fw}/{version}/`에 버전별 독립 프로젝트를 만들고 `frameworks.*`에 `{fw}-{version}` 형태로 등록합니다.

## 신규 DBMS 추가 방법

예: PostgreSQL을 추가하는 경우

1. `example/dbms/postgresql/`에 `compose.yaml`(고정 이미지 태그, Named Volume, health check, `127.0.0.1` 바인딩), `.env.example`, 설정 파일, `init/`, `README.md`를 만듭니다. 컨테이너/Volume/네트워크 이름은 MySQL과 겹치지 않게 합니다.
2. 프레임워크 예제에서 DB 종류를 `DB_*` 환경변수(필요 시 `DB_ENGINE`)로 선택하도록 하고, 드라이버 의존성을 추가합니다. SQL 방언 차이(예: `LIKE ... ESCAPE`, `LIMIT/OFFSET`, 자리표시자 문법)는 프레임워크별 저장소 계층에 둡니다.
3. `scripts/lib.*`의 MySQL 전용 함수(`compose`, `wait_mysql`)를 DBMS 디렉터리 인자를 받도록 확장하거나 `scripts/postgresql.sh`를 추가합니다.
