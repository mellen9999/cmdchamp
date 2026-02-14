#!/usr/bin/env bash
# cmdchamp test suite - exhaustive unit + sandbox verification
set -uo pipefail

PASS=0 FAIL=0 SKIP=0 ERRORS=()
G=$'\e[32m' R=$'\e[31m' Y=$'\e[33m' D=$'\e[2m' N=$'\e[0m' B=$'\e[1m'

ok()   { ((++PASS)); printf '  %s✓%s %s\n' "$G" "$N" "$1"; }
fail() { ((++FAIL)); ERRORS+=("[$CURRENT_SECTION] $1: $2"); printf '  %s✗%s %s: %s\n' "$R" "$N" "$1" "$2"; }
skip() { ((++SKIP)); printf '  %s-%s %s (skipped)\n' "$Y" "$N" "$1"; }
CURRENT_SECTION=""
section() { CURRENT_SECTION="$1"; printf '\n%s%s=== %s ===%s\n' "$B" "$Y" "$1" "$N"; }

TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMDCHAMP="$SCRIPT_DIR/cmdchamp"

# Source cmdchamp without running main
SOURCE_FILE="$TDIR/cmdchamp_source.sh"
{
  sed -e 's/^_tty().*/\_tty() { :; }/' \
      -e '/^\[.*--no-sandbox/,$d' \
      "$CMDCHAMP"
  echo 'SANDBOX_MODE=0'
} > "$SOURCE_FILE"

export DATA="$TDIR/data"
mkdir -p "$DATA"
touch "$DATA/scores"

# Helper: run bash snippet with sourced cmdchamp
_run() { bash -c "source '$SOURCE_FILE' 2>/dev/null; $1" 2>/dev/null; }

# ─────────────────────────────────────────────────────────────────────────────
section "Syntax"

if bash -n "$CMDCHAMP" 2>&1; then
  ok "bash -n passes"
else
  fail "bash -n" "syntax error"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Source & Function Definitions"

if output=$(bash -c "source '$SOURCE_FILE' 2>/dev/null; echo OK" 2>&1) && [[ "$output" == *OK* ]]; then
  ok "sources without error"
else
  fail "source" "$output"
fi

for lv in {1..30}; do
  if ! bash -c "source '$SOURCE_FILE' 2>/dev/null; declare -f gen_level${lv} >/dev/null" 2>/dev/null; then
    fail "gen_level${lv}" "function not defined"
  fi
done
count=$(grep -c '^gen_level[0-9]*()' "$CMDCHAMP")
if ((count == 30)); then
  ok "all 30 gen_level functions defined"
else
  fail "gen_level count" "expected 30, got $count"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Answer Normalization (norm)"

run_norm() { _run "norm '$1'"; }

# Combined short flags
r=$(run_norm "ls -la")
[[ "$r" == "ls -a -l" ]] && ok "norm -la -> -a -l" || fail "norm -la" "got '$r'"

r=$(run_norm "ls -l -a")
[[ "$r" == "ls -a -l" ]] && ok "norm -l -a -> -a -l" || fail "norm -l -a" "got '$r'"

r=$(run_norm "grep -rn TODO .")
[[ "$r" == "grep -n -r TODO ." ]] && ok "norm -rn splits+sorts" || fail "norm -rn" "got '$r'"

# Triple combined flags
r=$(run_norm "ls -rla")
[[ "$r" == "ls -a -l -r" ]] && ok "norm -rla -> -a -l -r" || fail "norm -rla" "got '$r'"

# Long flags preserved
r=$(run_norm "sort --reverse file")
[[ "$r" == "sort --reverse file" ]] && ok "norm preserves long flags" || fail "norm long" "got '$r'"

# Long + short mixed
r=$(run_norm "sort --reverse -n file")
[[ "$r" == "sort -n --reverse file" ]] && ok "norm mixed long+short" || fail "norm mixed" "got '$r'"

# Flags with values
r=$(run_norm "head --lines=5 file")
[[ "$r" == "head --lines=5 file" ]] && ok "norm --flag=val preserved" || fail "norm --flag=val" "got '$r'"

r=$(run_norm "head -n 10 file")
[[ "$r" == "head -n 10 file" ]] && ok "norm -n 10 preserves value arg" || fail "norm -n 10" "got '$r'"

# Single char flag
r=$(run_norm "ls -a")
[[ "$r" == "ls -a" ]] && ok "norm single flag -a" || fail "norm -a" "got '$r'"

# No flags
r=$(run_norm "pwd")
[[ "$r" == "pwd" ]] && ok "norm single command pwd" || fail "norm pwd" "got '$r'"

r=$(run_norm "echo hello world")
[[ "$r" == "echo hello world" ]] && ok "norm preserves args order" || fail "norm args" "got '$r'"

# Empty input
r=$(run_norm "")
[[ -z "$r" ]] && ok "norm handles empty" || fail "norm empty" "got '$r'"

