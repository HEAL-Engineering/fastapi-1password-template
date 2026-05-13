#!/usr/bin/env bash
# =============================================================================
# Interactive setup wizard for FastAPI + 1Password template (macOS-only)
#
# Run this ONCE per project. For ongoing operations, use the task commands
# (task env:generate, task dev, etc.).
#
#   ./setup.sh             run setup (warns if .setup.config already exists)
#   ./setup.sh --help      show this help
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Globals
# -----------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${REPO_ROOT}/.setup.config"
GENERATE_ENV_SCRIPT="${REPO_ROOT}/scripts/generate-env.sh"
TASKFILE="${REPO_ROOT}/Taskfile.yml"
WIZARD_VERSION=1

VAULT_PREFIX=""
APP_NAME=""
EXTERNAL_PORT=""
OPTIONAL_SECTIONS=""

CREATED_VAULTS=()
VAULT_ITEM_SUMMARY=()   # entries like "VAULT-NAME:N"

# Exit codes
EXIT_OK=0
EXIT_GENERIC=1
EXIT_UNSUPPORTED_OS=2
EXIT_TOOL_DECLINED=3
EXIT_OP_SIGNIN=4
EXIT_VAULT_FAILED=5
EXIT_VERIFY_FAILED=6
EXIT_BAD_ARGS=64
EXIT_INTERRUPT=130

# ANSI fallbacks
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_CYAN=$'\033[36m'

