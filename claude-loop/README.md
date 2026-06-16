# Claude Loop

Runs a task in **headless Claude Code** (`-p`) autonomously and resiliently to quota. It's a *Ralph loop* (run the agent in a loop until the task is done) with built-in usage-limit handling: when the subscription hits its quota, the script **sleeps and resumes the same session** once the window resets. Multi-account aware on the same machine via `CLAUDE_CONFIG_DIR`.

```bash
claude-loop --account work \
            --path ~/Workspaces/my-project \
            --prompt "Implement the recorder mp4 export with tests." \
            --until 04:05
```

## Why it exists

Claude Code has **no** automatic resume after a quota reset. In interactive mode, hitting the limit leaves the process **alive but blocked** at the REPL — and two sessions writing the same transcript corrupt it (there is no file locking). In headless mode (`-p`) the process **exits cleanly** on quota, which makes it safe for an external loop to wait for the reset and resume with `--continue`. This script is that loop.

## Installation

```bash
cd ~/Workspaces/ai-tools/claude-loop
./install.sh        # creates symlink ~/.local/bin/claude-loop -> claude-loop.sh
```

Upgrades: `git pull` in the repo (the symlink points at the versioned file).

## Usage

```
claude-loop --path <dir> --prompt "<work>" [options]
```

### Required

| Flag | Description |
|------|-------------|
| `-d, --path DIR` | Project directory the session runs in |
| `-p, --prompt TEXT` | Initial instruction (the real start of the work) |

### Config selection

`--config-dir` wins over `--account`; both are optional.

| Flag | Description |
|------|-------------|
| `-a, --account NAME` | Account name resolved from the accounts file (see [Accounts](#accounts)) |
| `--config-dir DIR` | `CLAUDE_CONFIG_DIR` to use directly (skips the accounts file) |

### Wait when quota is hit

| Flag | Description |
|------|-------------|
| `-s, --sleep DUR` | Duration of each wait cycle (default: `30m`). Accepts the `sleep` format (`30m`, `1h`, `1800`) |
| `-u, --until HH:MM` | Sleep until this time (next occurrence) on the **first** quota hit; later cycles fall back to `--sleep` |

`--until` takes priority on the first wait (ideal when you know the reset time). If you're still in quota when it wakes, it falls into the `--sleep` cycle until it clears.

### Session

| Flag | Description |
|------|-------------|
| `-S, --session UUID` | Fixed session UUID for deterministic resume. The first call creates it with `--session-id`, later calls resume with `--resume`. Pass `auto` to have the script generate (and log) a UUID |
| `-N, --session-name S` | Session display name (shown in the `/resume` picker). Applied only on creation |

**Name vs UUID:** Claude Code identifies sessions by **UUID**; names (`--name`) are just display labels. In headless always use the **UUID** — an ambiguous `--resume <name>` opens the interactive picker, which hangs with nobody to answer. Without `--session`, the script uses `--continue` (most recent session in `--path`), which is more fragile when several sessions touched the same directory.

### Optional

| Flag | Default | Description |
|------|---------|-------------|
| `-r, --resume` | off | Treat the session as **already existing** from the first call (resume the most recent in `--path`, or the given `--session`). Use after an interactive brainstorm — **exit** that session first |
| `-l, --log-dir DIR` | `~/.claude-loop-logs` | Log output directory |
| `-m, --max-iters N` | `300` | Iteration cap (safety brake) |
| `--marker TEXT` | `<<<TASK_COMPLETE>>>` | Marker that signals completion |
| `--perm MODE` | `bypass` | `bypass` = `--dangerously-skip-permissions` · `accept` = `--permission-mode acceptEdits` |

## How the loop works

Each iteration:

1. Runs `claude -p` headless on the right account.
2. **Found the marker** in the output? → exit success (exit 0).
3. **Detected quota**? → sleep (`--until` on the first time, otherwise `--sleep`) and retry.
4. **Neither done nor quota**? → keep working (Ralph loop), short 10s pause.
5. Reached `--max-iters` without the marker → stop and ask for review (exit 2).

The completion marker is **appended automatically** to the prompt, instructing the model to write it only when the task is genuinely verified.

## Recommended flow (brainstorm → autonomous)

To resume **exactly** the brainstorm session, pin a UUID to it and pass the same one to the loop:

```bash
# 1) Generate a UUID and brainstorm in the interactive session with that id; then EXIT (/exit)
U=$(uuidgen)
claude --session-id "$U"     # your usual alias + fixed id, in the project directory

# 2) Fire the loop resuming that same session (-r = already exists)
claude-loop -a work -d ~/Workspaces/my-project -r -S "$U" \
            -p "Execute the plan we agreed on, starting at step 1." \
            --until 04:05
```

Without pinning a UUID, use just `-r` and the loop continues the **most recent** session in `--path` via `--continue`. Either way, **exit** the interactive session before firing the loop — it avoids transcript conflicts between the interactive and the headless process.

## Permissions and safety

`--perm bypass` (default) skips prompts, but does **not** override `deny` rules or `PreToolUse` hooks — precedence is always **deny → ask → allow** in any mode. So protections like "never `git commit`" still hold, **as long as** they're implemented as a `deny` rule in `settings.json` or a hook. **Confirm this before running unattended.**

`--perm accept` is more restrictive (auto-approves edits only), but in headless it can **block** commands that would need approval (running tests, builds), since there's no one to answer the prompt.

> Headless = no review by you while it runs. Check `git diff` and the logs before accepting anything.

## Accounts

The account → `CLAUDE_CONFIG_DIR` mapping lives in the accounts file at `~/.config/ai-tools/claude-loop/accounts` (override with `CLAUDE_LOOP_ACCOUNTS_FILE`). Each line is `<name> = <CLAUDE_CONFIG_DIR path>`; `#` lines and blanks are ignored, and `~/` expands to `$HOME`. See [`accounts.example`](accounts.example) for the format.

```bash
# Add an account (prompts for the dir if --config-dir is omitted)
claude-loop --add-account work --config-dir ~/path/to/work-config

# List configured accounts
claude-loop --list-accounts
```

`--config-dir DIR` bypasses the file entirely and sets `CLAUDE_CONFIG_DIR` directly. When neither `--account` nor `--config-dir` is given, the current environment's `CLAUDE_CONFIG_DIR` (if any) is used.

## Logs

Written to `<log-dir>/<account>-<project>.full.log` (cumulative) and `.last` (last iteration, used to detect state). The directory comes from `--log-dir`, else the `CLAUDE_LOOP_LOG_DIR` env var, else `~/.claude-loop-logs`.

## Environment variables

| Var | Default | Use |
|-----|---------|-----|
| `CLAUDE_LOOP_ACCOUNTS_FILE` | `~/.config/ai-tools/claude-loop/accounts` | Accounts file (name → `CLAUDE_CONFIG_DIR`) |
| `CLAUDE_LOOP_BIN` | `~/.local/bin/claude` | Claude Code binary |
| `CLAUDE_LOOP_LOG_DIR` | `~/.claude-loop-logs` | Log directory |
| `CLAUDE_LOOP_BIN_DIR` | `~/.local/bin` | (install.sh) where to create the symlink |

## Limitations

- The quota reset time only appears as human-readable text; that's why waiting is by `--until`/cycles, not timed to the exact reset second.
- Completion depends on the model honoring the marker instruction — use a well-defined "done" criterion in the prompt.
- There is no native quota retry in Claude Code; this loop is the external mechanism.

## Requirements

- Bash, GNU `date` (Linux)
- Claude Code CLI installed and authenticated on each account
- `nvm` (optional; auto-loaded if present)
