#!/usr/bin/env python3
"""
Claude Code Status Line — multi-line
Line 1: model · effort · dir · git · context · api time · cost · lines
Line 2: quota bars — 5h · 7d · per-model · extra usage
"""

import io
import json
import os
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# Force UTF-8 output (required for block chars on some terminals)
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

# ── ANSI ─────────────────────────────────────────────────────────────────────
RESET  = "\033[0m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
CYAN   = "\033[36m"
GREEN  = "\033[32m"
YELLOW = "\033[33m"
RED    = "\033[31m"

FILL  = "█"
EMPTY = "░"
SEP   = f" {DIM}·{RESET} "

# ── Config ────────────────────────────────────────────────────────────────────
CACHE_DIR = Path("/tmp/claude-statusline-cache")
CACHE_DIR.mkdir(parents=True, exist_ok=True)

CREDENTIALS_FILE = Path.home() / ".claude" / ".credentials.json"
USAGE_URL       = "https://api.anthropic.com/api/oauth/usage"
QUOTA_CACHE_TTL = 60   # seconds — back off from API


# ── Helpers ───────────────────────────────────────────────────────────────────

def read_json_input() -> dict:
    try:
        return json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return {}


def cache_get(key: str, ttl: int) -> str | None:
    f = CACHE_DIR / f"{key}.cache"
    if f.exists() and (time.time() - f.stat().st_mtime) < ttl:
        return f.read_text().strip()
    return None


def cache_set(key: str, value: str) -> None:
    (CACHE_DIR / f"{key}.cache").write_text(value)


def cache_touch(key: str) -> None:
    f = CACHE_DIR / f"{key}.cache"
    if f.exists():
        f.touch()


def color_for(pct: float) -> str:
    if pct >= 80:
        return RED
    if pct >= 50:
        return YELLOW
    return GREEN


def bar(pct: float, width: int = 10) -> str:
    pct = max(0.0, min(100.0, float(pct)))
    filled = round(pct / 100 * width)
    c = color_for(pct)
    return f"{c}{FILL * filled}{DIM}{EMPTY * (width - filled)}{RESET}"


def time_until(iso: str, show_clock: bool = False) -> str:
    try:
        target = datetime.fromisoformat(iso)
        delta = int((target - datetime.now(timezone.utc)).total_seconds())
        if delta <= 0:
            return "now"
        h, m = delta // 3600, (delta % 3600) // 60
        remaining = f"{h}h{m:02d}m" if h else f"{m}m"
        if show_clock:
            local = target.astimezone().strftime("%H:%M")
            return f"{remaining} ({local})"
        return remaining
    except Exception:
        return "?"


def expires_at(iso: str) -> str:
    """Return weekday + local time for the expiration timestamp."""
    try:
        dt = datetime.fromisoformat(iso).astimezone()
        days_pt = ["seg", "ter", "qua", "qui", "sex", "sáb", "dom"]
        return f"{days_pt[dt.weekday()]} {dt.strftime('%H:%M')}"
    except Exception:
        return "?"


def fmt_cost(v: float | str) -> str:
    try:
        f = float(v)
        return f"{f:.2f}" if f > 0.001 else "—"
    except (ValueError, TypeError):
        return "—"


def fmt_duration(total_seconds: int) -> str:
    """Format seconds into human-readable h m s."""
    if total_seconds < 1:
        return ""
    h, rem = divmod(total_seconds, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h{m:02d}m{s:02d}s"
    if m:
        return f"{m}m{s:02d}s"
    return f"{s}s"


def fmt_ms(ms: int | str) -> str:
    try:
        v = int(ms)
        if v <= 0:
            return "—"
        secs = v // 1000
        dur = fmt_duration(secs)
        return dur if dur else f"{v}ms"
    except (ValueError, TypeError):
        return "—"


def fmt_pct(v: float) -> str:
    return f"{v:.0f}%"


def fmt_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}k"
    return str(n)


# ── Session data ──────────────────────────────────────────────────────────────

def get_git_info(cwd: str) -> str:
    try:
        subprocess.run(
            ["git", "rev-parse", "--git-dir"],
            cwd=cwd, capture_output=True, check=True, timeout=2,
        )
        branch = subprocess.run(
            ["git", "branch", "--show-current"],
            cwd=cwd, capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        if not branch:
            return ""
        raw = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=cwd, capture_output=True, text=True, timeout=2,
        ).stdout.strip()
        count = len(raw.splitlines()) if raw else 0
        suffix = f"±{count}" if count else ""
        return f"🌿 {branch}{suffix}"
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return ""


def get_output_style(data: dict) -> str:
    """Return output style name from statusline input (e.g. 'fast', 'default')."""
    style = data.get("output_style", {}).get("name", "")
    return style if style and style != "default" else ""


# ── Quota ─────────────────────────────────────────────────────────────────────

