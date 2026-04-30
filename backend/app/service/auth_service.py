"""
Auth Service - Authentication Business Logic

This service handles authentication operations including:
- Password-based authentication (demo implementation)
- JWT token generation and refresh
- User authorization via Bearer tokens

SERVICE PATTERN:
    AuthService orchestrates authentication flows using:
    - DAOFactory: For database operations (user lookup, etc.)
    - Token utilities: For JWT generation/validation

    Routes should inject AuthService via Depends(), not use tokens directly.

DEMO IMPLEMENTATION:
    This template includes a simulated password check for demonstration.
    In a real application, you would:
    1. Create a User model with hashed passwords
    2. Use a UserDAO to fetch users
    3. Use bcrypt/argon2 for password hashing

USAGE IN ROUTES:
    @router.post("/login")
    async def login(
        request: LoginRequest,
        auth_service: AuthService = Depends(AuthService),
    ):
        return await auth_service.authenticate(request.username, request.password)
"""

from typing import Any

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.config import settings
from app.core.token import (
    generate_jwt_tokens,
    generate_short_lived_jwt_token,
    validate_jwt_token,
)
from app.dao.factory import DAOFactory

logger = settings.logger

# Create security scheme for Bearer token authentication
security = HTTPBearer()


class AuthService:
    """
    Authentication service for handling user auth flows.

    This service demonstrates:
    1. Password-based authentication (simulated)
    2. JWT token generation
    3. Token refresh flow
    4. Bearer token validation for protected routes
    """

    def __init__(self, dao_factory: DAOFactory = Depends(DAOFactory)):
        """
        Initialize auth service with dependencies.

        Args:
            dao_factory: Factory for creating DAOs (injected by FastAPI)
        """
        self.dao_factory = dao_factory
        # In a real app: self.user_dao = dao_factory.get_user_dao()

    async def authenticate(
        self, username: str, password: str
    ) -> dict[str, Any]:
        """
        Authenticate a user with username and password.

        DEMO IMPLEMENTATION: This uses a simulated password check.
        In production, replace with actual user lookup and password verification.

        Args:
            username: User's username or email
            password: User's password

        Returns:
            Dictionary containing access_token, refresh_token, and expires_in

        Raises:
            HTTPException: 401 if authentication fails
        """
        # =================================================================
        # DEMO: Simulated authentication
        # Replace this with actual user lookup and password verification:
        #
        #   user = await self.user_dao.get_by_username(username)
        #   if not user or not verify_password(password, user.hashed_password):
        #       raise HTTPException(status_code=401, detail="Invalid credentials")
        #   user_id = str(user.id)
        # =================================================================

        # Demo: Accept any non-empty credentials and use username as user_id
        if not username or not password:
            raise HTTPException(status_code=401, detail="Invalid credentials")

        # In demo mode, we use a hash of the username as a fake user_id
        # This makes the demo predictable but not tied to a real database
        user_id = str(hash(username) % 1000000)

        logger.info(f"User authenticated: {username} (demo mode)")

        # Generate JWT tokens
        access_token, refresh_token = generate_jwt_tokens(user_id=user_id)

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "expires_in": settings.access_token_expire_minutes * 60,  # seconds
        }

    async def refresh_token(self, refresh_token: str) -> dict[str, Any]:
        """
        Refresh an access token using a valid refresh token.

        Args:
            refresh_token: The refresh token

        Returns:
            Dictionary containing new access_token and expires_in

        Raises:
            HTTPException: 401 if refresh token is invalid or expired
        """
        # Validate the refresh token
        payload = validate_jwt_token(refresh_token, token_type="refresh")

        if not payload:
            raise HTTPException(
                status_code=401, detail="Invalid or expired refresh token"
            )

        # Extract user_id from the refresh token
        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token payload")

        # Generate only a new access token
        access_token = generate_short_lived_jwt_token(user_id=user_id)

        logger.debug(f"Refreshed access token for user: {user_id}")

        return {
            "access_token": access_token,
            "expires_in": settings.access_token_expire_minutes * 60,  # seconds
        }

    async def authorize_user(
        self, credentials: HTTPAuthorizationCredentials
    ) -> dict[str, Any]:
        """
        Validate Bearer token and return authorized user info.

        Used as a dependency in protected routes to verify the user is authenticated.

        Args:
            credentials: HTTPAuthorizationCredentials from FastAPI security

        Returns:
            Dictionary with user_id from the token

        Raises:
            HTTPException: 401 if token is invalid or expired
        """
        token = credentials.credentials
        payload = validate_jwt_token(token, token_type="access")

        if not payload:
            raise HTTPException(status_code=401, detail="Invalid or expired token")

        user_id = payload.get("sub")
        if not user_id:
            raise HTTPException(status_code=401, detail="Invalid token payload")

        # In a real app, you might fetch full user details here:
        #   user = await self.user_dao.get(int(user_id))
        #   return UserBase(id=user.id, email=user.email, ...)

        return {"user_id": user_id}


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    auth_service: AuthService = Depends(AuthService),
) -> dict[str, Any]:
    """
    FastAPI dependency for protected routes.

    Validates the Bearer token and returns the current user info.

    Usage:
        @router.get("/protected")
        async def protected_route(
            current_user: dict = Depends(get_current_user),
        ):
            user_id = current_user["user_id"]
            return {"message": f"Hello user {user_id}"}

    Args:
        credentials: Bearer token from Authorization header
        auth_service: Injected AuthService instance

    Returns:
        Dictionary with user information (at minimum, user_id)

    Raises:
        HTTPException: 401 if not authenticated
    """
    return await auth_service.authorize_user(credentials)
