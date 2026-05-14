# FastAPI 1Password Template

Production-ready FastAPI backend template with 1Password secrets management, PostgreSQL, and 4-layer architecture (API → Service → Provider → DAO).

## What's wired up

This isn't a "hello world" scaffold — the architectural plumbing is already done right so you can ship features on day one:

- **Dependency injection through every layer.** Routes declare `service: GreetingService = Depends(GreetingService)`. Services declare `dao_factory: DAOFactory = Depends(DAOFactory)`. No globals, no service locators, no manual wiring — and every layer is trivially testable with FastAPI's `app.dependency_overrides`.
- **Strict 4-layer separation that actually holds.** API → Service → Provider → DAO, enforced by convention and example code. Routes never touch the DB. Services never write SQL. Business logic lives in exactly one place.
- **1Password as the source of truth for secrets.** One vault per environment (`{PREFIX}-LOCAL`, `-TEST`, `-PROD`); `task env:generate ENV=local` pulls secrets into `.env.local`. No `.env` files in git, no hand-copied credentials in Slack DMs, teammates onboard with `./onboard.sh` and are running locally in under a minute.
- **Transaction patterns built into the DAO base class.** `create()` / `update()` / `delete()` auto-commit with auto-rollback on error; `add()` + `dao_factory.commit()` gives you atomic multi-record writes when you need them. You don't write boilerplate transaction handling.
- **Async end-to-end.** Every DAO, service, and route uses `async/await` with SQLAlchemy `AsyncSession`. No blocking calls hiding in the request path, no sync-over-async footguns.

See [CLAUDE.md](CLAUDE.md) for the full architecture reference and the example greeting endpoint for a complete route → service → DAO flow.

## Prerequisites

- macOS (Apple Silicon or Intel) — the setup wizard targets macOS
- A 1Password account

Everything else (Homebrew, Task, Docker Desktop, 1Password CLI, jq) is installed by the wizard if needed.

## Quick Start

If you're starting a new project from this template, run the setup wizard:

```bash
./setup.sh
```

The wizard walks you through:

1. Installing any missing tools (1Password CLI, jq, Task, Docker Desktop; Homebrew is bootstrapped first if missing)
2. Signing in to 1Password and picking an account
3. Picking an app name (used as both the Docker container prefix and the uppercased 1Password vault prefix) and external port
4. Picking which optional secret groups to seed (`test`, `sentry`, `config`)
5. Creating the `{PREFIX}-LOCAL` 1Password vault and seeding it with secrets (JWT key + DB password auto-generated)
6. Verifying end-to-end by generating `.env.local`
7. Optionally detaching from the template's git history (fresh-start your project)

Only the `-LOCAL` vault is created by the wizard. `-TEST` and `-PROD` vaults can be added later as you need them.

Once it finishes:

```bash
task start
```

API is at `http://localhost:8000` (or your configured `EXTERNAL_PORT`) and `/docs` for the OpenAPI UI.

### Re-running the wizard

The wizard is one-and-done. After it succeeds, day-to-day use is `task start` and `task env:generate` — see the Commands section below.

If you re-run `./setup.sh` on a project that's already set up, it shows a big warning, lists the existing config, and requires you to type `yes` to proceed. Anything else exits without touching a thing.

```bash
./setup.sh             # run setup (warns if .setup.config already exists)
./setup.sh --help      # show usage
```

### Joining an existing project

If a teammate already ran `./setup.sh` and you just cloned the repo, run the onboarding wizard instead:

```bash
./onboard.sh
```

It installs the same tools, signs you into 1Password, lets you pick the project's shared `-LOCAL` vault, writes `.setup.config`, and generates `.env.local` so `task start` works. You need to be invited to the project's 1Password vault first.

```bash
./onboard.sh           # run onboarding (warns if .setup.config already exists)
./onboard.sh --help    # show usage
```

### What gets seeded into each vault

**Required (always):** `JWT_SECRET_KEY`, `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`

**Optional (you choose):**
- `test` — `TEST_DB_HOST`, `TEST_DB_PORT`, `TEST_DB_USER`, `TEST_DB_PASSWORD`, `TEST_DB_NAME`
- `sentry` — `SENTRY_DSN`, `SENTRY_ENVIRONMENT`
- `config` — `ENVIRONMENT`, `LOG_LEVEL`, `DB_PORT`

The wizard auto-generates strong values for `JWT_SECRET_KEY` and any `DB_PASSWORD` (you can override). Everything else has sensible defaults you can accept or edit.

## Commands

| Command | Description |
|---------|-------------|
| `task start` | Start development environment |
| `task down` | Stop the dev environment |
| `task clean` | Stop containers, optionally remove artifacts |
| `task clean:all` | Remove all project Docker resources |
| `task logs` | View backend logs |
| `task test` | Run tests |

## Production Checklist

Before deploying to production, complete these security requirements:

### Authentication (Required)

- [ ] **Replace demo authentication** - The template includes a demo auth that accepts any credentials. Implement real password verification:
  - Create a User model with hashed passwords
  - Use bcrypt or argon2 for password hashing
  - See `backend/app/service/auth_service.py` lines 91-107

### API Security

- [ ] **Disable OpenAPI docs** - Prevent API enumeration by disabling docs in production. In `backend/app/main.py`:
  ```python
  from app.core.config import settings, LOCAL_ENVIRONMENTS

  app = FastAPI(
      title=settings.app_name,
      version=settings.app_version,
      docs_url="/docs" if settings.environment in LOCAL_ENVIRONMENTS else None,
      redoc_url="/redoc" if settings.environment in LOCAL_ENVIRONMENTS else None,
      openapi_url="/openapi.json" if settings.environment in LOCAL_ENVIRONMENTS else None,
  )
  ```

### Database Security

- [ ] **Remove database port exposure** - In production `docker-compose.yml`, remove or restrict:
  ```yaml
  ports:
    - "5432:5432"  # Remove this line
  ```

- [ ] **Use strong credentials** - Never rely on default fallbacks (`postgres`, `app_pass`). Always set explicit credentials via 1Password.

### Secrets Management

- [ ] **Generate strong JWT secret** - Use a cryptographically secure key:
  ```bash
  openssl rand -hex 32
  ```

- [ ] **Configure 1Password vaults** - Create separate vaults for each environment:
  - `{PROJECT}-LOCAL`
  - `{PROJECT}-TEST`
  - `{PROJECT}-PROD`

### Infrastructure

- [ ] **Use HTTPS** - Deploy behind a reverse proxy (nginx, Caddy, or cloud load balancer) with TLS
- [ ] **Set appropriate token expiration** - Review `access_token_expire_minutes` and `refresh_token_expire_minutes` in config
- [ ] **Configure Sentry** - Set `SENTRY_DSN` for error tracking (ensure `sentry_send_pii=False`)
