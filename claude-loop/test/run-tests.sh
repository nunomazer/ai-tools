#!/usr/bin/env bash
# Black-box test suite for claude-loop.sh. No external deps.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../claude-loop.sh"
FAKE="$HERE/fake-claude.sh"
chmod +x "$FAKE" "$SCRIPT"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
WORK="$TMP/work"; mkdir -p "$WORK"

export CLAUDE_LOOP_BIN="$FAKE"
export CLAUDE_LOOP_LOG_DIR="$TMP/logs"
export CLAUDE_LOOP_ACCOUNTS_FILE="$TMP/accounts"

pass=0; fail=0
ok() { printf 'ok   - %s\n' "$1"; pass=$((pass+1)); }
no() { printf 'FAIL - %s\n' "$1"; fail=$((fail+1)); }
assert_contains() { case "$2" in *"$1"*) ok "$3" ;; *) no "$3"; printf '       wanted substring: %s\n       in: %s\n' "$1" "$2" ;; esac; }
assert_missing()  { case "$2" in *"$1"*) no "$3"; printf '       unexpected substring: %s\n' "$1" ;; *) ok "$3" ;; esac; }
assert_exit()     { if [ "$1" = "$2" ]; then ok "$3"; else no "$3"; printf '       wanted exit %s got %s\n' "$2" "$1"; fi; }

# Run the script with CLAUDE_CONFIG_DIR unset unless a test sets it explicitly.
run() { env -u CLAUDE_CONFIG_DIR bash "$SCRIPT" "$@"; }

# --- Task 1: --config-dir resolution ---
mkdir -p "$TMP/cfgA"
out="$(run --path "$WORK" --prompt "x" --config-dir "$TMP/cfgA" 2>&1)"; rc=$?
assert_exit "$rc" 0 "config-dir: exits 0 when marker found"
assert_contains "FAKE_CLAUDE_CONFIG_DIR=[$TMP/cfgA]" "$out" "config-dir: exported to claude"

# account is optional: no --account, no --config-dir, no ambient -> not exported
out="$(run --path "$WORK" --prompt "x" 2>&1)"; rc=$?
assert_exit "$rc" 0 "no-account: exits 0 (account not required)"
assert_contains "FAKE_CLAUDE_CONFIG_DIR=[<unset>]" "$out" "no-account: CLAUDE_CONFIG_DIR left unset"

# --- Task 2: --account resolution from accounts file (incl. hyphen) + ambient ---
mkdir -p "$TMP/cfgWork" "$TMP/cfgCto" "$TMP/cfgEnv"
cat > "$CLAUDE_LOOP_ACCOUNTS_FILE" <<EOF
# comment line
work          = $TMP/cfgWork

work-cto      = $TMP/cfgCto
EOF

out="$(run --path "$WORK" --prompt "x" --account work 2>&1)"; rc=$?
assert_exit "$rc" 0 "account: exits 0"
assert_contains "FAKE_CLAUDE_CONFIG_DIR=[$TMP/cfgWork]" "$out" "account: resolves from file"

out="$(run --path "$WORK" --prompt "x" --account work-cto 2>&1)"; rc=$?
assert_contains "FAKE_CLAUDE_CONFIG_DIR=[$TMP/cfgCto]" "$out" "account: hyphenated name works"

# ambient CLAUDE_CONFIG_DIR respected when no account/config-dir
out="$(CLAUDE_CONFIG_DIR="$TMP/cfgEnv" bash "$SCRIPT" --path "$WORK" --prompt "x" 2>&1)"; rc=$?
assert_contains "FAKE_CLAUDE_CONFIG_DIR=[$TMP/cfgEnv]" "$out" "ambient: CLAUDE_CONFIG_DIR honored"

# --- Task 3: error cases ---
out="$(run --path "$WORK" --prompt "x" --account work --config-dir "$TMP/cfgWork" 2>&1)"; rc=$?
assert_exit "$rc" 1 "exclusive: --account + --config-dir errors"
assert_contains "not both" "$out" "exclusive: clear message"

out="$(run --path "$WORK" --prompt "x" --account nope 2>&1)"; rc=$?
assert_exit "$rc" 1 "unknown account: errors"
assert_contains "unknown account 'nope'" "$out" "unknown account: clear message"

# --- Task 4: --add-account ---
ADDF="$TMP/accts_add"; rm -f "$ADDF"
mkdir -p "$TMP/cfgAdd"
out="$(CLAUDE_LOOP_ACCOUNTS_FILE="$ADDF" run --add-account newacct --config-dir "$TMP/cfgAdd" 2>&1)"; rc=$?
assert_exit "$rc" 0 "add: exits 0"
assert_contains "newacct = $TMP/cfgAdd" "$(cat "$ADDF")" "add: writes name = path"

# add-account does not require --path/--prompt
out="$(CLAUDE_LOOP_ACCOUNTS_FILE="$ADDF" run --add-account second --config-dir "$TMP/cfgAdd" 2>&1)"; rc=$?
assert_exit "$rc" 0 "add: no --path/--prompt needed"

# non-interactive missing --config-dir errors
out="$(CLAUDE_LOOP_ACCOUNTS_FILE="$ADDF" run --add-account third </dev/null 2>&1)"; rc=$?
assert_exit "$rc" 1 "add: missing config-dir non-interactive errors"

# nonexistent dir errors
out="$(CLAUDE_LOOP_ACCOUNTS_FILE="$ADDF" run --add-account bad --config-dir "$TMP/nope" 2>&1)"; rc=$?
assert_exit "$rc" 1 "add: nonexistent config-dir errors"

# invalid name (contains =) rejected
out="$(CLAUDE_LOOP_ACCOUNTS_FILE="$ADDF" run --add-account "bad=name" --config-dir "$TMP/cfgAdd" 2>&1)"; rc=$?
assert_exit "$rc" 1 "add: name with = rejected"
assert_contains "must not contain" "$out" "add: = rejection message"

# duplicate non-interactive refuses to overwrite
out="$(CLAUDE_LOOP_ACCOUNTS_FILE="$ADDF" run --add-account newacct --config-dir "$TMP/cfgAdd" </dev/null 2>&1)"; rc=$?
assert_exit "$rc" 1 "add: duplicate non-interactive refused"
assert_contains "already exists" "$out" "add: duplicate message"

# --- Task 5: --list-accounts ---
LISTF="$TMP/accts_list"
cat > "$LISTF" <<EOF
# header
alpha = $TMP/cfgWork
beta  = $TMP/cfgCto
EOF
out="$(CLAUDE_LOOP_ACCOUNTS_FILE="$LISTF" run --list-accounts 2>&1)"; rc=$?
assert_exit "$rc" 0 "list: exits 0"
assert_contains "alpha" "$out" "list: shows alpha"
assert_contains "beta" "$out" "list: shows beta"
assert_missing "$TMP/cfgWork" "$out" "list: hides full paths"

out="$(CLAUDE_LOOP_ACCOUNTS_FILE="$TMP/none" run --list-accounts 2>&1)"; rc=$?
assert_exit "$rc" 0 "list: empty exits 0"
assert_contains "No accounts configured" "$out" "list: empty message"

echo "----"
echo "PASS=$pass FAIL=$fail"
[ "$fail" = 0 ]
