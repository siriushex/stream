#ifndef STREAM_NEWCAMD_KEYS_H
#define STREAM_NEWCAMD_KEYS_H

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#define NEWCAMD_CW_HALF_SIZE 8

typedef struct
{
    uint8_t key[2][NEWCAMD_CW_HALF_SIZE];
    bool valid[2];
} newcamd_cw_cache_t;

static inline bool newcamd_cw_half_is_zero(const uint8_t *half)
{
    static const uint8_t zero[NEWCAMD_CW_HALF_SIZE] = { 0 };
    return memcmp(half, zero, NEWCAMD_CW_HALF_SIZE) == 0;
}

/*
 * Merge a 16-byte CW response in-place.
 *
 * Newcamd/NDS servers may return one updated half and zero the other half.
 * Never synthesize an unknown half: reject that response until a valid
 * previous half is available.  A response with both halves present refreshes
 * both cached values.
 */
static inline bool newcamd_cw_cache_merge(newcamd_cw_cache_t *cache, uint8_t response[16])
{
    if(!cache || !response)
        return false;

    const bool even_zero = newcamd_cw_half_is_zero(&response[0]);
    const bool odd_zero = newcamd_cw_half_is_zero(&response[8]);

    if(even_zero && odd_zero)
        return false;

    if(!even_zero)
    {
        memcpy(cache->key[0], &response[0], NEWCAMD_CW_HALF_SIZE);
        cache->valid[0] = true;
    }

    if(!odd_zero)
    {
        memcpy(cache->key[1], &response[8], NEWCAMD_CW_HALF_SIZE);
        cache->valid[1] = true;
    }

    /* A first partial response is cached but must not be applied until the
     * other half has also been observed. */
    if(!cache->valid[0] || !cache->valid[1])
        return false;

    if(even_zero)
        memcpy(&response[0], cache->key[0], NEWCAMD_CW_HALF_SIZE);
    if(odd_zero)
        memcpy(&response[8], cache->key[1], NEWCAMD_CW_HALF_SIZE);

    return true;
}

#endif
