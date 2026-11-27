# Express에서 MySQL을 사용할 때의 SQL Injection 방어

## MySQL 예제 환경

[Java와 Spring 예제](Spring.md#mysql-예제-환경)와 같은 MySQL 8.4의 `customer_db.customers` table을 사용한다. 예제는 Express 5와 `mysql2`를 설치한 Node.js 프로젝트의 ES module에서 실행한다. connection pool은 `localhost:3306`을 사용하고, 계정 정보는 environment variable에서 읽는다. [MySQL2 Connection Pool](https://sidorares.github.io/node-mysql2/docs/examples/connections/create-pool)

## Input Validation과 Parameter Binding

`req.query.lastName`은 클라이언트가 바꿀 수 있고, query parser에 따라 배열이나 객체가 될 수 있다. 단일 문자열인지 확인한 뒤 길이와 공백을 검사한다. 검증을 통과한 값은 `mysql2`의 `execute()`에 별도 배열로 전달한다. `supportBigNumbers`와 `bigNumberStrings`를 사용해 MySQL `BIGINT` ID를 JavaScript 문자열로 반환한다. [Express Request API](https://expressjs.com/en/api/request/) · [MySQL2 Prepared Statements](https://sidorares.github.io/node-mysql2/docs/documentation/prepared-statements)

```javascript
import express from 'express';
import { createPool } from 'mysql2/promise';

const app = express();
const db = createPool({
  host: 'localhost',
  database: 'customer_db',
  user: process.env.MYSQL_USER,
  password: process.env.MYSQL_PASSWORD,
  multipleStatements: false,
  supportBigNumbers: true,
  bigNumberStrings: true,
});

app.get('/customers/search', async (req, res) => {
  const { lastName } = req.query;
  if (typeof lastName !== 'string' || !lastName.trim() || [...lastName].length > 100) {
    return res.status(400).json({ error: '성을 1자 이상 100자 이하로 입력해야 합니다.' });
  }

  const [rows] = await db.execute(
    'SELECT id FROM customers WHERE last_name = ?',
    [lastName],
  );
  return res.json(rows.map((row) => row.id));
});

app.listen(3000);
```

`/customers/search?lastName=O%27Connor`에서 `O'Connor`는 성을 비교하는 값으로 사용된다. 세미콜론이나 SQL 주석 표기가 들어와도 값 전체가 `?`에 바인딩되므로 기존 조회 조건이 유지된다. 일치하는 성이 없으면 빈 목록을 반환한다. [MySQL Prepared Statements](https://dev.mysql.com/doc/refman/8.4/en/prepare.html)

## Dynamic Sorting과 검색 조건

`ORDER BY`에 사용할 column과 정렬 방향은 코드에서 정한다. 아래는 route handler에서 요청 키를 고정 정렬식에 매핑하는 예제다. 허용된 키를 확인한 후에만 해당 정렬식을 SQL에 넣는다.

```javascript
const sortOrders = new Map([
  ['name', 'last_name ASC, id ASC'],
  ['recent', 'created_at DESC, id DESC'],
]);

app.get('/customers/sorted', async (req, res) => {
  const orderBy = sortOrders.get(req.query.sort);
  if (!orderBy) {
    return res.status(400).json({ error: '지원하지 않는 정렬 기준입니다.' });
  }

  const [rows] = await db.execute('SELECT id FROM customers ORDER BY ' + orderBy);
  return res.json(rows.map((row) => row.id));
});
```

`IN` 조회는 검증한 ID 목록의 길이만큼 `?`를 만들고 값은 별도 배열로 전달한다. 빈 목록은 빈 결과로 처리한다. `LIKE`에서 `%`와 `_`를 일반 문자로 검색할 때는 `!`, `%`, `_`를 순서대로 `!!`, `!%`, `!_`로 치환한다. 그 값 양쪽에 `%`를 붙여 `LIKE ? ESCAPE '!'`에 바인딩한다. [MySQL `LIKE`](https://dev.mysql.com/doc/refman/8.4/en/string-comparison-functions.html)

## 운영과 테스트

- 조회 계정의 권한을 필요한 table이나 view의 `SELECT`로 제한한다. `multipleStatements`는 `false`로 유지하고 단일 SQL 문의 값도 바인딩한다. [MySQL `GRANT`](https://dev.mysql.com/doc/refman/8.4/en/grant.html)
- MySQL integration test에서 `O'Connor`는 해당 고객만 반환하고, 일치하지 않는 주석 표기 포함 문자열은 빈 결과를 반환하는지 확인한다. 누락, 빈 문자열, 중복 parameter는 HTTP 400을 반환하는지 확인한다. 허용한 sort key마다 결과 순서를 확인하고 `%`와 `_`는 일반 문자로 검색되는지 확인한다.
