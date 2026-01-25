# bashgym

CLI command trainer with flashcard-style drills. Learn shell commands through spaced repetition.

## Features

- **10 progressive levels** - Shell basics → security tools (nmap, hashcat, volatility)
- **Adaptive difficulty** - Three tiers per question: copy → complete → recall
- **Spaced repetition** - Prioritizes questions you struggle with
- **Vi keybindings** - Optional vi-style input with visual mode indicator
- **Tab hints** - Press TAB for answer + command explanations
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
bashgym         # Resume from last position
bashgym 3       # Start at level 3
bashgym stats   # Show mastery per level
bashgym reset   # Clear all progress
bashgym version # Show version
bashgym help    # Show usage
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
| Ctrl+n | Skip question (no penalty) |
| Enter | Submit answer |

Vi mode adds full navigation: `h/l/w/b/e/0/$`, delete: `x/X/D/dd/dw`, change: `C/cc/cw`, undo: `u`

## Data

Progress stored in `~/.local/share/bashgym/` (XDG compliant).

## License

MIT
