-- 02-seed.sql
-- 데모 DB에만 가상의 테스트 데이터를 넣는다. 실제 개인정보는 사용하지 않는다.
-- 테이블이 비어 있을 때만 삽입하므로 여러 번 적용해도 중복되지 않는다.
-- 테스트 DB({fw}_customer_test_db)는 각 테스트가 자체 데이터를 준비하므로 비워 둔다.

INSERT INTO spring_boot_customer_db.customers (last_name, created_at)
SELECT v.last_name, v.created_at
FROM (
    VALUES
        ROW('Kim', '2026-01-05 09:00:00'),
        ROW('Lee', '2026-01-06 09:00:00'),
        ROW('Park', '2026-01-07 09:00:00'),
        ROW('O''Connor', '2026-01-08 09:00:00'),
        ROW('Smith', '2026-01-09 09:00:00'),
        ROW('Smith', '2026-01-10 09:00:00'),
        ROW('Under_Score', '2026-01-11 09:00:00'),
        ROW('Percent%Sign', '2026-01-12 09:00:00'),
        ROW('Bang!Name', '2026-01-13 09:00:00')
) AS v (last_name, created_at)
WHERE NOT EXISTS (SELECT 1 FROM spring_boot_customer_db.customers);

INSERT INTO nestjs_customer_db.customers (last_name, created_at)
SELECT v.last_name, v.created_at
FROM (
    VALUES
        ROW('Kim', '2026-01-05 09:00:00'),
        ROW('Lee', '2026-01-06 09:00:00'),
        ROW('Park', '2026-01-07 09:00:00'),
        ROW('O''Connor', '2026-01-08 09:00:00'),
        ROW('Smith', '2026-01-09 09:00:00'),
        ROW('Smith', '2026-01-10 09:00:00'),
        ROW('Under_Score', '2026-01-11 09:00:00'),
        ROW('Percent%Sign', '2026-01-12 09:00:00'),
        ROW('Bang!Name', '2026-01-13 09:00:00')
) AS v (last_name, created_at)
WHERE NOT EXISTS (SELECT 1 FROM nestjs_customer_db.customers);

INSERT INTO express_customer_db.customers (last_name, created_at)
SELECT v.last_name, v.created_at
FROM (
    VALUES
        ROW('Kim', '2026-01-05 09:00:00'),
        ROW('Lee', '2026-01-06 09:00:00'),
        ROW('Park', '2026-01-07 09:00:00'),
        ROW('O''Connor', '2026-01-08 09:00:00'),
        ROW('Smith', '2026-01-09 09:00:00'),
        ROW('Smith', '2026-01-10 09:00:00'),
        ROW('Under_Score', '2026-01-11 09:00:00'),
        ROW('Percent%Sign', '2026-01-12 09:00:00'),
        ROW('Bang!Name', '2026-01-13 09:00:00')
) AS v (last_name, created_at)
WHERE NOT EXISTS (SELECT 1 FROM express_customer_db.customers);

INSERT INTO fastapi_customer_db.customers (last_name, created_at)
SELECT v.last_name, v.created_at
FROM (
    VALUES
        ROW('Kim', '2026-01-05 09:00:00'),
        ROW('Lee', '2026-01-06 09:00:00'),
        ROW('Park', '2026-01-07 09:00:00'),
        ROW('O''Connor', '2026-01-08 09:00:00'),
        ROW('Smith', '2026-01-09 09:00:00'),
        ROW('Smith', '2026-01-10 09:00:00'),
        ROW('Under_Score', '2026-01-11 09:00:00'),
        ROW('Percent%Sign', '2026-01-12 09:00:00'),
        ROW('Bang!Name', '2026-01-13 09:00:00')
) AS v (last_name, created_at)
WHERE NOT EXISTS (SELECT 1 FROM fastapi_customer_db.customers);

INSERT INTO django_customer_db.customers (last_name, created_at)
SELECT v.last_name, v.created_at
FROM (
    VALUES
        ROW('Kim', '2026-01-05 09:00:00'),
        ROW('Lee', '2026-01-06 09:00:00'),
        ROW('Park', '2026-01-07 09:00:00'),
        ROW('O''Connor', '2026-01-08 09:00:00'),
        ROW('Smith', '2026-01-09 09:00:00'),
        ROW('Smith', '2026-01-10 09:00:00'),
        ROW('Under_Score', '2026-01-11 09:00:00'),
        ROW('Percent%Sign', '2026-01-12 09:00:00'),
        ROW('Bang!Name', '2026-01-13 09:00:00')
) AS v (last_name, created_at)
WHERE NOT EXISTS (SELECT 1 FROM django_customer_db.customers);
