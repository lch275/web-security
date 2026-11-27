package com.example.sqlinjection;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.web.client.RestClient;

/** 연결할 수 없는 DB 주소로 기동하여 장애 시 503 응답과 비노출을 확인한다. */
@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "spring.datasource.url=jdbc:mysql://127.0.0.1:1/unreachable?connectTimeout=1000",
                "spring.datasource.hikari.connection-timeout=1000",
                "spring.datasource.hikari.minimum-idle=0"
        })
class DatabaseFailureTest {

    @Value("${local.server.port}")
    int port;

    @Test
    void unreachableDatabaseReturns503() {
        RestClient http = RestClient.builder()
                .baseUrl("http://localhost:" + port)
                .defaultStatusHandler(status -> true, (request, response) -> {
                })
                .build();

        assertThat(http.get().uri("/health").retrieve().toBodilessEntity().getStatusCode().value()).isEqualTo(503);

        var search = http.get().uri("/customers/search?lastName=Kim").retrieve().toEntity(String.class);
        assertThat(search.getStatusCode().value()).isEqualTo(503);
        assertThat(search.getBody()).doesNotContain("Communications link failure").doesNotContain("SELECT");

        var create = http.post().uri("/customers").header("Content-Type", "application/json")
                .body("{\"lastName\":\"Kim\"}").retrieve().toEntity(String.class);
        assertThat(create.getStatusCode().value()).isEqualTo(503);
    }
}
