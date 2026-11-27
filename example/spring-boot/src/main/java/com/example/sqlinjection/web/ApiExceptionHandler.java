package com.example.sqlinjection.web;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.dao.QueryTimeoutException;
import org.springframework.dao.TransientDataAccessResourceException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.jdbc.CannotGetJdbcConnectionException;
import org.springframework.transaction.CannotCreateTransactionException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

import com.example.sqlinjection.customer.CustomerNotFoundException;
import com.example.sqlinjection.customer.InvalidRequestException;
import com.example.sqlinjection.customer.UnsupportedSortKeyException;

/**
 * Spring MVC 표준 예외(누락/형식 오류/Bean Validation)는 상위 클래스가 400 ProblemDetail로 변환한다.
 * DB 오류는 SQL이나 입력값을 노출하지 않고 503/500으로 응답한다.
 */
@RestControllerAdvice
public class ApiExceptionHandler extends ResponseEntityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler({UnsupportedSortKeyException.class, InvalidRequestException.class})
    ProblemDetail badRequest(RuntimeException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    @ExceptionHandler(CustomerNotFoundException.class)
    ProblemDetail notFound(CustomerNotFoundException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.NOT_FOUND, "고객을 찾을 수 없습니다.");
    }

    @ExceptionHandler({
            CannotGetJdbcConnectionException.class,
            CannotCreateTransactionException.class,
            DataAccessResourceFailureException.class,
            TransientDataAccessResourceException.class,
            QueryTimeoutException.class})
    ProblemDetail unavailable(Exception e) {
        log.error("database unavailable: {}", e.getClass().getSimpleName());
        return ProblemDetail.forStatusAndDetail(HttpStatus.SERVICE_UNAVAILABLE, "데이터베이스를 사용할 수 없습니다.");
    }

    @ExceptionHandler(DataAccessException.class)
    ProblemDetail databaseError(DataAccessException e) {
        log.error("database error: {}: {}", e.getClass().getSimpleName(), e.getMostSpecificCause().getMessage());
        return ProblemDetail.forStatusAndDetail(HttpStatus.INTERNAL_SERVER_ERROR, "요청을 처리하지 못했습니다.");
    }
}
