# cmdchamp

The networks are dead. The sky is ash. Master the command line or be forgotten.

Pure bash CLI trainer. 1000+ questions across 29 levels — fundamentals to privilege escalation — with spaced repetition, sandbox execution, boss fights, and vi keybindings.

## Features

- **Spaced repetition** — Two-tier system (blank → recall), prioritizes weak spots
- **Sandbox execution** — Commands run in bubblewrap isolation against real files
- **Boss fights** — Named daemons gate each level. No hints. 4/5 to pass.
- **Fire mode** — 5-answer streak earns double points and forces pure recall
- **Dynamic generation** — Variable pools make every session different
- **Vi keybindings** — Full vi-style line editing with motions, operators, and undo stack
- **Mid-level resume** — Quit anytime, continue exactly where you left off
- **Tab hints** — Reveals answer + inline manpage explanations
- **Modern + POSIX** — Accepts both `rg`/`fd` and `grep`/`find` answers

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

**Optional:** [bubblewrap](https://github.com/containers/bubblewrap) for sandbox mode — without it, answers are text-matched only

## Usage

```bash
cmdchamp                # Resume from last position
cmdchamp n              # Start fresh from level 0
cmdchamp 14             # Jump to level (password required if locked)
cmdchamp pass           # Show earned passwords
cmdchamp pass CODE      # Jump to level using password
cmdchamp stats          # Show mastery statistics
cmdchamp reset          # Clear all progress
cmdchamp cleanup        # Deduplicate score file
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
| 4 | Input & Transform | <, <<<, here-strings, tr, sed |
| 5 | Error Handling | 2>, 2>&1, &>, /dev/null |
| 6 | Logic Gates | &&, \|\| |
| 7 | Variables | $VAR, assignment, expansion |
| 8 | Special Variables | $$, $?, $!, $#, $@, $0 |
| 9 | Job Control | bg, fg, jobs, &, Ctrl+Z |
| 10 | Test Conditions | -f, -d, -z, -n, -eq, -lt |
| 11 | Core File Tools | cp, ln, chmod, wc, du, file, tar |
| 12 | System Admin | ping, df, free, ss, systemctl, ip |
| 13 | Multiplexers | tmux, screen: sessions, windows, panes |
| 14 | Text Search | grep, ripgrep, regex |
| 15 | File Finding | find, fd, by name/size/time/type |
| 16 | Data Processing | sort, uniq, cut, awk, ps, ss |
| 17 | String & Arrays | parameter expansion, arrays |
| 18 | Control Flow | if/else, loops, case, functions |
| 19 | Batch Ops | find -exec, xargs |
| 20 | Advanced Regex | lookahead, sed, awk |
| | **DevOps & Security** | |
| 21 | Git | branches, remotes, rebasing, stashing, bisect |
| 22 | Network Tools | tshark, curl, wget, ssh tunnels, openssl |
| 23 | Network Scanning | nmap, service detection, scripts |
| 24 | WiFi & RF | aircrack-ng, netcat, masscan |
| 25 | Hash Cracking | hashcat, john, hydra, encoding |
| 26 | Forensics | strings, binwalk, exiftool, dd |
| 27 | Privilege Escalation | SUID, GTFOBins, enumeration |
| 28 | ROOT | emergency recovery, chroot, offline survival |

## Progression

Each level ends with a **boss fight** — a named daemon with no hints. Score 4/5 to defeat the boss and earn a **password** that unlocks the next level.

Hit a 5-answer streak for **fire mode**: double points, forced pure recall.

## Controls

| Key | Action |
|-----|--------|
| Enter | Submit answer |
| Tab | Toggle hint + command explanation |
| Ctrl+d | Quit (saves position) |
| Esc | Enter vi normal mode |
| ? | Show all keybindings (normal mode) |

**Vi normal mode:**

| Key | Action |
|-----|--------|
| `h` `l` | Move left/right |
| `k` `j` / ↑↓ | History prev/next |
| `w` `b` | Word forward/back |
| `f` `F` `t` `T` + char | Find char |
| `0` `$` / `gg` `G` | Line start/end |
| `x` `X` | Delete char forward/back |
| `dw` `db` `dd` / `D` | Delete word/back/line/to-end |
| `cw` `cb` `cc` / `C` | Change word/back/line/to-end |
| `r` + char | Replace char |
| `s` `S` | Substitute char/line |
| `i` `a` `I` `A` | Insert at/after cursor, line start/end |
| `u` | Undo (multi-level stack) |
| `[num]cmd` | Repeat (e.g. `3w`, `2x`) |
| `q` | Quit |

## Data

Progress stored in `${XDG_DATA_HOME:-~/.local/share}/cmdchamp/` (XDG compliant).

## License

MIT
