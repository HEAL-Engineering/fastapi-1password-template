# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**FastAPI backend template with 1Password secrets management**

**Async codebase** — all DAOs, services, and routes use `async/await` with `AsyncSession`. Every database operation must be awaited.

**Package manager:** [uv](https://docs.astral.sh/uv/) (not pip/poetry). Use `uv add`, `uv remove`, `uv lock --upgrade`.

---

## 4-Layer Architecture (Strict)

```
API Layer (app/api/)         → HTTP handling, auth, Pydantic validation
Service Layer (app/service/) → Business logic, orchestration
Provider Layer (app/provider/) → External API integrations
DAO Layer (app/dao/)         → Database CRUD only
```

**Rules:**
- Routes call Services, Services call Providers/DAOs
- NEVER put business logic in routes
- NEVER put DB queries in services
- NEVER skip layers

---

## DAO Factory & Service Pattern

Routes inject services via `Depends(ServiceClass)`. Services own the transaction (commit/rollback).

```python
# Route (app/api/greeting.py)
@router.post("/greeting/{name}")
async def create_greeting(
    name: str,
    service: GreetingService = Depends(GreetingService)
):
    return await service.create_greeting(name)

# Service (app/service/greeting_service.py)
from app.core.config import settings
logger = settings.logger

class GreetingService:
    def __init__(self, dao_factory: DAOFactory = Depends(DAOFactory)):
        self.dao_factory = dao_factory
        self.greeting_dao = dao_factory.get_greeting_dao()

    async def create_greeting(self, name: str) -> GreetingResponse:
        try:
            logger.info(f"Creating greeting for: {name}")
            # create() auto-commits; use add() + commit() for atomic multi-record ops
            greeting = await self.greeting_dao.create(
                name=name, message=f"Hello, {name}!"
            )
            return GreetingResponse.model_validate(greeting)
        except SQLAlchemyError as e:
            logger.error(f"DB error: {str(e)}", exc_info=True)
            raise HTTPException(500, "Failed to create greeting")
        except Exception as e:
            logger.error(f"Unexpected error: {str(e)}", exc_info=True)
            raise HTTPException(500, "Internal server error")
```

**DAO Transaction Patterns:**
- `create()` / `update()` / `delete()` → auto-commit, auto-rollback on error
- `add()` → flush only, caller must `await dao_factory.commit()`

**Rules:**
- Routes inject services via `Depends(ServiceClass)`
- Services declare `dao_factory: DAOFactory = Depends(DAOFactory)` in `__init__`
- ALWAYS wrap DB/external calls in try-except
- ALWAYS use `settings.logger` (never `logging.getLogger()`)
- ALWAYS use `exc_info=True` for error logs
- NEVER log sensitive data (passwords, tokens, PII)

---

## 1Password Environment Management

Secrets live in 1Password vaults and are generated to `.env` files:

```bash
./onboard.sh                 # First-time setup (installs op CLI, signs in, writes .setup.config)
task env:generate            # Generate all .env files
task env:generate ENV=local  # Generate one environment
task env:add                 # Add a new secret to a vault
```

**Vaults:** `{VAULT_PREFIX}-LOCAL`, `{VAULT_PREFIX}-TEST`, `{VAULT_PREFIX}-PROD`. `VAULT_PREFIX` is set in `.setup.config` by `./setup.sh`.

Each 1Password item title = one env var name. **Never commit `.env` files.**

---

## Project Structure

```
backend/
├── app/
│   ├── main.py              # FastAPI entry point
│   ├── api/                  # Routes (auth.py, greeting.py)
│   ├── service/              # Business logic
│   ├── provider/             # External integrations
│   ├── dao/                  # Data access (base.py, factory.py, daos/)
│   ├── model/
│   │   ├── database/         # SQLAlchemy models
│   │   └── schema/           # Pydantic request/response models
│   ├── core/                 # config.py, token.py
│   └── database/             # connection.py
├── Dockerfile
└── pyproject.toml
```

---

## Configuration

Single place to change project settings in `Taskfile.yml`:

```yaml
vars:
  APP_NAME: fastapi-template    # Docker container prefix
  EXTERNAL_PORT: "8000"         # Host port
```

App settings in `backend/app/core/config.py`:
```python
DEFAULT_APP_NAME = "FastAPI Template"
DEFAULT_APP_VERSION = "0.1.0"
```

---

## Key Files

| Category | Files |
|----------|-------|
| Entry | `app/main.py`, `app/core/config.py` |
| Database | `app/database/connection.py`, `app/dao/base.py`, `app/dao/factory.py` |
| Auth | `app/service/auth_service.py`, `app/core/token.py` |
| Example | `app/api/greeting.py`, `app/service/greeting_service.py`, `app/dao/daos/greeting_dao.py` |
| Config | `Taskfile.yml`, `tasks/env.yml`, `scripts/generate-env.sh` |

---

## Common Tasks

**Add Endpoint:** Schema (`model/schema/`) → Route (`api/`) → Service (`service/`) → DAO if needed

**Add Table:** Model (`model/database/`) → DAO (`dao/daos/`) → Factory getter (`dao/factory.py`)

**Add External Integration:** Provider class (`provider/`) → Use in Service layer

---

## Critical Reminders

### ALWAYS
- Use try-except with logging for DB/external calls
- Type hints on all functions
- Pydantic validation for requests/responses
- Follow 4-layer architecture

### NEVER
- Put business logic in routes
- Put DB queries in services
- Skip error handling
- Log sensitive data
- Use `logging.getLogger()` (use `settings.logger`)
