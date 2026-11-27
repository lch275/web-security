import { Inject, Injectable } from '@nestjs/common';
import type { Pool, PoolConnection, ResultSetHeader, RowDataPacket } from 'mysql2/promise';

import { CUSTOMER_DB, QUERY_TIMEOUT_MS } from '../database/database.module';
import type { SortKey } from './dto/customer-queries.dto';

// NestJS.md: 정렬 키를 코드에 정의한 정렬식으로 매핑한다. SQL에는 이 값만 붙인다.
export const ORDER_BY: Record<SortKey, string> = {
  name: 'last_name ASC, id ASC',
  recent: 'created_at DESC, id DESC',
};

export interface Customer {
  id: string;
  lastName: string;
  createdAt: Date;
}

type IdRow = RowDataPacket & { id: string };
type CustomerRow = RowDataPacket & Customer;
type Executor = Pool | PoolConnection;

const COLUMNS = 'id, last_name AS lastName, created_at AS createdAt';

export function escapeLike(text: string): string {
  return text.replace(/!/g, '!!').replace(/%/g, '!%').replace(/_/g, '!_');
}

@Injectable()
export class CustomersRepository {
  constructor(
    @Inject(CUSTOMER_DB) private readonly db: Pool,
    @Inject(QUERY_TIMEOUT_MS) private readonly timeout: number,
  ) {}

  async ping(): Promise<void> {
    await this.db.execute({ sql: 'SELECT 1', timeout: this.timeout });
  }

  async searchByLastName(lastName: string, sort: SortKey): Promise<string[]> {
    return this.ids('SELECT id FROM customers WHERE last_name = ? ORDER BY ' + ORDER_BY[sort], [lastName]);
  }

  async searchByLastNameContains(keyword: string): Promise<string[]> {
    return this.ids("SELECT id FROM customers WHERE last_name LIKE ? ESCAPE '!' ORDER BY id", [
      `%${escapeLike(keyword)}%`,
    ]);
  }

  async findAllIdsSorted(sort: SortKey): Promise<string[]> {
    return this.ids('SELECT id FROM customers ORDER BY ' + ORDER_BY[sort]);
  }

  // NestJS.md의 findIds: 빈 목록이면 쿼리 실행 전에 빈 결과를 반환한다.
  async findIds(ids: string[]): Promise<string[]> {
    if (ids.length === 0) {
      return [];
    }
    const placeholders = ids.map(() => '?').join(', ');
    return this.ids(`SELECT id FROM customers WHERE id IN (${placeholders}) ORDER BY id`, ids);
  }

  // MySQL 8.0.22+ 준비된 문에서 LIMIT/OFFSET은 정수 문자열로 바인딩한다.
  async list(limit: number, offset: number): Promise<Customer[]> {
    const [rows] = await this.db.execute<CustomerRow[]>(
      { sql: `SELECT ${COLUMNS} FROM customers ORDER BY id LIMIT ? OFFSET ?`, timeout: this.timeout },
      [String(limit), String(offset)],
    );
    return rows.map(toCustomer);
  }

  async findById(id: string, executor: Executor = this.db): Promise<Customer | null> {
    const [rows] = await executor.execute<CustomerRow[]>(
      { sql: `SELECT ${COLUMNS} FROM customers WHERE id = ?`, timeout: this.timeout },
      [id],
    );
    return rows.length ? toCustomer(rows[0]) : null;
  }

  async create(lastName: string, executor: Executor = this.db): Promise<Customer> {
    const [result] = await executor.execute<ResultSetHeader>(
      { sql: 'INSERT INTO customers (last_name) VALUES (?)', timeout: this.timeout },
      [lastName],
    );
    return (await this.findById(String(result.insertId), executor))!;
  }

  async update(id: string, lastName: string): Promise<Customer | null> {
    const [result] = await this.db.execute<ResultSetHeader>(
      { sql: 'UPDATE customers SET last_name = ? WHERE id = ?', timeout: this.timeout },
      [lastName, id],
    );
    return result.affectedRows === 0 ? null : this.findById(id);
  }

  async remove(id: string): Promise<boolean> {
    const [result] = await this.db.execute<ResultSetHeader>(
      { sql: 'DELETE FROM customers WHERE id = ?', timeout: this.timeout },
      [id],
    );
    return result.affectedRows > 0;
  }

  // 하나의 연결에서 트랜잭션으로 처리하고, 실패하면 전체를 롤백한다. 연결은 항상 반환한다.
  async createAll(lastNames: string[]): Promise<Customer[]> {
    const connection = await this.db.getConnection();
    try {
      await connection.beginTransaction();
      const created: Customer[] = [];
      for (const lastName of lastNames) {
        created.push(await this.create(lastName, connection));
      }
      await connection.commit();
      return created;
    } catch (err) {
      await connection.rollback().catch(() => undefined);
      throw err;
    } finally {
      connection.release();
    }
  }

  private async ids(sql: string, values: string[] = []): Promise<string[]> {
    const [rows] = await this.db.execute<IdRow[]>({ sql, timeout: this.timeout }, values);
    return rows.map((row) => row.id);
  }
}

function toCustomer(row: CustomerRow): Customer {
  return { id: row.id, lastName: row.lastName, createdAt: row.createdAt };
}
