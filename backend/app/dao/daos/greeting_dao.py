"""
Greeting Data Access Object

This DAO handles all database operations for the Greeting model.
It extends BaseDAO for standard CRUD and adds domain-specific queries.

DAO GUIDELINES:
- DAOs should ONLY contain database operations
- Never include business logic (that belongs in Services)
- Never call external APIs (that belongs in Providers)
- Always accept AsyncSession in __init__
- Use type hints for all method signatures

ADDING CUSTOM QUERIES:
1. Define the method with clear parameter and return types
2. Use SQLAlchemy select() for queries
3. Return model instances, lists, or None
4. Document what the query does

EXAMPLE CUSTOM QUERIES SHOWN:
- get_by_name(): Find by exact field match
- get_recent(): Find with ordering and limit
- search_by_message(): Find with LIKE pattern matching
"""

from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.dao.base import BaseDAO
from app.models.greeting import Greeting


class GreetingDAO(BaseDAO[Greeting]):
    """
    Data Access Object for Greeting model.

    Inherits standard CRUD operations from BaseDAO:
    - get(id) -> Greeting | None
    - create(**kwargs) -> Greeting
    - add(**kwargs) -> Greeting (no commit)
    - update(id, **kwargs) -> Greeting | None
    - delete(id) -> bool
    - exists(id) -> bool
    """

    def __init__(self, session: AsyncSession):
        """
        Initialize GreetingDAO with database session.

        Args:
            session: SQLAlchemy async session from DAOFactory
        """
        super().__init__(session, Greeting)

    async def get_by_name(self, name: str) -> Greeting | None:
        """
        Find a greeting by name.

        Args:
            name: The name to search for (exact match)

        Returns:
            Greeting if found, None otherwise
        """
        stmt = select(Greeting).where(Greeting.name == name)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def get_recent(self, limit: int = 10) -> list[Greeting]:
        """
        Get the most recent greetings.

        Args:
            limit: Maximum number of greetings to return (default: 10)

        Returns:
            List of Greeting instances, newest first
        """
        stmt = (
            select(Greeting)
            .order_by(Greeting.created_at.desc())
            .limit(limit)
        )
        result = await self.session.scalars(stmt)
        return list(result.all())

    async def search_by_message(self, pattern: str) -> list[Greeting]:
        """
        Search greetings by message content.

        Args:
            pattern: Search pattern (uses SQL LIKE, so % is wildcard)

        Returns:
            List of matching Greeting instances
        """
        stmt = select(Greeting).where(Greeting.message.ilike(f"%{pattern}%"))
        result = await self.session.scalars(stmt)
        return list(result.all())

    async def get_since(self, since: datetime) -> list[Greeting]:
        """
        Get all greetings created since a given time.

        Args:
            since: Datetime threshold (timezone-aware recommended)

        Returns:
            List of Greeting instances created after the given time
        """
        # Ensure we're comparing with timezone-aware datetime
        if since.tzinfo is None:
            since = since.replace(tzinfo=timezone.utc)

        stmt = (
            select(Greeting)
            .where(Greeting.created_at >= since)
            .order_by(Greeting.created_at.asc())
        )
        result = await self.session.scalars(stmt)
        return list(result.all())
