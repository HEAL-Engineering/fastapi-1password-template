#!/usr/bin/env bash
# =============================================================================
# Onboard a teammate into an existing project (macOS-only).
#
# Use this when someone else already ran ./setup.sh for this project and you
# just cloned the repo. It will:
#   • install required tools (brew, op, jq, task, docker)
#   • sign you into 1Password and pick your account
#   • let you pick the project's shared 1Password vault
#   • write .setup.config so Taskfile.yml works
#   • generate .env.local from the vault
#
# If you're the original project owner, run ./setup.sh instead.
#
#   ./onboard.sh           run onboarding (warns if .setup.config already exists)
#   ./onboard.sh --help    show this help
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Globals
# -----------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${REPO_ROOT}/.setup.config"

VAULT_PREFIX=""
VAULT_NAME=""
APP_NAME=""
EXTERNAL_PORT=""
OP_ACCOUNT=""
OP_ACCOUNT_LABEL=""

# Exit codes
EXIT_OK=0
EXIT_GENERIC=1
EXIT_UNSUPPORTED_OS=2
EXIT_TOOL_DECLINED=3
EXIT_OP_SIGNIN=4
EXIT_NO_VAULT=5
EXIT_GENERATE_FAILED=6
EXIT_BAD_ARGS=64
EXIT_INTERRUPT=130

# Shared helpers (colors, logging, prompts, brew/op/docker bootstrap).
# shellcheck source=scripts/lib.sh
source "${REPO_ROOT}/scripts/lib.sh"

# =============================================================================
# Argument parsing & help
# =============================================================================
print_help() {
    cat <<'EOF'
Onboard a teammate into an existing project (macOS-only).

Use this when someone else already ran ./setup.sh for this project and you
just cloned the repo. The wizard will install dependencies, sign you into
1Password, let you pick the project's shared vault, write .setup.config,
and generate .env.local.

If you're the original project owner, run ./setup.sh instead.

Usage:
  ./onboard.sh           run onboarding (warns if .setup.config already exists)
  ./onboard.sh --help    show this help
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
# Step 0 — warn if already onboarded
# =============================================================================
warn_if_already_onboarded() {
    [ ! -f "$CONFIG_FILE" ] && return

    log_warn ".setup.config already exists at $CONFIG_FILE"
    log_info "If you're already onboarded, just run: task start"
    log_info "Re-running onboarding will overwrite the existing config."
    if ! ask_confirm "Overwrite the existing .setup.config?"; then
        log_info "Aborted. Nothing was changed."
        exit "$EXIT_OK"
    fi
}

# =============================================================================
# Step 1 — Dependencies
# =============================================================================
step_dep_check() {
    print_header "Step 1 — Dependencies"
    ensure_tool "op"   "--cask 1password-cli"
    ensure_tool "jq"   "jq"
    ensure_tool "task" "go-task"
    ensure_docker
}

# =============================================================================
# Step 2 — 1Password sign-in + account selection
# =============================================================================
step_op_signin() {
    print_header "Step 2 — Sign in to 1Password"
    ensure_op_signed_in
    prompt_op_account
}

# =============================================================================
# Step 3 — Pick the project's vault
# =============================================================================
step_pick_vault() {
    print_header "Step 3 — Pick the project's vault"
    log_info "Looking for the LOCAL development vault for this project."

    local vaults_json vault_total
    vaults_json="$(op vault list --format json 2>/dev/null || echo '[]')"
    vault_total="$(printf '%s' "$vaults_json" | jq 'length')"

    if [ "$vault_total" -eq 0 ]; then
        log_err "No vaults are visible in this account."
        log_info "Ask your teammate to invite you to the project's 1Password vault, then re-run ./onboard.sh."
        exit "$EXIT_NO_VAULT"
    fi

    local local_vaults_json local_count
    local_vaults_json="$(printf '%s' "$vaults_json" | jq '[.[] | select(.name | endswith("-LOCAL"))]')"
    local_count="$(printf '%s' "$local_vaults_json" | jq 'length')"

    local choice name
    if [ "$local_count" -gt 0 ]; then
        printf '\nVaults ending in -LOCAL:\n'
        for i in $(seq 0 $((local_count - 1))); do
            name="$(printf '%s' "$local_vaults_json" | jq -r ".[$i].name")"
            printf '  %d) %s\n' "$((i + 1))" "$name"
        done
        printf '  %d) %sNone of these — show all vaults%s\n' "$((local_count + 1))" "$C_DIM" "$C_RESET"
        while :; do
            read -r -p "Pick vault [1]: " choice
            [ -z "$choice" ] && choice=1
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $((local_count + 1)) ]; then
                break
            fi
            log_err "Enter a number 1-$((local_count + 1))."
        done
        if [ "$choice" -le "$local_count" ]; then
            VAULT_NAME="$(printf '%s' "$local_vaults_json" | jq -r ".[$((choice - 1))].name")"
        fi
    fi

    if [ -z "$VAULT_NAME" ]; then
        printf '\nAll visible vaults:\n'
        for i in $(seq 0 $((vault_total - 1))); do
            name="$(printf '%s' "$vaults_json" | jq -r ".[$i].name")"
            printf '  %d) %s\n' "$((i + 1))" "$name"
        done
        while :; do
            read -r -p "Pick vault: " choice
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$vault_total" ]; then
                break
            fi
            log_err "Enter a number 1-$vault_total."
        done
        VAULT_NAME="$(printf '%s' "$vaults_json" | jq -r ".[$((choice - 1))].name")"
    fi

    # Strip -LOCAL/-TEST/-PROD suffix to get the vault prefix Taskfile expects.
    if [[ "$VAULT_NAME" =~ ^(.+)-(LOCAL|TEST|PROD)$ ]]; then
        VAULT_PREFIX="${BASH_REMATCH[1]}"
        log_ok "Vault prefix: $VAULT_PREFIX"
    else
        log_warn "Vault '$VAULT_NAME' doesn't follow the <PREFIX>-LOCAL convention."
        VAULT_PREFIX="$(ask_input "Enter the vault prefix manually" "$VAULT_NAME")"
    fi
}

