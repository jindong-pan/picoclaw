#!/usr/bin/env bash
# =============================================================================
# migrate_secrets.sh — Extract secrets from ~/.picoclaw/config.json into .env
# =============================================================================
# Reads  : ~/.picoclaw/config.json   (your working config)
# Writes : ~/picoclaw/.env           (gitignored, in your git repo)
# =============================================================================

set -euo pipefail

CONFIG="${HOME}/.picoclaw/config.json"
ENV_FILE="${HOME}/picoclaw/.env"
GITIGNORE="${HOME}/picoclaw/.gitignore"
BACKUP="${HOME}/picoclaw/.secrets_backup_$(date +%Y%m%d_%H%M%S)"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info() { echo -e "  ${GREEN}✓${RESET} $1"; }
warn() { echo -e "  ${YELLOW}!${RESET} $1"; }
step() { echo -e "\n${CYAN}${BOLD}── $1${RESET}"; }

echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  PicoClaw Secret Migration             ${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════${RESET}"
echo ""
echo -e "  Reads  : ${BOLD}$CONFIG${RESET}"
echo -e "  Writes : ${BOLD}$ENV_FILE${RESET}"

[[ -f "$CONFIG" ]] || { echo -e "${RED}✗ Not found: $CONFIG${RESET}"; exit 1; }

# ── Backup ────────────────────────────────────────────────────────────────────
step "Backing up"
mkdir -p "$BACKUP"
cp "$CONFIG" "$BACKUP/config.json.bak"
[[ -f "$ENV_FILE" ]] && cp "$ENV_FILE" "$BACKUP/.env.bak"
info "Backup saved → $BACKUP"

# ── Extract & replace in one Python pass ─────────────────────────────────────
step "Extracting secrets"

python3 - "$CONFIG" "$ENV_FILE" << 'PYEOF'
import json, sys, os
from datetime import datetime

config_path = sys.argv[1]
env_path    = sys.argv[2]

with open(config_path) as f:
    cfg = json.load(f)

# ── Helpers ───────────────────────────────────────────────────────────────────
FAKE = {
    '', 'YOUR_API_KEY', 'your-api-key', 'xxx', 'gsk_xxx', 'nvapi-xxx',
    'pplx-xxx', 'YOUR_BRAVE_API_KEY', 'YOUR_ZHIPU_API_KEY',
    'YOUR_TOKEN', 'YOUR_CLIENT_ID', 'YOUR_CLIENT_SECRET',
    'YOUR_QQ_APP_ID', 'YOUR_QQ_APP_SECRET',
    'YOUR_43_CHAR_ENCODING_AES_KEY', 'YOUR_CORP_ID', 'YOUR_CORP_SECRET',
    'YOUR_LINE_CHANNEL_SECRET', 'YOUR_LINE_CHANNEL_ACCESS_TOKEN',
    'xapp-YOUR-APP-TOKEN', 'xoxb-YOUR-BOT-TOKEN', 'ollama',
}

def is_real(v):
    if not isinstance(v, str):
        return False
    v = v.strip()
    if v in FAKE or v.startswith('${') or len(v) < 8:
        return False
    return True

# Load existing .env to avoid duplicates
existing = {}
if os.path.exists(env_path):
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                k, _, v = line.partition('=')
                existing[k.strip()] = v.strip()

new_vars = {}       # env_var -> value
replacements = []   # (description, env_var) for the report

def extract(value, env_var, description):
    if not is_real(value):
        return value
    new_vars[env_var] = value
    replacements.append((description, env_var))
    return f'${{{env_var}}}'

# ── 1. model_list ─────────────────────────────────────────────────────────────
# All openrouter entries share the same key → single PICOCLAW_OPENROUTER_API_KEY
for i, entry in enumerate(cfg.get('model_list', [])):
    key  = entry.get('api_key', '')
    base = entry.get('api_base', '')
    name = entry.get('model_name', f'model{i}')

    if not is_real(key):
        continue

    if 'openrouter.ai' in base:
        env_var = 'PICOCLAW_OPENROUTER_API_KEY'
    else:
        safe = name.upper().replace('-','_').replace('.','_').replace('/','_')
        env_var = f'PICOCLAW_MODEL_{safe}_API_KEY'

    cfg['model_list'][i]['api_key'] = extract(key, env_var,
        f'model_list[{i}] ({name})')

# ── 2. providers ──────────────────────────────────────────────────────────────
PROVIDER_MAP = {
    'openrouter' : 'PICOCLAW_OPENROUTER_API_KEY',
    'anthropic'  : 'PICOCLAW_ANTHROPIC_API_KEY',
    'openai'     : 'PICOCLAW_OPENAI_API_KEY',
    'deepseek'   : 'PICOCLAW_DEEPSEEK_API_KEY',
    'gemini'     : 'PICOCLAW_GEMINI_API_KEY',
    'zhipu'      : 'PICOCLAW_ZHIPU_API_KEY',
    'groq'       : 'PICOCLAW_GROQ_API_KEY',
    'moonshot'   : 'PICOCLAW_MOONSHOT_API_KEY',
    'qwen'       : 'PICOCLAW_QWEN_API_KEY',
    'cerebras'   : 'PICOCLAW_CEREBRAS_API_KEY',
    'nvidia'     : 'PICOCLAW_NVIDIA_API_KEY',
    'volcengine' : 'PICOCLAW_VOLCENGINE_API_KEY',
    'mistral'    : 'PICOCLAW_MISTRAL_API_KEY',
    'perplexity' : 'PICOCLAW_PERPLEXITY_API_KEY',
}

for pname, pdata in cfg.get('providers', {}).items():
    if not isinstance(pdata, dict):
        continue
    key = pdata.get('api_key', '')
    env_var = PROVIDER_MAP.get(pname, f'PICOCLAW_{pname.upper()}_API_KEY')
    cfg['providers'][pname]['api_key'] = extract(key, env_var,
        f'providers.{pname}.api_key')

# ── 3. channels ───────────────────────────────────────────────────────────────
CHANNEL_FIELDS = {
    'telegram'  : [('token',                'PICOCLAW_TELEGRAM_TOKEN')],
    'discord'   : [('token',                'PICOCLAW_DISCORD_TOKEN')],
    'slack'     : [('bot_token',            'PICOCLAW_SLACK_BOT_TOKEN'),
                   ('app_token',            'PICOCLAW_SLACK_APP_TOKEN')],
    'dingtalk'  : [('client_id',            'PICOCLAW_DINGTALK_CLIENT_ID'),
                   ('client_secret',        'PICOCLAW_DINGTALK_CLIENT_SECRET')],
    'line'      : [('channel_secret',       'PICOCLAW_LINE_CHANNEL_SECRET'),
                   ('channel_access_token', 'PICOCLAW_LINE_CHANNEL_ACCESS_TOKEN')],
    'wecom'     : [('token',                'PICOCLAW_WECOM_TOKEN'),
                   ('encoding_aes_key',     'PICOCLAW_WECOM_ENCODING_AES_KEY')],
    'wecom_app' : [('corp_id',              'PICOCLAW_WECOM_APP_CORP_ID'),
                   ('corp_secret',          'PICOCLAW_WECOM_APP_CORP_SECRET'),
                   ('token',                'PICOCLAW_WECOM_APP_TOKEN'),
                   ('encoding_aes_key',     'PICOCLAW_WECOM_APP_ENCODING_AES_KEY')],
    'qq'        : [('app_id',               'PICOCLAW_QQ_APP_ID'),
                   ('app_secret',           'PICOCLAW_QQ_APP_SECRET')],
    'feishu'    : [('app_id',               'PICOCLAW_FEISHU_APP_ID'),
                   ('app_secret',           'PICOCLAW_FEISHU_APP_SECRET'),
                   ('encrypt_key',          'PICOCLAW_FEISHU_ENCRYPT_KEY'),
                   ('verification_token',   'PICOCLAW_FEISHU_VERIFICATION_TOKEN')],
    'onebot'    : [('access_token',         'PICOCLAW_ONEBOT_ACCESS_TOKEN')],
}

for chan, fields in CHANNEL_FIELDS.items():
    ch = cfg.get('channels', {}).get(chan)
    if not isinstance(ch, dict):
        continue
    for field, env_var in fields:
        val = ch.get(field, '')
        cfg['channels'][chan][field] = extract(val, env_var,
            f'channels.{chan}.{field}')

# ── 4. tools.web ─────────────────────────────────────────────────────────────
for tool, env_var in [('brave',      'PICOCLAW_BRAVE_API_KEY'),
                      ('tavily',     'PICOCLAW_TAVILY_API_KEY'),
                      ('perplexity', 'PICOCLAW_PERPLEXITY_API_KEY')]:
    t = cfg.get('tools', {}).get('web', {}).get(tool)
    if not isinstance(t, dict):
        continue
    val = t.get('api_key', '')
    cfg['tools']['web'][tool]['api_key'] = extract(val, env_var,
        f'tools.web.{tool}.api_key')

# ── Write .env ────────────────────────────────────────────────────────────────
if not new_vars:
    print("  \033[1;33m!\033[0m No real secrets found — config.json may already be clean.")
    sys.exit(0)

lines = [
    '',
    f'# PicoClaw secrets — migrated {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}',
    '# Do NOT commit this file!',
    '',
]

written = 0
for env_var, value in new_vars.items():
    if env_var in existing:
        print(f"  \033[1;33m!\033[0m Skipped (already in .env): {env_var}")
        continue
    lines.append(f'{env_var}={value}')
    written += 1

lines.append('')
os.makedirs(os.path.dirname(env_path), exist_ok=True)
with open(env_path, 'a') as f:
    f.write('\n'.join(lines))

print(f"\n  \033[0;32m✓\033[0m Wrote {written} secret(s) to .env:\n")
for desc, env_var in replacements:
    tag = '\033[1;33m(existed)\033[0m' if env_var in existing else '\033[0;32m(new)\033[0m'
    print(f"      {desc}  →  {env_var}  {tag}")

# ── Write updated config.json ─────────────────────────────────────────────────
with open(config_path, 'w') as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write('\n')

print(f"\n  \033[0;32m✓\033[0m config.json updated — secrets replaced with ${{VAR}} placeholders")
PYEOF

# ── Update .gitignore ─────────────────────────────────────────────────────────
step "Updating .gitignore"
touch "$GITIGNORE"
for entry in ".env" ".secrets_backup_*" "picoclaw" ".aider*"; do
    if ! grep -qF "$entry" "$GITIGNORE"; then
        echo "$entry" >> "$GITIGNORE"
        info "Added to .gitignore: $entry"
    else
        info "Already in .gitignore: $entry"
    fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}════════════════════════════════════════${RESET}"
echo -e "${CYAN}${BOLD}  Done!                                 ${RESET}"
echo -e "${CYAN}${BOLD}════════════════════════════════════════${RESET}"
echo ""
echo -e "  Secrets : ${BOLD}${ENV_FILE}${RESET}  ← keep private"
echo -e "  Config  : ${BOLD}${CONFIG}${RESET}  ← placeholders in place"
echo -e "  Backup  : ${BOLD}${BACKUP}${RESET}"
echo ""
echo "  Verify and test:"
echo "    cat ~/picoclaw/.env"
echo "    cd ~/picoclaw && source .env && picoclaw agent -m 'hello'"
echo ""
echo -e "  ${YELLOW}⚠  Revoke your old OpenRouter key now: https://openrouter.ai/keys${RESET}"
echo ""
