#!/usr/bin/env bash
#
# claude-loop.sh — Ralph loop with quota handling for headless Claude Code.
#
# Runs a task in headless mode (-p) autonomously. When the subscription quota is
# hit, it sleeps (a fixed delay OR until a given time) and resumes the SAME
# session once the window resets. Stops when Claude writes the completion marker
# to its output.
#
# Usage:
#   claude-loop.sh --path <dir> --prompt "<work>" [options]
#
# Required:
#   -d, --path DIR        Project directory the session runs in
#   -p, --prompt TEXT     Initial instruction (the real start of the work)
#
# Config selection (optional; --config-dir wins over --account):
#   -a, --account NAME    Account name resolved from the accounts file
#                         (~/.config/ai-tools/claude-loop/accounts). Optional.
#       --config-dir DIR  CLAUDE_CONFIG_DIR to use directly (skips the accounts file)
#
# Account management:
#       --add-account NAME [--config-dir DIR]
#                         Add an account to the accounts file (prompts for the
#                         config dir if --config-dir is omitted) and exit
#       --list-accounts   List configured accounts and exit
#
# Wait when quota is hit (pick one; --until wins on the first wait):
#   -s, --sleep DUR       Duration of each wait cycle (default: 30m)
#   -u, --until HH:MM     Sleep until this time (next occurrence) on the FIRST
#                         quota hit; later cycles fall back to --sleep
#
# Session (deterministic by UUID; an ambiguous name would hang in headless):
#   -S, --session UUID    Fixed session UUID. First call creates it (--session-id),
#                         later calls resume it (--resume). Use 'auto' to generate one.
#   -N, --session-name S  Display name (shown in the /resume picker). Applied only
#                         when the session is created.
#
# Optional:
#   -r, --resume          Treat the session as ALREADY existing from the first call
#                         (resume the most recent in --path, or the given --session).
#                         Use after an interactive brainstorm — EXIT that session first.
#   -l, --log-dir DIR     Log output directory (default: ~/.claude-loop-logs)
#   -m, --max-iters N     Safety cap on iterations (default: 300)
#       --marker TEXT     Completion marker (default: <<<TASK_COMPLETE>>>)
#       --perm MODE       Permission mode (default: bypass)
#                         bypass = --dangerously-skip-permissions (deny rules still apply)
#                         accept = --permission-mode acceptEdits (more restrictive)
#   -h, --help            This help
#
# Accounts map to CLAUDE_CONFIG_DIR via the accounts file. See --add-account.
#
set -uo pipefail

CLAUDE_BIN="${CLAUDE_LOOP_BIN:-$HOME/.local/bin/claude}"

ACCOUNT=""
WORKDIR=""
PROMPT=""
SLEEP_DUR="30m"
UNTIL=""
SESSION=""
SESSION_NAME=""
RESUME_FIRST=0
LOG_DIR=""
MAX_ITERS=300
MARKER="<<<TASK_COMPLETE>>>"
PERM="bypass"
CONFIG_DIR_ARG=""
ADD_ACCOUNT=""
DO_LIST=0
CFG_DIR=""
ACCOUNTS_FILE="${CLAUDE_LOOP_ACCOUNTS_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-tools/claude-loop/accounts}"

usage() {
    awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1 && !/^#/{exit}' "$0"
    exit "${1:-0}"
}

gen_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr 'A-Z' 'a-z'
    elif [ -r /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    else
        echo "Error: could not generate a UUID (install uuidgen)" >&2; exit 1
    fi
}

expand_tilde() {
    local p="$1"
    case "$p" in
        "~")   printf '%s' "$HOME" ;;
        "~/"*) printf '%s' "$HOME/${p#\~/}" ;;
        *)     printf '%s' "$p" ;;
    esac
}

