# FastAPI 1Password Template

Production-ready FastAPI backend template with 1Password secrets management, PostgreSQL, and 4-layer architecture (API → Service → Provider → DAO).

## Prerequisites

- macOS (Apple Silicon or Intel) — the setup wizard targets macOS
- A 1Password account

Everything else (Homebrew, Task, Docker Desktop, 1Password CLI, jq, gum) is installed by the wizard.

## Quick Start

```bash
./setup.sh
```

The wizard walks you through:

1. Installing any missing tools (Homebrew, gum, 1Password CLI, jq, Task, Docker Desktop)
2. Signing in to 1Password
3. Picking a vault prefix, app name, and external port
4. Auto-creating your three 1Password vaults (`{PREFIX}-LOCAL`, `-TEST`, `-PROD`)
5. Seeding each vault with the required secrets (JWT key + DB password auto-generated)
6. Wiring `scripts/generate-env.sh` and `Taskfile.yml` to your config
7. Verifying end-to-end by generating `.env.local`
8. Optionally detaching from the template's git history (fresh-start your project)

Once it finishes:

```bash
task dev
```

API is at `http://localhost:8000` (or your configured `EXTERNAL_PORT`) and `/docs` for the OpenAPI UI.

### Re-running the wizard

The wizard is one-and-done. After it succeeds, day-to-day use is `task dev` and `task env:generate` — see the Commands section below.

If you re-run `./setup.sh` on a project that's already set up, it shows a big warning, lists the existing config, and requires you to type `yes` to proceed. Anything else exits without touching a thing.

```bash
./setup.sh             # run setup (warns if .setup.config already exists)
./setup.sh --no-gum    # plain-text prompts (skip gum install)
./setup.sh --help      # all flags
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
| `task dev` | Start development environment |
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
