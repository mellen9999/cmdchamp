#!/usr/bin/env bash
# Legacy-terminal conformance test.
#
# Renders every screen cmdchamp can draw under a range of TERM types and asserts the
# byte stream is something that terminal can actually display. This is what stands in
# for owning a VT320: a real one would show the failures below as screen confetti.
#
#   ./test_terminals.sh          run all checks
#   ./test_terminals.sh -v       also dump offending bytes
set -uo pipefail
cd "$(dirname "$0")" || exit 1

VERBOSE=0; [[ ${1:-} == -v ]] && VERBOSE=1
pass=0; fail=0
B=$'\e[1m'; G=$'\e[32m'; R=$'\e[31m'; D=$'\e[2m'; N=$'\e[0m'

ok()   { ((pass++)); printf '  %s+%s %s\n' "$G" "$N" "$1"; }
bad()  { ((fail++)); printf '  %sx%s %s\n    %s%s%s\n' "$R" "$N" "$1" "$D" "$2" "$N"; }

# Terminals that predate UTF-8 entirely. Anything above 0x7f reaching one of these is
# rendered as one garbage glyph per byte.
LEGACY=(vt100 vt102 vt220 vt320 vt420 wy60 ansi dumb)
# Of those, the ones with no colour at all — a green or amber CRT.
MONO=(vt100 vt102 vt220 vt320 vt420)

render() { # $1=TERM  -> full visual surface on stdout
  env -u LANG -u LC_ALL -u LC_CTYPE TERM="$1" CMDCHAMP_DEV=1 \
    ./cmdchamp preview 2>/dev/null
}

printf '%slegacy terminal conformance%s\n\n' "$B" "$N"

# ── 1. no 8-bit bytes reach a 7-bit terminal ──
for t in "${LEGACY[@]}"; do
  out=$(render "$t")
  n=$(printf '%s' "$out" | LC_ALL=C grep -c $'[\x80-\xff]')
  if ((n == 0)); then ok "$t: no 8-bit bytes"
  else
    detail="$n lines carry bytes >0x7f"
    ((VERBOSE)) && detail+=$'\n    '$(printf '%s' "$out" | LC_ALL=C grep -n $'[\x80-\xff]' | head -3 | cut -c1-90)
    bad "$t: 8-bit bytes leak" "$detail"
  fi
done

# ── 2. monochrome terminals get no colour SGR ──
# 30-37/90-97 set foreground colour. A VT320 has one phosphor; emitting these means the
# UI is encoding meaning in a channel the screen cannot show.
echo
for t in "${MONO[@]}"; do
  out=$(render "$t")
  n=$(printf '%s' "$out" | grep -oP '\x1b\[[0-9;]*m' | grep -cP '\[(3[0-7]|9[0-7])[;m]')
  if ((n == 0)); then ok "$t: no colour SGR (mono-safe)"
  else bad "$t: emits $n colour codes" "monochrome screen cannot render these"; fi
done

# ── 3. NO_COLOR is honoured everywhere, including the manpage panel ──
echo
out=$(NO_COLOR=1 TERM=xterm-256color CMDCHAMP_DEV=1 ./cmdchamp preview 2>/dev/null)
n=$(printf '%s' "$out" | grep -oP '\x1b\[[0-9;]*m' | wc -l)
((n == 0)) && ok "NO_COLOR: preview clean" || bad "NO_COLOR: $n SGR sequences leaked" "NO_COLOR must suppress all styling"

# The manpage bodies hold their own inline SGR codes; render one directly.
mp=$(mktemp) || exit 1
trap 'rm -f "$mp"' EXIT
end=$(grep -n '^_mp_show() {' cmdchamp | cut -d: -f1)
sed -n "1,$((end + 5))p" cmdchamp > "$mp"
printf '\n_EBUF=""; _mp_show grep; printf "%%s" "$_EBUF"\n' >> "$mp"
for mode in "NO_COLOR=1" "TERM=dumb"; do
  n=$(env $mode bash "$mp" 2>/dev/null | grep -oP '\x1b\[[0-9;]*m' | wc -l)
  ((n == 0)) && ok "manpage panel: $mode clean" || bad "manpage panel: $mode leaked $n codes" "inline SGR in MANPAGE data is not being remapped"
done
n=$(env -u LANG -u LC_ALL TERM=vt320 bash "$mp" 2>/dev/null | LC_ALL=C grep -c $'[\x80-\xff]')
((n == 0)) && ok "manpage panel: vt320 is 7-bit" || bad "manpage panel: vt320 8-bit leak" "$n lines"