# =============================================================================
# Step 4 — Project settings
# =============================================================================
step_collect_config() {
    print_header "Step 4 — Project settings"
    log_info "If your teammate told you specific values, use them. Otherwise the defaults are fine."

    local default_app
    default_app="$(printf '%s' "$VAULT_PREFIX" | tr '[:upper:]' '[:lower:]')"
    printf '\n'
    APP_NAME="$(ask_input "App name (Docker container prefix)" "$default_app")"
    printf '\n'
    EXTERNAL_PORT="$(ask_input "External port for the API" "8000")"
}

# =============================================================================
# Step 5 — Write .setup.config
# =============================================================================
write_config() {
    print_header "Step 5 — Write .setup.config"

    local tmp="${CONFIG_FILE}.tmp"
    {
        printf '# Generated by ./onboard.sh — re-run the wizard to update.\n'
        printf 'VAULT_PREFIX=%s\n'  "$VAULT_PREFIX"
        printf 'APP_NAME=%s\n'      "$APP_NAME"
        printf 'EXTERNAL_PORT=%s\n' "$EXTERNAL_PORT"
        printf 'OP_ACCOUNT=%s\n'    "$OP_ACCOUNT"
        printf 'ONBOARDED=1\n'
        printf 'ONBOARD_DATE=%s\n'  "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$tmp"
    mv "$tmp" "$CONFIG_FILE"
    log_ok "Wrote $CONFIG_FILE"
}

# =============================================================================
# Step 6 — Generate .env.local
# =============================================================================
step_generate_env() {
    print_header "Step 6 — Generate .env.local from the vault"

    if ! task env:generate ENV=local; then
        log_err "Failed to generate .env.local."
        log_info "The most likely cause is that the vault has no items yet, or your account doesn't have read access."
        log_info "Check with your teammate, then re-run: task env:generate ENV=local"
        exit "$EXIT_GENERATE_FAILED"
    fi

    local envfile="${REPO_ROOT}/.env.local"
    if [ ! -s "$envfile" ] || ! grep -q '^[A-Z_]' "$envfile"; then
        log_warn ".env.local was created but appears empty — check that the vault ${VAULT_PREFIX}-LOCAL has items."
    fi
}

# =============================================================================
# Summary
# =============================================================================
step_summary() {
    printf '\n%s%s✓ Onboarded!%s\n\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
    printf 'Config:        %s\n' "$CONFIG_FILE"
    printf 'Vault prefix:  %s\n' "$VAULT_PREFIX"
    printf 'App name:      %s\n' "$APP_NAME"
    printf 'External port: %s\n' "$EXTERNAL_PORT"
    printf '1P account:    %s\n' "${OP_ACCOUNT_LABEL:-(default)}"
    printf '\n'
    printf 'Next steps:\n'
    printf '  • task start                      # start the dev environment\n'
    printf '  • open http://localhost:%s/docs   # API docs once it'\''s up\n' "$EXTERNAL_PORT"
    printf '  • task --list                     # see all available tasks\n'
}

# =============================================================================
# Interrupt handler
# =============================================================================
on_interrupt() {
    printf '\n' >&2
    log_warn "Interrupted. Re-run ./onboard.sh to start over."
    exit "$EXIT_INTERRUPT"
}
trap on_interrupt INT TERM

# =============================================================================
# Main
# =============================================================================
main() {
    parse_args "$@"
    require_macos
    warn_if_already_onboarded
    install_homebrew_if_missing

    print_header "Onboarding wizard"
    log_info "This sets you up to work on an existing project that a teammate already configured."
    log_info "You'll need to be invited to the project's 1Password vault before continuing."

    step_dep_check
    step_op_signin
    step_pick_vault
    step_collect_config
    write_config
    step_generate_env
    step_summary
}

main "$@"
