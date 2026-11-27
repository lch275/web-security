# Django 예제

[`SQL Injection/Django.md`](../../SQL%20Injection/Django.md)를 실행 가능한 프로젝트로 구현했습니다.

| 항목 | 값 |
| --- | --- |
| 런타임 | Python 3.12 이상 (기준: Docker `python:3.13.9-slim-bookworm`, 호스트 3.15.2에서도 검증) |
| 프레임워크 | Django 5.2.19 (LTS) |
| 드라이버 | mysqlclient 2.3.2 (`django.db.backends.mysql`) |
| WSGI 서버 | gunicorn 27.0.1 (컨테이너), 호스트에서는 `manage.py runserver` |
| 테스트 | Django 기본 테스트 러너 (`manage.py test`) |
| 포트 | 8085 |
| DB | `django_customer_db` (실행) / `django_customer_test_db` (테스트), 계정 `django_app` |

## 구조

```
django/
├── manage.py
├── requirements.txt / requirements-dev.txt / constraints.txt
├── config/
│   ├── settings.py      # DATABASES(환경변수), CONN_MAX_AGE, 타임아웃, 로깅
│   ├── urls.py / wsgi.py
│   └── test_runner.py   # 기존 테스트 DB 사용 (DB 생성/삭제 권한 불필요)
├── customers/
│   ├── models.py        # 문서의 Customer 모델 (managed = False)
│   ├── forms.py         # 문서의 CustomerSearchForm, 정렬 ChoiceField, ids 검증
│   ├── views.py         # JsonResponse 뷰, 400/404
│   ├── queries.py       # ORM 조회, cursor.execute(sql, params), raw(), atomic 트랜잭션
│   ├── middleware.py    # 요청 로그, DB 오류 → 503/500
│   └── tests/           # 실제 MySQL 통합 테스트 19건 (subTest 포함)
└── Dockerfile           # build(mysqlclient 컴파일) / test / runtime
```

## 실행

```bash
example/scripts/mysql.sh up
example/scripts/example.sh build django     # .venv + pip install + manage.py check
example/scripts/example.sh test django
example/scripts/example.sh run django       # http://127.0.0.1:8085 (runserver --noreload)
example/scripts/example.sh docker-run django   # gunicorn
```

직접 실행:

```bash
cd example/django
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt -c constraints.txt
export DB_HOST=127.0.0.1 DB_PORT=3306 DB_NAME=django_customer_db DB_USERNAME=django_app DB_PASSWORD='<DJANGO_DB_PASSWORD>'
python manage.py runserver 127.0.0.1:8085
```

Linux에서 mysqlclient를 소스로 빌드하려면 `pkg-config`, `gcc`, `default-libmysqlclient-dev`(또는 `libmysqlclient-dev`)가 필요합니다. Windows에는 wheel이 배포됩니다.

| 환경변수 | 기본값 | 설명 |
| --- | --- | --- |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD` | `localhost`, `3306`, `django_customer_db`(테스트 시 `django_customer_test_db`), `django_app`, (필수) | |
| `DB_CONN_MAX_AGE` | `60` | 영속 연결 유지 시간(초) |
| `DB_CONNECT_TIMEOUT_SECONDS` | `5` | |
| `DB_QUERY_TIMEOUT_MS` | `10000` | `init_command`의 `MAX_EXECUTION_TIME` |
| `DJANGO_SECRET_KEY` | 실행마다 임의 생성 | 세션/서명을 쓰지 않는 예제라 고정 키가 필요 없음 |
| `DJANGO_ALLOWED_HOSTS` | `localhost,127.0.0.1` | |
| `DJANGO_DEBUG` | `false` | |

## API와 예상 결과

파라미터와 JSON 필드는 문서대로 `last_name`이고 검증 실패는 400 `{"errors": ...}`입니다.

```bash
curl -G http://127.0.0.1:8085/customers/search --data-urlencode "last_name=O'Connor"   # [4]
curl "http://127.0.0.1:8085/customers/search?last_name="                               # 400 {"errors":{"last_name":[...]}}
curl -G http://127.0.0.1:8085/customers/contains --data-urlencode "keyword=_"          # [7] (Under_Score)
```

## 설계 메모와 문서와의 차이

- **`created_at`**: 문서 모델은 `DateTimeField()`입니다. ORM으로 INSERT하면 `NULL`이 들어가 실패하므로 `db_default=Now()`를 추가했습니다(테이블 정의는 동일).
- **`contains`의 대소문자**: 문서는 "대소문자 비교는 MySQL 컬럼의 콜레이션에 따른다"고 설명합니다. 그러나 Django 5.2 MySQL 백엔드는 `contains`를 `LIKE BINARY`로 변환하므로 `utf8mb4_0900_ai_ci` 콜레이션에서도 **대소문자를 구분**합니다. 콜레이션을 따르는 것은 `icontains`입니다. 테스트 `test_contains_is_case_sensitive_on_mysql`로 확인합니다.
- **연결 풀**: Django는 MySQL용 연결 풀을 제공하지 않습니다(5.1+의 풀은 PostgreSQL 전용). `CONN_MAX_AGE`로 스레드별 영속 연결을 재사용하고 `CONN_HEALTH_CHECKS`로 끊긴 연결을 교체합니다.
- **테스트 DB**: 앱 계정에는 `CREATE DATABASE` 권한이 없으므로 `config/test_runner.py`가 Django의 테스트 DB 생성을 건너뛰고 `django_customer_test_db`를 그대로 사용합니다. 각 테스트는 `TestCase` 트랜잭션 롤백으로 격리됩니다. DDL 권한 테스트는 암묵적 커밋을 피하기 위해 별도 연결에서 실행합니다.
- **CSRF**: 쿠키/세션 인증이 없는 JSON API 예제이므로 `CsrfViewMiddleware`를 사용하지 않습니다. 쿠키 기반 인증을 추가하면 CSRF 보호를 함께 적용해야 합니다.
