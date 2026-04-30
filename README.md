# FastAPI 1Password Template

Production-ready FastAPI backend template with 1Password secrets management, PostgreSQL, and 4-layer architecture (API → Service → Provider → DAO).

## Prerequisites

- Docker
- [Task](https://taskfile.dev/) - `brew install go-task`
- [1Password CLI](https://1password.com/downloads/command-line/) - `brew install --cask 1password-cli`

## Quick Start

### 1. Configure Project Settings

Edit `Taskfile.yml` lines 11-13:

```yaml
vars:
  APP_NAME: your-project        # Docker container prefix
  EXTERNAL_PORT: "8000"         # Host port for API
```

Update your 1Password vault prefix in `scripts/generate-env.sh` line 7:

```bash
VAULT_PREFIX="YOUR-PROJECT"  # → vaults: YOUR-PROJECT-LOCAL, YOUR-PROJECT-TEST, YOUR-PROJECT-PROD
```

### 2. Set Up 1Password Vault

Create a vault named `{VAULT_PREFIX}-LOCAL` (e.g., `YOUR-PROJECT-LOCAL`) and add these items:

#### Required Secrets

| Item Title | Description | How to Generate |
|------------|-------------|-----------------|
| `JWT_SECRET_KEY` | Token signing key | `openssl rand -hex 32` |
| `DB_HOST` | Database hostname | `localhost` (local) or `postgres` (Docker) |
| `DB_USER` | Database username | e.g., `app_user` |
| `DB_PASSWORD` | Database password | Strong password |
| `DB_NAME` | Database name | e.g., `app_db` |

#### Optional Secrets

| Item Title | Default | Description |
|------------|---------|-------------|
| `ENVIRONMENT` | `development` | Environment name (`local`, `development`, `production`) |
| `LOG_LEVEL` | `info` | Logging level (`debug`, `info`, `warning`, `error`) |
| `DB_PORT` | `5432` | Database port |
| `JWT_ALGORITHM` | `HS256` | JWT signing algorithm |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `1440` | Access token TTL (24 hours) |
| `REFRESH_TOKEN_EXPIRE_MINUTES` | `43200` | Refresh token TTL (30 days) |

#### Optional: Test Database

| Item Title | Description |
|------------|-------------|
| `TEST_DB_HOST` | Test database host |
| `TEST_DB_PORT` | Test database port (default: 5432) |
| `TEST_DB_USER` | Test database user |
| `TEST_DB_PASSWORD` | Test database password |
| `TEST_DB_NAME` | Test database name |

#### Optional: Sentry Monitoring

| Item Title | Default | Description |
|------------|---------|-------------|
| `SENTRY_DSN` | None | Sentry project DSN |
| `SENTRY_ENVIRONMENT` | None | Environment tag for Sentry |
| `SENTRY_SAMPLE_RATE` | `1.0` | Trace sample rate (0.0-1.0) |
| `SENTRY_SEND_PII` | `False` | Send PII to Sentry (keep `False`) |
| `SENTRY_LOG_LEVEL` | `info` | Minimum level to send to Sentry |
| `SENTRY_BREADCRUMBS_LEVEL` | `error` | Breadcrumb capture level |

### 3. Generate Environment File

```bash
task env:setup     # First time: install 1Password CLI and sign in
task env:generate  # Generate .env.local from 1Password vault
```

### 4. Start Development

```bash
task dev
```

API available at `http://localhost:8000` (or your configured `EXTERNAL_PORT`).

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
