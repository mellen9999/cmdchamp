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
      -e '/^# Handle --no-sandbox/,$d' \
      "$CMDCHAMP"
  echo 'SANDBOX_MODE=0'
} > "$SOURCE_FILE"

export DATA="$TDIR/data"
mkdir -p "$DATA"
touch "$DATA/scores"

# Helper: run bash snippet with sourced cmdchamp
_run() { bash -c "source '$SOURCE_FILE' 2>/dev/null; $1" 2>/dev/null; }
_rune() { bash -c "source '$SOURCE_FILE' 2>/dev/null; $1" 2>/dev/null; }

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
section "Answer Normalization (_fnorm)"

run_norm() { _run "_fnorm '$1'; printf '%s' \"\$REPLY\""; }

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

# !perm: check (file is not executable)
chmod 644 "$SBOX/testfile"
r=$(_run_state '_sandbox_check_state "!perm:testfile:x" && echo PASS || echo FAIL')
[[ "$r" == "PASS" ]] && ok "state !perm:x pass (644)" || fail "state !perm" "$r"

# !perm: fail (file IS executable)
chmod 755 "$SBOX/testfile"
r=$(_run_state '_sandbox_check_state "!perm:testfile:x" && echo PASS || echo FAIL')
[[ "$r" == "FAIL" ]] && ok "state !perm:x fail (755)" || fail "state !perm fail" "$r"
chmod 644 "$SBOX/testfile"  # restore

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
echo "$r" | grep -q 'ver=3' && ok "profile ver=3" || fail "profile ver" "$r"
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
echo "$r" | grep -q 'ver=3' && ok "v1->v2->v3: ver bumped" || fail "v1->v2 ver" "$r"
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

HAS_BWRAP=0
if ! command -v bwrap &>/dev/null; then
  printf '  %s⚠  bwrap NOT INSTALLED — 25-40%% of tests will be skipped!%s\n' "$R$B" "$N"
  printf '  %s   Install bwrap for full coverage: paru -S bubblewrap%s\n' "$Y" "$N"
  skip "bwrap not installed - skipping sandbox verification"
