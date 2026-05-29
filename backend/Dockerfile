# Development and Test Dockerfile
# Using Amazon ECR Public to avoid Docker Hub rate limits
FROM public.ecr.aws/docker/library/python:3.14-slim

# Set working directory
WORKDIR /app

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install system dependencies and uv (pinned version for reproducibility)
ENV UV_VERSION=0.9.6
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    git \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh \
    && cp /root/.local/bin/uv /usr/local/bin/uv \
    && cp /root/.local/bin/uvx /usr/local/bin/uvx

# Copy dependency files first for better caching
COPY pyproject.toml uv.lock ./

# Sync dependencies from lockfile (including dev dependencies)
RUN uv sync --frozen --group dev

# Copy application code
COPY . .

# Create a non-root user to run the app
RUN useradd -m -u 1000 appuser && \
    chown -R appuser:appuser /app

# Create data directory for application use
RUN mkdir -p /app/data && \
    chown -R appuser:appuser /app/data

USER appuser

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the application with hot reload for development
CMD ["uv", "run", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
