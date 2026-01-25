#!/bin/bash
# cmd - CLI Command Trainer
# SNES-hard flashcard game for modern CLI mastery
# https://github.com/mellen/cmd

set -euo pipefail

# XDG paths
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/cmd"
PROGRESS_FILE="$DATA_DIR/progress.json"
STATS_FILE="$DATA_DIR/stats.json"
SESSION_FILE="$DATA_DIR/session.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

# State
CURRENT_LEVEL=1
CURRENT_Q=0
USED_HINT=false
PROGRESS=0
TOTAL_Q=0

# ============================================================================
# QUESTIONS - Format: "prompt|canonical_answer"
# Validator normalizes flags so order doesn't matter
# ============================================================================

# Level 1: Core tools - bat, eza, fd, head/tail, basic ops
declare -a LEVEL1=(
  "View config.ini with syntax highlighting|bat config.ini"
  "List files with size and permissions|eza -l"
  "List all files with details, including hidden|eza -la"
  "Show files as tree|eza -T"
  "Find all python files|fd -e py"
  "First 10 lines of data.txt|head -10 data.txt"
  "Last 20 lines of log.txt|tail -20 log.txt"
  "Count lines in data.csv|wc -l data.csv"
  "Disk usage current dir|dust"
  "Copy config.ini to backup.ini|cp config.ini backup.ini"
)

# Level 2: rg essentials - searching text
declare -a LEVEL2=(
  "Search for 'error' in all files|rg error"
  "Case-insensitive search for 'warning'|rg -i warning"
  "Show line numbers with matches|rg -n TODO"
  "Count matches in file|rg -c error log.txt"
  "Show 2 lines context around match|rg -C 2 panic"
  "Only show filenames with matches|rg -l error"
  "Search only in python files|rg -t py import"
  "Search for regex pattern|rg '\\d{3}-\\d{4}'"
  "Invert match - lines without error|rg -v error log.txt"
  "Fixed string search (no regex)|rg -F 'func()' app.py"
)

# Level 3: fd essentials - finding files
declare -a LEVEL3=(
  "Find files by extension|fd -e log"
  "Find files larger than 10M|fd -S +10M"
  "Find files modified in last hour|fd --changed-within 1h"
  "Find directories only|fd -t d"
  "Find and include hidden files|fd -H config"
  "Find excluding .git|fd -E .git"
  "Find empty files|fd -t f -S 0"
  "Find executable files|fd -t x"
  "Find symlinks|fd -t l"
  "Find by full path pattern|fd -p src/.*test"
)

# Level 4: eza advanced + basic piping
declare -a LEVEL4=(
  "List sorted by size descending|eza -l --sort size -r"
  "List sorted by modification time|eza -l --sort modified"
  "List directories only|eza -D"
  "List with git status|eza -l --git"
  "Tree view 2 levels deep|eza -T -L 2"
  "Follow log file live|tail -f server.log"
  "Sort and dedupe lines|sort -u dupes.txt"
  "Extract 2nd CSV column|cut -d',' -f2 data.csv"
  "Sort by 2nd column|sort -k2 data.txt"
  "Count unique lines|sort data.txt | uniq -c"
)

# Level 5: fd -x execution + pipes
declare -a LEVEL5=(
  "Find and list each file details|fd -e py -x eza -l {}"
  "Find and count lines in each|fd -e txt -x wc -l {}"
  "Find and delete temp files|fd -e tmp -x rm {}"
  "Find and chmod scripts|fd -e sh -x chmod +x {}"
  "Find and search inside|fd -e log -x rg error {}"
  "Extract IPs and count|rg -o '\\d+\\.\\d+\\.\\d+\\.\\d+' log.txt | sort | uniq -c"
  "Find large files show sizes|fd -S +100M -x du -h {}"
  "Replace text in file|sd 'old' 'new' config.txt"
  "Replace in multiple files|fd -e txt -x sd 'foo' 'bar' {}"
  "Process tree view|procs --tree"
)

