#!/usr/bin/env bash
# =============================================================================
# migrate_secrets.sh — Extract secrets from config.json into a .env file
# =============================================================================
# WHAT THIS DOES:
#   1. Reads your existing ~/picoclaw/config.json
#   2. Extracts all API keys and tokens into ~/picoclaw/.env
#   3. Replaces the secrets in config.json with ${ENV_VAR} placeholders
#   4. Creates backups of both files before modifying anything
#   5. Adds .env to .gitignore
#
# SAFE TO RUN MULTIPLE TIMES — it never overwrites an existing .env.
#
# USAGE:
#   chmod +x migrate_secrets.sh
#   ./migrate_secrets.sh
# =============================================================================

set -euo pipefail

PROJECT="${1:-$HOME/picoclaw}"
CONFIG="$PROJECT/config.json"
ENV_FILE="$PROJECT/.env"
GITIGNORE="$PROJECT/.gitignore"
BACKUP_DIR="$PROJECT/.secrets_backup_$(date +%Y%m%d_%H%M%S)"

# Colors
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "  ${GREEN}✓${RESET} $1"; }
warn()  { echo -e "  ${YELLOW}!${RESET} $1"; }
error() { echo -e "  ${RED}✗${RESET} $1"; exit 1; }
step()  { echo -e "\n${CYAN}${BOLD}── $1${RESET}"; }

echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  PicoClaw Secret Migration Tool        ${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════${RESET}"

# ── Preflight ─────────────────────────────────────────────────────────────────
step "Preflight checks"

[[ -d "$PROJECT" ]]  || error "Project not found: $PROJECT"
[[ -f "$CONFIG"  ]]  || error "config.json not found: $CONFIG"

# Check for python3 or jq for JSON parsing
if command -v python3 &>/dev/null; then
    JSON_TOOL="python3"
    info "Using python3 for JSON parsing"
elif command -v jq &>/dev/null; then
    JSON_TOOL="jq"
    info "Using jq for JSON parsing"
else
    error "Neither python3 nor jq found. Install one: sudo apt install python3"
fi

if [[ -f "$ENV_FILE" ]]; then
    warn ".env already exists — will APPEND new keys only (won't overwrite existing values)"
else
    info ".env will be created fresh"
fi

# ── Backup ────────────────────────────────────────────────────────────────────
step "Creating backups"
mkdir -p "$BACKUP_DIR"
cp "$CONFIG" "$BACKUP_DIR/config.json.bak"
info "Backed up config.json → $BACKUP_DIR/config.json.bak"
if [[ -f "$ENV_FILE" ]]; then
    cp "$ENV_FILE" "$BACKUP_DIR/.env.bak"
    info "Backed up .env → $BACKUP_DIR/.env.bak"
fi

# ── Extract secrets using Python ──────────────────────────────────────────────
step "Extracting secrets from config.json"

python3 << 'PYEOF'
import json, os, sys, re

project = os.environ.get('PROJECT', os.path.expanduser('~/picoclaw'))
config_path = os.path.join(project, 'config.json')
env_path    = os.path.join(project, '.env')

with open(config_path) as f:
    raw = f.read()

try:
    cfg = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"  ✗ Could not parse config.json: {e}")
    sys.exit(1)

