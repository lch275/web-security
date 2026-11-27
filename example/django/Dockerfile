# Django 예제 이미지
#   build   : mysqlclient C 확장 빌드 (Linux용 wheel이 배포되지 않음)
#   test    : 통합 테스트 실행 (docker build --target test)
#   runtime : gunicorn 실행 이미지 (기본 타깃)
FROM python:3.13.9-slim-bookworm AS build
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc pkg-config default-libmysqlclient-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY requirements.txt constraints.txt ./
RUN pip wheel --wheel-dir /wheels -r requirements.txt -c constraints.txt

FROM python:3.13.9-slim-bookworm AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DJANGO_SETTINGS_MODULE=config.settings
# mysqlclient 실행에 필요한 클라이언트 라이브러리(MariaDB Connector/C, caching_sha2_password 플러그인 포함)
RUN apt-get update \
    && apt-get install -y --no-install-recommends libmariadb3 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --no-create-home app
WORKDIR /app
COPY --from=build /wheels /wheels
RUN pip install --no-index --find-links /wheels /wheels/*.whl && rm -rf /wheels
COPY manage.py ./
COPY config ./config
COPY customers ./customers

FROM base AS test
USER app
CMD ["python", "manage.py", "test", "-v", "2"]

FROM base AS runtime
USER app
ENV APP_PORT=8085
EXPOSE 8085
# gunicorn은 SIGTERM을 받으면 처리 중인 요청을 마친 뒤 종료한다(graceful-timeout).
CMD ["sh", "-c", "exec gunicorn config.wsgi --bind 0.0.0.0:${APP_PORT} --workers 2 --threads 4 --timeout 30 --graceful-timeout 10"]
