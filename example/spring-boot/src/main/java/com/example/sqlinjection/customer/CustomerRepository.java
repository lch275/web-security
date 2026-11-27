package com.example.sqlinjection.customer;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

/** Spring.md의 Spring Data JPA Repository 예제 */
public interface CustomerRepository extends JpaRepository<Customer, Long> {

    List<Customer> findByLastName(String lastName);

    @Query(value = "SELECT c.* FROM customers c WHERE c.last_name = ?1", nativeQuery = true)
    List<Customer> searchByLastName(String lastName);
}