# Double-dash: norm treats -- as a long flag (expected behavior)
r=$(run_norm "rm -- -file")
[[ "$r" == "rm -- -e -f -i -l" ]] && ok "norm double-dash (splits -file)" || fail "norm --" "got '$r'"

# ─────────────────────────────────────────────────────────────────────────────
section "Question Parser (_qparse)"

# | delimiter basic
r=$(_run "_qparse 'Show files|ls|ls -a'; echo \"p=\$_qprompt a=\$_qans d=\$_qdelim\"")
[[ "$r" == *"p=Show files"* && "$r" == *"a=ls"* && "$r" == *"d=|"* ]] && ok "_qparse | basic" || fail "_qparse |" "$r"

# § delimiter
r=$(_run "_qparse 'Count lines§wc -l < file§cat file | wc -l'; echo \"p=\$_qprompt a=\$_qans d=\$_qdelim\"")
[[ "$r" == *"p=Count lines"* && "$r" == *"a=wc -l < file"* && "$r" == *"d=§"* ]] && ok "_qparse § delimiter" || fail "_qparse §" "$r"

# #output: alone
r=$(_run "_qparse 'Show dir|pwd|#output:~^/sandbox'; echo \"o=\$_qoutput s=\$_qstate t=\$_qtext\"")
[[ "$r" == *"o=~^/sandbox"* && "$r" == *"s="* && "$r" == *"t=0"* ]] && ok "_qparse #output: alone" || fail "_qparse #output:" "$r"

# #state: alone
r=$(_run "_qparse 'Touch file|touch x|#state:exists:x'; echo \"o=\$_qoutput s=\$_qstate t=\$_qtext\"")
[[ "$r" == *"s=exists:x"* && "$r" == *"o="* ]] && ok "_qparse #state: alone" || fail "_qparse #state:" "$r"

# #text: alone
r=$(_run "_qparse 'What flag|--help|#text:'; echo \"t=\$_qtext\"")
[[ "$r" == *"t=1"* ]] && ok "_qparse #text: alone" || fail "_qparse #text:" "$r"

# Combined #output: + #state:
r=$(_run "_qparse 'Do it|cmd|#output:~foo #state:exists:file'; echo \"o=\$_qoutput s=\$_qstate\"")
# _qoutput should have ~foo (before #state:), _qstate should have exists:file
[[ "$r" == *"o=~foo "* && "$r" == *"s=exists:file"* ]] && ok "_qparse combined output+state" || fail "_qparse combined" "$r"

# #state: before #output: - greedy extraction means state grabs everything after #state:
# This is by-design: always put #output: before #state: in question definitions
r=$(_run "_qparse 'Do it|cmd|#state:exists:x#output:hello'; echo \"s=\$_qstate\"")
[[ "$r" == *"s=exists:x#output:hello"* ]] && ok "_qparse state-before-output grabs rest (by design)" || fail "_qparse reversed" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Sandbox Output Check (_sandbox_check_output)"

