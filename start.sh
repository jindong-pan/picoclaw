#!/usr/bin/env bash
# =============================================================================
# start.sh — Load .env and start picoclaw gateway
# =============================================================================
# USAGE:
#   ./start.sh              # start gateway normally
#   ./start.sh --help       # pass any picoclaw flags through
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# .env can live in the project root (~/picoclaw/.env) OR ~/.picoclaw/.env
# We check both, project root takes priority
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
    echo "✓ Environment loaded from $ENV_FILE"
else
    echo "✗ No .env file found in $SCRIPT_DIR or ~/.picoclaw/"
    echo ""
    echo "  Run the migration first:"
    echo "    ~/picoclaw/scripts/migrate_secrets.sh"
    exit 1
fi

# ── Sanity check — warn if the most important key is missing ─────────────────
if [[ -z "${PICOCLAW_OPENROUTER_API_KEY:-}" && \
      -z "${PICOCLAW_ANTHROPIC_API_KEY:-}"  && \
      -z "${PICOCLAW_OPENAI_API_KEY:-}"     && \
      -z "${PICOCLAW_ZHIPU_API_KEY:-}"      && \
      -z "${PICOCLAW_GEMINI_API_KEY:-}" ]]; then
    echo "⚠  Warning: No LLM provider API key found in .env"
    echo "   Set at least one of: PICOCLAW_OPENROUTER_API_KEY, PICOCLAW_ANTHROPIC_API_KEY, etc."
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

echo "✓ Starting picoclaw gateway with binary: $PICOCLAW_BIN"
echo ""

exec "$PICOCLAW_BIN" gateway "$@"
