"""
Greeting Provider - External Integration Layer

Providers handle ALL external API integrations. They encapsulate third-party
SDK/API calls and isolate your application from external dependencies.

PROVIDER RESPONSIBILITIES:
- Make HTTP requests to external APIs
- Handle authentication with external services
- Transform external data formats to internal models
- Manage rate limiting and retry logic
- Handle provider-specific errors

PROVIDERS SHOULD NOT:
- Access the database directly (that belongs in DAOs)
- Contain business logic (that belongs in Services)
- Handle HTTP request/response for YOUR API (that belongs in Routes)

COMMON PROVIDER PATTERNS:
- HTTP client (httpx) for REST APIs
- SDK wrappers (boto3, stripe-python, openai)
- OAuth providers (Google, Apple, Strava)
- Message queue publishers (SNS, SQS, RabbitMQ)

This example provider simulates an external "greeting service" API.
In a real application, replace with actual integration code.

USAGE IN SERVICES:
    class GreetingService:
        def __init__(self, dao_factory: DAOFactory = Depends(DAOFactory)):
            self.provider = GreetingProvider()

        async def get_fancy_greeting(self, name: str) -> str:
            return await self.provider.fetch_greeting(name)
"""

import httpx

from app.core.config import settings

logger = settings.logger


class GreetingProvider:
    """
    Example provider simulating an external greeting service.

    In a real application, this might be:
    - A payment provider (Stripe, PayPal)
    - A notification service (Twilio, SendGrid)
    - An AI service (OpenAI, Anthropic)
    - A third-party data API (weather, stocks, etc.)

    This example shows the patterns without requiring an actual external service.
    """

    def __init__(self):
        """
        Initialize the provider.

        In a real provider, you might:
        - Load API keys from settings
        - Initialize SDK clients
        - Set up connection pools
        """
        # Example: self.api_key = settings.external_api_key
        # Example: self.client = ExternalSDK(api_key=self.api_key)
        self.base_url = "https://api.example.com"  # Placeholder

    async def fetch_greeting(self, name: str, style: str = "friendly") -> str:
        """
        Fetch a greeting from an external service.

        This is a SIMULATED external call. In production, this would
        make an actual HTTP request to an external API.

        Args:
            name: Name to greet
            style: Greeting style (friendly, formal, casual)

        Returns:
            A greeting string from the "external service"

        Raises:
            httpx.HTTPError: If the external API call fails
        """
        # SIMULATED: In production, uncomment the actual HTTP call
        # async with httpx.AsyncClient() as client:
        #     response = await client.get(
        #         f"{self.base_url}/greetings",
        #         params={"name": name, "style": style},
        #         headers={"Authorization": f"Bearer {self.api_key}"},
        #     )
        #     response.raise_for_status()
        #     data = response.json()
        #     return data["greeting"]

        # Simulated response for template demonstration
        logger.debug(f"GreetingProvider: Simulating external API call for {name}")

        greetings = {
            "friendly": f"Hey {name}! Great to see you!",
            "formal": f"Good day, {name}. How may I assist you?",
            "casual": f"Yo {name}, what's up?",
        }

        return greetings.get(style, f"Hello, {name}!")

    async def fetch_greeting_of_the_day(self) -> str:
        """
        Fetch a daily greeting from an external service.

        Demonstrates a parameterless external API call.

        Returns:
            The greeting of the day
        """
        # SIMULATED: Would be an actual API call in production
        logger.debug("GreetingProvider: Fetching greeting of the day")
        return "Welcome! Today is a great day to build something amazing."

    async def validate_name(self, name: str) -> bool:
        """
        Validate a name against an external service.

        Example of a provider method that returns a simple result
        from an external validation service.

        Args:
            name: Name to validate

        Returns:
            True if valid, False otherwise
        """
        # SIMULATED: Would call external validation API
        logger.debug(f"GreetingProvider: Validating name '{name}'")

        # Simple validation rules (simulating external service logic)
        if not name or len(name) < 2:
            return False
        if len(name) > 100:
            return False

        return True
