#!/usr/bin/env bash
# =============================================================================
# scan_picoclaw.sh — Static malware/security scan for the picoclaw project
# =============================================================================
# WHAT THIS SCRIPT DOES:
#   Scans source code for patterns commonly associated with malware, backdoors,
#   credential theft, suspicious networking, and obfuscated code.
#   It does NOT install anything, modify any files, or send data anywhere.
#   All output is printed to your terminal (and optionally saved to a report).
#
# USAGE:
#   chmod +x scan_picoclaw.sh
#   ./scan_picoclaw.sh [path-to-project]   # defaults to ~/picoclaw
#
# EXAMPLE:
#   ./scan_picoclaw.sh ~/picoclaw
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
TARGET="${1:-$HOME/picoclaw}"
REPORT="picoclaw_scan_report_$(date +%Y%m%d_%H%M%S).txt"
FINDINGS=0

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
header() {
    echo ""
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════${RESET}"
    echo -e "${CYAN}${BOLD}  $1${RESET}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════${RESET}"
}

section() {
    echo ""
    echo -e "${BOLD}── $1 ──────────────────────────────────────────${RESET}"
}

hit() {
    local label="$1"
    local pattern="$2"
    local file="$3"
    local line="$4"
    echo -e "  ${RED}[!] $label${RESET}"
    echo -e "      File   : $file"
    echo -e "      Match  : $line"
    FINDINGS=$((FINDINGS + 1))
}

info() {
    echo -e "  ${GREEN}[ok]${RESET} $1"
}

warn() {
    echo -e "  ${YELLOW}[?]${RESET} $1"
}

# Run a grep scan across the project and report each match
scan() {
    local label="$1"
    local pattern="$2"
    shift 2
    local extra_args=("$@")

    local results
    results=$(grep -rn --include="*.go" --include="*.sh" --include="*.py" \
        --include="*.js" --include="*.ts" --include="*.json" \
        --include="*.yaml" --include="*.yml" --include="*.env" \
        --include="Makefile" --include="Dockerfile" \
        "${extra_args[@]}" -E "$pattern" "$TARGET" 2>/dev/null || true)

    if [[ -n "$results" ]]; then
        while IFS= read -r line; do
            local file
            file=$(echo "$line" | cut -d: -f1)
            local content
            content=$(echo "$line" | cut -d: -f3-)
            hit "$label" "$pattern" "$file" "$content"
        done <<< "$results"
    fi
}

# ── Preflight checks ──────────────────────────────────────────────────────────
header "PicoClaw Security Scanner"
echo ""
echo -e "  Target    : ${BOLD}$TARGET${RESET}"
echo -e "  Report    : ${BOLD}$REPORT${RESET}"
echo -e "  Started   : $(date)"

if [[ ! -d "$TARGET" ]]; then
    echo -e "\n${RED}ERROR: Directory '$TARGET' not found.${RESET}"
    echo "Usage: $0 [path-to-project]"
    exit 1
fi

# Redirect a copy of all output to the report file
exec > >(tee -a "$REPORT") 2>&1

# ── 1. File inventory ─────────────────────────────────────────────────────────
header "1. File Inventory"

section "Unexpected binary files in source tree"
find "$TARGET" -type f \
    ! -path "*/.git/*" \
    ! -name "*.go" ! -name "*.md" ! -name "*.sh" ! -name "*.json" \
    ! -name "*.yaml" ! -name "*.yml" ! -name "*.mod" ! -name "*.sum" \
    ! -name "*.txt" ! -name "*.html" ! -name "*.css" ! -name "*.js" \
    ! -name "*.ts" ! -name "*.png" ! -name "*.jpg" ! -name "*.svg" \
    ! -name "*.gif" ! -name "*.ico" ! -name "*.env" ! -name "*.example" \
    ! -name "Makefile" ! -name "Dockerfile" ! -name ".dockerignore" \
    ! -name ".gitignore" ! -name ".goreleaser*" ! -name ".golangci*" \
    -exec file {} \; 2>/dev/null | grep -i "ELF\|Mach-O\|PE32\|executable\|binary" \
    | while IFS= read -r line; do
        echo -e "  ${RED}[!] Unexpected binary:${RESET} $line"
        FINDINGS=$((FINDINGS + 1))
    done || true
info "Binary file scan complete"

section "Hidden files and directories"
find "$TARGET" -name ".*" ! -path "*/.git/*" ! -name ".gitignore" \
    ! -name ".env*" ! -name ".dockerignore" ! -name ".goreleaser*" \
    ! -name ".golangci*" ! -name ".github" 2>/dev/null \
    | while IFS= read -r f; do
        warn "Hidden file/dir: $f"
    done || true

# ── 2. Credential & secret leakage ───────────────────────────────────────────
header "2. Credential & Secret Leakage"

