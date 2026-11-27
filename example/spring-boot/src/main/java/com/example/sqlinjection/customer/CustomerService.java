package com.example.sqlinjection.customer;

import java.util.List;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 쓰기 작업은 Spring Data JPA와 선언적 트랜잭션으로 처리한다. */
@Service
public class CustomerService {

    private final CustomerRepository customerRepository;

    public CustomerService(CustomerRepository customerRepository) {
        this.customerRepository = customerRepository;
    }

    @Transactional(readOnly = true)
    public CustomerResponse get(long id) {
        return customerRepository.findById(id)
                .map(CustomerResponse::from)
                .orElseThrow(() -> new CustomerNotFoundException(id));
    }

    @Transactional
    public CustomerResponse create(String lastName) {
        return CustomerResponse.from(customerRepository.saveAndFlush(new Customer(lastName.strip())));
    }

    /** 하나의 트랜잭션으로 저장한다. 중간에 예외가 발생하면 앞선 INSERT까지 모두 롤백된다. */
    @Transactional
    public List<CustomerResponse> createAll(List<String> lastNames) {
        return lastNames.stream()
                .map(lastName -> customerRepository.saveAndFlush(new Customer(lastName.strip())))
                .map(CustomerResponse::from)
                .toList();
    }

    @Transactional
    public CustomerResponse update(long id, String lastName) {
        Customer customer = customerRepository.findById(id).orElseThrow(() -> new CustomerNotFoundException(id));
        customer.changeLastName(lastName.strip());
        return CustomerResponse.from(customerRepository.saveAndFlush(customer));
    }

    @Transactional
    public void delete(long id) {
        Customer customer = customerRepository.findById(id).orElseThrow(() -> new CustomerNotFoundException(id));
        customerRepository.delete(customer);
    }
}
