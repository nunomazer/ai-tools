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
#   claude-loop.sh --account <account> --path <dir> --prompt "<work>" [options]
#
# Required:
#   -a, --account NAME    Account: personal | brevenlaw | brevenlaw-cto | softbinator
#   -d, --path DIR        Project directory the session runs in
#   -p, --prompt TEXT     Initial instruction (the real start of the work)
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
# Accounts map to CLAUDE_CONFIG_DIR via ACCOUNT_BASE_DIR below.
#
set -uo pipefail

ACCOUNT_BASE_DIR="${CLAUDE_LOOP_ACCOUNT_BASE:-$HOME/Insync/ademir.mazer.jr@gmail.com/Google Drive/claude}"
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
        -h|--help)         usage 0 ;;
        *) echo "Unknown argument: $1" >&2; usage 1 ;;
    esac
done

[ -n "$ACCOUNT" ] || { echo "Error: --account is required" >&2; usage 1; }
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

case "$ACCOUNT" in
    personal)      CFG_DIR="$ACCOUNT_BASE_DIR/claude-personal-account" ;;
    brevenlaw)     CFG_DIR="$ACCOUNT_BASE_DIR/claude-brevenlaw-account" ;;
    brevenlaw-cto) CFG_DIR="$ACCOUNT_BASE_DIR/claude-brevenlaw-account-cto" ;;
    softbinator)   CFG_DIR="$ACCOUNT_BASE_DIR/claude-softbinator-account" ;;
    *) echo "Unknown account: $ACCOUNT" >&2; exit 1 ;;
esac
[ -d "$CFG_DIR" ]    || { echo "Config dir does not exist: $CFG_DIR" >&2; exit 1; }
[ -d "$WORKDIR" ]    || { echo "Path does not exist: $WORKDIR" >&2; exit 1; }
[ -x "$CLAUDE_BIN" ] || { echo "claude not found/executable: $CLAUDE_BIN" >&2; exit 1; }

case "$PERM" in
    bypass) PERM_FLAGS=(--dangerously-skip-permissions) ;;
    accept) PERM_FLAGS=(--permission-mode acceptEdits) ;;
    *) echo "Invalid perm (use bypass|accept): $PERM" >&2; exit 1 ;;
esac

export CLAUDE_CONFIG_DIR="$CFG_DIR"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm use node >/dev/null 2>&1

cd "$WORKDIR" || exit 1

LOG_DIR="${LOG_DIR:-${CLAUDE_LOOP_LOG_DIR:-$HOME/.claude-loop-logs}}"
mkdir -p "$LOG_DIR" || { echo "Could not create log-dir: $LOG_DIR" >&2; exit 1; }
STAMP="${ACCOUNT}-$(basename "$WORKDIR")"
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

log "=== LOOP START | account=$ACCOUNT path=$WORKDIR perm=$PERM sleep=$SLEEP_DUR until=${UNTIL:-—} session=${SESSION:-—} resume=$RESUME_FIRST ==="
log "CLAUDE_CONFIG_DIR=$CFG_DIR | LOG_DIR=$LOG_DIR"

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