# =============================================================================
# UI helpers — plain bash + ANSI colors (no TUI libraries)
# =============================================================================
ask_confirm() {
    local prompt="$1" ans
    read -r -p "$prompt [y/N] " ans
    case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

ask_input() {
    local label="$1" default_val="${2:-}" ans
    if [ -n "$default_val" ]; then
        read -r -p "$label [$default_val]: " ans
        [ -z "$ans" ] && ans="$default_val"
    else
        read -r -p "$label: " ans
    fi
    printf '%s' "$ans"
}

ask_password() {
    local label="$1" ans
    read -r -s -p "$label: " ans
    printf '\n' >&2
    printf '%s' "$ans"
}

ask_choose() {
    # Usage: ask_choose "Prompt" "opt1" "opt2" ...   → prints chosen option to stdout
    local label="$1"; shift
    printf '\n%s\n' "$label" >&2
    local i=1
    for opt in "$@"; do
        printf '  %d) %s\n' "$i" "$opt" >&2
        i=$((i + 1))
    done
    local choice
    read -r -p "Choice [1]: " choice
    [ -z "$choice" ] && choice=1
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt $# ]; then
        choice=1
    fi
    printf '%s' "${!choice}"
}

ask_multichoose() {
    # Usage: ask_multichoose "Prompt" "opt1" "opt2" ...   → prints chosen options, one per line
    local label="$1"; shift
    printf '\n%s\n' "$label" >&2
    printf '%s\n' "(comma-separated numbers, or empty for none)" >&2
    local i=1
    for opt in "$@"; do
        printf '  %d) %s\n' "$i" "$opt" >&2
        i=$((i + 1))
    done
    local raw
    read -r -p "Selections: " raw
    local IFS=','
    for n in $raw; do
        n="$(echo "$n" | tr -d '[:space:]')"
        [ -z "$n" ] && continue
        [[ "$n" =~ ^[0-9]+$ ]] || continue
        [ "$n" -ge 1 ] && [ "$n" -le $# ] && printf '%s\n' "${!n}"
    done
}

run_with_label() {
    # Usage: run_with_label "Doing thing..." -- cmd args...
    local title="$1"; shift
    [ "${1:-}" = "--" ] && shift
    printf '%s→%s %s\n' "$C_BLUE" "$C_RESET" "$title" >&2
    "$@"
    local rc=$?
    if [ $rc -eq 0 ]; then printf '%s✓%s done\n'    "$C_GREEN" "$C_RESET" >&2
    else                   printf '%s✗%s failed\n'  "$C_RED"   "$C_RESET" >&2; fi
    return $rc
}

print_header() {
    local text="$1"
    printf '\n%s%s%s%s\n' "$C_BOLD" "$C_CYAN" "$text" "$C_RESET"
    printf '%s\n' "$(printf '%*s' "${#text}" | tr ' ' '-')"
}

print_box() {
    printf '\n%s\n' "$1"
}

log_info() { printf '%s→ %s%s\n' "$C_BLUE"   "$*" "$C_RESET"; }
log_ok()   { printf '%s✓ %s%s\n' "$C_GREEN"  "$*" "$C_RESET"; }
log_warn() { printf '%s! %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
log_err()  { printf '%s✗ %s%s\n' "$C_RED"    "$*" "$C_RESET" >&2; }

# =============================================================================
# Argument parsing & help
# =============================================================================
print_help() {
    cat <<'EOF'
Interactive setup wizard for FastAPI + 1Password template (macOS-only)

Run this ONCE per project. For ongoing operations, use the task commands
(task env:generate, task dev, etc.).

Usage:
  ./setup.sh             run setup (warns if .setup.config already exists)
  ./setup.sh --help      show this help
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --help|-h) print_help; exit "$EXIT_OK" ;;
            *)         printf 'Unknown flag: %s\n' "$1" >&2; print_help >&2; exit "$EXIT_BAD_ARGS" ;;
        esac
        shift
    done
}

# =============================================================================
# Sanity check — this template targets macOS only
# =============================================================================
require_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        log_err "This wizard is macOS-only. Detected: $(uname -s)"
        log_err "If you're on Linux/WSL, the manual flow in README still works."
        exit "$EXIT_UNSUPPORTED_OS"
    fi
}

# =============================================================================
# Step 0 — warn if this project has already been set up
# =============================================================================
warn_if_already_setup() {
    [ ! -f "$CONFIG_FILE" ] && return

    # Surface the existing config so the user knows what's about to be replaced.
    local existing_prefix existing_app existing_port
    existing_prefix="$(grep -E '^VAULT_PREFIX='  "$CONFIG_FILE" | head -1 | cut -d= -f2- || true)"
    existing_app="$(   grep -E '^APP_NAME='     "$CONFIG_FILE" | head -1 | cut -d= -f2- || true)"
    existing_port="$(  grep -E '^EXTERNAL_PORT=' "$CONFIG_FILE" | head -1 | cut -d= -f2- || true)"

    printf '\n'
    printf '%s%s⚠️   WARNING — this project is already set up.%s\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
    printf '\n'
    printf '  Current config: %s\n' "$CONFIG_FILE"
    printf '    VAULT_PREFIX=%s\n' "$existing_prefix"
    printf '    APP_NAME=%s\n'    "$existing_app"
    printf '    EXTERNAL_PORT=%s\n' "$existing_port"
    printf '\n'
    printf '  Running the wizard again will:\n'
    printf '    • OVERWRITE .setup.config\n'
    printf '    • Walk you through creating/recreating 1Password vaults\n'
    printf '    • Prompt to overwrite vault items (you can still pick "Keep")\n'
    printf '    • Re-patch Taskfile.yml and scripts/generate-env.sh\n'
    printf '\n'
    printf '  %sFor ongoing operations, use the task commands instead:%s\n' "$C_BOLD" "$C_RESET"
    printf '    • task env:generate       # regenerate .env files from 1Password\n'
    printf '    • task dev                # start development environment\n'
    printf '    • task --list             # see all commands\n'
    printf '\n'

    local ans
    read -r -p "ARE YOU SURE YOU WANT TO CONTINUE? Type 'yes' to proceed: " ans
    if [ "$ans" != "yes" ]; then
        log_info "Aborted. Nothing was changed."
        exit "$EXIT_OK"
    fi

    log_warn "Proceeding with re-setup. Removing $CONFIG_FILE..."
    rm -f "$CONFIG_FILE"
}

# =============================================================================
# Homebrew bootstrap
# =============================================================================
install_homebrew_if_missing() {
    if command -v brew >/dev/null 2>&1; then return 0; fi

    printf 'Homebrew is required but not installed.\n'
    local ans
    read -r -p "Install Homebrew now? [Y/n] " ans
    case "$ans" in n|N) log_err "Cannot continue without Homebrew."; exit "$EXIT_TOOL_DECLINED" ;; esac

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH for this session (Apple Silicon default location).
    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

# =============================================================================
# Step 1 — dependency installation
# =============================================================================
ensure_tool() {
    # Usage: ensure_tool <name> <brew-args> [optional_install_check_cmd]
    local name="$1" brew_args="$2"
    local check_cmd="${3:-command -v $name >/dev/null 2>&1}"

    if eval "$check_cmd"; then
        log_ok "$name installed"
        return 0
    fi

    if ! ask_confirm "$name is not installed. Install it via brew?"; then
        log_warn "Skipping $name."
        if ! ask_confirm "Continue anyway? The wizard will likely fail later."; then
            exit "$EXIT_TOOL_DECLINED"
        fi
        return 0
    fi

    # shellcheck disable=SC2086  # intentional word-splitting on brew_args
    brew install $brew_args

    if eval "$check_cmd"; then
        log_ok "$name installed"
    else
        log_err "$name install did not succeed."
        if ! ask_confirm "Continue without $name?"; then exit "$EXIT_TOOL_DECLINED"; fi
    fi
}

ensure_docker() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        log_ok "docker installed and daemon running"
        return 0
    fi

    if ! command -v docker >/dev/null 2>&1; then
        if ask_confirm "Docker not installed. Install Docker Desktop via brew?"; then
            brew install --cask docker
            log_info "Launch Docker Desktop from /Applications and finish first-run setup."
            ask_confirm "Docker Desktop is running?" || true
        fi
    elif ! docker info >/dev/null 2>&1; then
        log_warn "Docker is installed but the daemon isn't running."
        ask_confirm "Start Docker Desktop, then continue?" || true
    fi
}

