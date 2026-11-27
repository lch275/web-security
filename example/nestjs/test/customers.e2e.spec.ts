// 실제 MySQL(nestjs_customer_test_db)을 사용하는 통합 테스트
import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { createPool, type Pool, type ResultSetHeader, type RowDataPacket } from 'mysql2/promise';
import request from 'supertest';

process.env.DB_NAME ??= 'nestjs_customer_test_db';
if (!process.env.DB_NAME.endsWith('_test_db')) {
  throw new Error(`테스트는 *_test_db 에서만 실행합니다. 현재 DB_NAME=${process.env.DB_NAME}`);
}

import { AppModule, configureApp } from '../src/app.module';
import { CustomersRepository } from '../src/customers/customers.repository';
import { CUSTOMER_DB, createCustomerPool } from '../src/database/database.module';

const FIXTURES: [string, string][] = [
  ["O'Connor", '2026-01-01 10:00:00'],
  ['Kim', '2026-01-02 10:00:00'],
  ['Smith', '2026-01-03 10:00:00'],
  ['Smith', '2026-01-04 10:00:00'],
  ['Under_Score', '2026-01-05 10:00:00'],
  ['UnderXScore', '2026-01-06 10:00:00'],
  ['Percent%Sign', '2026-01-07 10:00:00'],
  ['PercentXSign', '2026-01-08 10:00:00'],
  ['Bang!Name', '2026-01-09 10:00:00'],
];
const INJECTION_PAYLOADS = [
  "' OR '1'='1",
  "O'Connor' OR '1'='1",
  "x'; DROP TABLE customers; --",
  "O'Connor' -- ",
  "O'Connor'#",
  "O'Connor'/* comment */",
  "' UNION SELECT id FROM customers -- ",
];

async function createTestApp(pool?: Pool): Promise<INestApplication> {
  let builder = Test.createTestingModule({ imports: [AppModule] });
  if (pool) {
    builder = builder.overrideProvider(CUSTOMER_DB).useValue(pool);
  }
  const moduleRef = await builder.compile();
  moduleRef.useLogger(false);
  const app = configureApp(moduleRef.createNestApplication({ logger: false }));
  await app.init();
  return app;
}

