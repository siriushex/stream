#!/bin/sh
set -eu

CC_BIN=${CC:-cc}
OUT=${TMPDIR:-/tmp}/stream-playout-clock-test

"$CC_BIN" -std=c99 -Wall -Wextra -Werror -Imodules/mpegts \
    modules/mpegts/playout_clock_test.c -o "$OUT"
"$OUT"
printf '%s\n' 'Playout helper tests: OK.'