step_dep_check() {
    print_header "Step 1 — Dependencies"
    ensure_tool "op"   "--cask 1password-cli"
    ensure_tool "jq"   "jq"
    ensure_tool "task" "go-task"
    if ! command -v openssl >/dev/null 2>&1; then
        log_warn "openssl missing — secret generation will fall back to /dev/urandom."
    fi
    ensure_docker
}

# =============================================================================
# Step 2 — 1Password sign-in
# =============================================================================
step_op_signin() {
    print_header "Step 2 — Sign in to 1Password"

    local attempt=1 max=3
    while [ $attempt -le $max ]; do
        if op account list >/dev/null 2>&1; then
            local who
            who="$(op whoami --format json 2>/dev/null | jq -r '.email // empty' 2>/dev/null || true)"
            if [ -n "$who" ]; then log_ok "Signed in as $who"; else log_ok "Signed in to 1Password"; fi
            return 0
        fi

        print_box "Sign in to 1Password CLI

To enable Touch ID (recommended):
  1. Open the 1Password app
  2. Settings → Developer → Integrate with 1Password CLI

You'll need:
  • Your 1Password account email
  • Your Secret Key (from Emergency Kit)
  • Your Master Password"

        if op signin; then continue; fi

        attempt=$((attempt + 1))
        if [ $attempt -le $max ]; then
            ask_confirm "Sign-in failed. Retry?" || break
        fi
    done

    log_err "Could not sign in to 1Password after $max attempts."
    exit "$EXIT_OP_SIGNIN"
}

