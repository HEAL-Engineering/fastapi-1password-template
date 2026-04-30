"""
Base DAO (Data Access Object) Abstract Class

This module provides a generic base class for all DAOs with common CRUD operations.
DAOs are responsible for ALL database interactions - they are the ONLY layer that
should contain SQL queries or SQLAlchemy operations.

RESPONSIBILITIES:
- Execute database queries (SELECT, INSERT, UPDATE, DELETE)
- Handle SQLAlchemy session operations (flush, commit, rollback)
- Return model instances or None

NOT RESPONSIBLE FOR:
- Business logic (that belongs in Services)
- External API calls (that belongs in Providers)
- HTTP handling (that belongs in API routes)

TRANSACTION PATTERNS:
- create(): Commits immediately (auto-commit for simple operations)
- add(): Flushes only, no commit (caller controls transaction)
- update()/delete(): Commits immediately

Use add() when you need to insert multiple records atomically:
    record1 = await dao1.add(...)  # flush, no commit
    record2 = await dao2.add(...)  # flush, no commit
    await dao_factory.commit()     # commit both atomically
"""

from abc import ABC

from sqlalchemy import func, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import DeclarativeBase


class BaseDAO[ModelType: DeclarativeBase](ABC):
    """
    Abstract base class for Data Access Objects.

    Provides common CRUD operations for any SQLAlchemy model.
    Uses Python 3.12+ generic syntax for type safety.

    Type Parameters:
        ModelType: The SQLAlchemy model class this DAO manages

    Example:
        class UserDAO(BaseDAO[User]):
            def __init__(self, session: AsyncSession):
                super().__init__(session, User)

            async def get_by_email(self, email: str) -> User | None:
                stmt = select(User).where(User.email == email)
                result = await self.session.execute(stmt)
                return result.scalar_one_or_none()
    """

    def __init__(self, session: AsyncSession, model: type[ModelType]):
        """
        Initialize the DAO with a database session and model class.

        Args:
            session: SQLAlchemy async database session
            model: SQLAlchemy model class
        """
        self.session = session
        self.model = model

    async def get(self, id: int) -> ModelType | None:
        """
        Get a single record by ID.

        Args:
            id: Record ID

        Returns:
            Model instance or None if not found
        """
        stmt = select(self.model).where(self.model.id == id)
        result = await self.session.execute(stmt)
        return result.scalar_one_or_none()

    async def create(self, **kwargs) -> ModelType:
        """
        Create a new record and commit immediately.

        Use this for simple, single-record inserts where you want
        immediate persistence.

        Args:
            **kwargs: Model field values

        Returns:
            Created model instance with database-assigned ID

        Raises:
            SQLAlchemyError: If creation fails (automatically rolled back)
        """
        try:
            db_obj = self.model(**kwargs)
            self.session.add(db_obj)
            await self.session.commit()
            await self.session.refresh(db_obj)
            return db_obj
        except SQLAlchemyError:
            await self.session.rollback()
            raise

    async def add(self, **kwargs) -> ModelType:
        """
        Add a new record without committing (flush only).

        Use this when inserting multiple records that should be
        committed atomically. The caller is responsible for calling
        commit() on the session/factory.

        Args:
            **kwargs: Model field values

        Returns:
            Model instance with database-assigned ID (from flush)

        Raises:
            SQLAlchemyError: If flush fails
        """
        db_obj = self.model(**kwargs)
        self.session.add(db_obj)
        await self.session.flush()
        return db_obj

    async def update(self, id: int, **kwargs) -> ModelType | None:
        """
        Update an existing record.

        Args:
            id: Record ID
            **kwargs: Fields to update

        Returns:
            Updated model instance or None if not found

        Raises:
            SQLAlchemyError: If update fails (automatically rolled back)
        """
        try:
            db_obj = await self.get(id)
            if not db_obj:
                return None

            for key, value in kwargs.items():
                if hasattr(db_obj, key):
                    setattr(db_obj, key, value)

            await self.session.commit()
            await self.session.refresh(db_obj)
            return db_obj
        except SQLAlchemyError:
            await self.session.rollback()
            raise

    async def delete(self, id: int) -> bool:
        """
        Delete a record by ID.

        Args:
            id: Record ID

        Returns:
            True if deleted, False if not found

        Raises:
            SQLAlchemyError: If deletion fails (automatically rolled back)
        """
        try:
            db_obj = await self.get(id)
            if not db_obj:
                return False

            await self.session.delete(db_obj)
            await self.session.commit()
            return True
        except SQLAlchemyError:
            await self.session.rollback()
            raise

    async def exists(self, id: int) -> bool:
        """
        Check if a record exists.

        Args:
            id: Record ID

        Returns:
            True if exists, False otherwise
        """
        stmt = select(func.count()).select_from(self.model).where(self.model.id == id)
        result = await self.session.execute(stmt)
        return result.scalar() > 0
