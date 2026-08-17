#!/usr/bin/env bash
# cmdchamp audit.sh — omega-level automated testing for all 30 levels
# Tests: syntax validation, positive self-test, confusable negatives, generic negatives
set -uo pipefail

# ═══════════════════════════════════════════════════════════════════
# BOOTSTRAP: Source cmdchamp functions without triggering main flow
# ═══════════════════════════════════════════════════════════════════
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMDCHAMP="$SCRIPT_DIR/cmdchamp"

# Isolate: cmdchamp computes DATA from XDG_DATA_HOME at load, so point it at a temp
# dir — otherwise the bootstrap eval touches the user's real ~/.local/share/cmdchamp.
export XDG_DATA_HOME; XDG_DATA_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_DATA_HOME"' EXIT

# Extract everything before the main case statement
# This gives us all function defs, variable pools, constants
_bootstrap() {
  # Source everything up to the CLI entrypoint (same approach as test_cmdchamp.sh).
  # -g on the top-level arrays: this eval runs inside a function, where a bare
  # `declare -A MANPAGE=(...)` makes MANPAGE local and it disappears the moment
  # _bootstrap returns. Without it MANPAGE/EXP are not arrays by the time a phase
  # looks at them, and `${MANPAGE[$cmd]:-}` silently becomes an arithmetic
  # subscript — "pwd: unbound variable" instead of a manpage.
  eval "$(sed -e 's/^_tty().*/\_tty() { :; }/' \
              -e 's/^declare -\([aA]\) /declare -g\1 /' \
              -e '/^# ═══ CLI ENTRYPOINT ═══/,$d' \
              "$CMDCHAMP")"

  # Override interactive bits — must come AFTER the eval, or it redefines them
  _tty() { :; }
  _first_run() { :; }
  _load_profile() { PLAYER_NAME="auditor" BOSS_BEATEN=30; }
  _save_profile() { :; }
  _intro() { :; }
  _tutorial() { :; }
  _load_profile
}

# Fill an array with a level's questions (gen_level* writes via nameref, not stdout).
# "chains" selects the gauntlet chain pool (gen_chains), mirroring _pick_q in the game.
_gen() {
  local -n _gq=$2; _gq=()
  if [[ "$1" == chains ]]; then gen_chains _gq 2>/dev/null; else gen_level"$1" _gq 2>/dev/null; fi
}