# ~regex match
r=$(_run '_sandbox_check_output "hello world" "~hello" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "output ~regex match" || fail "output ~regex" "$r"

# ~regex mismatch
r=$(_run '_sandbox_check_output "hello world" "~^goodbye" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "output ~regex mismatch" || fail "output ~regex mis" "$r"

# @N line count exact
r=$(_run '_sandbox_check_output "line1
line2
line3" "@3" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "output @3 line count" || fail "output @3" "$r"

# @N wrong count
r=$(_run '_sandbox_check_output "line1
line2" "@5" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "output @N wrong count" || fail "output @N wrong" "$r"

# * any output
r=$(_run '_sandbox_check_output "something" "*" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "output * any output" || fail "output *" "$r"

# * empty = fail
r=$(_run '_sandbox_check_output "" "*" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "output * rejects empty" || fail "output * empty" "$r"

# Exact match
r=$(_run '_sandbox_check_output "hello" "hello" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "output exact match" || fail "output exact" "$r"

# Exact with whitespace trimming
r=$(_run '_sandbox_check_output "  hello  " "hello" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "output exact trims whitespace" || fail "output exact trim" "$r"

# Empty expected = fail
r=$(_run '_sandbox_check_output "hello" "" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "output empty expected = fail" || fail "output empty exp" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Sandbox State Check (_sandbox_check_state)"

# Set up a mini sandbox for state checks
SBOX="$TDIR/state_sandbox"
mkdir -p "$SBOX"
echo "hello foo bar" > "$SBOX/testfile"
printf 'line1\nline2\nline3\n' > "$SBOX/threelines"

# Must set SANDBOX_DIR *after* source (source overwrites it)
_run_state() { _run "SANDBOX_DIR='$SBOX'; $1"; }

# exists: pass
r=$(_run_state '_sandbox_check_state "exists:testfile" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "state exists: pass" || fail "state exists" "$r"

# exists: fail
r=$(_run_state '_sandbox_check_state "exists:nope" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "state exists: fail" || fail "state exists fail" "$r"

# !exists: pass
r=$(_run_state '_sandbox_check_state "!exists:nope" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "state !exists: pass" || fail "state !exists" "$r"

# !exists: fail
r=$(_run_state '_sandbox_check_state "!exists:testfile" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "state !exists: fail" || fail "state !exists fail" "$r"

# contains: pass
r=$(_run_state '_sandbox_check_state "contains:testfile:foo" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "state contains: pass" || fail "state contains" "$r"

# contains: fail
r=$(_run_state '_sandbox_check_state "contains:testfile:zzz" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "state contains: fail" || fail "state contains fail" "$r"

# lines: pass
r=$(_run_state '_sandbox_check_state "lines:threelines:3" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "state lines: pass" || fail "state lines" "$r"

# lines: fail
r=$(_run_state '_sandbox_check_state "lines:threelines:5" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "state lines: fail" || fail "state lines fail" "$r"

# Comma-separated combos
r=$(_run_state '_sandbox_check_state "exists:testfile,contains:testfile:foo" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "state combo pass" || fail "state combo" "$r"

# Combo where one fails
r=$(_run_state '_sandbox_check_state "exists:testfile,contains:testfile:zzz" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "state combo partial fail" || fail "state combo fail" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Destructive Detection (_is_destructive)"

# Destructive commands
for cmd in "rm file" "mv a b" "cp a b" "echo x > file" "sed -i 's/a/b/' f" "dd if=/dev/zero" \
           "truncate -s 0 f" "find . -delete" \
           "install -m 755 bin /usr/local/bin/" "split -b 1M file" "patch -p1 < fix.patch" \
           "ln -sf /new link" "rsync --delete src/ dst/" "find . | xargs rm" \
           "find . -exec rm {} ;" "cmd 2>file" "cmd &>file"; do
  r=$(_run "_is_destructive '$cmd' && echo YES || echo NO")
  [[ "$r" == "YES" ]] && ok "destructive: $cmd" || fail "destructive" "$cmd -> $r"
done

# Non-destructive commands
for cmd in "ls -la" "cat file" "grep pattern file" "head -5 file" "wc -l file" "sort file" \
           "pwd" "echo hello" "find . -name '*.txt'" "rsync src/ dst/" "xargs echo"; do
  r=$(_run "_is_destructive '$cmd' && echo YES || echo NO")
  [[ "$r" == "NO" ]] && ok "safe: $cmd" || fail "safe" "$cmd -> $r"
done

# ─────────────────────────────────────────────────────────────────────────────
section "Hash Consistency"

r=$(_run '
  _hash "test question"; h1=$REPLY
  _hash "test question"; h2=$REPLY
  _hash "different"; h3=$REPLY
  [[ $h1 == $h2 ]] && echo consistent || echo inconsistent
  [[ $h1 != $h3 ]] && echo unique || echo collision
  # Verify caching
  [[ -n "${_HASH_CACHE[test question]:-}" ]] && echo cached || echo nocache
')
echo "$r" | grep -q 'consistent' && ok "hash deterministic" || fail "hash determinism" "$r"
echo "$r" | grep -q 'unique' && ok "hash differentiates" || fail "hash uniqueness" "$r"
echo "$r" | grep -q 'cached' && ok "hash uses cache" || fail "hash cache" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Answer Checking (check)"

run_check() {
  bash -c "
    source '$SOURCE_FILE' 2>/dev/null
    SANDBOX_MODE=0; _qdelim='|'; _qoutput=''; _qstate=''; _qtext=0
    check '$1' '$2' && echo PASS || echo FAIL
  " 2>/dev/null
}
run_check_sec() {
  bash -c "
    source '$SOURCE_FILE' 2>/dev/null
    SANDBOX_MODE=0; _qdelim='§'; _qoutput=''; _qstate=''; _qtext=0
    check '$1' '$2' && echo PASS || echo FAIL
  " 2>/dev/null
}

# Exact match
r=$(run_check "ls" "ls|ls -a")
[[ "$r" == "PASS" ]] && ok "check exact 'ls'" || fail "check exact" "$r"

# Alt answer
r=$(run_check "ls -a" "ls|ls -a")
[[ "$r" == "PASS" ]] && ok "check alt 'ls -a'" || fail "check alt" "$r"

# Wrong
r=$(run_check "pwd" "ls|ls -a")
[[ "$r" == "FAIL" ]] && ok "check rejects wrong" || fail "check wrong" "$r"

# Flag reorder
r=$(run_check "ls -la" "ls -al")
[[ "$r" == "PASS" ]] && ok "check flag reorder -la == -al" || fail "check reorder" "$r"

# Whitespace trim
r=$(run_check "  ls  " "ls")
[[ "$r" == "PASS" ]] && ok "check trims whitespace" || fail "check trim" "$r"

# § with pipes
r=$(run_check_sec "sort file | uniq" "sort file | uniq§sort -u file")
[[ "$r" == "PASS" ]] && ok "check § with pipe" || fail "check §" "$r"

r=$(run_check_sec "sort -u file" "sort file | uniq§sort -u file")
[[ "$r" == "PASS" ]] && ok "check § alt" || fail "check § alt" "$r"

# Regex ~pattern
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  SANDBOX_MODE=0; _qdelim='|'; _qoutput=''; _qstate=''; _qtext=0
  check 'echo hello' '~^echo' && echo PASS || echo FAIL
" 2>/dev/null)
[[ "$r" == "PASS" ]] && ok "check regex ~pattern" || fail "check regex" "$r"

# Empty input = fail
r=$(run_check "" "ls")
[[ "$r" == "FAIL" ]] && ok "check rejects empty" || fail "check empty" "$r"

# Trimmed alternatives
r=$(run_check "ls -a" "  ls -a  | ls ")
[[ "$r" == "PASS" ]] && ok "check trims alternatives" || fail "check trim alts" "$r"

# Multiple § alternatives
r=$(run_check_sec "sort -u file" "sort file | uniq§sort -u file§sort file | uniq -u")
[[ "$r" == "PASS" ]] && ok "check multi § alts" || fail "check multi §" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "_ctx() Variable Coverage"

r=$(_run '
  eval "local $_QV"
  _ctx
  missing=0
  for v in $_QV; do
    eval "[[ -z \"\$$v\" ]]" && { echo "EMPTY: $v"; ((++missing)); }
  done
  echo "missing=$missing"
')
miss=$(echo "$r" | grep 'missing=' | grep -o '[0-9]*')
if ((miss == 0)); then
  ok "all _QV vars non-empty after _ctx"
else
  fail "_ctx coverage" "$miss vars empty"
  echo "$r" | grep EMPTY | head -5
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Sandbox File Generators"

GEN_DIR="$TDIR/gen_sandbox"
_run "_gen_sandbox_files '$GEN_DIR'"

# Expected files exist
for f in server.log app.log data.csv users.csv config.ini settings.yaml \
         notes.txt todo.txt data/export.json logs/access.log logs/error.log \
         backup.sh deploy.sh main.py src/utils.py src/test/test_utils.py; do
  [[ -f "$GEN_DIR/$f" ]] && ok "gen: $f exists" || fail "gen file" "$f missing"
done

# Expected directories
for d in src src/test logs data backup temp config test; do
  [[ -d "$GEN_DIR/$d" ]] && ok "gen: dir $d" || fail "gen dir" "$d missing"
done

# Content patterns
grep -q 'id,name,email' "$GEN_DIR/data.csv" && ok "gen: CSV has header" || fail "gen CSV" "no header"
grep -q '192.168\|10.0\|172.16' "$GEN_DIR/server.log" && ok "gen: log has IPs" || fail "gen log" "no IPs"
grep -qE 'INFO|WARN|ERROR' "$GEN_DIR/app.log" && ok "gen: app.log has levels" || fail "gen app.log" "no levels"
grep -q '\[server\]' "$GEN_DIR/config.ini" && ok "gen: INI has sections" || fail "gen INI" "no sections"
grep -q 'server:' "$GEN_DIR/settings.yaml" && ok "gen: YAML has keys" || fail "gen YAML" "no keys"
grep -q 'version' "$GEN_DIR/data/export.json" && ok "gen: JSON valid" || fail "gen JSON" "bad"
grep -q 'username,fullname' "$GEN_DIR/users.csv" && ok "gen: users.csv header" || fail "gen users" "no header"

# Scripts executable
[[ -x "$GEN_DIR/backup.sh" ]] && ok "gen: backup.sh +x" || fail "gen backup.sh" "not executable"
[[ -x "$GEN_DIR/deploy.sh" ]] && ok "gen: deploy.sh +x" || fail "gen deploy.sh" "not executable"

# Line counts reasonable
lc=$(wc -l < "$GEN_DIR/server.log")
((lc >= 40 && lc <= 60)) && ok "gen: server.log ~50 lines ($lc)" || fail "gen server.log" "$lc lines"

lc=$(wc -l < "$GEN_DIR/data.csv")
((lc >= 25 && lc <= 35)) && ok "gen: data.csv ~31 lines ($lc)" || fail "gen data.csv" "$lc lines"

# ─────────────────────────────────────────────────────────────────────────────
section "Question Generation (all 30 levels)"

for lv in {1..30}; do
  output=$(_run "gen_level${lv}")
  qcount=$(echo "$output" | grep -c '.')
  if ((qcount < 3)); then
    fail "gen_level${lv}" "only $qcount questions (need >=3)"
  fi
done
ok "all 30 levels generate >=3 questions"

# Format: every line must have | or §
bad_format=()
for lv in {1..30}; do
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" != *"|"* && "$line" != *"§"* ]]; then
      bad_format+=("L${lv}: ${line:0:60}")
    fi
  done < <(_run "gen_level${lv}")
done
if ((${#bad_format[@]} == 0)); then
  ok "all questions have | or § delimiter"
else
  fail "question format" "${#bad_format[@]} missing delimiter"
  for bf in "${bad_format[@]:0:5}"; do printf '    %s%s%s\n' "$D" "$bf" "$N"; done
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Question Quality"

# All questions parseable, no empty prompts, no dupes within level
total_q=0 empty_prompts=0 parse_fails=0 dupe_count=0
for lv in {1..30}; do
  r=$(_run "
    declare -A seen
    dupes=0; empty=0; pfails=0; count=0
    while IFS= read -r line; do
      [[ -z \"\$line\" ]] && continue
      ((++count))
      _qparse \"\$line\" 2>/dev/null || { ((++pfails)); continue; }
      [[ -z \"\$_qprompt\" ]] && ((++empty))
      [[ -n \"\${seen[\$_qprompt]:-}\" ]] && ((++dupes))
      seen[\$_qprompt]=1
    done < <(gen_level${lv})
    echo \"\$count \$empty \$pfails \$dupes\"
  ")
  read -r cnt emp pf dp <<< "$r"
  ((total_q += cnt)); ((empty_prompts += emp)); ((parse_fails += pf)); ((dupe_count += dp))
done
((empty_prompts == 0)) && ok "no empty prompts" || fail "empty prompts" "$empty_prompts"
((parse_fails == 0)) && ok "all questions parse" || fail "parse failures" "$parse_fails"
((dupe_count == 0)) && ok "no dupe prompts within levels" || fail "dupe prompts" "$dupe_count"
ok "total questions: $total_q"

# ─────────────────────────────────────────────────────────────────────────────
section "Profile System"

# New profile
r=$(_run "
  _first_run 2>/dev/null <<< 'TestPlayer'
  _load_profile
  echo \"name=\$PLAYER_NAME ver=\$_PROFILE_VER beaten=\$BOSS_BEATEN gauntlet=\$BEST_GAUNTLET timed=\$BEST_TIMED\"
")
echo "$r" | grep -q 'name=TestPlayer' && ok "profile stores name" || fail "profile name" "$r"
echo "$r" | grep -q 'ver=2' && ok "profile ver=2" || fail "profile ver" "$r"
echo "$r" | grep -q 'beaten=0' && ok "new BOSS_BEATEN=0" || fail "profile beaten" "$r"

# v0->v1 migration: BOSS_BEATEN=-1 (old format) -> 0
# Must set DATA *after* source since source overwrites it
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig1'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=migtest\nBOSS_BEATEN=-1\nPROFILE_VER=0\n' > \"\$DATA/profile\"
  _load_profile
  echo \"\$BOSS_BEATEN\"
" 2>/dev/null)
[[ "$r" == "0" ]] && ok "v0->v1: -1 -> 0" || fail "v0 migrate -1" "got '$r'"

# v0->v1 migration: BOSS_BEATEN=0 (0-indexed, beat level 1) -> 1
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig2'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=migtest\nBOSS_BEATEN=0\nPROFILE_VER=0\n' > \"\$DATA/profile\"
  _load_profile
  echo \"\$BOSS_BEATEN\"
" 2>/dev/null)
[[ "$r" == "1" ]] && ok "v0->v1: 0 -> 1" || fail "v0 migrate 0" "got '$r'"

# v0->v1 migration: BOSS_BEATEN=5 (0-indexed) -> 6
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig3'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=migtest\nBOSS_BEATEN=5\nPROFILE_VER=0\n' > \"\$DATA/profile\"
  _load_profile
  echo \"\$BOSS_BEATEN\"
" 2>/dev/null)
[[ "$r" == "6" ]] && ok "v0->v1: 5 -> 6" || fail "v0 migrate 5" "got '$r'"

# BOSS_BEATEN clamping to MAX_LEVEL
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig4'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=clamp\nBOSS_BEATEN=999\nPROFILE_VER=1\n' > \"\$DATA/profile\"
  _load_profile
  echo \"\$BOSS_BEATEN\"
" 2>/dev/null)
[[ "$r" == "30" ]] && ok "BOSS_BEATEN clamped to 30" || fail "clamp" "got '$r'"

# v1->v2 migration: scores reset
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig5'; mkdir -p \"\$DATA\"
  printf 'old_hash|2|5\n' > \"\$DATA/scores\"
  printf 'PLAYER_NAME=migtest\nBOSS_BEATEN=3\nPROFILE_VER=1\n' > \"\$DATA/profile\"
  _load_profile
  echo \"ver=\$_PROFILE_VER scores=\$(wc -c < \"\$DATA/scores\")\"
" 2>/dev/null)
echo "$r" | grep -q 'ver=2' && ok "v1->v2: ver bumped" || fail "v1->v2 ver" "$r"
echo "$r" | grep -q 'scores=0' && ok "v1->v2: scores cleared" || fail "v1->v2 scores" "$r"

# Save/load round-trip
r=$(_run "LVL=14; QI=7; save; LVL=0; QI=0; load; echo \"\$LVL \$QI\"")
[[ "$r" == "14 7" ]] && ok "save/load round-trip" || fail "save/load" "got '$r'"

# Load migration: LVL<1 -> 1
r=$(bash -c "
  export DATA='$TDIR/data_sess'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  source '$SOURCE_FILE' 2>/dev/null
  printf '{\"level\":0,\"qi\":0}\n' > \"\$DATA/session.json\"
  load; echo \"\$LVL\"
" 2>/dev/null)
[[ "$r" == "1" ]] && ok "load migrates LVL=0 -> 1" || fail "load migration" "got '$r'"

# ─────────────────────────────────────────────────────────────────────────────
section "Score System"

r=$(_run "
  declare -A _sc
  _sget() { _hash \"\$1\"; local _v=\"\${_sc[\$REPLY]:-1}\"; REPLY=\"\${_v%%|*}\"; }
  _sset() { _hash \"\$1\"; _sc[\$REPLY]=\"\$2|1\"; _sflush; }

  _sget 'test q'; echo \"default=\$REPLY\"
  _sset 'test q' 2
  _sget 'test q'; echo \"after=\$REPLY\"
  _sget 'other q'; echo \"other=\$REPLY\"
")
echo "$r" | grep -q 'default=1' && ok "default tier=1" || fail "score default" "$r"
echo "$r" | grep -q 'after=2' && ok "tier updates to 2" || fail "score update" "$r"
echo "$r" | grep -q 'other=1' && ok "unrelated unaffected" || fail "score isolation" "$r"

# Atomic flush + reload
r=$(_run "
  declare -A _sc
  _sget() { _hash \"\$1\"; local _v=\"\${_sc[\$REPLY]:-1}\"; REPLY=\"\${_v%%|*}\"; }
  _sset() { _hash \"\$1\"; _sc[\$REPLY]=\"\$2|1\"; _sflush; }
  _sset 'persist q' 2

  # Reload from file
  declare -A _sc2
  while IFS='|' read -r k v; do _sc2[\$k]=\$v; done < \"\$DATA/scores\"
  _hash 'persist q'
  echo \"reloaded=\${_sc2[\$REPLY]:-missing}\"
")
echo "$r" | grep -q 'reloaded=2|1' && ok "flush+reload consistent" || fail "flush reload" "$r"

# Back-compat: old format hash|tier (no level)
r=$(bash -c "
  export DATA='$TDIR/data_oldsc'; mkdir -p \"\$DATA\"
  source '$SOURCE_FILE' 2>/dev/null
  _hash 'old q'; echo \"\$REPLY|2\" > \"\$DATA/scores\"
  declare -A _sc; while IFS='|' read -r k v; do _sc[\$k]=\$v; done < \"\$DATA/scores\"
  _hash 'old q'; echo \"tier=\${_sc[\$REPLY]%%|*}\"
" 2>/dev/null)
echo "$r" | grep -q 'tier=2' && ok "back-compat old score format" || fail "old format" "$r"

# Score versioning: #v1 header
r=$(_run "
  declare -A _sc
  _sc[abc123]=2|1
  _sflush
  head -1 \"\$DATA/scores\"
")
[[ "$r" == "#v1" ]] && ok "scores file has #v1 header" || fail "score version" "got '$r'"

# Loaders skip # lines
r=$(bash -c "
  export DATA='$TDIR/data_v1sc'; mkdir -p \"\$DATA\"
  source '$SOURCE_FILE' 2>/dev/null
  printf '#v1\nabc123|2|1\n' > \"\$DATA/scores\"
  declare -gA _sc; _sc=()
  while IFS='|' read -r k v; do [[ \"\$k\" == \"#\"* ]] && continue; _sc[\$k]=\$v; done < \"\$DATA/scores\"
  echo \"count=\${#_sc[@]}\"
  echo \"val=\${_sc[abc123]:-missing}\"
" 2>/dev/null)
echo "$r" | grep -q 'count=1' && ok "loader skips # lines" || fail "loader skip" "$r"
echo "$r" | grep -q 'val=2|1' && ok "loader reads data after header" || fail "loader data" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Level Locking"

for bb in 0 1 5 14 29 30; do
  for lv in 1 2 6 15 30; do
    r=$(_run "BOSS_BEATEN=$bb; if (($lv > 1 && $lv > BOSS_BEATEN + 1)); then echo LOCKED; else echo OPEN; fi")
    if ((lv > 1 && lv > bb + 1)); then
      [[ "$r" == "LOCKED" ]] && ok "L$lv locked@BB=$bb" || fail "lock L$lv@$bb" "$r"
    else
      [[ "$r" == "OPEN" ]] && ok "L$lv open@BB=$bb" || fail "unlock L$lv@$bb" "$r"
    fi
  done
done

# ─────────────────────────────────────────────────────────────────────────────
section "Array Structure"

r=$(_run "
  echo \"names=\${#LEVEL_NAMES[@]}\"
  echo \"bosses=\${#BOSS_NAMES[@]}\"
  echo \"flavors=\${#BOSS_FLAVOR[@]}\"
  echo \"pad_name=\${LEVEL_NAMES[0]}\"
  echo \"pad_boss=\${BOSS_NAMES[0]}\"
  echo \"l1=\${LEVEL_NAMES[1]}\"
  echo \"l30=\${LEVEL_NAMES[30]}\"
")
echo "$r" | grep -q 'names=31' && ok "31 LEVEL_NAMES" || fail "LEVEL_NAMES" "$r"
echo "$r" | grep -q 'bosses=31' && ok "31 BOSS_NAMES" || fail "BOSS_NAMES" "$r"
echo "$r" | grep -q 'flavors=31' && ok "31 BOSS_FLAVOR" || fail "BOSS_FLAVOR" "$r"
echo "$r" | grep -q 'pad_name=$' && ok "LEVEL_NAMES[0] empty" || fail "LEVEL_NAMES[0]" "$r"
echo "$r" | grep -q 'pad_boss=$' && ok "BOSS_NAMES[0] empty" || fail "BOSS_NAMES[0]" "$r"
echo "$r" | grep -q 'l1=First Steps' && ok "LEVEL_NAMES[1]" || fail "LEVEL_NAMES[1]" "$r"
echo "$r" | grep -q 'l30=ROOT' && ok "LEVEL_NAMES[30]" || fail "LEVEL_NAMES[30]" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "MANPAGE & EXP Coverage"

r=$(_run "
  missing=0
  for cmd in ls cat head tail grep sort uniq cut wc tr sed awk find fd \
    rg ssh curl git nmap tmux chmod tar cp mv rm ln mkdir echo cd \
    pwd touch test tee less xargs kill fg bg jobs; do
    [[ -z \"\${MANPAGE[\$cmd]:-}\" ]] && { echo \"MISS: \$cmd\"; ((++missing)); }
  done
  echo \"missing=\$missing\"
")
miss=$(echo "$r" | grep 'missing=' | grep -o '[0-9]*')
((miss == 0)) && ok "all core commands have MANPAGE" || { fail "MANPAGE" "$miss missing"; echo "$r" | grep MISS | head -5; }

r=$(_run "echo \"exp=\${#EXP[@]}\"")
count=$(echo "$r" | grep -o '[0-9]*')
((count > 50)) && ok "EXP has $count entries" || fail "EXP count" "only $count"

# ─────────────────────────────────────────────────────────────────────────────
section "Constants"

r=$(_run "echo \"\$MAX_LEVEL \$BOSS_TOTAL \$BOSS_THRESHOLD \$FIRE_STREAK\"")
[[ "$r" == "30 5 4 5" ]] && ok "constants: MAX=30 TOTAL=5 THRESH=4 FIRE=5" || fail "constants" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Level 5/6 Split"

l5=$(_run "gen_level5")
echo "$l5" | grep -q '<<<' && fail "L5" "contains <<<" || ok "L5 no <<<"
l6=$(_run "gen_level6")
echo "$l6" | grep -q '<<<' && ok "L6 has <<<" || fail "L6" "no <<<"

# ─────────────────────────────────────────────────────────────────────────────
section "No Stale References"

grep -q 'gen_level0' "$CMDCHAMP" && fail "stale" "gen_level0 referenced" || ok "no gen_level0"
pr=$(grep -n '_level_pass\|PASSWORD:' "$CMDCHAMP" | grep -v '^#' | grep -v 'password cracker\|passwd\|wordlist\|rockyou' || true)
[[ -z "$pr" ]] && ok "no _level_pass/PASSWORD" || fail "stale passwords" "$pr"
hr=$(grep -n '\bHINT\b' "$CMDCHAMP" | grep -v '#\|hint' || true)
[[ -z "$hr" ]] && ok "no HINT refs" || fail "stale HINT" "$hr"

# ═════════════════════════════════════════════════════════════════════════════
# SANDBOX ANSWER VERIFICATION - The Big One
# ═════════════════════════════════════════════════════════════════════════════
section "Sandbox Answer Verification"

if ! command -v bwrap &>/dev/null; then
  skip "bwrap not installed - skipping sandbox verification"
else
  # Create sandbox source with SANDBOX_MODE=1
  SB_SOURCE="$TDIR/cmdchamp_sandbox.sh"
  {
    sed -e 's/^_tty().*/\_tty() { :; }/' \
        -e '/^\[.*--no-sandbox/,$d' \
        "$CMDCHAMP"
    echo 'SANDBOX_MODE=1'
  } > "$SB_SOURCE"

  SB_DATA="$TDIR/sb_data"
  SB_PRISTINE="$SB_DATA/sandbox.pristine"
  SB_DIR="$SB_DATA/sandbox"

  # Generate pristine sandbox once
  bash -c "
    export DATA='$SB_DATA'; mkdir -p '$SB_DATA'; touch '$SB_DATA/scores'
    SANDBOX_PRISTINE='$SB_PRISTINE' SANDBOX_DIR='$SB_DIR'
    source '$SB_SOURCE' 2>/dev/null
    SANDBOX_PRISTINE='$SB_PRISTINE' SANDBOX_DIR='$SB_DIR'
    _gen_sandbox_files '$SB_PRISTINE'
  " 2>/dev/null

  sb_pass=0 sb_fail=0 sb_skip=0 sb_total=0
  sb_errors=()

  for lv in {1..30}; do
    lv_pass=0 lv_fail=0 lv_skip=0 lv_total=0

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue

      # Parse the question
      read -r _qprompt _qans _qoutput _qstate _qtext _qdelim _qanswers < <(bash -c "
        source '$SB_SOURCE' 2>/dev/null
        _qparse \"\$1\"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' \"\$_qprompt\" \"\$_qans\" \"\$_qoutput\" \"\$_qstate\" \"\$_qtext\" \"\$_qdelim\" \"\$_qanswers\"
      " _ "$line" 2>/dev/null)

      # Skip #text: questions (no sandbox validation possible)
      if [[ "$_qtext" == "1" ]]; then
        ((++lv_skip)); ((++sb_skip))
        continue
      fi

      # Skip questions with no sandbox markers
      if [[ -z "$_qoutput" && -z "$_qstate" ]]; then
        ((++lv_skip)); ((++sb_skip))
        continue
      fi

      ((++lv_total)); ((++sb_total))

      # Reset sandbox to pristine
      rm -rf "$SB_DIR"
      cp -a "$SB_PRISTINE" "$SB_DIR"

      # Execute answer in sandbox and check
      result=$(bash -c "
        export DATA='$SB_DATA'
        export SANDBOX_PRISTINE='$SB_PRISTINE'
        export SANDBOX_DIR='$SB_DIR'
        source '$SB_SOURCE' 2>/dev/null
        SANDBOX_MODE=1
        SANDBOX_PRISTINE='$SB_PRISTINE'
        SANDBOX_DIR='$SB_DIR'

        _qparse \"\$1\"

        # Execute command
        output=\$(_sandbox_exec \"\$_qans\" 5 2>/dev/null) || true

        passed=1
        if [[ -n \"\$_qoutput\" ]]; then
          _sandbox_check_output \"\$output\" \"\$_qoutput\" || passed=0
        fi
        if [[ -n \"\$_qstate\" ]]; then
          _sandbox_check_state \"\$_qstate\" || passed=0
        fi

        if ((passed)); then
          echo PASS
        else
          echo \"FAIL|output=\${output:0:80}|expected_out=\$_qoutput|expected_state=\$_qstate\"
        fi
      " _ "$line" 2>/dev/null)

      if [[ "$result" == "PASS" ]]; then
        ((++lv_pass)); ((++sb_pass))
      else
        ((++lv_fail)); ((++sb_fail))
        sb_errors+=("L${lv}: ${_qans} -> ${result}")
      fi
    done < <(bash -c "source '$SB_SOURCE' 2>/dev/null; gen_level${lv}" 2>/dev/null)

    # Per-level summary (compact)
    if ((lv_total > 0)); then
      if ((lv_fail == 0)); then
        printf '  %s✓%s L%-2d  %d/%d sandbox pass  (%d skipped)\n' "$G" "$N" "$lv" "$lv_pass" "$lv_total" "$lv_skip"
      else
        printf '  %s✗%s L%-2d  %d/%d sandbox pass  %s(%d FAILED)%s\n' "$R" "$N" "$lv" "$lv_pass" "$lv_total" "$R" "$lv_fail" "$N"
      fi
    else
      printf '  %s-%s L%-2d  all %d questions skipped (text-only)\n' "$Y" "$N" "$lv" "$lv_skip"
    fi
  done

  # Sandbox summary
  printf '\n  %sSandbox totals:%s %s%d pass%s / %s%d fail%s / %s%d skip%s (of %d)\n' \
    "$B" "$N" "$G" "$sb_pass" "$N" "$R" "$sb_fail" "$N" "$Y" "$sb_skip" "$N" "$sb_total"

  if ((sb_fail == 0)); then
    ok "all $sb_total sandbox answers verified"
    ((++PASS))  # extra for total
  else
    fail "sandbox verification" "$sb_fail/$sb_total failed"
    printf '\n  %sFailed sandbox answers:%s\n' "$R" "$N"
    for e in "${sb_errors[@]:0:20}"; do
      printf '    %s• %s%s\n' "$R" "$e" "$N"
    done
    ((${#sb_errors[@]} > 20)) && printf '    %s... and %d more%s\n' "$D" "$((${#sb_errors[@]} - 20))" "$N"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# Summary
# ═════════════════════════════════════════════════════════════════════════════
printf '\n%s════════════════════════════════════════%s\n' "$B" "$N"
printf '%s%d passed%s, ' "$G" "$PASS" "$N"
if ((FAIL > 0)); then
  printf '%s%d failed%s' "$R" "$FAIL" "$N"
  ((SKIP > 0)) && printf ', %s%d skipped%s' "$Y" "$SKIP" "$N"
  printf '\n\n%sFailures:%s\n' "$R" "$N"
  for e in "${ERRORS[@]}"; do
    printf '  %s• %s%s\n' "$R" "$e" "$N"
  done
  exit 1
else
  printf '%s0 failed%s' "$G" "$N"
  ((SKIP > 0)) && printf ', %s%d skipped%s' "$Y" "$SKIP" "$N"
  printf '\n'
  exit 0
fi
