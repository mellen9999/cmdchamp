#!/usr/bin/env bash
# cmd - CLI command trainer (github.com/mellen9999/cmd)
set -uo pipefail

[[ -t 0 ]] || { echo "Error: requires interactive terminal" >&2; exit 1; }

# Config - XDG compliant, user-agnostic
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/cmd"
mkdir -p "$DATA"

# Colors
R=$'\e[31m' G=$'\e[32m' Y=$'\e[33m' C=$'\e[36m' D=$'\e[2m' B=$'\e[1m' N=$'\e[0m'

# Prompt char - env override, or $ (# for root)
PROMPT_CHAR="${CMD_PROMPT:-$([[ $EUID -eq 0 ]] && echo '#' || echo '$')}"

# Vi mode: saved preference, env override, or ask once
VI_PREF="$DATA/vi_mode"
if [[ -n "${CMD_VI:-}" ]]; then
  VI_MODE=$CMD_VI
elif [[ -f "$VI_PREF" ]]; then
  VI_MODE=$(<"$VI_PREF")
else
  echo -n "Enable vi keybindings? (ESC for normal mode) [y/N] "
  read -r yn
  [[ "$yn" =~ ^[Yy] ]] && VI_MODE=1 || VI_MODE=0
  echo "$VI_MODE" > "$VI_PREF"
fi

