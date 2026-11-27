# 프레임워크 구현 비교 (FRAMEWORK_COMPARISON)

다섯 예제는 같은 MySQL 스키마와 같은 REST 계약을 구현하지만, 각 문서와 프레임워크 관례를 따르기 때문에 구현 방식이 다릅니다.

## 1. 값 바인딩

| 프레임워크 | API | 자리표시자 | 바인딩 방식 |
| --- | --- | --- | --- |
| spring-boot | `JdbcTemplate.queryForList(sql, Long.class, args...)` | `?` | Connector/J `PreparedStatement` (기본 `useServerPrepStmts=false`: 드라이버가 값을 이스케이프하여 전송) |
| | `NamedParameterJdbcTemplate` | `:lastName` | 이름을 `?`로 변환 후 위와 동일 |
| | `PreparedStatement.setString(1, v)` | `?` | JDBC 표준 |
| | Spring Data JPA `findByLastName`, `@Query(nativeQuery=true) ?1` | 파생/`?1` | Hibernate가 `PreparedStatement`로 바인딩 |
| nestjs / express | mysql2 `execute(sql, values)` | `?` | **서버 측 준비된 문** (`COM_STMT_PREPARE/EXECUTE`) |
| fastapi | mysql-connector-python `cursor(prepared=True).execute(sql, tuple)` | `%s` | **서버 측 준비된 문** |
| django | ORM `filter(last_name=...)`, `cursor.execute(sql, params)`, `raw(sql, params)` | `%s` | mysqlclient가 클라이언트 측에서 이스케이프 후 전송 |

공통 결과: 7가지 페이로드(`' OR '1'='1`, `x'; DROP TABLE customers; --`, `O'Connor'#`, `/* */`, `UNION SELECT` 등)가 모든 프레임워크에서 빈 결과를 반환하고 테이블이 유지됨을 통합 테스트로 확인했습니다. Spring Boot와 Django는 바인딩 방식 간(JdbcTemplate/Named/PreparedStatement/JPA, ORM/cursor/raw) 결과가 같은지도 비교합니다.

## 2. 입력값 검증

| 프레임워크 | 방식 | 실패 응답 | 중복 파라미터(`lastName=a&lastName=b`) | 공백 처리 |
| --- | --- | --- | --- | --- |
| spring-boot | Bean Validation (`@NotBlank @Size`)을 `@RequestParam`에 직접 적용 (Spring 6.1+ 내장 메서드 검증) | 400 ProblemDetail | `"a,b"`로 합쳐져 하나의 값으로 바인딩 (빈 결과) | 검색값은 그대로, 저장 시 `strip()` |
| nestjs | DTO + 전역 `ValidationPipe(whitelist, forbidNonWhitelisted, transform)` | 400 | 배열 → `@IsString` 실패 400 | `@Matches(/\S/)`, 저장 시 `@Transform(trim)` |
| express | 수동 검증 함수 (`typeof === 'string'`, 코드 포인트 길이) | 400 | 배열 → 400 | 검색값은 그대로, 저장 시 `trim()` |
| fastapi | Pydantic 쿼리 파라미터 모델 (`StringConstraints(strip_whitespace)`, `Literal`) | **422** | 마지막 값 사용 | 앞뒤 공백 제거 후 검색 |
| django | `forms.Form` (`CharField`, `ChoiceField`) | 400 `{"errors":...}` | 마지막 값 사용 | `CharField` 기본 `strip=True` |

길이 기준: Express/NestJS(class-validator)는 코드 포인트, Spring `@Size`는 UTF-16 코드 유닛, Pydantic/Django는 Python `str` 길이(코드 포인트)입니다. 이모지처럼 서로게이트 쌍인 문자는 Spring에서 2자로 계산됩니다.

## 3. 허용 목록 (정렬)

| 프레임워크 | 구현 | 미등록 키 처리 |
| --- | --- | --- |
| spring-boot | `switch` 식 → SQL 정렬 문자열 | `UnsupportedSortKeyException` → 400 |
| nestjs | `@IsIn(['name','recent'])` + `ORDER_BY` Record | DTO 검증 400 |
| express | `Map` 조회 | `undefined` → 400 (배열/`__proto__`도 거부) |
| fastapi | `Literal["name","recent"]` + `ORDER_BY` dict | 422 |
| django | `ChoiceField` + `order_by(*fields)` (SQL 문자열 아님) | 400 |

Spring 문서 예제의 `IllegalArgumentException`은 `@Repository` 빈 안에서 던지면 JPA 예외 변환에 의해 `InvalidDataAccessApiUsageException`이 되어 500으로 처리되는 것을 테스트로 발견했습니다. 전용 `RuntimeException`으로 바꿔 해결했습니다.

## 4. LIKE 와일드카드

