# Java와 Spring에서 MySQL을 사용할 때의 SQL Injection 방어

SQL query의 구조는 코드에서 정하고, 외부 입력값은 parameter로 바인딩한다. 문자열 연결이나 `String.format()`, `.formatted()`로 입력값을 query 본문에 넣으면 `PreparedStatement`에도 이미 조합된 SQL이 전달된다. JDBC의 `?`와 Spring JDBC의 `:lastName` 같은 placeholder는 따옴표 없이 작성한다. [OWASP SQL Injection Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html)

## MySQL 예제 환경

예제에서는 MySQL 8.4의 `customer_db.customers` table과 MySQL Connector/J(`com.mysql:mysql-connector-j`)를 사용한다. JDBC URL은 `jdbc:mysql://localhost:3306/customer_db`를 사용한다. Spring Boot에서는 이 URL을 `spring.datasource.url`에 설정한다. [MySQL Connector/J Configuration](https://dev.mysql.com/doc/connector-j/en/connector-j-reference-configuration-properties.html)

`customer_db`를 기본 schema로 선택한 상태에서 다음 table을 생성한다. [MySQL `CREATE TABLE`](https://dev.mysql.com/doc/refman/8.4/en/create-table.html)

```sql
CREATE TABLE customers (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    last_name VARCHAR(100) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE = InnoDB DEFAULT CHARACTER SET = utf8mb4;
```

## HTTP Request Parameter 변조 방어

고객 검색 화면에서 `lastName`에 성을 입력받더라도, 클라이언트는 HTTP 요청의 parameter 값을 직접 바꿀 수 있다. Spring MVC의 `@RequestParam`은 이 값을 읽어 method 인자로 전달한다. 조회할 때는 SQL에 `WHERE last_name = ?` 조건을 고정하고, `lastName`을 `JdbcTemplate`의 별도 인자로 전달한다. [Spring JDBC Reference](https://docs.spring.io/spring-framework/reference/data-access/jdbc/core.html)

```java
// jdbcTemplate이 주입된 Spring MVC 컨트롤러 내부
@GetMapping("/customers/search")
public List<Long> searchCustomers(@RequestParam("lastName") String lastName) {
    return jdbcTemplate.queryForList(
        "SELECT id FROM customers WHERE last_name = ?",
        Long.class,
        lastName
    );
}
```

`GET /customers/search?lastName=O%27Connor`를 요청하면 Spring MVC는 `O'Connor`를 전달하고, MySQL은 이 값을 `last_name`과 비교한다. `lastName`이 마지막 parameter이고 입력에 세미콜론(`;`)과 `SELECT`가 이어져도 처리 방식은 같다. `JdbcTemplate`이 요청값 전체를 하나의 문자열로 바인딩하므로 `WHERE` 절의 구조는 유지되고 추가 query는 실행되지 않는다. 일치하는 성이 없으면 빈 목록을 반환한다. [MySQL `PREPARE`](https://dev.mysql.com/doc/refman/8.4/en/prepare.html)

`lastName`에 `--`, `#`, `/* ... */` 같은 주석 표기가 포함되어도 값 전체를 그대로 바인딩한다. MySQL은 이 표기를 검색값의 문자로 비교하므로 query의 기존 조건은 그대로 적용된다. 이 동작은 단일 SQL 문 안에서도 적용된다. [MySQL SQL Comments](https://dev.mysql.com/doc/refman/8.4/en/comments.html) · [MySQL `PREPARE`](https://dev.mysql.com/doc/refman/8.4/en/prepare.html)

MySQL Connector/J의 `allowMultiQueries` 기본값은 `false`다. 이 설정을 유지하면 일반 JDBC 실행 호출에서 세미콜론으로 구분한 여러 SQL 문을 한 번에 실행하는 기능이 꺼진다. 단일 SQL 문에서도 입력을 연결하면 조회 조건이 바뀔 수 있으므로 parameter binding을 적용한다. [MySQL Connector/J Security Properties](https://dev.mysql.com/doc/connector-j/en/connector-j-connp-props-security.html)

## Java JDBC의 `PreparedStatement`

`setString()`, `setLong()` 등 값의 타입에 맞는 method를 사용해 query의 `?`에 값을 바인딩한다. JDBC parameter의 index는 1부터 시작한다. [Oracle JDBC 가이드](https://docs.oracle.com/javase/tutorial/jdbc/basics/prepared.html)

```java
String sql = "SELECT id FROM customers WHERE last_name = ?";

try (PreparedStatement statement = connection.prepareStatement(sql)) {
    statement.setString(1, lastName);

    try (ResultSet rows = statement.executeQuery()) {
        while (rows.next()) {
            customerIds.add(rows.getLong("id"));
        }
    }
}
```

## Spring JDBC의 `JdbcTemplate`과 `NamedParameterJdbcTemplate`

`JdbcTemplate`에는 query의 `?`가 나오는 순서대로 값을 전달한다. `NamedParameterJdbcTemplate`에는 `:lastName`처럼 query에 지정한 parameter 이름에 대응하는 값을 전달한다. [Spring JDBC Reference](https://docs.spring.io/spring-framework/reference/data-access/jdbc/core.html)

```java
List<Long> ids = jdbcTemplate.queryForList(
    "SELECT id FROM customers WHERE last_name = ?",
    Long.class,
    lastName
);

List<Long> idsByName = namedParameterJdbcTemplate.queryForList(
    "SELECT id FROM customers WHERE last_name = :lastName",
    new MapSqlParameterSource("lastName", lastName),
    Long.class
);
```

`IN` 조건은 `WHERE id IN (:ids)`처럼 작성하고 `ids`에 collection을 전달한다. `NamedParameterJdbcTemplate`은 원소마다 placeholder를 만든다. 빈 목록에 대해 조회 결과가 없어야 한다면 데이터베이스를 호출하기 전에 빈 결과를 반환한다. [NamedParameterJdbcTemplate API](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/jdbc/core/namedparam/NamedParameterJdbcTemplate.html)

## Spring Data JPA의 Repository와 `@Query`

`Customer` entity를 `@Table(name = "customers")`로, `lastName` 필드를 `@Column(name = "last_name")`으로 매핑한다. `findByLastName`은 이 매핑을 바탕으로 조회한다. MySQL query를 직접 작성할 때는 `@Query`에 `nativeQuery = true`를 지정한다. `?1`에는 method의 첫 번째 인자가 바인딩된다. [Spring Data JPA Reference](https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html)

```java
public interface CustomerRepository extends JpaRepository<Customer, Long> {
    List<Customer> findByLastName(String lastName);

    @Query(value = "SELECT c.* FROM customers c WHERE c.last_name = ?1", nativeQuery = true)
    List<Customer> searchByLastName(String lastName);
}
```

## Dynamic Sorting과 검색 조건

column 이름, table 이름, 정렬 방향은 SQL 구조의 일부이므로 값으로 바인딩할 수 없다. 동적 정렬에서는 요청의 sort key를 코드에 정의된 정렬 표현식에 매핑한다. 등록되지 않은 키는 거부한다. Spring Data JPA에서는 allowlist에 있는 entity 속성을 `Sort.by()`에 전달한다. [OWASP Allowlist Validation](https://cheatsheetseries.owasp.org/cheatsheets/SQL_Injection_Prevention_Cheat_Sheet.html#allow-list-input-validation) · [Spring Data JPA Sorting](https://docs.spring.io/spring-data/jpa/reference/jpa/query-methods.html#jpa.query-methods.sorting)

```java
// sortKey는 기본값 처리와 필수 값 검증을 마친 요청 파라미터다.
String orderBy = switch (sortKey) {
    case "name" -> "last_name ASC, id ASC";
    case "recent" -> "created_at DESC, id DESC";
    default -> throw new IllegalArgumentException("지원하지 않는 정렬 기준입니다.");
};

List<Long> sortedIds = jdbcTemplate.queryForList(
    "SELECT id FROM customers WHERE last_name = ? ORDER BY " + orderBy,
    Long.class,
    lastName
);
```

MySQL의 `LIKE` 검색에서 입력값에 포함된 `%`와 `_`를 일반 문자로 처리하려면 `ESCAPE` 절에 escape 문자를 지정한다. 아래 예제에서는 escape 문자 `!`와 wildcard `%`, `_`를 먼저 escape한다. 부분 검색을 위해 양쪽에 `%`를 붙인 뒤 패턴 전체를 바인딩한다. [MySQL `LIKE`와 `ESCAPE`](https://dev.mysql.com/doc/refman/8.4/en/string-comparison-functions.html)

```java
String literal = searchText.replace("!", "!!").replace("%", "!%").replace("_", "!_");
List<Long> matchingIds = jdbcTemplate.queryForList(
    "SELECT id FROM customers WHERE last_name LIKE ? ESCAPE '!'",
    Long.class,
    "%" + literal + "%"
);
```

## 운영과 테스트

- 요청값의 타입과 길이를 검증하고, 검증을 마친 값도 parameter로 바인딩한다.
- MySQL 조회 계정에는 필요한 table이나 view에만 `SELECT` 권한을 부여한다. schema 변경에는 별도 계정을 사용한다. [MySQL `GRANT`](https://dev.mysql.com/doc/refman/8.4/en/grant.html)
- MySQL integration test에서 `O'Connor`와 다른 성의 고객을 준비한다. `lastName`에 `O'Connor`를 보내면 해당 고객만 반환하고, 저장되지 않은 성을 보내면 빈 결과를 반환하는지 확인한다.
- `LIKE`에 전달한 `%`와 `_`가 일반 문자로 처리되는지 확인한다.
- 허용된 sort key마다 결과가 지정한 순서로 반환되는지 확인한다.
