ARG BUILD_DATE="unknown"
ARG VCS_REF="unknown"
ARG VERSION="unknown"

FROM --platform=$BUILDPLATFORM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy pom.xml first so dependency layer is only invalidated when dependencies change.
COPY pom.xml .
RUN mvn dependency:go-offline --no-transfer-progress -q

COPY src ./src

# Tests run in the pipeline before this build; skipping avoids a redundant pass
# inside a discarded layer and keeps the build deterministic.
RUN mvn package \
      --no-transfer-progress \
      -DskipTests \
  && cp target/*.jar target/app.jar

FROM eclipse-temurin:17-jre-jammy AS runtime

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

LABEL org.opencontainers.image.title="springboot-app" \
      org.opencontainers.image.description="Spring Boot application — private VNet deployment" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://dev.azure.com/org/project/_git/springboot-app" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Your Organisation"

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      tini \
  && rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 1001 appgroup \
  && useradd --system --uid 1001 \
             --gid appgroup \
             --no-create-home \
             --shell /sbin/nologin \
             appuser

WORKDIR /app

COPY --from=builder --chown=appuser:appgroup /build/target/app.jar app.jar

USER appuser

# UseContainerSupport reads cgroup limits instead of host values.
# ExitOnOutOfMemoryError crashes fast so Kubernetes can restart cleanly.
ENV JAVA_OPTS="\
  -XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -XX:+ExitOnOutOfMemoryError \
  -Djava.security.egd=file:/dev/./urandom \
  -Dspring.profiles.active=prod"

EXPOSE 8080

HEALTHCHECK \
  --interval=30s \
  --timeout=10s \
  --start-period=60s \
  --retries=3 \
  CMD curl --fail --silent --max-time 5 \
      http://localhost:8080/actuator/health \
      | grep -q '"status":"UP"' \
    || exit 1

# tini as PID 1 ensures SIGTERM is forwarded to the JVM and zombies are reaped.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
