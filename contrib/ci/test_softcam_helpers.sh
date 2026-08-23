#!/bin/sh
set -eu

CC_BIN=${CC:-cc}
BUILD_DIR=${TMPDIR:-/tmp}/stream-softcam-helper-tests
mkdir -p "$BUILD_DIR"

run_test() {
    source_file=$1
    output_name=$2
    "$CC_BIN" -std=c99 -Wall -Wextra -Werror \
        -Imodules/softcam -Imodules/softcam/cam \
        "$source_file" -o "$BUILD_DIR/$output_name"
    "$BUILD_DIR/$output_name"
}

run_test modules/softcam/cam/newcamd_cw_guard_test.c newcamd_cw_guard_test
printf '%s\n' 'SoftCAM helper tests: OK.'
