# 웹 보안 학습 예제

웹 애플리케이션에서 자주 발생하는 취약점을 정리하고, 취약점이 생기는 조건과 방어 방법을 예제 코드로 확인하는 저장소다. 각 주제에는 원리를 설명하는 문서와 실행 가능한 예제를 함께 작성한다. 프레임워크별로 요청을 검증하고 데이터를 처리하는 방식이 어떻게 다른지도 비교한다.

## 현재 다루는 주제

### SQL Injection

요청값이 SQL 구문의 일부로 해석되는 원리와 이를 막는 방법을 다룬다. 프레임워크별 고객 검색 예제에서 값 바인딩, 입력 검증, 정렬 허용 목록, `LIKE` 검색의 와일드카드 처리, 데이터베이스 계정의 최소 권한을 확인한다. [SQL Injection 원리와 공통 방어 방법](SQL%20Injection/README.md)

| Framework | 방어 가이드 | 실행 프로젝트 | 기본 포트 |
| --- | --- | --- | --- |
| Spring Boot | [Spring JDBC와 JPA](SQL%20Injection/Spring.md) | [spring-boot](SQL%20Injection/example/spring-boot/README.md) | 8081 |
| NestJS | [DTO와 mysql2](SQL%20Injection/NestJS.md) | [nestjs](SQL%20Injection/example/nestjs/README.md) | 8082 |
| Express | [요청 검증과 mysql2](SQL%20Injection/Express.md) | [express](SQL%20Injection/example/express/README.md) | 8083 |
| FastAPI | [Pydantic과 Connector/Python](SQL%20Injection/FastAPI.md) | [fastapi](SQL%20Injection/example/fastapi/README.md) | 8084 |
| Django | [Django ORM과 Raw SQL](SQL%20Injection/Django.md) | [django](SQL%20Injection/example/django/README.md) | 8085 |

다섯 프로젝트는 같은 고객 API를 구현한다. 이름 검색, 부분 검색, ID 목록 조회, 정렬에서 각 framework가 입력을 검증하고 SQL에 값을 전달하는 방식을 비교할 수 있다. [프레임워크별 구현 비교](SQL%20Injection/example/reports/FRAMEWORK_COMPARISON.md)

### 추가할 주제

다음 주제의 후보로 크로스 사이트 스크립팅(XSS), 크로스 사이트 요청 위조(CSRF), 접근 제어, 경로 탐색이 있다. 새 주제마다 취약점의 발생 조건과 영향을 설명하고, 해당 기능의 방어 코드와 정상 요청 및 잘못된 입력을 검증하는 테스트를 작성한다.

## SQL Injection 예제 실행

Docker와 Docker Compose v2를 준비한다. `SQL Injection` 디렉터리로 이동한 뒤(이후 명령도 같은 위치에서 실행한다) [환경 변수 템플릿](SQL%20Injection/example/dbms/mysql/.env.example)을 같은 디렉터리의 `.env`로 복사하고 로컬 비밀번호를 설정한다. 공통 스크립트가 이 파일에서 각 앱에 필요한 DB 접속 정보를 읽는다.

PowerShell에서 Express 예제를 실행하려면 다음 두 명령을 사용한다. 첫 번째 명령은 공통 MySQL 8.4 컨테이너가 준비될 때까지 기다리고, 두 번째 명령은 Express 이미지를 빌드해 실행한다.

```powershell
.\example\scripts\mysql.ps1 up
.\example\scripts\example.ps1 docker-run express
```

앱이 시작되면 `http://127.0.0.1:8083/health`에서 DB 연결 상태를 확인한다. 다른 앱은 위 표의 프로젝트 이름과 포트를 사용한다. Bash에서는 `bash example/scripts/mysql.sh up`과 `bash example/scripts/example.sh docker-run express`로 실행한다. [전체 실행 가이드](SQL%20Injection/example/README.md)

| 작업 | PowerShell 명령 |
| --- | --- |
| 실행 중인 Express API 확인 | `.\example\scripts\example.ps1 smoke express` |
| Docker에서 다섯 프로젝트 통합 테스트 | `.\example\scripts\example.ps1 docker-test all` |
| Express 컨테이너 종료 | `.\example\scripts\example.ps1 docker-stop express` |
| MySQL 종료 | `.\example\scripts\mysql.ps1 down` |

각 프로젝트는 데모 DB와 테스트 DB를 따로 사용한다. 통합 테스트 결과는 `example/reports/test-results/summary.md`에 기록된다. 2026년 11월 27일 기록 기준으로 다섯 프로젝트 모두 호스트와 Docker에서 각각 최근 실행 결과가 `PASS`였다.