# Map of JSON paths -> env var names
# Format: (json_key_path, env_var_name)
MAPPINGS = [
    # model_list entries
    ("model_list[*].api_key",             None),  # handled dynamically below

    # providers
    ("providers.openrouter.api_key",      "PICOCLAW_OPENROUTER_API_KEY"),
    ("providers.anthropic.api_key",       "PICOCLAW_ANTHROPIC_API_KEY"),
    ("providers.openai.api_key",          "PICOCLAW_OPENAI_API_KEY"),
    ("providers.deepseek.api_key",        "PICOCLAW_DEEPSEEK_API_KEY"),
    ("providers.gemini.api_key",          "PICOCLAW_GEMINI_API_KEY"),
    ("providers.zhipu.api_key",           "PICOCLAW_ZHIPU_API_KEY"),
    ("providers.groq.api_key",            "PICOCLAW_GROQ_API_KEY"),
    ("providers.moonshot.api_key",        "PICOCLAW_MOONSHOT_API_KEY"),
    ("providers.qwen.api_key",            "PICOCLAW_QWEN_API_KEY"),
    ("providers.cerebras.api_key",        "PICOCLAW_CEREBRAS_API_KEY"),
    ("providers.nvidia.api_key",          "PICOCLAW_NVIDIA_API_KEY"),
    ("providers.volcengine.api_key",      "PICOCLAW_VOLCENGINE_API_KEY"),
    ("providers.litellm.api_key",         "PICOCLAW_LITELLM_API_KEY"),

    # channels
    ("channels.telegram.token",                    "PICOCLAW_TELEGRAM_TOKEN"),
    ("channels.discord.token",                     "PICOCLAW_DISCORD_TOKEN"),
    ("channels.slack.token",                       "PICOCLAW_SLACK_TOKEN"),
    ("channels.dingtalk.client_id",                "PICOCLAW_DINGTALK_CLIENT_ID"),
    ("channels.dingtalk.client_secret",            "PICOCLAW_DINGTALK_CLIENT_SECRET"),
    ("channels.line.channel_secret",               "PICOCLAW_LINE_CHANNEL_SECRET"),
    ("channels.line.channel_access_token",         "PICOCLAW_LINE_CHANNEL_ACCESS_TOKEN"),
    ("channels.wecom.token",                       "PICOCLAW_WECOM_TOKEN"),
    ("channels.wecom.encoding_aes_key",            "PICOCLAW_WECOM_ENCODING_AES_KEY"),
    ("channels.wecom_app.corp_secret",             "PICOCLAW_WECOM_APP_CORP_SECRET"),
    ("channels.wecom_app.token",                   "PICOCLAW_WECOM_APP_TOKEN"),
    ("channels.wecom_app.encoding_aes_key",        "PICOCLAW_WECOM_APP_ENCODING_AES_KEY"),
    ("channels.wecom_aibot.token",                 "PICOCLAW_WECOM_AIBOT_TOKEN"),
    ("channels.wecom_aibot.encoding_aes_key",      "PICOCLAW_WECOM_AIBOT_ENCODING_AES_KEY"),
    ("channels.qq.app_id",                         "PICOCLAW_QQ_APP_ID"),
    ("channels.qq.app_secret",                     "PICOCLAW_QQ_APP_SECRET"),
    ("channels.feishu.app_id",                     "PICOCLAW_FEISHU_APP_ID"),
    ("channels.feishu.app_secret",                 "PICOCLAW_FEISHU_APP_SECRET"),
    ("channels.feishu.encrypt_key",                "PICOCLAW_FEISHU_ENCRYPT_KEY"),
    ("channels.feishu.verification_token",         "PICOCLAW_FEISHU_VERIFICATION_TOKEN"),
    ("channels.whatsapp.bridge_token",             "PICOCLAW_WHATSAPP_BRIDGE_TOKEN"),

    # tools
    ("tools.web.proxy",                   "PICOCLAW_PROXY"),
    ("tools.web.brave.api_key",           "PICOCLAW_BRAVE_API_KEY"),
    ("tools.web.tavily.api_key",          "PICOCLAW_TAVILY_API_KEY"),
]

def get_nested(d, path):
    """Walk a dot-separated path into a dict, return (value, found)."""
    parts = path.split('.')
    cur = d
    for p in parts:
        if not isinstance(cur, dict) or p not in cur:
            return None, False
        cur = cur[p]
    return cur, True

def set_nested(d, path, value):
    """Walk a dot-separated path and set the value."""
    parts = path.split('.')
    cur = d
    for p in parts[:-1]:
        if p not in cur:
            return
        cur = cur[p]
    if parts[-1] in cur:
        cur[parts[-1]] = value

# Load existing .env to avoid duplicates
existing_env = {}
if os.path.exists(env_path):
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, _, v = line.partition('=')
                existing_env[k.strip()] = v.strip()