def get_access_token() -> str | None:
    try:
        data = json.loads(CREDENTIALS_FILE.read_text())
        return data.get("claudeAiOauth", {}).get("accessToken")
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def fetch_usage_api() -> dict | None:
    token = get_access_token()
    if not token:
        return None
    try:
        req = urllib.request.Request(
            USAGE_URL,
            headers={
                "Authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20",
                "Content-Type": "application/json",
                "User-Agent": "claude-code/1.0",
            },
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            if resp.status == 200:
                return json.loads(resp.read())
    except Exception:
        pass
    return None


def get_quota() -> dict | None:
    cache_file = CACHE_DIR / "quota.json"

    if cache_file.exists() and (time.time() - cache_file.stat().st_mtime) < QUOTA_CACHE_TTL:
        try:
            return json.loads(cache_file.read_text())
        except json.JSONDecodeError:
            pass

    data = fetch_usage_api()
    if data:
        cache_file.write_text(json.dumps(data))
        return data

    # Fetch failed — serve stale but bump mtime to back off
    if cache_file.exists():
        try:
            stale = json.loads(cache_file.read_text())
            cache_file.touch()
            return stale
        except json.JSONDecodeError:
            pass

    return None


# ── Lines ─────────────────────────────────────────────────────────────────────

def build_line1(data: dict) -> str:
    model  = data.get("model", {}).get("display_name", "Model")
    cwd    = data.get("workspace", {}).get("current_dir", os.getcwd())
    cost   = data.get("cost", {})
    ctx    = data.get("context_window", {})

    git   = get_git_info(cwd)
    style = get_output_style(data)

    ctx_pct = ctx.get("used_percentage")
    ctx_str = f"{color_for(ctx_pct)}{ctx_pct}%{RESET}" if ctx_pct is not None else "?"

    style_str = ""
    if style:
        style_str = f" {YELLOW}{style}{RESET}"

    lines_added   = cost.get("total_lines_added", 0)
    lines_removed = cost.get("total_lines_removed", 0)
    changes_str   = f" 📝 +{lines_added}−{lines_removed}" if (lines_added or lines_removed) else ""

    dir_str = f"📁 {Path(cwd).name}"
    if git:
        dir_str += f"  {git}{changes_str}"
    elif changes_str:
        dir_str += changes_str

    tok_in  = ctx.get("total_input_tokens", 0)
    tok_out = ctx.get("total_output_tokens", 0)
    tok_str = f"{fmt_tokens(tok_in)}↓ {fmt_tokens(tok_out)}↑"

    parts = [
        f"{CYAN}{model}{RESET}{style_str}",
        dir_str,
        f"{BOLD}{CYAN}⏩{RESET} {fmt_ms(cost.get('total_api_duration_ms', 0))}",
        f"📊 {ctx_str}",
        f"🧩 {tok_str}",
        f"💲 {fmt_cost(cost.get('total_cost_usd', 0))}",
    ]
    return SEP.join(parts)


def build_line2(quota: dict | None) -> str:
    if not quota:
        return f"{DIM}quota unavailable{RESET}"

    segments = []

    # 5-hour window
    fh = quota.get("five_hour")
    if fh:
        u = fh["utilization"]
        segments.append(
            f"{BOLD}{CYAN}⏰{RESET} Session ↺{time_until(fh.get('resets_at', ''), show_clock=True)} {bar(u)} {color_for(u)}{fmt_pct(u)}{RESET}"
        )

    # 7-day total
    sd = quota.get("seven_day")
    if sd:
        u = sd["utilization"]
        segments.append(
            f"📅 Week ↺{expires_at(sd.get('resets_at', ''))} {bar(u)} {color_for(u)}{fmt_pct(u)}{RESET}"
        )

    # Per-model 7-day (only non-null entries)
    per_model = {
        "seven_day_opus":       "opus",
        "seven_day_sonnet":     "sonnet",
        "seven_day_haiku":      "haiku",
        "seven_day_oauth_apps": "apps",
        "seven_day_cowork":     "cowork",
    }
    for key, label in per_model.items():
        entry = quota.get(key)
        if entry:
            u = entry["utilization"]
            segments.append(f"{label} {bar(u, 6)} {color_for(u)}{fmt_pct(u)}{RESET}")

    # iguana_necktie — unknown internal feature, show if populated
    iguana = quota.get("iguana_necktie")
    if iguana:
        u = iguana.get("utilization", 0)
        segments.append(f"🦎 {bar(u, 6)} {color_for(u)}{fmt_pct(u)}{RESET}")

    # Extra usage (pay-as-you-go credits) — only when enabled
    extra = quota.get("extra_usage") or {}
    if extra.get("is_enabled"):
        u     = extra.get("utilization") or 0
        used  = extra.get("used_credits") or 0
        limit = extra.get("monthly_limit") or 0
        segments.append(
            f"extra {bar(u, 6)} {color_for(u)}{fmt_pct(u)}{RESET} "
            f"{DIM}${used:.2f}/${limit:.2f}{RESET}"
        )

    return SEP.join(segments) if segments else f"{DIM}quota: no data{RESET}"


def main() -> None:
    data  = read_json_input()
    # Save input for debugging
    (CACHE_DIR / "debug_input.json").write_text(json.dumps(data, indent=2))
    quota = get_quota()
    print(build_line1(data))
    print(build_line2(quota))


if __name__ == "__main__":
    main()
