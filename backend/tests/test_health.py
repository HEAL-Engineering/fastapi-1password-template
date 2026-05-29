"""
Template test file demonstrating fixture usage patterns.

Three patterns:
1. isolated_session - DAO/database unit tests
2. isolated_client - API tests without database
3. get_session_client - API tests with database transactions
"""

from app.dao.daos.greeting_dao import GreetingDAO


async def test_dao_with_isolated_session(isolated_session):
    """DAO test using isolated_session fixture."""
    dao = GreetingDAO(isolated_session)

    # Create a greeting
    greeting = await dao.create(
        name="TestUser",
        message="Hello, TestUser!",
        source="unit_test",
    )

    # Verify it was created
    assert greeting.id is not None
    assert greeting.name == "TestUser"

    # Verify we can retrieve it
    found = await dao.get_by_name("TestUser")
    assert found is not None
    assert found.id == greeting.id


def test_health_endpoint_with_isolated_client(isolated_client):
    """API test using isolated_client fixture (no database)."""
    response = isolated_client.get("/health")

    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_greeting_endpoint_with_session_client(get_session_client):
    """API test using get_session_client fixture (with database transaction)."""
    session, client = get_session_client

    # Call endpoint that creates a database record
    response = client.get("/api/v1/greeting/IntegrationTest")

    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "IntegrationTest"
    assert "message" in data
