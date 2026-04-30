"""
Application Configuration

This module centralizes all application settings using Pydantic BaseSettings.
Environment variables are automatically loaded from .env files and the system environment.

CONFIGURATION GUIDE:
1. Required variables have no default value - the app won't start without them
2. Optional variables have default values or are typed as `str | None`
3. Sensitive values (passwords, secrets) should ONLY come from 1Password vaults

To add new environment variables:
1. Add the field to the Settings class below
2. Add the variable to your 1Password vault
3. Re-run `task env:generate` to update your .env files
"""

import logging
from typing import Any
from urllib.parse import quote_plus

from pydantic import ConfigDict
from pydantic_settings import BaseSettings
from python_sentry_logger_wrapper import get_logger


# =============================================================================
# CONFIGURATION - Modify these values for your project
# =============================================================================
DEFAULT_APP_NAME = "FastAPI Template"
DEFAULT_APP_VERSION = "0.1.0"
# =============================================================================


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables.

    Environment variables are case-insensitive (DB_HOST, db_host, Db_Host all work).
    Values are loaded from (in order of precedence):
    1. Environment variables
    2. .env file
    3. Default values defined here
    """

    # -------------------------------------------------------------------------
    # API Settings
    # -------------------------------------------------------------------------
    app_name: str = DEFAULT_APP_NAME
    app_version: str = DEFAULT_APP_VERSION

    # -------------------------------------------------------------------------
    # Environment Settings
    # -------------------------------------------------------------------------
    environment: str = "development"
    log_level: str = "info"

    # -------------------------------------------------------------------------
    # JWT Authentication Settings
    # Used for generating and validating access/refresh tokens
    # -------------------------------------------------------------------------
    jwt_secret_key: str  # Required - generate with: openssl rand -hex 32
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 1440  # 24 hours
    refresh_token_expire_minutes: int = 43200  # 30 days

    # -------------------------------------------------------------------------
    # Database Settings
    # Individual components allow flexible configuration across environments
    # -------------------------------------------------------------------------
    db_host: str
    db_port: int = 5432
    db_user: str
    db_password: str
    db_name: str

    @property
    def database_url(self) -> str:
        """
        Construct async PostgreSQL URL from individual components.

        Uses the psycopg async driver for SQLAlchemy 2.0+.
        Password is URL-encoded to handle special characters.
        """
        user = quote_plus(self.db_user)
        password = quote_plus(self.db_password)
        return f"postgresql+psycopg://{user}:{password}@{self.db_host}:{self.db_port}/{self.db_name}"

    # -------------------------------------------------------------------------
    # Test Database Settings (optional - for pytest)
    # -------------------------------------------------------------------------
    test_db_host: str | None = None
    test_db_port: int = 5432
    test_db_user: str | None = None
    test_db_password: str | None = None
    test_db_name: str | None = None

    @property
    def test_database_url(self) -> str | None:
        """Construct test database URL if all components are configured."""
        if not all([
            self.test_db_host,
            self.test_db_user,
            self.test_db_password,
            self.test_db_name,
        ]):
            return None
        user = quote_plus(self.test_db_user)
        password = quote_plus(self.test_db_password)
        return f"postgresql+psycopg://{user}:{password}@{self.test_db_host}:{self.test_db_port}/{self.test_db_name}"

    # -------------------------------------------------------------------------
    # Sentry Settings (Optional - for error tracking and monitoring)
    # -------------------------------------------------------------------------
    sentry_dsn: str | None = None
    sentry_environment: str | None = None
    sentry_sample_rate: float = 1.0  # Sample all traces by default
    sentry_send_pii: bool = False  # Never send PII by default
    sentry_breadcrumbs_level: str | None = None
    sentry_log_level: str | None = None

    # -------------------------------------------------------------------------
    # Logger (initialized after settings are loaded)
    # -------------------------------------------------------------------------
    logger: Any | None = None

    # -------------------------------------------------------------------------
    # Pydantic Configuration
    # -------------------------------------------------------------------------
    model_config = ConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,  # Allow UPPER_CASE env vars to map to lower_case fields
        extra="ignore",  # Ignore unknown environment variables
    )


# Create singleton instance - imported throughout the application
settings = Settings()

# Initialize logger with Sentry integration
log_level_map = {
    "debug": logging.DEBUG,
    "info": logging.INFO,
    "warning": logging.WARNING,
    "error": logging.ERROR,
}

log_level = log_level_map.get(settings.log_level.lower(), logging.INFO)
sentry_log_level = (
    log_level_map.get(settings.sentry_log_level.lower(), logging.INFO)
    if settings.sentry_log_level
    else logging.INFO
)
sentry_breadcrumbs_level = (
    log_level_map.get(settings.sentry_breadcrumbs_level.lower(), logging.ERROR)
    if settings.sentry_breadcrumbs_level
    else logging.ERROR
)

settings.logger = get_logger(
    service_name=settings.app_name,
    log_level=log_level,
    sentry_dsn=settings.sentry_dsn,
    sentry_breadcrumbs_level=sentry_breadcrumbs_level,
    sentry_log_level=sentry_log_level,
    sentry_environment=settings.sentry_environment,
    sentry_sample_rate=settings.sentry_sample_rate,
    sentry_send_pii=settings.sentry_send_pii,
)

# Environment constants for consistent checks across codebase
LOCAL_ENVIRONMENTS = ("local", "development", "dev")
