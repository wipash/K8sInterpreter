# syntax=docker/dockerfile:1
# Keep this syntax directive! It's used to enable Docker BuildKit

################################
# Builder STAGE
################################
FROM ghcr.io/astral-sh/uv:python3.13-trixie-slim AS builder

ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy
ENV UV_PYTHON_DOWNLOADS=0

WORKDIR /app

# Install dependencies into a virtual environment
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=requirements.txt,target=requirements.txt \
    uv venv /app/.venv && \
    uv pip install --python /app/.venv/bin/python -r requirements.txt

# Copy application code
COPY main.py .

################################
# Production STAGE
################################
FROM python:3.13-slim-trixie AS production

# Install runtime dependencies
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      curl \
      util-linux; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/*

# Create non-root user (used when nsenter is not needed)
RUN groupadd -r -g 1000 appuser && useradd -r -u 1000 -g appuser appuser

WORKDIR /app

# Copy the application from the builder
COPY --from=builder /app /app

# Place executables in the environment at the front of the path
ENV PATH="/app/.venv/bin:$PATH"

# Create working directory
RUN mkdir -p /mnt/data && chown -R appuser:appuser /mnt/data /app

# Note: We run as root by default because nsenter requires elevated privileges
# to enter another container's namespace. Security is controlled via:
# - shareProcessNamespace: true (required for nsenter)
# - securityContext.capabilities.add: ["SYS_PTRACE", "SYS_ADMIN", "SYS_CHROOT"]
# - allowPrivilegeEscalation: true

# Environment defaults
ENV WORKING_DIR=/mnt/data \
    LANGUAGE=python \
    SIDECAR_PORT=8080 \
    MAX_EXECUTION_TIME=120 \
    PYTHONUNBUFFERED=1

# Expose sidecar port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run sidecar
CMD ["python", "main.py"]