_bootstrap
trap '((SANDBOX_MODE)) && [[ -d "${SANDBOX_DIR:-}" ]] && rm -rf "$SANDBOX_DIR"' EXIT

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
  ((WARN++)); ((TOTAL++))
  printf '  WARN: %s\n' "$1"
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 1: QUESTION GENERATION VALIDATION
# ═══════════════════════════════════════════════════════════════════
phase1_syntax() {
  printf '\n%s\n' "═══ PHASE 1: Question Syntax Validation ═══"

  for lv in {1..30} chains; do
    local count=0 errors=0

    # Generate 3 times to catch randomization issues
    for round in 1 2 3; do
      local -a raw=()
      _gen "$lv" raw || { _fail "L${lv}: gen_level${lv} crashed (round $round)"; ((errors++)); continue; }
      ((${#raw[@]})) || { _fail "L${lv}: gen_level${lv} produced no questions (round $round)"; ((errors++)); continue; }

      for line in "${raw[@]}"; do
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
        if [[ "$_qprompt" =~ \$\{?[a-z_]+\}? ]] && [[ ! "$_qprompt" =~ '\$' ]]; then
          # Could be intentional (teaching variables), check level
          if ((lv < 7 && lv != 4)); then
            # Levels 1-6 (except 4 which uses $term in grep prompts) shouldn't have bare $var in prompts
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
              exists:*|!exists:*|contains:*:*|lines:*:*|perm:*:*|!perm:*:*) ;;
              *) _fail "L${lv}: bad #state: marker '$_chk' for: ${_qprompt:0:60}" ;;
            esac
          done
        fi

      done
    done

    ((errors == 0)) && _ok
    local _lname; [[ "$lv" == chains ]] && _lname="the gauntlet" || _lname="${LEVEL_NAMES[$lv]}"
    printf '  L%-6s %-22s %4d questions, %d errors\n' "$lv" "$_lname" "$count" "$errors"
  done
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 2: POSITIVE SELF-TEST (correct answers pass own validators)
# ═══════════════════════════════════════════════════════════════════
phase2_positive() {
  printf '\n%s\n' "═══ PHASE 2: Positive Self-Test (sandbox) ═══"

  if ! ((SANDBOX_MODE)); then
    printf '  %s\n' "WARNING: sandbox disabled (bwrap not found) — phase 2 will only validate markers"
  fi
  ((SANDBOX_MODE)) && _sandbox_init

  for lv in {1..30} chains; do
    local tested=0 passed=0 failed=0 skipped=0
    local -a raw=()
    _gen "$lv" raw || continue

    for line in "${raw[@]}"; do
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
            { _sandbox_exec "$ans" 5 &>/dev/null; } 2>/dev/null
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
    done

    if ((tested > 0 || failed > 0)); then
      local _lname; [[ "$lv" == chains ]] && _lname="the gauntlet" || _lname="${LEVEL_NAMES[$lv]}"
      printf '  L%-6s %-22s tested:%d pass:%d fail:%d skip:%d\n' \
        "$lv" "$_lname" "$tested" "$passed" "$failed" "$skipped"
    fi
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

# A mutation the question itself lists as an accepted answer is not a wrong answer —
# it's a declared-correct alternate, so it must not count as a leak. Keeps the mutation
# rules intact for every other question instead of deleting them globally.
_is_listed() {
  local mut=$1 answers=$2 delim=$3 a
  local -a opts; IFS="$delim" read -ra opts <<< "$answers"
  for a in "${opts[@]}"; do
    _trim "$a"; [[ "$mut" == "$REPLY" ]] && return 0
  done
  return 1
}

phase3_confusable() {
  printf '\n%s\n' "═══ PHASE 3: Confusable Negative Testing ═══"

  for lv in {1..30}; do
    local tested=0 caught=0 leaked=0
    local -a raw=()
    _gen "$lv" raw || continue

    for line in "${raw[@]}"; do
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
        _is_listed "$mut" "$answers" "$_qdelim" && continue  # declared-correct alternate, not a leak
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
    done

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

  for lv in {1..30}; do
    local tested=0 caught=0 leaked=0
    local -a raw=()
    _gen "$lv" raw || continue

    # Test first 10 questions per level (enough for generics)
    local qcount=0
    for line in "${raw[@]}"; do
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
    done

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
  for lv in {1..30}; do
    local -a raw=(); local count=0
    _gen "$lv" raw || continue
    for line in "${raw[@]}"; do [[ -n "$line" ]] && ((count++)); done
    if ((count < 5)); then
      _fail "L${lv}: only $count questions, boss needs 5"
    else
      _ok
    fi
  done

  # Check _fnorm() handles edge cases
  printf '  Checking _fnorm() edge cases...\n'
  local n
  _fnorm "ls -la"; n=$REPLY; [[ "$n" =~ ^"ls -a -l"$ ]] && _ok || _fail "_fnorm('ls -la') = '$n', expected 'ls -a -l'"
  _fnorm "grep -rn pattern file"; n=$REPLY; [[ "$n" =~ ^"grep -n -r pattern file"$ ]] && _ok || _fail "_fnorm('grep -rn pattern file') = '$n'"
  _fnorm ""; _ok  # shouldn't crash
  _fnorm "ls"; n=$REPLY; [[ "$n" =~ ^"ls"$ ]] && _ok || _fail "_fnorm('ls') = '$n'"
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 6: SCENARIO SANDBOX VERIFICATION
# Execute each scenario step's correct answer and validate markers
# ═══════════════════════════════════════════════════════════════════
phase6_scenarios() {
  printf '\n%s\n' "═══ PHASE 6: Scenario Verification (sandbox) ═══"

  if ! ((SANDBOX_MODE)); then
    printf '  WARNING: sandbox disabled — scenario steps cannot be verified\n'
    return
  fi

  for ((sc_id=1; sc_id<=SC_TOTAL; sc_id++)); do
    local tested=0 passed=0 failed=0 skipped=0

    # Init sandbox and run setup
    _sandbox_init
    _sc_setup_${sc_id} "$SANDBOX_DIR"

    # Get steps
    local steps
    steps=$(_sc_steps_${sc_id} 2>/dev/null) || { _fail "SC${sc_id}: _sc_steps_${sc_id} crashed"; continue; }

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      _qparse "$line"

      # Skip text-only questions
      ((_qtext)) && { ((skipped++)); continue; }

      # Skip if no markers
      [[ -z "$_qoutput" && -z "$_qstate" ]] && { ((skipped++)); continue; }

      ((tested++))

      # Execute canonical answer in sandbox
      local output="" _sb_rc=0
      { output=$(_sandbox_exec "$_qans" 5 2>"$SANDBOX_DIR/.stderr"); } 2>/dev/null; _sb_rc=$?

      if ((_sb_rc == 127 || _sb_rc == 126)); then
        ((skipped++)); ((tested--)); continue
      fi

      # Validate
      local out_ok=1 state_ok=1
      if [[ -n "$_qoutput" ]]; then
        _sandbox_check_output "$output" "$_qoutput" || out_ok=0
      fi
      if [[ -n "$_qstate" ]]; then
        _sandbox_check_state "$_qstate" || state_ok=0
      fi

      if ((out_ok && state_ok)); then
        ((passed++)); _ok
      else
        ((failed++))
        local reason=""
        ((out_ok)) || reason+="output_fail(got='${output:0:40}',expect='$_qoutput') "
        ((state_ok)) || reason+="state_fail(expect='$_qstate') "
        _fail "SC${sc_id} step: '${_qans:0:50}' [${reason}]"
      fi
    done <<< "$steps"

    printf '  SC%d %-22s tested:%d pass:%d fail:%d skip:%d\n' \
      "$sc_id" "${SC_NAMES[$sc_id]}" "$tested" "$passed" "$failed" "$skipped"
  done
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 8: TAB PANEL COVERAGE
# The Tab panel is the only reference a player gets, and every question is
# meant to be solvable the first time it is seen. So for every canonical
# answer: each command it runs must have a page, and each flag it passes must
# appear on the page the panel actually renders. A flag that only lives in the
# real system manpage is a question the player cannot answer, only guess.
# ═══════════════════════════════════════════════════════════════════
_PANEL_PLACEHOLDER=' cmd cmd1 cmd2 cmd3 c1 c2 cond condition true false '
_PANEL_KW=' if elif while until then do else { ! ( for select case in done fi esac } ) '
_PANEL_WRAP=' sudo doas time nohup env stdbuf setsid nice ionice xargs timeout watch '

_panel_check() {
  local ans=$1 prompt=$2 label=$3
  local -a toks; set -f; read -ra toks <<< "$ans"; set +f
  ((${#toks[@]})) || return 0
  local rx=0; [[ $ans == '~'* ]] && rx=1   # a regex answer: only its command names are literal
  _EBUF=""; explain "$ans" q; _strip_ansi "$_EBUF"; local panel=$REPLY
  _strip_ansi "$prompt"; local pr=$REPLY
  local cp=1 lst=0 qz=0 t tt q body c ok
  local defined=" "                                  # `die() {...}; die x` defines its own command
  for t in "${toks[@]}"; do [[ $t == *'()' ]] && defined+="${t%'()'} "; done

  for t in "${toks[@]}"; do
    tt=$t; while [[ $tt == *';' && $tt != '\;' ]]; do tt=${tt%;}; done
    q=${t//[^\'\"]}                                  # inside a quoted string nothing is
    ((${#q} % 2)) && qz=$((1 - qz))                  # a command and no word is a flag
    ((qz)) && continue
    ((${#q})) && continue
    case "$tt" in for|select|case) lst=1; cp=0; continue ;; do) lst=0; cp=1; continue ;; esac
    ((lst)) && continue                              # the list between `for` and `do` is data
    case "$tt" in
      '|'|'|&'|'&&'|'||'|'&'|''|-exec|-execdir|-ok|-okdir) cp=1; continue ;;
      '<'*|'>'*|'&>'*|'2>'*|'1>'*|'\;') cp=0; continue ;;
    esac
    [[ $_PANEL_KW == *" $tt "* ]] && { cp=1; continue; }
    [[ -n "$tt" && "$pr" == *"$tt"* ]] && { cp=0; continue; }   # the prompt already spells it out
    if ((cp)); then
      case "$tt" in -*|[0-9]*|'{}'|*=*|./*|/*|*[\(\)\{\}\$\[\]\*\;\|]*) continue ;; esac
      cp=0; [[ $_PANEL_WRAP == *" $tt "* ]] && cp=1
      [[ $_PANEL_PLACEHOLDER == *" $tt "* || $defined == *" $tt "* ]] && continue
      [[ $tt == *.* || $tt == */* ]] && continue
      tt=${tt#\~}; tt=${tt#^}
      _canonical_cmd "$tt"
      [[ -n "${MANPAGE[$REPLY]:-}" || -n "${EXP[$REPLY]:-}" ]] && continue
      _fail "$label: no manpage or explanation for '$tt' — panel teaches nothing ($ans)"
      continue
    fi
    ((rx)) && continue
    case "$tt" in *[\(\)\{\}\$\[\]\|]*) continue ;; esac
    case "$tt" in
      --*) [[ "$panel" == *"${tt%%=*}"* ]] || _fail "$label: ${tt%%=*} not on the panel ($ans)" ;;
      -[0-9]*) ;;                                    # a count or a size, not a flag
      -[!-]*)
        [[ "$panel" == *"$tt"* ]] && continue
        body=${tt#-}; ok=1
        if [[ "$body" =~ ^[a-zA-Z]+$ ]]; then        # -tlnp: every letter must be documented
          for ((c=0; c<${#body}; c++)); do [[ "$panel" == *"-${body:c:1}"* ]] || ok=0; done
        elif [[ "$body" =~ ^[a-zA-Z] ]]; then ok=0   # -f2 / -k4,4rn: flag with its value glued on
          [[ "$panel" == *"-${body:0:1}"* ]] && ok=1
        else ok=0; fi
        ((ok)) || _fail "$label: $tt not on the panel ($ans)" ;;
    esac
  done
  return 0
}

phase8_panel_coverage() {
  printf '\n%s\n' "═══ PHASE 8: Tab Panel Coverage ═══"
  local lv si round before=$FAIL checked=0
  local -a pq=()
  for round in 1 2 3; do
    for ((lv=1; lv<=MAX_LEVEL; lv++)); do
      pq=(); _gen "$lv" pq
      for line in "${pq[@]}"; do
        [[ -z $line ]] && continue
        _qparse "$line"; ((checked++)); _panel_check "$_qans" "$_qprompt" "L$lv"
        _ok
      done
    done
    pq=(); _gen chains pq            # the gauntlet chain pool
    for line in "${pq[@]}"; do
      [[ -z $line ]] && continue
      _qparse "$line"; ((checked++)); _panel_check "$_qans" "$_qprompt" "CHAIN"
      _ok
    done
  done
  for ((si=1; si<=SC_TOTAL; si++)); do
    while IFS= read -r line; do
      [[ -z $line ]] && continue
      _qparse "$line"; ((checked++)); _panel_check "$_qans" "$_qprompt" "SC$si"
      _ok
    done < <("_sc_steps_$si" 2>/dev/null)
  done
  printf '  panels checked: %d   gaps: %d\n' "$checked" "$((FAIL - before))"
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 7: SCENARIO WRONG-ANSWER REJECTION
# Similar-but-wrong answers for scenario steps should be rejected
# ═══════════════════════════════════════════════════════════════════
phase7_scenario_negatives() {
  printf '\n%s\n' "═══ PHASE 7: Scenario Wrong-Answer Rejection ═══"

  if ! ((SANDBOX_MODE)); then
    printf '  WARNING: sandbox disabled — skipping scenario negatives\n'
    return
  fi

  for ((sc_id=1; sc_id<=SC_TOTAL; sc_id++)); do
    local tested=0 caught=0 leaked=0

    local steps
    steps=$(_sc_steps_${sc_id} 2>/dev/null) || continue

    # Collect all steps into array for sequential replay
    local -a step_arr=()
    while IFS= read -r line; do [[ -n "$line" ]] && step_arr+=("$line"); done <<< "$steps"

    for ((si=0; si<${#step_arr[@]}; si++)); do
      _qparse "${step_arr[$si]}"

      # Skip text-only
      ((_qtext)) && continue

      local ans="$_qans" answers="$_qanswers" prompt="$_qprompt"

      # Generate confusable mutations. No mutations (plain grep/sed/git answers)
      # must NOT skip the step — the generic wrong-answer loop below still runs.
      local mut_list
      mut_list=$(_mutate "$ans") || mut_list=""

      while IFS= read -r mut; do
        [[ -z "$mut" ]] && continue
        [[ "$mut" == "$ans" ]] && continue
        _is_listed "$mut" "$answers" "$_qdelim" && continue
        ((tested++))

        # Reset sandbox, run setup, then replay all PRIOR steps correctly
        _sandbox_init
        _sc_setup_${sc_id} "$SANDBOX_DIR"
        for ((pi=0; pi<si; pi++)); do
          _qparse "${step_arr[$pi]}"
          { _sandbox_exec "$_qans" 5 &>/dev/null; } 2>/dev/null || true
        done
        # Restore current step's parse state
        _qparse "${step_arr[$si]}"

        if check "$mut" "$answers" 2>/dev/null; then
          ((leaked++))
          _fail "SC${sc_id}: mutation '${mut:0:40}' PASSED for: ${prompt:0:40} [correct: ${ans:0:40}]"
        else
          ((caught++)); _ok
        fi
      done <<< "$mut_list"

      # Also test generic wrong answers
      for wrong in "" "ls" "echo hi" "asdfqwer"; do
        [[ "$wrong" == "$ans" ]] && continue
        ((tested++))
        _sandbox_init
        _sc_setup_${sc_id} "$SANDBOX_DIR"
        for ((pi=0; pi<si; pi++)); do
          _qparse "${step_arr[$pi]}"
          { _sandbox_exec "$_qans" 5 &>/dev/null; } 2>/dev/null || true
        done
        _qparse "${step_arr[$si]}"
        if check "$wrong" "$answers" 2>/dev/null; then
          ((leaked++))
          _fail "SC${sc_id}: generic '$wrong' PASSED for: ${prompt:0:40}"
        else
          ((caught++)); _ok
        fi
      done
    done

    printf '  SC%d %-22s tested:%d caught:%d leaked:%d\n' \
      "$sc_id" "${SC_NAMES[$sc_id]}" "$tested" "$caught" "$leaked"
  done
}

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════
main() {
  printf '%s\n' "╔══════════════════════════════════════════╗"
  printf '%s\n' "║   CmdChamp Omega Audit                   ║"
  printf '%s\n' "║   30 levels × 8 phases                   ║"
  printf '%s\n' "╚══════════════════════════════════════════╝"

  if ! ((SANDBOX_MODE)); then
    printf '\n  ⚠  bwrap NOT INSTALLED — phases 2-4 degrade to text-match only!\n'
    printf '     Install bwrap for full coverage: paru -S bubblewrap\n\n'
  fi

  phase1_syntax
  phase2_positive
  phase3_confusable
  phase4_generic
  phase5_crosscheck
  phase6_scenarios
  phase7_scenario_negatives
  phase8_panel_coverage

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

  if ! ((SANDBOX_MODE)); then
    printf '\n  ⚠  INCOMPLETE: bwrap missing — sandbox execution was disabled\n'
  fi

  ((FAIL > 0)) && return 1 || return 0
}

main "$@"
