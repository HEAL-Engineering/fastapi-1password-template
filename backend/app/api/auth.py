"""
Auth API Routes

Authentication endpoints for login, token refresh, etc.

ROUTE PATTERN:
    Routes inject Services via Depends(), call service methods,
    and return Pydantic response models.

    Route → Service → DAOFactory/Providers
"""

from fastapi import APIRouter, Depends, HTTPException

from app.core.config import settings
from app.model.schema.auth import (
    AccessTokenResponse,
    LoginRequest,
    RefreshTokenRequest,
    TokenResponse,
)
from app.service.auth_service import AuthService

logger = settings.logger
router = APIRouter()


@router.post(
    "/login",
    response_model=TokenResponse,
    responses={401: {"description": "Invalid credentials"}},
)
async def login(
    request: LoginRequest,
    auth_service: AuthService = Depends(AuthService),
) -> TokenResponse:
    """
    Authenticate with username and password.

    Returns access and refresh tokens for API authentication.

    NOTE: This is a demo implementation. In production, replace with
    actual user lookup and password verification.
    """
    try:
        result = await auth_service.authenticate(request.username, request.password)
        return TokenResponse(**result)
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Login failed", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error") from e


@router.post(
    "/refresh",
    response_model=AccessTokenResponse,
    responses={401: {"description": "Invalid or expired refresh token"}},
)
async def refresh_token(
    request: RefreshTokenRequest,
    auth_service: AuthService = Depends(AuthService),
) -> AccessTokenResponse:
    """
    Refresh an access token using a valid refresh token.

    Returns a new access token. The refresh token remains valid.
    """
    try:
        result = await auth_service.refresh_token(request.refresh_token)
        return AccessTokenResponse(**result)
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Token refresh failed", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error") from e
