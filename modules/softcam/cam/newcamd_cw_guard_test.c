#include <assert.h>
#include <stdint.h>
#include <string.h>

#include "newcamd_cw_guard.h"

static void fill(uint8_t *buffer, size_t size, uint8_t value)
{
    memset(buffer, value, size);
}

int main(void)
{
    newcamd_cw_cache_t cache = {0};
    uint8_t full[16];
    uint8_t even_only[16] = {0};
    uint8_t odd_only[16] = {0};
    uint8_t zero[16] = {0};
    uint8_t expected[16];
    uint8_t decrypt_a;
    uint8_t arg_a;
    uint8_t arg_b;
    uint8_t decrypt_b;
    const newcamd_cw_scope_t scope_a = { &decrypt_a, &arg_a, 1 };
    const newcamd_cw_scope_t scope_b = { &decrypt_a, &arg_b, 1 };
    const newcamd_cw_scope_t scope_reused = { &decrypt_a, &arg_a, 2 };
    const newcamd_cw_scope_t scope_service_b = { &decrypt_b, &arg_b, 1 };

    assert(newcamd_response_id_matches(0x1234, 0x12, 0x34));
    assert(!newcamd_response_id_matches(0x1234, 0x12, 0x35));
    assert(!newcamd_cw_scope_matches(scope_a, scope_b));
    assert(!newcamd_cw_scope_matches(scope_a, scope_reused));

    fill(full, sizeof(full), 0x11);
    fill(&full[8], 8, 0x22);
    assert(newcamd_cw_cache_merge(&cache, scope_a, full) == NEWCAMD_CW_ACCEPTED);
    assert(newcamd_cw_cache_merge(&cache, scope_a, zero) == NEWCAMD_CW_REJECTED_NO_CACHE);

    fill(even_only, 8, 0x33);
    memcpy(expected, even_only, sizeof(expected));
    memcpy(&expected[8], &full[8], 8);
    assert(newcamd_cw_cache_merge(&cache, scope_a, even_only) == NEWCAMD_CW_ACCEPTED);
    assert(memcmp(even_only, expected, sizeof(expected)) == 0);

    fill(&odd_only[8], 8, 0x44);
    memcpy(expected, even_only, 8);
    memcpy(&expected[8], &odd_only[8], 8);
    assert(newcamd_cw_cache_merge(&cache, scope_a, odd_only) == NEWCAMD_CW_ACCEPTED);
    assert(memcmp(odd_only, expected, sizeof(expected)) == 0);

    newcamd_cw_cache_reset(&cache);
    memset(even_only, 0, sizeof(even_only));
    fill(even_only, 8, 0x55);
    assert(newcamd_cw_cache_merge(&cache, scope_a, even_only) == NEWCAMD_CW_REJECTED_NO_CACHE);

    assert(newcamd_cw_cache_merge(&cache, scope_a, full) == NEWCAMD_CW_ACCEPTED);
    memset(even_only, 0, sizeof(even_only));
    fill(even_only, 8, 0x66);
    assert(newcamd_cw_cache_merge(&cache, scope_b, even_only) == NEWCAMD_CW_REJECTED_SCOPE);
    assert(newcamd_cw_cache_merge(&cache, scope_reused, even_only) == NEWCAMD_CW_REJECTED_SCOPE);

    newcamd_cw_cache_reset(&cache);
    memset(odd_only, 0, sizeof(odd_only));
    fill(&odd_only[8], 8, 0x77);
    assert(newcamd_cw_cache_merge(&cache, scope_a, odd_only) == NEWCAMD_CW_REJECTED_NO_CACHE);

    /* Interleaved services on one Newcamd socket keep independent CW halves. */
    newcamd_cw_cache_reset(&cache);
    fill(full, sizeof(full), 0x11);
    fill(&full[8], 8, 0x22);
    assert(newcamd_cw_cache_merge(&cache, scope_a, full) == NEWCAMD_CW_ACCEPTED);

    fill(full, sizeof(full), 0x55);
    fill(&full[8], 8, 0x66);
    assert(newcamd_cw_cache_merge(&cache, scope_service_b, full) == NEWCAMD_CW_ACCEPTED);

    memset(even_only, 0, sizeof(even_only));
    fill(even_only, 8, 0x33);
    assert(newcamd_cw_cache_merge(&cache, scope_a, even_only) == NEWCAMD_CW_ACCEPTED);
    fill(expected, 8, 0x33);
    fill(&expected[8], 8, 0x22);
    assert(memcmp(even_only, expected, sizeof(expected)) == 0);

    memset(odd_only, 0, sizeof(odd_only));
    fill(&odd_only[8], 8, 0x77);
    assert(newcamd_cw_cache_merge(&cache, scope_service_b, odd_only) == NEWCAMD_CW_ACCEPTED);
    fill(expected, 8, 0x55);
    fill(&expected[8], 8, 0x77);
    assert(memcmp(odd_only, expected, sizeof(expected)) == 0);

    return 0;
}
