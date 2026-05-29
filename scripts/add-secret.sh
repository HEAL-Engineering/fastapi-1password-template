#!/usr/bin/env bash
set -euo pipefail

# Interactive helper to add a new secret to a 1Password vault and (optionally)
# declare a matching field in backend/app/core/config.py.
#
# Invoked via `task env:add`. Run from the repo root.

CONFIG_FILE="backend/app/core/config.py"
SENTINEL="# === task env:add inserts new settings above this line ==="

# Vault names derive from VAULT_PREFIX in .setup.config (written by ./setup.sh).
_SETUP_CONFIG="$(cd "$(dirname "$0")/.." && pwd)/.setup.config"
if [ -f "$_SETUP_CONFIG" ]; then
    set -a; . "$_SETUP_CONFIG"; set +a
fi
: "${VAULT_PREFIX:?VAULT_PREFIX not set — run ./setup.sh first to configure}"

if ! command -v op >/dev/null 2>&1; then
    echo "❌ 1Password CLI not installed. Run: ./setup.sh" >&2
    exit 1
fi
if ! op account list >/dev/null 2>&1; then
    echo "❌ Not signed in to 1Password. Run: op signin" >&2
    exit 1
fi

echo "Select vault:"
echo "  1) ${VAULT_PREFIX}-LOCAL"
echo "  2) ${VAULT_PREFIX}-TEST"
echo "  3) ${VAULT_PREFIX}-PROD"
read -rp "Choice [1-3]: " choice
case "$choice" in
    1) VAULT="${VAULT_PREFIX}-LOCAL" ;;
    2) VAULT="${VAULT_PREFIX}-TEST" ;;
    3) VAULT="${VAULT_PREFIX}-PROD" ;;
    *) echo "Invalid choice." >&2; exit 1 ;;
esac

read -rp "Variable name (e.g. MY_NEW_VAR): " VAR_NAME
if [ -z "${VAR_NAME:-}" ]; then
    echo "Variable name required." >&2
    exit 1
fi
if ! [[ "$VAR_NAME" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
    echo "Variable name must be UPPER_SNAKE_CASE (letters, digits, underscores)." >&2
    exit 1
fi

read -rsp "Value (hidden): " VAR_VALUE
echo
if [ -z "${VAR_VALUE:-}" ]; then
    echo "Value required." >&2
    exit 1
fi
if [[ "$VAR_VALUE" =~ [[:space:]] ]]; then
    echo "Value must not contain whitespace (spaces, tabs, or LF/CR)." >&2
    exit 1
fi
if [[ "$VAR_VALUE" == *'`'* ]]; then
    echo "Value must not contain backticks." >&2
    exit 1
fi

if op item get "$VAR_NAME" --vault="$VAULT" >/dev/null 2>&1; then
    read -rp "Item '$VAR_NAME' already exists in $VAULT. Overwrite? [y/N]: " overwrite
    case "${overwrite:-}" in
        y|Y)
            echo "Updating $VAR_NAME in $VAULT..."
            op item edit "$VAR_NAME" --vault="$VAULT" "password=$VAR_VALUE" >/dev/null
            ;;
        *)
            echo "Aborted." >&2
            exit 1
            ;;
    esac
else
    echo "Creating $VAR_NAME in $VAULT..."
    op item create \
        --category=password \
        --title="$VAR_NAME" \
        --vault="$VAULT" \
        "password=$VAR_VALUE" >/dev/null
fi
echo "✅ $VAR_NAME uploaded to $VAULT"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ℹ️  $CONFIG_FILE not found — skipping config.py update."
    exit 0
fi

PY_NAME=$(echo "$VAR_NAME" | tr '[:upper:]' '[:lower:]')
if grep -qE "^[[:space:]]+${PY_NAME}[[:space:]]*:" "$CONFIG_FILE"; then
    echo "ℹ️  ${PY_NAME} already declared in ${CONFIG_FILE} — skipping."
    exit 0
fi

read -rp "Add '${PY_NAME}: str | None = None' to ${CONFIG_FILE}? [y/N]: " add_config
case "${add_config:-}" in
    y|Y) ;;
    *) echo "Skipped config.py update."; exit 0 ;;
esac

if ! grep -qF "$SENTINEL" "$CONFIG_FILE"; then
    echo "❌ Sentinel not found in ${CONFIG_FILE}:" >&2
    echo "    ${SENTINEL}" >&2
    echo "   Add the sentinel comment back in (or insert the field by hand)." >&2
    exit 1
fi

python3 - "$CONFIG_FILE" "$PY_NAME" "$SENTINEL" <<'PYEOF'
import sys

path, name, sentinel = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    lines = f.readlines()

anchor = next((i for i, ln in enumerate(lines) if sentinel in ln), None)
if anchor is None:
    sys.exit("sentinel disappeared between checks")

indent = lines[anchor][: len(lines[anchor]) - len(lines[anchor].lstrip())]
new_field = f"{indent}{name}: str | None = None\n"
lines.insert(anchor, new_field)

with open(path, "w") as f:
    f.writelines(lines)
PYEOF

echo "✅ Added '${PY_NAME}: str | None = None' to ${CONFIG_FILE}"
echo ""
echo "Next steps:"
echo "  • Regenerate the matching .env file: task env:generate ENV=<env>"
echo "  • If you want a non-default type/default, edit ${CONFIG_FILE} directly."
