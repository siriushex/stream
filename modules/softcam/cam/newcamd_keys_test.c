#include <assert.h>
#include <stdint.h>
#include <string.h>

#include "newcamd_keys.h"

static void expect_bytes(const uint8_t *actual, const uint8_t *expected)
{
    assert(memcmp(actual, expected, 16) == 0);
}

int main(void)
{
    newcamd_cw_cache_t cache = { 0 };
    uint8_t response[16];
    const uint8_t first[16] = {
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
    };
    const uint8_t even_update[16] = {
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    };
    const uint8_t odd_update[16] = {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
    };
    const uint8_t expected_even[16] = {
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
    };
    const uint8_t expected_odd[16] = {
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
    };
    const uint8_t expected_partial_start[16] = {
        0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28,
        0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
    };

    memcpy(response, first, sizeof(response));
    assert(newcamd_cw_cache_merge(&cache, response));
    expect_bytes(response, first);

    memcpy(response, even_update, sizeof(response));
    assert(newcamd_cw_cache_merge(&cache, response));
    expect_bytes(response, expected_even);

    memcpy(response, odd_update, sizeof(response));
    assert(newcamd_cw_cache_merge(&cache, response));
    expect_bytes(response, expected_odd);

    newcamd_cw_cache_t empty = { 0 };
    memcpy(response, odd_update, sizeof(response));
    assert(!newcamd_cw_cache_merge(&empty, response));
    assert(empty.valid[0] == false);
    assert(empty.valid[1] == true);

    memcpy(response, even_update, sizeof(response));
    assert(newcamd_cw_cache_merge(&empty, response));
    expect_bytes(response, expected_partial_start);

    newcamd_cw_cache_t zeros_cache = { 0 };
    memset(response, 0, sizeof(response));
    assert(!newcamd_cw_cache_merge(&zeros_cache, response));
    assert(zeros_cache.valid[0] == false);
    assert(zeros_cache.valid[1] == false);

    return 0;
}
