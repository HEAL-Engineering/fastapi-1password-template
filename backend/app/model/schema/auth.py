"""
Auth Schemas - Request/Response Models for Authentication

Pydantic models for auth-related API requests and responses.

SCHEMA NAMING CONVENTIONS:
    - *Request: Input from client
    - *Response: Output to client
    - Use descriptive names (LoginRequest, not AuthRequest)

VALIDATION:
    Pydantic v2 field_validator for custom validation.
    Keep validation simple - complex business logic belongs in Services.
"""

from pydantic import BaseModel


class LoginRequest(BaseModel):
    """Request body for username/password login."""

    username: str
    password: str


class RefreshTokenRequest(BaseModel):
    """Request body for token refresh."""

    refresh_token: str


class TokenResponse(BaseModel):
    """Response containing access and refresh tokens."""

    access_token: str
    refresh_token: str
    expires_in: int  # seconds until access token expiration


class AccessTokenResponse(BaseModel):
    """Response containing only an access token (for refresh)."""

    access_token: str
    expires_in: int  # seconds until expiration