account_path() {
    local want="$1" line name path
    [ -f "$ACCOUNTS_FILE" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="${line#"${line%%[![:space:]]*}"}"
        case "$line" in ''|'#'*) continue ;; esac
        case "$line" in *'='*) ;; *) continue ;; esac
        name="${line%%=*}"
        path="${line#*=}"
        name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
        path="${path#"${path%%[![:space:]]*}"}"; path="${path%"${path##*[![:space:]]}"}"
        if [ "$name" = "$want" ]; then
            expand_tilde "$path"
            return 0
        fi
    done < "$ACCOUNTS_FILE"
    return 1
}

add_account() {
    local name="$1" raw="$2" dir ans tmp line trimmed lname
    [ -n "$name" ] || { echo "Error: --add-account requires a name" >&2; exit 1; }
    case "$name" in
        *'='*|*$'\n'*) echo "Error: account name must not contain '=' or newlines" >&2; exit 1 ;;
    esac
    if [ -z "$raw" ]; then
        if [ -t 0 ]; then
            printf 'Config dir for "%s": ' "$name" >&2
            IFS= read -r raw
        else
            echo "Error: --config-dir is required for --add-account when not interactive" >&2
            exit 1
        fi
    fi
    dir="$(expand_tilde "$raw")"
    [ -d "$dir" ] || { echo "Error: config dir does not exist: $dir" >&2; exit 1; }

    mkdir -p "$(dirname "$ACCOUNTS_FILE")" || { echo "Error: could not create $(dirname "$ACCOUNTS_FILE")" >&2; exit 1; }
    touch "$ACCOUNTS_FILE"

    if account_path "$name" >/dev/null 2>&1; then
        if [ -t 0 ]; then
            printf 'Account "%s" already exists. Overwrite? [y/N] ' "$name" >&2
            IFS= read -r ans
            case "$ans" in y|Y) ;; *) echo "Aborted." >&2; exit 1 ;; esac
        else
            echo "Error: account \"$name\" already exists (refusing to overwrite non-interactively)" >&2
            exit 1
        fi
        tmp="$(mktemp)"
        trap 'rm -f "$tmp"' EXIT
        while IFS= read -r line || [ -n "$line" ]; do
            trimmed="${line#"${line%%[![:space:]]*}"}"
            case "$trimmed" in ''|'#'*) printf '%s\n' "$line" >> "$tmp"; continue ;; esac
            case "$trimmed" in *'='*) ;; *) printf '%s\n' "$line" >> "$tmp"; continue ;; esac
            lname="${trimmed%%=*}"; lname="${lname#"${lname%%[![:space:]]*}"}"; lname="${lname%"${lname##*[![:space:]]}"}"
            [ "$lname" = "$name" ] && continue
            printf '%s\n' "$line" >> "$tmp"
        done < "$ACCOUNTS_FILE"
        mv "$tmp" "$ACCOUNTS_FILE" || { echo "Error: could not rewrite accounts file" >&2; exit 1; }
        trap - EXIT
    fi

    printf '%s = %s\n' "$name" "$raw" >> "$ACCOUNTS_FILE"
    echo "Saved account \"$name\" -> $raw" >&2
}

list_accounts() {
    if [ ! -f "$ACCOUNTS_FILE" ]; then
        echo "No accounts configured. Add one with: claude-loop --add-account <name> --config-dir <dir>" >&2
        return 0
    fi
    local line trimmed name found=0
    while IFS= read -r line || [ -n "$line" ]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        case "$trimmed" in ''|'#'*) continue ;; esac
        case "$trimmed" in *'='*) ;; *) continue ;; esac
        name="${trimmed%%=*}"
        name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
        printf '%s\n' "$name"
        found=1
    done < "$ACCOUNTS_FILE"
    [ "$found" = 1 ] || echo "No accounts configured. Add one with: claude-loop --add-account <name> --config-dir <dir>" >&2
}