# =============================================================================
# Step 3 — Project config prompts
# =============================================================================
prompt_vault_prefix() {
    local default val
    default="${VAULT_PREFIX:-API-APP}"
    log_info "Used to name your 1Password vaults: <PREFIX>-LOCAL, <PREFIX>-TEST, <PREFIX>-PROD"
    while :; do
        read -r -p "Change the vault prefix: " val
        [ -z "$val" ] && val="$default"
        if [[ ! "$val" =~ ^[A-Z0-9-]+$ ]]; then
            log_err "Prefix must contain only uppercase letters, digits, and dashes."
            continue
        fi
        if [ ${#val} -lt 3 ] || [ ${#val} -gt 30 ]; then
            log_err "Prefix must be 3-30 characters."
            continue
        fi
        if [ "$val" = "YOUR-PROJECT" ]; then
            log_err "Pick a real project name, not the placeholder."
            continue
        fi
        VAULT_PREFIX="$val"
        return
    done
}

prompt_app_name() {
    local default val
    default="${APP_NAME:-$(printf '%s' "$VAULT_PREFIX" | tr '[:upper:]' '[:lower:]')}"
    while :; do
        val="$(ask_input "App name (kebab-case, used as Docker container prefix)" "$default")"
        if [[ ! "$val" =~ ^[a-z0-9-]+$ ]]; then
            log_err "App name must be lowercase letters, digits, and dashes."
            continue
        fi
        APP_NAME="$val"
        return
    done
}

prompt_external_port() {
    local val default
    default="${EXTERNAL_PORT:-8000}"
    while :; do
        val="$(ask_input "External port (host port exposed for API)" "$default")"
        if [[ ! "$val" =~ ^[0-9]+$ ]] || [ "$val" -lt 1024 ] || [ "$val" -gt 65535 ]; then
            log_err "Port must be a number between 1024 and 65535."
            continue
        fi
        EXTERNAL_PORT="$val"
        return
    done
}

prompt_optional_sections() {
    local selected
    selected="$(ask_multichoose "Which optional sections do you want?" \
        "test" "sentry" "config")"
    OPTIONAL_SECTIONS="$(printf '%s' "$selected" | tr '\n' ',' | sed 's/,$//')"
}

step_collect_config() {
    print_header "Step 3 — Project configuration"
    prompt_vault_prefix
    prompt_app_name
    prompt_external_port

    print_header "Step 4 — Optional sections"
    log_info "Pick which optional secret groups you want to seed:"
    log_info "  • test   — TEST_DB_HOST/PORT/USER/PASSWORD/NAME"
    log_info "  • sentry — SENTRY_DSN, SENTRY_ENVIRONMENT"
    log_info "  • config — ENVIRONMENT, LOG_LEVEL, DB_PORT"
    prompt_optional_sections
}

# =============================================================================
# Step 5 + 6 — Vault create + item seeding
# =============================================================================
section_enabled() {
    case ",${OPTIONAL_SECTIONS}," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

generate_jwt_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    else
        head -c 32 /dev/urandom | xxd -p -c 256 | tr -d '\n'
    fi
}

generate_db_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 24 | tr -d '=+/' | head -c 24
    else
        head -c 32 /dev/urandom | base64 | tr -d '=+/' | head -c 24
    fi
}

env_suffix_upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

default_value_for() {
    local key="$1" env="$2"
    case "$key" in
        JWT_SECRET_KEY) generate_jwt_secret ;;
        DB_PASSWORD)    generate_db_password ;;
        DB_HOST)        case "$env" in local|test) echo "postgres" ;; prod) echo "" ;; esac ;;
        DB_USER)        echo "app_user" ;;
        DB_NAME)        case "$env" in local|test) echo "app_db" ;; prod) echo "" ;; esac ;;
        DB_PORT)        echo "5432" ;;
        ENVIRONMENT)    case "$env" in local) echo "local" ;; test) echo "test" ;; prod) echo "production" ;; esac ;;
        LOG_LEVEL)      case "$env" in local) echo "debug" ;; *) echo "info" ;; esac ;;
        TEST_DB_HOST)   case "$env" in local|test) echo "postgres" ;; prod) echo "" ;; esac ;;
        TEST_DB_USER)   echo "app_user" ;;
        TEST_DB_PASSWORD) generate_db_password ;;
        TEST_DB_NAME)   case "$env" in local|test) echo "app_db_test" ;; prod) echo "" ;; esac ;;
        TEST_DB_PORT)   echo "5432" ;;
        SENTRY_DSN)     echo "" ;;
        SENTRY_ENVIRONMENT) case "$env" in local) echo "local" ;; test) echo "test" ;; prod) echo "production" ;; esac ;;
        *) echo "" ;;
    esac
}

is_auto_generated() {
    case "$1" in JWT_SECRET_KEY|DB_PASSWORD|TEST_DB_PASSWORD) return 0 ;; *) return 1 ;; esac
}

