# Claude Code Status Line

Custom two-line status line for the Claude Code CLI displaying session information and quota usage.

```
Opus 4.6 · 📁 my-project  🌿 main±3 📝 +156−23 · ⏩ 4m32s · 📊 42% · 🧩 71↓ 17.6k↑ · 💲 1.37
⏰ Session ↺2h30m (20:45) ██████░░░░ 55% · 📅 Week ↺fri 14:00 ████░░░░░░ 35% · opus ██████░░░░ 60%
```

## Installation

### 1. Copy the script

Copy `statusline.py` to an accessible location. If the path contains spaces, create a wrapper:

```bash
#!/bin/bash
# ~/.claude/statusline-wrapper.sh
exec python3 "/path/to/statusline.py"
```

```bash
chmod +x ~/.claude/statusline-wrapper.sh
```

### 2. Configure credentials

Update the `CREDENTIALS_FILE` constant in the script to point to your Claude Code `.credentials.json` file. This is required for fetching quota data from the API.

### 3. Configure Claude Code

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-wrapper.sh",
    "padding": 0
  }
}
```

If the script path has no spaces, you can point to it directly:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/statusline.py",
    "padding": 0
  }
}
```

### 4. Restart Claude Code

The status line will appear automatically on the next session.

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

The script caches data in `/tmp/claude-statusline-cache/` to avoid excessive API calls:

| File | TTL | Content |
|------|-----|---------|
| `quota.json` | 60s | Quota data from the Anthropic API |
| `debug_input.json` | — | Last JSON input received (for debugging) |

To clear the cache:

```bash
rm -rf /tmp/claude-statusline-cache
```

## Requirements

- Python 3.10+
- Git (for branch information)
- Claude Code account with OAuth (for quota data)
