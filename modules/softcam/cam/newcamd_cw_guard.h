#ifndef ASTRA_NEWCAMD_CW_GUARD_H
#define ASTRA_NEWCAMD_CW_GUARD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define NEWCAMD_CW_HALF_SIZE 8

typedef enum {
    NEWCAMD_CW_ACCEPTED,
    NEWCAMD_CW_REJECTED_NO_CACHE,
    NEWCAMD_CW_REJECTED_SCOPE,
} newcamd_cw_merge_result_t;

typedef struct {
    const void *decrypt;
    const void *arg;
    uint64_t generation;
} newcamd_cw_scope_t;

typedef struct {
    uint8_t half[2][NEWCAMD_CW_HALF_SIZE];
    bool valid[2];
    bool scope_valid;
    newcamd_cw_scope_t scope;
} newcamd_cw_cache_t;

static inline bool newcamd_response_id_matches(uint16_t expected, uint8_t hi, uint8_t lo)
{
    return expected == (((uint16_t)hi << 8) | lo);
}

static inline bool newcamd_cw_scope_matches(newcamd_cw_scope_t left,
                                             newcamd_cw_scope_t right)
{
    return left.decrypt == right.decrypt
        && left.arg == right.arg
        && left.generation == right.generation;
}

static inline bool newcamd_cw_half_nonzero(const uint8_t *half)
{
    size_t i;
    for(i = 0; i < NEWCAMD_CW_HALF_SIZE; ++i)
    {
        if(half[i] != 0)
            return true;
    }
    return false;
}

static inline void newcamd_cw_cache_reset(newcamd_cw_cache_t *cache)
{
    memset(cache, 0, sizeof(*cache));
}

static inline newcamd_cw_merge_result_t newcamd_cw_cache_merge(
      newcamd_cw_cache_t *cache, newcamd_cw_scope_t scope, uint8_t *cw)
{
    const bool has_even = newcamd_cw_half_nonzero(&cw[0]);
    const bool has_odd = newcamd_cw_half_nonzero(&cw[NEWCAMD_CW_HALF_SIZE]);

    if(has_even && has_odd)
    {
        memcpy(cache->half[0], &cw[0], NEWCAMD_CW_HALF_SIZE);
        memcpy(cache->half[1], &cw[NEWCAMD_CW_HALF_SIZE], NEWCAMD_CW_HALF_SIZE);
        cache->valid[0] = true;
        cache->valid[1] = true;
        cache->scope = scope;
        cache->scope_valid = true;
        return NEWCAMD_CW_ACCEPTED;
    }

    if(!has_even && !has_odd)
        return NEWCAMD_CW_REJECTED_NO_CACHE;
    if(!cache->scope_valid)
        return NEWCAMD_CW_REJECTED_NO_CACHE;
    if(!newcamd_cw_scope_matches(cache->scope, scope))
        return NEWCAMD_CW_REJECTED_SCOPE;

    if(!has_even)
    {
        if(!cache->valid[0])
            return NEWCAMD_CW_REJECTED_NO_CACHE;
        memcpy(&cw[0], cache->half[0], NEWCAMD_CW_HALF_SIZE);
    }
    else
    {
        if(!cache->valid[1])
            return NEWCAMD_CW_REJECTED_NO_CACHE;
        memcpy(&cw[NEWCAMD_CW_HALF_SIZE], cache->half[1], NEWCAMD_CW_HALF_SIZE);
    }

    memcpy(cache->half[0], &cw[0], NEWCAMD_CW_HALF_SIZE);
    memcpy(cache->half[1], &cw[NEWCAMD_CW_HALF_SIZE], NEWCAMD_CW_HALF_SIZE);
    cache->valid[0] = true;
    cache->valid[1] = true;
    return NEWCAMD_CW_ACCEPTED;
}

#endif
