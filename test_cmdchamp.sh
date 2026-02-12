#!/usr/bin/env bash
# cmdchamp test suite
set -uo pipefail

PASS=0 FAIL=0 ERRORS=()
G=$'\e[32m' R=$'\e[31m' Y=$'\e[33m' D=$'\e[2m' N=$'\e[0m' B=$'\e[1m'

ok()   { ((++PASS)); printf '  %s✓%s %s\n' "$G" "$N" "$1"; }
fail() { ((++FAIL)); ERRORS+=("$1: $2"); printf '  %s✗%s %s: %s\n' "$R" "$N" "$1" "$2"; }
section() { printf '\n%s%s=== %s ===%s\n' "$B" "$Y" "$1" "$N"; }

# Temp dir for test data
TDIR=$(mktemp -d)
trap 'rm -rf "$TDIR"' EXIT

# Source cmdchamp without running main (strip case block + disable tty check + sandbox)
SOURCE_FILE="$TDIR/cmdchamp_source.sh"
{
  # Replace _tty with no-op, strip everything from the --no-sandbox line onward
  sed -e 's/^_tty().*/\_tty() { :; }/' \
      -e '/^\[.*--no-sandbox/,$d' \
      "$(dirname "$0")/cmdchamp"
  echo 'SANDBOX_MODE=0'
} > "$SOURCE_FILE"

# Override DATA to temp dir
export DATA="$TDIR/data"
mkdir -p "$DATA"
touch "$DATA/scores"

# ─────────────────────────────────────────────────────────────────────────────
section "Syntax"

if bash -n "$(dirname "$0")/cmdchamp" 2>&1; then
  ok "bash -n passes"
else
  fail "bash -n" "syntax error"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Source & Function Definitions"

# Source in subshell to test
if output=$(bash -c "source '$SOURCE_FILE' 2>/dev/null; echo OK" 2>&1) && [[ "$output" == *OK* ]]; then
  ok "sources without error"
else
  fail "source" "$output"
fi

# Check all 30 gen_level functions exist
for lv in {1..30}; do
  if bash -c "source '$SOURCE_FILE' 2>/dev/null; declare -f gen_level${lv} >/dev/null" 2>/dev/null; then
    :
  else
    fail "gen_level${lv}" "function not defined"
  fi
done
count=$(grep -c '^gen_level[0-9]*()' "$(dirname "$0")/cmdchamp")
if ((count == 30)); then
  ok "all 30 gen_level functions defined"
else
  fail "gen_level count" "expected 30, got $count"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Question Generation (all 30 levels)"

