#!/bin/sh
set -eu

CC_BIN=${CC:-cc}
OUT=${TMPDIR:-/tmp}/stream-http-buffer-health-test

"$CC_BIN" -std=c99 -Wall -Wextra -Werror -Imodules/http_buffer \
    modules/http_buffer/http_buffer_health_gate_test.c -o "$OUT"
"$OUT"
printf '%s\n' 'HTTP buffer helper tests: OK.'