while [ $# -gt 0 ]; do
    case "$1" in
        -a|--account)      ACCOUNT="$2"; shift 2 ;;
        -d|--path)         WORKDIR="$2"; shift 2 ;;
        -p|--prompt)       PROMPT="$2"; shift 2 ;;
        -s|--sleep)        SLEEP_DUR="$2"; shift 2 ;;
        -u|--until)        UNTIL="$2"; shift 2 ;;
        -S|--session)      SESSION="$2"; shift 2 ;;
        -N|--session-name) SESSION_NAME="$2"; shift 2 ;;
        -r|--resume)       RESUME_FIRST=1; shift ;;
        -l|--log-dir)      LOG_DIR="$2"; shift 2 ;;
        -m|--max-iters)    MAX_ITERS="$2"; shift 2 ;;
        --marker)          MARKER="$2"; shift 2 ;;
        --perm)            PERM="$2"; shift 2 ;;
        --config-dir)      CONFIG_DIR_ARG="$2"; shift 2 ;;
        --add-account)     ADD_ACCOUNT="$2"; shift 2 ;;
        --list-accounts)   DO_LIST=1; shift ;;
        -h|--help)         usage 0 ;;
        *) echo "Unknown argument: $1" >&2; usage 1 ;;
    esac
done

if [ "$DO_LIST" = 1 ]; then
    list_accounts
    exit 0
fi

if [ -n "$ADD_ACCOUNT" ]; then
    add_account "$ADD_ACCOUNT" "$CONFIG_DIR_ARG"
    exit 0
fi

[ -n "$WORKDIR" ] || { echo "Error: --path is required" >&2; usage 1; }
[ -n "$PROMPT" ]  || { echo "Error: --prompt is required" >&2; usage 1; }