new_env_lines = []
new_env_lines.append("")
new_env_lines.append("# Auto-generated by migrate_secrets.sh on " + 
                      __import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S'))
new_env_lines.append("")

found_count = 0
placeholder_count = 0

# Process standard mappings
for path, env_var in MAPPINGS:
    value, found = get_nested(cfg, path)
    if not found or not value:
        continue
    # Skip if it's already a placeholder
    if isinstance(value, str) and value.startswith('${'):
        continue
    if not isinstance(value, str):
        value = str(value)
    # Skip empty or obviously fake values
    if value in ('', 'YOUR_API_KEY', 'your-api-key', 'xxx', 'sk-...'):
        continue

    print(f"  \033[0;32m✓\033[0m Found secret: {path} → {env_var}")
    found_count += 1

    # Write to .env only if not already there
    if env_var not in existing_env:
        new_env_lines.append(f"{env_var}={value}")
    else:
        print(f"    (skipped — {env_var} already in .env)")

    # Replace in config with placeholder
    set_nested(cfg, path, f"${{{env_var}}}")
    placeholder_count += 1

# Handle model_list api_keys dynamically
model_list = cfg.get('model_list', [])
for i, entry in enumerate(model_list):
    key = entry.get('api_key', '')
    if not key or key.startswith('${') or key in ('', 'YOUR_API_KEY'):
        continue
    model_name = entry.get('model_name', f'model_{i}').upper().replace('-', '_').replace('/', '_')
    env_var = f"PICOCLAW_MODEL_{model_name}_API_KEY"
    print(f"  \033[0;32m✓\033[0m Found model key: model_list[{i}].api_key → {env_var}")
    found_count += 1
    if env_var not in existing_env:
        new_env_lines.append(f"{env_var}={key}")
    cfg['model_list'][i]['api_key'] = f"${{{env_var}}}"
    placeholder_count += 1

new_env_lines.append("")

if found_count == 0:
    print("  \033[1;33m!\033[0m No plaintext secrets found in config.json (already clean or empty)")
else:
    # Append new keys to .env
    with open(env_path, 'a') as f:
        f.write('\n'.join(new_env_lines) + '\n')
    print(f"\n  \033[0;32m✓\033[0m Written {found_count} secret(s) to {env_path}")

    # Write updated config.json
    with open(config_path, 'w') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(f"  \033[0;32m✓\033[0m Updated config.json with {placeholder_count} placeholder(s)")

PYEOF
export PROJECT  # make it available to the python heredoc on next run if needed

# ── Update .gitignore ─────────────────────────────────────────────────────────
step "Updating .gitignore"

add_to_gitignore() {
    local entry="$1"
    if [[ -f "$GITIGNORE" ]] && grep -qF "$entry" "$GITIGNORE"; then
        info "Already in .gitignore: $entry"
    else
        echo "$entry" >> "$GITIGNORE"
        info "Added to .gitignore: $entry"
    fi
}

add_to_gitignore ".env"
add_to_gitignore "config.json"
add_to_gitignore ".secrets_backup_*"
add_to_gitignore "picoclaw"          # the debug binary found in scan
add_to_gitignore ".aider*"           # aider chat history files

# ── Remove config.json from git tracking (if tracked) ────────────────────────
step "Removing secrets from git history tracking"

if git -C "$PROJECT" ls-files --error-unmatch config.json &>/dev/null 2>&1; then
    git -C "$PROJECT" rm --cached config.json
    warn "config.json was tracked by git — removed from index (file kept on disk)"
    warn "Run 'git commit -m \"remove config.json from tracking\"' to finalize"
else
    info "config.json is not tracked by git — nothing to remove"
fi

if git -C "$PROJECT" ls-files --error-unmatch .env &>/dev/null 2>&1; then
    git -C "$PROJECT" rm --cached .env
    warn ".env was tracked by git — removed from index"
else
    info ".env is not tracked by git — good"
fi

# ── Create launcher that loads .env ──────────────────────────────────────────
step "Creating .env-aware launcher scripts"

cat > "$PROJECT/start.sh" << 'EOF'
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
EOF
chmod +x "$PROJECT/start.sh"
info "Created start.sh — use this instead of 'picoclaw gateway'"

cat > "$PROJECT/agent.sh" << 'EOF'
#!/usr/bin/env bash
# Load .env and run picoclaw agent
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

exec picoclaw agent "$@"
EOF
chmod +x "$PROJECT/agent.sh"
info "Created agent.sh — use this instead of 'picoclaw agent'"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Migration Complete                     ${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════${RESET}"
echo ""
echo -e "  Backups saved : ${BOLD}$BACKUP_DIR${RESET}"
echo -e "  Secrets file  : ${BOLD}$PROJECT/.env${RESET}  ← keep this private"
echo -e "  Clean config  : ${BOLD}$PROJECT/config.json${RESET}  ← safe to commit"
echo ""
echo -e "  ${CYAN}${BOLD}Next steps:${RESET}"
echo "    1. Verify .env has all your keys:  cat ~/picoclaw/.env"
echo "    2. Test it works:                  ./start.sh"
echo "    3. Revoke your old OpenRouter key: https://openrouter.ai/keys"
echo "    4. Generate a new key and add it:  echo 'PICOCLAW_OPENROUTER_API_KEY=sk-or-v1-newkey' >> ~/picoclaw/.env"
echo "    5. Commit the clean config:        git add config.json .gitignore && git commit -m 'chore: move secrets to .env'"
echo ""
echo -e "  ${YELLOW}⚠  IMPORTANT: Your .env is NOT committed to git.${RESET}"
echo -e "  ${YELLOW}   Back it up somewhere secure (password manager, etc.)${RESET}"
echo ""
