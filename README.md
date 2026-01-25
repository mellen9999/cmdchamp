# bashgym

CLI command trainer. Master shell commands through flashcard-style drills and spaced repetition.

151 questions across 10 levels—from basic shell syntax to security tools like nmap, hashcat, and volatility.

## Features

- **Spaced repetition** - Three tiers per question (copy → complete → recall), prioritizes weak spots
- **Mid-level resume** - Quit anytime, continue exactly where you left off
- **Vi keybindings** - Full vi-style editing with `?` for help
- **Tab hints** - Show answer + command explanations
- **Modern + POSIX** - Accepts both `rg`/`fd` and `grep`/`find` answers

## Install

**One-liner:**
```bash
mkdir -p ~/.local/bin && curl -sL https://raw.githubusercontent.com/mellen9999/bashgym/main/bashgym -o ~/.local/bin/bashgym && chmod +x ~/.local/bin/bashgym
```
Add `~/.local/bin` to PATH if not already: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc`

**Or clone:**
```bash
git clone https://github.com/mellen9999/bashgym.git
./bashgym/bashgym
```

Requires: bash 4.3+, coreutils (shuf, md5sum)

## Usage

```bash
bashgym         # Resume from last position (level + question)
bashgym n       # Start fresh from level 0
bashgym 3       # Start at level 3
bashgym stats   # Show mastery per level
bashgym reset   # Clear all progress
```

## Levels

| Level | Focus |
|-------|-------|
| 0 | Shell fundamentals: `!!`, `!$`, `$$`, brace expansion, process substitution |
| 1 | Core tools: ls, cat, head, tail, cp |
| 2 | Text search: grep, rg |
| 3 | File finding: find, fd |
| 4 | Sorting, piping, eza |
| 5 | find -exec, fd -x, sed/sd |
| 6 | nmap scanning |
| 7 | hashcat, john, hydra |
| 8 | Forensics: binwalk, volatility, strings |
| 9 | Web/WiFi: tshark, sqlmap, aircrack |

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

Progress stored in `~/.local/share/bashgym/` (XDG compliant).

## License

MIT