declare -a LEVEL6=(
  "Scan host for open ports|nmap -p- 10.0.0.1"
  "Quick scan common ports|nmap --top-ports 100 10.0.0.1"
  "Detect service versions|nmap -sV 10.0.0.1"
  "Scan with OS detection|nmap -O 10.0.0.1"
  "UDP scan top ports|nmap -sU --top-ports 20 10.0.0.1"
  "Aggressive scan with scripts|nmap -A 10.0.0.1"
  "Scan subnet for live hosts|nmap -sn 10.0.0.0/24"
  "Fast scan skip host discovery|nmap -Pn -F 10.0.0.1"
  "Output scan to greppable format|nmap -oG scan.txt 10.0.0.1"
  "Scan through proxy|proxychains nmap -sT 10.0.0.1"
  "Check for specific vulnerability|nmap --script vuln 10.0.0.1"
  "Banner grab on port 80|nmap -sV -p 80 --script banner 10.0.0.1"
  "Scan for SMB shares|nmap --script smb-enum-shares 10.0.0.1"
  "Detect web server info|nmap -sV -p 80,443 10.0.0.1"
  "Full port scan save all formats|nmap -p- -oA full_scan 10.0.0.1"
)

declare -a LEVEL7=(
  "Crack MD5 hash with wordlist|hashcat -m 0 hash.txt wordlist.txt"
  "Crack SHA256 hash|hashcat -m 1400 hash.txt wordlist.txt"
  "Crack bcrypt hash|hashcat -m 3200 hash.txt wordlist.txt"
  "Brute force 4 digit PIN|hashcat -m 0 -a 3 hash.txt ?d?d?d?d"
  "Crack with rules|hashcat -m 0 -r rules/best64.rule hash.txt wordlist.txt"
  "Show cracked passwords|hashcat -m 0 hash.txt --show"
  "John the Ripper default crack|john hash.txt"
  "John with specific wordlist|john --wordlist=wordlist.txt hash.txt"
  "John show cracked|john --show hash.txt"
  "Generate hash from password|echo -n 'password' | md5sum"
  "HTTP brute force with hydra|hydra -l admin -P wordlist.txt 10.0.0.1 http-get /"
  "SSH brute force|hydra -l root -P wordlist.txt 10.0.0.1 ssh"
  "Crack zip password|john --format=zip archive.zip"
  "Base64 decode|base64 -d encoded.txt"
  "Hex to ascii|xxd -r -p hex.txt"
)

declare -a LEVEL8=(
  "Extract strings from binary|strings binary.exe"
  "Analyze binary headers|readelf -h binary.elf"
  "Disassemble with radare2|r2 -A binary.exe"
  "Extract embedded files|binwalk -e firmware.bin"
  "Analyze entropy|binwalk -E firmware.bin"
  "Dump memory from image|volatility3 -f memory.dmp windows.info"
  "List processes in memory dump|volatility3 -f memory.dmp windows.pslist"
  "Extract network connections|volatility3 -f memory.dmp windows.netscan"
  "Recover deleted files|foremost -i disk.img -o output/"
  "Analyze filesystem|fls -r disk.img"
  "Extract metadata from image|exiftool photo.jpg"
  "Verify file integrity|sha256sum -c checksums.txt"
  "Create disk image|dd if=/dev/sda of=disk.img bs=4M"
  "Mount forensic image readonly|mount -o ro,loop disk.img /mnt/evidence"
  "Timeline filesystem|mactime -b bodyfile.txt"
)

declare -a LEVEL9=(
  "Full nmap scan with version scripts output all|nmap -sV -sC -p- -oA full 10.0.0.1"
  "Capture traffic on interface|tshark -i eth0 -w capture.pcap"
  "Filter HTTP traffic|tshark -r capture.pcap -Y http"
  "Extract credentials from pcap|tshark -r capture.pcap -Y 'http.request.method == POST' -T fields -e http.file_data"
  "Scan web app for vulns|nikto -h http://10.0.0.1"
  "SQL injection test|sqlmap -u 'http://10.0.0.1/page?id=1' --dbs"
  "Directory enumeration|feroxbuster -u http://10.0.0.1"
  "WiFi monitor mode|airmon-ng start wlan0"
  "Capture WiFi handshake|airodump-ng -c 6 --bssid AA:BB:CC:DD:EE:FF -w capture wlan0mon"
  "Deauth attack for handshake|aireplay-ng -0 5 -a AA:BB:CC:DD:EE:FF wlan0mon"
  "Crack WPA handshake|aircrack-ng -w wordlist.txt capture.cap"
  "Mass port scan fast|masscan -p1-65535 10.0.0.0/24 --rate 10000"
  "Enumerate SMB|smbclient -L //10.0.0.1 -N"
  "Reverse shell listener|nc -lvnp 4444"
  "System audit|lynis audit system"
)

