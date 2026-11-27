package com.example.sqlinjection;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.support.GeneratedKeyHolder;
import org.springframework.web.client.RestClient;

import com.example.sqlinjection.customer.Customer;
import com.example.sqlinjection.customer.CustomerQueryRepository;
import com.example.sqlinjection.customer.CustomerRepository;
import com.example.sqlinjection.customer.CustomerResponse;
import com.example.sqlinjection.customer.CustomerService;

/** 실제 MySQL(spring_boot_customer_test_db)을 사용하는 통합 테스트 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class CustomerApiIntegrationTest {

    private static final ParameterizedTypeReference<List<Long>> ID_LIST = new ParameterizedTypeReference<>() {
    };
    private static final String[][] FIXTURES = {
            {"O'Connor", "2026-01-01 10:00:00"},
            {"Kim", "2026-01-02 10:00:00"},
            {"Smith", "2026-01-03 10:00:00"},
            {"Smith", "2026-01-04 10:00:00"},
            {"Under_Score", "2026-01-05 10:00:00"},
            {"UnderXScore", "2026-01-06 10:00:00"},
            {"Percent%Sign", "2026-01-07 10:00:00"},
            {"PercentXSign", "2026-01-08 10:00:00"},
            {"Bang!Name", "2026-01-09 10:00:00"},
    };
    static final String[] INJECTION_PAYLOADS = {
            "' OR '1'='1",
            "O'Connor' OR '1'='1",
            "x'; DROP TABLE customers; --",
            "O'Connor' -- ",
            "O'Connor'#",
            "O'Connor'/* comment */",
            "' UNION SELECT id FROM customers -- ",
    };

    @Value("${local.server.port}")
    int port;
    @Value("${spring.datasource.url}")
    String jdbcUrl;
    @Value("${spring.datasource.username}")
    String username;
    @Value("${spring.datasource.password}")
    String password;

    @Autowired
    JdbcTemplate jdbcTemplate;
    @Autowired
    CustomerQueryRepository queries;
    @Autowired
    CustomerRepository customerRepository;
    @Autowired
    CustomerService customerService;

    RestClient http;
    final Map<String, List<Long>> ids = new LinkedHashMap<>();
    final List<Long> insertedIds = new ArrayList<>();

    @BeforeAll
    static void guardTestDatabase() {
        String dbName = System.getProperty("DB_NAME", "");
        assertThat(dbName).as("테스트는 *_test_db 에서만 실행합니다").endsWith("_test_db");
    }

    @BeforeEach
    void setUp() {
        http = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> {
                })
                .build();
        jdbcTemplate.update("DELETE FROM customers");
        ids.clear();
        insertedIds.clear();
        for (String[] row : FIXTURES) {
            GeneratedKeyHolder keys = new GeneratedKeyHolder();
            jdbcTemplate.update(connection -> {
                PreparedStatement ps = connection.prepareStatement(
                        "INSERT INTO customers (last_name, created_at) VALUES (?, ?)", Statement.RETURN_GENERATED_KEYS);
                ps.setString(1, row[0]);
                ps.setString(2, row[1]);
                return ps;
            }, keys);
            Long id = keys.getKey().longValue();
            ids.computeIfAbsent(row[0], k -> new ArrayList<>()).add(id);
            insertedIds.add(id);
        }
    }

    ResponseEntity<List<Long>> getIds(String uri, Object... vars) {
        return http.get().uri(uri, vars).retrieve().toEntity(ID_LIST);
    }

    int status(String uri, Object... vars) {
        return http.get().uri(uri, vars).retrieve().toBodilessEntity().getStatusCode().value();
    }

    int countRows() {
        return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM customers", Integer.class);
    }

    @Nested
    class ValueBinding {

        @Test
        void oConnorReturnsOnlyThatCustomer() {
            ResponseEntity<List<Long>> res = getIds("/customers/search?lastName={v}", "O'Connor");
            assertThat(res.getStatusCode().value()).isEqualTo(200);
            assertThat(res.getBody()).isEqualTo(ids.get("O'Connor"));
        }

        @Test
        void unknownLastNameReturnsEmptyList() {
            assertThat(getIds("/customers/search?lastName={v}", "Nobody").getBody()).isEmpty();
        }

        @ParameterizedTest
        @ValueSource(strings = {
                "' OR '1'='1",
                "O'Connor' OR '1'='1",
                "x'; DROP TABLE customers; --",
                "O'Connor' -- ",
                "O'Connor'#",
                "O'Connor'/* comment */",
                "' UNION SELECT id FROM customers -- "})
        void injectionPayloadIsComparedAsValue(String payload) {
            ResponseEntity<List<Long>> res = getIds("/customers/search?lastName={v}", payload);
            assertThat(res.getStatusCode().value()).isEqualTo(200);
            assertThat(res.getBody()).isEmpty();
            assertThat(countRows()).isEqualTo(FIXTURES.length);
        }

        @Test
        void allBindingStylesReturnSameResult() {
            for (String value : List.of("O'Connor", "Smith", "Nobody", INJECTION_PAYLOADS[0], INJECTION_PAYLOADS[2])) {
                List<Long> expected = queries.searchIdsNamed(value);
                assertThat(queries.searchIdsWithPreparedStatement(value)).as(value).isEqualTo(expected);
                assertThat(queries.searchIds(value, "name")).as(value).isEqualTo(expected);
                assertThat(customerRepository.findByLastName(value).stream().map(Customer::getId).sorted().toList())
                        .as(value).isEqualTo(expected);
                assertThat(customerRepository.searchByLastName(value).stream().map(Customer::getId).sorted().toList())
                        .as(value).isEqualTo(expected);
            }
        }

        @Test
        void sortKeysDefineOrder() {
            Long older = ids.get("Smith").get(0);
            Long newer = ids.get("Smith").get(1);
            assertThat(getIds("/customers/search?lastName=Smith&sort=name").getBody()).containsExactly(older, newer);
            assertThat(getIds("/customers/search?lastName=Smith&sort=recent").getBody()).containsExactly(newer, older);
        }

        @Test
        void invalidInputReturns400() {
            assertThat(status("/customers/search")).isEqualTo(400);
            assertThat(status("/customers/search?lastName=")).isEqualTo(400);
            assertThat(status("/customers/search?lastName={v}", "   ")).isEqualTo(400);
            assertThat(status("/customers/search?lastName={v}", "a".repeat(101))).isEqualTo(400);
            assertThat(status("/customers/search?lastName=Kim&sort=last_name")).isEqualTo(400);
        }
    }

    @Nested
    class SortLikeIn {

        @Test
        void sortedByAllowListOnly() {
            List<Long> byName = new ArrayList<>();
            for (String name : List.of("Bang!Name", "Kim", "O'Connor", "Percent%Sign", "PercentXSign", "Smith",
                    "Under_Score", "UnderXScore")) {
                byName.addAll(ids.get(name));
            }
            assertThat(getIds("/customers/sorted?sort=name").getBody()).isEqualTo(byName);
            List<Long> recent = new ArrayList<>(insertedIds);
            Collections.reverse(recent);
            assertThat(getIds("/customers/sorted?sort=recent").getBody()).isEqualTo(recent);
            assertThat(status("/customers/sorted")).isEqualTo(400);
            assertThat(status("/customers/sorted?sort={v}", "id;DROP TABLE customers")).isEqualTo(400);
        }

        @ParameterizedTest
        @CsvSource(delimiter = '|', value = {
                "r_S|Under_Score",
                "_|Under_Score",
                "t%S|Percent%Sign",
                "%|Percent%Sign",
                "g!N|Bang!Name",
                "mit|Smith"})
        void likeWildcardsAreLiteral(String keyword, String name) {
            assertThat(getIds("/customers/contains?keyword={v}", keyword).getBody()).isEqualTo(ids.get(name));
        }

        @Test
        void inQuery() {
            List<Long> wanted = new ArrayList<>(List.of(ids.get("Kim").get(0), ids.get("O'Connor").get(0)));
            Collections.sort(wanted);
            assertThat(getIds("/customers/by-ids?ids={a},{b}", wanted.get(0), wanted.get(1)).getBody()).isEqualTo(wanted);
            assertThat(getIds("/customers/by-ids?ids=").getBody()).isEmpty();
            assertThat(queries.findIds(List.of())).isEmpty();
            assertThat(status("/customers/by-ids")).isEqualTo(400);
            assertThat(status("/customers/by-ids?ids=1,abc")).isEqualTo(400);
            assertThat(status("/customers/by-ids?ids={v}", "1 OR 1=1")).isEqualTo(400);
        }
    }

    @Nested
    class Crud {

        @Test
        void createReadUpdateDelete() {
            ResponseEntity<CustomerResponse> created = http.post().uri("/customers")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("lastName", "  Tester  "))
                    .retrieve().toEntity(CustomerResponse.class);
            assertThat(created.getStatusCode().value()).isEqualTo(201);
            assertThat(created.getBody().lastName()).isEqualTo("Tester");
            assertThat(created.getBody().createdAt()).isNotNull();
            long id = created.getBody().id();

            assertThat(http.get().uri("/customers/{id}", id).retrieve().body(CustomerResponse.class).lastName())
                    .isEqualTo("Tester");
            assertThat(http.get().uri("/customers?limit=2").retrieve().body(CustomerResponse[].class)).hasSize(2);

            CustomerResponse updated = http.put().uri("/customers/{id}", id)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("lastName", "D'Angelo"))
                    .retrieve().body(CustomerResponse.class);
            assertThat(updated.lastName()).isEqualTo("D'Angelo");

            assertThat(http.delete().uri("/customers/{id}", id).retrieve().toBodilessEntity().getStatusCode().value())
                    .isEqualTo(204);
            assertThat(status("/customers/{id}", id)).isEqualTo(404);
            assertThat(http.delete().uri("/customers/{id}", id).retrieve().toBodilessEntity().getStatusCode().value())
                    .isEqualTo(404);
        }

        @Test
        void invalidInputReturns400() {
            assertThat(post("/customers", "{\"lastName\":\"   \"}")).isEqualTo(400);
            assertThat(post("/customers", "{\"lastName\":[\"a\"]}")).isEqualTo(400);
            assertThat(post("/customers", "{bad")).isEqualTo(400);
            assertThat(status("/customers/abc")).isEqualTo(400);
            assertThat(status("/customers?limit=1000")).isEqualTo(400);
        }
    }

    @Nested
    class Transactions {

        @Test
        void batchCommitsAllRows() {
            ResponseEntity<CustomerResponse[]> res = http.post().uri("/customers/batch")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(Map.of("lastNames", List.of("Batch-A", "Batch-B")))
                    .retrieve().toEntity(CustomerResponse[].class);
            assertThat(res.getStatusCode().value()).isEqualTo(201);
            assertThat(res.getBody()).extracting(CustomerResponse::lastName).containsExactly("Batch-A", "Batch-B");
            assertThat(countRows()).isEqualTo(FIXTURES.length + 2);
        }

        @Test
        void databaseErrorRollsBackPreviousInsert() {
            assertThatThrownBy(() -> customerService.createAll(List.of("Rollback-A", "x".repeat(101))))
                    .isInstanceOf(DataIntegrityViolationException.class);
            assertThat(jdbcTemplate.queryForObject(
                    "SELECT COUNT(*) FROM customers WHERE last_name = ?", Integer.class, "Rollback-A")).isZero();
            assertThat(countRows()).isEqualTo(FIXTURES.length);
        }

        @Test
        void batchValidationFailureSavesNothing() {
            assertThat(post("/customers/batch", "{\"lastNames\":[\"Ok\",\"\"]}")).isEqualTo(400);
            assertThat(countRows()).isEqualTo(FIXTURES.length);
        }
    }

    @Nested
    class Privileges {

        @Test
        void appAccountCannotRunDdl() {
            assertThatThrownBy(() -> jdbcTemplate.execute("DROP TABLE customers"))
                    .isInstanceOf(DataAccessException.class)
                    .hasRootCauseInstanceOf(SQLException.class)
                    .rootCause().satisfies(e -> assertThat(((SQLException) e).getErrorCode()).isEqualTo(1142));
            assertThat(countRows()).isEqualTo(FIXTURES.length);
        }

        @Test
        @EnabledIfEnvironmentVariable(named = "DB_READER_PASSWORD", matches = ".+")
        void readerAccountCannotInsert() throws SQLException {
            String reader = System.getenv().getOrDefault("DB_READER_USERNAME", "spring_boot_reader");
            try (Connection connection = DriverManager.getConnection(jdbcUrl, reader, System.getenv("DB_READER_PASSWORD"));
                 Statement statement = connection.createStatement()) {
                statement.executeQuery("SELECT COUNT(*) FROM customers").close();
                assertThatThrownBy(() -> statement.executeUpdate("INSERT INTO customers (last_name) VALUES ('Denied')"))
                        .isInstanceOf(SQLException.class)
                        .satisfies(e -> assertThat(((SQLException) e).getErrorCode()).isEqualTo(1142));
            }
        }
    }

    @Test
    void healthIsUp() {
        assertThat(http.get().uri("/health").retrieve().body(Map.class)).isEqualTo(Map.of("status", "UP"));
    }

    int post(String uri, String json) {
        return http.post().uri(uri).contentType(MediaType.APPLICATION_JSON).body(json)
                .retrieve().toBodilessEntity().getStatusCode().value();
    }
}
