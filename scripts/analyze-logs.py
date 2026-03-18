#!/usr/bin/env python3
"""
PicoClaw Log Analyzer
Detects token waste, skill bypass, loops, failures, and model behavior patterns.

Usage:
    picoclaw-logs | python3 analyze-logs.py
    python3 analyze-logs.py < picoclaw.log
    python3 analyze-logs.py --file picoclaw.log
    python3 analyze-logs.py --file picoclaw.log --since "2026-03-16 19:00"
    python3 analyze-logs.py --file picoclaw.log --tail 500
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta


# ── Patterns ──────────────────────────────────────────────────────────────────

RE_TIMESTAMP   = re.compile(r'\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)\]')
RE_TOKEN_SUMMARY     = re.compile(r'Token usage summary')
RE_TOTAL_PROMPT      = re.compile(r'total_prompt=(\d+)')
RE_TOTAL_COMPLETION  = re.compile(r'total_completion=(\d+)')
RE_TOTAL_TOKENS      = re.compile(r'total_tokens=(\d+)')
RE_ITERATIONS        = re.compile(r'iterations=(\d+)')
RE_TOOL_CALL   = re.compile(r'Tool call: (\w+)\((\{.*?\})\)')
RE_CACHE_HIT   = re.compile(r'Tool call cache hit.*?url=(\S+)')
RE_SKILL_WARN  = re.compile(r'invalid skill.*?name=(\S+).*?error="([^"]+)"')
RE_STATIC_TOK  = re.compile(r'static_tokens=(\d+)')
RE_MSG_FROM    = re.compile(r'Processing message from (\S+): (.+?) \{')
RE_RESPONSE    = re.compile(r'Response: (.+?) \{.*?iterations=(\d+).*?final_length=(\d+)')
RE_LLM_FAILED  = re.compile(r'LLM call failed.*?error=(.+)')
RE_POSTMORTEM  = re.compile(r'Post-mortem notification sent.*?entry_id=(\S+)')
RE_RATE_LIMIT  = re.compile(r'429|rate.limit|Rate limit', re.I)
RE_DEFAULT_RSP = re.compile(r"I've completed processing but have no response")


STOOQ_DOMAINS  = {'stooq.com'}
YAHOO_DOMAINS  = {'query1.finance.yahoo.com', 'query2.finance.yahoo.com', 'finance.yahoo.com'}
SKILL_URLS     = {
    'price-check': {'stooq.com', 'coingecko.com', 'frankfurter.app'},
    'weather':     {'wttr.in'},
    'summarize':   {'.picoclaw/workspace/summarize.sh'},
}


# ── Parser ────────────────────────────────────────────────────────────────────

def parse_log(lines):
    """Parse log lines into structured session records."""
    sessions = []
    current = None

    for line in lines:
        # New message starts a new session record
        m = RE_MSG_FROM.search(line)
        if m:
            if current:
                sessions.append(current)
            ts_m = RE_TIMESTAMP.search(line)
            current = {
                'ts':         ts_m.group(1) if ts_m else '',
                'sender':     m.group(1),
                'query':      m.group(2)[:120],
                'tool_calls': [],      # list of (tool, url/args)
                'cache_hits': [],
                'iterations': 0,
                'total_tokens': 0,
                'prompt_tokens': 0,
                'completion_tokens': 0,
                'static_tokens': 0,
                'failed': False,
                'llm_errors': [],
                'postmortem': None,
                'is_heartbeat': 'heartbeat' in line.lower() or 'session_key=heartbeat' in line,
            }
            continue

        if current is None:
            continue

        # Tool calls
        m = RE_TOOL_CALL.search(line)
        if m:
            tool, args_str = m.group(1), m.group(2)
            try:
                args = json.loads(args_str)
                url = args.get('url', args.get('command', str(args)))
            except Exception:
                url = args_str[:80]
            current['tool_calls'].append((tool, url))

        # Cache hits
        m = RE_CACHE_HIT.search(line)
        if m:
            current['cache_hits'].append(m.group(1))

        # Token summary
        if RE_TOKEN_SUMMARY.search(line):
            if m := RE_TOTAL_PROMPT.search(line):
                current['prompt_tokens'] = int(m.group(1))
            if m := RE_TOTAL_COMPLETION.search(line):
                current['completion_tokens'] = int(m.group(1))
            if m := RE_TOTAL_TOKENS.search(line):
                current['total_tokens'] = int(m.group(1))
            if m := RE_ITERATIONS.search(line):
                current['iterations'] = int(m.group(1))

        # Static tokens
        m = RE_STATIC_TOK.search(line)
        if m and 'Prompt token breakdown' in line:
            current['static_tokens'] = int(m.group(1))

        # Default response (failure)
        if RE_DEFAULT_RSP.search(line):
            current['failed'] = True

        # LLM errors
        m = RE_LLM_FAILED.search(line)
        if m:
            current['llm_errors'].append(m.group(1)[:100])

        # Postmortem
        m = RE_POSTMORTEM.search(line)
        if m:
            current['postmortem'] = m.group(1)

    if current:
        sessions.append(current)

    return sessions


# ── Analyzers ─────────────────────────────────────────────────────────────────

def detect_skill_bypass(session):
    """Detect when LLM ignores skill instructions and uses wrong source."""
    issues = []
    tools_used = [url for _, url in session['tool_calls']]
    query_lower = session['query'].lower()

    # Price queries should use stooq
    price_keywords = ['价格', '價格', 'price', '匯率', '汇率', 'gold', '黄金', '黃金',
                      '原油', 'oil', 'bitcoin', '比特币', 'silver', '白银', '白銀']
    is_price_query = any(kw in query_lower for kw in price_keywords)

    if is_price_query:
        used_yahoo  = any(d in url for url in tools_used for d in YAHOO_DOMAINS)
        used_stooq  = any('stooq.com' in url for url in tools_used)
        if used_yahoo and not used_stooq:
            issues.append('⚠️  SKILL BYPASS: price query used Yahoo Finance instead of stooq.com')
        elif used_yahoo and used_stooq:
            issues.append('⚠️  SKILL PARTIAL: tried Yahoo Finance first, fell back to stooq.com')

    # Weather queries should use wttr.in
    weather_keywords = ['天气', '天氣', 'weather', '温度', '氣溫']
    is_weather_query = any(kw in query_lower for kw in weather_keywords)
    if is_weather_query:
        used_wttr = any('wttr.in' in url for url in tools_used)
        if not used_wttr:
            issues.append('⚠️  SKILL BYPASS: weather query did not use wttr.in')

    return issues


def detect_loops(session):
    """Detect repeated tool calls with same URL."""
    issues = []
    url_counts = defaultdict(int)
    for tool, url in session['tool_calls']:
        if tool in ('web_fetch', 'exec'):
            url_counts[url] += 1

    for url, count in url_counts.items():
        if count >= 3:
            cached = url in session['cache_hits']
            cache_note = ' (cache prevented re-fetch)' if cached else ' ⚠️  cache did NOT prevent this'
            issues.append(f'🔁 LOOP: {url!r} called {count}x{cache_note}')

    return issues


def detect_token_waste(session):
    """Flag sessions with high token usage."""
    issues = []
    t = session['total_tokens']
    if t > 50000:
        issues.append(f'💸 HIGH TOKENS: {t:,} total tokens (>{50000:,})')
    elif t > 20000:
        issues.append(f'💰 ELEVATED TOKENS: {t:,} total tokens')

    if session['iterations'] >= 10:
        issues.append(f'⚙️  HIGH ITERATIONS: {session["iterations"]} iterations')

    return issues


def detect_skill_loading(lines):
    """Scan all lines for skill loading warnings."""
    issues = []
    for line in lines:
        m = RE_SKILL_WARN.search(line)
        if m:
            issues.append(f'❌ INVALID SKILL: {m.group(1)} — {m.group(2)}')
        if RE_RATE_LIMIT.search(line) and 'LLM call failed' in line:
            ts_m = RE_TIMESTAMP.search(line)
            ts = ts_m.group(1) if ts_m else '?'
            issues.append(f'🚫 RATE LIMIT at {ts}')
    return list(dict.fromkeys(issues))  # deduplicate


# ── Report ────────────────────────────────────────────────────────────────────

def print_report(sessions, global_issues, args):
    total        = len([s for s in sessions if not s['is_heartbeat']])
    failed       = [s for s in sessions if s['failed']]
    high_token   = [s for s in sessions if s['total_tokens'] > 20000]
    postmortems  = [s for s in sessions if s['postmortem']]
    all_tokens   = sum(s['total_tokens'] for s in sessions if not s['is_heartbeat'])
    heartbeats   = [s for s in sessions if s['is_heartbeat']]

    print('\n' + '═' * 60)
    print('  PicoClaw Log Analyzer')
    print('═' * 60)

    # Summary
    print(f'\n📊 SUMMARY')
    print(f'  User sessions:    {total}')
    print(f'  Heartbeats:       {len(heartbeats)}')
    print(f'  Failed sessions:  {len(failed)}')
    print(f'  High-token (>20k):{len(high_token)}')
    print(f'  Postmortems sent: {len(postmortems)}')
    print(f'  Total tokens:     {all_tokens:,}')
    if total > 0:
        print(f'  Avg tokens/query: {all_tokens // max(total,1):,}')

    # Global issues
    if global_issues:
        print(f'\n🔧 GLOBAL ISSUES')
        for issue in global_issues:
            print(f'  {issue}')

    # Static tokens trend (skill loading health)
    static_vals = [s['static_tokens'] for s in sessions if s['static_tokens'] > 0]
    if static_vals:
        print(f'\n📌 STATIC TOKENS (skill loading health)')
        print(f'  Min: {min(static_vals):,}  Max: {max(static_vals):,}  Latest: {static_vals[-1]:,}')
        if max(static_vals) - min(static_vals) > 500:
            print(f'  ⚠️  Large variation — skills may have loaded/unloaded during session')

    # Failed sessions
    if failed:
        print(f'\n❌ FAILED SESSIONS ({len(failed)})')
        for s in failed[-5:]:  # show last 5
            print(f'  [{s["ts"]}] {s["query"][:60]}')
            print(f'    iterations={s["iterations"]} tokens={s["total_tokens"]:,}')
            if s['postmortem']:
                print(f'    postmortem={s["postmortem"]}')
            loops = detect_loops(s)
            for l in loops:
                print(f'    {l}')

    # Skill bypass issues
    bypass_issues = []
    for s in sessions:
        if s['is_heartbeat']:
            continue
        issues = detect_skill_bypass(s)
        if issues:
            bypass_issues.append((s, issues))

    if bypass_issues:
        print(f'\n🎯 SKILL BYPASS ISSUES ({len(bypass_issues)})')
        for s, issues in bypass_issues[-5:]:
            print(f'  [{s["ts"]}] {s["query"][:60]}')
            for issue in issues:
                print(f'    {issue}')
            print(f'    Tools used: {[url[:50] for _, url in s["tool_calls"][:5]]}')

    # High token sessions
    if high_token and not args.summary_only:
        print(f'\n💸 HIGH TOKEN SESSIONS (top 5)')
        for s in sorted(high_token, key=lambda x: -x['total_tokens'])[:5]:
            print(f'  [{s["ts"]}] {s["query"][:60]}')
            print(f'    tokens={s["total_tokens"]:,} iter={s["iterations"]} failed={s["failed"]}')
            loops = detect_loops(s)
            for l in loops:
                print(f'    {l}')

    # LLM errors
    error_sessions = [s for s in sessions if s['llm_errors']]
    if error_sessions:
        print(f'\n⚡ LLM ERRORS ({len(error_sessions)})')
        for s in error_sessions[-5:]:
            print(f'  [{s["ts"]}] {s["query"][:50]}')
            for e in s['llm_errors']:
                print(f'    {e[:100]}')

    print('\n' + '═' * 60 + '\n')


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description='Analyze PicoClaw logs')
    parser.add_argument('--file', '-f',   help='Log file path (default: stdin)')
    parser.add_argument('--tail', '-n',   type=int, help='Only analyze last N lines')
    parser.add_argument('--since',        help='Only analyze logs since datetime (e.g. "2026-03-16 19:00")')
    parser.add_argument('--summary-only', action='store_true', help='Only show summary, skip details')
    args = parser.parse_args()

    # Read input
    if args.file:
        with open(args.file) as f:
            lines = f.readlines()
    else:
        lines = sys.stdin.readlines()

    # Apply tail
    if args.tail:
        lines = lines[-args.tail:]

    # Apply since filter
    if args.since:
        since_dt = datetime.strptime(args.since, '%Y-%m-%d %H:%M')
        filtered = []
        for line in lines:
            m = RE_TIMESTAMP.search(line)
            if m:
                line_dt = datetime.strptime(m.group(1), '%Y-%m-%dT%H:%M:%SZ')
                if line_dt >= since_dt:
                    filtered.append(line)
            else:
                filtered.append(line)
        lines = filtered

    sessions     = parse_log(lines)
    global_issues = detect_skill_loading(lines)

    print_report(sessions, global_issues, args)


if __name__ == '__main__':
    main()
