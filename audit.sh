#!/usr/bin/env bash
# cmdchamp audit.sh — omega-level automated testing for all 29 levels
# Tests: syntax validation, positive self-test, confusable negatives, generic negatives
set -uo pipefail

# ═══════════════════════════════════════════════════════════════════
# BOOTSTRAP: Source cmdchamp functions without triggering main flow
# ═══════════════════════════════════════════════════════════════════
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMDCHAMP="$SCRIPT_DIR/cmdchamp"

# Extract everything before the main case statement (line 3631)
# This gives us all function defs, variable pools, constants
_bootstrap() {
  # Disable tty check, override interactive bits
  _tty() { :; }
  _first_run() { :; }
  _load_profile() { PLAYER_NAME="auditor" BOSS_BEATEN=28; }
  _save_profile() { :; }
  _intro() { :; }
  _tutorial() { :; }

  # Source everything up to main flow
  eval "$(head -n 3644 "$CMDCHAMP" | tail -n +2)"
  _load_profile
}

_bootstrap

# ═══════════════════════════════════════════════════════════════════
# TEST FRAMEWORK
# ═══════════════════════════════════════════════════════════════════
PASS=0 FAIL=0 WARN=0 TOTAL=0
declare -a FAILURES=()

_ok() { ((PASS++)); ((TOTAL++)); }
_fail() {
  ((FAIL++)); ((TOTAL++))
  FAILURES+=("$1")
  printf '  FAIL: %s\n' "$1"
}
_warn() {
  ((WARN++))
  printf '  WARN: %s\n' "$1"
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 1: QUESTION GENERATION VALIDATION
# ═══════════════════════════════════════════════════════════════════
phase1_syntax() {
  printf '\n%s\n' "═══ PHASE 1: Question Syntax Validation ═══"

  for lv in {0..28}; do
    local count=0 errors=0

    # Generate 3 times to catch randomization issues
    for round in 1 2 3; do
      local raw
      raw=$(gen_level${lv} 2>/dev/null) || { _fail "L${lv}: gen_level${lv} crashed (round $round)"; ((errors++)); continue; }

      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        ((count++))

        # Parse question
        _qparse "$line"

        # Check: prompt not empty
        if [[ -z "$_qprompt" ]]; then
          _fail "L${lv}: empty prompt in: ${line:0:80}..."
          ((errors++)); continue
        fi

        # Check: at least one answer
        if [[ -z "$_qans" ]]; then
          _fail "L${lv}: empty answer for: ${_qprompt:0:60}..."
          ((errors++)); continue
        fi

        # Check: no literal unreplaced variables (common bug: $var not expanded)
        if [[ "$_qprompt" =~ \$\{?[a-z_]+\}? ]] && [[ ! "$_qprompt" =~ \\\$ ]] && [[ ! "$_qprompt" =~ '\$' ]]; then
          # Could be intentional (teaching variables), check level
          if ((lv < 7 && lv != 4)); then
            # Levels 0-6 (except 4 which uses <<<) shouldn't have bare $var in prompts
            local _match="${BASH_REMATCH[0]}"
            # Exclude known variable teaching contexts
            case "$_qprompt" in
              *'$USER'*|*'$HOME'*|*'$SHELL'*|*'$RANDOM'*|*'$HOSTNAME'*) ;;
              *) _warn "L${lv}: possible unresolved var '${_match}' in prompt: ${_qprompt:0:60}" ;;
            esac
          fi
        fi

        # Check: no double delimiters (||, §§ without content between)
        if [[ "$line" =~ \|{3,} ]] || [[ "$line" =~ §§ ]]; then
          _fail "L${lv}: double/triple delimiter in: ${line:0:80}"
          ((errors++))
        fi

        # Check: #output: marker is well-formed if present
        if [[ -n "$_qoutput" ]]; then
          case "$_qoutput" in
            \~*) ;; # regex - ok
            @*) [[ "${_qoutput:1}" =~ ^[0-9]+$ ]] || _fail "L${lv}: bad @linecount: $_qoutput for: ${_qprompt:0:60}" ;;
            \*) ;; # any output - ok
            *) ;; # exact match - ok
          esac
        fi

        # Check: #state: marker is well-formed if present
        if [[ -n "$_qstate" ]]; then
          IFS=',' read -ra _checks <<< "$_qstate"
          for _chk in "${_checks[@]}"; do
            case "$_chk" in
              exists:*|!exists:*|contains:*:*|lines:*:*) ;;
              *) _fail "L${lv}: bad #state: marker '$_chk' for: ${_qprompt:0:60}" ;;
            esac
          done
        fi

      done <<< "$raw"
    done

    ((errors == 0)) && _ok
    printf '  L%02d %-22s %4d questions, %d errors\n' "$lv" "${LEVEL_NAMES[$lv]}" "$count" "$errors"
  done
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 2: POSITIVE SELF-TEST (correct answers pass own validators)
# ═══════════════════════════════════════════════════════════════════
phase2_positive() {
  printf '\n%s\n' "═══ PHASE 2: Positive Self-Test (sandbox) ═══"

  ((SANDBOX_MODE)) && _sandbox_init

  for lv in {0..28}; do
    local tested=0 passed=0 failed=0 skipped=0
    local raw
    raw=$(gen_level${lv} 2>/dev/null) || continue

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      _qparse "$line"

      # Skip text-match-only questions (pager commands etc)
      ((_qtext)) && { ((skipped++)); continue; }

      # Skip questions without sandbox markers
      [[ -z "$_qoutput" && -z "$_qstate" ]] && { ((skipped++)); continue; }

      ((tested++))

      # Reset sandbox before each test
      ((SANDBOX_MODE)) && _sandbox_reset

      # Execute the canonical correct answer
      local ans="$_qans"
      local output="" _sb_rc=0
      if ((SANDBOX_MODE)); then
        { output=$(_sandbox_exec "$ans" 5 2>"$SANDBOX_DIR/.stderr"); } 2>/dev/null; _sb_rc=$?
      fi

      # Skip if command not found (tools not installed)
      if ((_sb_rc == 127 || _sb_rc == 126)); then
        ((skipped++)); ((tested--)); continue
      fi

      # Track destructive
      _is_destructive "$ans" && _sandbox_reset 2>/dev/null

      # Validate output
      local out_ok=1 state_ok=1
      if [[ -n "$_qoutput" ]]; then
        _sandbox_check_output "$output" "$_qoutput" || out_ok=0
      fi
      if [[ -n "$_qstate" ]]; then
        # Re-execute for state check (destructive commands may have reset)
        if ((_sb_rc != 127 && _sb_rc != 126)); then
          # For state checks, need to re-execute after reset
          if _is_destructive "$ans"; then
            _sandbox_reset 2>/dev/null
            { _sandbox_exec "$ans" 5 2>/dev/null; } 2>/dev/null
          fi
          _sandbox_check_state "$_qstate" || state_ok=0
        fi
      fi

      if ((out_ok && state_ok)); then
        ((passed++)); _ok
      else
        ((failed++))
        local reason=""
        ((out_ok)) || reason+="output_fail "
        ((state_ok)) || reason+="state_fail "
        _fail "L${lv}: answer '${ans:0:60}' fails own validator [${reason}] for: ${_qprompt:0:50}"
      fi
    done <<< "$raw"

    printf '  L%02d %-22s tested:%d pass:%d fail:%d skip:%d\n' \
      "$lv" "${LEVEL_NAMES[$lv]}" "$tested" "$passed" "$failed" "$skipped"
  done
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 3: CONFUSABLE NEGATIVE TESTING
# Smart mutations — test that similar-but-wrong answers are rejected
# ═══════════════════════════════════════════════════════════════════

# Generate mutations of a correct answer
_mutate() {
  local ans="$1"
  local -a mutations=()

  # Redirect mutations: > ↔ >>
  if [[ "$ans" =~ [^2\&]'> ' ]]; then
    mutations+=("${ans/> />> }")
  fi
  if [[ "$ans" =~ '>> ' ]]; then
    mutations+=("${ans/>> /> }")
  fi

  # Input redirect: < ↔ <<<
  # Check for standalone < (not part of <<< or <<)
  local _has_stdin=0
  [[ "$ans" =~ [[:space:]]'<'[[:space:]] ]] && _has_stdin=1
  if ((_has_stdin)); then
    mutations+=("${ans/ < / <<< }")
  fi
  if [[ "$ans" == *'<<<'* ]]; then
    mutations+=("${ans/<<</<}")
  fi

  # Error redirect: 2> ↔ > ↔ &> ↔ 2>&1
  if [[ "$ans" =~ '2> ' ]] && [[ ! "$ans" =~ '2>&1' ]]; then
    mutations+=("${ans/2> /> }")
    mutations+=("${ans/2> /&> }")
  fi
  if [[ "$ans" =~ '&> ' ]]; then
    mutations+=("${ans/&> /2> }")
    mutations+=("${ans/&> /> }")
  fi

  # Logic: && ↔ || ↔ ;
  if [[ "$ans" =~ ' && ' ]]; then
    mutations+=("${ans/ && / || }")
    mutations+=("${ans/ && / ; }")
  fi
  if [[ "$ans" =~ ' || ' ]]; then
    mutations+=("${ans/ || / && }")
    mutations+=("${ans/ || / ; }")
  fi

  # head ↔ tail
  if [[ "$ans" =~ ^head[[:space:]] ]]; then
    mutations+=("${ans/head/tail}")
  fi
  if [[ "$ans" =~ ^tail[[:space:]] ]]; then
    mutations+=("${ans/tail/head}")
  fi

  # grep flag mutations
  if [[ "$ans" =~ 'grep -i ' ]]; then
    mutations+=("${ans/grep -i /grep }")
    mutations+=("${ans/grep -i /grep -v }")
  fi
  if [[ "$ans" =~ 'grep -v ' ]]; then
    mutations+=("${ans/grep -v /grep }")
    mutations+=("${ans/grep -v /grep -i }")
  fi
  if [[ "$ans" =~ 'grep -c ' ]]; then
    mutations+=("${ans/grep -c /grep }")
  fi
  if [[ "$ans" =~ 'grep -r ' ]]; then
    mutations+=("${ans/grep -r /grep }")
  fi

  # wc flag mutations
  if [[ "$ans" =~ 'wc -l' ]]; then
    mutations+=("${ans/wc -l/wc -w}")
    mutations+=("${ans/wc -l/wc -c}")
  fi
  if [[ "$ans" =~ 'wc -w' ]]; then
    mutations+=("${ans/wc -w/wc -l}")
    mutations+=("${ans/wc -w/wc -c}")
  fi
  if [[ "$ans" =~ 'wc -c' ]]; then
    mutations+=("${ans/wc -c/wc -l}")
    mutations+=("${ans/wc -c/wc -w}")
  fi

  # sort mutations
  if [[ "$ans" =~ 'sort -n ' ]]; then
    mutations+=("${ans/sort -n /sort }")
    mutations+=("${ans/sort -n /sort -r }")
  fi
  if [[ "$ans" =~ 'sort -r ' ]]; then
    mutations+=("${ans/sort -r /sort }")
    mutations+=("${ans/sort -r /sort -n }")
  fi
  if [[ "$ans" == "sort "* ]] && [[ ! "$ans" =~ 'sort -' ]]; then
    mutations+=("${ans/sort /sort -r }")
  fi

  # chmod mutations
  if [[ "$ans" =~ 'chmod +x' ]]; then
    mutations+=("${ans/chmod +x/chmod -x}")
    mutations+=("${ans/chmod +x/chmod 644}")
  fi
  if [[ "$ans" =~ 'chmod 755' ]]; then
    mutations+=("${ans/chmod 755/chmod 644}")
  fi
  if [[ "$ans" =~ 'chmod 644' ]]; then
    mutations+=("${ans/chmod 644/chmod 755}")
  fi

  # cp ↔ mv ↔ ln
  if [[ "$ans" =~ ^'cp ' ]]; then
    mutations+=("${ans/cp /mv }")
  fi
  if [[ "$ans" =~ ^'mv ' ]]; then
    mutations+=("${ans/mv /cp }")
  fi

  # cat ↔ less ↔ head ↔ tail (for file display)
  if [[ "$ans" =~ ^'cat ' ]] && [[ ! "$ans" =~ '-n' ]]; then
    mutations+=("${ans/cat /head -5 }")
  fi

  # test flags: -f ↔ -d ↔ -e ↔ -r ↔ -w ↔ -x
  if [[ "$ans" =~ '-f ' ]]; then
    mutations+=("${ans/-f /-d }")
  fi
  if [[ "$ans" =~ '-d ' ]] && [[ ! "$ans" =~ '-fd' ]]; then
    mutations+=("${ans/-d /-f }")
  fi

  # nmap scan types
  if [[ "$ans" =~ '-sV' ]]; then
    mutations+=("${ans/-sV/-sC}")
    mutations+=("${ans/-sV/-sS}")
  fi
  if [[ "$ans" =~ '-sS ' ]]; then
    mutations+=("${ans/-sS/-sT}")
  fi

  # hashcat mode mutations
  if [[ "$ans" =~ '-m 0 ' ]]; then
    mutations+=("${ans/-m 0 /-m 100 }")
    mutations+=("${ans/-m 0 /-m 1000 }")
  fi

  # tar flags: czf ↔ xzf ↔ tzf
  if [[ "$ans" =~ 'tar czf' ]]; then
    mutations+=("${ans/tar czf/tar xzf}")
  fi
  if [[ "$ans" =~ 'tar xzf' ]]; then
    mutations+=("${ans/tar xzf/tar czf}")
  fi

  # git: add ↔ commit ↔ push
  if [[ "$ans" =~ 'git add' ]]; then
    mutations+=("${ans/git add/git commit}")
  fi
  if [[ "$ans" =~ 'git push' ]]; then
    mutations+=("${ans/git push/git pull}")
  fi

  # bg ↔ fg
  if [[ "$ans" =~ ^'fg' ]]; then
    mutations+=("${ans/fg/bg}")
  fi
  if [[ "$ans" =~ ^'bg' ]]; then
    mutations+=("${ans/bg/fg}")
  fi

  # ssh tunnel: -L ↔ -R ↔ -D
  if [[ "$ans" =~ 'ssh -L' ]]; then
    mutations+=("${ans/ssh -L/ssh -R}")
  fi
  if [[ "$ans" =~ 'ssh -R' ]]; then
    mutations+=("${ans/ssh -R/ssh -L}")
  fi
  if [[ "$ans" =~ 'ssh -D' ]]; then
    mutations+=("${ans/ssh -D/ssh -L}")
  fi

  # find -name ↔ -type ↔ -size
  if [[ "$ans" =~ '-name ' ]] && [[ "$ans" =~ ^find ]]; then
    mutations+=("${ans/-name /-iname }")
  fi

  # tr case: a-z A-Z ↔ A-Z a-z
  if [[ "$ans" =~ 'tr a-z A-Z' ]]; then
    mutations+=("${ans/tr a-z A-Z/tr A-Z a-z}")
  fi
  if [[ "$ans" =~ 'tr A-Z a-z' ]]; then
    mutations+=("${ans/tr A-Z a-z/tr a-z A-Z}")
  fi

  # rev vs cat (L4)
  if [[ "$ans" =~ ^'rev ' ]]; then
    mutations+=("${ans/rev /cat }")
  fi

  # kill vs disown
  if [[ "$ans" =~ ^'kill ' ]]; then
    mutations+=("${ans/kill /disown }")
  fi
  if [[ "$ans" =~ ^'disown ' ]]; then
    mutations+=("${ans/disown /kill }")
  fi

  # echo $$ ↔ $? ↔ $! ↔ $# ↔ $@
  if [[ "$ans" == 'echo $$' ]]; then
    mutations+=('echo $?' 'echo $!')
  fi
  if [[ "$ans" == 'echo $?' ]]; then
    mutations+=('echo $$' 'echo $!')
  fi
  if [[ "$ans" == 'echo $!' ]]; then
    mutations+=('echo $$' 'echo $?')
  fi
  if [[ "$ans" == 'echo $#' ]]; then
    mutations+=('echo $@' 'echo $0')
  fi
  if [[ "$ans" == 'echo $@' ]] || [[ "$ans" == 'echo "$@"' ]]; then
    mutations+=('echo $#' 'echo $0')
  fi

  # systemctl verbs
  if [[ "$ans" =~ 'systemctl start' ]]; then
    mutations+=("${ans/systemctl start/systemctl stop}")
    mutations+=("${ans/systemctl start/systemctl restart}")
  fi
  if [[ "$ans" =~ 'systemctl enable' ]]; then
    mutations+=("${ans/systemctl enable/systemctl disable}")
  fi

  # tmux split: -h ↔ -v
  if [[ "$ans" =~ 'split-window -h' ]]; then
    mutations+=("${ans/-h/-v}")
  fi
  if [[ "$ans" =~ 'split-window -v' ]]; then
    mutations+=("${ans/-v/-h}")
  fi

  # airmon start ↔ stop
  if [[ "$ans" =~ 'airmon-ng start' ]]; then
    mutations+=("${ans/start/stop}")
  fi

  printf '%s\n' "${mutations[@]}"
}

phase3_confusable() {
  printf '\n%s\n' "═══ PHASE 3: Confusable Negative Testing ═══"

  for lv in {0..28}; do
    local tested=0 caught=0 leaked=0
    local raw
    raw=$(gen_level${lv} 2>/dev/null) || continue

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      _qparse "$line"
      local ans="$_qans"
      local answers="$_qanswers"

      # Skip text-match questions with #text: (pager commands)
      ((_qtext)) && continue

      # Generate confusable mutations
      local mut_list
      mut_list=$(_mutate "$ans") || continue
      [[ -z "$mut_list" ]] && continue

      while IFS= read -r mut; do
        [[ -z "$mut" ]] && continue
        [[ "$mut" == "$ans" ]] && continue  # skip if mutation produced same answer
        ((tested++))

        # Reset sandbox state
        ((SANDBOX_MODE)) && _sandbox_reset 2>/dev/null

        # Check if mutated answer passes (it shouldn't)
        if check "$mut" "$answers" 2>/dev/null; then
          ((leaked++))
          _fail "L${lv}: mutation '${mut:0:50}' PASSED (should fail) for: ${_qprompt:0:50} [correct: ${ans:0:50}]"
        else
          ((caught++)); _ok
        fi
      done <<< "$mut_list"
    done <<< "$raw"

    printf '  L%02d %-22s tested:%d caught:%d leaked:%d\n' \
      "$lv" "${LEVEL_NAMES[$lv]}" "$tested" "$caught" "$leaked"
  done
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 4: GENERIC NEGATIVE TESTING
# Obvious wrong answers should always be rejected
# ═══════════════════════════════════════════════════════════════════
phase4_generic() {
  printf '\n%s\n' "═══ PHASE 4: Generic Negative Testing ═══"

  local generics=("" "ls" "echo hi" "asdfqwer" "rm -rf /")

  for lv in {0..28}; do
    local tested=0 caught=0 leaked=0
    local raw
    raw=$(gen_level${lv} 2>/dev/null) || continue

    # Test first 10 questions per level (enough for generics)
    local qcount=0
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      ((qcount++ >= 10)) && break

      _qparse "$line"

      # Skip text-match questions
      ((_qtext)) && continue

      for wrong in "${generics[@]}"; do
        # Skip if the wrong answer happens to be the right one
        [[ "$wrong" == "$_qans" ]] && continue
        ((tested++))

        ((SANDBOX_MODE)) && _sandbox_reset 2>/dev/null

        if check "$wrong" "$_qanswers" 2>/dev/null; then
          ((leaked++))
          _fail "L${lv}: generic '${wrong}' PASSED for: ${_qprompt:0:50} [correct: ${_qans:0:50}]"
        else
          ((caught++)); _ok
        fi
      done
    done <<< "$raw"

    printf '  L%02d %-22s tested:%d caught:%d leaked:%d\n' \
      "$lv" "${LEVEL_NAMES[$lv]}" "$tested" "$caught" "$leaked"
  done
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 5: CROSS-CHECKS
# ═══════════════════════════════════════════════════════════════════
phase5_crosscheck() {
  printf '\n%s\n' "═══ PHASE 5: Cross-Checks ═══"

  # Check sandbox files exist
  printf '  Checking sandbox file references...\n'
  ((SANDBOX_MODE)) && _sandbox_init

  local sb_files=(server.log app.log logs/access.log logs/error.log notes.txt todo.txt
    data.csv users.csv config.ini settings.yaml backup.sh deploy.sh
    main.py src/utils.py src/test/test_utils.py data/export.json)

  for f in "${sb_files[@]}"; do
    if [[ ! -f "$SANDBOX_DIR/$f" ]]; then
      _fail "sandbox missing: $f"
    else
      _ok
    fi
  done

  # Check boss can find 5 unseen questions per level
  printf '  Checking boss question availability...\n'
  for lv in {0..28}; do
    local raw count=0
    raw=$(gen_level${lv} 2>/dev/null) || continue
    while IFS= read -r line; do [[ -n "$line" ]] && ((count++)); done <<< "$raw"
    if ((count < 5)); then
      _fail "L${lv}: only $count questions, boss needs 5"
    else
      _ok
    fi
  done

  # Check norm() handles edge cases
  printf '  Checking norm() edge cases...\n'
  local n
  n=$(norm "ls -la") ; [[ "$n" =~ ^"ls -a -l"$ ]] && _ok || _fail "norm('ls -la') = '$n', expected 'ls -a -l'"
  n=$(norm "grep -rn pattern file") ; [[ "$n" =~ ^"grep -n -r pattern file"$ ]] && _ok || _fail "norm('grep -rn pattern file') = '$n'"
  n=$(norm "") ; _ok  # shouldn't crash
  n=$(norm "ls") ; [[ "$n" =~ ^"ls"$ ]] && _ok || _fail "norm('ls') = '$n'"
}

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════
main() {
  printf '%s\n' "╔══════════════════════════════════════════╗"
  printf '%s\n' "║   CmdChamp Omega Audit                   ║"
  printf '%s\n' "║   29 levels × 5 phases                   ║"
  printf '%s\n' "╚══════════════════════════════════════════╝"

  phase1_syntax
  phase2_positive
  phase3_confusable
  phase4_generic
  phase5_crosscheck

  printf '\n%s\n' "═══════════════════════════════════════════"
  printf '  TOTAL: %d tests  PASS: %d  FAIL: %d  WARN: %d\n' "$TOTAL" "$PASS" "$FAIL" "$WARN"
  printf '%s\n' "═══════════════════════════════════════════"

  if ((FAIL > 0)); then
    printf '\n%s\n' "═══ ALL FAILURES ═══"
    for f in "${FAILURES[@]}"; do
      printf '  ✗ %s\n' "$f"
    done
    printf '\n'
  fi

  ((FAIL > 0)) && return 1 || return 0
}

main "$@"