describe('NestJS customers (MySQL 통합)', () => {
  let app: INestApplication;
  let db: Pool;
  let ids: Record<string, string[]>;
  let insertedIds: string[];

  const countRows = async (): Promise<number> => {
    const [rows] = await db.query<RowDataPacket[]>('SELECT COUNT(*) AS n FROM customers');
    return Number(rows[0].n);
  };

  beforeAll(async () => {
    db = createCustomerPool();
    app = await createTestApp();
  });

  beforeEach(async () => {
    await db.query('DELETE FROM customers');
    ids = {};
    insertedIds = [];
    for (const [lastName, createdAt] of FIXTURES) {
      const [result] = await db.execute<ResultSetHeader>(
        'INSERT INTO customers (last_name, created_at) VALUES (?, ?)',
        [lastName, createdAt],
      );
      (ids[lastName] ??= []).push(String(result.insertId));
      insertedIds.push(String(result.insertId));
    }
  });

  afterAll(async () => {
    await db.query('DELETE FROM customers');
    await db.end();
    await app.close(); // onApplicationShutdown 에서 앱 풀을 닫는다
  });

  describe('값 바인딩: GET /customers/search', () => {
    it("O'Connor는 해당 고객만 반환한다", async () => {
      const res = await request(app.getHttpServer()).get('/customers/search').query({ lastName: "O'Connor" });
      expect(res.status).toBe(200);
      expect(res.body).toEqual(ids["O'Connor"]);
      expect(typeof res.body[0]).toBe('string');
    });

    it('저장되지 않은 성은 빈 목록을 반환한다', async () => {
      const res = await request(app.getHttpServer()).get('/customers/search').query({ lastName: 'Nobody' });
      expect(res.body).toEqual([]);
    });

    it.each(INJECTION_PAYLOADS)('페이로드 %p 는 값으로 비교되어 빈 결과를 반환한다', async (payload) => {
      const res = await request(app.getHttpServer()).get('/customers/search').query({ lastName: payload });
      expect(res.status).toBe(200);
      expect(res.body).toEqual([]);
      expect(await countRows()).toBe(FIXTURES.length);
    });

    it('허용된 정렬 키마다 지정한 순서로 반환한다', async () => {
      const [older, newer] = ids.Smith;
      const server = app.getHttpServer();
      expect((await request(server).get('/customers/search?lastName=Smith&sort=name')).body).toEqual([older, newer]);
      expect((await request(server).get('/customers/search?lastName=Smith&sort=recent')).body).toEqual([newer, older]);
    });

    it.each([
      '/customers/search',
      '/customers/search?lastName=',
      '/customers/search?lastName=%20%20',
      `/customers/search?lastName=${'a'.repeat(101)}`,
      '/customers/search?lastName=Kim&lastName=Lee',
      '/customers/search?lastName=Kim&sort=last_name',
      '/customers/search?lastName=Kim&unknown=1',
    ])('%s 는 400이다', async (url) => {
      expect((await request(app.getHttpServer()).get(url)).status).toBe(400);
    });
  });

  describe('허용 목록 정렬과 LIKE, IN', () => {
    it('GET /customers/sorted', async () => {
      const server = app.getHttpServer();
      expect((await request(server).get('/customers/sorted?sort=name')).body).toEqual([
        ...ids['Bang!Name'], ...ids.Kim, ...ids["O'Connor"], ...ids['Percent%Sign'], ...ids.PercentXSign,
        ...ids.Smith, ...ids.Under_Score, ...ids.UnderXScore,
      ]);
      expect((await request(server).get('/customers/sorted?sort=recent')).body).toEqual([...insertedIds].reverse());
      expect((await request(server).get('/customers/sorted')).status).toBe(400);
      expect((await request(server).get('/customers/sorted?sort=id%3BDROP')).status).toBe(400);
    });

    it.each([
      ['r_S', 'Under_Score'],
      ['_', 'Under_Score'],
      ['t%S', 'Percent%Sign'],
      ['%', 'Percent%Sign'],
      ['g!N', 'Bang!Name'],
      ['mit', 'Smith'],
    ])('contains keyword=%p 는 %s 만 찾는다', async (keyword, name) => {
      const res = await request(app.getHttpServer()).get('/customers/contains').query({ keyword });
      expect(res.body).toEqual(ids[name]);
    });

    it('GET /customers/by-ids', async () => {
      const server = app.getHttpServer();
      const wanted = [ids.Kim[0], ids["O'Connor"][0]];
      expect((await request(server).get(`/customers/by-ids?ids=${wanted.join(',')}`)).body).toEqual(
        [...wanted].sort((a, b) => Number(a) - Number(b)),
      );
      expect((await request(server).get('/customers/by-ids?ids=')).body).toEqual([]);
      for (const url of ['/customers/by-ids', '/customers/by-ids?ids=1,abc', '/customers/by-ids?ids=1%20OR%201%3D1']) {
        expect((await request(server).get(url)).status).toBe(400);
      }
    });
  });

  describe('CRUD', () => {
    it('생성, 단건 조회, 목록, 수정, 삭제', async () => {
      const server = app.getHttpServer();
      const created = await request(server).post('/customers').send({ lastName: '  Tester  ' });
      expect(created.status).toBe(201);
      expect(created.body.lastName).toBe('Tester');
      const { id } = created.body;

      expect((await request(server).get(`/customers/${id}`)).body.lastName).toBe('Tester');
      expect((await request(server).get('/customers?limit=2')).body).toHaveLength(2);

      const updated = await request(server).put(`/customers/${id}`).send({ lastName: "D'Angelo" });
      expect(updated.body.lastName).toBe("D'Angelo");

      expect((await request(server).delete(`/customers/${id}`)).status).toBe(204);
      expect((await request(server).get(`/customers/${id}`)).status).toBe(404);
      expect((await request(server).delete(`/customers/${id}`)).status).toBe(404);
    });

    it('잘못된 입력은 400이다', async () => {
      const server = app.getHttpServer();
      expect((await request(server).post('/customers').send({ lastName: '   ' })).status).toBe(400);
      expect((await request(server).post('/customers').send({ lastName: ['a'] })).status).toBe(400);
      expect((await request(server).get('/customers/abc')).status).toBe(400);
      expect((await request(server).get('/customers?limit=1000')).status).toBe(400);
    });
  });

  describe('트랜잭션', () => {
    it('POST /customers/batch 는 모든 행을 커밋한다', async () => {
      const res = await request(app.getHttpServer()).post('/customers/batch').send({ lastNames: ['Batch-A', 'Batch-B'] });
      expect(res.status).toBe(201);
      expect(res.body.map((c: { lastName: string }) => c.lastName)).toEqual(['Batch-A', 'Batch-B']);
      expect(await countRows()).toBe(FIXTURES.length + 2);
    });

    it('중간에 DB 오류가 나면 앞선 INSERT도 롤백한다', async () => {
      const repository = app.get(CustomersRepository);
      await expect(repository.createAll(['Rollback-A', 'x'.repeat(101)])).rejects.toMatchObject({
        code: 'ER_DATA_TOO_LONG',
      });
      const [rows] = await db.execute<RowDataPacket[]>('SELECT COUNT(*) AS n FROM customers WHERE last_name = ?', [
        'Rollback-A',
      ]);
      expect(Number(rows[0].n)).toBe(0);
    });

    it('배치 입력 검증 실패는 400이며 아무것도 저장하지 않는다', async () => {
      const res = await request(app.getHttpServer()).post('/customers/batch').send({ lastNames: ['Ok', ''] });
      expect(res.status).toBe(400);
      expect(await countRows()).toBe(FIXTURES.length);
    });
  });

  describe('최소 권한', () => {
    it('애플리케이션 계정은 DDL을 실행할 수 없다', async () => {
      await expect(db.query('DROP TABLE customers')).rejects.toMatchObject({ code: 'ER_TABLEACCESS_DENIED_ERROR' });
    });

    (process.env.DB_READER_PASSWORD ? it : it.skip)('SELECT 전용 계정은 INSERT 할 수 없다', async () => {
      const reader = createPool({
        host: process.env.DB_HOST || 'localhost',
        port: Number(process.env.DB_PORT || 3306),
        database: process.env.DB_NAME,
        user: process.env.DB_READER_USERNAME || 'nestjs_reader',
        password: process.env.DB_READER_PASSWORD,
      });
      try {
        await reader.query('SELECT COUNT(*) FROM customers');
        await expect(reader.execute('INSERT INTO customers (last_name) VALUES (?)', ['Denied'])).rejects.toMatchObject({
          code: 'ER_TABLEACCESS_DENIED_ERROR',
        });
      } finally {
        await reader.end();
      }
    });
  });

  describe('데이터베이스 장애', () => {
    it('DB에 연결할 수 없으면 503을 반환한다', async () => {
      const broken = createPool({
        host: '127.0.0.1',
        port: 1,
        user: 'nobody',
        password: 'nothing',
        connectTimeout: 1000,
      });
      const brokenApp = await createTestApp(broken);
      try {
        expect((await request(brokenApp.getHttpServer()).get('/health')).status).toBe(503);
        const res = await request(brokenApp.getHttpServer()).get('/customers/search?lastName=Kim');
        expect(res.status).toBe(503);
        expect(JSON.stringify(res.body)).not.toContain('ECONNREFUSED');
      } finally {
        await brokenApp.close();
      }
    });

    it('정상 연결에서 /health 는 UP 이다', async () => {
      expect((await request(app.getHttpServer()).get('/health')).body).toEqual({ status: 'UP' });
    });
  });
});
