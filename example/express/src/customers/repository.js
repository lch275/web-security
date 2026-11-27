// 모든 요청값은 execute()의 별도 배열로 전달한다. SQL 본문에는 코드에 정의한 문자열만 붙인다.

// Express.md: 정렬 키를 고정 정렬식에 매핑하는 허용 목록
export const sortOrders = new Map([
  ['name', 'last_name ASC, id ASC'],
  ['recent', 'created_at DESC, id DESC'],
]);

const COLUMNS = 'id, last_name AS lastName, created_at AS createdAt';

export function escapeLike(text) {
  return text.replace(/!/g, '!!').replace(/%/g, '!%').replace(/_/g, '!_');
}

export function createCustomerRepository({ pool, queryTimeoutMs }) {
  const run = async (executor, sql, values = []) => {
    const [rows] = await executor.execute({ sql, timeout: queryTimeoutMs }, values);
    return rows;
  };
  const ids = (rows) => rows.map((row) => row.id);

  return {
    async ping() {
      await run(pool, 'SELECT 1');
    },

    // orderBy는 sortOrders의 값만 받는다(라우트에서 검증).
    async searchByLastName(lastName, orderBy) {
      return ids(await run(pool, 'SELECT id FROM customers WHERE last_name = ? ORDER BY ' + orderBy, [lastName]));
    },

    async searchByLastNameContains(keyword) {
      return ids(await run(
        pool,
        "SELECT id FROM customers WHERE last_name LIKE ? ESCAPE '!' ORDER BY id",
        [`%${escapeLike(keyword)}%`],
      ));
    },

    async findAllIdsSorted(orderBy) {
      return ids(await run(pool, 'SELECT id FROM customers ORDER BY ' + orderBy));
    },

    // 검증한 ID 목록의 길이만큼 ?를 만들고, 빈 목록은 쿼리 없이 반환한다.
    async findIds(idList) {
      if (idList.length === 0) {
        return [];
      }
      const placeholders = idList.map(() => '?').join(', ');
      return ids(await run(pool, `SELECT id FROM customers WHERE id IN (${placeholders}) ORDER BY id`, idList));
    },

    // MySQL 8.0.22+ 준비된 문에서 LIMIT/OFFSET은 정수 문자열로 바인딩해야 한다.
    async list(limit, offset) {
      return run(pool, `SELECT ${COLUMNS} FROM customers ORDER BY id LIMIT ? OFFSET ?`, [String(limit), String(offset)]);
    },

    async findById(id, executor = pool) {
      const rows = await run(executor, `SELECT ${COLUMNS} FROM customers WHERE id = ?`, [id]);
      return rows[0] ?? null;
    },

    async create(lastName, executor = pool) {
      const result = await run(executor, 'INSERT INTO customers (last_name) VALUES (?)', [lastName]);
      return this.findById(String(result.insertId), executor);
    },

    async update(id, lastName) {
      const result = await run(pool, 'UPDATE customers SET last_name = ? WHERE id = ?', [lastName, id]);
      return result.affectedRows === 0 ? null : this.findById(id);
    },

    async remove(id) {
      const result = await run(pool, 'DELETE FROM customers WHERE id = ?', [id]);
      return result.affectedRows > 0;
    },

    // 하나의 연결에서 트랜잭션으로 처리한다. 중간에 실패하면 앞선 INSERT도 롤백한다.
    async createAll(lastNames) {
      const connection = await pool.getConnection();
      try {
        await connection.beginTransaction();
        const created = [];
        for (const lastName of lastNames) {
          created.push(await this.create(lastName, connection));
        }
        await connection.commit();
        return created;
      } catch (err) {
        await connection.rollback().catch(() => {});
        throw err;
      } finally {
        connection.release();
      }
    },
  };
}
