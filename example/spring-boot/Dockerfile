# Spring Boot 예제 이미지
#   build   : 의존성 다운로드와 패키징(테스트 제외)
#   test    : 통합 테스트 실행 (docker build --target test)
#   runtime : JRE + 실행 JAR (기본 타깃)
FROM maven:3.9.11-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q -DskipTests package

# surefire는 JUnit 프로바이더를 테스트 실행 시점에 내려받으므로 오프라인(-o) 모드를 사용하지 않는다.
FROM build AS test
CMD ["mvn", "-B", "test"]

FROM eclipse-temurin:21.0.8_9-jre-noble AS runtime
RUN groupadd --system app && useradd --system --gid app --no-create-home app
WORKDIR /app
COPY --from=build /app/target/spring-boot-sql-injection-example-1.0.0.jar app.jar
USER app
ENV APP_PORT=8081
EXPOSE 8081
# java를 PID 1로 실행하여 SIGTERM을 직접 받고 graceful shutdown 한다.
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "/app/app.jar"]
