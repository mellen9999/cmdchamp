# cmdchamp

Bash CLI trainer — 30 levels from `ls` to privilege escalation.

![demo](demo.gif)

Every question asks you to type a real command — get instant feedback, move on. Many run against real files in the sandbox, and all accept multiple valid syntaxes (`sort -u` or `sort | uniq`). Tab toggles the manpage when you need a reference, and the order is randomized each run so you can't memorize it. Mastery tracks what you know: get a question right twice to master it, miss it and it demotes so it comes back sooner. A 5-answer streak triggers fire mode — a banner that runs until you miss.

Each level ends with a boss round — no manpages, 30s timer, 4/5 to pass. Fail and you can retry the boss immediately or go back to practice. Beat all 30 and **challenge mode** unlocks — the endgame gauntlet: insane multi-command chains that compose the tools from across the whole game into one pipeline. 30s each, one life, no manpages, your best score is the record. Every chain is graded on its real output in the sandbox, so *any* correct pipeline passes — and the questions are freshly parameterized each run (delimiter, sort direction, aggregate, transform), so it never plays the same twice. First run includes a short tutorial and a placement test that lets you skip levels you already know.

With [bubblewrap](https://github.com/containers/bubblewrap), commands run in a real sandboxed filesystem and are graded on their actual output. Without it — and for the network/root/pentest tools of levels 24-30, which can't safely run — answers are text-matched instead. Search levels (16-17) accept both `rg`/`fd` and `grep`/`find` syntax. Vi line editing built in.

## Install

**Arch (AUR):**

```bash
paru -S cmdchamp   # or: yay -S cmdchamp
```

**Anywhere (single file):**

```bash
mkdir -p ~/.local/bin && curl -sL https://raw.githubusercontent.com/mellen9999/cmdchamp/main/cmdchamp -o ~/.local/bin/cmdchamp && chmod +x ~/.local/bin/cmdchamp
```

Add `~/.local/bin` to PATH if needed: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc`

**Or clone:**

```bash
git clone https://github.com/mellen9999/cmdchamp.git
cd cmdchamp && make install
```

**Requires:** bash 4.4+, coreutils, awk

**macOS:** Ships with bash 3.2 — install bash 4.4+ first: `brew install bash`

**Optional:** [bubblewrap](https://github.com/containers/bubblewrap) (`bwrap`) for sandbox mode (Linux only) — most desktop distros include it. Without it, answers are text-matched only

**Accessibility:** Honors `NO_COLOR` and `TERM=dumb`. Layout adapts to `COLUMNS` / `tput cols`. Mastery bars carry both color and a `✓` / `~` / `x` symbol — readable without color.

**Terminals:** Runs on real serial terminals, not just emulators. cmdchamp probes what the terminal can actually display and picks one of three render tiers — unicode, DEC ACS line-drawing, or pure ASCII — so frames stay intact on a VT100/VT220/VT320/VT420 or Wyse. On a monochrome screen, color distinctions are re-encoded as bold/reverse. Force a tier with `CMDCHAMP_ASCII=1` or `CMDCHAMP_UNICODE=1`. `./test_terminals.sh` verifies it.

## Usage

```bash
cmdchamp                # Launch the game menu
cmdchamp --no-sandbox   # Disable sandbox (text-match only)
cmdchamp reset          # Clear all progress
cmdchamp test           # Run self-tests
cmdchamp version        # Print version
cmdchamp help           # Show help
```

The menu holds continue, new game, scenarios, challenge mode, stats, and options. Hotkeys 1–7 jump straight to an item; `j`/`k` or arrows move; Enter selects.

## Levels

| # | Name | Focus |
|---|------|-------|
| | **Fundamentals** | |
| 1 | First Steps | pwd, ls, echo, cd, mkdir |
| 2 | File Basics | cp, mv |
| 3 | Save Your Work | >, >>, tee |
| 4 | Reading Files | cat, head, tail, less |
| 5 | Basic Pipes | pipes, grep, wc, sort, uniq |
| 6 | Input & Here-Strings | <, <<<, tr, cut, rev, bc |
| 7 | Error Handling | 2>, 2>&1, &>, /dev/null |
| 8 | Logic Gates | &&, \|\| |
| 9 | Variables | `$VAR`, assignment, expansion |
| 10 | Special Variables | `$$`, `$?`, `$!`, `$#`, `$@`, `$0` |
| 11 | Job Control | bg, fg, jobs, &, Ctrl+Z |
| 12 | Test Conditions | -f, -d, -z, -n, -eq, -lt |
| 13 | Core File Tools | cp, mv, ln, chmod, du, tar, diff |
| 14 | System Admin | ping, df, free, ss, systemctl, ip |
| 15 | Multiplexers | tmux: sessions, windows, panes |
| 16 | Text Search | grep, ripgrep, regex |
| 17 | File Finding | find, fd, by name/size/time/type |
| 18 | Data Processing | sort, uniq, cut, awk, tr, comm |
| 19 | String & Arrays | parameter expansion, arrays |
| 20 | Control Flow | if/else, loops, case, functions |
| 21 | Batch Ops | find -exec, xargs, sed -i, crontab |
| 22 | Advanced Regex | lookahead, sed, awk |
| | **DevOps & Security** | |
| 23 | Git | branches, remotes, rebasing, stashing, bisect |
| 24 | Network Tools | tshark, curl, jq, ssh tunnels, openssl, SMB |
| 25 | Network Scanning | nmap, service detection, scripts |
| 26 | WiFi & RF | aircrack-ng, netcat, tcpdump, wireless recon |
| 27 | Hash Cracking | hashcat, john, hydra, encoding |
| 28 | Forensics | strings, readelf, binwalk, volatility, exiftool |
| 29 | Privilege Escalation | SUID, GTFOBins, enumeration |
| 30 | ROOT | emergency recovery, chroot, offline survival |

## Scenarios

Multi-step sandbox challenges — state persists between steps. Available from the **Scenarios** menu once you clear the unlock boss.

| # | Name | Unlocks at | Steps |
|---|------|-----------|-------|
| 1 | Permission Lockout | L13 boss | 6 |
| 2 | Archive & Extract | L13 boss | 6 |
| 3 | Find the Needle | L16 boss | 7 |
| 4 | Messy CSV | L18 boss | 4 |
| 5 | The Incident | L18 boss | 5 |
| 6 | The Broken Deploy | L21 boss | 7 |
| 7 | Log Emergency | L21 boss | 5 |
| 8 | Config Surgery | L21 boss | 5 |
| 9 | Git Rescue | L23 boss | 6 |
| 10 | Batch Refactor | L21 boss | 6 |
| 11 | Forensic Sweep | L22 boss | 6 |

## Placement test

After the first-run tutorial, you're asked if you want to take the placement test to skip ahead. Accept and it runs 2 questions per level, 30s each, no manpages. Miss one and that's your starting level.

## Easter eggs

8 hidden achievements. The Stats screen shows how many you've found.

## Controls

| Key | Action |
|-----|--------|
| Enter | Submit answer |
| Tab | Toggle manpage |
| Ctrl+d | Quit (session summary) |
| Esc | Vi normal mode |
| ? | All keybindings (normal mode) |

## Data

Progress saves to `${XDG_DATA_HOME:-~/.local/share}/cmdchamp/`.

## License

MIT