section "Hardcoded API keys / tokens / passwords"
scan "Hardcoded secret (api_key=)" \
    '(api_key|apikey|api-key)\s*[:=]\s*"[A-Za-z0-9_\-]{16,}"'

scan "Hardcoded secret (password=)" \
    '(password|passwd|secret|token)\s*[:=]\s*"[A-Za-z0-9@#\$%^&*!_\-]{8,}"'

scan "Bearer / Authorization token" \
    'Bearer\s+[A-Za-z0-9_\-\.]{20,}'

scan "AWS key pattern" \
    'AKIA[0-9A-Z]{16}'

scan "Private key block" \
    'BEGIN (RSA|EC|OPENSSH|PGP) PRIVATE KEY'

scan "GitHub/Anthropic/OpenAI-style token" \
    '(ghp_|ghs_|sk-ant-|sk-or-v1-|sk-)[A-Za-z0-9]{20,}'

info "Credential scan complete"

# ── 3. Suspicious networking ──────────────────────────────────────────────────
header "3. Suspicious Networking"

section "Outbound connections to unusual hosts"
scan "Hardcoded non-API IP address" \
    '"(http|https|ftp)://([0-9]{1,3}\.){3}[0-9]{1,3}[:/]'

scan "DNS / IP lookup of external host (non-standard)" \
    '(net\.Dial|net\.LookupHost|http\.Get|http\.Post)\s*\(\s*"[^"]{6,}"'

scan "Hardcoded suspicious domain" \
    '(pastebin\.com|ngrok\.io|requestbin|webhook\.site|burpcollaborator|interactsh)'

scan "Base64-encoded URL (potential C2)" \
    'base64\.(StdEncoding|URLEncoding|RawStdEncoding)\.Decode.*[A-Za-z0-9+/=]{40,}'

info "Network scan complete"

# ── 4. Code execution & shell injection ──────────────────────────────────────
header "4. Code Execution & Shell Injection"

section "Dynamic command execution"
scan "os/exec with variable input (potential injection)" \
    'exec\.Command\([^)]*\+[^)]*\)'

scan "Shell -c with variable" \
    '(exec\.Command|os\.system|subprocess)\s*\(.*"sh".*"-c"'

scan "eval() usage" \
    '\beval\s*\('

section "Dangerous system calls"
scan "Dangerous rm -rf pattern in code" \
    '"rm\s+-[rRfF]+'

scan "Direct disk write (/dev/sd)" \
    '/dev/sd[a-z]'

scan "Format/wipe commands" \
    '(mkfs|diskpart|format\s+[A-Z]:)'

info "Code execution scan complete"

# ── 5. Data exfiltration patterns ─────────────────────────────────────────────
header "5. Data Exfiltration Patterns"

section "File system reads of sensitive paths"
scan "Reading /etc/passwd or shadow" \
    '(/etc/passwd|/etc/shadow|/etc/hosts)'

scan "SSH key access" \
    '(\.ssh/id_rsa|\.ssh/authorized_keys|\.ssh/known_hosts)'

scan "Browser credential paths" \
    '(Chrome/Default/Login|firefox/profiles|keychain)'

scan "Env var harvesting" \
    'os\.Environ\(\)'

section "Sending file contents outbound"
scan "File read + HTTP post combo" \
    '(ioutil\.ReadFile|os\.ReadFile).*http\.(Post|NewRequest)'

info "Exfiltration scan complete"

# ── 6. Obfuscation & encoding ─────────────────────────────────────────────────
header "6. Obfuscation & Encoding"

section "Base64 blobs (possible hidden payloads)"
# Look for very long base64 strings that aren't clearly image/cert data
grep -rn --include="*.go" --include="*.sh" --include="*.py" \
    -E '[A-Za-z0-9+/]{80,}={0,2}' "$TARGET" 2>/dev/null \
    | grep -v "_test\|\.sum\|go\.mod\|\.png\|\.jpg\|certificate\|CERTIFICATE\|testdata" \
    | while IFS= read -r line; do
        echo -e "  ${YELLOW}[?] Long base64 blob:${RESET}"
        echo "      $line"
    done || true

section "Hex-encoded strings"
scan "Long hex string (>32 chars)" \
    '0x[0-9a-fA-F]{32,}'

section "ROT13 / XOR obfuscation"
scan "XOR loop over bytes (common obfuscation)" \
    'for.*\^\s*(0x[0-9a-f]{2}|[0-9]+)\b'

info "Obfuscation scan complete"

# ── 7. Persistence mechanisms ─────────────────────────────────────────────────
header "7. Persistence Mechanisms"

section "Cron / scheduled task manipulation"
scan "Writing to crontab" \
    '(crontab|/etc/cron\.|/var/spool/cron)'

scan "systemd service file creation" \
    '(/etc/systemd/system|/lib/systemd/system)'

