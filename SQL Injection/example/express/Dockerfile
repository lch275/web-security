# Express 예제 이미지
#   test    : 개발 의존성 포함, 통합 테스트 실행 (docker build --target test)
#   runtime : 운영 의존성만 포함한 실행 이미지 (기본 타깃)
FROM node:24.11.1-alpine3.22 AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

FROM deps AS test
RUN npm ci --no-audit --no-fund
COPY src ./src
COPY test ./test
USER node
CMD ["node", "--test", "--test-concurrency=1", "test/**/*.test.js"]

FROM node:24.11.1-alpine3.22 AS runtime
ENV NODE_ENV=production \
    APP_PORT=8083
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
USER node
EXPOSE 8083
# node를 PID 1로 실행하여 SIGTERM을 직접 받아 정상 종료한다.
CMD ["node", "src/server.js"]
