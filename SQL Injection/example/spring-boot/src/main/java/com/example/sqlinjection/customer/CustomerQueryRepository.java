package com.example.sqlinjection.customer;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

import javax.sql.DataSource;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceUtils;
import org.springframework.stereotype.Repository;

/**
 * Spring.md의 JDBC 예제를 모은 조회 전용 저장소.
 * SQL 구조는 코드에서 정하고 요청값은 항상 파라미터로 바인딩한다.
 */
@Repository
public class CustomerQueryRepository {

    private static final String COLUMNS = "id, last_name, created_at";
    private static final int QUERY_TIMEOUT_SECONDS = 10;

    private final JdbcTemplate jdbcTemplate;
    private final NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    private final DataSource dataSource;

    public CustomerQueryRepository(JdbcTemplate jdbcTemplate,
                                   NamedParameterJdbcTemplate namedParameterJdbcTemplate,
                                   DataSource dataSource) {
        this.jdbcTemplate = jdbcTemplate;
        this.namedParameterJdbcTemplate = namedParameterJdbcTemplate;
        this.dataSource = dataSource;
    }

    /** Spring.md: 요청의 정렬 키를 코드에 정의된 정렬 표현식에 매핑한다. 등록되지 않은 키는 거부한다. */
    static String orderBy(String sortKey) {
        return switch (sortKey) {
            case "name" -> "last_name ASC, id ASC";
            case "recent" -> "created_at DESC, id DESC";
            default -> throw new UnsupportedSortKeyException("지원하지 않는 정렬 기준입니다.");
        };
    }

    public void ping() {
        jdbcTemplate.queryForObject("SELECT 1", Integer.class);
    }

    /** JdbcTemplate: ?가 나오는 순서대로 값을 전달한다. */
    public List<Long> searchIds(String lastName, String sortKey) {
        return jdbcTemplate.queryForList(
                "SELECT id FROM customers WHERE last_name = ? ORDER BY " + orderBy(sortKey),
                Long.class,
                lastName);
    }

    /** NamedParameterJdbcTemplate: :lastName 이름에 대응하는 값을 전달한다. */
    public List<Long> searchIdsNamed(String lastName) {
        return namedParameterJdbcTemplate.queryForList(
                "SELECT id FROM customers WHERE last_name = :lastName ORDER BY id",
                new MapSqlParameterSource("lastName", lastName),
                Long.class);
    }

    /** Java JDBC PreparedStatement: 타입에 맞는 setXxx()로 1부터 시작하는 인덱스에 바인딩한다. */
    public List<Long> searchIdsWithPreparedStatement(String lastName) {
        String sql = "SELECT id FROM customers WHERE last_name = ? ORDER BY id";
        List<Long> customerIds = new ArrayList<>();
        // 트랜잭션에 참여하는 연결을 얻고, 사용 후 반드시 반환한다.
        Connection connection = DataSourceUtils.getConnection(dataSource);
        try (PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setQueryTimeout(QUERY_TIMEOUT_SECONDS);
            statement.setString(1, lastName);

            try (ResultSet rows = statement.executeQuery()) {
                while (rows.next()) {
                    customerIds.add(rows.getLong("id"));
                }
            }
        } catch (SQLException e) {
            throw jdbcTemplate.getExceptionTranslator().translate("searchIdsWithPreparedStatement", sql, e);
        } finally {
            DataSourceUtils.releaseConnection(connection, dataSource);
        }
        return customerIds;
    }

    /** LIKE: 이스케이프 문자 !와 와일드카드 %, _를 먼저 이스케이프한 뒤 패턴 전체를 바인딩한다. */
    public List<Long> containsIds(String searchText) {
        String literal = searchText.replace("!", "!!").replace("%", "!%").replace("_", "!_");
        return jdbcTemplate.queryForList(
                "SELECT id FROM customers WHERE last_name LIKE ? ESCAPE '!' ORDER BY id",
                Long.class,
                "%" + literal + "%");
    }

    public List<Long> sortedIds(String sortKey) {
        return jdbcTemplate.queryForList("SELECT id FROM customers ORDER BY " + orderBy(sortKey), Long.class);
    }

    /** IN 조건: 원소마다 자리표시자를 만들고, 빈 목록은 DB 호출 전에 빈 결과를 반환한다. */
    public List<Long> findIds(Collection<Long> ids) {
        if (ids.isEmpty()) {
            return List.of();
        }
        return namedParameterJdbcTemplate.queryForList(
                "SELECT id FROM customers WHERE id IN (:ids) ORDER BY id",
                new MapSqlParameterSource("ids", ids),
                Long.class);
    }

    public List<CustomerResponse> list(int limit, int offset) {
        return jdbcTemplate.query(
                "SELECT " + COLUMNS + " FROM customers ORDER BY id LIMIT ? OFFSET ?",
                (rs, rowNum) -> new CustomerResponse(
                        rs.getLong("id"),
                        rs.getString("last_name"),
                        rs.getTimestamp("created_at").toInstant()),
                limit,
                offset);
    }
}