| 프레임워크 | 구현 | 대소문자 |
| --- | --- | --- |
| spring-boot, nestjs, express, fastapi | `!`→`!!`, `%`→`!%`, `_`→`!_` 치환 후 `LIKE ? ESCAPE '!'` | 컬럼 콜레이션(`utf8mb4_0900_ai_ci`, 구분 안 함) |
| django | `filter(last_name__contains=...)` (Django가 `\`로 이스케이프) | **`LIKE BINARY` → 구분함**. 콜레이션을 따르려면 `icontains` |

## 5. IN 조회

| 프레임워크 | 구현 |
| --- | --- |
| spring-boot | `NamedParameterJdbcTemplate` `IN (:ids)` + 컬렉션 → 원소마다 `?` 생성. 빈 목록은 호출 전 `List.of()` |
| nestjs / express | `ids.map(() => '?').join(', ')`로 자리표시자 생성, 값은 별도 배열. 빈 목록 단락 |
| fastapi | `", ".join(["%s"] * n)` + 튜플. 빈 목록 단락 |
| django | `filter(id__in=ids)`. 빈 목록 단락 |

## 6. 연결 풀과 타임아웃

| 프레임워크 | 풀 | 연결 타임아웃 | 쿼리 타임아웃 | DB 없이 기동 |
| --- | --- | --- | --- | --- |
| spring-boot | HikariCP (max 10, min idle 2, 누수 감지 20s) | `connectTimeout=5000`, Hikari 5s | JdbcTemplate 10s, JPA 10s, `setQueryTimeout(10)`, `socketTimeout=30s` | 가능 (`initialization-fail-timeout=-1`, 메타데이터 조회 비활성화) |
| nestjs / express | mysql2 pool (limit 10, queueLimit 100, idle 60s) | `connectTimeout` 5s | `execute({ sql, timeout: 10000 })` | 가능 (지연 연결) |
| fastapi | `MySQLConnectionPool` (10) + `BoundedSemaphore`(대기 5s) | `connection_timeout` 5s | 대여 시 `SET SESSION MAX_EXECUTION_TIME` (SELECT 한정) | 가능 (첫 요청 시 풀 생성) |
| django | 풀 없음. `CONN_MAX_AGE=60` 영속 연결 + `CONN_HEALTH_CHECKS` | `connect_timeout` 5s | `init_command`의 `MAX_EXECUTION_TIME`, `read_timeout` 30s | 가능 (요청 시 연결) |

## 7. 트랜잭션

| 프레임워크 | 방식 | 롤백 검증 |
| --- | --- | --- |
| spring-boot | `@Transactional` 서비스 + JPA `saveAndFlush` | 101자 값으로 `DataIntegrityViolationException` 발생 시 앞선 INSERT 없음 |
| nestjs / express | `pool.getConnection()` → `beginTransaction/commit/rollback`, `finally release()` | `ER_DATA_TOO_LONG` 발생 시 앞선 INSERT 없음 |
| fastapi | 컨텍스트 매니저에서 `commit` / 예외 시 `rollback`, 항상 풀 반환 | `DataError(1406)` 발생 시 앞선 INSERT 없음 |
| django | `transaction.atomic()` | `DataError` 발생 시 atomic 블록 전체 롤백 (테스트는 savepoint로 검증) |

모든 예제는 MySQL `STRICT_TRANS_TABLES` 모드에 의존해 길이 초과를 경고가 아닌 오류로 받습니다.

## 8. 오류 처리와 로깅

| 프레임워크 | DB 장애 → 503 | 응답에 SQL/드라이버 메시지 노출 | 요청 로그 |
| --- | --- | --- | --- |
| spring-boot | `@RestControllerAdvice` (`CannotGetJdbcConnectionException` 등) | 없음 | `OncePerRequestFilter`: 메서드, 경로, 상태, 시간 |
| nestjs | 전역 `@Catch()` 필터 (mysql2 오류 코드) | 없음 | 미들웨어: 경로만 (쿼리 문자열 제외) |
| express | 오류 처리 미들웨어 (mysql2 오류 코드) | 없음 | 미들웨어: 경로만 |
| fastapi | `exception_handler(errors.Error)` (errno) | 없음 | 미들웨어: 경로만. uvicorn 접근 로그 비활성화 |
| django | `process_exception` 미들웨어 (errno) | 없음 | 미들웨어: 경로만. `django.server` 로그 레벨 상향 |

검색값(쿼리 문자열)은 개인정보가 될 수 있으므로 어떤 예제도 로그에 남기지 않습니다. 비밀번호는 설정 객체 `repr`/로그에서 제외했습니다.

## 9. 테스트 방식

| 프레임워크 | 도구 | DB 격리 | 테스트 수 |
| --- | --- | --- | --- |
| spring-boot | JUnit 5 + `@SpringBootTest(RANDOM_PORT)` + `RestClient` | 각 테스트 전 `DELETE` + 고정 데이터 | 29 |
| nestjs | Jest + `@nestjs/testing` + supertest | 각 테스트 전 `DELETE` + 고정 데이터 | 34 |
| express | `node:test` + supertest | 각 테스트 전 `DELETE` + 고정 데이터 | 23 |
| fastapi | pytest + `TestClient` | fixture에서 `DELETE` + 고정 데이터 | 33 |
| django | `django.test.TestCase` + 전용 러너 | 테스트별 트랜잭션 롤백 | 19 (subTest 다수) |

## 10. 종료 처리

| 프레임워크 | 방식 |
| --- | --- |
| spring-boot | `server.shutdown=graceful` (10s), Hikari 풀은 컨텍스트 종료 시 close |
| nestjs | `enableShutdownHooks()` → `onApplicationShutdown`에서 `pool.end()` |
| express | `SIGINT/SIGTERM` → `server.close()` → `pool.end()` |
| fastapi | uvicorn 종료 → lifespan에서 풀 연결 제거 |
| django | gunicorn `--graceful-timeout 10` (컨테이너), runserver(호스트) |
