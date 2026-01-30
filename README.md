# cmdchamp

CLI trainer with spaced repetition. Shell, security tools, infrastructure.

1000+ questions across 19 levels — fundamentals to privesc.

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
cmdchamp 11      # Start at level 11 (Git)
cmdchamp stats   # Show mastery stats
cmdchamp reset   # Clear all progress
```

## Levels

| Level | Focus |
|-------|-------|
| **Fundamentals** ||
| 0 | Shell basics: redirects, pipes, jobs, history, variables |
| 1 | Core tools: cat, ls, head, tail, tar, ln, chmod, wc, du |
| 2 | System admin: ping, df, free, top, systemctl, ip, users |
| 3 | tmux & screen: sessions, windows, panes, copy mode |
| 4 | Text search: grep, ripgrep, regex |
| 5 | File finding: find, fd, by name/size/time/type |
| 6 | Data processing: sort, uniq, cut, awk, ps, ss |
| 7 | String & arrays: parameter expansion, arrays |
| 8 | Control flow: if/else, loops, case, functions, traps |
| 9 | Batch ops: find -exec, xargs |
| 10 | Advanced regex: lookahead, sed, awk |
| **DevOps & Security** ||
| 11 | Git: branches, remotes, rebasing, stashing, bisect |
| 12 | Network tools: tshark, curl, wget, ssh tunnels, openssl |
| 13 | Network scanning: nmap, service detection, scripts |
| 14 | Local network & RF: wifi, smb, netcat, masscan |
| 15 | Hash cracking: hashcat, john, hydra, encoding |
| 16 | Forensics: strings, binwalk, exiftool, dd |
| 17 | Privilege escalation: SUID, GTFOBins, enumeration |
| 18 | Survival: one-liners, recovery, offline scenarios |

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
