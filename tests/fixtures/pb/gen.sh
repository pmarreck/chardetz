#!/usr/bin/env bash
# Regenerate the committed PRINTABLE-BINARY metamorphic fixtures.
#
# These are REAL printable-binary CLI output (the independent oracle/encoder) over
# fixed inputs, committed as hermetic test vectors so the metamorphic gate
# (tests/unit/pb_metamorphic_test.zig) runs in the sandbox without a runtime
# dependency on printable-binary. Re-run this if printable_binary's glyph map
# changes (then also re-vendor src/printable_binary_map.txt and re-bless hashes).
set -u
cd "$(dirname "$0")" || exit 1
PB=/Users/pmarreck/Documents-CloudManaged/printable_binary/bin/printable-binary
[ -x "$PB" ] || PB=printable-binary

# Deterministic inputs: a real binary (high/control-byte dense) and a legible
# text+binary mix (readable text with embedded control/high bytes + punctuation).
head -c 1200 /bin/ls > /tmp/pb_in_bin.dat
printf 'Report 2026: revenue up 12%%.\nNotes:\t\x00\x01\x02\x80\x81\xfe\xff binary blob follows here \x1b[0m and more text to read clearly across the line\n' > /tmp/pb_in_mix.dat

"$PB"    /tmp/pb_in_bin.dat > bin_default.pbtxt
"$PB" -s /tmp/pb_in_bin.dat > bin_s.pbtxt
"$PB" -w /tmp/pb_in_bin.dat > bin_w.pbtxt
"$PB" -f /tmp/pb_in_bin.dat > bin_f.pbtxt
"$PB"    /tmp/pb_in_mix.dat > mix_default.pbtxt
"$PB" -w /tmp/pb_in_mix.dat > mix_w.pbtxt
echo "regenerated $(ls *.pbtxt | wc -l | tr -d ' ') PB fixtures" >&2
