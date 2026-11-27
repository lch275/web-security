# NestJS에서 MySQL을 사용할 때의 SQL Injection 방어

## MySQL 예제 환경

[Java와 Spring 예제](Spring.md#mysql-예제-환경)와 같은 MySQL 8.4의 `customer_db.customers` 테이블을 사용한다. `mysql2`, `class-validator`, `class-transformer`를 설치한다. 아래 풀은 기본 연결 주소인 `localhost:3306`을 사용하고, 계정 정보는 환경 변수에서 읽는다. [MySQL2 연결 풀](https://sidorares.github.io/node-mysql2/docs/examples/connections/create-pool) · [NestJS 입력 검증](https://docs.nestjs.com/techniques/validation)

## 요청 DTO 검증과 값 바인딩

`/customers/search?lastName=O%27Connor`에서 `lastName`은 클라이언트가 바꿀 수 있다. `ValidationPipe`와 DTO로 문자열 여부, 길이, 공백만 포함하는지 검사한다. 검증을 통과한 값은 `mysql2`의 `execute()`에 별도 인자로 전달한다. `supportBigNumbers`와 `bigNumberStrings`를 사용해 MySQL `BIGINT` ID를 JavaScript 문자열로 반환한다. [MySQL2 준비된 문](https://sidorares.github.io/node-mysql2/docs/documentation/prepared-statements)

```typescript
import { Controller, Get, Inject, Module, Query, ValidationPipe } from '@nestjs/common';
import { IsString, Length, Matches } from 'class-validator';
import { createPool, type Pool, type RowDataPacket } from 'mysql2/promise';

class CustomerSearchDto {
  @IsString()
  @Length(1, 100)
  @Matches(/\S/)
  lastName!: string;
}

@Controller('customers')
class CustomersController {
  constructor(@Inject('CUSTOMER_DB') private readonly db: Pool) {}

  @Get('search')
  async search(@Query(new ValidationPipe()) query: CustomerSearchDto) {
    const [rows] = await this.db.execute<(RowDataPacket & { id: string })[]>(
      'SELECT id FROM customers WHERE last_name = ?',
      [query.lastName],
    );
    return rows.map((row) => row.id);
  }
}

@Module({
  controllers: [CustomersController],
  providers: [{
    provide: 'CUSTOMER_DB',
    useFactory: () => createPool({
      host: 'localhost',
      database: 'customer_db',
      user: process.env.MYSQL_USER,
      password: process.env.MYSQL_PASSWORD,
      multipleStatements: false,
      supportBigNumbers: true,
      bigNumberStrings: true,
    }),
  }],
})
export class CustomersModule {}
```

`CustomersModule`을 애플리케이션의 루트 모듈에서 가져온다. `execute()`는 `?`에 검색값을 바인딩하므로 입력에 작은따옴표, 세미콜론 또는 SQL 주석 표기가 있어도 `WHERE` 조건을 바꾸거나 추가 쿼리를 실행할 수 없다. 저장된 성과 일치하지 않으면 빈 목록을 반환한다. [MySQL 준비된 문](https://dev.mysql.com/doc/refman/8.4/en/prepare.html)

## 동적 정렬과 검색 조건

- 정렬 키는 DTO에서 `@IsIn(['name', 'recent'])`로 검사하고, `name`은 `last_name ASC, id ASC`, `recent`는 `created_at DESC, id DESC`로 매핑한다. SQL에 붙이는 정렬식은 코드에 정의한 값으로 제한한다.
- `LIKE` 부분 검색은 입력에서 `!`, `%`, `_`를 순서대로 `!!`, `!%`, `!_`로 치환한다. 변환한 값 양쪽에 `%`를 붙여 `WHERE last_name LIKE ? ESCAPE '!'`에 바인딩한다. [MySQL `LIKE`](https://dev.mysql.com/doc/refman/8.4/en/string-comparison-functions.html)

`IN` 조회는 검증한 ID 목록의 길이만큼 `?`를 만든다. ID 값은 별도 배열로 전달하고, 빈 목록이면 쿼리 실행 전에 빈 결과를 반환한다.

```typescript
async function findIds(db: Pool, ids: string[]): Promise<string[]> {
  if (ids.length === 0) {
    return [];
  }

  const placeholders = ids.map(() => '?').join(', ');
  const [rows] = await db.execute<(RowDataPacket & { id: string })[]>(
    `SELECT id FROM customers WHERE id IN (${placeholders})`,
    ids,
  );
  return rows.map((row) => row.id);
}
```

## 운영과 검증

- 조회 계정에는 필요한 테이블이나 뷰의 `SELECT` 권한만 부여한다. `multipleStatements`는 `false`로 유지하고 모든 조회 값에 바인딩을 적용한다. [MySQL `GRANT`](https://dev.mysql.com/doc/refman/8.4/en/grant.html)
- MySQL 통합 테스트에서 `O'Connor` 검색은 해당 고객만 반환하고, 일치하지 않는 문자열과 일치하지 않는 주석 표기 포함 문자열은 빈 결과를 반환하는지 확인한다. `lastName`이 없거나 길이를 초과하면 HTTP 400을 반환하는지 확인한다. 허용한 정렬 키마다 결과 순서를 검사하고, `%`와 `_`는 부분 검색에서 일반 문자로 처리되는지 확인한다.