# Questions: prompt|answer|alt1|alt2... (OG primary, modern alternates accepted)
declare -a Q0=(
  # Redirections
  'Redirect stdout to file.txt (overwrite)|cmd > file.txt'
  'Redirect stdout to file.txt (append)|cmd >> file.txt'
  'Redirect stderr to errors.log|cmd 2> errors.log'
  'Redirect both stdout and stderr to out.log|cmd &> out.log|cmd > out.log 2>&1'
  'Redirect stderr to stdout|cmd 2>&1'
  'Discard all output|cmd > /dev/null 2>&1|cmd &> /dev/null'
  'Discard only errors|cmd 2> /dev/null'
  'Read input from file.txt|cmd < file.txt'
  'Here string - pass string as stdin|cmd <<< "text"'
  # Pipes and logic
  'Pipe stdout to next command|cmd1 | cmd2'
  'Pipe both stdout and stderr|cmd1 |& cmd2'
  'Run cmd2 only if cmd1 succeeds|cmd1 && cmd2'
  'Run cmd2 only if cmd1 fails|cmd1 || cmd2'
  'Negate exit status|! cmd'
  # Job control
  'Run command in background|cmd &'
  'List background jobs|jobs'
  'Bring job 1 to foreground|fg %1'
  'Send job 1 to background|bg %1'
  'Kill job 1|kill %1'
  # Command substitution
  'Store command output in variable|var=$(cmd)'
  'Use command output inline|echo "Today is $(date)"'
  # Subshell and grouping
  'Run commands in subshell|(cd /tmp && pwd)'
  'Group commands in current shell|{ cmd1; cmd2; }'
  # History expansion
  'Repeat last command|!!'
  "Run last command starting with 'git'|!git"
  'Run command number 42 from history|!42'
  '^foo^bar to fix typo in last command|^foo^bar'
  'Last argument of previous command|!$'
  'First argument of previous command|!^'
  'All arguments of previous command|!*'
  # Special variables
  'Print current shell PID|echo $$'
  'Print exit status of last command|echo $?'
  'Print PID of last background process|echo $!'
  'Print number of arguments to script|echo $#'
  'Print all script arguments|echo $@'
  'Print current script name|echo $0'
  # Brace expansion
  'Create files a.txt b.txt c.txt|touch {a,b,c}.txt'
  'Create file1 through file5|touch file{1..5}'
  'Backup config.ini to config.ini.bak|cp config.ini{,.bak}'
  'Diff file.old vs file.new using brace expansion|diff file.{old,new}'
  # Process substitution
  'Diff output of two commands|diff <(cmd1) <(cmd2)'
)
declare -a Q1=(
  "View config.ini with syntax highlighting|cat config.ini|bat config.ini"
  "List files with size+perms|ls -l|eza -l"
  "List all files including hidden|ls -la|eza -la"
  "Show directory tree|tree|eza -T"
  "Find all .py files|find . -name '*.py'|fd -e py"
  "First 10 lines of data.txt|head -10 data.txt"
  "Last 20 lines of log.txt|tail -20 log.txt"
  "Count lines in data.csv|wc -l data.csv"
  "Show disk usage of current dir|du -sh .|dust"
  "Copy config.ini to backup.ini|cp config.ini backup.ini"
)
declare -a Q2=(
  "Search for 'error' recursively|grep -r error|rg error"
  "Case-insensitive search for 'warning'|grep -ri warning|rg -i warning"
  "Search for TODO with line numbers|grep -rn TODO|rg -n TODO"
  "Count 'error' matches in log.txt|grep -c error log.txt|rg -c error log.txt"
  "Search 'panic' with 2 lines context|grep -C 2 panic|rg -C 2 panic"
  "List only filenames containing 'error'|grep -rl error|rg -l error"
  "Search 'import' in .py files only|grep -r --include='*.py' import|rg -t py import"
  "Find phone pattern XXX-XXXX|grep -E '[0-9]{3}-[0-9]{4}'|rg '\\d{3}-\\d{4}'"
  "Lines without 'error' in log.txt|grep -v error log.txt|rg -v error log.txt"
  "Literal search 'func()' in app.py|grep -F 'func()' app.py|rg -F 'func()' app.py"
)
declare -a Q3=(
  "Find all .log files|find . -name '*.log'|fd -e log"
  "Find files larger than 10M|find . -size +10M|fd -S +10M"
  "Find files modified in last hour|find . -mmin -60|fd --changed-within 1h"
  "Find directories only|find . -type d|fd -t d"
  "Find 'config' including hidden files|find . -name '*config*'|fd -H config"
  "Find all, excluding .git|find . -not -path './.git/*'|fd -E .git"
  "Find empty files|find . -type f -empty|fd -t f -S 0"
  "Find executable files|find . -type f -executable|fd -t x"
  "Find symlinks|find . -type l|fd -t l"
  "Find files matching path src/*test*|find . -path '*src/*test*'|fd -p src/.*test"
)
declare -a Q4=(
  "List files sorted by size (largest first)|ls -lS|eza -l --sort size -r"
  "List files sorted by modification time|ls -lt|eza -l --sort modified"
  "List directories only|ls -d */|eza -D"
  "List files with git status|eza -l --git"
  "Show tree 2 levels deep|tree -L 2|eza -T -L 2"
  "Follow server.log in realtime|tail -f server.log"
  "Sort and deduplicate dupes.txt|sort -u dupes.txt"
  "Extract 2nd column from data.csv|cut -d',' -f2 data.csv"
  "Sort data.txt by column 2|sort -k2 data.txt"
  "Count unique lines in data.txt|sort data.txt | uniq -c"
)
declare -a Q5=(
  "Run ls -l on each .py file found|find . -name '*.py' -exec ls -l {} \\;|fd -e py -x ls -l {}"
  "Count lines in each .txt file|find . -name '*.txt' -exec wc -l {} \\;|fd -e txt -x wc -l {}"
  "Delete all .tmp files|find . -name '*.tmp' -delete|fd -e tmp -x rm {}"
  "Make all .sh files executable|find . -name '*.sh' -exec chmod +x {} \\;|fd -e sh -x chmod +x {}"
  "Search 'error' in each .log file|find . -name '*.log' -exec grep error {} \\;|fd -e log -x rg error {}"
  "Extract and count IPs from log.txt|grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' log.txt | sort | uniq -c|rg -o '\\d+\\.\\d+\\.\\d+\\.\\d+' log.txt | sort | uniq -c"
  "Show size of files >100M|find . -size +100M -exec du -h {} \\;|fd -S +100M -x du -h {}"
  "Replace 'old' with 'new' in config.txt|sed -i 's/old/new/g' config.txt|sd 'old' 'new' config.txt"
  "Replace 'foo' with 'bar' in all .txt files|find . -name '*.txt' -exec sed -i 's/foo/bar/g' {} \\;|fd -e txt -x sd 'foo' 'bar' {}"
  "Show process tree|ps auxf|procs --tree"
)
declare -a Q6=(
  "Scan all ports on 10.0.0.1|nmap -p- 10.0.0.1"
  "Scan top 100 ports on 10.0.0.1|nmap --top-ports 100 10.0.0.1"
  "Detect service versions on 10.0.0.1|nmap -sV 10.0.0.1"
  "Detect OS on 10.0.0.1|nmap -O 10.0.0.1"
  "UDP scan top 20 ports on 10.0.0.1|nmap -sU --top-ports 20 10.0.0.1"
  "Aggressive scan on 10.0.0.1|nmap -A 10.0.0.1"
  "Ping sweep 10.0.0.0/24 subnet|nmap -sn 10.0.0.0/24"
  "Fast scan 10.0.0.1, skip ping|nmap -Pn -F 10.0.0.1"
  "Scan 10.0.0.1, save greppable to scan.txt|nmap -oG scan.txt 10.0.0.1"
  "Scan 10.0.0.1 through proxychains|proxychains nmap -sT 10.0.0.1"
  "Run vuln scripts on 10.0.0.1|nmap --script vuln 10.0.0.1"
  "Banner grab port 80 on 10.0.0.1|nmap -sV -p 80 --script banner 10.0.0.1"
  "Enumerate SMB shares on 10.0.0.1|nmap --script smb-enum-shares 10.0.0.1"
  "Detect web server on 10.0.0.1 ports 80,443|nmap -sV -p 80,443 10.0.0.1"
  "Full scan 10.0.0.1, all output formats to full_scan|nmap -p- -oA full_scan 10.0.0.1"
)
declare -a Q7=(
  "Crack MD5 hashes in hash.txt using wordlist.txt|hashcat -m 0 hash.txt wordlist.txt"
  "Crack SHA256 hashes in hash.txt|hashcat -m 1400 hash.txt wordlist.txt"
  "Crack bcrypt hashes in hash.txt|hashcat -m 3200 hash.txt wordlist.txt"
  "Brute force 4-digit PIN for hash.txt|hashcat -m 0 -a 3 hash.txt ?d?d?d?d"
  "Crack hash.txt with best64 rules|hashcat -m 0 -r rules/best64.rule hash.txt wordlist.txt"
  "Show already cracked from hash.txt|hashcat -m 0 hash.txt --show"
  "Crack hash.txt with john default|john hash.txt"
  "Crack hash.txt with john using wordlist.txt|john --wordlist=wordlist.txt hash.txt"
  "Show cracked hashes from john|john --show hash.txt"
  "Generate MD5 hash of string 'password'|echo -n 'password' | md5sum"
  "Brute force HTTP auth on 10.0.0.1 user admin|hydra -l admin -P wordlist.txt 10.0.0.1 http-get /"
  "Brute force SSH on 10.0.0.1 user root|hydra -l root -P wordlist.txt 10.0.0.1 ssh"
  "Crack password on archive.zip|john --format=zip archive.zip"
  "Decode base64 file encoded.txt|base64 -d encoded.txt"
  "Convert hex file hex.txt to ascii|xxd -r -p hex.txt"
)
declare -a Q8=(
  "Extract strings from binary.exe|strings binary.exe"
  "Show ELF headers of binary.elf|readelf -h binary.elf"
  "Analyze binary.exe with radare2|r2 -A binary.exe"
  "Extract embedded files from firmware.bin|binwalk -e firmware.bin"
  "Analyze entropy of firmware.bin|binwalk -E firmware.bin"
  "Get system info from memory.dmp|volatility3 -f memory.dmp windows.info"
  "List processes from memory.dmp|volatility3 -f memory.dmp windows.pslist"
  "Extract network connections from memory.dmp|volatility3 -f memory.dmp windows.netscan"
  "Recover deleted files from disk.img to output/|foremost -i disk.img -o output/"
  "List filesystem of disk.img recursively|fls -r disk.img"
  "Extract metadata from photo.jpg|exiftool photo.jpg"
  "Verify checksums in checksums.txt|sha256sum -c checksums.txt"
  "Create disk image of /dev/sda to disk.img|dd if=/dev/sda of=disk.img bs=4M"
  "Mount disk.img readonly at /mnt/evidence|mount -o ro,loop disk.img /mnt/evidence"
  "Create filesystem timeline from bodyfile.txt|mactime -b bodyfile.txt"
)
declare -a Q9=(
  "Full nmap scan 10.0.0.1 with scripts, all output to 'full'|nmap -sV -sC -p- -oA full 10.0.0.1"
  "Capture traffic on eth0 to capture.pcap|tshark -i eth0 -w capture.pcap"
  "Filter HTTP traffic from capture.pcap|tshark -r capture.pcap -Y http"
  "Extract POST data from capture.pcap|tshark -r capture.pcap -Y 'http.request.method == POST' -T fields -e http.file_data"
  "Scan http://10.0.0.1 for web vulns with nikto|nikto -h http://10.0.0.1"
  "Test SQLi on http://10.0.0.1/page?id=1|sqlmap -u 'http://10.0.0.1/page?id=1' --dbs"
  "Enumerate directories on http://10.0.0.1|feroxbuster -u http://10.0.0.1"
  "Enable monitor mode on wlan0|airmon-ng start wlan0"
  "Capture handshake on channel 6 from AA:BB:CC:DD:EE:FF|airodump-ng -c 6 --bssid AA:BB:CC:DD:EE:FF -w capture wlan0mon"
  "Send 5 deauth packets to AA:BB:CC:DD:EE:FF|aireplay-ng -0 5 -a AA:BB:CC:DD:EE:FF wlan0mon"
  "Crack WPA handshake in capture.cap|aircrack-ng -w wordlist.txt capture.cap"
  "Mass scan all ports on 10.0.0.0/24 at 10k rate|masscan -p1-65535 10.0.0.0/24 --rate 10000"
  "List SMB shares on //10.0.0.1 anonymously|smbclient -L //10.0.0.1 -N"
  "Start reverse shell listener on port 4444|nc -lvnp 4444"
  "Run system security audit with lynis|lynis audit system"
)
LEVELS=(Q0 Q1 Q2 Q3 Q4 Q5 Q6 Q7 Q8 Q9)

