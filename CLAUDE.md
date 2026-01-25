# cmd - CLI Command Trainer

Single-file bash script for learning CLI commands through flashcard-style drills.

## Architecture

- **Single file**: `cmd` (~314 lines bash 4.0+)
- **Data**: `~/.local/share/cmd/` (XDG compliant)
  - `session.json` - current level/question
  - `vi_mode` - saved vi preference (0 or 1)

## Question Format

```
"Prompt text|answer1|answer2|answer3"
```
- First field: what user sees
- Remaining fields: accepted answers (flag order normalized)
- Prompts MUST include all context (filenames, IPs, targets)

## Levels

| Level | Focus |
|-------|-------|
| Q0 | Shell fundamentals: `!!`, `!$`, `$$`, `$?`, brace expansion, process substitution |
| Q1 | Core tools (ls, cat, head, tail, cp) |
| Q2 | grep/rg text search |
| Q3 | find/fd file finding |
| Q4 | Sorting, piping, eza advanced |
| Q5 | find -exec, fd -x, sed/sd |
| Q6 | nmap scanning |
| Q7 | hashcat, john, hydra cracking |
| Q8 | Forensics (binwalk, volatility, strings) |
| Q9 | Web/WiFi (tshark, sqlmap, aircrack) |

## Key Functions

- `norm()` - Normalize flags for comparison (-la == -al == -a -l)
- `check()` - Check input against pipe-separated answers
- `draw()` - Render input line with vi mode colors
- `hdr()/bar()` - UI header and progress bar
- `demo()` - Safe sandbox execution of correct answers
- `run()` - Main game loop

## User Settings

| Env Var | Purpose |
|---------|---------|
| `CMD_VI=1/0` | Force vi mode on/off |
| `CMD_PROMPT=X` | Custom prompt char |

## Vi Mode

- Detected from: `~/.inputrc`, EDITOR/VISUAL containing "vi", `set -o vi`
- Prompt color: white=insert, red=normal
- First run asks preference, saved to `$DATA/vi_mode`

### Keybindings

| Key | Action |
|-----|--------|
| `i/a/A/I` | Insert at cursor/after/end/start |
| `s/S` | Substitute char/line |
| `h/l` | Left/right |
| `0/$` | Line start/end |
| `w/b/e` | Word forward/back/end |
| `x/X` | Delete char at/before cursor |
| `r` | Replace single char |
| `D/C` | Delete/change to end of line |
| `dd/dw/db/d$/d0` | Delete line/word fwd/word back/to end/to start |
| `cc/cw/cb/c$/c0` | Change (delete + insert mode) variants |

## Coding Guidelines

- Keep single-file, no external dependencies except jq/shuf
- Prompts must be unambiguous (include ALL filenames/args)
- Test with `bash -n cmd` before committing
- Both POSIX (grep, find, sed) and modern (rg, fd, sd) answers accepted
- Dangerous commands skipped in demo (nmap, hydra, dd, rm, etc.)

## Commands

```bash
./cmd         # Resume from last position
./cmd 3       # Start at level 3
./cmd reset   # Clear all progress + vi preference
./cmd help    # Show usage
```
