# MySQL 8.4 공통 예제 환경

모든 프레임워크 예제가 공유하는 MySQL 컨테이너입니다. 데이터베이스와 계정은 프레임워크별로 분리되어 있으며, DB 관련 Docker, 초기화 SQL, 설정, 환경변수는 이 디렉터리에만 둡니다.

## 구성

| 파일 | 설명 |
| --- | --- |
| `compose.yaml` | 서비스 정의. 이미지 `mysql:8.4.13` 기반, Named Volume `web-security-example-mysql-data`, 네트워크 `web-security-example`, health check |
| `Dockerfile` | `conf/my.cnf`를 0644 권한으로 포함하는 얇은 이미지 (아래 "설정 파일" 참고) |
| `.env.example` | 접속 정보 템플릿. `.env`로 복사해서 사용 (`.env`는 Git 제외) |
| `conf/my.cnf` | utf8mb4, UTC, STRICT 모드, `local_infile=0`, 연결 수/타임아웃 |
| `init/01-schema.sql` | 프레임워크별 DB 10개(데모 5 + 테스트 5)와 `customers` 테이블 |
| `init/02-seed.sql` | 데모 DB에 가상 테스트 데이터 9건 (테이블이 비어 있을 때만) |
| `init/03-users.sh` | `{fw}_app`(DML), `{fw}_reader`(SELECT) 계정 생성 및 비밀번호 동기화 |
| `provision.sh` | 기존 Volume에 `init/` 전체를 다시 적용 (컨테이너 내부에서 실행) |

