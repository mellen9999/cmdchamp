# cmdchamp demo - seamless loop, starts mid-gameplay
Output demo.gif

Require bash

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 700
Set Framerate 24
Set TypingSpeed 1ms
Set Padding 20
Set LoopOffset 0

# Setup: seeded profile, skip to gameplay (hidden)
Hide
Type `rm -rf /tmp/demo-xdg && mkdir -p /tmp/demo-xdg/cmdchamp && printf 'PLAYER_NAME=hacker\nBOSS_BEATEN=0\nBEST_CHALLENGE=0\nDISKS_FOUND=nightowl\nSC_DONE=\nLAST_DECAY=99999999999\nOPT_VI=1\nOPT_SOUND=0\nOPT_ALTS=1\nPROFILE_VER=4\n' > /tmp/demo-xdg/cmdchamp/profile && printf '{"level":1,"qi":3}' > /tmp/demo-xdg/cmdchamp/session.json && export XDG_DATA_HOME=/tmp/demo-xdg`
Enter
Sleep 300ms
# Copy and patch for deterministic questions
Type `cp cmdchamp /tmp/demo-cmd && chmod +x /tmp/demo-cmd && sed -i 's/^_run_loop() {/_run_loop() { RANDOM=42/' /tmp/demo-cmd && clear`
Enter
Sleep 300ms
Type "bash /tmp/demo-cmd"
Enter
Sleep 2.5s
# Continue (first menu item)
Enter
Sleep 2s
# Q1: answer hidden so GIF starts clean on Q2
Set TypingSpeed 1ms
Type "cd .."
Enter
Sleep 1.5s
Enter
# Wait for Q2 screen to fully render (past the flash)
Sleep 1.5s
Show

# ── Q2: "Create nested directories src/assets" → wrong then correct ──
Set TypingSpeed 70ms
Sleep 800ms
Type "mkdir src/assets"
Sleep 300ms
Enter
Sleep 1.8s
Enter
Sleep 1s
Type "mkdir -p src/assets"
Sleep 300ms
Enter
Sleep 1s
Enter
Sleep 1s

# ── Q3: "Print hello world" → Tab manpage, then correct ──
Sleep 600ms
Tab
Sleep 2.5s
Set TypingSpeed 60ms
Type "echo hello world"
Sleep 300ms
Enter
Sleep 1s
Enter
Sleep 1s

# ── Q4: "Change to src directory" → correct ──
Set TypingSpeed 70ms
Sleep 600ms
Type "cd src"
Sleep 300ms
Enter
Sleep 1s
Enter
Sleep 1s

# ── Q5: "Go to filesystem root (/)" → correct ──
Sleep 600ms
Type "cd /"
Sleep 300ms
Enter
Sleep 1s
# Don't press Enter — freeze on the correct feedback
# When it loops, jumps back to Q2 prompt (both are static game screens)
Sleep 2s
