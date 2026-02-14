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

# Setup: exec into clean bash (rcfile does cleanup + clear)
Type "exec bash --rcfile /tmp/demo-bashrc"
Enter
Sleep 500ms

# Launch
Set TypingSpeed 60ms
Type "cmdchamp n"
Enter
Sleep 2s

# ASCII banner - enter handle
Set TypingSpeed 100ms
Type "hacker"
Sleep 400ms
Enter
Sleep 2.5s

# Intro story - press to continue
Enter
Sleep 1.5s

# Tutorial - press to continue
Enter
Sleep 1s

# ── Q1: pwd question → correct ──
Set TypingSpeed 70ms
Sleep 400ms
Type "pwd"
Sleep 200ms
Enter
Sleep 1.2s
Enter
Sleep 600ms

# ── Q2: pwd question → wrong (type ls), then correct ──
Sleep 300ms
Type "ls"
Sleep 200ms
Enter
Sleep 2s
Enter
Sleep 600ms
Type "pwd"
Sleep 200ms
Enter
Sleep 1.2s
Enter
Sleep 600ms

# ── Q3: ls question → Tab for manpage, then correct ──
Sleep 300ms
Tab
Sleep 2s
Type "ls"
Sleep 200ms
Enter
Sleep 1.2s
Enter
Sleep 600ms

# ── Q4: ls -a question → correct ──
Sleep 300ms
Type "ls -a"
Sleep 200ms
Enter
Sleep 1.5s

# Session summary
Ctrl+D
Sleep 3s