`customers` 테이블 정의는 [`SQL Injection/Spring.md`](../../../Spring.md#mysql-예제-환경)와 같습니다.

## 데이터베이스와 계정

| 프레임워크 | 데모 DB | 테스트 DB | 앱 계정 (SELECT/INSERT/UPDATE/DELETE) | 조회 계정 (SELECT) |
| --- | --- | --- | --- | --- |
| spring-boot | `spring_boot_customer_db` | `spring_boot_customer_test_db` | `spring_boot_app` | `spring_boot_reader` |
| nestjs | `nestjs_customer_db` | `nestjs_customer_test_db` | `nestjs_app` | `nestjs_reader` |
| express | `express_customer_db` | `express_customer_test_db` | `express_app` | `express_reader` |
| fastapi | `fastapi_customer_db` | `fastapi_customer_test_db` | `fastapi_app` | `fastapi_reader` |
| django | `django_customer_db` | `django_customer_test_db` | `django_app` | `django_reader` |

- 권한은 **테이블 단위**(`{db}.customers`)로만 부여합니다. 앱 계정은 `CREATE/DROP/ALTER`를 할 수 없고, 다른 프레임워크의 DB에 접근할 수 없습니다.
- 스키마 변경은 `root` 계정으로 `init/` 스크립트만 수행합니다. 애플리케이션은 `root`를 사용하지 않습니다.
- 앱 계정 비밀번호는 `.env`의 `{FW}_DB_PASSWORD`, 조회 계정은 `READER_DB_PASSWORD`입니다.

## 실행

가장 쉬운 방법은 공통 스크립트입니다. 스크립트는 자신의 위치를 기준으로 경로를 계산하므로 어느 디렉터리에서 실행해도 됩니다. 아래 예시는 `SQL Injection` 디렉터리 기준이며, `cp`/`docker compose` 명령의 상대 경로도 이 위치를 기준으로 합니다.

```bash
cp example/dbms/mysql/.env.example example/dbms/mysql/.env   # 최초 1회, 비밀번호 변경 권장
example/scripts/mysql.sh up          # 시작 + healthy 대기
example/scripts/mysql.sh status
```

```powershell
Copy-Item example\dbms\mysql\.env.example example\dbms\mysql\.env
.\example\scripts\mysql.ps1 up
```

Docker Compose를 직접 쓸 때는 `--project-directory`로 이 디렉터리를 지정합니다. 그러면 `compose.yaml` 안의 상대 경로(`./init`, `./conf`)가 실행 위치와 관계없이 이 디렉터리를 기준으로 해석됩니다.

```bash
docker compose --project-directory example/dbms/mysql --env-file example/dbms/mysql/.env up -d --build
```

## 접속

포트는 `127.0.0.1:${MYSQL_PORT}`(기본 3306)에만 바인딩됩니다. 컨테이너 내부에서는 서비스 이름 `mysql:3306`으로 접속합니다.

```bash
# 컨테이너 안의 mysql 클라이언트 (비밀번호는 프롬프트로 입력)
docker exec -it web-security-example-mysql mysql -u express_app -p express_customer_db

# 호스트의 클라이언트
mysql -h 127.0.0.1 -P 3306 -u express_app -p express_customer_db
```

## 종료와 초기화

| 명령 | 동작 | 데이터 |
| --- | --- | --- |
| `mysql.sh down` / `mysql.ps1 down` | 컨테이너 종료 및 삭제 | **유지** (Volume 보존) |
| `mysql.sh provision` / `mysql.ps1 provision` | `init/` 스크립트를 기존 Volume에 다시 적용 | 유지 (멱등) |
| `mysql.sh reset --yes` / `mysql.ps1 reset -Yes` | Volume 삭제 후 재생성, `init/` 최초 실행 | **삭제** |

`reset`은 확인 플래그가 없으면 실행되지 않습니다.

## 스키마 관리

MySQL 공식 이미지는 `/docker-entrypoint-initdb.d`(= `init/`)의 스크립트를 **데이터 디렉터리가 비어 있을 때(Volume 최초 생성 시)만** 실행합니다. 이미 Volume이 있는 상태에서 스키마나 계정을 바꾸려면 다음 중 하나를 사용합니다.

1. `init/` 파일을 수정한 뒤 `mysql.sh provision`을 실행합니다. 모든 스크립트는 `IF NOT EXISTS`, `CREATE USER IF NOT EXISTS` + `ALTER USER`, "비어 있을 때만 시드"로 작성되어 있어 여러 번 실행해도 안전합니다. `.env`에서 바꾼 비밀번호도 이때 반영됩니다(컨테이너를 다시 만든 뒤 실행: `mysql.sh down && mysql.sh up && mysql.sh provision`).
2. 데이터를 버려도 된다면 `mysql.sh reset --yes`.

신규 프레임워크 `foo`를 추가할 때는 다음을 수정합니다.

- `init/01-schema.sql`: `foo_customer_db`, `foo_customer_test_db` 생성 블록 추가
- `init/02-seed.sql`: `foo_customer_db` 시드 블록 추가
- `init/03-users.sh`: `frameworks` 목록에 `foo` 추가
- `compose.yaml`, `.env.example`: `FOO_DB_PASSWORD` 추가
- 이후 `mysql.sh down && mysql.sh up && mysql.sh provision`

## 설정 파일

Windows/macOS의 Docker Desktop 바인드 마운트는 파일 권한을 `0777`로 노출하는 경우가 있고, MySQL은 world-writable 설정 파일을 `World-writable config file ... is ignored` 경고와 함께 무시합니다. 그래서 `conf/my.cnf`는 바인드 마운트하지 않고 `Dockerfile`에서 `COPY --chmod=0644`로 이미지에 포함합니다. `my.cnf`를 수정했다면 `mysql.sh up`(내부적으로 `--build`)으로 다시 빌드합니다.

적용 여부 확인:

```bash
docker exec -e MYSQL_PWD=<root 비밀번호> web-security-example-mysql \
  mysql -uroot -e "SELECT @@character_set_server, @@time_zone, @@local_infile, @@sql_mode"
```

## 보안 메모

- `latest` 태그를 사용하지 않습니다 (`mysql:8.4.13`).
- health check와 스크립트는 비밀번호를 명령행 인자가 아닌 `MYSQL_PWD` 환경변수로 전달합니다.
- `init/03-users.sh`는 비밀번호에 따옴표, 역슬래시, 공백이 있으면 거부합니다(초기화 SQL 자체의 인젝션 방지). 12자 이상이어야 합니다.
- 시드 데이터는 가상의 성(last name)만 포함합니다.
