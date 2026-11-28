package com.example.sqlinjection.customer;

import java.time.Instant;

public record CustomerResponse(Long id, String lastName, Instant createdAt) {

    static CustomerResponse from(Customer customer) {
        return new CustomerResponse(customer.getId(), customer.getLastName(), customer.getCreatedAt());
    }
}