create_or_reuse_vault() {
    local env="$1" vault
    vault="${VAULT_PREFIX}-$(env_suffix_upper "$env")"

    if op vault get "$vault" >/dev/null 2>&1; then
        log_info "Vault $vault already exists."
        local action
        action="$(ask_choose "What should I do with $vault?" "Use existing" "Recreate (deletes all items!)" "Skip this vault")"
        case "$action" in
            "Use existing")
                CREATED_VAULTS+=("$vault")
                ;;
            "Recreate"*)
                if ask_confirm "Really delete $vault and all its items?"; then
                    op vault delete "$vault"
                    if ! op vault create "$vault" >/dev/null; then
                        log_err "Failed to recreate vault $vault."
                        exit "$EXIT_VAULT_FAILED"
                    fi
                    CREATED_VAULTS+=("$vault")
                fi
                ;;
            "Skip"*)
                log_warn "Skipping $vault"
                return 1
                ;;
        esac
    else
        if ! ask_confirm "Create vault $vault?"; then
            log_warn "Skipping $vault"
            return 1
        fi
        if ! op vault create "$vault" >/dev/null; then
            log_err "Failed to create vault $vault."
            exit "$EXIT_VAULT_FAILED"
        fi
        CREATED_VAULTS+=("$vault")
    fi
    return 0
}

seed_item() {
    local vault="$1" env="$2" key="$3" value=""

    if op item get "$key" --vault "$vault" >/dev/null 2>&1; then
        local action
        action="$(ask_choose "$vault/$key exists. What now?" "Keep existing" "Overwrite" "Skip")"
        case "$action" in
            "Keep"*) return 0 ;;
            "Skip")  return 1 ;;
            "Overwrite") ;;
        esac
    fi

    if is_auto_generated "$key"; then
        if ask_confirm "Auto-generate a strong $key? (recommended)"; then
            value="$(default_value_for "$key" "$env")"
            log_info "$key: generated (value hidden)"
        else
            value="$(ask_password "Enter $key for $vault")"
        fi
    else
        local default
        default="$(default_value_for "$key" "$env")"
        if [ -n "$default" ]; then
            value="$(ask_input "$key for $vault" "$default")"
        else
            value="$(ask_input "$key for $vault" "")"
        fi
        if [ -z "$value" ]; then
            log_warn "$key left empty; skipping."
            return 1
        fi
    fi

    if op item get "$key" --vault "$vault" >/dev/null 2>&1; then
        op item edit "$key" --vault "$vault" "password=$value" >/dev/null
    else
        op item create --vault "$vault" --category password --title "$key" "password=$value" >/dev/null
    fi
    return 0
}

seed_vault_items() {
    local env="$1" vault count=0
    vault="${VAULT_PREFIX}-$(env_suffix_upper "$env")"

    local required=(JWT_SECRET_KEY DB_HOST DB_USER DB_PASSWORD DB_NAME)
    local optional_test=(TEST_DB_HOST TEST_DB_PORT TEST_DB_USER TEST_DB_PASSWORD TEST_DB_NAME)
    local optional_sentry=(SENTRY_DSN SENTRY_ENVIRONMENT)
    local optional_config=(ENVIRONMENT LOG_LEVEL DB_PORT)

    log_info "Seeding items into $vault..."
    for key in "${required[@]}"; do
        if seed_item "$vault" "$env" "$key"; then count=$((count + 1)); fi
    done
    if section_enabled "test"; then
        for key in "${optional_test[@]}"; do
            if seed_item "$vault" "$env" "$key"; then count=$((count + 1)); fi
        done
    fi
    if section_enabled "sentry"; then
        for key in "${optional_sentry[@]}"; do
            if seed_item "$vault" "$env" "$key"; then count=$((count + 1)); fi
        done
    fi
    if section_enabled "config"; then
        for key in "${optional_config[@]}"; do
            if seed_item "$vault" "$env" "$key"; then count=$((count + 1)); fi
        done
    fi

    VAULT_ITEM_SUMMARY+=("${vault}:${count}")
    log_ok "$vault: $count items processed"
}

step_create_and_seed_vaults() {
    print_header "Step 5 — Vaults"
    for env in local test prod; do
        if create_or_reuse_vault "$env"; then
            seed_vault_items "$env"
        fi
    done
}

