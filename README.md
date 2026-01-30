# cmdchamp

CLI trainer with spaced repetition. Shell, security tools, infrastructure.

1000+ questions across 18 levels — fundamentals to privesc.

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
cmdchamp 10      # Start at level 10 (Git)
cmdchamp stats   # Show mastery stats
cmdchamp reset   # Clear all progress
```

## Levels

| Level | Focus |
|-------|-------|
| **Shell Fundamentals** ||
| 0 | Redirects, pipes, jobs, history, variables, expansion |
| 1 | Core tools: cat, ls, head, tail, tar, ln, chmod, wc, du |
| 2 | tmux & screen: sessions, windows, panes, copy mode |
| 3 | Text search: grep, ripgrep, regex |
| 4 | File finding: find, fd, by name/size/time/type |
| 5 | Data processing: sort, uniq, cut, awk, ps, ss, ip |
| 6 | String & arrays: parameter expansion, arrays |
| 7 | Control flow: if/else, loops, case, functions, traps |
| 8 | Advanced regex: lookahead, sed, awk |
| 9 | Batch ops: find -exec, xargs, systemctl, journalctl |
| **Security & DevOps** ||
| 10 | Git: branches, remotes, rebasing, stashing, bisect |
| 11 | Network tools: tshark, curl, wget, ssh tunnels, openssl |
| 12 | Network scanning: nmap, service detection, scripts |
| 13 | Local network & RF: wifi, smb, netcat, masscan |
| 14 | Hash cracking: hashcat, john, hydra, encoding |
| 15 | Forensics: strings, binwalk, volatility, disk imaging |
| 16 | Privilege escalation: SUID, GTFOBins, enumeration |
| 17 | Survival: one-liners, recovery, offline scenarios |

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
