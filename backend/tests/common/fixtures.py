"""
Shared pytest fixtures for database testing.

These fixtures provide transaction-based test isolation:
- Each test runs inside a transaction that gets rolled back
- Tests are fast because no data persists between tests
- Tests are isolated because each starts with clean state

USAGE:
    # For API tests (needs both session and client):
    def test_endpoint(get_session_client):
        session, client = get_session_client
        response = client.get("/health")
        assert response.status_code == 200

    # For DAO/database unit tests:
    async def test_dao(isolated_session):
        dao = MyDAO(isolated_session)
        result = await dao.create(...)

    # For API tests without database:
    def test_simple_endpoint(isolated_client):
        response = isolated_client.get("/health")
        assert response.status_code == 200
"""

import pytest
import pytest_asyncio
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

from app.core.config import settings
from app.database.connection import Base, get_session
from app.main import app


@pytest_asyncio.fixture(scope="session")
async def engine():
    """
    Create async database engine for tests.
    Uses settings.test_database_url configured via TEST_DB_* environment variables.

    scope="session" means this runs ONCE for the entire test session, not per-test.
    """
    test_url = settings.test_database_url
    if not test_url:
        raise RuntimeError(
            "Test database not configured. Set TEST_DB_HOST, TEST_DB_USER, "
            "TEST_DB_PASSWORD, and TEST_DB_NAME environment variables."
        )

    # NullPool = no connection pooling, each connect() opens a fresh connection
    test_engine = create_async_engine(
        test_url,
        poolclass=NullPool,
        echo=False,
    )

    # Create all tables once at the start of the test session
    # begin() starts a transaction that auto-commits on exit
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # Engine is shared across all tests
    yield test_engine

    # Cleanup after all tests complete
    await test_engine.dispose()


@pytest_asyncio.fixture()
async def get_session_client(engine):
    """
    Get database session and test client with transaction rollback.
    Uses transaction rollback for test isolation (very fast).

    How it works:
    1. Opens a connection and starts an OUTER transaction
    2. Creates a session that uses SAVEPOINTs instead of real commits
    3. Test runs - all "commits" are actually savepoints
    4. After test: rollback outer transaction, undoing ALL changes
    """
    # Context manager 1: Opens a new database connection from the engine
    # On exit: closes the connection
    async with engine.connect() as connection:
        # Starts the OUTER transaction - this is what gets rolled back at the end
        transaction = await connection.begin()

        # Create session factory bound to THIS connection (not the engine)
        # join_transaction_mode="create_savepoint" is the key:
        #   - Every session.commit() creates a SAVEPOINT instead of real COMMIT
        #   - Savepoints are nested inside the outer transaction
        #   - When we rollback the outer transaction, ALL savepoints are undone
        async_session_factory = async_sessionmaker(
            bind=connection,
            class_=AsyncSession,
            expire_on_commit=False,
            join_transaction_mode="create_savepoint",
        )

        # Context manager 2: Creates a session from the factory
        # On exit: closes the session (but transaction stays open)
        async with async_session_factory() as session:
            # Make FastAPI use THIS session for all requests during the test
            async def override_get_session():
                yield session

            app.dependency_overrides[get_session] = override_get_session

            # Test runs here - all commits become savepoints
            yield session, TestClient(app)

            app.dependency_overrides.clear()

        # ROLLBACK the outer transaction - undoes ALL savepoints/changes
        await transaction.rollback()


@pytest_asyncio.fixture()
async def isolated_session(engine):
    """
    Isolated database session for unit tests.
    Uses transaction rollback for test isolation.

    Use this for DAO/database unit tests that don't need the HTTP client.
    """
    # Context manager 1: Opens a new database connection
    async with engine.connect() as connection:
        # Start outer transaction
        transaction = await connection.begin()

        # join_transaction_mode="create_savepoint": commits become savepoints
        async_session_factory = async_sessionmaker(
            bind=connection,
            class_=AsyncSession,
            expire_on_commit=False,
            join_transaction_mode="create_savepoint",
        )

        # Context manager 2: Creates session
        async with async_session_factory() as session:
            # Test runs here
            yield session

        # Rollback outer transaction - undoes everything
        await transaction.rollback()


@pytest.fixture()
def isolated_client():
    """
    Test client without database session.
    Use this for tests that don't need database access.
    """
    yield TestClient(app)
