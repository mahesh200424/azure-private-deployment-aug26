# =============================================================
# Dockerfile — Multi-stage build for a Spring Boot application
#
# Stage 1 (builder): compile + test with Maven
# Stage 2 (runtime): minimal JRE image, non-root user
# =============================================================

# ── Build arguments (passed in from the pipeline) ────────────
ARG BUILD_DATE="unknown"
ARG VCS_REF="unknown"
ARG VERSION="unknown"

# =============================================================
# STAGE 1 — builder
# Full Maven + JDK image; produces the executable JAR.
# Nothing from this stage leaks into the final image.
# =============================================================
FROM --platform=$BUILDPLATFORM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# ── Copy dependency manifest first for better layer caching ──
# Docker will only re-download dependencies when pom.xml changes.
COPY pom.xml .
RUN mvn dependency:go-offline --no-transfer-progress -q

# ── Copy source and build ─────────────────────────────────────
COPY src ./src

# Unit tests run in the pipeline workspace before this image build, so their
# JUnit XML is available to Azure DevOps. Keep this image build deterministic
# and avoid running a second hidden test pass inside a discarded layer.
RUN mvn package \
      --no-transfer-progress \
      -DskipTests \
  && echo "Build successful" \
  # Rename the fat JAR to a predictable name, stripping the version suffix
  && cp target/*.jar target/app.jar

# =============================================================
# STAGE 2 — runtime
# Minimal Alpine JRE image; only the JAR and its runtime are
# included.  The Maven cache, sources, and build tools are left
# behind in the builder stage.
# =============================================================
FROM eclipse-temurin:17-jre-jammy AS runtime

# ── Re-declare build args so they are available in this stage ─
ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

# ── OCI / Docker image labels ────────────────────────────────
LABEL org.opencontainers.image.title="springboot-app" \
      org.opencontainers.image.description="Spring Boot application — private VNet deployment" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://dev.azure.com/org/project/_git/springboot-app" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Your Organisation"

# ── Install only what the runtime needs ──────────────────────
# curl  → used by the HEALTHCHECK command
# tini  → init process: reaps zombie processes and forwards signals
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl \
      tini \
  && rm -rf /var/lib/apt/lists/*

# ── Create a dedicated non-root user and group ───────────────
RUN groupadd --system --gid 1001 appgroup \
  && useradd --system --uid 1001 \
             --gid appgroup \
             --no-create-home \
             --shell /sbin/nologin \
             appuser

# ── Application directory ────────────────────────────────────
WORKDIR /app

# ── Copy the fat JAR from the builder stage ──────────────────
COPY --from=builder --chown=appuser:appgroup /build/target/app.jar app.jar

# ── Switch to non-root user ───────────────────────────────────
USER appuser

# ── JVM tuning flags ─────────────────────────────────────────
# UseContainerSupport  — reads cgroup CPU/memory limits instead of host values
# MaxRAMPercentage     — use up to 75 % of the container memory limit for the heap
# ExitOnOutOfMemoryError — crash fast rather than thrash; let k8s restart the pod
ENV JAVA_OPTS="\
  -XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -XX:+ExitOnOutOfMemoryError \
  -Djava.security.egd=file:/dev/./urandom \
  -Dspring.profiles.active=prod"

# ── Expose application port ───────────────────────────────────
EXPOSE 8080

# ── Health check ─────────────────────────────────────────────
# Spring Boot Actuator endpoint must be enabled and accessible.
# Adjust the path if you use a custom management port or context-path.
# Tune the timings to match your application's startup time.
HEALTHCHECK \
  --interval=30s \
  --timeout=10s \
  --start-period=60s \
  --retries=3 \
  CMD curl --fail --silent --max-time 5 \
      http://localhost:8080/actuator/health \
      | grep -q '"status":"UP"' \
    || exit 1

# ── Entry point ───────────────────────────────────────────────
# tini wraps the JVM so signals (SIGTERM) are handled properly
# and zombie processes are reaped.
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["sh", "-c", "java $JAVA_OPTS -jar /app/app.jar"]
