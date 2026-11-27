"""Django 설정. 접속 정보와 비밀값은 환경변수에서 읽는다."""

import os
import sys
from pathlib import Path

from django.core.management.utils import get_random_secret_key

BASE_DIR = Path(__file__).resolve().parent.parent

DEBUG = os.environ.get("DJANGO_DEBUG", "false").lower() == "true"
# 세션/쿠키를 사용하지 않는 예제 API이므로 미설정 시 기동마다 임의 키를 생성한다.
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY") or get_random_secret_key()
ALLOWED_HOSTS = [h.strip() for h in os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",") if h.strip()]

INSTALLED_APPS = [
    "customers",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
    "customers.middleware.RequestLogMiddleware",
    "customers.middleware.DatabaseErrorMiddleware",
]

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"
APPEND_SLASH = False
DATA_UPLOAD_MAX_MEMORY_SIZE = 16 * 1024

_running_tests = len(sys.argv) > 1 and sys.argv[1] == "test"

# Django.md: ENGINE=django.db.backends.mysql. DB 이름은 프레임워크별로 분리한다.
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.mysql",
        "NAME": os.environ.get("DB_NAME") or ("django_customer_test_db" if _running_tests else "django_customer_db"),
        "USER": os.environ.get("DB_USERNAME", "django_app"),
        "PASSWORD": os.environ.get("DB_PASSWORD", ""),
        "HOST": os.environ.get("DB_HOST", "localhost"),
        "PORT": os.environ.get("DB_PORT", "3306"),
        # Django는 MySQL용 연결 풀을 제공하지 않는다. 스레드별 영속 연결을 재사용하고 사용 전 상태를 확인한다.
        "CONN_MAX_AGE": int(os.environ.get("DB_CONN_MAX_AGE", "60")),
        "CONN_HEALTH_CHECKS": True,
        "OPTIONS": {
            "charset": "utf8mb4",
            "connect_timeout": int(os.environ.get("DB_CONNECT_TIMEOUT_SECONDS", "5")),
            "read_timeout": 30,
            "write_timeout": 30,
            # SELECT 실행 시간 제한(ms). 서버 설정의 STRICT 모드도 세션에서 보장한다.
            "init_command": "SET SESSION sql_mode = CONCAT(@@sql_mode, ',STRICT_TRANS_TABLES'), "
            f"SESSION MAX_EXECUTION_TIME = {int(os.environ.get('DB_QUERY_TIMEOUT_MS', '10000'))}",
        },
    }
}

if not DATABASES["default"]["PASSWORD"]:
    raise RuntimeError("DB_PASSWORD 환경변수가 필요합니다.")

# customers 테이블은 example/dbms/mysql 초기화 스크립트가 관리한다.
TEST_RUNNER = "config.test_runner.ExistingDatabaseTestRunner"

USE_TZ = True
TIME_ZONE = "UTC"
LANGUAGE_CODE = "ko-kr"
USE_I18N = True

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"plain": {"format": "%(asctime)s %(levelname)s %(name)s - %(message)s"}},
    "handlers": {"console": {"class": "logging.StreamHandler", "formatter": "plain"}},
    "root": {"handlers": ["console"], "level": "INFO"},
    "loggers": {
        # 기본 요청 로그는 쿼리 문자열을 포함하므로 줄이고 RequestLogMiddleware를 사용한다.
        "django.server": {"level": "WARNING"},
        "django.request": {"level": "ERROR"},
    },
}