scan "rc.local or init.d modification" \
    '(/etc/rc\.local|/etc/init\.d/)'

section "Auto-start / startup file modification"
scan "Writing to shell profile" \
    '(\.bashrc|\.zshrc|\.profile|\.bash_profile)'

info "Persistence scan complete"

# ── 8. Go dependency review ───────────────────────────────────────────────────
header "8. Go Dependency Review"

if [[ -f "$TARGET/go.mod" ]]; then
    section "go.mod — Direct dependencies"
    grep "^require" -A 999 "$TARGET/go.mod" | grep -v "^)" | grep "^\s" \
        | awk '{print $1}' | while IFS= read -r dep; do
            echo "    $dep"
        done || true
    info "Review each dependency above against pkg.go.dev for known issues"

    section "Checking for 'replace' directives (can redirect dependencies)"
    if grep -q "^replace" "$TARGET/go.mod" 2>/dev/null; then
        grep "^replace" "$TARGET/go.mod" | while IFS= read -r line; do
            warn "REPLACE directive: $line"
        done
    else
        info "No 'replace' directives found — good"
    fi
else
    warn "go.mod not found at $TARGET/go.mod"
fi

# ── 9. Script file review ─────────────────────────────────────────────────────
header "9. Shell Script Review"

section "Shell scripts in project"
find "$TARGET" -name "*.sh" ! -path "*/.git/*" 2>/dev/null \
    | while IFS= read -r script; do
        echo -e "  ${BOLD}Reviewing:${RESET} $script"
        # Check for wget/curl piped to bash (classic malware pattern)
        if grep -qE '(wget|curl).*(bash|sh|zsh|python|perl)' "$script" 2>/dev/null; then
            echo -e "  ${RED}[!] SUSPICIOUS: curl/wget piped to shell interpreter${RESET}"
            grep -nE '(wget|curl).*(bash|sh|zsh|python|perl)' "$script"
            FINDINGS=$((FINDINGS + 1))
        fi
        # Check for remote code download
        if grep -qE '(wget|curl)\s+.*\|\s*(bash|sh)' "$script" 2>/dev/null; then
            echo -e "  ${RED}[!] SUSPICIOUS: Remote code download and exec${RESET}"
            FINDINGS=$((FINDINGS + 1))
        fi
    done || true

info "Shell script review complete"

# ── 10. GitHub Actions / CI review ───────────────────────────────────────────
header "10. CI/CD Pipeline Review"

if [[ -d "$TARGET/.github/workflows" ]]; then
    section "GitHub Actions workflows"
    find "$TARGET/.github/workflows" -name "*.yml" -o -name "*.yaml" 2>/dev/null \
        | while IFS= read -r wf; do
            echo -e "  ${BOLD}Workflow:${RESET} $wf"
            # Check for secrets being exfiltrated
            if grep -qE '(curl|wget).*secrets\.' "$wf" 2>/dev/null; then
                echo -e "  ${RED}[!] SUSPICIOUS: Sending secrets outbound in CI${RESET}"
                grep -nE '(curl|wget).*secrets\.' "$wf"
                FINDINGS=$((FINDINGS + 1))
            fi
            # Check for third-party actions pinned by SHA vs branch
            if grep -qE 'uses:.*@(main|master|latest|v[0-9]+)' "$wf" 2>/dev/null; then
                warn "Actions pinned by tag/branch (not SHA) — consider pinning by commit SHA for supply chain safety"
                grep -nE 'uses:.*@(main|master|latest|v[0-9]+)' "$wf"
            fi
        done || true
else
    warn "No .github/workflows directory found"
fi

info "CI/CD review complete"

# ── Final summary ─────────────────────────────────────────────────────────────
header "Scan Complete"
echo ""
echo -e "  Total findings : ${BOLD}$FINDINGS${RESET}"
echo -e "  Report saved   : ${BOLD}$REPORT${RESET}"
echo ""
if [[ $FINDINGS -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}✓ No suspicious patterns detected.${RESET}"
    echo -e "  ${GREEN}  This does not guarantee safety — always review code manually.${RESET}"
else
    echo -e "  ${RED}${BOLD}⚠ $FINDINGS pattern(s) flagged for review.${RESET}"
    echo -e "  ${YELLOW}  Review each finding above. Many may be false positives.${RESET}"
    echo -e "  ${YELLOW}  Focus first on: credentials, networking, and binary files.${RESET}"
fi
echo ""
echo -e "  ${CYAN}Next steps:${RESET}"
echo "    1. Review all [!] RED findings first — those are highest priority"
echo "    2. Review [?] YELLOW warnings — lower priority, often false positives"
echo "    3. Run: go mod verify   (inside the project) to verify dependency checksums"
echo "    4. Run: govulncheck ./... (install: go install golang.org/x/vuln/cmd/govulncheck@latest)"
echo ""
