# cmdchamp

CLI trainer with spaced repetition. Shell, security tools, infrastructure.

1000+ questions across 29 levels — fundamentals to privesc.

## Features

- **Spaced repetition** - Three tiers per question (copy → complete → recall), prioritizes weak spots
- **Dynamic generation** - Questions use variable pools, every session is different
- **Mid-level resume** - Quit anytime, continue exactly where you left off
- **Vi keybindings** - Full vi-style editing with `?` for help
- **Tab hints** - Show answer + command explanations
- **Modern + POSIX** - Accepts both `rg`/`fd` and `grep`/`find` answers

## Install

**One-liner:**
```bash
mkdir -p ~/.local/bin && curl -sL https://raw.githubusercontent.com/mellen9999/cmdchamp/main/cmdchamp -o ~/.local/bin/cmdchamp && chmod +x ~/.local/bin/cmdchamp
```
Add `~/.local/bin` to PATH if not already: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc`

**Or clone:**
```bash
git clone https://github.com/mellen9999/cmdchamp.git
./cmdchamp/cmdchamp
```

Requires: bash 4.3+, coreutils (shuf, md5sum)

## Usage

```bash
cmdchamp         # Resume from last position (level + question)
cmdchamp n       # Start fresh from level 0
cmdchamp 21      # Start at level 21 (Git)
cmdchamp stats   # Show mastery stats
cmdchamp reset   # Clear all progress
```

## Levels

| Level | Focus |
|-------|-------|
| **Fundamentals** ||
| 0 | First Commands: pwd, ls, echo, cd, mkdir |
| 1 | Save Output: >, >>, tee |
| 2 | Read Files: cat, head, tail, less |
| 3 | Basic Pipes: pipes, grep, wc, sort, uniq |
| 4 | Input Redirection: <, <<<, here-strings |
| 5 | Error Redirection: 2>, 2>&1, &>, /dev/null |
| 6 | Logic Operators: &&, \|\| |
| 7 | Job Control: bg, fg, jobs, &, Ctrl+Z |
| 8 | Variables: $VAR, assignment, expansion |
| 9 | Special Variables: $$, $?, $!, $#, $@, $0 |
| 10 | Test Operators: -f, -d, -z, -n, -eq, -lt |
| 11 | Core Tools: cp, ln, chmod, wc, du, file, tar |
| 12 | System Admin: ping, df, free, top, systemctl, ip |
| 13 | tmux & Screen: sessions, windows, panes, copy mode |
| 14 | Text Search: grep, ripgrep, regex |
| 15 | File Finding: find, fd, by name/size/time/type |
| 16 | Data Processing: sort, uniq, cut, awk, ps, ss |
| 17 | String & Arrays: parameter expansion, arrays |
| 18 | Control Flow: if/else, loops, case, functions |
| 19 | Batch Ops: find -exec, xargs |
| 20 | Advanced Regex: lookahead, sed, awk |
| **DevOps & Security** ||
| 21 | Git: branches, remotes, rebasing, stashing, bisect |
| 22 | Network Tools: tshark, curl, wget, ssh tunnels, openssl |
| 23 | Network Scanning: nmap, service detection, scripts |
| 24 | Local Network & RF: wifi, smb, netcat, masscan |
| 25 | Hash Cracking: hashcat, john, hydra, encoding |
| 26 | Forensics: strings, binwalk, exiftool, dd |
| 27 | Privilege Escalation: SUID, GTFOBins, enumeration |
| 28 | Survival: one-liners, recovery, offline scenarios |

## Controls

| Key | Action |
|-----|--------|
| Tab | Toggle hint + explanations |
| Ctrl+n | Skip question |
| Ctrl+d / q | Quit (saves position) |
| ? | Show all keybindings (vi normal mode) |
| Enter | Submit answer |

Vi mode: `hjkl`, `wb`, `fFtT`, `0$`, `x/X`, `dw/db/dd`, `cw/cb/cc`, `r`, `s/S`, `u`, `?`, number prefixes (`3w`, `2db`)

## Data

Progress stored in `~/.local/share/cmdchamp/` (XDG compliant).

## License

MIT
