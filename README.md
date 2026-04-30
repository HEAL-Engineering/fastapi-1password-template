# FastAPI 1Password Template

Production-ready FastAPI backend template with 1Password secrets management, PostgreSQL, and 4-layer architecture (API → Service → Provider → DAO).

## Prerequisites

- Docker
- [Task](https://taskfile.dev/) - `brew install go-task`
- [1Password CLI](https://1password.com/downloads/command-line/) - `brew install --cask 1password-cli`

## Quick Start

```bash
task dev
```

## Configuration

Edit `Taskfile.yml` lines 11-13:

```yaml
vars:
  APP_NAME: fastapi-template    # Docker container prefix
  EXTERNAL_PORT: "8000"         # Host port for API
```

Then update your 1Password vault name in `scripts/generate-env.sh` line 7:

```bash
VAULT_PREFIX="YOUR-PROJECT"  # → vaults: YOUR-PROJECT-LOCAL, YOUR-PROJECT-TEST, YOUR-PROJECT-PROD
```

## Commands

| Command | Description |
|---------|-------------|
| `task dev` | Start development environment |
| `task clean` | Stop containers, optionally remove artifacts |
| `task clean:all` | Remove all project Docker resources |
| `task logs` | View backend logs |
| `task test` | Run tests |