# Normalize: sort flags so -la == -al == -a -l
norm() {
  local cmd="$1" parts flags=() args=()
  read -ra parts <<< "$cmd"
  local out="${parts[0]}"
  for ((i=1; i<${#parts[@]}; i++)); do
    local p="${parts[$i]}"
    if [[ "$p" == -* ]]; then
      if [[ "$p" =~ ^-[a-zA-Z]+$ && ${#p} -gt 2 ]]; then
        for ((j=1; j<${#p}; j++)); do flags+=("-${p:j:1}"); done
      else flags+=("$p"); fi
    else args+=("$p"); fi
  done
  IFS=$'\n' flags=($(sort <<<"${flags[*]}")); unset IFS
  for f in "${flags[@]}"; do out+=" $f"; done
  for a in "${args[@]}"; do out+=" $a"; done
  echo "$out"
}

# Check input against one answer (trim, normalize)
check1() {
  local a=$(echo "$1" | xargs) b=$(echo "$2" | xargs)
  [[ "$a" == "$b" ]] || [[ "$(norm "$a")" == "$(norm "$b")" ]]
}
# Check input against all answers (pipe-separated)
check() {
  local inp="$1" answers="$2" a
  IFS='|' read -ra opts <<< "$answers"
  for a in "${opts[@]}"; do check1 "$inp" "$a" && return 0; done
  return 1
}

# State
LVL=0 QN=0 HINT=false PROG=0 TOT=0
load() { [[ -f "$DATA/session.json" ]] && { LVL=$(jq -r '.level//.l//0' "$DATA/session.json"); QN=$(jq -r '.question//.q//0' "$DATA/session.json"); }; }
save() { printf '{"level":%d,"question":%d}\n' "$LVL" "$QN" > "$DATA/session.json"; }

# Minimal sandbox for demos
demo() {
  local cmd="$1" sb="/tmp/cmd$$"
  mkdir -p "$sb"/{logs,src}; cd "$sb"
  echo -e "host=localhost\nport=8080" > config.ini
  printf '%s\n' {1..12} > data.txt
  echo -e "ERROR: fail\nINFO: ok\nWARN: slow" > log.txt
  echo "a,1\nb,2\nc,3" > data.csv
  echo -e "x\ny\nx\ny" > dupes.txt
  touch app.{py,js,sh} file.{txt,log}
  echo -e "\n${D}─ output ─${N}"
  case "$cmd" in rm*|mv*|dd*|mkfs*|nmap*|hydra*|hashcat*|john*|aircrack*|sqlmap*|nc\ *|masscan*)
    echo "${D}[skipped]${N}";; *)
    timeout 2s bash -c "$cmd" 2>&1 | head -10 || true;; esac
  echo -e "${D}──────────${N}"
  cd /; rm -rf "$sb"; sleep 2
}

# UI helpers
input="" cursor=0 mode="insert" SHOW_HINT=0
hdr() { clear; echo -e "${B}=== Level $1 ===${N}  ${D}TAB=hint${N}\n"; }
bar() { echo -ne "["; printf '█%.0s' $(seq 1 $PROG 2>/dev/null); printf '░%.0s' $(seq 1 $((TOT-PROG)) 2>/dev/null); echo "]"; }
draw() {
  echo -ne "\r\e[K"
  if ((SHOW_HINT)); then echo -ne "${D}$PROMPT_CHAR ${ans}${N}"
  elif ((VI_MODE)); then [[ "$mode" == "insert" ]] && echo -ne "\e[97m$PROMPT_CHAR\e[0m " || echo -ne "\e[91m$PROMPT_CHAR\e[0m "; echo -n "$input"
  else echo -ne "\e[97m$PROMPT_CHAR\e[0m "; echo -n "$input"; fi
  local b=$((${#input}-cursor)); ((b>0)) && echo -ne "\e[${b}D"
}

run() {
  local lv=$1; local arr="Q$lv" shuf=() done=0 qi=0
  local -n qs="$arr"
  TOT=${#qs[@]}; PROG=0
  readarray -t shuf < <(printf '%s\n' "${qs[@]}" | shuf)
  hdr "$lv"
  while ((qi < ${#shuf[@]})); do
    local line="${shuf[$qi]}"
    prompt="${line%%|*}"; answers="${line#*|}"
    ans="${answers%%|*}"
    HINT=false; SHOW_HINT=0
    bar; echo -e "\n${D}$prompt${N}\n"

    while true; do
      input="" cursor=0 mode="insert"
      read -t 0.01 -rsn 1000 ||:  # flush input buffer
      draw
      while true; do
        IFS= read -rsn1 c
        # TAB toggles hint (instant, spammable)
        if [[ "$c" == $'\t' ]]; then
          ((SHOW_HINT)) && SHOW_HINT=0 || { SHOW_HINT=1; HINT=true; }
          draw; continue
        fi
        if [[ "$mode" == "insert" ]]; then
          case "$c" in
            $'\x1b') ((VI_MODE)) && { mode="normal"; ((cursor>0)) && ((cursor--)); draw; };;
            $'\x7f'|$'\b') ((cursor>0)) && { input="${input:0:cursor-1}${input:cursor}"; ((cursor--)); SHOW_HINT=0; draw; };;
            '') echo; break;;
            *) input="${input:0:cursor}${c}${input:cursor}"; ((++cursor)); SHOW_HINT=0; draw;;
          esac
        elif ((VI_MODE)); then
          case "$c" in
            # Enter insert mode
            i) mode="insert"; draw;; a) mode="insert"; ((cursor<${#input})) && ((++cursor)); draw;;
            A) mode="insert"; cursor=${#input}; draw;; I) mode="insert"; cursor=0; draw;;
            s) ((${#input}>0)) && { input="${input:0:cursor}${input:cursor+1}"; mode="insert"; draw; };;  # substitute char
            S) input="" cursor=0 mode="insert"; draw;;  # substitute line
            # Motion
            h) ((cursor>0)) && ((cursor--)); draw;; l) ((cursor<${#input}-1)) && ((++cursor)); draw;;
            0) cursor=0; draw;; \$) cursor=$((${#input}>0?${#input}-1:0)); draw;;
            w) while ((cursor<${#input})) && [[ "${input:cursor:1}" != " " ]]; do ((++cursor)); done
               while ((cursor<${#input})) && [[ "${input:cursor:1}" == " " ]]; do ((++cursor)); done
               ((cursor>=${#input}&&${#input}>0)) && cursor=$((${#input}-1)); draw;;
            b) ((cursor>0)) && ((cursor--))
               while ((cursor>0)) && [[ "${input:cursor:1}" == " " ]]; do ((cursor--)); done
               while ((cursor>0)) && [[ "${input:cursor-1:1}" != " " ]]; do ((cursor--)); done; draw;;
            e) ((cursor<${#input}-1)) && ((++cursor))
               while ((cursor<${#input}-1)) && [[ "${input:cursor:1}" == " " ]]; do ((++cursor)); done
               while ((cursor<${#input}-1)) && [[ "${input:cursor+1:1}" != " " ]]; do ((++cursor)); done; draw;;
            # Delete
            x) ((${#input}>0&&cursor<${#input})) && { input="${input:0:cursor}${input:cursor+1}"
               ((cursor>=${#input}&&cursor>0)) && ((cursor--)); draw; };;
            X) ((cursor>0)) && { input="${input:0:cursor-1}${input:cursor}"; ((cursor--)); draw; };;
            D) input="${input:0:cursor}"; ((cursor>0)) && ((cursor--)); draw;;  # delete to end
            r) IFS= read -rsn1 c2; [[ -n "$c2" && "$c2" != $'\x1b' ]] && { input="${input:0:cursor}${c2}${input:cursor+1}"; draw; };;
            d) IFS= read -rsn1 c2; case "$c2" in
                 d) input="" cursor=0; draw;;  # dd - delete line
                 w) e=$cursor; while ((e<${#input})) && [[ "${input:e:1}" != " " ]]; do ((++e)); done
                    input="${input:0:cursor}${input:e}"; ((cursor>=${#input}&&cursor>0)) && cursor=$((${#input}-1)); draw;;
                 b) e=$cursor; ((e>0)) && ((e--)); while ((e>0)) && [[ "${input:e:1}" == " " ]]; do ((e--)); done
                    while ((e>0)) && [[ "${input:e-1:1}" != " " ]]; do ((e--)); done
                    input="${input:0:e}${input:cursor}"; cursor=$e; draw;;
                 \$) input="${input:0:cursor}"; ((cursor>0)) && ((cursor--)); draw;;
                 0) input="${input:cursor}"; cursor=0; draw;;
               esac;;
            # Change
            C) input="${input:0:cursor}"; mode="insert"; draw;;  # change to end
            c) IFS= read -rsn1 c2; case "$c2" in
                 c) input="" cursor=0 mode="insert"; draw;;  # cc - change line
                 w) e=$cursor; while ((e<${#input})) && [[ "${input:e:1}" != " " ]]; do ((++e)); done
                    input="${input:0:cursor}${input:e}"; mode="insert"; draw;;
                 b) e=$cursor; ((e>0)) && ((e--)); while ((e>0)) && [[ "${input:e:1}" == " " ]]; do ((e--)); done
                    while ((e>0)) && [[ "${input:e-1:1}" != " " ]]; do ((e--)); done
                    input="${input:0:e}${input:cursor}"; cursor=$e; mode="insert"; draw;;
                 \$) input="${input:0:cursor}"; mode="insert"; draw;;
                 0) input="${input:cursor}"; cursor=0; mode="insert"; draw;;
               esac;;
            '') echo; break;;
          esac
        fi
      done

      if check "$input" "$answers"; then
        ((++PROG))
        $HINT && echo -e "${Y}+1${N} ${D}(hint)${N}" || { ((++done)); echo -e "${G}+1${N}"; }
        demo "$ans"; ((++qi)); save; break
      else
        ((PROG>0)) && ((PROG--))
        echo -e "${R}-1${N}\n${D}answer:${N} ${C}${ans}${N}"
        sleep 2
      fi
      hdr "$lv"; bar; echo -e "\n${D}$prompt${N}\n"
    done
    hdr "$lv"
  done

  if ((done>=TOT)); then
    echo -e "${G}${B}Level $lv Complete!${N}"
    ((lv<9)) && { echo "Enter for Level $((lv+1))..."; read -r; LVL=$((lv+1)); QN=0; save; run "$LVL"; } \
             || echo -e "${G}${B}ALL COMPLETE - CLI MASTER${N}"
  else
    echo -e "${Y}Need $((TOT-done)) more without hints${N}"; echo "Enter to retry..."; read -r; run "$lv"
  fi
}

case "${1:-}" in
  [0-9]) LVL=$1 QN=0; save; run "$LVL";;
  r|reset) rm -f "$DATA"/*.json "$DATA/vi_mode"; echo "Reset.";;
  h|help|-h|--help) echo "cmd [0-9|n|reset|help] - CLI trainer. TAB=hint";;
  n|new) LVL=0 QN=0; save; run "$LVL";;
  "")
    load
    if [[ -f "$DATA/session.json" ]] && ((LVL > 0 || QN > 0)); then
      echo -n "Continue Level $LVL? [Y/n] "; read -r yn
      [[ "$yn" =~ ^[Nn] ]] && { LVL=0 QN=0; save; }
    fi
    run "$LVL";;
  *) echo "cmd help"; exit 1;;
esac
