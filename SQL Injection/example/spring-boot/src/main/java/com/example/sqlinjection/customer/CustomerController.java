package com.example.sqlinjection.customer;

import java.util.Arrays;
import java.util.List;
import java.util.regex.Pattern;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;

import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * 요청 파라미터는 Bean Validation으로 검증하고(실패 시 400), 검증을 통과한 값도 SQL에는 바인딩한다.
 */
@RestController
@RequestMapping("/customers")
public class CustomerController {

    private static final Pattern IDS = Pattern.compile("^$|^[1-9][0-9]{0,17}(,[1-9][0-9]{0,17}){0,99}$");

    private final CustomerQueryRepository queries;
    private final CustomerService service;

    public CustomerController(CustomerQueryRepository queries, CustomerService service) {
        this.queries = queries;
        this.service = service;
    }

    public record CustomerRequest(@NotBlank @Size(max = 100) String lastName) {
    }

    public record CustomerBatchRequest(@NotEmpty @Size(max = 100) List<@NotBlank @Size(max = 100) String> lastNames) {
    }

    /** Spring.md: SQL에 WHERE last_name = ? 조건을 고정하고 lastName을 별도 인자로 전달한다. */
    @GetMapping("/search")
    public List<Long> searchCustomers(
            @RequestParam("lastName") @NotBlank @Size(max = 100) String lastName,
            @RequestParam(name = "sort", defaultValue = "name") String sort) {
        return queries.searchIds(lastName, sort);
    }

    @GetMapping("/contains")
    public List<Long> contains(@RequestParam("keyword") @Size(min = 1, max = 100) String keyword) {
        return queries.containsIds(keyword);
    }

    @GetMapping("/sorted")
    public List<Long> sorted(@RequestParam("sort") String sort) {
        return queries.sortedIds(sort);
    }

    @GetMapping("/by-ids")
    public List<Long> byIds(@RequestParam("ids") String ids) {
        if (!IDS.matcher(ids).matches()) {
            throw new InvalidRequestException("ids는 쉼표로 구분한 1 이상의 정수를 최대 100개까지 전달할 수 있습니다.");
        }
        List<Long> idList = ids.isEmpty()
                ? List.of()
                : Arrays.stream(ids.split(",")).map(Long::valueOf).distinct().toList();
        return queries.findIds(idList);
    }

    @GetMapping
    public List<CustomerResponse> list(
            @RequestParam(name = "limit", defaultValue = "20") @Min(1) @Max(100) int limit,
            @RequestParam(name = "offset", defaultValue = "0") @Min(0) @Max(100_000) int offset) {
        return queries.list(limit, offset);
    }

    @PostMapping("/batch")
    @ResponseStatus(HttpStatus.CREATED)
    public List<CustomerResponse> createAll(@Valid @RequestBody CustomerBatchRequest request) {
        return service.createAll(request.lastNames());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public CustomerResponse create(@Valid @RequestBody CustomerRequest request) {
        return service.create(request.lastName());
    }

    @GetMapping("/{id}")
    public CustomerResponse get(@PathVariable("id") @Positive long id) {
        return service.get(id);
    }

    @PutMapping("/{id}")
    public CustomerResponse update(@PathVariable("id") @Positive long id, @Valid @RequestBody CustomerRequest request) {
        return service.update(id, request.lastName());
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable("id") @Positive long id) {
        service.delete(id);
    }
}
