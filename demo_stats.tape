# cmdchamp demo — segment 2: veteran stats, the full ls→ROOT ladder
# Rendered + concatenated with demo_play.tape by ./demo.sh
Output demo_stats.mp4

Require bash

Set Shell "bash"
Set FontSize 16
Set Width 1200
Set Height 960
Set Framerate 24
Set TypingSpeed 1ms
Set Padding 20

# Setup (hidden): a veteran profile — all 30 bosses beaten, mastery seeded across every level
Hide
Type `rm -rf /tmp/demo-xdg2 && mkdir -p /tmp/demo-xdg2/cmdchamp && export XDG_DATA_HOME=/tmp/demo-xdg2`
Enter
Type `printf 'PLAYER_NAME=hacker\nBOSS_BEATEN=30\nBEST_CHALLENGE=27\nDISKS_FOUND=1,2,3\nSC_DONE=1,2,3,4,5\nLAST_DECAY=99999999999\nOPT_VI=1\nOPT_SOUND=0\nOPT_ALTS=1\nPLACED_THROUGH=0\nPROFILE_VER=5\n' > /tmp/demo-xdg2/cmdchamp/profile`
Enter
Type `{ echo '#v1'; for lv in $(seq 30); do for n in $(seq 5); do t=2; [ $n -gt $(( (lv%3)+3 )) ] && t=1; echo "l${lv}q${n}|$t|$lv|99999999"; done; done; } > /tmp/demo-xdg2/cmdchamp/scores`
Enter
Type `cp cmdchamp /tmp/demo-cmd2 && chmod +x /tmp/demo-cmd2 && clear`
Enter

# Launch — menu now reads "ALL BOSSES DEFEATED", every mode unlocked
Set TypingSpeed 60ms
Type "/tmp/demo-cmd2"
Enter
Sleep 2.5s
Show
Sleep 2.2s

# Open Stats (no Continue → 1 New, 2 Scenarios, 3 Challenge, 4 Stats)
Type "4"
Sleep 5s
