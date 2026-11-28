// 실제 MySQL(express_customer_test_db)을 사용하는 통합 테스트
import assert from 'node:assert/strict';
import { after, before, beforeEach, describe, test } from 'node:test';

import { createPool } from 'mysql2/promise';
import request from 'supertest';

import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';
import { createDb } from '../src/db.js';
import { createCustomerRepository } from '../src/customers/repository.js';

const config = loadConfig({ DB_NAME: 'express_customer_test_db', ...process.env });
if (!config.db.database.endsWith('_test_db')) {
  throw new Error(`테스트는 *_test_db 에서만 실행합니다. 현재 DB_NAME=${config.db.database}`);
}

const silentLogger = { info() {}, warn() {}, error() {} };
const FIXTURES = [
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

let db;
let app;
let ids; // last_name -> [id...]
let insertedIds; // 삽입 순서(= created_at 오름차순)

async function resetFixtures() {
  await db.pool.query('DELETE FROM customers');
  ids = {};
  insertedIds = [];
  for (const [lastName, createdAt] of FIXTURES) {
    const [result] = await db.pool.execute(
      'INSERT INTO customers (last_name, created_at) VALUES (?, ?)',
      [lastName, createdAt],
    );
    (ids[lastName] ??= []).push(String(result.insertId));
    insertedIds.push(String(result.insertId));
  }
}

async function countRows() {
  const [rows] = await db.pool.query('SELECT COUNT(*) AS n FROM customers');
  return Number(rows[0].n);
}

before(async () => {
  db = createDb(config.db);
  app = createApp(db, silentLogger);
});

beforeEach(resetFixtures);

after(async () => {
  await db.pool.query('DELETE FROM customers');
  await db.pool.end();
});

describe('값 바인딩: GET /customers/search', () => {
  test("O'Connor는 해당 고객만 반환한다", async () => {
    const res = await request(app).get('/customers/search').query({ lastName: "O'Connor" });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, ids["O'Connor"]);
  });

  test('저장되지 않은 성은 빈 목록을 반환한다', async () => {
    const res = await request(app).get('/customers/search').query({ lastName: 'Nobody' });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, []);
  });

  test('SQL Injection 페이로드는 값으로 비교되어 빈 결과를 반환하고 테이블은 유지된다', async () => {
    for (const payload of INJECTION_PAYLOADS) {
      const res = await request(app).get('/customers/search').query({ lastName: payload });
      assert.equal(res.status, 200, payload);
      assert.deepEqual(res.body, [], payload);
    }
    assert.equal(await countRows(), FIXTURES.length);
  });

  test('BIGINT ID는 문자열로 반환한다', async () => {
    const res = await request(app).get('/customers/search').query({ lastName: 'Kim' });
    assert.equal(typeof res.body[0], 'string');
  });

  test('허용된 정렬 키마다 지정한 순서로 반환한다', async () => {
    const [older, newer] = ids.Smith;
    const byName = await request(app).get('/customers/search').query({ lastName: 'Smith', sort: 'name' });
    const byRecent = await request(app).get('/customers/search').query({ lastName: 'Smith', sort: 'recent' });
    assert.deepEqual(byName.body, [older, newer]);
    assert.deepEqual(byRecent.body, [newer, older]);
  });

  test('누락, 빈 문자열, 공백, 길이 초과, 중복 파라미터, 미등록 정렬 키는 400이다', async () => {
    const cases = [
      '/customers/search',
      '/customers/search?lastName=',
      '/customers/search?lastName=%20%20',
      `/customers/search?lastName=${'a'.repeat(101)}`,
      '/customers/search?lastName=Kim&lastName=Lee',
      '/customers/search?lastName=Kim&sort=last_name',
      '/customers/search?lastName=Kim&sort=name&sort=recent',
    ];
    for (const url of cases) {
      const res = await request(app).get(url);
      assert.equal(res.status, 400, url);
      assert.ok(res.body.error, url);
    }
  });

  test('100자는 허용한다(코드 포인트 기준)', async () => {
    const res = await request(app).get('/customers/search').query({ lastName: '가'.repeat(100) });
    assert.equal(res.status, 200);
  });
});

