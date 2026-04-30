"""
Greeting Service - Business Logic Layer

Services contain ALL business logic and orchestrate between DAOs (database)
and Providers (external APIs). They are the "brain" of your application.

SERVICE RESPONSIBILITIES:
- Implement business rules and validation
- Orchestrate multiple DAO operations
- Coordinate with external providers
- Handle transaction boundaries (commit/rollback)
- Transform data between layers

SERVICES SHOULD NOT:
- Make HTTP requests directly (use Providers)
- Execute SQL directly (use DAOs)
- Handle HTTP status codes (that's the API layer)
- Know about FastAPI Request/Response objects

DEPENDENCY INJECTION:
    Services receive DAOFactory via FastAPI's Depends().
    Routes inject Services via Depends(ServiceClass).

    Route → Service → DAOFactory → DAOs
                   → Providers

USAGE IN ROUTES:
    @router.get("/greeting/{name}")
    async def get_greeting(
        name: str,
        service: GreetingService = Depends(GreetingService),
    ):
        return await service.get_or_create_greeting(name)
"""

from fastapi import Depends

from app.core.config import settings
from app.dao.factory import DAOFactory
from app.model.database.greeting import Greeting
from app.provider.greeting_provider import GreetingProvider

logger = settings.logger


class GreetingService:
    """
    Business logic for greeting operations.

    This service demonstrates:
    1. DAO injection via DAOFactory
    2. Provider usage for external calls
    3. Orchestrating multiple operations
    4. Business rule implementation
    """

    def __init__(self, dao_factory: DAOFactory = Depends(DAOFactory)):
        """
        Initialize service with dependencies.

        Args:
            dao_factory: Factory for creating DAOs (injected by FastAPI)
        """
        self.dao_factory = dao_factory
        self.greeting_dao = dao_factory.get_greeting_dao()
        self.provider = GreetingProvider()

    async def get_greeting(self, greeting_id: int) -> Greeting | None:
        """
        Get a greeting by ID.

        Simple passthrough to DAO - demonstrates basic service method.

        Args:
            greeting_id: The greeting ID

        Returns:
            Greeting if found, None otherwise
        """
        return await self.greeting_dao.get(greeting_id)

    async def get_or_create_greeting(self, name: str) -> Greeting:
        """
        Get existing greeting for name, or create a new one.

        Demonstrates business logic that combines multiple operations:
        1. Check if greeting exists (DAO)
        2. If not, fetch greeting from external service (Provider)
        3. Create new greeting record (DAO)

        Args:
            name: Name to greet

        Returns:
            Existing or newly created Greeting
        """
        # Check if we already have a greeting for this name
        existing = await self.greeting_dao.get_by_name(name)
        if existing:
            logger.info(f"Found existing greeting for {name}")
            return existing

        # Get greeting message from external provider
        logger.info(f"Creating new greeting for {name}")
        message = await self.provider.fetch_greeting(name)

        # Create and return new greeting
        greeting = await self.greeting_dao.create(
            name=name,
            message=message,
            source="greeting_provider",
        )

        return greeting

    async def create_greeting(
        self,
        name: str,
        message: str | None = None,
        source: str | None = None,
    ) -> Greeting:
        """
        Create a new greeting with optional custom message.

        If no message provided, fetches one from the external provider.

        Args:
            name: Name to greet
            message: Optional custom message
            source: Optional source identifier

        Returns:
            Created Greeting

        Raises:
            ValueError: If name validation fails
        """
        # Business rule: Validate name via external service
        is_valid = await self.provider.validate_name(name)
        if not is_valid:
            raise ValueError(f"Invalid name: {name}")

        # Get message from provider if not provided
        if not message:
            message = await self.provider.fetch_greeting(name)

        # Create the greeting
        greeting = await self.greeting_dao.create(
            name=name,
            message=message,
            source=source or "api",
        )

        logger.info(f"Created greeting {greeting.id} for {name}")
        return greeting

    async def get_recent_greetings(self, limit: int = 10) -> list[Greeting]:
        """
        Get the most recent greetings.

        Args:
            limit: Maximum number of greetings to return

        Returns:
            List of recent Greeting instances
        """
        return await self.greeting_dao.get_recent(limit=limit)

    async def delete_greeting(self, greeting_id: int) -> bool:
        """
        Delete a greeting by ID.

        Args:
            greeting_id: The greeting ID to delete

        Returns:
            True if deleted, False if not found
        """
        result = await self.greeting_dao.delete(greeting_id)
        if result:
            logger.info(f"Deleted greeting {greeting_id}")
        return result
