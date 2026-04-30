"""
JWT Token Utilities

This module handles all JWT token generation and validation for the application.
It provides access tokens (short-lived) and refresh tokens (long-lived) for
authentication flows.

CONFIGURATION:
    JWT settings are loaded from app.core.config.settings:
    - jwt_secret_key: Secret key for signing tokens
    - jwt_algorithm: Algorithm (default: HS256)
    - access_token_expire_minutes: Access token TTL
    - refresh_token_expire_minutes: Refresh token TTL

TOKEN TYPES:
    - access: Short-lived token for API authentication
    - refresh: Long-lived token for obtaining new access tokens

USAGE IN SERVICES:
    from app.core.token import generate_jwt_tokens, validate_jwt_token

    # Generate tokens for a user
    access_token, refresh_token = generate_jwt_tokens(user_id="123")

    # Validate an access token
    payload = validate_jwt_token(token, token_type="access")
    if payload:
        user_id = payload.get("sub")
"""

from datetime import UTC, datetime, timedelta

import jwt

from app.core.config import settings

# =============================================================================
# CONFIGURATION - Modify these values for your project
# =============================================================================
TOKEN_ISSUER = "fastapi-template-backend"
TOKEN_AUDIENCE = "fastapi-template-frontend"

logger = settings.logger


def generate_short_lived_jwt_token(user_id: str) -> str:
    """
    Generate a short-lived access JWT token.

    Args:
        user_id: Unique user identifier (will be stored in 'sub' claim)

    Returns:
        Encoded JWT access token string
    """
    payload = {
        "sub": user_id,  # Subject - user identifier
        "iat": datetime.now(UTC),  # Issued at
        "exp": datetime.now(UTC)
        + timedelta(minutes=settings.access_token_expire_minutes),
        "type": "access",
        "iss": TOKEN_ISSUER,
        "aud": TOKEN_AUDIENCE,
    }

    access_token = jwt.encode(
        payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm
    )

    return access_token


def generate_refresh_jwt_token(user_id: str) -> str:
    """
    Generate a long-lived refresh JWT token.

    Args:
        user_id: Unique user identifier (will be stored in 'sub' claim)

    Returns:
        Encoded JWT refresh token string
    """
    payload = {
        "sub": user_id,  # Subject - user identifier
        "iat": datetime.now(UTC),  # Issued at
        "exp": datetime.now(UTC)
        + timedelta(minutes=settings.refresh_token_expire_minutes),
        "type": "refresh",
        "iss": TOKEN_ISSUER,
        "aud": TOKEN_AUDIENCE,
    }

    refresh_token = jwt.encode(
        payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm
    )

    return refresh_token


def generate_jwt_tokens(user_id: str) -> tuple[str, str]:
    """
    Generate both access and refresh JWT tokens.

    This is the primary function to use when authenticating a user.
    Returns a tuple of (access_token, refresh_token).

    Args:
        user_id: Unique user identifier

    Returns:
        Tuple of (access_token, refresh_token)
    """
    access_token = generate_short_lived_jwt_token(user_id)
    refresh_token = generate_refresh_jwt_token(user_id)

    return access_token, refresh_token


def validate_jwt_token(token: str, token_type: str = "access") -> dict | None:
    """
    Validate and decode a JWT token.

    Verifies the token signature, expiration, issuer, audience, and token type.

    Args:
        token: The JWT token to validate
        token_type: Expected token type ("access" or "refresh")

    Returns:
        Decoded token payload dict if valid, None otherwise
    """
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret_key,
            algorithms=[settings.jwt_algorithm],
            issuer=TOKEN_ISSUER,
            audience=TOKEN_AUDIENCE,
        )

        # Verify token type matches expected
        if payload.get("type") != token_type:
            logger.debug(f"Token type mismatch: expected {token_type}")
            return None

        return payload

    except jwt.ExpiredSignatureError:
        logger.debug("Token has expired")
        return None
    except jwt.InvalidTokenError as e:
        logger.debug(f"Invalid token: {e}")
        return None
    except Exception:
        logger.debug("Token validation failed")
        return None
