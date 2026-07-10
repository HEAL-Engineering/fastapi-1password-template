# =============================================================================
# Shared helpers for setup.sh and onboard.sh (macOS-only).
#
# Sourced, not executed. Callers should `set -euo pipefail` themselves;
# this file is safe to source under those flags.
# =============================================================================

# Exit code defaults — only set if the caller didn't already define them.
: "${EXIT_UNSUPPORTED_OS:=2}"
: "${EXIT_TOOL_DECLINED:=3}"
: "${EXIT_OP_SIGNIN:=4}"

# -----------------------------------------------------------------------------
# Colors + logging
# -----------------------------------------------------------------------------
C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'
C_CYAN=$'\033[36m'

log_info() { printf '%s→ %s%s\n' "$C_BLUE"   "$*" "$C_RESET"; }
log_ok()   { printf '%s✓ %s%s\n' "$C_GREEN"  "$*" "$C_RESET"; }
log_warn() { printf '%s! %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
log_err()  { printf '%s✗ %s%s\n' "$C_RED"    "$*" "$C_RESET" >&2; }

print_header() {
    local text="$1"
    printf '\n\n%s%s%s%s\n' "$C_BOLD" "$C_CYAN" "$text" "$C_RESET"
    printf '%s\n' "$(printf '%*s' "${#text}" | tr ' ' '-')"
}

print_box() {
    printf '\n%s\n' "$1"
}

# -----------------------------------------------------------------------------
# Prompts
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# macOS guard
# -----------------------------------------------------------------------------
require_macos() {
    if [ "$(uname -s)" != "Darwin" ]; then
        log_err "This wizard is macOS-only. Detected: $(uname -s)"
        exit "$EXIT_UNSUPPORTED_OS"
    fi
}

# -----------------------------------------------------------------------------
# Homebrew bootstrap
# -----------------------------------------------------------------------------
install_homebrew_if_missing() {
    if command -v brew >/dev/null 2>&1; then return 0; fi

    printf 'Homebrew is required but not installed.\n'
    local ans
    read -r -p "Install Homebrew now? [Y/n] " ans
    case "$ans" in n|N) log_err "Cannot continue without Homebrew."; exit "$EXIT_TOOL_DECLINED" ;; esac

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [ -x /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -x /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

# -----------------------------------------------------------------------------
# Generic tool install via brew
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Docker: install if missing, launch Docker Desktop, poll until daemon is up
# -----------------------------------------------------------------------------
ensure_docker() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        log_ok "docker installed and daemon running"
        return 0
    fi

    if ! command -v docker >/dev/null 2>&1; then
        if ! ask_confirm "Docker not installed. Install Docker Desktop via brew?"; then
            exit "$EXIT_TOOL_DECLINED"
        fi
        brew install --cask docker
        open -a Docker || true
        log_info "Launching Docker Desktop — finish first-run setup if prompted."
    else
        log_warn "Docker is installed but the daemon isn't running."
        open -a Docker || true
    fi

    local tries=0
    until docker info >/dev/null 2>&1; do
        tries=$((tries + 1))
        if [ "$tries" -gt 30 ]; then
            log_err "Docker daemon never came up."
            ask_confirm "Continue without Docker?" || exit "$EXIT_TOOL_DECLINED"
            return 0
        fi
        sleep 2
    done
    log_ok "docker daemon running"
}

# -----------------------------------------------------------------------------
# 1Password sign-in loop (3 attempts)
# -----------------------------------------------------------------------------
ensure_op_signed_in() {
    local attempt=1 max=3
    while [ $attempt -le $max ]; do
        if op account list >/dev/null 2>&1; then return 0; fi

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

# -----------------------------------------------------------------------------
# 1Password account picker
#
# Sets: OP_ACCOUNT (uuid) and OP_ACCOUNT_LABEL (human-readable),
#       and exports OP_ACCOUNT so subsequent op calls target it.
#
# When multiple accounts are present, also peeks at each account's vault list
# to help disambiguate accounts that share email+URL. Locked accounts are
# offered a one-time unlock so their vaults can be shown.
# -----------------------------------------------------------------------------
prompt_op_account() {
    local accounts_json count
    accounts_json="$(op account list --format json 2>/dev/null || echo '[]')"
    count="$(printf '%s' "$accounts_json" | jq 'length')"

    if [ "$count" -eq 0 ]; then
        log_err "No 1Password accounts are added to op. Run 'op account add' first."
        exit "$EXIT_OP_SIGNIN"
    fi

    if [ "$count" -eq 1 ]; then
        local email url uuid
        email="$(printf '%s' "$accounts_json" | jq -r '.[0].email')"
        url="$(  printf '%s' "$accounts_json" | jq -r '.[0].url')"
        uuid="$( printf '%s' "$accounts_json" | jq -r '.[0].user_uuid')"
        log_info "Found one 1Password account: $email @ $url"
        if ! ask_confirm "Use this account?"; then
            log_err "Aborted. Add or switch accounts via 'op account add', then re-run."
            exit "$EXIT_OP_SIGNIN"
        fi
        OP_ACCOUNT="$uuid"
        OP_ACCOUNT_LABEL="$email @ $url"
        export OP_ACCOUNT
        log_ok "Using $OP_ACCOUNT_LABEL"
        return 0
    fi

    printf '\n%sMultiple 1Password accounts detected.%s\n' "$C_BOLD" "$C_RESET" >&2
    printf 'Showing vaults in each account so you can tell them apart:\n' >&2
    printf '%s(If an unlock prompt appears for an account you don'\''t plan to use, cancel it once — it won'\''t re-prompt.)%s\n' "$C_DIM" "$C_RESET" >&2

    # Each account's vault list is fetched exactly once. A locked account
    # triggers at most one desktop-app unlock prompt (the initial list attempt);
    # declining it just hides that account's vaults — no second prompt.
    local i uuid email url short_uuid
    local uuids=() labels=() vaults_json vaults
    for i in $(seq 0 $((count - 1))); do
        email="$(printf '%s' "$accounts_json" | jq -r ".[$i].email")"
        url="$(  printf '%s' "$accounts_json" | jq -r ".[$i].url")"
        uuid="$( printf '%s' "$accounts_json" | jq -r ".[$i].user_uuid")"
        short_uuid="$(printf '%s' "$uuid" | cut -c1-8)"

        vaults_json="$(op vault list --account "$uuid" --format json 2>/dev/null || true)"
        if [ -z "$vaults_json" ]; then
            log_warn "Account [$short_uuid] $email @ $url is locked."
            if ask_confirm "Unlock it (Touch ID / master password) to show its vaults?"; then
                vaults_json="$(op vault list --account "$uuid" --format json 2>/dev/null || true)"
                [ -z "$vaults_json" ] && log_warn "Unlock failed — this account will show without vault info."
            fi
        fi

        vaults="$(printf '%s' "$vaults_json" | jq -r 'map(.name) | join(", ")' 2>/dev/null || true)"
        if [ -z "$vaults" ]; then
            vaults="(locked — vaults hidden)"
        elif [ "${#vaults}" -gt 90 ]; then
            vaults="$(printf '%s' "$vaults" | cut -c1-87)..."
        fi

        uuids+=("$uuid")
        labels+=("$email @ $url  [${short_uuid}]")

        printf '\n  %d) %s @ %s  %s[%s]%s\n' "$((i + 1))" "$email" "$url" "$C_DIM" "$short_uuid" "$C_RESET" >&2
        printf '       %svaults:%s %s\n' "$C_DIM" "$C_RESET" "$vaults" >&2
    done

    printf '\n' >&2
    local choice
    while :; do
        read -r -p "Pick an account [1]: " choice
        [ -z "$choice" ] && choice=1
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
            break
        fi
        log_err "Enter a number 1-$count."
    done

    local idx=$((choice - 1))
    OP_ACCOUNT="${uuids[$idx]}"
    OP_ACCOUNT_LABEL="${labels[$idx]}"
    export OP_ACCOUNT
    log_ok "Using account: $OP_ACCOUNT_LABEL"
}
