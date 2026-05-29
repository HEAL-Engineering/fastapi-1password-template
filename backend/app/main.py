"""
FastAPI Application Entry Point

This module creates and configures the FastAPI application.
Routes are organized into routers and included with prefixes.

ROUTER ORGANIZATION:
    /health     - Health check (no auth)
    /auth       - Authentication (login, refresh)
    /greeting   - Greeting example endpoints
"""

from fastapi import FastAPI

from app.api.auth import router as auth_router
from app.api.greeting import router as greeting_router
from app.core.config import settings

logger = settings.logger
logger.info(
    f"Starting {settings.app_name} in {settings.environment} environment "
    f"with log level: {settings.log_level}"
)

# =============================================================================
# CONFIGURATION - Modify these values for your project
# =============================================================================
API_PREFIX = "/api/v1"

app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)


@app.get("/health")
async def health_check() -> dict:
    """Health check endpoint for Docker and monitoring."""
    return {
        "status": "healthy",
        "service": settings.app_name,
        "version": settings.app_version,
    }


@app.get("/")
async def root() -> dict:
    """Root endpoint with API information."""
    return {
        "message": settings.app_name,
        "version": settings.app_version,
        "docs": "/docs",
        "health": "/health",
    }


# Include routers with API prefix
app.include_router(auth_router, prefix=f"{API_PREFIX}/auth")
app.include_router(greeting_router, prefix=f"{API_PREFIX}/greeting")