if [ -n "$UNTIL" ] && ! [[ "$UNTIL" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "Error: --until must be HH:MM (24h), e.g. 04:05" >&2; exit 1
fi

if [ "$SESSION" = "auto" ]; then
    SESSION="$(gen_uuid)"
    echo "Generated session: $SESSION" >&2
elif [ -n "$SESSION" ] && ! [[ "$SESSION" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    echo "Error: --session must be a valid UUID (or 'auto'): $SESSION" >&2; exit 1
fi

if [ -n "$CONFIG_DIR_ARG" ] && [ -n "$ACCOUNT" ]; then
    echo "Error: pass either --account or --config-dir, not both" >&2; exit 1
fi

if [ -n "$CONFIG_DIR_ARG" ]; then
    CFG_DIR="$(expand_tilde "$CONFIG_DIR_ARG")"
    [ -d "$CFG_DIR" ] || { echo "Config dir does not exist: $CFG_DIR" >&2; exit 1; }
elif [ -n "$ACCOUNT" ]; then
    CFG_DIR="$(account_path "$ACCOUNT")" || { echo "Error: unknown account '$ACCOUNT' (not in $ACCOUNTS_FILE)" >&2; exit 1; }
    [ -d "$CFG_DIR" ] || { echo "Config dir for account '$ACCOUNT' does not exist: $CFG_DIR" >&2; exit 1; }
elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    CFG_DIR="$CLAUDE_CONFIG_DIR"
fi

[ -d "$WORKDIR" ]    || { echo "Path does not exist: $WORKDIR" >&2; exit 1; }
[ -x "$CLAUDE_BIN" ] || { echo "claude not found/executable: $CLAUDE_BIN" >&2; exit 1; }

case "$PERM" in
    bypass) PERM_FLAGS=(--dangerously-skip-permissions) ;;
    accept) PERM_FLAGS=(--permission-mode acceptEdits) ;;
    *) echo "Invalid perm (use bypass|accept): $PERM" >&2; exit 1 ;;
esac

[ -n "$CFG_DIR" ] && export CLAUDE_CONFIG_DIR="$CFG_DIR"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm use node >/dev/null 2>&1

cd "$WORKDIR" || exit 1

LOG_DIR="${LOG_DIR:-${CLAUDE_LOOP_LOG_DIR:-$HOME/.claude-loop-logs}}"
mkdir -p "$LOG_DIR" || { echo "Could not create log-dir: $LOG_DIR" >&2; exit 1; }
if [ -n "$ACCOUNT" ]; then
    LABEL="$ACCOUNT"
elif [ -n "$CFG_DIR" ]; then
    LABEL="$(basename "$CFG_DIR")"
else
    LABEL="default"
fi
STAMP="${LABEL}-$(basename "$WORKDIR")"
LAST_LOG="$LOG_DIR/${STAMP}.last"
FULL_LOG="$LOG_DIR/${STAMP}.full.log"

DONE_INSTRUCTION="When the task is 100% complete and verified, write on a line by itself, exactly: ${MARKER} — do not write this marker before you have genuinely finished."
INITIAL_PROMPT="${PROMPT}

${DONE_INSTRUCTION}"
CONTINUE_PROMPT="Continue the previous task from exactly where it stopped. ${DONE_INSTRUCTION}"

QUOTA_REGEX="you've hit your.*limit|usage limit reached|reset[s]? at|weekly limit|opus limit"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$FULL_LOG"; }

seconds_until() {
    local target="$1" now_s target_s
    now_s=$(date +%s)
    target_s=$(date -d "today $target" +%s)
    if [ "$target_s" -le "$now_s" ]; then
        target_s=$(date -d "tomorrow $target" +%s)
    fi
    echo $((target_s - now_s))
}

log "=== LOOP START | account=${ACCOUNT:-—} cfg=${CFG_DIR:-<default>} path=$WORKDIR perm=$PERM sleep=$SLEEP_DUR until=${UNTIL:-—} session=${SESSION:-—} resume=$RESUME_FIRST ==="
log "CLAUDE_CONFIG_DIR=${CFG_DIR:-<default ~/.claude>} | LOG_DIR=$LOG_DIR"

iter=0
first=1
used_until=0
while [ "$iter" -lt "$MAX_ITERS" ]; do
    iter=$((iter + 1))

    if [ "$first" = 1 ] && [ "$RESUME_FIRST" = 0 ]; then
        RUN_PROMPT="$INITIAL_PROMPT"
        if [ -n "$SESSION" ]; then
            CONT_FLAGS=(--session-id "$SESSION")
            [ -n "$SESSION_NAME" ] && CONT_FLAGS+=(--name "$SESSION_NAME")
        else
            CONT_FLAGS=()
        fi
    else
        RUN_PROMPT="$CONTINUE_PROMPT"
        if [ -n "$SESSION" ]; then
            CONT_FLAGS=(--resume "$SESSION")
        else
            CONT_FLAGS=(--continue)
        fi
    fi
    first=0

    log "--- iteration $iter/$MAX_ITERS (${CONT_FLAGS[*]:-new}) ---"
    "$CLAUDE_BIN" "${CONT_FLAGS[@]}" "${PERM_FLAGS[@]}" -p "$RUN_PROMPT" 2>&1 | tee "$LAST_LOG"
    cat "$LAST_LOG" >> "$FULL_LOG"

    if grep -qF "$MARKER" "$LAST_LOG"; then
        log "=== DONE: marker found on iteration $iter ==="
        exit 0
    fi

    if grep -qiE "$QUOTA_REGEX" "$LAST_LOG"; then
        if [ -n "$UNTIL" ] && [ "$used_until" = 0 ]; then
            secs=$(seconds_until "$UNTIL")
            used_until=1
            log "Quota hit. Sleeping until $UNTIL (~$((secs / 60)) min)..."
            sleep "$secs"
        else
            log "Quota hit. Sleeping $SLEEP_DUR before retrying..."
            sleep "$SLEEP_DUR"
        fi
        continue
    fi

    log "No marker and no quota: keep working (Ralph loop). Short 10s pause."
    sleep 10
done

log "=== STOPPED: reached the $MAX_ITERS-iteration cap without a marker. Review $FULL_LOG ==="
exit 2