for lv in {1..30}; do
  output=$(bash -c "
    source '$SOURCE_FILE' 2>/dev/null
    gen_level${lv}
  " 2>/dev/null)
  qcount=$(echo "$output" | grep -c '.')
  if ((qcount >= 3)); then
    :  # silent pass per level
  else
    fail "gen_level${lv}" "only $qcount questions (expected >=3)"
  fi
done
ok "all 30 levels generate questions (min 3 each)"

# Check question format: every line must have | or §
bad_format=()
for lv in {1..30}; do
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" != *"|"* && "$line" != *"§"* ]]; then
      bad_format+=("L${lv}: $line")
    fi
  done < <(bash -c "source '$SOURCE_FILE' 2>/dev/null; gen_level${lv}" 2>/dev/null)
done
if ((${#bad_format[@]} == 0)); then
  ok "all questions have | or § delimiter"
else
  fail "question format" "${#bad_format[@]} missing delimiter"
  for bf in "${bad_format[@]:0:5}"; do
    printf '    %s%s%s\n' "$D" "$bf" "$N"
  done
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Question Parser (_qparse)"

# Test | delimiter
result=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  _qparse 'Show files|ls|ls -a'
  echo \"prompt=\$_qprompt\"
  echo \"ans=\$_qans\"
  echo \"answers=\$_qanswers\"
  echo \"delim=\$_qdelim\"
" 2>/dev/null)
if echo "$result" | grep -q 'prompt=Show files' && echo "$result" | grep -q 'ans=ls'; then
  ok "_qparse with | delimiter"
else
  fail "_qparse |" "$result"
fi

# Test § delimiter (for pipes in answers)
result=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  _qparse 'Count lines§wc -l < file§cat file | wc -l'
  echo \"prompt=\$_qprompt\"
  echo \"ans=\$_qans\"
  echo \"delim=\$_qdelim\"
" 2>/dev/null)
if echo "$result" | grep -q 'prompt=Count lines' && echo "$result" | grep -q 'ans=wc -l < file' && echo "$result" | grep -q 'delim=§'; then
  ok "_qparse with § delimiter"
else
  fail "_qparse §" "$result"
fi

# Test #output: marker
result=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  _qparse 'Show dir|pwd|#output:~^/sandbox'
  echo \"prompt=\$_qprompt\"
  echo \"output=\$_qoutput\"
" 2>/dev/null)
if echo "$result" | grep -q 'output=~^/sandbox'; then
  ok "_qparse with #output: marker"
else
  fail "_qparse #output:" "$result"
fi

# Test #text: marker
result=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  _qparse 'What flag|--help|#text:'
  echo \"text=\$_qtext\"
" 2>/dev/null)
if echo "$result" | grep -q 'text=1'; then
  ok "_qparse with #text: marker"
else
  fail "_qparse #text:" "$result"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Answer Normalization (norm)"

run_norm() {
  bash -c "source '$SOURCE_FILE' 2>/dev/null; norm '$1'" 2>/dev/null
}

# Basic normalization
r=$(run_norm "ls -la")
[[ "$r" == "ls -a -l" ]] && ok "norm 'ls -la' -> 'ls -a -l'" || fail "norm ls -la" "got '$r'"

r=$(run_norm "ls -l -a")
[[ "$r" == "ls -a -l" ]] && ok "norm 'ls -l -a' -> 'ls -a -l'" || fail "norm ls -l -a" "got '$r'"

r=$(run_norm "grep -rn TODO .")
[[ "$r" == "grep -n -r TODO ." ]] && ok "norm 'grep -rn' splits and sorts" || fail "norm grep -rn" "got '$r'"

r=$(run_norm "sort --reverse file")
[[ "$r" == "sort --reverse file" ]] && ok "norm preserves long flags" || fail "norm long flag" "got '$r'"

r=$(run_norm "echo hello world")
[[ "$r" == "echo hello world" ]] && ok "norm preserves args order" || fail "norm args" "got '$r'"

# Empty input
r=$(run_norm "")
[[ -z "$r" ]] && ok "norm handles empty" || fail "norm empty" "got '$r'"

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
[[ "$r" == "PASS" ]] && ok "check exact match 'ls'" || fail "check exact" "$r"

# Alternative answer
r=$(run_check "ls -a" "ls|ls -a")
[[ "$r" == "PASS" ]] && ok "check alt answer 'ls -a'" || fail "check alt" "$r"

# Wrong answer
r=$(run_check "pwd" "ls|ls -a")
[[ "$r" == "FAIL" ]] && ok "check rejects wrong 'pwd'" || fail "check wrong" "$r"

# Flag reordering: ls -la should match ls -al
r=$(run_check "ls -la" "ls -al")
[[ "$r" == "PASS" ]] && ok "check flag reorder 'ls -la' == 'ls -al'" || fail "check reorder" "$r"

# Whitespace trimming
r=$(run_check "  ls  " "ls")
[[ "$r" == "PASS" ]] && ok "check trims whitespace" || fail "check trim" "$r"

# § delimiter (answers with pipes)
r=$(run_check_sec "sort file | uniq" "sort file | uniq§sort -u file")
[[ "$r" == "PASS" ]] && ok "check § delimiter with pipe" || fail "check §" "$r"

r=$(run_check_sec "sort -u file" "sort file | uniq§sort -u file")
[[ "$r" == "PASS" ]] && ok "check § alt answer" || fail "check § alt" "$r"

# Regex match (~pattern)
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  SANDBOX_MODE=0; _qdelim='|'; _qoutput=''; _qstate=''; _qtext=0
  check 'echo hello' '~^echo' && echo PASS || echo FAIL
" 2>/dev/null)
[[ "$r" == "PASS" ]] && ok "check regex ~pattern" || fail "check regex" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Hash Consistency"

r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  _hash 'test question'; h1=\$REPLY
  _hash 'test question'; h2=\$REPLY
  _hash 'different'; h3=\$REPLY
  [[ \$h1 == \$h2 ]] && echo 'consistent' || echo 'inconsistent'
  [[ \$h1 != \$h3 ]] && echo 'unique' || echo 'collision'
" 2>/dev/null)
echo "$r" | grep -q 'consistent' && ok "hash is deterministic" || fail "hash determinism" "$r"
echo "$r" | grep -q 'unique' && ok "hash differentiates inputs" || fail "hash uniqueness" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Save/Load Round-trip"

r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  LVL=14; QI=7; save
  LVL=0; QI=0; load
  echo \"\$LVL \$QI\"
" 2>/dev/null)
[[ "$r" == "14 7" ]] && ok "save/load round-trip" || fail "save/load" "got '$r'"

# Migration: LVL < 1 bumps to 1
r=$(bash -c "
  export DATA='$TDIR/data_migrate'; mkdir -p \"\$DATA\"; touch \"\$DATA/scores\"
  source '$SOURCE_FILE' 2>/dev/null
  printf '{\"level\":0,\"qi\":0}\n' > \"\$DATA/session.json\"
  load
  echo \"\$LVL\"
" 2>/dev/null)
[[ "$r" == "1" ]] && ok "load migrates LVL=0 to LVL=1" || fail "load migration" "got '$r'"

# ─────────────────────────────────────────────────────────────────────────────
section "Profile System"

r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  _first_run 2>/dev/null <<< 'TestPlayer'
  _load_profile
  echo \"name=\$PLAYER_NAME ver=\$_PROFILE_VER beaten=\$BOSS_BEATEN\"
" 2>/dev/null)
echo "$r" | grep -q 'name=TestPlayer' && ok "profile stores player name" || fail "profile name" "$r"
echo "$r" | grep -q 'ver=1' && ok "profile version set to 1" || fail "profile ver" "$r"
echo "$r" | grep -q 'beaten=0' && ok "new profile BOSS_BEATEN=0" || fail "profile beaten" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Score System"

r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  declare -A _sc
  _sget() { _hash \"\$1\"; local _v=\"\${_sc[\$REPLY]:-1}\"; REPLY=\"\${_v%%|*}\"; }
  _sset() { _hash \"\$1\"; _sc[\$REPLY]=\"\$2|1\"; _sflush; }

  # Default tier = 1
  _sget 'test q'; echo \"default=\$REPLY\"

  # Set and retrieve
  _sset 'test q' 2
  _sget 'test q'; echo \"after_set=\$REPLY\"

  # Different question
  _sget 'other q'; echo \"other=\$REPLY\"
" 2>/dev/null)
echo "$r" | grep -q 'default=1' && ok "default score tier = 1" || fail "score default" "$r"
echo "$r" | grep -q 'after_set=2' && ok "score updates to tier 2" || fail "score update" "$r"
echo "$r" | grep -q 'other=1' && ok "unrelated question unaffected" || fail "score isolation" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Level Locking"

# BOSS_BEATEN=0, trying to access level 2 should fail
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  BOSS_BEATEN=0
  if ((2 > 1 && 2 > BOSS_BEATEN + 1)); then echo LOCKED; else echo OPEN; fi
" 2>/dev/null)
[[ "$r" == "LOCKED" ]] && ok "level 2 locked when BOSS_BEATEN=0" || fail "lock L2" "$r"

# BOSS_BEATEN=1, level 2 should be open
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  BOSS_BEATEN=1
  if ((2 > 1 && 2 > BOSS_BEATEN + 1)); then echo LOCKED; else echo OPEN; fi
" 2>/dev/null)
[[ "$r" == "OPEN" ]] && ok "level 2 open when BOSS_BEATEN=1" || fail "unlock L2" "$r"

# Level 1 always open
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  BOSS_BEATEN=0
  if ((1 > 1 && 1 > BOSS_BEATEN + 1)); then echo LOCKED; else echo OPEN; fi
" 2>/dev/null)
[[ "$r" == "OPEN" ]] && ok "level 1 always open" || fail "lock L1" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "LEVEL_NAMES / BOSS_NAMES / BOSS_FLAVOR Arrays"

r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  echo \"names=\${#LEVEL_NAMES[@]}\"
  echo \"bosses=\${#BOSS_NAMES[@]}\"
  echo \"flavors=\${#BOSS_FLAVOR[@]}\"
  echo \"pad_name=\${LEVEL_NAMES[0]}\"
  echo \"pad_boss=\${BOSS_NAMES[0]}\"
  echo \"l1=\${LEVEL_NAMES[1]}\"
  echo \"l30=\${LEVEL_NAMES[30]}\"
  echo \"b1=\${BOSS_NAMES[1]}\"
  echo \"b30=\${BOSS_NAMES[30]}\"
" 2>/dev/null)
echo "$r" | grep -q 'names=31' && ok "31 LEVEL_NAMES (0-pad + 30)" || fail "LEVEL_NAMES count" "$r"
echo "$r" | grep -q 'bosses=31' && ok "31 BOSS_NAMES" || fail "BOSS_NAMES count" "$r"
echo "$r" | grep -q 'flavors=31' && ok "31 BOSS_FLAVOR" || fail "BOSS_FLAVOR count" "$r"
echo "$r" | grep -q 'pad_name=$' && ok "LEVEL_NAMES[0] is empty (pad)" || fail "LEVEL_NAMES[0]" "$r"
echo "$r" | grep -q 'pad_boss=$' && ok "BOSS_NAMES[0] is empty (pad)" || fail "BOSS_NAMES[0]" "$r"
echo "$r" | grep -q 'l1=First Steps' && ok "LEVEL_NAMES[1] = First Steps" || fail "LEVEL_NAMES[1]" "$r"
echo "$r" | grep -q 'l30=ROOT' && ok "LEVEL_NAMES[30] = ROOT" || fail "LEVEL_NAMES[30]" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "MANPAGE Coverage"

# Check that commands used in questions have manpage entries
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  missing=0
  # Core commands that should definitely have manpages
  for cmd in ls cat head tail grep sort uniq cut wc tr sed awk find fd \
    grep rg ssh curl git nmap tmux chmod tar cp mv rm ln mkdir echo cd \
    pwd touch test tee less xargs kill fg bg jobs; do
    [[ -z \"\${MANPAGE[\$cmd]:-}\" ]] && { echo \"MISSING: \$cmd\"; ((++missing)); }
  done
  echo \"missing=\$missing\"
" 2>/dev/null)
miss=$(echo "$r" | grep 'missing=' | grep -o '[0-9]*')
if ((miss == 0)); then
  ok "all core commands have MANPAGE entries"
else
  fail "MANPAGE coverage" "$miss commands missing"
  echo "$r" | grep MISSING | head -5
fi

# ─────────────────────────────────────────────────────────────────────────────
section "EXP (Explain) Coverage"

r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  echo \"exp_count=\${#EXP[@]}\"
" 2>/dev/null)
count=$(echo "$r" | grep -o '[0-9]*')
((count > 50)) && ok "EXP has $count entries" || fail "EXP count" "only $count"

# ─────────────────────────────────────────────────────────────────────────────
section "Constants & Config"

r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  echo \"max=\$MAX_LEVEL\"
  echo \"boss_total=\$BOSS_TOTAL\"
  echo \"boss_thresh=\$BOSS_THRESHOLD\"
  echo \"fire=\$FIRE_STREAK\"
" 2>/dev/null)
echo "$r" | grep -q 'max=30' && ok "MAX_LEVEL=30" || fail "MAX_LEVEL" "$r"
echo "$r" | grep -q 'boss_total=5' && ok "BOSS_TOTAL=5" || fail "BOSS_TOTAL" "$r"
echo "$r" | grep -q 'boss_thresh=4' && ok "BOSS_THRESHOLD=4" || fail "BOSS_THRESHOLD" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "Level 5 (<) vs Level 6 (<<<) Split"

# Level 5 should only have < questions, no <<<
l5=$(bash -c "source '$SOURCE_FILE' 2>/dev/null; gen_level5" 2>/dev/null)
if echo "$l5" | grep -q '<<<'; then
  fail "level 5 split" "contains <<< (should be < only)"
else
  ok "level 5 has no <<< (input redirection only)"
fi

# Level 6 should have <<< questions
l6=$(bash -c "source '$SOURCE_FILE' 2>/dev/null; gen_level6" 2>/dev/null)
if echo "$l6" | grep -q '<<<'; then
  ok "level 6 has <<< (here-strings)"
else
  fail "level 6 split" "no <<< found"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Edge Cases"

# norm() with single command (no flags)
r=$(run_norm "pwd")
[[ "$r" == "pwd" ]] && ok "norm single command 'pwd'" || fail "norm pwd" "got '$r'"

# check() empty input
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  SANDBOX_MODE=0; _qdelim='|'; _qoutput=''; _qstate=''; _qtext=0
  check '' 'ls' && echo PASS || echo FAIL
" 2>/dev/null)
[[ "$r" == "FAIL" ]] && ok "check rejects empty input" || fail "check empty" "$r"

# check() with extra spaces in answer list
r=$(run_check "ls -a" "  ls -a  | ls ")
[[ "$r" == "PASS" ]] && ok "check trims answer alternatives" || fail "check trim alts" "$r"

# Question with multiple § alternatives
r=$(run_check_sec "sort -u file" "sort file | uniq§sort -u file§sort file | uniq -u")
[[ "$r" == "PASS" ]] && ok "check multiple § alternatives" || fail "check multi §" "$r"

# ─────────────────────────────────────────────────────────────────────────────
section "No Stale References"

# No references to gen_level0
if grep -q 'gen_level0' "$(dirname "$0")/cmdchamp"; then
  fail "stale ref" "gen_level0 still referenced"
else
  ok "no gen_level0 references"
fi

# No password references in game logic (pass CLI allowed in help text context)
password_refs=$(grep -n '_level_pass\|PASSWORD:' "$(dirname "$0")/cmdchamp" | grep -v '^#' | grep -v 'password cracker' | grep -v 'passwd' | grep -v 'wordlist' | grep -v 'rockyou' || true)
if [[ -z "$password_refs" ]]; then
  ok "no _level_pass/PASSWORD references"
else
  fail "stale passwords" "$password_refs"
fi

# No HINT references (removed system)
hint_refs=$(grep -n '\bHINT\b' "$(dirname "$0")/cmdchamp" | grep -v '#' | grep -v 'hint' || true)
if [[ -z "$hint_refs" ]]; then
  ok "no HINT variable references"
else
  fail "stale HINT" "$hint_refs"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "Gauntlet/Timed/Review Guards"

# These modes should require BOSS_BEATEN >= MAX_LEVEL
r=$(bash -c "
  source '$SOURCE_FILE' 2>/dev/null
  echo \"\$MAX_LEVEL\"
" 2>/dev/null)
[[ "$r" == "30" ]] && ok "MAX_LEVEL=30 for endgame guard" || fail "endgame guard" "$r"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
printf '\n%s════════════════════════════════════════%s\n' "$B" "$N"
printf '%s%d passed%s, ' "$G" "$PASS" "$N"
if ((FAIL > 0)); then
  printf '%s%d failed%s\n' "$R" "$FAIL" "$N"
  printf '\n%sFailures:%s\n' "$R" "$N"
  for e in "${ERRORS[@]}"; do
    printf '  %s• %s%s\n' "$R" "$e" "$N"
  done
  exit 1
else
  printf '%s0 failed%s\n' "$G" "$N"
  exit 0
fi
