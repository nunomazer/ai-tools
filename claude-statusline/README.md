# Claude Code Status Line

Custom two-line status line for the Claude Code CLI displaying session information and quota usage. Supports multiple concurrent Claude accounts on the same machine via `CLAUDE_CONFIG_DIR`.

```
Opus 4.6 · 📁 my-project  🌿 main±3 📝 +156−23 · ⏩ 4m32s · 📊 42% · 🧩 71↓ 17.6k↑ · 💲 1.37
⏰ Session ↺2h30m (20:45) ██████░░░░ 55% · 📅 Week ↺fri 14:00 ████░░░░░░ 35% · opus ██████░░░░ 60%
```

## Installation (new users)

```bash
git clone <this-repo> ~/Workspaces/ai-tools
cd ~/Workspaces/ai-tools/claude-statusline
./install.sh
```

The installer:

- Creates a wrapper at `~/.claude/statusline-wrapper.sh` (or `statusline-wrapper-<account>.sh` when `CLAUDE_CONFIG_DIR` is set) that execs the `statusline.py` from this repo.
- Writes/updates `statusLine` in the active `settings.json` (in `$CLAUDE_CONFIG_DIR` if set, otherwise in `~/.claude/`).
- Preserves other keys in `settings.json` and is idempotent — safe to re-run.

### Multiple accounts

If you use several Claude accounts on the same machine (e.g. `claude-personal-account`, `claude-work-account`), run the installer once per account with `CLAUDE_CONFIG_DIR` pointed at each account's config folder:

```bash
CLAUDE_CONFIG_DIR=/path/to/claude-personal-account ./install.sh
CLAUDE_CONFIG_DIR=/path/to/claude-work-account ./install.sh
```

Each account gets its own wrapper (`statusline-wrapper-<basename>.sh`) and settings entry, but they all share the single `statusline.py` from this repo. Quota is isolated at runtime — see [How multi-account isolation works](#how-multi-account-isolation-works).

### Manual installation (no installer)

1. Ensure `python3` is on your PATH.
2. Create a wrapper at `~/.claude/statusline-wrapper.sh`:
   ```bash
   #!/bin/bash
   exec python3 "/absolute/path/to/statusline.py"
   ```
   `chmod +x` it.
3. Add to the `settings.json` of the account (inside `$CLAUDE_CONFIG_DIR` or `~/.claude/`):
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline-wrapper.sh",
       "padding": 0
     }
   }
   ```
4. Restart Claude Code.

Credentials are located automatically from `CLAUDE_CONFIG_DIR/.credentials.json` (falling back to `~/.claude/.credentials.json`). **No manual path configuration is required.**

## Upgrading

### From the current (single-file) setup

```bash
cd ~/Workspaces/ai-tools && git pull
```

Then restart any open Claude Code sessions. All installed accounts point to the same `statusline.py`, so one pull upgrades everything.

### From a previous per-account copy setup

Earlier versions of this project suggested copying `statusline.py` into each account folder (e.g. inside `CLAUDE_CONFIG_DIR`) and hardcoding `CREDENTIALS_FILE` per copy. If you still have that layout, consolidate once with these steps:

1. **Pull the latest `statusline.py`** in this repo.
2. **Delete the per-account copies** of `statusline.py` (keep your `settings.json` and `.credentials.json`):
   ```bash
   rm /path/to/claude-personal-account/statusline.py
   rm /path/to/claude-work-account/statusline.py
   # ...one per account
   ```
3. **Repoint each wrapper** in `~/.claude/` to the repo file:
   ```bash
   REPO="$HOME/Workspaces/ai-tools/claude-statusline/statusline.py"
   for w in ~/.claude/statusline*-wrapper.sh ~/.claude/statusline-wrapper.sh; do
     [ -f "$w" ] || continue
     cat > "$w" <<EOF
   #!/bin/bash
   exec python3 "$REPO"
   EOF
     chmod +x "$w"
   done
   ```
4. **Clear stale cache** from the old shared cache location (optional but recommended):
   ```bash
   rm -f /tmp/claude-statusline-cache/*.json
   ```
5. **Restart** each Claude Code session.

From now on, upgrades are just `git pull` in step 1.

## How multi-account isolation works

The script resolves the active account on every invocation:

- **Credentials** are read from `$CLAUDE_CONFIG_DIR/.credentials.json` (or `~/.claude/.credentials.json`) — guaranteeing each session uses its own OAuth token.
- **Cache** lives in `/tmp/claude-statusline-cache/<hash>/`, where `<hash>` is derived from the config dir path. Concurrent sessions on different accounts cannot read each other's quota data.
- **Fallback**: if the API is unreachable and no cache exists, the script uses the `rate_limits` block that Claude Code already passes in on stdin — so the 5h / 7d bars stay correct even offline.

## Line 1 — Session information

| Icon | Information | Example | Description |
|------|-------------|---------|-------------|
| — | **Model** | `Opus 4.6` or `Opus 4.6 fast` | Active model name. Shows `fast` when fast mode is enabled |
| 📁 | **Directory** | `📁 my-project` | Current working directory |
| 🌿 | **Git branch** | `🌿 main±3` | Current branch. `±N` = number of modified files in the working tree |
| 📝 | **Lines edited** | `📝 +156−23` | Lines added (+) and removed (−) during the session. Shown next to the branch |
| ⏩ | **Execution time** | `⏩ 4m32s` | Total API call time. Formats: `350ms`, `45s`, `4m32s`, `1h02m30s` |
| 📊 | **Context window** | `📊 42%` | Percentage of the context window in use |
| 🧩 | **Tokens** | `🧩 71↓ 17.6k↑` | Session tokens: input (↓) and output (↑). Suffixes: `k` (thousands), `M` (millions) |
| 💲 | **Cost** | `💲 1.37` | Total session cost in USD |

### Dynamic colors

Percentage values use colors to indicate usage level:

- **Green** — below 50%
- **Yellow** — between 50% and 80%
- **Red** — above 80%

## Line 2 — Quota usage

| Icon | Information | Example | Description |
|------|-------------|---------|-------------|
| ⏰ | **Session (5h)** | `⏰ Session ↺2h30m (20:45) ██████░░░░ 55%` | 5-hour window usage. Shows remaining time and local reset time in parentheses |
| 📅 | **Week (7d)** | `📅 Week ↺fri 14:00 ████░░░░░░ 35%` | 7-day window usage. Shows weekday and time of reset |
| — | **Per-model** | `opus ██████░░░░ 60%` | Per-model 7-day usage (opus, sonnet, haiku). Only shown when data is available |
| — | **Extra usage** | `extra ██░░░░ 18% $3.60/$20.00` | Pay-as-you-go credits, if enabled. Shows usage percentage and USD amounts |

Each item displays a progress bar using the same color coding (green/yellow/red).

## Cache

Cached data is written to `/tmp/claude-statusline-cache/<account-hash>/` to avoid excessive API calls:

| File | TTL | Content |
|------|-----|---------|
| `quota.json` | 60s | Quota data from the Anthropic API |
| `debug_input.json` | — | Last JSON input received (for debugging) |

To clear cache for **all** accounts:

```bash
rm -rf /tmp/claude-statusline-cache
```

## Requirements

- Python 3.10+
- Git (for branch information)
- Claude Code account with OAuth (for quota data)