# =============================================================================
# Step 7 — Persist .setup.config
# =============================================================================
write_config() {
    local mark_complete="${1:-0}"
    local tmp="${CONFIG_FILE}.tmp"
    {
        printf '# Generated by ./setup.sh — re-run the wizard to update.\n'
        printf 'VAULT_PREFIX=%s\n' "$VAULT_PREFIX"
        printf 'APP_NAME=%s\n'    "$APP_NAME"
        printf 'EXTERNAL_PORT=%s\n' "$EXTERNAL_PORT"
        printf 'OPTIONAL_SECTIONS=%s\n' "$OPTIONAL_SECTIONS"
        printf 'WIZARD_VERSION=%s\n' "$WIZARD_VERSION"
        printf 'SETUP_DATE=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        if [ "$mark_complete" = "1" ]; then
            printf 'SETUP_COMPLETE=1\n'
        fi
    } > "$tmp"
    mv "$tmp" "$CONFIG_FILE"
}

# =============================================================================
# Step 8 — Patch tracked files
# =============================================================================
patch_generate_env_sh() {
    if [ ! -f "$GENERATE_ENV_SCRIPT" ]; then
        log_warn "$GENERATE_ENV_SCRIPT missing; skipping patch."
        return 0
    fi
    if grep -q "SETUP_WIZARD_MANAGED" "$GENERATE_ENV_SCRIPT"; then
        log_ok "scripts/generate-env.sh already wizard-managed"
        return 0
    fi
    if ! grep -q '^VAULT_PREFIX="YOUR-PROJECT"$' "$GENERATE_ENV_SCRIPT"; then
        log_warn "scripts/generate-env.sh has been hand-edited; leaving it alone."
        return 0
    fi

    local tmp="${GENERATE_ENV_SCRIPT}.tmp"
    awk '
        /^VAULT_PREFIX="YOUR-PROJECT"$/ {
            print "# SETUP_WIZARD_MANAGED — VAULT_PREFIX sourced from .setup.config"
            print "_SETUP_CONFIG=\"$(cd \"$(dirname \"$0\")/..\" && pwd)/.setup.config\""
            print "if [ -f \"$_SETUP_CONFIG\" ]; then"
            print "  set -a; . \"$_SETUP_CONFIG\"; set +a"
            print "fi"
            print ": \"${VAULT_PREFIX:?VAULT_PREFIX not set — run ./setup.sh first}\""
            next
        }
        { print }
    ' "$GENERATE_ENV_SCRIPT" > "$tmp"

    mv "$tmp" "$GENERATE_ENV_SCRIPT"
    chmod +x "$GENERATE_ENV_SCRIPT"
    log_ok "Patched scripts/generate-env.sh"
}

patch_taskfile() {
    if [ ! -f "$TASKFILE" ]; then
        log_warn "$TASKFILE missing; skipping patch."
        return 0
    fi
    local tmp="${TASKFILE}.tmp"
    awk -v app_name="$APP_NAME" -v ext_port="$EXTERNAL_PORT" '
        /^  APP_NAME: fastapi-template$/ { print "  APP_NAME: " app_name; next }
        /^  EXTERNAL_PORT: "8000"$/      { print "  EXTERNAL_PORT: \"" ext_port "\""; next }
        { print }
    ' "$TASKFILE" > "$tmp"

    if cmp -s "$TASKFILE" "$tmp"; then
        log_ok "Taskfile.yml already up to date"
        rm -f "$tmp"
    else
        mv "$tmp" "$TASKFILE"
        log_ok "Patched Taskfile.yml (APP_NAME, EXTERNAL_PORT)"
    fi
}

step_patch_tracked_files() {
    print_header "Step 6 — Wire up scripts"
    patch_generate_env_sh
    patch_taskfile
}

