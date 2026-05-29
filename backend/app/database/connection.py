"""
Database Connection and Session Management

This module configures the async SQLAlchemy engine and session factory for PostgreSQL.
It uses the psycopg async driver for optimal performance with FastAPI.

KEY CONCEPTS:
- Engine: The connection pool manager (one per application)
- Session: A single database conversation (one per request)
- Base: The declarative base class all models inherit from

USAGE:
    from app.database.connection import get_session, Base

    # In FastAPI routes (via dependency injection):
    @router.get("/items")
    async def get_items(session: AsyncSession = Depends(get_session)):
        ...

    # For creating tables:
    await init_db()
"""

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase

from app.core.config import settings

logger = settings.logger


def create_engine() -> AsyncEngine:
    """
    Create async PostgreSQL engine with connection pooling.

    Pool settings explained:
    - pool_size: Number of connections to keep open (15 for moderate load)
    - max_overflow: Additional connections allowed during bursts
    - pool_timeout: Seconds to wait for available connection before error
    - pool_recycle: Seconds before recycling connections (prevents stale connections)
    - pool_pre_ping: Test connections before using (handles disconnects)
    - pool_use_lifo: Last-in-first-out improves cache locality

    Returns:
        AsyncEngine: Configured SQLAlchemy async engine
    """
    logger.info("Initializing async PostgreSQL database connection")

    return create_async_engine(
        settings.database_url,
        pool_size=15,
        max_overflow=15,
        pool_timeout=30,
        pool_recycle=3600,  # Recycle connections after 1 hour
        pool_pre_ping=True,  # Verify connections before using
        pool_use_lifo=True,  # Better for cloud databases (connection affinity)
        echo=False,  # Set True for SQL query logging (debugging only)
    )


# Create the engine singleton
engine = create_engine()
logger.info("Async PostgreSQL engine created")

# Session factory - creates new sessions for each request
session_factory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,  # Don't expire objects after commit
    autocommit=False,  # Explicit transaction control
    autoflush=False,  # Manual flush control (flush before queries)
)


class Base(DeclarativeBase):
    """
    Base class for all SQLAlchemy ORM models.

    All database models should inherit from this class:

        class User(Base):
            __tablename__ = "users"
            id: Mapped[int] = mapped_column(primary_key=True)
            ...
    """

    pass


async def get_session() -> AsyncGenerator[AsyncSession]:
    """
    Dependency for FastAPI to inject database sessions.

    This is the primary way to get database access in routes:

        @router.get("/items")
        async def get_items(session: AsyncSession = Depends(get_session)):
            result = await session.execute(select(Item))
            return result.scalars().all()

    The session is automatically closed when the request completes.

    Yields:
        AsyncSession: Database session for the current request
    """
    async with session_factory() as session:
        yield session


async def init_db() -> None:
    """
    Initialize database by creating all tables.

    This uses SQLAlchemy's create_all() which is idempotent -
    it only creates tables that don't exist.

    For production, use Alembic migrations instead.
    """
    # Import models to register them with Base.metadata
    import app.models  # noqa: F401

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
