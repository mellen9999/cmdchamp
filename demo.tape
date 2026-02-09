# cmdchamp demo - CLI trainer showcase
Output demo.gif

Require bash

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 700
Set Framerate 24
Set TypingSpeed 1ms
Set Padding 20

# Hidden setup: deterministic version + clean state
Hide
Type "rm -rf ~/.local/share/cmdchamp"
Enter
Sleep 300ms
Type "export PATH=/tmp:$PATH"
Enter
Sleep 300ms
Type "export PS1='$ '"
Enter
Sleep 200ms
Type "clear"
Enter
Sleep 500ms
Show

# Launch
Set TypingSpeed 60ms
Sleep 300ms
Type "cmdchamp n"
Enter
Sleep 2s

# ASCII banner - enter handle
Set TypingSpeed 100ms
Type "hacker"
Sleep 500ms
Enter
Sleep 3s

# Intro story - press to continue
Enter
Sleep 2.5s

# Tutorial - press to continue
Enter
Sleep 1.5s

# ── Q1: "Show current directory" → pwd ✓ ──
Set TypingSpeed 70ms
Sleep 500ms
Type "pwd"
Sleep 300ms
Enter
Sleep 1.5s
Enter
Sleep 1s

# ── Q2: "What directory?" → whoami ✗ then pwd ✓ ──
Sleep 300ms
Type "whoami"
Sleep 300ms
Enter
Sleep 2.5s
Enter
Sleep 1s
Type "pwd"
Sleep 300ms
Enter
Sleep 1.5s
Enter
Sleep 1s

# ── Q3: "Show files in current directory" → ls ✓ ──
Sleep 300ms
Type "ls"
Sleep 300ms
Enter
Sleep 1.5s
Enter
Sleep 1s

# ── Q4: "List all files including hidden" → Tab hint → ls -a → +0 ──
Sleep 300ms
Tab
Sleep 2.5s
Type "ls -a"
Sleep 300ms
Enter
Sleep 2s
Enter
Sleep 1s

# Session summary
Ctrl+D
Sleep 4s
