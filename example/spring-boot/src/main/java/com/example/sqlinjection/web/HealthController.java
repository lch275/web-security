package com.example.sqlinjection.web;

import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.example.sqlinjection.customer.CustomerQueryRepository;

@RestController
public class HealthController {

    private static final Logger log = LoggerFactory.getLogger(HealthController.class);

    private final CustomerQueryRepository queries;

    public HealthController(CustomerQueryRepository queries) {
        this.queries = queries;
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        try {
            queries.ping();
            return ResponseEntity.ok(Map.of("status", "UP"));
        } catch (DataAccessException e) {
            log.warn("health check failed: {}", e.getClass().getSimpleName());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(Map.of("status", "DOWN"));
        }
    }
}
