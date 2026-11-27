package com.example.sqlinjection.customer;

/**
 * 허용 목록에 없는 정렬 키.
 * <p>
 * Spring.md 예제는 IllegalArgumentException을 사용한다. 그러나 {@code @Repository} 빈에서 던진
 * IllegalArgumentException은 JPA 예외 변환에 의해 InvalidDataAccessApiUsageException(DataAccessException)으로
 * 바뀌어 DB 오류(500)처럼 처리된다. 그래서 RuntimeException을 직접 상속한다.
 */
public class UnsupportedSortKeyException extends RuntimeException {

    public UnsupportedSortKeyException(String message) {
        super(message);
    }
}
