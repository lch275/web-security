package com.example.sqlinjection.customer;

public class CustomerNotFoundException extends RuntimeException {

    public CustomerNotFoundException(long id) {
        super("고객을 찾을 수 없습니다. id=" + id);
    }
}