describe('허용 목록 정렬: GET /customers/sorted', () => {
  test('name, recent 정렬', async () => {
    const byName = await request(app).get('/customers/sorted?sort=name');
    assert.deepEqual(byName.body, [
      ...ids['Bang!Name'], ...ids.Kim, ...ids["O'Connor"], ...ids['Percent%Sign'], ...ids.PercentXSign,
      ...ids.Smith, ...ids.Under_Score, ...ids.UnderXScore,
    ]);
    const byRecent = await request(app).get('/customers/sorted?sort=recent');
    assert.deepEqual(byRecent.body, [...insertedIds].reverse());
  });

  test('누락 또는 미등록 정렬 키는 400이다', async () => {
    for (const url of ['/customers/sorted', '/customers/sorted?sort=id;DROP TABLE customers', '/customers/sorted?sort=__proto__']) {
      assert.equal((await request(app).get(url)).status, 400, url);
    }
  });
});

describe('LIKE 이스케이프: GET /customers/contains', () => {
  test('%, _, ! 는 일반 문자로 검색한다', async () => {
    const cases = [
      ['r_S', ids.Under_Score],
      ['_', ids.Under_Score],
      ['t%S', ids['Percent%Sign']],
      ['%', ids['Percent%Sign']],
      ['g!N', ids['Bang!Name']],
      ['mit', ids.Smith],
    ];
    for (const [keyword, expected] of cases) {
      const res = await request(app).get('/customers/contains').query({ keyword });
      assert.equal(res.status, 200, keyword);
      assert.deepEqual(res.body, expected, keyword);
    }
  });

  test('누락은 400이다', async () => {
    assert.equal((await request(app).get('/customers/contains')).status, 400);
  });
});

describe('IN 조회: GET /customers/by-ids', () => {
  test('검증한 ID 목록으로 조회한다', async () => {
    const wanted = [ids.Kim[0], ids["O'Connor"][0]];
    const res = await request(app).get('/customers/by-ids').query({ ids: wanted.join(',') });
    assert.deepEqual(res.body, [...wanted].sort((a, b) => Number(a) - Number(b)));
  });

  test('빈 목록은 빈 결과를 반환한다', async () => {
    const res = await request(app).get('/customers/by-ids?ids=');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, []);
  });

  test('정수가 아닌 ID는 400이다', async () => {
    for (const url of ['/customers/by-ids', '/customers/by-ids?ids=1,abc', '/customers/by-ids?ids=1%20OR%201%3D1', '/customers/by-ids?ids=0']) {
      assert.equal((await request(app).get(url)).status, 400, url);
    }
  });
});

describe('CRUD', () => {
  test('생성, 단건 조회, 목록, 수정, 삭제', async () => {
    const created = await request(app).post('/customers').send({ lastName: '  Tester  ' });
    assert.equal(created.status, 201);
    assert.equal(created.body.lastName, 'Tester');
    assert.ok(created.body.createdAt);
    const { id } = created.body;

    assert.equal((await request(app).get(`/customers/${id}`)).body.lastName, 'Tester');

    const list = await request(app).get('/customers?limit=2&offset=0');
    assert.equal(list.status, 200);
    assert.equal(list.body.length, 2);

    const updated = await request(app).put(`/customers/${id}`).send({ lastName: "D'Angelo" });
    assert.equal(updated.status, 200);
    assert.equal(updated.body.lastName, "D'Angelo");

    assert.equal((await request(app).delete(`/customers/${id}`)).status, 204);
    assert.equal((await request(app).get(`/customers/${id}`)).status, 404);
    assert.equal((await request(app).delete(`/customers/${id}`)).status, 404);
    assert.equal((await request(app).put(`/customers/${id}`).send({ lastName: 'X' })).status, 404);
  });

  test('잘못된 입력은 400이다', async () => {
    assert.equal((await request(app).post('/customers').send({ lastName: '' })).status, 400);
    assert.equal((await request(app).post('/customers').send({ lastName: ['a'] })).status, 400);
    assert.equal((await request(app).post('/customers').set('Content-Type', 'application/json').send('{bad')).status, 400);
    assert.equal((await request(app).get('/customers/abc')).status, 400);
    assert.equal((await request(app).get('/customers?limit=1000')).status, 400);
  });
});