# All levels array
declare -a LEVELS=("LEVEL1" "LEVEL2" "LEVEL3" "LEVEL4" "LEVEL5" "LEVEL6" "LEVEL7" "LEVEL8" "LEVEL9")

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

init_data_dir() {
  mkdir -p "$DATA_DIR"
  [[ -f "$PROGRESS_FILE" ]] || echo '{"completed":[]}' > "$PROGRESS_FILE"
  [[ -f "$STATS_FILE" ]] || echo '{}' > "$STATS_FILE"
  [[ -f "$SESSION_FILE" ]] || echo '{"level":1,"question":0}' > "$SESSION_FILE"
}

get_terminal_width() {
  tput cols 2>/dev/null || echo 80
}

# Normalize command for comparison - sort flags alphabetically
normalize_cmd() {
  local cmd="$1"
  local result=""
  local -a parts
  local -a flags=()
  local -a args=()

  # Split into words
  read -ra parts <<< "$cmd"

  # First word is always the command
  result="${parts[0]}"

  # Separate flags from args
  for ((i=1; i<${#parts[@]}; i++)); do
    local part="${parts[$i]}"
    if [[ "$part" == -* ]]; then
      # Expand combined short flags: -la -> -a -l (sorted)
      if [[ "$part" =~ ^-[a-zA-Z]+$ && ${#part} -gt 2 ]]; then
        local chars="${part:1}"
        for ((j=0; j<${#chars}; j++)); do
          flags+=("-${chars:$j:1}")
        done
      else
        flags+=("$part")
      fi
    else
      args+=("$part")
    fi
  done

  # Sort flags
  IFS=$'\n' sorted_flags=($(sort <<<"${flags[*]}")); unset IFS

  # Rebuild command
  for f in "${sorted_flags[@]}"; do
    result+=" $f"
  done
  for a in "${args[@]}"; do
    result+=" $a"
  done

  echo "$result"
}

# Check if answer matches (with flag order normalization)
check_answer() {
  local given="$1"
  local expected="$2"

  # Trim whitespace
  given="$(echo "$given" | xargs)"
  expected="$(echo "$expected" | xargs)"

  # Direct match
  [[ "$given" == "$expected" ]] && return 0

  # Normalized match
  local norm_given norm_expected
  norm_given="$(normalize_cmd "$given")"
  norm_expected="$(normalize_cmd "$expected")"

  [[ "$norm_given" == "$norm_expected" ]] && return 0

  return 1
}

# Draw vi-mode input line
# Uses globals: mode, input, cursor
# Draw level header with keybinds
# Autocomplete from prompt/answer words
autocomplete() {
  local partial="$1"
  local words="$2"
  [[ -z "$partial" ]] && return 1
  for word in $words; do
    if [[ "$word" == "$partial"* && "$word" != "$partial" ]]; then
      echo "$word"
      return 0
    fi
  done
  return 1
}

draw_header() {
  local level=$1
  local left="=== Level $level ==="
  local right="(?) hint  (TAB) complete"
  local width=$(tput cols 2>/dev/null || echo 80)
  local pad=$((width - ${#left} - ${#right}))
  ((pad < 1)) && pad=1
  printf "${BOLD}%s${NC}%${pad}s${DIM}%s${NC}\n\n" "$left" "" "$right"
}

draw_input() {
  echo -ne "\r\e[K"
  if [[ "$mode" == "insert" ]]; then
    echo -ne "\e[97m\$\e[0m "  # white $ (insert)
  else
    echo -ne "\e[91m\$\e[0m "  # red $ (normal)
  fi
  echo -n "$input"
  # Position cursor
  local back=$((${#input} - cursor))
  ((back > 0)) && echo -ne "\e[${back}D" || true
}

# Explain flags in a command
explain_flags() {
  local cmd="$1"
  local tool="${cmd%% *}"
  local explanations=""

  case "$tool" in
    rg)
      [[ "$cmd" == *" -i "* || "$cmd" == *" -i" ]] && explanations+=" -i=ignore case"
      [[ "$cmd" == *" -n "* || "$cmd" == *" -n" ]] && explanations+=" -n=line numbers"
      [[ "$cmd" == *" -c "* || "$cmd" == *" -c" ]] && explanations+=" -c=count only"
      [[ "$cmd" == *" -l "* || "$cmd" == *" -l" ]] && explanations+=" -l=files only"
      [[ "$cmd" == *" -v "* || "$cmd" == *" -v" ]] && explanations+=" -v=invert match"
      [[ "$cmd" == *" -F "* || "$cmd" == *" -F" ]] && explanations+=" -F=literal string"
      [[ "$cmd" == *" -t "* ]] && explanations+=" -t=file type"
      [[ "$cmd" == *" -C "* ]] && explanations+=" -C=context lines"
      [[ "$cmd" == *" -o "* ]] && explanations+=" -o=only matching"
      ;;
    fd)
      [[ "$cmd" == *" -e "* ]] && explanations+=" -e=extension"
      [[ "$cmd" == *" -t d"* ]] && explanations+=" -t d=directories"
      [[ "$cmd" == *" -t f"* ]] && explanations+=" -t f=files"
      [[ "$cmd" == *" -t l"* ]] && explanations+=" -t l=symlinks"
      [[ "$cmd" == *" -t x"* ]] && explanations+=" -t x=executables"
      [[ "$cmd" == *" -H"* ]] && explanations+=" -H=include hidden"
      [[ "$cmd" == *" -E "* ]] && explanations+=" -E=exclude"
      [[ "$cmd" == *" -S "* ]] && explanations+=" -S=size filter"
      [[ "$cmd" == *" -x "* ]] && explanations+=" -x=exec per file"
      [[ "$cmd" == *" -p "* ]] && explanations+=" -p=full path"
      [[ "$cmd" == *"--changed-within"* ]] && explanations+=" --changed-within=modified recently"
      ;;
    eza)
      [[ "$cmd" == *"-l"* ]] && explanations+=" -l=long format"
      [[ "$cmd" == *"-a"* ]] && explanations+=" -a=show hidden"
      [[ "$cmd" == *"-T"* ]] && explanations+=" -T=tree view"
      [[ "$cmd" == *"-D"* ]] && explanations+=" -D=dirs only"
      [[ "$cmd" == *"-r"* ]] && explanations+=" -r=reverse"
      [[ "$cmd" == *"-L "* ]] && explanations+=" -L=tree depth"
      [[ "$cmd" == *"--sort"* ]] && explanations+=" --sort=order by"
      [[ "$cmd" == *"--git"* ]] && explanations+=" --git=show status"
      ;;
    head) [[ "$cmd" == *"-"* ]] && explanations+=" -N=first N lines" ;;
    tail)
      [[ "$cmd" == *" -f"* ]] && explanations+=" -f=follow live"
      [[ "$cmd" == *"-"[0-9]* ]] && explanations+=" -N=last N lines"
      ;;
    wc) [[ "$cmd" == *" -l"* ]] && explanations+=" -l=lines only" ;;
    sort)
      [[ "$cmd" == *" -u"* ]] && explanations+=" -u=unique"
      [[ "$cmd" == *" -k"* ]] && explanations+=" -k=by column"
      [[ "$cmd" == *" -r"* ]] && explanations+=" -r=reverse"
      [[ "$cmd" == *" -n"* ]] && explanations+=" -n=numeric"
      ;;
    cut) [[ "$cmd" == *" -d"* ]] && explanations+=" -d=delimiter -f=field" ;;
    nmap)
      [[ "$cmd" == *" -p-"* ]] && explanations+=" -p-=all ports"
      [[ "$cmd" == *" -sV"* ]] && explanations+=" -sV=version detect"
      [[ "$cmd" == *" -sC"* ]] && explanations+=" -sC=default scripts"
      [[ "$cmd" == *" -O"* ]] && explanations+=" -O=OS detect"
      [[ "$cmd" == *" -A"* ]] && explanations+=" -A=aggressive"
      [[ "$cmd" == *" -sn"* ]] && explanations+=" -sn=ping scan"
      [[ "$cmd" == *" -Pn"* ]] && explanations+=" -Pn=skip ping"
      [[ "$cmd" == *" -sU"* ]] && explanations+=" -sU=UDP scan"
      [[ "$cmd" == *" -oG"* ]] && explanations+=" -oG=greppable out"
      [[ "$cmd" == *" -oA"* ]] && explanations+=" -oA=all formats"
      ;;
  esac

  [[ -n "$explanations" ]] && echo "$explanations"
}

# Draw progress bar
draw_bar() {
  local current=$1
  local total=$2
  local width=10

  local filled=$((current * width / total))
  local empty=$((width - filled))

  printf "["
  for ((i=0; i<filled; i++)); do printf "█"; done
  for ((i=0; i<empty; i++)); do printf "░"; done
  echo "]"
}


# Demo command in sandbox
demo_command() {
  local cmd="$1"
  local sandbox="/tmp/cmd_sandbox_$$"

  # Create sandbox with dummy files
  mkdir -p "$sandbox"/{logs,archive}
  cd "$sandbox" || return

  # Create dummy files for demos
  echo -e "# Config file\nhost=localhost\nport=8080\ndebug=true" > config.ini
  echo -e "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11\nline12" > data.txt
  echo -e "ERROR: connection failed\nINFO: starting\nWARN: slow query\nERROR: timeout" > log.txt
  echo -e "ERROR: disk full\nINFO: backup complete" > sys.log
  echo -e "name,age,city\nalice,30,NYC\nbob,25,LA\ncharlie,35,Chicago" > data.csv
  echo -e "alice,30,NYC\nbob,25,LA\nalice,30,NYC\nbob,25,LA" > dupes.txt
  echo '#!/bin/bash\necho "Hello World"' > script.sh
  echo "def main():\n    print('hello')" > app.py
  echo "console.log('test')" > app.js
  touch file.txt src.txt old.txt huge.log access.log server.log essay.txt file.csv mystery.bin
  echo "some binary data" > mystery.bin

  echo -e "\n${DIM}─── output ───${NC}"

  # Run command with timeout, skip dangerous ones
  case "$cmd" in
    rm*|mv*|dd*|mkfs*|nmap*|hydra*|hashcat*|john*|aircrack*|sqlmap*|nc\ *|masscan*)
      echo -e "${DIM}[demo skipped]${NC}"
      ;;
    *)
      # Run with color support, timeout 2s
      timeout 2s bash -c "$cmd" 2>&1 | head -15 || true
      ;;
  esac

  echo -e "${DIM}──────────────${NC}\n"

  # Cleanup
  cd "$HOME" || true
  rm -rf "$sandbox"
  sleep 1.5
}

# Save session state
save_session() {
  printf '{"level":%d,"question":%d}\n' "$CURRENT_LEVEL" "$CURRENT_Q" > "$SESSION_FILE"
}

# Load session state
load_session() {
  if [[ -f "$SESSION_FILE" ]]; then
    CURRENT_LEVEL=$(jq -r '.level // 1' "$SESSION_FILE")
    CURRENT_Q=$(jq -r '.question // 0' "$SESSION_FILE")
  fi
}

# Mark level complete
mark_complete() {
  local level=$1
  local completed
  completed=$(jq -r '.completed' "$PROGRESS_FILE")
  if ! echo "$completed" | jq -e "index($level)" > /dev/null 2>&1; then
    jq ".completed += [$level]" "$PROGRESS_FILE" > "$PROGRESS_FILE.tmp"
    mv "$PROGRESS_FILE.tmp" "$PROGRESS_FILE"
  fi
}

# Check if level is complete
is_complete() {
  local level=$1
  jq -e ".completed | index($level)" "$PROGRESS_FILE" > /dev/null 2>&1
}

# Update stats
update_stats() {
  local level=$1
  local question=$2
  local correct=$3
  local key="L${level}Q${question}"

  local attempts correct_count
  attempts=$(jq -r ".[\"$key\"].attempts // 0" "$STATS_FILE")
  correct_count=$(jq -r ".[\"$key\"].correct // 0" "$STATS_FILE")

  ((attempts++)) || true
  ((correct)) && ((++correct_count)) || true

  jq ".[\"$key\"] = {\"attempts\": $attempts, \"correct\": $correct_count}" "$STATS_FILE" > "$STATS_FILE.tmp"
  mv "$STATS_FILE.tmp" "$STATS_FILE"
}

# Show stats
show_stats() {
  echo -e "${BOLD}=== Command Training Stats ===${NC}\n"

  # Show completion
  echo -e "${CYAN}Completed Levels:${NC}"
  local completed
  completed=$(jq -r '.completed | sort | .[]' "$PROGRESS_FILE" 2>/dev/null)
  if [[ -n "$completed" ]]; then
    echo "$completed" | tr '\n' ' '
    echo
  else
    echo "None yet"
  fi
  echo

  # Show weak areas (questions with < 50% accuracy)
  echo -e "${YELLOW}Weak Areas (need practice):${NC}"
  jq -r 'to_entries | map(select(.value.attempts > 0 and (.value.correct / .value.attempts) < 0.5)) | .[].key' "$STATS_FILE" 2>/dev/null | head -10
  echo

  # Overall accuracy
  local total_attempts total_correct
  total_attempts=$(jq '[.[].attempts] | add // 0' "$STATS_FILE")
  total_correct=$(jq '[.[].correct] | add // 0' "$STATS_FILE")

  if ((total_attempts > 0)); then
    local pct=$((total_correct * 100 / total_attempts))
    echo -e "${BOLD}Overall Accuracy:${NC} $pct% ($total_correct/$total_attempts)"
  fi
}

# ============================================================================
# MAIN GAME LOOP
# ============================================================================

run_level() {
  local level=$1
  local level_name="LEVEL$level"
  local -n questions="$level_name"

  # Vi-mode state (used by draw_input)
  input=""
  cursor=0
  mode="insert"
  local char

  TOTAL_Q=${#questions[@]}
  PROGRESS=0

  # Shuffle questions
  local -a shuffled
  readarray -t shuffled < <(printf '%s\n' "${questions[@]}" | shuf)

  local completed_without_hint=0
  local q_index=0

  clear
  draw_header "$level"

  while ((q_index < ${#shuffled[@]})); do
    local card="${shuffled[$q_index]}"
    IFS='|' read -r prompt answer <<< "$card"

    USED_HINT=false
    local correct=false

    # Draw UI
    draw_bar "$PROGRESS" "$TOTAL_Q"
    echo -e "\n${DIM}$prompt${NC}\n"

    # Input loop for this question
    while ! $correct; do
      # Vi-mode input with PS1 style (white $=insert, red $=normal)
      input=""
      cursor=0
      mode="insert"

      draw_input

      while true; do
        IFS= read -rsn1 char

        # ? - show hint, any key dismisses
        if [[ "$char" == "?" ]]; then
          USED_HINT=true
          local flags=$(explain_flags "$answer")
          echo -ne "\r\e[K${DIM}\$ ${answer}${NC}"
          [[ -n "$flags" ]] && echo -e "\n${DIM}  ${flags}${NC}"
          read -rsn1 -t 0.3 || true  # wait, ignore held key
          read -t 0 -rsn 1000 || true  # flush buffer
          read -rsn1  # wait for fresh keypress
          [[ -n "$flags" ]] && echo -ne "\e[A"
          echo -ne "\r\e[K"
          draw_input
          continue
        fi

        if [[ "$mode" == "insert" ]]; then
          case "$char" in
            $'\t')  # TAB - autocomplete from prompt/answer words
              # Get current word (from last space to cursor)
              local before="${input:0:cursor}"
              local partial="${before##* }"
              # Words from prompt and answer
              local words="$prompt $answer"
              local completion=$(autocomplete "$partial" "$words")
              if [[ -n "$completion" ]]; then
                # Replace partial with completion
                local prefix="${before% *}"
                [[ "$before" == *" "* ]] && prefix+=" " || prefix=""
                input="${prefix}${completion}${input:cursor}"
                cursor=$((${#prefix} + ${#completion}))
                draw_input
              fi
              ;;
            $'\x1b')  # ESC - enter normal mode
              mode="normal"
              ((cursor > 0)) && ((cursor--))
              draw_input
              ;;
            $'\x7f'|$'\b')  # Backspace
              if ((cursor > 0)); then
                input="${input:0:cursor-1}${input:cursor}"
                ((cursor--))
                draw_input
              fi
              ;;
            '')  # Enter
              echo
              break
              ;;
            *)
              # Insert char at cursor
              input="${input:0:cursor}${char}${input:cursor}"
              ((++cursor))
              draw_input
              ;;
          esac
        else  # normal mode
          case "$char" in
            i)  # Insert at cursor
              mode="insert"
              draw_input
              ;;
            a)  # Append after cursor
              mode="insert"
              ((cursor < ${#input})) && ((++cursor))
              draw_input
              ;;
            A)  # Append at end
              mode="insert"
              cursor=${#input}
              draw_input
              ;;
            I)  # Insert at beginning
              mode="insert"
              cursor=0
              draw_input
              ;;
            h)  # Left
              ((cursor > 0)) && ((cursor--))
              draw_input
              ;;
            l)  # Right
              ((cursor < ${#input} - 1)) && ((++cursor))
              draw_input
              ;;
            0)  # Beginning of line
              cursor=0
              draw_input
              ;;
            $|^)  # End of line
              cursor=$((${#input} > 0 ? ${#input} - 1 : 0))
              draw_input
              ;;
            w)  # Word forward
              while ((cursor < ${#input})) && [[ "${input:cursor:1}" != " " ]]; do ((++cursor)); done
              while ((cursor < ${#input})) && [[ "${input:cursor:1}" == " " ]]; do ((++cursor)); done
              ((cursor >= ${#input} && ${#input} > 0)) && cursor=$((${#input} - 1))
              draw_input
              ;;
            b)  # Word backward
              ((cursor > 0)) && ((cursor--))
              while ((cursor > 0)) && [[ "${input:cursor:1}" == " " ]]; do ((cursor--)); done
              while ((cursor > 0)) && [[ "${input:cursor-1:1}" != " " ]]; do ((cursor--)); done
              draw_input
              ;;
            e)  # End of word
              ((cursor < ${#input} - 1)) && ((++cursor))
              while ((cursor < ${#input} - 1)) && [[ "${input:cursor:1}" == " " ]]; do ((++cursor)); done
              while ((cursor < ${#input} - 1)) && [[ "${input:cursor+1:1}" != " " ]]; do ((++cursor)); done
              draw_input
              ;;
            x)  # Delete char at cursor
              if ((${#input} > 0 && cursor < ${#input})); then
                input="${input:0:cursor}${input:cursor+1}"
                ((cursor >= ${#input} && cursor > 0)) && ((cursor--))
                draw_input
              fi
              ;;
            X)  # Delete char before cursor
              if ((cursor > 0)); then
                input="${input:0:cursor-1}${input:cursor}"
                ((cursor--))
                draw_input
              fi
              ;;
            d)  # Delete commands
              IFS= read -rsn1 char
              case "$char" in
                d)  # dd - delete whole line
                  input=""
                  cursor=0
                  draw_input
                  ;;
                w)  # dw - delete word
                  local end=$cursor
                  while ((end < ${#input})) && [[ "${input:end:1}" != " " ]]; do ((++end)); done
                  while ((end < ${#input})) && [[ "${input:end:1}" == " " ]]; do ((++end)); done
                  input="${input:0:cursor}${input:end}"
                  ((cursor >= ${#input} && cursor > 0)) && cursor=$((${#input} - 1))
                  draw_input
                  ;;
                $|0)  # d$ or d0
                  if [[ "$char" == "$" ]]; then
                    input="${input:0:cursor}"
                  else
                    input="${input:cursor}"
                    cursor=0
                  fi
                  ((cursor >= ${#input} && cursor > 0)) && cursor=$((${#input} - 1))
                  draw_input
                  ;;
              esac
              ;;
            c)  # Change commands
              IFS= read -rsn1 char
              case "$char" in
                c)  # cc - change whole line
                  input=""
                  cursor=0
                  mode="insert"
                  draw_input
                  ;;
                w)  # cw - change word
                  local end=$cursor
                  while ((end < ${#input})) && [[ "${input:end:1}" != " " ]]; do ((++end)); done
                  input="${input:0:cursor}${input:end}"
                  mode="insert"
                  draw_input
                  ;;
              esac
              ;;
            '')  # Enter
              echo
              break
              ;;
          esac
        fi
      done

      # Check answer
      if check_answer "$input" "$answer"; then
        correct=true
        ((++PROGRESS))

        if ! $USED_HINT; then
          ((++completed_without_hint))
          update_stats "$level" "$q_index" 1
          echo -e "${GREEN}+1${NC}"
        else
          update_stats "$level" "$q_index" 0
          echo -e "${YELLOW}+1${NC} ${DIM}(hint used)${NC}"
        fi

        # Demo the command live
        demo_command "$answer"

        ((++q_index))
        save_session
      else
        update_stats "$level" "$q_index" 0
        if ((PROGRESS > 0)); then
          ((PROGRESS--)) || true
        fi
        echo -e "${RED}-1${NC}"
        echo -e "${DIM}answer:${NC} ${CYAN}${answer}${NC}"
        echo -ne "${DIM}any key to continue${NC}"
        read -rsn1
        echo
      fi

      # Redraw
      if ! $correct; then
        sleep 0.3
        clear
        draw_header "$level"
        draw_bar "$PROGRESS" "$TOTAL_Q"
        echo -e "\n${DIM}$prompt${NC}\n"
      fi
    done

    clear
    draw_header "$level"
  done

  # Level complete
  if ((completed_without_hint >= TOTAL_Q)); then
    mark_complete "$level"
    echo -e "${GREEN}${BOLD}Level $level Complete!${NC}\n"
    if ((level < 9)); then
      echo "Press Enter for Level $((level + 1))..."
      read -r
      CURRENT_LEVEL=$((level + 1))
      CURRENT_Q=0
      save_session
      run_level "$CURRENT_LEVEL"
    else
      echo -e "${GREEN}${BOLD}ALL LEVELS COMPLETE! You are a CLI master.${NC}"
    fi
  else
    echo -e "${YELLOW}Level $level needs ${BOLD}$((TOTAL_Q - completed_without_hint))${NC}${YELLOW} more without hints${NC}"
    echo "Press Enter to retry..."
    read -r
    run_level "$level"
  fi
}

# ============================================================================
# ENTRY POINT
# ============================================================================

init_data_dir

case "${1:-}" in
  [1-9])
    CURRENT_LEVEL=$1
    CURRENT_Q=0
    save_session
    run_level "$CURRENT_LEVEL"
    ;;
  stats|s)
    show_stats
    ;;
  reset)
    rm -f "$PROGRESS_FILE" "$STATS_FILE" "$SESSION_FILE"
    echo "Progress reset."
    ;;
  help|h|--help|-h)
    echo "cmd - CLI Command Trainer"
    echo
    echo "Usage:"
    echo "  cmd         Resume from last position"
    echo "  cmd 1-9     Start at specific level"
    echo "  cmd stats   Show statistics"
    echo "  cmd reset   Reset all progress"
    echo
    echo "In-game:"
    echo "  ?           Show hint (won't count)"
    echo "  Enter       Submit answer"
    echo "  Ctrl+C      Quit (progress saved)"
    ;;
  "")
    load_session
    run_level "$CURRENT_LEVEL"
    ;;
  *)
    echo "Unknown command: $1"
    echo "Try: cmd help"
    exit 1
    ;;
esac