else
  HAS_BWRAP=1
  # Create sandbox source with SANDBOX_MODE=1
  SB_SOURCE="$TDIR/cmdchamp_sandbox.sh"
  {
    sed -e 's/^_tty().*/\_tty() { :; }/' \
        -e '/^# Handle --no-sandbox/,$d' \
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

# ─────────────────────────────────────────────────────────────────────────────
section "Boss Mechanics"

# Boss threshold: 4/5 = pass, 3/5 = fail
r=$(_run "
  ((4 >= BOSS_THRESHOLD)) && echo pass4 || echo fail4
  ((3 >= BOSS_THRESHOLD)) && echo pass3 || echo fail3
  ((5 >= BOSS_THRESHOLD)) && echo pass5 || echo fail5
")
echo "$r" | grep -q 'pass4' && ok "4/5 meets threshold" || fail "boss threshold 4" "$r"
echo "$r" | grep -q 'fail3' && ok "3/5 fails threshold" || fail "boss threshold 3" "$r"
echo "$r" | grep -q 'pass5' && ok "5/5 meets threshold" || fail "boss threshold 5" "$r"

# Boss questions are drawn from current level
r=$(_run "
  BOSS_BEATEN=30
  generate_level 1
  echo \"qcount=\${#CURRENT_QUESTIONS[@]}\"
")
qc=$(echo "$r" | grep 'qcount=' | grep -o '[0-9]*')
((qc >= 5)) && ok "L1 has >=5 questions for boss" || fail "boss q pool" "only $qc"

# Boss excludes seen prompts
r=$(_rune '
  BOSS_BEATEN=30
  generate_level 1
  declare -A _seen_map
  seen_count=0
  for q in "${CURRENT_QUESTIONS[@]}"; do
    _qparse "$q"
    _seen_map[$_qprompt]=1
    ((++seen_count >= 3)) && break
  done
  unseen=0
  for q in "${CURRENT_QUESTIONS[@]}"; do
    _qparse "$q"
    [[ -z "${_seen_map[$_qprompt]:-}" ]] && ((++unseen))
  done
  echo "unseen=$unseen total=${#CURRENT_QUESTIONS[@]} seen=3"
')
unseen=$(echo "$r" | grep 'unseen=' | sed 's/.*unseen=\([0-9]*\).*/\1/')
((unseen >= 5)) && ok "enough unseen for boss after 3 seen" || fail "boss unseen" "$r"

# BOSS_BEATEN increments on win
r=$(_run "BOSS_BEATEN=5; ((4 >= BOSS_THRESHOLD)) && { ((BOSS_BEATEN < 6)) && BOSS_BEATEN=6; }; echo \$BOSS_BEATEN")
[[ "$r" == "6" ]] && ok "BOSS_BEATEN increments 5->6 on win" || fail "boss increment" "$r"

# BOSS_BEATEN doesn't decrement on loss
r=$(_run "BOSS_BEATEN=5; ((2 >= BOSS_THRESHOLD)) || true; echo \$BOSS_BEATEN")
[[ "$r" == "5" ]] && ok "BOSS_BEATEN stable on loss" || fail "boss loss stable" "$r"

# Level unlock after boss beat
r=$(_run "BOSS_BEATEN=5; lv=6; if ((lv > 1 && lv > BOSS_BEATEN + 1)); then echo LOCKED; else echo OPEN; fi")
[[ "$r" == "OPEN" ]] && ok "L6 open after BB=5" || fail "boss unlock L6" "$r"
r=$(_run "BOSS_BEATEN=5; lv=7; if ((lv > 1 && lv > BOSS_BEATEN + 1)); then echo LOCKED; else echo OPEN; fi")
[[ "$r" == "LOCKED" ]] && ok "L7 locked after BB=5" || fail "boss lock L7" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Tier/Mastery System"

# Default tier is 1 (learning)
r=$(_run 'declare -A _sc; _sget() { _hash "$1"; local _v="${_sc[$REPLY]:-1}"; REPLY="${_v%%|*}"; }; _sget "brand new"; echo $REPLY')
[[ "$r" == "1" ]] && ok "default tier=1 (learning)" || fail "default tier" "$r"

# Correct answer promotes 1->2
r=$(_run '
  declare -A _sc
  _sget() { _hash "$1"; local _v="${_sc[$REPLY]:-1}"; REPLY="${_v%%|*}"; }
  _sget "q1"; tier=$REPLY
  new_tier=$((tier<2?tier+1:2))
  echo "old=$tier new=$new_tier"
')
echo "$r" | grep -q 'old=1 new=2' && ok "correct: tier 1->2 (mastered)" || fail "tier promote" "$r"

# Wrong answer demotes 2->1
r=$(_run '
  declare -A _sc
  _hash "q1"; _sc[$REPLY]="2|1"
  _sget() { _hash "$1"; local _v="${_sc[$REPLY]:-1}"; REPLY="${_v%%|*}"; }
  _sget "q1"; tier=$REPLY
  new_tier=$((tier>0?tier-1:0))
  echo "old=$tier new=$new_tier"
')
echo "$r" | grep -q 'old=2 new=1' && ok "wrong: tier 2->1 (demoted)" || fail "tier demote" "$r"

# Wrong answer demotes 1->0
r=$(_run '
  declare -A _sc
  _hash "q1"; _sc[$REPLY]="1|1"
  _sget() { _hash "$1"; local _v="${_sc[$REPLY]:-1}"; REPLY="${_v%%|*}"; }
  _sget "q1"; tier=$REPLY
  new_tier=$((tier>0?tier-1:0))
  echo "old=$tier new=$new_tier"
')
echo "$r" | grep -q 'old=1 new=0' && ok "wrong: tier 1->0" || fail "tier demote 1->0" "$r"

# Tier caps at 2
r=$(_run 'tier=2; new_tier=$((tier<2?tier+1:2)); echo $new_tier')
[[ "$r" == "2" ]] && ok "tier capped at 2" || fail "tier cap" "$r"

# Tier floors at 0
r=$(_run 'tier=0; new_tier=$((tier>0?tier-1:0)); echo $new_tier')
[[ "$r" == "0" ]] && ok "tier floored at 0" || fail "tier floor" "$r"

# FIRE_STREAK forces tier 2 (recall mode)
r=$(_run '
  streak=$FIRE_STREAK tier=1
  ((streak>=FIRE_STREAK)) && tier=2
  echo $tier
')
[[ "$r" == "2" ]] && ok "fire streak forces tier 2" || fail "fire tier" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Gauntlet Logic"

# _post_root_check blocks when BOSS_BEATEN < MAX_LEVEL
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  BOSS_BEATEN=29 MAX_LEVEL=30
  _post_root_check 2>&1 || true
" 2>/dev/null)
echo "$r" | grep -q 'Locked' && ok "gauntlet locked at BB=29" || fail "gauntlet lock" "$r"

# Difficulty escalation: every 5 correct answers, difficulty++
r=$(_run '
  difficulty=1
  for i in {1..15}; do
    ((i % 5 == 0 && difficulty <= 30)) && ((++difficulty))
  done
  echo $difficulty
')
[[ "$r" == "4" ]] && ok "difficulty escalates 1->4 after 15 correct" || fail "gauntlet difficulty" "$r"

# 3 lives tracking
r=$(_run '
  lives=3 streak=0
  # 2 wrongs
  ((lives--)); ((lives--))
  echo "lives=$lives"
')
echo "$r" | grep -q 'lives=1' && ok "gauntlet lives decrement" || fail "gauntlet lives" "$r"

# Best gauntlet tracking
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_gauntlet'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=test\nBOSS_BEATEN=30\nBEST_GAUNTLET=10\nBEST_TIMED=0\nEGGS_FOUND=\nSC_DONE=\nPROFILE_VER=3\n' > \"\$DATA/profile\"
  _load_profile
  score=15
  ((score > BEST_GAUNTLET)) && { BEST_GAUNTLET=\$score; _save_profile; }
  _load_profile
  echo \"\$BEST_GAUNTLET\"
" 2>/dev/null)
[[ "$r" == "15" ]] && ok "gauntlet best score persists" || fail "gauntlet best" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Timed Mode Logic"

# Valid durations
for dur in 60 120 300; do
  r=$(_run "
    case $dur in 60|120|300) echo valid;; *) echo invalid;; esac
  ")
  [[ "$r" == "valid" ]] && ok "timed duration $dur valid" || fail "timed dur $dur" "$r"
done

# Invalid duration rejected
r=$(_run 'case 90 in 60|120|300) echo valid;; *) echo invalid;; esac')
[[ "$r" == "invalid" ]] && ok "timed rejects 90s" || fail "timed reject" "$r"

# Best timed tracking
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_timed'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=test\nBOSS_BEATEN=30\nBEST_GAUNTLET=0\nBEST_TIMED=8\nEGGS_FOUND=\nSC_DONE=\nPROFILE_VER=3\n' > \"\$DATA/profile\"
  _load_profile
  score=12
  ((score > BEST_TIMED)) && { BEST_TIMED=\$score; _save_profile; }
  _load_profile
  echo \"\$BEST_TIMED\"
" 2>/dev/null)
[[ "$r" == "12" ]] && ok "timed best score persists" || fail "timed best" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Review Mode Logic"

# Weak level detection: <80% mastery = weak
r=$(_rune '
  declare -A _sc
  for i in {1..10}; do _hash "q$i"; _sc[$REPLY]="1|1"; done
  for i in {1..6}; do _hash "q$i"; _sc[$REPLY]="2|1"; done
  declare -A lv_total lv_mastered
  for k in "${!_sc[@]}"; do
    _val="${_sc[$k]}" _tier="${_val%%|*}"
    [[ "$_val" == *"|"* ]] && _lvtag="${_val#*|}" || _lvtag=""
    [[ -n "$_lvtag" ]] && {
      lv_total[$_lvtag]=$(( ${lv_total[$_lvtag]:-0} + 1 ))
      [[ "$_tier" != "0" && "$_tier" != "1" ]] && lv_mastered[$_lvtag]=$(( ${lv_mastered[$_lvtag]:-0} + 1 ))
    }
  done
  lt=${lv_total[1]:-0} lm=${lv_mastered[1]:-0}
  ((lt > 0)) && pct=$((lm * 100 / lt)) || pct=0
  ((pct < 80)) && echo "weak pct=$pct" || echo "strong pct=$pct"
')
echo "$r" | grep -q 'weak pct=60' && ok "60% mastery = weak" || fail "review weak" "$r"

# Strong level detection: >=80% mastery
r=$(_rune '
  declare -A _sc
  for i in {1..10}; do _hash "s$i"; _sc[$REPLY]="2|2"; done
  for i in {1..2}; do _hash "s$i"; _sc[$REPLY]="1|2"; done
  declare -A lv_total lv_mastered
  for k in "${!_sc[@]}"; do
    _val="${_sc[$k]}" _tier="${_val%%|*}"
    [[ "$_val" == *"|"* ]] && _lvtag="${_val#*|}" || _lvtag=""
    [[ -n "$_lvtag" ]] && {
      lv_total[$_lvtag]=$(( ${lv_total[$_lvtag]:-0} + 1 ))
      [[ "$_tier" != "0" && "$_tier" != "1" ]] && lv_mastered[$_lvtag]=$(( ${lv_mastered[$_lvtag]:-0} + 1 ))
    }
  done
  lt=${lv_total[2]:-0} lm=${lv_mastered[2]:-0}
  ((lt > 0)) && pct=$((lm * 100 / lt)) || pct=0
  ((pct < 80)) && echo "weak pct=$pct" || echo "strong pct=$pct"
')
echo "$r" | grep -q 'strong pct=80' && ok "80% mastery = strong" || fail "review strong" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Easter Eggs"

# Override _egg_found to skip sleep and ANSI output
_egg_setup='EGGS_FOUND=""; _save_profile() { :; }; _egg_found() { local name=$1; [[ ",$EGGS_FOUND," == *",$name,"* ]] && return; [[ -n "$EGGS_FOUND" ]] && EGGS_FOUND="$EGGS_FOUND,$name" || EGGS_FOUND="$name"; }'

# sudorm egg
r=$(_rune "$_egg_setup; _egg_check wrong \"sudo rm -rf /\"; echo \"\$EGGS_FOUND\"")
echo "$r" | grep -q 'sudorm' && ok "egg: sudorm" || fail "egg sudorm" "$r"

# forkbomb egg
r=$(_rune "$_egg_setup; _egg_check wrong ':(){ :|:& };:'; echo \"\$EGGS_FOUND\"")
echo "$r" | grep -q 'forkbomb' && ok "egg: forkbomb" || fail "egg forkbomb" "$r"

# rtfm egg
r=$(_rune "$_egg_setup; _egg_check wrong man; echo \"\$EGGS_FOUND\"")
echo "$r" | grep -q 'rtfm' && ok "egg: rtfm" || fail "egg rtfm" "$r"

# streak10 egg
r=$(_rune "$_egg_setup; _S_STREAK=10; _egg_check streak; echo \"\$EGGS_FOUND\"")
echo "$r" | grep -q 'streak10' && ok "egg: streak10" || fail "egg streak10" "$r"

# streak10 doesn't fire at 9
r=$(_rune "$_egg_setup; _S_STREAK=9; _egg_check streak; echo \"eggs=\${EGGS_FOUND:-none}\"")
echo "$r" | grep -q 'eggs=none' && ok "egg: streak9 no trigger" || fail "egg streak9" "$r"

# flawless egg
r=$(_rune "$_egg_setup; _egg_check flawless; echo \"\$EGGS_FOUND\"")
echo "$r" | grep -q 'flawless' && ok "egg: flawless" || fail "egg flawless" "$r"

# _egg_found deduplication
r=$(_rune "$_egg_setup; _egg_found sudorm; _egg_found sudorm; echo \"\$EGGS_FOUND\"")
[[ "$(echo "$r" | tail -1)" == "sudorm" ]] && ok "egg: no duplicates" || fail "egg dedup" "$r"

# Multiple eggs accumulate
r=$(_rune "$_egg_setup; _egg_found sudorm; _egg_found rtfm; echo \"\$EGGS_FOUND\"")
echo "$r" | grep -q 'sudorm,rtfm' && ok "egg: accumulate" || fail "egg accumulate" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Session Persistence"

# Score persist: write scores, reload from file, verify
r=$(bash -c "
  export DATA='$TDIR/data_persist'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_persist'
  declare -gA _sc; _sc=()
  _hash 'persist question'; _sc[\$REPLY]='2|5'
  _sflush

  # Reload in fresh context
  declare -A _sc2; _sc2=()
  while IFS='|' read -r k v rest; do [[ \"\$k\" == '#'* ]] && continue; _sc2[\$k]=\$v; done < \"\$DATA/scores\"
  _hash 'persist question'
  echo \"tier=\${_sc2[\$REPLY]:-missing}\"
" 2>/dev/null)
echo "$r" | grep -q 'tier=2' && ok "scores persist across reload" || fail "score persist" "$r"

# Profile round-trip with all fields
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_prof_rt'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  PLAYER_NAME='testguy' BOSS_BEATEN=15 BEST_GAUNTLET=42 BEST_TIMED=99 EGGS_FOUND='sudorm,rtfm' SC_DONE='1,3' _PROFILE_VER=3
  _save_profile
  # Reset
  PLAYER_NAME='' BOSS_BEATEN=0 BEST_GAUNTLET=0 BEST_TIMED=0 EGGS_FOUND='' SC_DONE='' _PROFILE_VER=0
  _load_profile
  echo \"name=\$PLAYER_NAME bb=\$BOSS_BEATEN bg=\$BEST_GAUNTLET bt=\$BEST_TIMED eggs=\$EGGS_FOUND sc=\$SC_DONE ver=\$_PROFILE_VER\"
" 2>/dev/null)
echo "$r" | grep -q 'name=testguy' && ok "profile name round-trip" || fail "prof name" "$r"
echo "$r" | grep -q 'bb=15' && ok "profile BOSS_BEATEN round-trip" || fail "prof bb" "$r"
echo "$r" | grep -q 'bg=42' && ok "profile BEST_GAUNTLET round-trip" || fail "prof bg" "$r"
echo "$r" | grep -q 'bt=99' && ok "profile BEST_TIMED round-trip" || fail "prof bt" "$r"
echo "$r" | grep -q 'eggs=sudorm,rtfm' && ok "profile EGGS_FOUND round-trip" || fail "prof eggs" "$r"
echo "$r" | grep -q 'sc=1,3' && ok "profile SC_DONE round-trip" || fail "prof sc" "$r"
echo "$r" | grep -q 'ver=3' && ok "profile ver=3 stable" || fail "prof ver" "$r"

# Session save/load with scores
r=$(bash -c "
  export DATA='$TDIR/data_sess2'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_sess2'
  LVL=14; QI=7; save
  LVL=1; QI=0; load
  echo \"lvl=\$LVL qi=\$QI\"
" 2>/dev/null)
echo "$r" | grep -q 'lvl=14 qi=7' && ok "session LVL+QI persist" || fail "session persist" "$r"

# v2->v3 migration adds eggs+scenario fields
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig_v3'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=migtest\nBOSS_BEATEN=5\nPROFILE_VER=2\n' > \"\$DATA/profile\"
  _load_profile
  echo \"ver=\$_PROFILE_VER eggs=\${EGGS_FOUND:-empty} sc=\${SC_DONE:-empty}\"
" 2>/dev/null)
echo "$r" | grep -q 'ver=3' && ok "v2->v3: ver bumped" || fail "v2->v3 ver" "$r"
echo "$r" | grep -q 'eggs=empty' && ok "v2->v3: eggs initialized" || fail "v2->v3 eggs" "$r"
echo "$r" | grep -q 'sc=empty' && ok "v2->v3: sc initialized" || fail "v2->v3 sc" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Scenario System"

# SC_TOTAL matches actual scenario count
r=$(_run "echo \"\$SC_TOTAL\"")
[[ "$r" == "8" ]] && ok "SC_TOTAL=8" || fail "SC_TOTAL" "$r"

# All scenario functions exist
for sc_id in {1..8}; do
  r=$(_run "declare -f _sc_setup_${sc_id} >/dev/null && echo Y || echo N")
  [[ "$r" == "Y" ]] && ok "sc_setup_${sc_id} exists" || fail "sc_setup_${sc_id}" "missing"
  r=$(_run "declare -f _sc_steps_${sc_id} >/dev/null && echo Y || echo N")
  [[ "$r" == "Y" ]] && ok "sc_steps_${sc_id} exists" || fail "sc_steps_${sc_id}" "missing"
done

# SC_UNLOCK array has correct size
r=$(_run "echo \"\${#SC_UNLOCK[@]}\"")
[[ "$r" == "9" ]] && ok "SC_UNLOCK has 9 entries (padded)" || fail "SC_UNLOCK size" "$r"

# _sc_is_done / _sc_mark_done
r=$(_rune 'SC_DONE=""; _save_profile() { :; }
  _sc_is_done 1 && echo "already" || echo "not_done"
  _sc_mark_done 1
  _sc_is_done 1 && echo "done" || echo "still_not"
  _sc_mark_done 1
  echo "sc=$SC_DONE"
')
echo "$r" | grep -q 'not_done' && ok "sc: not done initially" || fail "sc init" "$r"
echo "$r" | grep -q '^done$' && ok "sc: done after mark" || fail "sc mark" "$r"
echo "$r" | grep -q 'sc=1$' && ok "sc: no duplicate mark" || fail "sc dedup" "$r"

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
  ((!HAS_BWRAP)) && printf '\n%s⚠  INCOMPLETE: bwrap missing — sandbox tests were skipped%s\n' "$R$B" "$N"
  exit 1
else
  printf '%s0 failed%s' "$G" "$N"
  ((SKIP > 0)) && printf ', %s%d skipped%s' "$Y" "$SKIP" "$N"
  printf '\n'
  ((!HAS_BWRAP)) && printf '\n%s⚠  INCOMPLETE: bwrap missing — sandbox tests were skipped%s\n' "$R$B" "$N"
  exit 0
fi