describe('트랜잭션', () => {
  test('POST /customers/batch 는 모든 행을 커밋한다', async () => {
    const res = await request(app).post('/customers/batch').send({ lastNames: ['Batch-A', 'Batch-B'] });
    assert.equal(res.status, 201);
    assert.deepEqual(res.body.map((c) => c.lastName), ['Batch-A', 'Batch-B']);
    assert.equal(await countRows(), FIXTURES.length + 2);
  });

  test('중간에 DB 오류가 나면 앞선 INSERT도 롤백한다', async () => {
    const repository = createCustomerRepository(db);
    await assert.rejects(
      repository.createAll(['Rollback-A', 'x'.repeat(101)]),
      (err) => err.code === 'ER_DATA_TOO_LONG',
    );
    const [rows] = await db.pool.execute('SELECT COUNT(*) AS n FROM customers WHERE last_name = ?', ['Rollback-A']);
    assert.equal(Number(rows[0].n), 0);
    assert.equal(await countRows(), FIXTURES.length);
  });

  test('배치 입력 검증 실패는 400이며 아무것도 저장하지 않는다', async () => {
    const res = await request(app).post('/customers/batch').send({ lastNames: ['Ok', ''] });
    assert.equal(res.status, 400);
    assert.equal(await countRows(), FIXTURES.length);
  });
});

describe('최소 권한', () => {
  test('애플리케이션 계정은 DDL을 실행할 수 없다', async () => {
    await assert.rejects(db.pool.query('DROP TABLE customers'), (err) => err.code === 'ER_TABLEACCESS_DENIED_ERROR');
    await assert.rejects(db.pool.query('CREATE TABLE injected (id INT)'), (err) => err.code === 'ER_TABLEACCESS_DENIED_ERROR');
  });

  test('SELECT 전용 계정은 INSERT 할 수 없다', { skip: !process.env.DB_READER_PASSWORD && 'DB_READER_PASSWORD 미설정' }, async () => {
    const reader = createPool({
      host: config.db.host,
      port: config.db.port,
      database: config.db.database,
      user: process.env.DB_READER_USERNAME || 'express_reader',
      password: process.env.DB_READER_PASSWORD,
    });
    try {
      const [rows] = await reader.query('SELECT COUNT(*) AS n FROM customers');
      assert.equal(Number(rows[0].n), FIXTURES.length);
      await assert.rejects(
        reader.execute('INSERT INTO customers (last_name) VALUES (?)', ['Denied']),
        (err) => err.code === 'ER_TABLEACCESS_DENIED_ERROR',
      );
    } finally {
      await reader.end();
    }
  });
});

describe('데이터베이스 장애', () => {
  test('DB에 연결할 수 없으면 503을 반환한다', async () => {
    const broken = createDb({ ...config.db, host: '127.0.0.1', port: 1, connectTimeoutMs: 1000 });
    const brokenApp = createApp(broken, silentLogger);
    try {
      assert.equal((await request(brokenApp).get('/health')).status, 503);
      const res = await request(brokenApp).get('/customers/search?lastName=Kim');
      assert.equal(res.status, 503);
      assert.deepEqual(Object.keys(res.body), ['error']);
    } finally {
      await broken.pool.end();
    }
  });

  test('정상 연결에서 /health 는 UP 이다', async () => {
    const res = await request(app).get('/health');
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { status: 'UP' });
  });
});
