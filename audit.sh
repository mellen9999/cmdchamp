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
    # The gauntlet derives #output against a randomised tree and grades against that SAME tree
    # (in-game, SANDBOX_DIR is pointed at it). Mirror that here or derive!=grade for chains.
    local _ch_save_sd="" _ch_tree=""
    if [[ "$lv" == chains ]] && ((SANDBOX_MODE)); then
      if _ch_tree=$(mktemp -d) && _gen_gauntlet_files "$_ch_tree" 2>/dev/null; then
        _GAUNTLET_DIR=$_ch_tree; _ch_save_sd=$SANDBOX_DIR; SANDBOX_DIR=$_ch_tree
      fi
    fi
    _gen "$lv" raw || continue

    for line in "${raw[@]}"; do
      [[ -z "$line" ]] && continue
      _qparse "$line"

      # Skip text-match-only questions (pager commands etc)
      ((_qtext)) && { ((skipped++)); continue; }

      # Skip questions without sandbox markers
      [[ -z "$_qoutput" && -z "$_qstate" ]] && { ((skipped++)); continue; }

      ((tested++))

      # Reset sandbox before each test. Chains are read-only and share ONE tree for the whole
      # level — resetting to pristine would clobber the randomised fixtures their #outputs
      # were derived from.
      [[ "$lv" != chains ]] && ((SANDBOX_MODE)) && _sandbox_reset

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

    if [[ "$lv" == chains && -n "$_ch_tree" ]]; then
      SANDBOX_DIR=$_ch_save_sd; _GAUNTLET_DIR=""; rm -rf "$_ch_tree"
    fi

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

  # Shell syntax is not a command and carries no flags, so both loops below skip
  # it — this is the only thing standing between a player and an answer like
  # `total=$(sort f | wc -l)` with nothing on the panel but sort's page.
  # Detected here independently of _syn_legend, so a hole in either one shows up.
  local bare="" qz2=0 dq2=0 ch ci
  for ((ci=0; ci<${#ans}; ci++)); do ch=${ans:ci:1}   # keep only what the shell expands:
    if ((qz2)); then [[ $ch == "'" ]] && qz2=0; continue; fi   # '...' is literal, "..."
    [[ $ch == '\' ]] && { ((ci++)); continue; }                # expands, \$ does not, and
    case "$ch" in '"') dq2=$((1 - dq2)); continue ;;           # an apostrophe inside "..."
      "'") ((dq2)) || qz2=1; continue ;; esac                  # opens nothing
    bare+=$ch
  done
  [[ $bare == *'$(('* ]] && { [[ "$panel" == *'$((expr))'* ]] || _fail "$label: \$(( not on the panel ($ans)"; }
  local rest=${bare//'$(('/}                       # so a bare $(( is not read as $(
  [[ $rest == *'$('*  ]] && { [[ "$panel" == *'$(cmd)'* ]] || _fail "$label: \$( not on the panel ($ans)"; }
  [[ $bare == *'<('*  ]] && { [[ "$panel" == *'<(cmd)'* ]] || _fail "$label: <( not on the panel ($ans)"; }
  [[ $bare == *'>('*  ]] && { [[ "$panel" == *'>(cmd)'* ]] || _fail "$label: >( not on the panel ($ans)"; }
  [[ $bare == *'`'*   ]] && { [[ "$panel" == *'`cmd`'* ]] || _fail "$label: backtick not on the panel ($ans)"; }
  [[ $bare == *'${'*  ]] && { [[ "$panel" == *'${'* ]]    || _fail "$label: \${ not on the panel ($ans)"; }
  local a_cp=1 a_t; local -a a_toks
  set -f; read -ra a_toks <<< "$bare"; set +f
  for a_t in "${a_toks[@]}"; do
    case "$a_t" in '|'|'|&'|'&&'|'||'|';'|'&'|export|declare|local|readonly|typeset|env) a_cp=1; continue ;; esac
    if ((a_cp)) && [[ $a_t == [A-Za-z_]*=* && ${a_t%%=*} =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      case ${a_t#*=} in
        '('*) [[ "$panel" == *'arr=(a b c)'* ]] || _fail "$label: array assignment not on the panel ($ans)" ;;
        *)    [[ "$panel" == *'var=value'* ]]   || _fail "$label: assignment not on the panel ($ans)" ;;
      esac
      continue
    fi
    a_cp=0
  done
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
# PHASE 9: MANPAGE CARD GRID
# Every card is hand-spaced, so a one-space slip is invisible in the diff and
# obvious on screen — a right column that sits one off makes the whole panel
# look broken. The grid is: flag at col 2, its text at col 12, second flag at
# col 35, its text at col 45. Rows that cannot reach a column (a long flag, or
# left text that runs past col 33) are free-form and exempt — the rule only
# binds a row that had the room and missed it.
# ═══════════════════════════════════════════════════════════════════
_grid_cols() {                    # _COLS=(gapstart:tokenstart ...), leading indent excluded
  local s=$1; local len=${#s} i=2 j
  _COLS=()
  while ((i < len)); do
    if [[ ${s:i:2} == '  ' ]]; then
      j=$i; while ((j < len)) && [[ ${s:j:1} == ' ' ]]; do ((j++)); done
      ((j < len)) && _COLS+=("$i:$j")
      i=$j
    else ((i++)); fi
  done
}

phase9_manpage_grid() {
  printf '\n%s\n' "═══ PHASE 9: Manpage Card Grid ═══"
  local cmd row line c gs tok ags atok k rows=0 before=$FAIL
  local -a _COLS
  for cmd in "${!MANPAGE[@]}"; do
    while IFS= read -r row; do
      _strip_ansi "$row"; line=$REPLY
      [[ $line == '  '[!' ']* ]] || continue          # option rows are indented two spaces
      _grid_cols "$line"
      ((${#_COLS[@]})) || continue
      [[ ${_COLS[0]#*:} == 12 ]] || continue          # left text off col 12: a long flag, free-form
      [[ ${line:12:1} == '-' ]] && continue           # col 12 is itself a flag: a compact flag list
      gs=""; for ((k=1; k<${#_COLS[@]}; k++)); do
        tok=${_COLS[k]#*:}
        [[ ${line:tok:1} == '-' ]] && { gs=${_COLS[k]%:*}; break; }
      done
      [[ -n $gs ]] || continue                        # single-column row
      ((rows++))
      if ((gs <= 33)) && ((tok != 35)); then
        _fail "manpage $cmd: right column at $tok, expected 35 — |$line|"; else _ok
      fi
      ((tok == 35)) || continue
      ((k+1 < ${#_COLS[@]})) || continue
      ags=${_COLS[k+1]%:*}; atok=${_COLS[k+1]#*:}
      if ((ags <= 43)) && ((atok != 45)); then
        _fail "manpage $cmd: right text at $atok, expected 45 — |$line|"; else _ok
      fi
    done <<< "${MANPAGE[$cmd]}"
  done
  printf '  grid rows checked: %d   misaligned: %d\n' "$rows" "$((FAIL - before))"
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 10: RENDER SMOKE
# Draws every static screen in a clean subshell and demands two things of it:
# an EMPTY stderr, and no line wider than 79 visible columns.
#
# This is the phase that would have caught the circular nameref in `learn` —
# `_play_learn` passed its own nameref name down, so bash fell back to scalar
# expansion, sprayed warnings mid-render and evaluated a flag token as
# arithmetic. Every other phase here checks the question pool; none of them
# ever drew a screen, so a fully broken renderer shipped twice.
#
# Not covered (and deliberately): the in-game loops (run/challenge/daily/
# scenario) need a live sandbox and a keyboard, and the manpage panels have
# their own phases (8, 9).
# ═══════════════════════════════════════════════════════════════════
_RENDER_SRC="$XDG_DATA_HOME/render_src.sh"
_RENDER_RUN="$XDG_DATA_HOME/render_run.sh"

_render_prepare() {
  sed -e 's/^_tty().*/\_tty() { :; }/' \
      -e '/^# ═══ CLI ENTRYPOINT ═══/,$d' \
      "$CMDCHAMP" > "$_RENDER_SRC"
  printf '%s\n' 'SANDBOX_MODE=0' >> "$_RENDER_SRC"
  # The stubs stand in for a terminal and a human: no blocking reads, no sleeps,
  # and a selector that prints what it was handed instead of waiting on a keypress.
  cat > "$_RENDER_RUN" <<'RUNNER'
source "$1"
PLAYER_NAME=auditor BOSS_BEATEN=30 LVL=30 QI=0 streak=0 qi=1 TOT=10
_pause() { :; }
sleep() { :; }
# SEL_ONCE=1 lets the FIRST selection through (picking row 0) before quitting, so a
# menu's own dispatch runs once — that is the code path where `learn` handed its
# nameref name to the detail renderer and bash silently fell back to scalar expansion.
_sel() { printf '%s\n' "$1" "${@:2}"; REPLY=0
  [[ "${SEL_ONCE:-0}" == 1 ]] && { SEL_ONCE=0; return 0; }
  return 1; }
_PLAY_PLANTED=("${_PLAY_FLAG_ORDER[@]}"); _PLAY_FLAG_TOTAL=${#_PLAY_PLANTED[@]}
declare -A _flags=(); _PLAY_HINT_SEEN=()
eval "$2"
RUNNER
}

# One screen. Fails loud on a non-empty stderr, a hard error exit, a timeout,
# an over-wide line, or a screen that drew nothing at all.
_render_check() {
  local name=$1 code=$2 tier=${3:-} out err rc line n=0
  [[ -n "$tier" ]] && name="$name [${tier%%=*}]"
  out=$(env ${tier:+"$tier"} COLUMNS=79 timeout 20 bash "$_RENDER_RUN" "$_RENDER_SRC" "$code" 2>"$XDG_DATA_HOME/render_err" </dev/null)
  rc=$?
  err=$(<"$XDG_DATA_HOME/render_err")
  ((rc == 124)) && { _fail "render $name: timed out"; return; }
  ((rc > 1))    && { _fail "render $name: exit $rc"; return; }
  [[ -n "$err" ]] && { _fail "render $name: stderr — ${err%%$'\n'*}"; return; }
  [[ -n "${out//[[:space:]]/}" ]] || { _fail "render $name: drew nothing"; return; }
  while IFS= read -r line; do
    _strip_ansi "$line"
    ((${#REPLY} > 79)) && { _fail "render $name: line ${n} is ${#REPLY} cols (max 79) — |${REPLY:0:60}|"; return; }
    ((n++))
  done < <(printf '%s\n' "$out" | sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b[()][A-Z0-9]//g' -e 's/\x1b[=>]//g')
  _ok
}

phase10_render_smoke() {
  printf '\n%s\n' "═══ PHASE 10: Render Smoke ═══"
  local before=$FAIL i d screens=0
  _render_prepare
  local -a checks=(
    "intro|_intro nopause"
    "tutorial|_tutorial"
    "victory|_victory nopause"
    "stats|stats"
    "main menu|_main_menu"
    "options menu|_options_menu"
    "practice menu|_practice_menu"
    "playground card|_play_card _flags"
    "kill-chain map|_play_map _flags"
    "syllabus|SEL_ONCE=1 _play_learn _flags"
    "hint tier 1|_play_next_hint _flags; printf '%s\n' \"\$_PLAY_HINT_OUT\""
    "hint tier 3|for _i in 1 2 3; do _play_next_hint _flags; done; printf '%s\n' \"\$_PLAY_HINT_OUT\""
    "hint exhausted|for _t in \"\${_PLAY_FLAG_ORDER[@]}\"; do _flags[\$_t]=1; done; _play_next_hint _flags; printf '%s\n' \"\$_PLAY_HINT_OUT\""
    "question header|hdr 30 5 10"
    "question prompt|qdisp \"\$(printf 'Find every file under %s changed in the last 7 days and hand the list to tar' /sandbox/very/deep/path)\""
    "wrong answer|ans='find . -type f -newer .env -print0 | xargs -0 grep -l secret | sort -u | head -20'; _wrong_show"
  )
  # Both render tiers: unicode, and the ASCII fold legacy terminals get. The fold
  # swaps glyphs for ASCII of a different length, so a frame that fits in one tier
  # can shear in the other — each has to be measured on its own.
  local c t
  for t in "" "CMDCHAMP_ASCII=1"; do
    for c in "${checks[@]}"; do _render_check "${c%%|*}" "${c#*|}" "$t"; ((screens++)); done
    for ((i=1; i<=MAX_LEVEL; i++)); do
      _render_check "boss splash $i" "_boss_splash $i" "$t"
      _render_check "field manual $i" "OPT_BRIEF=1; _S_BRIEFED=(); _brief_show $i" "$t"
      ((screens+=2))
    done
    for ((i=1; i<=PLAY_MOD_TOTAL; i++)); do _render_check "module $i" "_play_mod_detail _flags $i" "$t"; ((screens++)); done
    for d in "${!_DISK_DESC[@]}"; do _render_check "disk $d" "DISKS_FOUND=; _disk_found $d" "$t"; ((screens++)); done
  done
  # The four timed modes (boss, gauntlet, scenario, placement) draw their own header
  # instead of going through qdisp, and each one printed the prompt raw — so a prompt
  # past the terminal width hard-wrapped mid-word in exactly the modes with no manpage
  # to fall back on. They share _pfmt now; both halves of that are checked here because
  # a live drive only sees the long prompts its random boss round happens to pick.
  local _longest="" _lp _w2
  for ((i=1; i<=MAX_LEVEL; i++)); do
    local -a _lq=(); "gen_level$i" _lq 2>/dev/null
    for _lp in "${_lq[@]}"; do
      [[ -z "$_lp" ]] && continue
      _qparse "$_lp"; _strip_ansi "$_qprompt"
      ((${#REPLY} > ${#_longest})) && _longest=$REPLY
    done
  done
  for _w2 in 79 40 20; do
    _render_check "pfmt at $_w2 cols" "COLUMNS=$_w2; _pfmt \"$_longest\"; printf '%s\\n' \"\$REPLY\""
    ((screens++))
  done
  if grep -q '\${C}\${prompt}\${N}' "$CMDCHAMP"; then
    _fail "render: a timed-mode header still prints the prompt unwrapped (use _pfmt)"
  else _ok; fi

  printf '  screens drawn: %d   longest prompt: %d cols   broken: %d\n' "$screens" "${#_longest}" "$((FAIL - before))"
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 11: PLAYGROUND TRAIL INTEGRITY
# Every file path the playground TEXT names has to exist in the tree it builds.
# The hints, the tier-3 solve commands, the module exercises and the kill-chain
# map all point the player at named artifacts; one renamed fixture turns a
# lesson into a dead end that no other phase would notice.
#
# Two artifacts are absent ON PURPOSE — that IS the lesson (module 3: what was
# deleted still lives in the backup). Those are declared below and checked the
# other way round: gone from disk, still whole inside the archive.
# ═══════════════════════════════════════════════════════════════════
declare -A _PLAY_DELETED=(
  ['web/config.php']='archive/site-backup.tar.gz'   # rm'd from disk, intact in the tarball
)

phase11_playground_trail() {
  printf '\n%s\n' "═══ PHASE 11: Playground Trail Integrity ═══"
  local tree="$XDG_DATA_HOME/playtrail" before=$FAIL
  rm -rf "$tree"
  local _save_bb=$BOSS_BEATEN; BOSS_BEATEN=$MAX_LEVEL   # max unlock = every flag planted
  if ! _gen_play_files "$tree" >/dev/null 2>&1; then
    _fail "playground: tree generation failed"; BOSS_BEATEN=$_save_bb; return
  fi
  if ((${#_PLAY_PLANTED[@]} == ${#_PLAY_FLAG_ORDER[@]})); then _ok
  else _fail "playground: only ${#_PLAY_PLANTED[@]}/${#_PLAY_FLAG_ORDER[@]} flags planted at max unlock"; fi

  # Every string the player is shown, in one stream.
  local copy="" t i
  for t in "${_PLAY_FLAG_ORDER[@]}"; do
    copy+="${_PLAY_FLAG_LOC[$t]}"$'\n'"${_PLAY_FLAG_HINT[$t]}"$'\n'"${_PLAY_FLAG_CMD[$t]}"$'\n'
  done
  for ((i=1; i<=PLAY_MOD_TOTAL; i++)); do copy+="${PLAY_MOD_TRY[$i]}"$'\n'"${PLAY_MOD_FOUND[$i]}"$'\n'; done
  for ((i=1; i<=PLAY_PHASE_TOTAL; i++)); do copy+="${PLAY_PHASE_ART[$i]}"$'\n'; done

  local path checked=0
  while IFS= read -r path; do
    path=${path#/sandbox/}
    [[ "$path" == /* ]] && continue                     # absolute: a real system path (/dev/null), not a fixture
    ((checked++))
    if [[ -n "${_PLAY_DELETED[$path]:-}" ]]; then
      [[ -e "$tree/$path" ]] && { _fail "playground: $path should be deleted from disk (that is the lesson)"; continue; }
      local arc="${_PLAY_DELETED[$path]}"
      if tar tzf "$tree/$arc" 2>/dev/null | grep -qx "$path"; then _ok
      else _fail "playground: $path is deleted and NOT in $arc — the lesson has no payoff"; fi
    elif [[ -e "$tree/$path" ]]; then _ok
    else _fail "playground: text points at $path, which the tree does not have"; fi
  done < <(printf '%s' "$copy" | grep -oE '/?[A-Za-z0-9_.][A-Za-z0-9_./-]*/[A-Za-z0-9_.-]+' | sort -u)

  rm -rf "$tree"; BOSS_BEATEN=$_save_bb
  printf '  paths checked: %d   dead ends: %d\n' "$checked" "$((FAIL - before))"
}

# ═══════════════════════════════════════════════════════════════════
# PHASE 12: LINE EDITOR
# Every answer in the game is typed through _read_line, and nothing tested it.
# Two passes:
#   1. exact cases - keystrokes in, expected buffer out, checked against vim's
#      real semantics (D leaves the space, p pastes AFTER the cursor, X deletes
#      the char before it). This pass caught `cw` on the last word inserting one
#      column early, because _del clamped a cursor that was about to enter insert.
#   2. fuzz - seeded random keystrokes, including raw escapes and control bytes.
#      Nothing may hang, crash, write to stderr, or grow the buffer past its cap.
#
# ESC is fed in its own chunk with a gap: _read_line only treats ESC as "leave
# insert" when no byte follows within 10ms, which is exactly how it tells a
# human's Esc from a terminal's arrow key. Feeding "\x1bx" in one write is an
# escape sequence, not Esc-then-x - the test has to type like a human here.
# ═══════════════════════════════════════════════════════════════════
_ED_SRC="$XDG_DATA_HOME/ed_src.sh"
_ED_RUN="$XDG_DATA_HOME/ed_run.sh"
_ED_OUT="$XDG_DATA_HOME/ed_out"
_ED_ERR="$XDG_DATA_HOME/ed_err"

_ed_prepare() {
  sed -e 's/^_tty().*/\_tty() { :; }/' -e '/^# ═══ CLI ENTRYPOINT ═══/,$d' "$CMDCHAMP" > "$_ED_SRC"
  printf '%s\n' 'SANDBOX_MODE=0' >> "$_ED_SRC"
  cat > "$_ED_RUN" <<'RUNNER'
source "$1"
OPT_VI=$2; _apply_opts
HIST=("first cmd" "second cmd"); HIST_IDX=${#HIST[@]}
_REDRAW_HDR() { :; }
_read_line 0 1 0
printf '%s' "$input" > "$3"
RUNNER
}

# _ed_type <vi> <chunk...> — feed keystrokes, leave the final buffer in $REPLY.
_ed_type() {
  local vi=$1; shift
  : > "$_ED_OUT"; : > "$_ED_ERR"
  { sleep 0.05; local p; for p in "$@"; do printf '%s' "$p"; sleep 0.03; done; } \
    | COLUMNS=79 timeout 10 bash "$_ED_RUN" "$_ED_SRC" "$vi" "$_ED_OUT" >/dev/null 2>"$_ED_ERR"
  _ED_RC=$?
  REPLY=$(<"$_ED_OUT")
}

_ed_case() { # <name> <vi> <expected> <chunk...>
  local name=$1 vi=$2 exp=$3; shift 3
  _ed_type "$vi" "$@"
  if ((_ED_RC == 124)); then _fail "editor $name: hung (10s timeout)"; return; fi
  if [[ -s "$_ED_ERR" ]]; then _fail "editor $name: stderr — $(head -c 90 "$_ED_ERR")"; return; fi
  if [[ "$REPLY" != "$exp" ]]; then _fail "editor $name: got |$REPLY| want |$exp|"; return; fi
  _ok
}

phase12_line_editor() {
  printf '\n%s\n' "═══ PHASE 12: Line Editor ═══"
  local before=$FAIL cases=0 E=$'\e' BS=$'\x7f'
  _ed_prepare
  # ── insert mode ──
  _ed_case "type"        0 'echo hi'   $'echo hi\n'
  _ed_case "backspace"   0 'echo hi'   "echo hix${BS}"$'\n'
  _ed_case "ctrl-u"      0 'xyz'       $'abc\x15xyz\n'
  _ed_case "ctrl-w"      0 'foo baz'   $'foo bar\x17baz\n'
  _ed_case "left arrow"  0 'aXbc'      $'abc\e[D\e[DX\n'
  _ed_case "history up"  0 'second cmd' $'\e[A\n'
  _ed_case "history up2" 0 'first cmd'  $'\e[A\e[A\n'
  cases=7
  # ── vi normal mode (expectations are vim's, not ours) ──
  local -a vi=(
    "x|hell|hello${E}|x"
    "X|foo br|foo bar${E}|X"
    "dw|bar|foo bar${E}|0|dw"
    "db|foo r|foo bar${E}|db"
    "D|foo |foo bar${E}|b|D"
    "cw last word|foo baz|foo bar${E}|b|cw|baz"
    "cw via w|foo baz|foo bar${E}|0|w|cw|baz"
    "ce|foo baz|foo bar${E}|b|ce|baz"
    "c\$|foo baz|foo bar${E}|b|c\$|baz"
    "cb|foo r|foo bar${E}|cb"
    "cc|baz|foo bar${E}|cc|baz"
    "cl|zoo bar|foo bar${E}|0|cl|z"
    "s|oo bar|foo bar${E}|0|s"
    "S|x|foo bar${E}|S|x"
    "r|zoo bar|foo bar${E}|0|rz"
    "tilde|Abc|abc${E}|0|~"
    "count 3x|a|aaaa${E}|0|3x"
    "count clamp|ab|ab${E}|999999999w"
    "undo|abc|abc${E}|x|u"
    "f then x|ab,c|a,b,c${E}|0|f,|x"
    "A append|helloX|hello${E}|A|X"
    "I insert|Xhello|hello${E}|I|X"
    "0 then l l|helo|hello${E}|0|ll|x"
    "dollar|hell|hello${E}|\$|x"
    "gg|oo bar|foo bar${E}|gg|x"
    "G|foo ba|foo bar${E}|G|x"
    "yw then p|foo bbarar|foo bar${E}|b|yw|p"
    "yw then P|foo barbar|foo bar${E}|b|yw|P"
    # visual mode — cross-checked against vis(1), a real vi
    "v d one char|oo bar|foo bar${E}|0|v|d"
    "ve d word| bar|foo bar${E}|0|ve|d"
    "vee d two words| baz|foo bar baz${E}|0|vee|d"
    "v\$ d to end||foo bar${E}|0|v\$|d"
    "vb d backwards|foo |foo bar${E}|\$|vb|d"
    "V d whole line||foo bar${E}|V|d"
    "v x deletes|oo bar|foo bar${E}|0|v|x"
    "ve c change|hi bar|foo bar${E}|0|vec|hi"
    "ve tilde|FOO bar|foo bar${E}|0|ve|~"
    "ve r fills|xxx bar|foo bar${E}|0|ve|rx"
    "ve y then P|foofoo bar|foo bar${E}|0|vey|0P"
    "vo swaps ends|ar|foo bar${E}|\$|vbo|0d"
    "v esc cancels|foo bar|foo bar${E}|0|ve|${E}"
    "vv cancels|foo bar|foo bar${E}|0|vev"
    "u after v d|foo bar|foo bar${E}|0|ved|u"
    "v on empty line|hi|${E}|v|i|hi"
  )
  local c name exp
  local IFS='|'
  for c in "${vi[@]}"; do
    local -a f=($c); IFS=' '
    name=${f[0]}; exp=${f[1]}
    _ed_case "$name" 1 "$exp" "${f[@]:2}" $'\n'
    ((cases++)); IFS='|'
  done
  IFS=' '
  # ── fuzz: seeded, so a failure is reproducible ──
  local seed=20260819 i n k blob
  RANDOM=$seed
  local -a bytes=(a b Z 0 9 ' ' '|' '"' "'" '$' '\' '/' '-' '.' ';' '~' '^'
    $'\e' $'\e[' $'\e[A' $'\e[B' $'\e[C' $'\e[D' $'\e[2' $'\x7f' $'\x17' $'\x15'
    d c y w b e x X p P u i a A I r f t '0' '$' '3' '9' $'\t')
  for ((i=0; i<40; i++)); do
    blob=""; n=$((RANDOM % 24 + 4))
    for ((k=0; k<n; k++)); do blob+="${bytes[RANDOM % ${#bytes[@]}]}"; done
    _ed_type $((i % 2)) "$blob"$'\n'
    ((cases++))
    if ((_ED_RC == 124)); then _fail "editor fuzz #$i (seed $seed): hung — |$(printf '%q' "$blob")|"
    elif [[ -s "$_ED_ERR" ]]; then _fail "editor fuzz #$i (seed $seed): stderr — $(head -c 90 "$_ED_ERR")"
    elif ((${#REPLY} > 512)); then _fail "editor fuzz #$i (seed $seed): buffer grew to ${#REPLY} (cap 512)"
    else _ok; fi
  done
  printf '  keystroke runs: %d (44 vi + 7 insert + 40 fuzz, seed %d)   broken: %d\n' "$cases" "$seed" "$((FAIL - before))"
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
# PHASE 13: HOSTILE ENVIRONMENT
#
# Everything a player's box can be that the developer's box never is. Each of
# these shipped as a real bug at least once:
#   - tr_TR.UTF-8 sorts "I" outside [A-Z], so the profile loader dropped
#     PROFILE_VER and reset the save on every launch
#   - "08" passed the ^[0-9]+$ guard and then died in ((...)) as octal
#   - a profile with no trailing newline lost its last line — PROFILE_VER again
#   - a CRLF round-trip put a CR in every value
# The rule for every check: a *recoverable* file round-trips intact, an
# *unrecoverable* one resets cleanly with a backup, and neither prints a byte to
# stderr. Runs under `env -i` — an inherited LANG would decide the result
# instead of the case under test.
# ═══════════════════════════════════════════════════════════════════
_HE_SRC="$XDG_DATA_HOME/he_src.sh"
_HE_DIR="$XDG_DATA_HOME/he_data"
_HE_LOC="$XDG_DATA_HOME/he_loc"
_HE_GRADED="$XDG_DATA_HOME/he_graded.sh"
_HE_PROFILE='PLAYER_NAME=ali
BOSS_BEATEN=15
BEST_CHALLENGE=42
DISKS_FOUND=nightowl
SC_DONE=1,2
LAST_DECAY=0
OPT_VI=1
OPT_ALTS=1
OPT_BRIEF=1
PLACED_THROUGH=3
LAST_DAILY=20260818
DAILY_STREAK=4
DAILY_MAXSTREAK=9
DAILY_BEST=77
DAILY_BEST_DATE=2026-08-18
PROFILE_VER=8'
_HE_WANT='ali|15|42|nightowl|20260818|4|77'
_HE_PROBE='_load_profile; printf "%s|%s|%s|%s|%s|%s|%s" "$PLAYER_NAME" "$BOSS_BEATEN" "$BEST_CHALLENGE" "$DISKS_FOUND" "$LAST_DAILY" "$DAILY_STREAK" "$DAILY_BEST"'

_he_prepare() {
  sed -e 's/^_tty().*/\_tty() { :; }/' -e '/^# ═══ CLI ENTRYPOINT ═══/,$d' "$CMDCHAMP" > "$_HE_SRC"
  printf '%s\n' 'SANDBOX_MODE=0' >> "$_HE_SRC"
  # Every string a question is GRADED on has to be 7-bit: the sandbox runs under
  # LC_ALL=C, so an expected output that changed with the player's locale (a Turkish
  # "ADMİN" for "admin") is an answer nobody can type.
  cat > "$_HE_GRADED" <<'GRADED'
_he_ascii() { [[ "$1" != *[!$'\x20'-$'\x7e']* ]]; }
_he_bad=""
for ((_lv=1; _lv<=MAX_LEVEL; _lv++)); do
  declare -a _Q=(); "gen_level$_lv" _Q 2>/dev/null
  for _q in "${_Q[@]}"; do
    [[ -z "$_q" ]] && continue
    for _tag in "#output:" "#require:"; do
      [[ "$_q" == *"$_tag"* ]] || continue
      _f=${_q##*"$_tag"}; _f=${_f%%#*}
      _he_ascii "$_f" || _he_bad="L$_lv $_tag$_f"
    done
  done
done
printf '%s' "${_he_bad:-ok}"
GRADED
}

_he_profile() { rm -rf "$_HE_DIR"; mkdir -p "$_HE_DIR/cmdchamp"; cat > "$_HE_DIR/cmdchamp/profile"; }

_he_run() {
  local envs=$1 code=$2
  # shellcheck disable=SC2086  # envs is a deliberate word-split list of NAME=VALUE
  env -i PATH="/usr/bin:/bin" XDG_DATA_HOME="$_HE_DIR" $envs \
    timeout 60 bash -c 'source "$1"; eval "$2"' _ "$_HE_SRC" "$code" 2>"$XDG_DATA_HOME/he_err"
}

_he_case() { # <name> <env> <code> <want>
  local name=$1 envs=$2 code=$3 want=$4 got rc err
  got=$(_he_run "$envs" "$code"); rc=$?
  err=$(<"$XDG_DATA_HOME/he_err")
  if   ((rc == 124));           then _fail "hostile $name: hung"
  elif ((rc != 0));             then _fail "hostile $name: exit $rc"
  elif [[ -n "$err" ]];         then _fail "hostile $name: stderr — ${err%%$'\n'*}"
  elif [[ "$got" != "$want" ]]; then _fail "hostile $name: got |$got| want |$want|"
  else _ok; fi
}

# Build a locale into a private LOCPATH so the box need not have it installed.
# Turkish is the one that matters: [A-Z] and ${x^^} both change meaning there.
_he_locale() {
  local name=$1 src=$2
  [[ -d "$_HE_LOC/$name" ]] && { REPLY="LOCPATH=$_HE_LOC LC_ALL=$name"; return 0; }
  command -v localedef >/dev/null 2>&1 || return 1
  [[ -f "/usr/share/i18n/locales/$src" ]] || return 1
  mkdir -p "$_HE_LOC"
  localedef -i "$src" -f UTF-8 "$_HE_LOC/$name" >/dev/null 2>&1 || return 1
  REPLY="LOCPATH=$_HE_LOC LC_ALL=$name"
}

phase13_hostile_env() {
  printf '\n%s\n' "═══ PHASE 13: Hostile Environment ═══"
  local before=$FAIL checks=0 locales=0 nm gen want got err rc s p e a l
  _he_prepare

  # ── A. save files a player can actually end up with ──────────────
  local -a survivable=(
    "trailing newline|printf '%s\n' \"\$_HE_PROFILE\""
    "no trailing newline|printf '%s' \"\$_HE_PROFILE\""
    "CRLF line endings|printf '%s\n' \"\$_HE_PROFILE\" | sed 's/\$/\r/'"
    "spaces round the =|printf '%s\n' \"\$_HE_PROFILE\" | sed 's/=/ = /'"
    "blank lines|printf '%s\n' \"\$_HE_PROFILE\" | sed G"
    "unknown future key|printf '%s\nWHAT_IS_THIS=1\n' \"\$_HE_PROFILE\""
    "leading-zero number|printf '%s\n' \"\$_HE_PROFILE\" | sed 's/=15/=015/'"
  )
  for s in "${survivable[@]}"; do
    nm=${s%%|*}; gen=${s#*|}
    eval "$gen" | _he_profile
    _he_case "profile: $nm" "" "$_HE_PROBE" "$_HE_WANT"; ((checks++))
  done

  # Numbers that pass ^[0-9]+$ and then break arithmetic, or that a hand edit invents.
  local -a poisoned=("octal 08:08:8" "octal 010:010:10" "over the cap:999:30"
    "past int64:99999999999999999999999:30" "not a number:fifteen:0" "negative:-5:0" "hex:0x10:0")
  for p in "${poisoned[@]}"; do
    nm=${p%%:*}; want=${p##*:}; gen=${p#*:}; gen=${gen%:*}
    printf '%s\n' "$_HE_PROFILE" | sed "s/^BOSS_BEATEN=15/BOSS_BEATEN=$gen/" | _he_profile
    _he_case "BOSS_BEATEN $nm" "" '_load_profile; printf "%s" "$BOSS_BEATEN"' "$want"; ((checks++))
  done

  # Unreadable files must reset cleanly — with a backup, and without a crash.
  head -c 64 /dev/urandom | _he_profile
  got=$(_he_run "" '_load_profile 2>/dev/null; printf "%s|%s" "$BOSS_BEATEN" "$PLAYER_NAME"')
  if [[ "$got" == "0|" && -f "$_HE_DIR/cmdchamp/profile.bak" ]]; then _ok
  else _fail "hostile profile: binary junk did not reset with a backup (got |$got|)"; fi
  ((checks++))

  # Scores: the same file shapes, plus a blank line (an empty subscript is fatal).
  local -a scorefiles=("trailing newline:a|2|1750000000\nb|2|1750000000\n:2"
    "no trailing newline:a|2|1750000000\nb|2|1750000000:2"
    "CRLF:a|2|1750000000\r\nb|2|1750000000\r\n:2"
    "blank line:a|2|1750000000\n\nb|2|1750000000\n:2"
    "comment line:# note\na|2|1750000000\n:1")
  printf '%s\n' "$_HE_PROFILE" | _he_profile
  for s in "${scorefiles[@]}"; do
    nm=${s%%:*}; want=${s##*:}; gen=${s#*:}; gen=${gen%:*}
    printf "$gen" > "$_HE_DIR/cmdchamp/scores"
    _he_case "scores: $nm" "" 'declare -A _t; _scores_load _t; printf "%s" "${#_t[@]}"' "$want"; ((checks++))
  done
  rm -f "$_HE_DIR/cmdchamp/scores"

  # ── B. locales ───────────────────────────────────────────────────
  printf '%s\n' "$_HE_PROFILE" | _he_profile
  local -a locs=("C" "POSIX")
  for s in "tr_TR.UTF-8:tr_TR" "de_DE.UTF-8:de_DE"; do
    _he_locale "${s%%:*}" "${s##*:}" && { locs+=("${s%%:*}"); ((locales++)); }
  done
  ((locales < 2)) && _warn "hostile: localedef or locale sources missing — tr_TR/de_DE coverage skipped"
  # Both spellings: LC_ALL is what a script exports, LANG is what a desktop sets, and
  # they take different paths through the pin (LC_ALL is unset, LANG is left alone).
  local v
  for l in "${locs[@]}"; do
    for v in LC_ALL LANG; do
      e="$v=$l"; [[ -d "$_HE_LOC/$l" ]] && e="LOCPATH=$_HE_LOC $v=$l"
      _he_case "locale $v=$l: profile"   "$e" "$_HE_PROBE" "$_HE_WANT"; ((checks++))
      _he_case "locale $v=$l: case fold" "$e" '_upper admin; printf "%s" "$REPLY"; _lower IVY; printf "%s" "$REPLY"' "ADMINivy"; ((checks++))
      _he_case "locale $v=$l: ranges"    "$e" \
        'r=; for k in PROFILE_VER DISKS_FOUND OPT_VI DAILY_BEST; do [[ "$k" =~ ^[A-Z_]+$ ]] && r+=1 || r+=0; done; printf "%s" "$r"' "1111"; ((checks++))
      _he_case "locale $v=$l: graded strings stay 7-bit" "$e" "source '$_HE_GRADED'" "ok"; ((checks++))
    done
  done

  # ── C. an environment nobody tests in ────────────────────────────
  local -a envs=("IFS=x" "CDPATH=/tmp" "POSIXLY_CORRECT=1" "GREP_OPTIONS=--color=always"
    "COLUMNS=20" "COLUMNS=1000" "LINES=5" "TERM=dumb" "TERM=vt100" "NO_COLOR=1"
    "TZ=Pacific/Kiritimati" "TZ=Etc/GMT+12" "CMDCHAMP_ASCII=1" "CMDCHAMP_UNICODE=1" "CMD_PROMPT=%s")
  for e in "${envs[@]}"; do
    _he_case "env $e: profile" "$e" "$_HE_PROBE" "$_HE_WANT"; ((checks++))
    _he_case "env $e: grade"   "$e" \
      'PLAYER_NAME=x; _qparse "List files|ls"; check ls "$_qanswers" && printf yes || printf no' "yes"; ((checks++))
    _he_case "env $e: draws"   "$e" \
      'PLAYER_NAME=x BOSS_BEATEN=30; o=$(_intro nopause </dev/null); [[ -n "${o//[[:space:]]/}" ]] && printf drew || printf blank' "drew"; ((checks++))
  done

  # ── D. arguments a user or a script can hand it ──────────────────
  for a in "--badflag" "daily 9999-99-99" "daily ../../etc/passwd" "daily \$(id)" "daily 0" "nonsense" "play extra"; do
    # shellcheck disable=SC2086
    got=$(env -i PATH="/usr/bin:/bin" XDG_DATA_HOME="$_HE_DIR" timeout 20 "$CMDCHAMP" $a </dev/null 2>"$XDG_DATA_HOME/he_err"); rc=$?
    err=$(<"$XDG_DATA_HOME/he_err")
    if   ((rc == 124));                       then _fail "hostile arg '$a': hung"
    elif [[ "$err" == *"line "*": "* ]];      then _fail "hostile arg '$a': bash error — ${err%%$'\n'*}"
    elif [[ -z "${got}${err}" ]];             then _fail "hostile arg '$a': said nothing (rc $rc)"
    else _ok; fi
    ((checks++))
  done

  # ── E. no terminal, an unwritable data dir, no HOME ──────────────
  got=$(env -i PATH="/usr/bin:/bin" XDG_DATA_HOME="$_HE_DIR" timeout 20 "$CMDCHAMP" </dev/null 2>&1); rc=$?
  if ((rc == 1)) && [[ "$got" == *"interactive terminal"* ]]; then _ok
  else _fail "hostile: no-tty launch should refuse cleanly (rc $rc, out |${got:0:60}|)"; fi
  ((checks++))

  chmod 500 "$_HE_DIR/cmdchamp"
  got=$(env -i PATH="/usr/bin:/bin" XDG_DATA_HOME="$_HE_DIR" timeout 20 "$CMDCHAMP" version 2>"$XDG_DATA_HOME/he_err"); rc=$?
  err=$(<"$XDG_DATA_HOME/he_err")
  chmod 700 "$_HE_DIR/cmdchamp"
  if ((rc == 0)) && [[ -n "$got" && -z "$err" ]]; then _ok
  else _fail "hostile: read-only data dir broke a plain run (rc $rc, err ${err%%$'\n'*})"; fi
  ((checks++))

  got=$(env -i PATH="/usr/bin:/bin" HOME="$XDG_DATA_HOME/nohome" timeout 20 "$CMDCHAMP" version 2>"$XDG_DATA_HOME/he_err"); rc=$?
  err=$(<"$XDG_DATA_HOME/he_err")
  if ((rc == 0)) && [[ -z "$err" ]]; then _ok
  else _fail "hostile: a fresh HOME broke a plain run (rc $rc, err ${err%%$'\n'*})"; fi
  ((checks++))

  printf '  hostile checks: %d   locales built: %d   broken: %d\n' "$checks" "$locales" "$((FAIL - before))"
}


# ═══════════════════════════════════════════════════════════════════
# PHASE 14: FULL PLAYTHROUGH
#
# Every other phase checks a part in isolation. This one plays the game: a blank
# profile, level 1, and a bot that answers each question with that question's own
# canonical answer, all the way to the victory screen — then challenge, daily, all
# 13 scenarios, practice and the placement test. It is the only thing that touches
# run(), the boss round, level unlock, and the save/reload spine at all.
#
# It has already earned its keep. The first full drive never finished: level 23's
# git questions answered with a raw regex, which check() cannot match, so the
# practice loop repeated one question forever — a real hard-lock for anyone playing
# without bwrap. The transcript then showed a 149-column progress bar (one cell per
# question, and level 30 has 149) and 83-column prompts in the boss round, which
# prints its prompt unwrapped. All three were invisible to 7000 other tests.
#
# The bot drives _read_line, not the keyboard: keystroke handling is phase 12's job.
# ═══════════════════════════════════════════════════════════════════
_AD_SRC="$XDG_DATA_HOME/ad_src.sh"
_AD_RUN="$XDG_DATA_HOME/ad_run.sh"
_AD_DIR="$XDG_DATA_HOME/ad_data"
_AD_OUT="$XDG_DATA_HOME/ad_out"
_AD_ERR="$XDG_DATA_HOME/ad_err"

_ad_prepare() {
  sed -e 's/^_tty().*/\_tty() { :; }/' -e '/^# ═══ CLI ENTRYPOINT ═══/,$d' "$CMDCHAMP" > "$_AD_SRC"
  printf '%s\n' 'SANDBOX_MODE=0' >> "$_AD_SRC"
  cat > "$_AD_RUN" <<'RUNNER'
source "$1"
PLAYER_NAME=driver
_pause() { :; }
sleep() { :; }
# AD_MAX is a runaway guard, not a scenario: the gauntlet never ends for a bot that
# never misses, so each mode gets its own budget. AD_WRONG misses on purpose.
AD_WRONG=0 AD_MAX=4000 AD_N=0
_ad_budget() { AD_N=0; AD_MAX=$1; AD_WRONG=${2:-0}; _QUIT=0; }
_read_line() {
  input="$_qans"
  ((AD_WRONG > 0)) && { input="nonsense not-an-answer"; ((AD_WRONG--)); }
  ((++AD_N)); ((AD_N > AD_MAX)) && { _QUIT=1; input=""; return 2; }
  return 0
}
eval "$2"
RUNNER
}

# _ad_drive <name> <key fed to blocking reads> <code>. Fails on a hang, a bash error,
# a dirty stderr, or a line wider than 79 columns anywhere in the transcript.
_ad_drive() {
  local name=$1 key=$2 code=$3 rc wide
  : > "$_AD_ERR"
  yes "$key" 2>/dev/null | COLUMNS=79 XDG_DATA_HOME="$_AD_DIR" timeout 300 \
    bash "$_AD_RUN" "$_AD_SRC" "$code" >"$_AD_OUT" 2>"$_AD_ERR"
  rc=${PIPESTATUS[1]}
  if ((rc == 124)); then _fail "playthrough $name: hung (300s)"; return 1; fi
  if [[ -s "$_AD_ERR" ]]; then _fail "playthrough $name: stderr — $(head -c 100 "$_AD_ERR")"; return 1; fi
  wide=$(sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' -e 's/\x1b[()][A-Z0-9]//g' -e 's/\x1b[=>78]//g' "$_AD_OUT" \
    | awk 'length($0) > 79 { print length($0) ": " substr($0,1,60); exit }')
  if [[ -n "$wide" ]]; then _fail "playthrough $name: line past 79 cols — $wide"; return 1; fi
  return 0
}

# Grep the transcript with the escapes gone.
_ad_seen() { sed -e 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$_AD_OUT" | grep -acF "$1"; }
_ad_expect() { # <name> <marker> <want-count-or-min:N>
  local n; n=$(_ad_seen "$2")
  if [[ "$3" == min:* ]]; then ((n >= ${3#min:})) && { _ok; return; }
  elif ((n == $3)); then _ok; return; fi
  _fail "playthrough $1: saw '$2' $n times, wanted $3"
}

phase14_playthrough() {
  printf '\n%s\n' "═══ PHASE 14: Full Playthrough ═══"
  local before=$FAIL i lv beaten
  _ad_prepare
  rm -rf "$_AD_DIR"; mkdir -p "$_AD_DIR"

  # ── 1. level 1 to ROOT, answering everything right ───────────────
  if _ad_drive "1→30" '' '
      _load_profile; BOSS_BEATEN=0; LVL=1; QI=0
      _session_init; _QUIT=0; _NEXT_BOSS=0
      _ad_budget 20000
      while :; do
        _lv=$LVL; run "$LVL" "$_NEXT_BOSS"; _rc=$?
        printf "\n@LVL %d beaten=%d rc=%d\n" "$_lv" "$BOSS_BEATEN" "$_rc"
        ((_rc != 0)) && break; ((_QUIT)) && break; LVL=$_NEXT_LV
      done'; then
    # Every level in order, each one leaving BOSS_BEATEN at its own number.
    local -a got=()
    while read -r lv beaten; do got+=("$lv:$beaten"); done < <(
      sed 's/\x1b\[[0-9;?]*[a-zA-Z]//g' "$_AD_OUT" | sed -n 's/^@LVL \([0-9]*\) beaten=\([0-9]*\).*/\1 \2/p')
    if ((${#got[@]} == MAX_LEVEL)); then _ok
    else _fail "playthrough: drove ${#got[@]} levels, wanted $MAX_LEVEL"; fi
    local ok=1
    for ((i=0; i<${#got[@]}; i++)); do [[ "${got[$i]}" == "$((i+1)):$((i+1))" ]] || { ok=0; _fail "playthrough: level $((i+1)) left ${got[$i]}"; break; }; done
    ((ok)) && _ok
    _ad_expect "victory" "The daemons are silent." 1
    _ad_expect "bosses"  "DEFEATED" "min:$MAX_LEVEL"
    _ad_expect "no boss loss" "PREVAILS" 0
    # And it has to be on disk, not just in memory.
    beaten=$(sed -n 's/^BOSS_BEATEN=//p' "$_AD_DIR/cmdchamp/profile")
    [[ "$beaten" == "$MAX_LEVEL" ]] && _ok || _fail "playthrough: profile says BOSS_BEATEN=$beaten after ROOT"
    (( $(grep -c . "$_AD_DIR/cmdchamp/scores" 2>/dev/null || echo 0) > 500 )) && _ok \
      || _fail "playthrough: scores file did not fill in ($(wc -l < "$_AD_DIR/cmdchamp/scores" 2>/dev/null) lines)"
  fi

  # ── 2. missing on purpose ────────────────────────────────────────
  # A miss must cost a tier, reset the streak, and repeat the question — and the
  # level must still be completable afterwards.
  if _ad_drive "wrong answers" '' '
      _load_profile; LVL=5; QI=0; _session_init; _QUIT=0
      _ad_budget 400 3
      _mode_init 5; _sset "probe question" 2; _sget "probe question"; printf "@TIER-BEFORE %s\n" "$REPLY"
      run 5 0; printf "@RUN rc=%d beaten=%d\n" "$?" "$BOSS_BEATEN"'; then
    _ad_expect "wrong path completes" "@RUN rc=0" 1
  fi

  # ── 3. losing the boss ───────────────────────────────────────────
  # Every boss answer wrong, then q at the retry prompt: the level must not unlock.
  if _ad_drive "boss loss" 'q' '
      _load_profile; BOSS_BEATEN=0; LVL=2; QI=0; _session_init; _QUIT=0
      _ad_budget 200 200
      run 2 1; printf "@BOSS rc=%d beaten=%d\n" "$?" "$BOSS_BEATEN"'; then
    _ad_expect "boss loss keeps the level locked" "@BOSS rc=0 beaten=0" 1
    _ad_expect "boss loss says so" "PREVAILS" 1
  fi

  # ── 4. the post-ROOT modes ───────────────────────────────────────
  if _ad_drive "challenge + daily" '' '
      _load_profile
      _ad_budget 40; challenge; printf "@CHAL best=%d\n" "$BEST_CHALLENGE"
      _ad_budget 40; daily;     printf "@DAILY last=%s streak=%d\n" "$LAST_DAILY" "$DAILY_STREAK"
      _ad_budget 40; daily;     printf "@AGAIN last=%s streak=%d\n" "$LAST_DAILY" "$DAILY_STREAK"
      _sv=$DAILY_STREAK
      _ad_budget 40; daily 2026-01-01; printf "@REPLAY same=%d\n" "$((DAILY_STREAK == _sv))"'; then
    _ad_expect "challenge scores"        "@CHAL best=" 1
    _ad_expect "daily starts a streak"   "streak=1" 2
    _ad_expect "a replay leaves it alone" "@REPLAY same=1" 1
  fi

  # ── 5. every scenario, start to finish ───────────────────────────
  # Scenarios refuse to run without a sandbox, so this is the one block that needs it.
  if ((SANDBOX_MODE)); then
    if _ad_drive "scenarios" '' '
        SANDBOX_MODE=1; _check_bwrap; _load_profile; SC_DONE=""
        for i in $(seq 1 $SC_TOTAL); do _ad_budget 60; scenario "$i"; printf "@SC %d rc=%d\n" "$i" "$?"; done
        printf "@SCDONE %d\n" "$(tr , "\n" <<< "$SC_DONE" | grep -c .)"'; then
      _ad_expect "13 scenarios run clean" "rc=0" "min:$SC_TOTAL"
      _ad_expect "13 scenarios recorded"  "@SCDONE $SC_TOTAL" 1
    fi
  else
    _warn "playthrough: no bwrap — the scenario engine was not driven"
  fi

  # ── 6. practice must not move the main game ──────────────────────
  if _ad_drive "practice" '' '
      _load_profile; _b=$BOSS_BEATEN; _l=${LVL:-1}
      _ad_budget 600; drill 3
      printf "@PRACTICE same=%d\n" "$((BOSS_BEATEN == _b))"'; then
    _ad_expect "practice leaves progress alone" "@PRACTICE same=1" 1
  fi

  # ── 7. the placement test ────────────────────────────────────────
  if _ad_drive "placement" '' '
      _load_profile; BOSS_BEATEN=0; PLACED_THROUGH=0; _session_init; _QUIT=0
      _ad_budget 200; place
      printf "@PLACE beaten=%d placed=%d\n" "$BOSS_BEATEN" "$PLACED_THROUGH"'; then
    _ad_expect "placement places" "@PLACE beaten=$MAX_LEVEL placed=$MAX_LEVEL" 1
  fi

  printf '  playthrough: %d levels + %d scenarios + challenge/daily/practice/placement   broken: %d\n' \
    "$MAX_LEVEL" "$SC_TOTAL" "$((FAIL - before))"
}

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════
main() {
  local _want="${1:-}"
  printf '%s\n' "╔══════════════════════════════════════════╗"
  printf '%s\n' "║   CmdChamp Omega Audit                   ║"
  printf '%s\n' "║   30 levels × 14 phases                  ║"
  printf '%s\n' "╚══════════════════════════════════════════╝"

  if ! ((SANDBOX_MODE)); then
    printf '\n  ⚠  bwrap NOT INSTALLED — phases 2-4 degrade to text-match only!\n'
    printf '     Install bwrap for full coverage: paru -S bubblewrap\n\n'
  fi

  # `./audit.sh 10` (or `1,10`) runs just those phases — the full sweep is slow
  # enough that iterating on one phase otherwise means waiting on nine others.
  local -a _phases=(phase1_syntax phase2_positive phase3_confusable phase4_generic
    phase5_crosscheck phase6_scenarios phase7_scenario_negatives phase8_panel_coverage
    phase9_manpage_grid phase10_render_smoke phase11_playground_trail phase12_line_editor
    phase13_hostile_env phase14_playthrough)
  local _p _n
  for _p in "${_phases[@]}"; do
    _n=${_p#phase}; _n=${_n%%_*}
    [[ -z "$_want" || ",$_want," == *",$_n,"* ]] && "$_p"
  done

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
