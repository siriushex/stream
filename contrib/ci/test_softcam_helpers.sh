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
run_test modules/softcam/decrypt_key_guard_timing_test.c decrypt_key_guard_timing_test
run_test modules/softcam/decrypt_shift_size_test.c decrypt_shift_size_test

if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libcrypto; then
    # Keep the configure-time probe compatible with OpenSSL 3, where the
    # legacy DES functions are deprecated and -Werror would reject them.
    # shellcheck disable=SC2046
    "$CC_BIN" -std=c99 -Wall -Wextra -Werror \
        -Imodules/softcam/cam \
        modules/softcam/cam/newcamd_openssl_probe_test.c \
        $(pkg-config --cflags --libs libcrypto) \
        -o "$BUILD_DIR/newcamd_openssl_probe_test"
    "$BUILD_DIR/newcamd_openssl_probe_test"
    grep -Fq '#include "modules/softcam/cam/newcamd_openssl_probe.h"' \
        modules/softcam/module.mk
fi

printf '%s\n' 'SoftCAM helper tests: OK.'
