#!/usr/bin/env bash
# =============================================================================
# agent.sh — Load .env and run picoclaw agent
# =============================================================================
# USAGE:
#   ./agent.sh                        # interactive chat mode
#   ./agent.sh -m "What is 2+2?"      # one-shot message
#   ./agent.sh -m "hello" --debug     # pass any picoclaw flags through
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .env can live in the project root (~/picoclaw/.env) OR ~/.picoclaw/.env
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    ENV_FILE="$SCRIPT_DIR/.env"
elif [[ -f "$HOME/.picoclaw/.env" ]]; then
    ENV_FILE="$HOME/.picoclaw/.env"
else
    ENV_FILE=""
fi

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ -n "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
else
    echo "⚠  No .env found in $SCRIPT_DIR or ~/.picoclaw/ — continuing with current environment."
fi

# ── Find the picoclaw binary ──────────────────────────────────────────────────
if command -v picoclaw &>/dev/null; then
    PICOCLAW_BIN="picoclaw"
elif [[ -x "$SCRIPT_DIR/build/picoclaw-linux-amd64" ]]; then
    PICOCLAW_BIN="$SCRIPT_DIR/build/picoclaw-linux-amd64"
elif [[ -x "$SCRIPT_DIR/build/picoclaw-linux-arm64" ]]; then
    PICOCLAW_BIN="$SCRIPT_DIR/build/picoclaw-linux-arm64"
else
    echo "✗ picoclaw binary not found."
    echo "  Build it first:  make build"
    exit 1
fi

exec "$PICOCLAW_BIN" agent "$@"
