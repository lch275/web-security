# NestJS 예제 이미지
#   test    : 개발 의존성 포함, 통합 테스트 실행 (docker build --target test)
#   runtime : 컴파일 결과(dist)와 운영 의존성만 포함 (기본 타깃)
FROM node:24.11.1-alpine3.22 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json tsconfig.build.json nest-cli.json ./
COPY src ./src
RUN npm run build

FROM build AS test
COPY test ./test
USER node
CMD ["npx", "jest", "--runInBand"]

FROM node:24.11.1-alpine3.22 AS prod-deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

FROM node:24.11.1-alpine3.22 AS runtime
ENV NODE_ENV=production \
    APP_PORT=8082
WORKDIR /app
COPY --from=prod-deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./
USER node
EXPOSE 8082
CMD ["node", "dist/main.js"]