# ── 4. no game screen overflows 80 columns ──
# Legacy terminals are 80 wide and wrap hard; a long line destroys the frame below it.
# The LEVELS & BOSSES block is skipped: it is a developer dump that prints level name,
# boss name, flavour and prompt+answer on one line, none of which the player ever sees
# together. Every other section is a real screen.
echo
for t in vt320 dumb; do
  out=$(render "$t")
  over=$(printf '%s\n' "$out" \
    | awk '/LEVELS & BOSSES/{skip=1} /BOSS SPLASH/{skip=0} !skip' \
    | sed $'s/\e\[[0-9;]*[a-zA-Z]//g; s/\e[()][A-B0]//g' \
    | awk 'length > 80 {c++} END {print c+0}')
  ((over == 0)) && ok "$t: every screen fits 80 columns" || bad "$t: $over lines exceed 80 columns" "these will wrap and shear the frame"
done

# ── 4b. prompt wrapping holds at 80 columns ──
# 19 of the 1265 prompts are longer than an 80-column line, so qdisp wraps rather than
# letting the terminal hard-wrap mid-word. Test the wrapper itself: it is what makes
# every prompt fit, including any added later.
echo
wrapsrc=$(mktemp) || exit 1
trap 'rm -f "$mp" "$wrapsrc"' EXIT
qd=$(grep -n '^_QD_KEY=' cmdchamp | cut -d: -f1)
sed -n "1,$((qd - 1))p" cmdchamp > "$wrapsrc"
cat >> "$wrapsrc" <<'PROBE'
fails=0
for w in 80 72 40; do
  for s in \
    "Capture handshake on wlp3s0mon from AP A1:B2:C3:D4:E5:F6 channel 11, write to capture and show only handshake frames" \
    "Count lines in ${W}a-very-long-file-name-goes-here.csv${C} - just the number, no filename at all thank you" \
    "short one" "supercalifragilisticexpialidociousandthensomemoretomakeitlongerthaneightycolumnswide tail"; do
    _wrap "$s" "$w"
    while IFS= read -r ln; do
      _strip_ansi "$ln"
      # A single unbreakable word may exceed the width; nothing can be done about that.
      [[ ${REPLY} == *' '* ]] && ((${#REPLY} > w)) && ((fails++))
    done <<< "$REPLY"
  done
done
echo "$fails"
PROBE
n=$(env -u LANG -u LC_ALL TERM=vt320 bash "$wrapsrc" 2>/dev/null | tail -1)
[[ $n == 0 ]] && ok "_wrap: no wrapped line exceeds its width" || bad "_wrap: $n over-width lines" "prompts will hard-wrap mid-word"

# ── 4c. the WHOLE prompt corpus renders clean on a VT ──
# 4b proves the wrapper; this proves the content. Every one of the ~1266 level and
# scenario prompts is pushed through the real _ascii_fold → _wrap pipeline (via the
# promptdump dev command) under TERM=vt320, then checked for the two things that shear
# a legacy frame: an 8-bit byte, or a wrapped line past 80 columns. A prompt that
# hard-codes a raw → or ≤ instead of the _G* glyph var, or that runs long, fails here.
echo
dump=$(env -u LANG -u LC_ALL -u LC_CTYPE TERM=vt320 CMDCHAMP_DEV=1 ./cmdchamp promptdump 2>/dev/null)
if [[ -z $dump ]]; then
  bad "prompt corpus: promptdump produced nothing" "dev command missing or errored"
else
  hi=$(printf '%s' "$dump" | LC_ALL=C grep -c $'[\x80-\xff]')
  ((hi == 0)) && ok "prompt corpus: every prompt is 7-bit on vt320" \
    || { detail="$hi wrapped lines carry bytes >0x7f"
         ((VERBOSE)) && detail+=$'\n    '$(printf '%s' "$dump" | LC_ALL=C grep -n $'[\x80-\xff]' | head -3 | cut -c1-90)
         bad "prompt corpus: 8-bit bytes leak" "$detail"; }
  over=$(printf '%s\n' "$dump" \
    | sed $'s/\e\[[0-9;]*[a-zA-Z]//g; s/\e[()][A-B0]//g' \
    | awk '/ / && length > 80 {c++} END {print c+0}')   # unbreakable single words can't wrap
  ((over == 0)) && ok "prompt corpus: every wrapped prompt fits 80 columns" \
    || bad "prompt corpus: $over wrapped lines exceed 80 columns" "these hard-wrap and shear the frame"
fi

# ── 4d. the WHOLE manpage corpus renders clean on a VT ──
# Tab pops a manpage panel. It's the densest screen and, unlike prompts, it does NOT
# wrap — the column alignment can't survive reflow — so every body must fit 80 as
# authored. Only `grep` was ever checked before; this renders all ~130 bodies through
# the real _mp_show path under vt320 and asserts 7-bit + inside 80 columns.
echo
mpdump=$(env -u LANG -u LC_ALL -u LC_CTYPE TERM=vt320 CMDCHAMP_DEV=1 ./cmdchamp mpdump 2>/dev/null)
if [[ -z $mpdump ]]; then
  bad "manpage corpus: mpdump produced nothing" "dev command missing or errored"
else
  hi=$(printf '%s' "$mpdump" | LC_ALL=C grep -c $'[\x80-\xff]')
  ((hi == 0)) && ok "manpage corpus: every body is 7-bit on vt320" \
    || bad "manpage corpus: 8-bit bytes leak" "$hi panel lines carry bytes >0x7f"
  over=$(printf '%s\n' "$mpdump" \
    | sed $'s/\e\[[0-9;]*[a-zA-Z]//g; s/\e[()][A-B0]//g' \
    | awk 'length > 80 {c++} END {print c+0}')
  ((over == 0)) && ok "manpage corpus: every body fits 80 columns" \
    || { detail="$over panel lines exceed 80 columns — Tab shears the frame"
         ((VERBOSE)) && detail+=$'\n    '$(printf '%s\n' "$mpdump" | sed $'s/\e\[[0-9;]*[a-zA-Z]//g' | awk 'length>80{print length": "$0}' | head -5 | cut -c1-90)
         bad "manpage corpus: $over lines over 80" "$detail"; }
fi

# ── 4e. the real Tab panel renders clean for every answer ──
# §4d checks raw manpage bodies; this drives explain() with every level and scenario
# answer — the exact panel a player sees on Tab — so it also covers EXP lines and
# escape legends and any body+EXP combination. An over-long EXP (e.g. a redirection
# hint) that shears a common question fails here.
echo
paneldump=$(env -u LANG -u LC_ALL -u LC_CTYPE TERM=vt320 CMDCHAMP_DEV=1 ./cmdchamp paneldump 2>/dev/null)
if [[ -z $paneldump ]]; then
  bad "Tab panel: paneldump produced nothing" "dev command missing or errored"
else
  hi=$(printf '%s' "$paneldump" | LC_ALL=C grep -c $'[\x80-\xff]')
  ((hi == 0)) && ok "Tab panel: every rendered panel is 7-bit on vt320" \
    || bad "Tab panel: 8-bit bytes leak" "$hi panel lines carry bytes >0x7f"
  over=$(printf '%s\n' "$paneldump" \
    | sed $'s/\e\[[0-9;]*[a-zA-Z]//g; s/\e[()][A-B0]//g' \
    | awk 'length > 80 {c++} END {print c+0}')
  ((over == 0)) && ok "Tab panel: every rendered panel fits 80 columns" \
    || { detail="$over panel lines exceed 80 columns — Tab shears the frame"
         ((VERBOSE)) && detail+=$'\n    '$(printf '%s\n' "$paneldump" | sed $'s/\e\[[0-9;]*[a-zA-Z]//g' | awk 'length>80{print length": "$0}' | sort -u | head -5 | cut -c1-90)
         bad "Tab panel: $over lines over 80" "$detail"; }
fi

# ── 5. ASCII fallbacks stay one column wide ──
# The UI does manual column arithmetic. A 2-char substitute silently shears every frame
# it appears in, which is far worse than a wrong-looking glyph.
echo
wide=$(env -u LANG -u LC_ALL TERM=vt320 bash -c '
  CMDCHAMP_ASCII=1; source <(sed -n "1,140p" ./cmdchamp) 2>/dev/null
  for v in _GH _GV _GTL _GTR _GBL _GBR _GBK _GSH _GS2 _GS3 _GUB _GLB \
           _GOK _GNO _GST _GTRI _GAR _GUP _GDN _GDOT _GLE _GGE _GNE _GEQ _GMUL _GDASH; do
    printf "%s=%s\n" "$v" "${#!v}"
  done' 2>/dev/null | awk -F= '$2 != 1 {print $1"("$2")"}' | tr '\n' ' ')
[[ -z $wide ]] && ok "ASCII tier: every glyph is 1 column" || bad "ASCII tier: non-1-column glyphs" "$wide"

# ── 6. the selftest still passes on a legacy terminal ──
echo
if env -u LANG -u LC_ALL TERM=vt320 ./cmdchamp test >/dev/null 2>&1; then
  ok "vt320: selftest passes"
else bad "vt320: selftest fails" "game logic broke under the legacy render path"; fi

printf '\n%s%s%d passed%s' "$B" "$G" "$pass" "$N"
((fail)) && printf ', %s%s%d failed%s\n' "$B" "$R" "$fail" "$N" || printf ', %s0 failed%s\n' "$D" "$N"
exit $((fail > 0))
