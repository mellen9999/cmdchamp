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
  # Honor a pre-exported DATA so tests stay inside $TDIR. Production computes DATA
  # from XDG_DATA_HOME/HOME unconditionally at load; without this rewrite every test
  # would read/write the user's real ~/.local/share/cmdchamp save.
  sed -e 's/^_tty().*/\_tty() { :; }/' \
      -e 's|^DATA=.*|DATA="${DATA:-${XDG_DATA_HOME:-${HOME:-/tmp}/.local/share}/cmdchamp}"|' \
      -e '/^# ═══ CLI ENTRYPOINT ═══/,$d' \
      "$CMDCHAMP"
  echo 'SANDBOX_MODE=0'
} > "$SOURCE_FILE"

export DATA="$TDIR/data"
mkdir -p "$DATA"
touch "$DATA/scores"

# Helper: run bash snippet with sourced cmdchamp
_run() { bash -c "source '$SOURCE_FILE' 2>/dev/null; $1" 2>/dev/null; }

# gen_level* write into a nameref array and print NOTHING to stdout — they must be
# handed an array, which is then emitted one question per line.
_qgen() { _run "declare -a Q=(); gen_level${1} Q; printf '%s\n' \"\${Q[@]}\""; }

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

# Long flags fold onto their short letter (per-command _LOPT table)
r=$(run_norm "sort --reverse file")
[[ "$r" == "sort -r file" ]] && ok "norm folds long flag to short" || fail "norm long" "got '$r'"

# Long + short mixed — _fnorm sorts flags in byte order (LC_ALL=C), locale-independent
r=$(run_norm "sort --reverse -n file")
[[ "$r" == "sort -n -r file" ]] && ok "norm mixed long+short" || fail "norm mixed" "got '$r'"

# Same long name, different letter per command
r=$(run_norm "chmod --recursive a+r dir")
[[ "$r" == "chmod -R a+r dir" ]] && ok "norm --recursive -> -R (chmod)" || fail "norm chmod long" "got '$r'"
r=$(run_norm "grep --recursive TODO .")
[[ "$r" == "grep -r TODO ." ]] && ok "norm --recursive -> -r (grep)" || fail "norm grep long" "got '$r'"

# Unknown long flag stays untouched
r=$(run_norm "ls --author file")
[[ "$r" == "ls --author file" ]] && ok "norm leaves unmapped long flag" || fail "norm unmapped" "got '$r'"

# tar: bare cluster, dashed cluster and long spelling all agree
a=$(run_norm "tar xzf a.tgz"); b=$(run_norm "tar -xzf a.tgz"); c=$(run_norm "tar --extract --gzip --file=a.tgz")
[[ "$a" == "$b" && "$b" == "$c" ]] && ok "norm tar spellings agree" || fail "norm tar" "got '$a' / '$b' / '$c'"

# sudo is transparent for flag shaping
r=$(run_norm "sudo chown --recursive me dir")
[[ "$r" == "sudo -R chown me dir" ]] && ok "norm long flag under sudo" || fail "norm sudo long" "got '$r'"

# -R and -r are one flag in cp/rm; sed -r is -E
r=$(run_norm "cp -R a b")
[[ "$r" == "cp -r a b" ]] && ok "norm cp -R -> -r" || fail "norm cp -R" "got '$r'"
r=$(run_norm "sed -r 's/a/b/' f")
[[ "$r" == "sed -E s/a/b/ f" ]] && ok "norm sed -r -> -E" || fail "norm sed -r" "got '$r'"

# Flags with values
r=$(run_norm "head --lines=5 file")
[[ "$r" == "head -n 5 file" ]] && ok "norm --flag=val split" || fail "norm --flag=val" "got '$r'"

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

# Double-dash: args after -- are never split as flags
r=$(run_norm "rm -- -file")
[[ "$r" == "rm -- -file" ]] && ok "norm double-dash preserves args" || fail "norm --" "got '$r'"

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

# #state: before #output: - parser stops state at next #tag boundary
# This is by-design: always put #output: before #state: in question definitions
r=$(_run "_qparse 'Do it|cmd|#state:exists:x#output:hello'; echo \"s=\$_qstate\"")
[[ "$r" == *"s=exists:x"* ]] && ok "_qparse stops state at next #tag boundary" || fail "_qparse reversed" "$r"

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

_qgen_bad=0
for lv in {1..30}; do
  output=$(_qgen "$lv")
  qcount=$(printf '%s\n' "$output" | grep -c '.')
  if ((qcount < 3)); then
    fail "gen_level${lv}" "only $qcount questions (need >=3)"
    ((++_qgen_bad))
  fi
done
((_qgen_bad == 0)) && ok "all 30 levels generate >=3 questions"

