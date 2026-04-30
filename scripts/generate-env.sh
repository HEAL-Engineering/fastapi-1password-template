#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# CONFIGURATION - Modify vault prefix for your project
# =============================================================================
VAULT_PREFIX="YOUR-PROJECT"
# Vaults expected: YOUR-PROJECT-LOCAL, YOUR-PROJECT-TEST, YOUR-PROJECT-PROD
# =============================================================================

ENV="${1:-local}"

# Map environment to vault name
case "$ENV" in
    local) VAULT="${VAULT_PREFIX}-LOCAL" ;;
    test)  VAULT="${VAULT_PREFIX}-TEST" ;;
    prod)  VAULT="${VAULT_PREFIX}-PROD" ;;
    *)     echo "Unknown environment: $ENV"; exit 1 ;;
esac

OUTPUT_FILE=".env.${ENV}"

echo "Generating $OUTPUT_FILE from 1Password vault: $VAULT"

# Create .env file with header
cat > "$OUTPUT_FILE" << EOF
# Environment: ${ENV}
# Source: 1Password/${VAULT}
# Generated: $(date)
# DO NOT COMMIT THIS FILE TO GIT

EOF

# Fetch all secrets in parallel (up to 10 concurrent)
# Uses positional params to avoid shell injection from item titles
op item list --vault="$VAULT" --format json | \
    jq -r '.[].title' | \
    xargs -P 10 -I {} sh -c '
        ITEM="$1"
        VALUE=$(op read "op://'"$VAULT"'/${ITEM}/password" 2>/dev/null) || {
            echo "⚠️  Failed to read ${ITEM}" >&2
            exit 0
        }
        if [ -n "$VALUE" ]; then echo "${ITEM}=$VALUE"; fi
    ' _ {} >> "$OUTPUT_FILE"

VAR_COUNT=$(grep -c '^[A-Z_]' "$OUTPUT_FILE" || echo "0")
echo "✅ Generated $OUTPUT_FILE with $VAR_COUNT variables"
