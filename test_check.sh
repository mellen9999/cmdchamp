#!/bin/bash
# Basic test harness for cmdchamp answer matching
# Tests check(), _fnorm(), and _qparse() in isolation
set -uo pipefail

PASS=0 FAIL=0 TOTAL=0

# Stub out everything except the functions we need
DATA="/tmp/cmdchamp-test-$$"
mkdir -p "$DATA"
SANDBOX_MODE=0
_qtext=0 _qoutput="" _qstate="" _qdelim='|'
trap 'rm -rf "$DATA"' EXIT

# Extract functions by sourcing in a subshell that stubs the main script
SRC="$(dirname "$0")/cmdchamp"
[[ -f "$SRC" ]] || { echo "ERROR: cmdchamp not found"; exit 1; }

# Extract function bodies using awk (handles nested braces)
_extract() {
  awk -v fn="$1" '
    $0 ~ "^"fn"\\(\\)" { p=1; d=0 }
    p { print; for(i=1;i<=length($0);i++){c=substr($0,i,1); if(c=="{")d++; if(c=="}")d--}; if(d==0&&NR>1)exit }
  ' "$SRC"
}
eval "$(_extract _fnorm)"
eval "$(_extract _qparse)"
eval "$(_extract check)"

ok()   { PASS=$((PASS + 1)); }
fail() { FAIL=$((FAIL + 1)); }

assert_pass() {
  local desc=$1 input=$2 answers=$3
  TOTAL=$((TOTAL + 1))
  if check "$input" "$answers"; then ok
  else fail; printf '  FAIL: %s\n    input=%q answers=%q\n' "$desc" "$input" "$answers"
  fi
}

assert_fail() {
  local desc=$1 input=$2 answers=$3
  TOTAL=$((TOTAL + 1))
  if check "$input" "$answers"; then
    fail; printf '  FAIL (should reject): %s\n    input=%q answers=%q\n' "$desc" "$input" "$answers"
  else ok
  fi
}

assert_eq() {
  local desc=$1 got=$2 want=$3
  TOTAL=$((TOTAL + 1))
  if [[ "$got" == "$want" ]]; then ok
  else fail; printf '  FAIL: %s\n    want=%q got=%q\n' "$desc" "$want" "$got"
  fi
}

echo "=== _fnorm tests ==="

_fnorm "grep -ri pattern file";  assert_eq "flag split+sort"  "$REPLY" "grep -i -r pattern file"
_fnorm "ls -la /tmp";            assert_eq "split -la"        "$REPLY" "ls -a -l /tmp"
_fnorm "ls --all -l";            assert_eq "long flag order"  "$REPLY" "ls --all -l"
_fnorm "";                       assert_eq "empty input"      "$REPLY" ""
_fnorm "cat file";               assert_eq "no flags"         "$REPLY" "cat file"

echo "=== _qparse tests ==="

_qparse "What is pwd|pwd|print working directory"
assert_eq "basic prompt"    "$_qprompt" "What is pwd"
assert_eq "basic answer"    "$_qans"    "pwd"
assert_eq "basic delim"     "$_qdelim"  "|"

_qparse "Pipe question§cmd1 | cmd2§alt answer"
assert_eq "section prompt"  "$_qprompt" "Pipe question"
assert_eq "section answer"  "$_qans"    "cmd1 | cmd2"
assert_eq "section delim"   "$_qdelim"  "§"

_qparse "Sandbox q|answer#output:expected"
assert_eq "output marker"   "$_qoutput" "expected"

_qparse "Sandbox q|answer#state:file=3"
assert_eq "state marker"    "$_qstate"  "file=3"

_qparse "Text only|answer#text:"
assert_eq "text marker"     "$_qtext"   "1"

echo "=== check() exact match ==="

assert_pass "exact match"       "ls -la"  "ls -la"
assert_pass "multiple answers"  "pwd"     "pwd|print working directory"
assert_pass "second answer"     "echo hi" "printf hi|echo hi"
assert_fail "wrong answer"      "cat"     "ls -la"
assert_fail "empty input"       ""        "ls -la"

echo "=== check() flag normalization ==="

assert_pass "flag reorder -la/-al"  "ls -al"  "ls -la"
assert_pass "flag reorder -ri/-ir"  "grep -ir pat file"  "grep -ri pat file"
assert_pass "split combined flags"  "ls -l -a"  "ls -la"
assert_pass "both normalized"       "sort -rn file"  "sort -nr file"
assert_fail "wrong flags"           "ls -r"  "ls -la"

echo "=== check() regex patterns ==="

assert_pass "regex basic"    "grep -n error log.txt"   "~grep.*error"
assert_pass "regex flexible" "find / -name '*.log'"    "~find.+-name"
assert_fail "regex no match" "cat file"                "~grep.*error"

echo "=== check() whitespace handling ==="

assert_pass "leading space"   "  ls -la"  "ls -la"
assert_pass "trailing space"  "ls -la  "  "ls -la"
assert_pass "both spaces"     "  ls -la  " "ls -la"

echo "=== check() § delimiter ==="

_qdelim='§'
assert_pass "pipe in answer"  "cat file | grep err"  "cat file | grep err§grep err file"
assert_pass "alt with pipe"   "grep err file"        "cat file | grep err§grep err file"
_qdelim='|'

echo ""
printf '=== Results: %d/%d passed' "$PASS" "$TOTAL"
((FAIL)) && printf ', %d FAILED' "$FAIL"
printf ' ===\n'

((FAIL)) && exit 1
exit 0