# =============================================================================
# Step 9 — Verify end-to-end
# =============================================================================
step_verify() {
    print_header "Step 7 — Verify"

    if ! command -v task >/dev/null 2>&1; then
        log_warn "task not installed; skipping verification."
        return 0
    fi

    if ! run_with_label "Running task env:generate ENV=local..." -- task env:generate ENV=local; then
        log_err "Verification failed: task env:generate ENV=local did not succeed."
        exit "$EXIT_VERIFY_FAILED"
    fi

    local envfile="${REPO_ROOT}/.env.local"
    if [ ! -f "$envfile" ]; then
        log_err ".env.local was not produced."
        exit "$EXIT_VERIFY_FAILED"
    fi
    if ! grep -q '^DB_HOST=' "$envfile" || ! grep -q '^JWT_SECRET_KEY=' "$envfile"; then
        log_err ".env.local is missing required keys."
        exit "$EXIT_VERIFY_FAILED"
    fi
    log_ok ".env.local generated successfully"
}

# =============================================================================
# Step 9b — Detach from template (optional)
# =============================================================================
step_detach_git() {
    print_header "Step 8 — Detach from the template (optional)"

    if [ ! -d "${REPO_ROOT}/.git" ]; then
        log_info "No .git directory; nothing to detach."
        return 0
    fi

    local current_remote=""
    if git -C "$REPO_ROOT" remote | grep -q '^origin$'; then
        current_remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
    fi

    if [ -n "$current_remote" ]; then
        log_info "Current 'origin' remote: $current_remote"
    else
        log_info "No 'origin' remote configured."
    fi

    local action
    action="$(ask_choose "How would you like to handle git for this project?" \
        "Fresh start (wipe .git, re-init as a new project)" \
        "Unlink remote only (keep history, remove origin)" \
        "Leave it alone")"

    case "$action" in
        "Fresh start"*)
            log_warn "This deletes ALL git history (including the template's commits)."
            if ask_confirm "Wipe .git and reinitialize? This cannot be undone."; then
                rm -rf "${REPO_ROOT}/.git"
                git -C "$REPO_ROOT" init -b main >/dev/null
                log_ok "Fresh git repo initialized on branch 'main'."
                log_info "Next: git add -A && git commit -m 'Initial commit'"
                log_info "Then: git remote add origin <your-new-repo-url>"
            else
                log_info "Skipped — git history left intact."
            fi
            ;;
        "Unlink remote"*)
            if [ -n "$current_remote" ]; then
                git -C "$REPO_ROOT" remote remove origin
                log_ok "Removed 'origin' remote. History preserved."
                log_info "Add your new remote with: git remote add origin <url>"
            else
                log_info "No 'origin' remote to remove."
            fi
            ;;
        *)
            log_info "Leaving git as-is."
            ;;
    esac
}

# =============================================================================
# Step 10 — Final summary
# =============================================================================
step_summary() {
    local vault_list="(none)" count_lines=""
    if [ ${#CREATED_VAULTS[@]} -gt 0 ]; then
        vault_list="$(printf '  • %s\n' "${CREATED_VAULTS[@]}")"
    fi
    if [ ${#VAULT_ITEM_SUMMARY[@]} -gt 0 ]; then
        for entry in "${VAULT_ITEM_SUMMARY[@]}"; do
            count_lines+="  • ${entry%:*}: ${entry##*:} items
"
        done
    fi

    local body
    body=$(cat <<EOF
${C_BOLD}✓ Setup complete!${C_RESET}

Config:           $CONFIG_FILE
Vault prefix:     $VAULT_PREFIX
App name:         $APP_NAME
External port:    $EXTERNAL_PORT
Optional groups:  ${OPTIONAL_SECTIONS:-(none)}

Vaults:
$vault_list

Items seeded:
${count_lines:-  (none)}

Next steps:
  • task dev                       # start the development environment
  • open http://localhost:$EXTERNAL_PORT/docs
EOF
)

    printf '\n%s\n\n' "$body"
}

# =============================================================================
# Interrupt handler
# =============================================================================
on_interrupt() {
    printf '\n' >&2
    log_warn "Interrupted. Re-run ./setup.sh to start over."
    exit "$EXIT_INTERRUPT"
}
trap on_interrupt INT TERM

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"
    require_macos
    warn_if_already_setup
    install_homebrew_if_missing

    print_header "FastAPI + 1Password setup wizard"

    step_dep_check
    step_op_signin
    step_collect_config
    write_config 0
    step_create_and_seed_vaults
    step_patch_tracked_files
    write_config 1
    step_verify
    step_detach_git
    step_summary
}

main "$@"
