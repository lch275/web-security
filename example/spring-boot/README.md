# Spring Boot 예제

[`SQL Injection/Spring.md`](../../SQL%20Injection/Spring.md)를 실행 가능한 프로젝트로 구현했습니다. 문서에 버전이 명시되지 않아 단일 버전(Spring Boot 4.0.x)으로 구성했습니다.

| 항목 | 값 |
| --- | --- |
| 런타임 | Java 21 (Docker: `maven:3.9.11-eclipse-temurin-21`, `eclipse-temurin:21.0.8_9-jre-noble`) |
| 프레임워크 | Spring Boot 4.0.10 (Spring Framework 7.0.11, Hibernate 7.2.25, HikariCP) |
| 드라이버 | MySQL Connector/J `com.mysql:mysql-connector-j` 26.10.0 (BOM 관리) |
| 빌드 | Maven 3.9.11 (Maven Wrapper `mvnw`, `mvnw.cmd` 포함) |
| 테스트 | JUnit 5 + AssertJ, `@SpringBootTest(RANDOM_PORT)` + `RestClient` |
| 포트 | 8081 |
| DB | `spring_boot_customer_db` (실행) / `spring_boot_customer_test_db` (테스트), 계정 `spring_boot_app` |

## 구조

```
spring-boot/
├── pom.xml, mvnw, mvnw.cmd, .mvn/wrapper/
├── src/main/java/com/example/sqlinjection/
│   ├── SqlInjectionExampleApplication.java   # 진입점
│   ├── customer/
│   │   ├── CustomerController.java           # @RequestParam + Bean Validation
│   │   ├── CustomerQueryRepository.java      # JdbcTemplate, NamedParameterJdbcTemplate, PreparedStatement
│   │   ├── CustomerRepository.java           # Spring Data JPA (findByLastName, native @Query ?1)
│   │   ├── CustomerService.java              # @Transactional 쓰기 작업
│   │   └── Customer.java, CustomerResponse.java, *Exception.java
│   └── web/
│       ├── ApiExceptionHandler.java          # ProblemDetail: 400/404/503/500
│       ├── HealthController.java             # GET /health
│       └── RequestLoggingFilter.java         # 경로/상태/시간만 기록
├── src/main/resources/application.yml        # 환경변수 매핑, Hikari, 타임아웃
├── src/test/java/...                         # 실제 MySQL 통합 테스트 29건
└── Dockerfile                                # build / test / runtime
```

## 실행

```bash
example/scripts/mysql.sh up
example/scripts/example.sh build spring-boot    # JDK 21 자동 탐색 후 ./mvnw package
example/scripts/example.sh test spring-boot
example/scripts/example.sh run spring-boot      # http://127.0.0.1:8081
example/scripts/example.sh docker-test spring-boot   # 호스트에 JDK 21이 없을 때
```

스크립트는 `JAVA_HOME` → `~/.jdks/*21*` → `/usr/lib/jvm` 순서로 JDK 21 이상을 찾습니다. 직접 실행:

```bash
cd example/spring-boot
export JAVA_HOME=/path/to/jdk-21
export DB_HOST=127.0.0.1 DB_PORT=3306 DB_NAME=spring_boot_customer_db DB_USERNAME=spring_boot_app DB_PASSWORD='<SPRING_BOOT_DB_PASSWORD>'
./mvnw -DskipTests package && java -jar target/spring-boot-sql-injection-example-1.0.0.jar
```

테스트 DB는 `-Dtest.db.name=...`로 바꿀 수 있으며 `_test_db`로 끝나지 않으면 테스트가 실패합니다.

| 환경변수 | 기본값 | 매핑 |
| --- | --- | --- |
| `DB_HOST`, `DB_PORT`, `DB_NAME` | `localhost`, `3306`, `spring_boot_customer_db` | `spring.datasource.url` |
| `DB_USERNAME`, `DB_PASSWORD` | `spring_boot_app`, (필수) | `spring.datasource.username/password` |
| `DB_POOL_SIZE` | `10` | `spring.datasource.hikari.maximum-pool-size` |
| `APP_PORT` | `8081` | `server.port` |

## 연결/타임아웃 설정

| 항목 | 설정 |
| --- | --- |
| 다중 문 실행 | `allowMultiQueries=false` (Connector/J 기본값을 명시) |
| 연결 타임아웃 | Connector/J `connectTimeout=5000`, Hikari `connection-timeout: 5000` |
| 소켓 읽기 타임아웃 | `socketTimeout=30000` |
| 쿼리 타임아웃 | `spring.jdbc.template.query-timeout: 10s`, JPA `jakarta.persistence.query.timeout: 10000`, `PreparedStatement.setQueryTimeout(10)` |
| 자원 반환 | try-with-resources, `DataSourceUtils.releaseConnection`, Hikari `leak-detection-threshold: 20000` |
| DB 장애 시 기동 | `initialization-fail-timeout: -1`, `hibernate.boot.allow_jdbc_metadata_access: false` → 요청 시 503 |
| 종료 | `server.shutdown: graceful`, 최대 10초 |

## API와 예상 결과

```bash
curl "http://127.0.0.1:8081/customers/search?lastName=O%27Connor"           # [4]
curl -G http://127.0.0.1:8081/customers/search --data-urlencode "lastName=O'Connor'#"   # []
curl "http://127.0.0.1:8081/customers/search?lastName=Smith&sort=recent"     # [6,5]
curl "http://127.0.0.1:8081/customers/search?lastName=Kim&sort=id"           # 400 ProblemDetail
curl http://127.0.0.1:8081/health                                            # {"status":"UP"}
```

## 문서 요구사항 구현 위치

| Spring.md | 구현 |
| --- | --- |
| `@RequestParam("lastName")` + `JdbcTemplate.queryForList(..., lastName)` | `CustomerController.searchCustomers`, `CustomerQueryRepository.searchIds` |
| `PreparedStatement` + `setString(1, ...)` | `searchIdsWithPreparedStatement` |
| `NamedParameterJdbcTemplate` `:lastName`, `IN (:ids)` + 빈 목록 단락 | `searchIdsNamed`, `findIds` |
| `CustomerRepository.findByLastName` / native `@Query ... ?1` | `CustomerRepository` |
| 정렬 `switch` 허용 목록 | `CustomerQueryRepository.orderBy` |
| `LIKE ? ESCAPE '!'` | `containsIds` |
| `allowMultiQueries` 기본값 유지 | `application.yml` |
| 통합 테스트(O'Connor, 빈 결과, `%`/`_`, 정렬 순서), 바인딩 방식 간 결과 비교 | `CustomerApiIntegrationTest` |

### 문서 예제와 다르게 구현한 부분

문서는 미등록 정렬 키에 `IllegalArgumentException`을 던집니다. 이 예외를 `@Repository` 빈 안에서 던지면 Spring의 JPA 예외 변환이 `InvalidDataAccessApiUsageException`(`DataAccessException`)으로 바꾸어, DB 오류처럼 500으로 처리됩니다(실제 테스트에서 확인). 그래서 `RuntimeException`을 상속한 `UnsupportedSortKeyException`을 사용하고 400으로 응답합니다.
