# cmdchamp

Pure bash CLI trainer — 29 levels from `ls` to privilege escalation.

![demo](demo.gif)

Questions randomize each run. Get one wrong and it comes back sooner — spaced repetition keeps weak spots in rotation. Each level ends with a boss fight (no hints, 4/5 to pass) that gates the next. Clear all 29 to unlock gauntlet and timed modes.

With bubblewrap installed, your answers execute in a sandbox against generated files. Without it, text-matched. Accepts both modern (`rg`, `fd`) and POSIX (`grep`, `find`) answers.

Full vi-style line editing with motions, operators, counts, and undo.

## Install

```bash
mkdir -p ~/.local/bin && curl -sL https://raw.githubusercontent.com/mellen9999/cmdchamp/main/cmdchamp -o ~/.local/bin/cmdchamp && chmod +x ~/.local/bin/cmdchamp
```

Add `~/.local/bin` to PATH if needed: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc`

**Or clone:**

```bash
git clone https://github.com/mellen9999/cmdchamp.git
./cmdchamp/cmdchamp
```

**Requires:** bash 4.3+, coreutils (shuf, md5sum), awk

**macOS:** Ships with bash 3.2 — install modern bash first: `brew install bash`

**Optional:** [bubblewrap](https://github.com/containers/bubblewrap) (`bwrap`) for sandbox mode (Linux only) — most desktop distros include it. Without it, answers are text-matched only

## Usage

```bash
cmdchamp                # Resume from last position
cmdchamp n              # Start fresh from level 0
cmdchamp 14             # Jump to level (password required if locked)
cmdchamp pass           # Show earned passwords
cmdchamp pass CODE      # Jump to level using password
cmdchamp stats          # Show mastery statistics
cmdchamp review         # Practice weak levels (< 80% mastery)
cmdchamp gauntlet       # 3 lives, escalating difficulty (post-ROOT)
cmdchamp timed          # Race the clock, default 120s (post-ROOT)
cmdchamp timed 60       # Timed mode: 60, 120, or 300 seconds
cmdchamp reset          # Clear all progress
cmdchamp --no-sandbox   # Disable sandbox (text-match only)
```

## Levels

| # | Name | Focus |
|---|------|-------|
| | **Fundamentals** | |
| 0 | First Steps | pwd, ls, echo, cd, mkdir |
| 1 | Save Your Work | >, >>, tee |
| 2 | Reading Files | cat, head, tail, less |
| 3 | Basic Pipes | pipes, grep, wc, sort, uniq |
| 4 | Input & Transform | <, <<<, here-strings, tr, cut, rev |
| 5 | Error Handling | 2>, 2>&1, &>, /dev/null |
| 6 | Logic Gates | &&, \|\| |
| 7 | Variables | `$VAR`, assignment, expansion |
| 8 | Special Variables | `$$`, `$?`, `$!`, `$#`, `$@`, `$0` |
| 9 | Job Control | bg, fg, jobs, &, Ctrl+Z |
| 10 | Test Conditions | -f, -d, -z, -n, -eq, -lt |
| 11 | Core File Tools | cp, mv, ln, chmod, du, tar, diff |
| 12 | System Admin | ping, df, free, ss, systemctl, ip |
| 13 | Multiplexers | tmux: sessions, windows, panes |
| 14 | Text Search | grep, ripgrep, regex |
| 15 | File Finding | find, fd, by name/size/time/type |
| 16 | Data Processing | sort, uniq, cut, awk, tr, comm |
| 17 | String & Arrays | parameter expansion, arrays |
| 18 | Control Flow | if/else, loops, case, functions |
| 19 | Batch Ops | find -exec, xargs, sed -i, crontab |
| 20 | Advanced Regex | lookahead, sed, awk |
| | **DevOps & Security** | |
| 21 | Git | branches, remotes, rebasing, stashing, bisect |
| 22 | Network Tools | tshark, curl, jq, ssh tunnels, openssl, SMB |
| 23 | Network Scanning | nmap, service detection, scripts |
| 24 | WiFi & RF | aircrack-ng, netcat, tcpdump, RTL-SDR |
| 25 | Hash Cracking | hashcat, john, hydra, encoding |
| 26 | Forensics | strings, readelf, binwalk, volatility, exiftool |
| 27 | Privilege Escalation | SUID, GTFOBins, enumeration |
| 28 | ROOT | emergency recovery, chroot, offline survival |

## Controls

| Key | Action |
|-----|--------|
| Enter | Submit answer |
| Tab | Show hint + manpage excerpt |
| Ctrl+d | Quit (session summary) |
| Esc | Vi normal mode |
| ? | All keybindings (normal mode) |

Vi normal mode supports full motions (`w b e f`), operators (`d c`), counts (`3w`), undo (`u`), and history (`k`/`j`). Press `?` for the complete list.

## Data

Progress stored in `${XDG_DATA_HOME:-~/.local/share}/cmdchamp/` (XDG compliant).

## License

MIT