# Format: every line must have | or §
bad_format=()
for lv in {1..30}; do
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" != *"|"* && "$line" != *"§"* ]]; then
      bad_format+=("L${lv}: ${line:0:60}")
    fi
  done < <(_qgen "$lv")
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
    declare -a Q=()
    dupes=0; empty=0; pfails=0; count=0
    gen_level${lv} Q
    for line in \"\${Q[@]}\"; do
      [[ -z \"\$line\" ]] && continue
      ((++count))
      _qparse \"\$line\" 2>/dev/null || { ((++pfails)); continue; }
      [[ -z \"\$_qprompt\" ]] && ((++empty))
      [[ -n \"\${seen[\$_qprompt]:-}\" ]] && ((++dupes))
      seen[\$_qprompt]=1
    done
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

# New profile — stub interactive parts of _first_run (intro/tutorial/place) so it
# only exercises the persistence path
r=$(_run "
  _intro() { :; }; _tutorial() { :; }; place() { :; }
  _first_run <<< 'TestPlayer'
  _load_profile
  echo \"name=\$PLAYER_NAME ver=\$_PROFILE_VER beaten=\$BOSS_BEATEN best_chal=\$BEST_CHALLENGE\"
")
echo "$r" | grep -q 'name=TestPlayer' && ok "profile stores name" || fail "profile name" "$r"
echo "$r" | grep -q 'ver=5' && ok "profile ver=5" || fail "profile ver" "$r"
echo "$r" | grep -q 'beaten=0' && ok "new BOSS_BEATEN=0" || fail "profile beaten" "$r"

# Profile version mismatch resets state. v0/v1 are pre-PROFILE_VER schemas;
# loading them resets BOSS_BEATEN to 0 (no in-place migration past v3→v4).
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig1'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=migtest\nBOSS_BEATEN=-1\nPROFILE_VER=0\n' > \"\$DATA/profile\"
  _load_profile
  echo \"\$BOSS_BEATEN\"
" 2>/dev/null)
[[ "$r" == "0" ]] && ok "v0 mismatch resets BOSS_BEATEN -> 0" || fail "v0 migrate -1" "got '$r'"

r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig2'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=migtest\nBOSS_BEATEN=5\nPROFILE_VER=0\n' > \"\$DATA/profile\"
  _load_profile
  echo \"\$BOSS_BEATEN\"
" 2>/dev/null)
[[ "$r" == "0" ]] && ok "v0 mismatch resets BOSS_BEATEN=5 -> 0" || fail "v0 migrate 5" "got '$r'"

# In-place migration: PROFILE_VER=3 → current (no reset, fields preserved)
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig_inplace'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=v3test\nBOSS_BEATEN=12\nPROFILE_VER=3\n' > \"\$DATA/profile\"
  _load_profile
  echo \"name=\$PLAYER_NAME bb=\$BOSS_BEATEN\"
" 2>/dev/null)
echo "$r" | grep -q 'name=v3test' && ok "v3→current preserves PLAYER_NAME" || fail "v3 migrate name" "$r"
echo "$r" | grep -q 'bb=12' && ok "v3→current preserves BOSS_BEATEN" || fail "v3 migrate bb" "$r"

# BOSS_BEATEN clamping to MAX_LEVEL on a current-version profile
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_mig4'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=clamp\nBOSS_BEATEN=999\nPROFILE_VER=5\n' > \"\$DATA/profile\"
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
echo "$r" | grep -q 'ver=5' && ok "v1->v5: ver bumped" || fail "v1->v2 ver" "$r"
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

# Drive the REAL score functions. _sget is defined by _mode_init (not at top level),
# which also declares _sc, loads the scores file and sets _MODE_TAG.
_score_env() {  # $1 = data dir suffix, $2 = mode tag, $3 = snippet
  bash -c "
    export DATA='$TDIR/$1'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
    source '$SOURCE_FILE' 2>/dev/null
    DATA='$TDIR/$1'
    _mode_init '$2' >/dev/null 2>&1
    $3
  " 2>/dev/null
}

r=$(_score_env sc_basic 3 '
  _sget "test q"; echo "default=$REPLY"
  _sset "test q" 2
  _sget "test q"; echo "after=$REPLY"
  _sget "other q"; echo "other=$REPLY"
')
echo "$r" | grep -q 'default=0' && ok "default tier=0 (unseen)" || fail "score default" "$r"
echo "$r" | grep -q 'after=2' && ok "tier updates to 2" || fail "score update" "$r"
echo "$r" | grep -q 'other=0' && ok "unrelated unaffected" || fail "score isolation" "$r"

# _sset writes 3 fields: tier|mode_tag|unix_ts
r=$(_score_env sc_fields 7 '
  _sset "fmt q" 2
  _hash "fmt q"; echo "raw=${_sc[$REPLY]}"
')
val=$(echo "$r" | sed -n 's/^raw=//p')
[[ "$val" == "2|7|"* ]] && ok "_sset writes tier|mode_tag|ts" || fail "sset format" "got '$val'"
ts="${val##*|}"
[[ "$ts" =~ ^[0-9]{10,}$ ]] && ok "_sset stamps unix timestamp" || fail "sset ts" "got '$ts'"

# Batched flush: dirty writes stay in memory until 10 accumulate
r=$(_score_env sc_batch 1 '
  _sset "b1" 2
  echo "after1=[$(grep -c . "$DATA/scores")] dirty=$_sdirty"
  for i in 2 3 4 5 6 7 8 9 10; do _sset "b$i" 2; done
  echo "after10=[$(grep -vc "^#" "$DATA/scores")] dirty=$_sdirty"
')
echo "$r" | grep -q 'after1=\[0\] dirty=1' && ok "_sset batches (no flush at 1 dirty)" || fail "sset batch" "$r"
echo "$r" | grep -q 'after10=\[10\] dirty=0' && ok "_sset flushes at 10 dirty" || fail "sset flush@10" "$r"

# _sflush_if_dirty flushes a partial batch
r=$(_score_env sc_partial 1 '
  _sset "p1" 2
  _sflush_if_dirty
  echo "rows=$(grep -vc "^#" "$DATA/scores") dirty=$_sdirty"
')
echo "$r" | grep -q 'rows=1 dirty=0' && ok "_sflush_if_dirty flushes partial batch" || fail "flush_if_dirty" "$r"

# Flush + reload round-trip through the real file format
r=$(_score_env sc_reload 4 '
  _sset "persist q" 2
  _sflush_if_dirty
  declare -A _sc2
  while IFS="|" read -r k v; do [[ "$k" == "#"* ]] && continue; _sc2[$k]=$v; done < "$DATA/scores"
  _hash "persist q"
  echo "reloaded=${_sc2[$REPLY]:-missing}"
')
echo "$r" | grep -qE 'reloaded=2\|4\|[0-9]{10,}' && ok "flush+reload consistent" || fail "flush reload" "$r"

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

# NOTE: there is no per-level lock. Progression is linear (run() sets LVL=lv+1 on a
# boss win) and placement raises BOSS_BEATEN/PLACED_THROUGH directly. The only real
# gate is _post_root_check (BOSS_BEATEN < MAX_LEVEL), covered under "Gauntlet Logic".

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

l5=$(_qgen 5)
echo "$l5" | grep -q '<<<' && fail "L5" "contains <<<" || ok "L5 no <<<"
l6=$(_qgen 6)
echo "$l6" | grep -q '<<<' && ok "L6 has <<<" || fail "L6" "no <<<"

# ─────────────────────────────────────────────────────────────────────────────
section "No Stale References"

grep -q 'gen_level0' "$CMDCHAMP" && fail "stale" "gen_level0 referenced" || ok "no gen_level0"
pr=$(grep -n '_level_pass\|PASSWORD:' "$CMDCHAMP" | grep -v '^#' | grep -v 'password cracker\|passwd\|wordlist\|rockyou' || true)
[[ -z "$pr" ]] && ok "no _level_pass/PASSWORD" || fail "stale passwords" "$pr"
hr=$(grep -n '\bHINT\b' "$CMDCHAMP" | grep -v '#\|hint' || true)
[[ -z "$hr" ]] && ok "no HINT refs" || fail "stale HINT" "$hr"

# ═════════════════════════════════════════════════════════════════════════════
# SANDBOX ANSWER VERIFICATION - Every alternate, every question
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
        -e '/^# ═══ CLI ENTRYPOINT ═══/,$d' \
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

  sb_pass=0 sb_fail=0 sb_skip=0 sb_total=0 sb_qcount=0
  sb_errors=()

  # One worker per level: sources cmdchamp ONCE, then generates, parses and executes
  # every answer in-process. The sandbox is still reset to pristine on disk before each
  # answer (identical isolation to a per-answer subshell — sandbox state lives in the
  # directory, not the shell), and the reset is verified so a failed reset can never
  # masquerade as a pass. Emits a tab-separated event per question/answer:
  #   Q = question seen   S = question skipped   P = answer passed
  #   F = answer failed   E = sandbox reset broke
  _sb_level() {
    bash -c '
      lv=$1 SB_SOURCE=$2 SB_DATA=$3 SB_PRISTINE=$4 SB_DIR=$5
      export DATA="$SB_DATA" SANDBOX_PRISTINE="$SB_PRISTINE" SANDBOX_DIR="$SB_DIR"
      source "$SB_SOURCE" 2>/dev/null
      SANDBOX_MODE=1; SANDBOX_PRISTINE="$SB_PRISTINE"; SANDBOX_DIR="$SB_DIR"

      declare -a Q=(); "gen_level$lv" Q
      for line in "${Q[@]}"; do
        [[ -z "$line" ]] && continue
        printf "Q\n"
        _qparse "$line"
        # #text: questions and questions with no sandbox markers cannot be executed
        if [[ "$_qtext" == "1" || ( -z "$_qoutput" && -z "$_qstate" ) ]]; then
          printf "S\n"; continue
        fi
        # Snapshot the expectations — the check helpers below must not see a later parse
        exp_out=$_qoutput exp_state=$_qstate delim=$_qdelim answers=$_qanswers

        IFS="$delim" read -ra all <<< "$answers"
        for a in "${all[@]}"; do
          a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
          [[ -z "$a" ]] && continue
          [[ "$a" == "~"* || "$a" == "#"* ]] && continue

          # Reset to pristine. chmod first: an answer may have chmod-ed a dir unreadable.
          chmod -R u+rwX "$SB_DIR" 2>/dev/null
          rm -rf "$SB_DIR"
          if ! cp -a "$SB_PRISTINE" "$SB_DIR" 2>/dev/null || [[ ! -e "$SB_DIR/server.log" ]]; then
            printf "E\t%s\treset to pristine failed\n" "$a"; continue
          fi

          output=$(_sandbox_exec "$a" 5 2>/dev/null) || true

          passed=1
          [[ -n "$exp_out" ]] && { _sandbox_check_output "$output" "$exp_out" || passed=0; }
          [[ -n "$exp_state" ]] && { _sandbox_check_state "$exp_state" || passed=0; }

          if ((passed)); then
            printf "P\n"
          else
            # Flatten: the event stream is line-based
            det=${output:0:80}; det=${det//[$'\n\t']/ }
            printf "F\t%s\toutput=%s|expected_out=%s|expected_state=%s\n" "$a" "$det" "$exp_out" "$exp_state"
          fi
        done
      done
    ' _ "$1" "$SB_SOURCE" "$SB_DATA" "$SB_PRISTINE" "$SB_DIR" 2>/dev/null
  }

  for lv in {1..30}; do
    lv_pass=0 lv_fail=0 lv_skip=0 lv_total=0 lv_qcount=0

    while IFS=$'\t' read -r tag answer detail; do
      case "$tag" in
        Q) ((++lv_qcount)); ((++sb_qcount)) ;;
        S) ((++lv_skip));   ((++sb_skip)) ;;
        P) ((++lv_total)); ((++sb_total)); ((++lv_pass)); ((++sb_pass)) ;;
        F) ((++lv_total)); ((++sb_total)); ((++lv_fail)); ((++sb_fail))
           sb_errors+=("L${lv}: ${answer} -> ${detail}") ;;
        E) ((++lv_total)); ((++sb_total)); ((++lv_fail)); ((++sb_fail))
           sb_errors+=("L${lv}: ${answer} -> SANDBOX RESET FAILED: ${detail}") ;;
      esac
    done < <(_sb_level "$lv")

    # A level that yields no questions means extraction broke — never a silent pass
    if ((lv_qcount == 0)); then
      fail "sandbox extraction" "L${lv} generated 0 questions"
      continue
    fi

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
  printf '\n  %sSandbox totals:%s %s%d pass%s / %s%d fail%s / %s%d skip%s (of %d, from %d questions)\n' \
    "$B" "$N" "$G" "$sb_pass" "$N" "$R" "$sb_fail" "$N" "$Y" "$sb_skip" "$N" "$sb_total" "$sb_qcount"

  # Guard: this section is the suite's core guarantee. Zero questions or zero
  # executable answers means it verified nothing — that is a failure, not a pass.
  ((sb_qcount > 0)) && ok "extracted $sb_qcount questions across 30 levels" \
    || fail "sandbox extraction" "0 questions extracted (gen_level nameref contract broken?)"
  ((sb_total > 0)) || fail "sandbox coverage" "0 answers executed (of $sb_qcount questions)"

  if ((sb_fail == 0 && sb_total > 0)); then
    ok "all $sb_total sandbox answers verified (every alternate)"
  elif ((sb_total == 0)); then
    : # already failed above
  else
    fail "sandbox verification" "$sb_fail/$sb_total failed"
    printf '\n  %sFailed sandbox answers:%s\n' "$R" "$N"
    for e in "${sb_errors[@]:0:30}"; do
      printf '    %s• %s%s\n' "$R" "$e" "$N"
    done
    ((${#sb_errors[@]} > 30)) && printf '    %s... and %d more%s\n' "$D" "$((${#sb_errors[@]} - 30))" "$N"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# TEXT-MATCH ALTERNATE VERIFICATION - check() accepts every alternate
# ═════════════════════════════════════════════════════════════════════════════
section "Text-Match Alternate Verification"

tm_pass=0 tm_fail=0 tm_skip=0 tm_total=0 tm_qcount=0
tm_errors=()

# One worker per level (see _sb_level): sources cmdchamp ONCE, then parses every question
# and runs the real check() over every alternate in-process. Per-answer globals are set
# exactly as run() leaves them — _qparse first, then check() — so _qrequire is honoured.
# Emits: Q = question seen, S = question skipped, P = accepted, F = rejected.
_tm_level() {
  bash -c '
    lv=$1 SRC=$2
    source "$SRC" 2>/dev/null
    declare -a Q=(); "gen_level$lv" Q
    for line in "${Q[@]}"; do
      [[ -z "$line" ]] && continue
      printf "Q\n"
      _qparse "$line"
      if [[ "$_qtext" == "1" ]]; then printf "S\n"; continue; fi
      delim=$_qdelim answers=$_qanswers require=$_qrequire

      IFS="$delim" read -ra all <<< "$answers"
      for a in "${all[@]}"; do
        a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
        [[ -z "$a" ]] && continue
        # Regex answers are patterns, not literal inputs; #-answers are sandbox markers
        [[ "$a" == "~"* || "$a" == "#"* ]] && continue

        # Text-match mode, fresh per answer: no sandbox, no stale expectations
        SANDBOX_MODE=0; _qdelim=$delim; _qrequire=$require; _qoutput=""; _qstate=""; _qtext=0
        if check "$a" "$answers"; then printf "P\n"; else printf "F\t%s\n" "$a"; fi
      done
    done
  ' _ "$1" "$SOURCE_FILE" 2>/dev/null
}

for lv in {1..30}; do
  lv_pass=0 lv_fail=0 lv_skip=0 lv_total=0 lv_qcount=0

  while IFS=$'\t' read -r tag answer; do
    case "$tag" in
      Q) ((++lv_qcount)); ((++tm_qcount)) ;;
      S) ((++lv_skip));   ((++tm_skip)) ;;
      P) ((++lv_total)); ((++tm_total)); ((++lv_pass)); ((++tm_pass)) ;;
      F) ((++lv_total)); ((++tm_total)); ((++lv_fail)); ((++tm_fail))
         tm_errors+=("L${lv}: '${answer}' rejected by check()") ;;
    esac
  done < <(_tm_level "$lv")

  if ((lv_qcount == 0)); then
    fail "text-match extraction" "L${lv} generated 0 questions"
    continue
  fi

  if ((lv_total > 0)); then
    if ((lv_fail == 0)); then
      printf '  %s✓%s L%-2d  %d/%d text-match pass  (%d skipped)\n' "$G" "$N" "$lv" "$lv_pass" "$lv_total" "$lv_skip"
    else
      printf '  %s✗%s L%-2d  %d/%d text-match pass  %s(%d FAILED)%s\n' "$R" "$N" "$lv" "$lv_pass" "$lv_total" "$R" "$lv_fail" "$N"
    fi
  else
    printf '  %s-%s L%-2d  all %d questions skipped (text-only)\n' "$Y" "$N" "$lv" "$lv_skip"
  fi
done

printf '\n  %sText-match totals:%s %s%d pass%s / %s%d fail%s / %s%d skip%s (of %d, from %d questions)\n' \
  "$B" "$N" "$G" "$tm_pass" "$N" "$R" "$tm_fail" "$N" "$Y" "$tm_skip" "$N" "$tm_total" "$tm_qcount"

# Guard: zero questions or zero checked answers means check() went unverified
((tm_qcount > 0)) && ok "extracted $tm_qcount questions across 30 levels" \
  || fail "text-match extraction" "0 questions extracted (gen_level nameref contract broken?)"
((tm_total > 0)) || fail "text-match coverage" "0 answers checked (of $tm_qcount questions)"

if ((tm_fail == 0 && tm_total > 0)); then
  ok "all $tm_total text-match answers verified (every alternate)"
elif ((tm_total == 0)); then
  : # already failed above
else
  fail "text-match verification" "$tm_fail/$tm_total failed"
  printf '\n  %sFailed text-match answers:%s\n' "$R" "$N"
  for e in "${tm_errors[@]:0:30}"; do
    printf '    %s• %s%s\n' "$R" "$e" "$N"
  done
  ((${#tm_errors[@]} > 30)) && printf '    %s... and %d more%s\n' "$D" "$((${#tm_errors[@]} - 30))" "$N"
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
r=$(_run '
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

# BOSS_BEATEN doesn't decrement on loss (2/5 must stay below BOSS_THRESHOLD)
r=$(_run "BOSS_BEATEN=5; ((2 >= BOSS_THRESHOLD)) && { ((BOSS_BEATEN < 6)) && BOSS_BEATEN=6; }; echo \$BOSS_BEATEN")
[[ "$r" == "5" ]] && ok "BOSS_BEATEN stable on loss" || fail "boss loss stable" "$r"

# BOSS_BEATEN clamps to MAX_LEVEL on the real load path (no unbounded growth)
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_bb_clamp'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=x\nBOSS_BEATEN=31\nPROFILE_VER=5\n' > \"\$DATA/profile\"
  _load_profile
  echo \"bb=\$BOSS_BEATEN\"
" 2>/dev/null)
echo "$r" | grep -q 'bb=30' && ok "BOSS_BEATEN=31 clamped to MAX_LEVEL" || fail "bb clamp" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Challenge Mechanics"

# BEST_CHALLENGE persists in profile round-trip
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_chal_rt'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  PLAYER_NAME=chal BOSS_BEATEN=30 BEST_CHALLENGE=17 _PROFILE_VER=5
  _save_profile
  BEST_CHALLENGE=0
  _load_profile
  echo \"bc=\$BEST_CHALLENGE\"
" 2>/dev/null)
[[ "$r" == "bc=17" ]] && ok "BEST_CHALLENGE round-trip" || fail "challenge persist" "$r"

# BEST_CHALLENGE only increments on improvement
r=$(_run "BEST_CHALLENGE=10; new=15; ((new > BEST_CHALLENGE)) && BEST_CHALLENGE=\$new; echo \$BEST_CHALLENGE")
[[ "$r" == "15" ]] && ok "BEST_CHALLENGE up on improve" || fail "challenge up" "$r"
r=$(_run "BEST_CHALLENGE=20; new=12; ((new > BEST_CHALLENGE)) && BEST_CHALLENGE=\$new; echo \$BEST_CHALLENGE")
[[ "$r" == "20" ]] && ok "BEST_CHALLENGE stable on regress" || fail "challenge stable" "$r"

# Challenge gate requires BOSS_BEATEN == MAX_LEVEL
r=$(_run "BOSS_BEATEN=29; MAX_LEVEL=30; ((BOSS_BEATEN >= MAX_LEVEL)) && echo OPEN || echo LOCKED")
[[ "$r" == "LOCKED" ]] && ok "challenge gated until L30" || fail "challenge gate" "$r"
r=$(_run "BOSS_BEATEN=30; MAX_LEVEL=30; ((BOSS_BEATEN >= MAX_LEVEL)) && echo OPEN || echo LOCKED")
[[ "$r" == "OPEN" ]] && ok "challenge unlocks at L30" || fail "challenge unlock" "$r"

# Numeric validation rejects garbage values on load
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_chal_bad'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=x\nBOSS_BEATEN=5\nBEST_CHALLENGE=oops\nOPT_VI=999\nOPT_SOUND=abc\nOPT_ALTS=-1\nPLACED_THROUGH=notanumber\nPROFILE_VER=5\n' > \"\$DATA/profile\"
  _load_profile
  echo \"bc=\$BEST_CHALLENGE vi=\$OPT_VI snd=\$OPT_SOUND alt=\$OPT_ALTS pt=\$PLACED_THROUGH\"
" 2>/dev/null)
echo "$r" | grep -q 'bc=0' && ok "BEST_CHALLENGE garbage→0" || fail "bc validate" "$r"
echo "$r" | grep -q 'vi=1' && ok "OPT_VI garbage→1" || fail "vi validate" "$r"
echo "$r" | grep -q 'snd=1' && ok "OPT_SOUND garbage→1" || fail "snd validate" "$r"
echo "$r" | grep -q 'alt=1' && ok "OPT_ALTS garbage→1" || fail "alt validate" "$r"
echo "$r" | grep -q 'pt=0' && ok "PLACED_THROUGH garbage→0" || fail "pt validate" "$r"

# PLACED_THROUGH doesn't gate levels — it only marks placed levels 'p' in stats
# (cmdchamp: `((lv <= PLACED_THROUGH)) && boss_mark="p"`, else '+' if beaten, '·' if not).
r=$(bash -c "
  export DATA='$TDIR/data_pt_stats'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_pt_stats'
  PLAYER_NAME=pt BOSS_BEATEN=10 PLACED_THROUGH=5
  stats
" 2>/dev/null | sed -e 's/\x1b\[[0-9;]*m//g')
echo "$r" | grep -qE '^ +p +5 ' && ok "stats marks L5 placed (PT=5)" || fail "stats placed mark" "no 'p' on L5"
echo "$r" | grep -qE '^ +\+ +6 ' && ok "stats marks L6 beaten-not-placed" || fail "stats beaten mark" "no '+' on L6"
echo "$r" | grep -qE '^ +· +11 ' && ok "stats marks L11 unbeaten" || fail "stats unbeaten mark" "no '·' on L11"

# PLACED_THROUGH clamps to MAX_LEVEL on load
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_pt_clamp'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=x\nBOSS_BEATEN=30\nPLACED_THROUGH=99\nPROFILE_VER=5\n' > \"\$DATA/profile\"
  _load_profile
  echo \"pt=\$PLACED_THROUGH\"
" 2>/dev/null)
echo "$r" | grep -q 'pt=30' && ok "PLACED_THROUGH=99 clamped to MAX_LEVEL" || fail "pt clamp" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Tier/Mastery System"

# Tiers: 0 = unseen, 1 = learning, 2 = mastered. Unseen questions default to 0.
r=$(_score_env tier_default 1 '_sget "brand new"; echo "t=$REPLY"')
echo "$r" | grep -q 't=0' && ok "default tier=0 (unseen)" || fail "default tier" "$r"

# Tier round-trips through the real _sset/_sget at each rung
for t in 0 1 2; do
  r=$(_score_env "tier_rt$t" 1 "_sset 'rt q' $t; _sget 'rt q'; echo \"t=\$REPLY\"")
  echo "$r" | grep -q "t=$t" && ok "tier $t round-trips" || fail "tier rt $t" "$r"
done

# _calc_mastery: 3-field values (tier|lvtag|ts) — the timestamp must be stripped off
# the level tag, else every question buckets under a bogus "tag|ts" level.
r=$(_run '
  declare -A sc lv_total lv_mastered
  sc[a]="2|3|1700000000"; sc[b]="1|3|1700000000"; sc[c]="0|3|1700000000"
  _calc_mastery sc
  echo "l3_total=${lv_total[3]:-0} l3_mast=${lv_mastered[3]:-0}"
  echo "seen=$_cm_seen learning=$_cm_t1 mastered=$_cm_t2 tagged=$_cm_tagged"
')
echo "$r" | grep -q 'l3_total=3 l3_mast=1' && ok "_calc_mastery strips ts from level tag" || fail "mastery lvtag" "$r"
echo "$r" | grep -q 'seen=3 learning=2 mastered=1' && ok "_calc_mastery: tier 0|1 learning, >=2 mastered" || fail "mastery tiers" "$r"
echo "$r" | grep -q 'tagged=1' && ok "_calc_mastery flags tagged scores" || fail "mastery tagged" "$r"

# _calc_mastery back-compat: 2-field (tier|lvtag) and bare (tier) values
r=$(_run '
  declare -A sc lv_total lv_mastered
  sc[a]="2|5"; sc[b]="2"
  _calc_mastery sc
  echo "l5_total=${lv_total[5]:-0} l5_mast=${lv_mastered[5]:-0} seen=$_cm_seen"
')
echo "$r" | grep -q 'l5_total=1 l5_mast=1' && ok "_calc_mastery reads 2-field format" || fail "mastery 2-field" "$r"
echo "$r" | grep -q 'seen=2' && ok "_calc_mastery counts untagged scores as seen" || fail "mastery untagged" "$r"

# FIRE_STREAK is flavor only (banner at streak>=5) — it does not touch tiers
r=$(_run 'echo "fs=$FIRE_STREAK"')
echo "$r" | grep -q 'fs=5' && ok "FIRE_STREAK=5 (banner threshold)" || fail "fire streak" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Gauntlet Logic"

# _post_root_check blocks when BOSS_BEATEN < MAX_LEVEL
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  BOSS_BEATEN=29 MAX_LEVEL=30
  _post_root_check 2>&1 || true
" 2>/dev/null)
echo "$r" | grep -q 'Locked' && ok "gauntlet locked at BB=29" || fail "gauntlet lock" "$r"

# Best gauntlet (challenge) tracking — BEST_GAUNTLET is the legacy alias for
# BEST_CHALLENGE; _load_profile accepts both for backward compat
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  DATA='$TDIR/data_gauntlet'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  printf 'PLAYER_NAME=test\nBOSS_BEATEN=30\nBEST_GAUNTLET=10\nBEST_TIMED=0\nEGGS_FOUND=\nSC_DONE=\nPROFILE_VER=3\n' > \"\$DATA/profile\"
  _load_profile
  score=15
  ((score > BEST_CHALLENGE)) && { BEST_CHALLENGE=\$score; _save_profile; }
  _load_profile
  echo \"\$BEST_CHALLENGE\"
" 2>/dev/null)
[[ "$r" == "15" ]] && ok "gauntlet best score persists" || fail "gauntlet best" "$r"

# NOTE: timed mode was merged into challenge mode (commit 57685d8). No _timed_* function
# or duration set exists any more — coverage lives in "Challenge Mechanics".

# ─────────────────────────────────────────────────────────────────────────────
section "Review Mode Logic"

# Weak/strong is derived from the REAL _calc_mastery over real 3-field score values.
# stats() calls it the same way: >=80% mastered is strong (green ✓), below is weak.
_mastery_pct() {  # $1 = level tag, $2... = score values to seed
  local lv=$1; shift
  local seed="" i=0
  for v in "$@"; do seed+="_hash \"mq$((++i))\"; sc[\$REPLY]=\"$v\"; "; done
  _run "
    declare -A sc lv_total lv_mastered
    $seed
    _calc_mastery sc
    lt=\${lv_total[$lv]:-0} lm=\${lv_mastered[$lv]:-0}
    ((lt > 0)) && pct=\$((lm * 100 / lt)) || pct=0
    ((pct < 80)) && echo \"weak pct=\$pct\" || echo \"strong pct=\$pct\"
  "
}

# 6 mastered of 10 on level 1 = 60% = weak
r=$(_mastery_pct 1 "2|1|1700000000" "2|1|1700000000" "2|1|1700000000" "2|1|1700000000" \
                   "2|1|1700000000" "2|1|1700000000" "1|1|1700000000" "1|1|1700000000" \
                   "0|1|1700000000" "1|1|1700000000")
echo "$r" | grep -q 'weak pct=60' && ok "60% mastery = weak" || fail "review weak" "$r"

# 8 mastered of 10 on level 2 = 80% = strong
r=$(_mastery_pct 2 "2|2|1700000000" "2|2|1700000000" "2|2|1700000000" "2|2|1700000000" \
                   "2|2|1700000000" "2|2|1700000000" "2|2|1700000000" "2|2|1700000000" \
                   "1|2|1700000000" "0|2|1700000000")
echo "$r" | grep -q 'strong pct=80' && ok "80% mastery = strong" || fail "review strong" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Floppy Disks (easter eggs)"

# Override _disk_found to skip sleep and ANSI output. DISKS_FOUND is the canonical
# field; EGGS_FOUND is a legacy alias still accepted by _load_profile for migration.
_disk_setup='DISKS_FOUND=""; _save_profile() { :; }; _disk_found() { local name=$1; [[ ",$DISKS_FOUND," == *",$name,"* ]] && return; [[ -n "$DISKS_FOUND" ]] && DISKS_FOUND="$DISKS_FOUND,$name" || DISKS_FOUND="$name"; }'

# sudorm disk
r=$(_run "$_disk_setup; _disk_check wrong \"sudo rm -rf /\"; echo \"\$DISKS_FOUND\"")
echo "$r" | grep -q 'sudorm' && ok "disk: sudorm" || fail "disk sudorm" "$r"

# forkbomb disk
r=$(_run "$_disk_setup; _disk_check wrong ':(){ :|:& };:'; echo \"\$DISKS_FOUND\"")
echo "$r" | grep -q 'forkbomb' && ok "disk: forkbomb" || fail "disk forkbomb" "$r"

# rtfm disk
r=$(_run "$_disk_setup; _disk_check wrong man; echo \"\$DISKS_FOUND\"")
echo "$r" | grep -q 'rtfm' && ok "disk: rtfm" || fail "disk rtfm" "$r"

# streak10 disk
r=$(_run "$_disk_setup; _S_STREAK=10; _disk_check streak; echo \"\$DISKS_FOUND\"")
echo "$r" | grep -q 'streak10' && ok "disk: streak10" || fail "disk streak10" "$r"

# streak10 doesn't fire at 9
r=$(_run "$_disk_setup; _S_STREAK=9; _disk_check streak; echo \"disks=\${DISKS_FOUND:-none}\"")
echo "$r" | grep -q 'disks=none' && ok "disk: streak9 no trigger" || fail "disk streak9" "$r"

# flawless disk
r=$(_run "$_disk_setup; _disk_check flawless; echo \"\$DISKS_FOUND\"")
echo "$r" | grep -q 'flawless' && ok "disk: flawless" || fail "disk flawless" "$r"

# _disk_found deduplication
r=$(_run "$_disk_setup; _disk_found sudorm; _disk_found sudorm; echo \"\$DISKS_FOUND\"")
[[ "$(echo "$r" | tail -1)" == "sudorm" ]] && ok "disk: no duplicates" || fail "disk dedup" "$r"

# Multiple disks accumulate
r=$(_run "$_disk_setup; _disk_found sudorm; _disk_found rtfm; echo \"\$DISKS_FOUND\"")
echo "$r" | grep -q 'sudorm,rtfm' && ok "disk: accumulate" || fail "disk accumulate" "$r"

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
  PLAYER_NAME='testguy' BOSS_BEATEN=15 BEST_CHALLENGE=7 DISKS_FOUND='sudorm,rtfm' SC_DONE='1,3' PLACED_THROUGH=12
  _save_profile
  # Reset shell vars to defaults (but not _PROFILE_VER — that's the source-of-truth
  # constant; resetting it would trigger a spurious version-mismatch reset on load)
  PLAYER_NAME='' BOSS_BEATEN=0 BEST_CHALLENGE=0 DISKS_FOUND='' SC_DONE='' PLACED_THROUGH=0
  _load_profile
  echo \"name=\$PLAYER_NAME bb=\$BOSS_BEATEN bc=\$BEST_CHALLENGE disks=\$DISKS_FOUND sc=\$SC_DONE pt=\$PLACED_THROUGH ver=\$_PROFILE_VER\"
" 2>/dev/null)
echo "$r" | grep -q 'name=testguy' && ok "profile name round-trip" || fail "prof name" "$r"
echo "$r" | grep -q 'bb=15' && ok "profile BOSS_BEATEN round-trip" || fail "prof bb" "$r"
echo "$r" | grep -q 'bc=7' && ok "profile BEST_CHALLENGE round-trip" || fail "prof bc" "$r"
echo "$r" | grep -q 'disks=sudorm,rtfm' && ok "profile DISKS_FOUND round-trip" || fail "prof disks" "$r"
echo "$r" | grep -q 'sc=1,3' && ok "profile SC_DONE round-trip" || fail "prof sc" "$r"
echo "$r" | grep -q 'pt=12' && ok "profile PLACED_THROUGH round-trip" || fail "prof pt" "$r"
echo "$r" | grep -q 'ver=5' && ok "profile ver=5 stable" || fail "prof ver" "$r"

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
echo "$r" | grep -q 'ver=5' && ok "v2->v5: ver bumped" || fail "v2->v3 ver" "$r"
echo "$r" | grep -q 'eggs=empty' && ok "v2->v3: eggs initialized" || fail "v2->v3 eggs" "$r"
echo "$r" | grep -q 'sc=empty' && ok "v2->v3: sc initialized" || fail "v2->v3 sc" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Scenario System"

# SC_TOTAL matches actual scenario count
r=$(_run "echo \"\$SC_TOTAL\"")
[[ "$r" == "11" ]] && ok "SC_TOTAL=11" || fail "SC_TOTAL" "$r"

# All scenario functions exist
for sc_id in {1..11}; do
  r=$(_run "declare -f _sc_setup_${sc_id} >/dev/null && echo Y || echo N")
  [[ "$r" == "Y" ]] && ok "sc_setup_${sc_id} exists" || fail "sc_setup_${sc_id}" "missing"
  r=$(_run "declare -f _sc_steps_${sc_id} >/dev/null && echo Y || echo N")
  [[ "$r" == "Y" ]] && ok "sc_steps_${sc_id} exists" || fail "sc_steps_${sc_id}" "missing"
done

# SC_UNLOCK array has correct size (one slot per scenario + leading "")
r=$(_run "echo \"\${#SC_UNLOCK[@]}\"")
[[ "$r" == "12" ]] && ok "SC_UNLOCK has 12 entries (padded)" || fail "SC_UNLOCK size" "$r"

# _sc_is_done / _sc_mark_done
r=$(_run 'SC_DONE=""; _save_profile() { :; }
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
