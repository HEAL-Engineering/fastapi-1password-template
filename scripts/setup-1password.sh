#!/usr/bin/env bash
set -euo pipefail

echo "1Password Setup"
echo "==============="
echo ""

# Install dependencies
echo "Checking dependencies..."

if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo "✓ Homebrew installed"
fi

if ! command -v op >/dev/null 2>&1; then
    echo "Installing 1Password CLI..."
    brew install --cask 1password-cli
else
    echo "✓ 1Password CLI installed"
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Installing jq..."
    brew install jq
else
    echo "✓ jq installed"
fi

echo ""

# Sign in to 1Password
if ! op account list >/dev/null 2>&1; then
    echo "Sign in to 1Password CLI"
    echo ""
    echo "To enable Touch ID:"
    echo "  1. Open 1Password app"
    echo "  2. Go to Settings → Security"
    echo "  3. Under 'Unlock', enable Touch ID"
    echo ""
    echo "You'll need:"
    echo "  • Your 1Password account email"
    echo "  • Your Secret Key (from Emergency Kit)"
    echo "  • Your Master Password"
    echo ""
    op signin
else
    echo "✓ Already signed in to 1Password"
fi

echo ""
echo "Setup complete! Run 'task env:generate' to generate .env files."
