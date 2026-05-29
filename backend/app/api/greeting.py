"""
Greeting API Routes

Example routes demonstrating the full 4-layer pattern:
    Route → Service → Provider/DAO

This module shows:
- Protected routes using get_current_user dependency
- Public routes (no auth required)
- Returning Pydantic response models
- Injecting services via Depends()
"""

from fastapi import APIRouter, Depends, HTTPException

from app.core.config import settings
from app.schemas.greeting import (
    GreetingCreate,
    GreetingListResponse,
    GreetingResponse,
)
from app.service.auth_service import get_current_user
from app.service.greeting_service import GreetingService

logger = settings.logger
router = APIRouter()


@router.get(
    "/{name}",
    response_model=GreetingResponse,
    responses={404: {"description": "Greeting not found"}},
)
async def get_or_create_greeting(
    name: str,
    greeting_service: GreetingService = Depends(GreetingService),
) -> GreetingResponse:
    """
    Get or create a greeting for the given name.

    This is a PUBLIC endpoint (no authentication required).
    Demonstrates the Service → Provider → DAO flow.

    If a greeting exists for this name, returns it.
    Otherwise, fetches a greeting from the provider and creates a new record.
    """
    try:
        greeting = await greeting_service.get_or_create_greeting(name)
        return GreetingResponse.model_validate(greeting)
    except Exception as e:
        logger.error(f"Failed to get/create greeting for {name}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error") from e


@router.post(
    "/",
    response_model=GreetingResponse,
    responses={
        400: {"description": "Invalid name"},
        401: {"description": "Not authenticated"},
    },
)
async def create_greeting(
    request: GreetingCreate,
    greeting_service: GreetingService = Depends(GreetingService),
    current_user: dict = Depends(get_current_user),
) -> GreetingResponse:
    """
    Create a new greeting (protected endpoint).

    Requires Bearer token authentication.
    Demonstrates a protected route with request body validation.
    """
    try:
        greeting = await greeting_service.create_greeting(
            name=request.name,
            message=request.message,
            source=request.source,
        )
        return GreetingResponse.model_validate(greeting)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    except Exception as e:
        logger.error("Failed to create greeting", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error") from e


@router.get(
    "/",
    response_model=GreetingListResponse,
)
async def list_recent_greetings(
    limit: int = 10,
    greeting_service: GreetingService = Depends(GreetingService),
) -> GreetingListResponse:
    """
    Get recent greetings.

    Public endpoint showing query parameter usage.
    """
    try:
        greetings = await greeting_service.get_recent_greetings(limit=limit)
        return GreetingListResponse(
            greetings=[GreetingResponse.model_validate(g) for g in greetings],
            count=len(greetings),
        )
    except Exception as e:
        logger.error("Failed to list greetings", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error") from e


@router.delete(
    "/{greeting_id}",
    responses={
        404: {"description": "Greeting not found"},
        401: {"description": "Not authenticated"},
    },
)
async def delete_greeting(
    greeting_id: int,
    greeting_service: GreetingService = Depends(GreetingService),
    current_user: dict = Depends(get_current_user),
) -> dict:
    """
    Delete a greeting by ID (protected endpoint).

    Requires Bearer token authentication.
    """
    try:
        deleted = await greeting_service.delete_greeting(greeting_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Greeting not found")
        return {"status": "deleted", "id": greeting_id}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete greeting {greeting_id}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error") from e
