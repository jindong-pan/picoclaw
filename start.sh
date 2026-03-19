#!/usr/bin/env bash
# Load .env and start picoclaw gateway
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    echo "✓ Loaded environment from .env"
else
    echo "⚠ No .env file found at $ENV_FILE"
    echo "  Copy .env.template to .env and fill in your keys"
    exit 1
fi

exec picoclaw gateway "$@"
