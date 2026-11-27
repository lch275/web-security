package com.example.sqlinjection.customer;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import org.hibernate.annotations.Generated;

/**
 * Spring.md: {@code @Table(name = "customers")}, {@code @Column(name = "last_name")} 매핑.
 * 테이블은 example/dbms/mysql/init 에서 생성하며 Hibernate는 스키마를 변경하지 않는다(ddl-auto=none).
 */
@Entity
@Table(name = "customers")
public class Customer {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "last_name", nullable = false, length = 100)
    private String lastName;

    // DB 기본값(CURRENT_TIMESTAMP)을 INSERT 후 다시 읽는다.
    @Generated
    @Column(name = "created_at", insertable = false, updatable = false)
    private Instant createdAt;

    protected Customer() {
    }

    public Customer(String lastName) {
        this.lastName = lastName;
    }

    public Long getId() {
        return id;
    }

    public String getLastName() {
        return lastName;
    }

    public void changeLastName(String lastName) {
        this.lastName = lastName;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
