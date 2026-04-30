"""
API Package

FastAPI route handlers. Routes should only:
- Parse/validate requests (via Pydantic schemas)
- Call Services for business logic
- Return responses

Routes should NOT:
- Contain business logic
- Access DAOs directly (use Services)
- Make external API calls (use Services → Providers)
"""
