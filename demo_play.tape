# cmdchamp demo — segment 1: the core practice loop (level 1)
# Rendered + concatenated with demo_stats.tape by ./demo.sh
Output demo_play.mp4

Require bash

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 960
Set Framerate 24
Set TypingSpeed 1ms
Set Padding 20

# Setup: seeded profile + session, deterministic question order (hidden)
Hide
Type `rm -rf /tmp/demo-xdg && mkdir -p /tmp/demo-xdg/cmdchamp && printf 'PLAYER_NAME=hacker\nBOSS_BEATEN=0\nBEST_CHALLENGE=0\nDISKS_FOUND=\nSC_DONE=\nLAST_DECAY=99999999999\nOPT_VI=1\nOPT_SOUND=0\nOPT_ALTS=1\nPLACED_THROUGH=0\nPROFILE_VER=5\n' > /tmp/demo-xdg/cmdchamp/profile && printf '{"level":1,"qi":3}' > /tmp/demo-xdg/cmdchamp/session.json && export XDG_DATA_HOME=/tmp/demo-xdg`
Enter
Type `cp cmdchamp /tmp/demo-cmd && chmod +x /tmp/demo-cmd && sed -i 's/^_run_loop() {/_run_loop() { RANDOM=42/' /tmp/demo-cmd && clear`
Enter

# Launch — main menu shows "Continue Level 1 Q4" preselected
Set TypingSpeed 60ms
Type "/tmp/demo-cmd"
Enter
Sleep 2.5s
Show

Sleep 1.2s
Enter
Sleep 1.5s

# ── Q4: "Print: hello hello hello" → correct ──
Set TypingSpeed 50ms
Sleep 400ms
Type "echo hello hello hello"
Sleep 200ms
Enter
Sleep 1.2s
Enter
Sleep 600ms

# ── Q5: "Delete todo.txt" → wrong, then correct ──
Sleep 300ms
Type "rm"
Sleep 200ms
Enter
Sleep 1.8s
Enter
Sleep 600ms
Type "rm todo.txt"
Sleep 200ms
Enter
Sleep 1.2s
Enter
Sleep 600ms

# ── Q6: "Create directory" → Tab manpage, then correct ──
Sleep 300ms
Tab
Sleep 2s
Type "mkdir tools"
Sleep 200ms
Enter
Sleep 1.2s
Enter
Sleep 600ms

# ── Q7: "Delete temp and everything in it" → correct ──
Sleep 300ms
Type "rm -r temp"
Sleep 200ms
Enter
Sleep 2s
