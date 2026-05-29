"""
DAO Factory for Dependency Injection

This module provides a factory class that creates and manages DAO instances.
It ensures all DAOs share the same database session within a single request,
enabling atomic transactions across multiple DAOs.

DEPENDENCY CHAIN:
    Routes → Services → DAOFactory → AsyncSession

    Routes should NEVER directly depend on DAOFactory.
    Routes depend on Services, which depend on DAOFactory.

WHY USE A FACTORY?
1. Single session per request: All DAOs share one AsyncSession
2. Lazy loading: DAOs are created only when needed
3. Transaction control: Centralized commit/rollback across all DAOs
4. Easy testing: Override get_session dependency to inject test sessions

USAGE IN SERVICES (the correct pattern):
    class GreetingService:
        def __init__(self, dao_factory: DAOFactory = Depends(DAOFactory)):
            self.dao_factory = dao_factory
            self.greeting_dao = dao_factory.get_greeting_dao()

        async def create_greeting(self, name: str) -> Greeting:
            greeting = await self.greeting_dao.create(name=name, message="Hello")
            return greeting

USAGE IN ROUTES (depends on Service, NOT DAOFactory):
    @router.post("/greetings")
    async def create_greeting(
        request: CreateGreetingRequest,
        service: GreetingService = Depends(GreetingService),
    ):
        return await service.create_greeting(request.name)

ATOMIC TRANSACTIONS:
    # Multiple inserts that commit together or not at all
    item = await item_dao.add(name="Item 1")        # flush, no commit
    detail = await detail_dao.add(item_id=item.id)  # flush, no commit
    await dao_factory.commit()                       # commit both atomically
"""

from fastapi import Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.dao.daos.greeting_dao import GreetingDAO
from app.database.connection import get_session


class DAOFactory:
    """
    Factory class for creating and managing DAO instances.

    Injected via FastAPI's dependency injection into SERVICES (not routes).
    Each request gets its own DAOFactory with its own database session.

    The factory lazily instantiates DAOs - they're only created when
    first accessed via their getter methods.
    """

    def __init__(self, session: AsyncSession = Depends(get_session)):
        """
        Initialize the DAO factory.

        Args:
            session: Database session (injected via FastAPI Depends)
        """
        self.session = session
        self._daos: dict = {}  # Lazy-load cache for DAO instances

    # -------------------------------------------------------------------------
    # DAO Getters - Add new DAOs here as your application grows
    # -------------------------------------------------------------------------

    def get_greeting_dao(self) -> GreetingDAO:
        """
        Get or create GreetingDAO instance.

        Returns:
            GreetingDAO: DAO for Greeting model
        """
        if "greeting" not in self._daos:
            self._daos["greeting"] = GreetingDAO(self.session)
        return self._daos["greeting"]

    # -------------------------------------------------------------------------
    # Transaction Control Methods
    # -------------------------------------------------------------------------

    async def commit(self) -> None:
        """
        Commit the current transaction.

        Call this after using add() on multiple DAOs to commit
        all changes atomically.
        """
        await self.session.commit()

    async def rollback(self) -> None:
        """
        Rollback the current transaction.

        Call this to undo all uncommitted changes (from add() calls).
        """
        await self.session.rollback()

    async def close(self) -> None:
        """
        Close the database session.

        Note: Usually handled automatically by FastAPI's dependency
        injection cleanup. Only call manually if needed.
        """
        await self.session.close()
