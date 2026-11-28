# FastAPI 예제 이미지
#   test    : 테스트 의존성 포함, 통합 테스트 실행 (docker build --target test)
#   runtime : 실행 의존성만 포함 (기본 타깃)
FROM python:3.13.9-slim-bookworm AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
RUN useradd --system --uid 10001 --no-create-home app
COPY requirements.txt constraints.txt ./
RUN pip install -r requirements.txt -c constraints.txt

FROM base AS test
COPY requirements-dev.txt ./
RUN pip install -r requirements-dev.txt -c constraints.txt
COPY pytest.ini ./
COPY app ./app
COPY tests ./tests
USER app
CMD ["python", "-m", "pytest", "-p", "no:cacheprovider"]

FROM base AS runtime
COPY app ./app
USER app
ENV APP_HOST=0.0.0.0 \
    APP_PORT=8084
EXPOSE 8084
CMD ["python", "-m", "app"]
