"""
Greeting Schemas - Request/Response Models for Greeting API

Pydantic models for greeting-related API requests and responses.

SCHEMA GUIDELINES:
    - Schemas define the API contract (what clients send/receive)
    - Keep them separate from database models (app/model/database/)
    - Use Optional[] for fields that may not be present in responses
    - Use ConfigDict for model configuration (orm_mode replacement)
"""

from datetime import datetime

from pydantic import BaseModel, ConfigDict


class GreetingCreate(BaseModel):
    """Request body for creating a greeting."""

    name: str
    message: str | None = None
    source: str | None = None


class GreetingResponse(BaseModel):
    """Response model for a single greeting."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    message: str
    source: str | None = None
    created_at: datetime


class GreetingListResponse(BaseModel):
    """Response model for a list of greetings."""

    greetings: list[GreetingResponse]
    count: int
