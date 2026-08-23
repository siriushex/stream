#ifndef ASTRA_NEWCAMD_CW_GUARD_H
#define ASTRA_NEWCAMD_CW_GUARD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define NEWCAMD_CW_HALF_SIZE 8
#define NEWCAMD_CW_CACHE_SLOTS 16

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
} newcamd_cw_cache_slot_t;

typedef struct {
    newcamd_cw_cache_slot_t slot[NEWCAMD_CW_CACHE_SLOTS];
    size_t next_slot;
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

static inline newcamd_cw_cache_slot_t *newcamd_cw_cache_find(
      newcamd_cw_cache_t *cache, newcamd_cw_scope_t scope)
{
    size_t i;
    for(i = 0; i < NEWCAMD_CW_CACHE_SLOTS; ++i)
    {
        newcamd_cw_cache_slot_t *slot = &cache->slot[i];
        if(slot->scope_valid && newcamd_cw_scope_matches(slot->scope, scope))
            return slot;
    }
    return NULL;
}

static inline newcamd_cw_cache_slot_t *newcamd_cw_cache_allocate(
      newcamd_cw_cache_t *cache)
{
    size_t i;
    for(i = 0; i < NEWCAMD_CW_CACHE_SLOTS; ++i)
    {
        if(!cache->slot[i].scope_valid)
            return &cache->slot[i];
    }

    i = cache->next_slot % NEWCAMD_CW_CACHE_SLOTS;
    cache->next_slot = (i + 1) % NEWCAMD_CW_CACHE_SLOTS;
    memset(&cache->slot[i], 0, sizeof(cache->slot[i]));
    return &cache->slot[i];
}

static inline newcamd_cw_merge_result_t newcamd_cw_cache_merge(
      newcamd_cw_cache_t *cache, newcamd_cw_scope_t scope, uint8_t *cw)
{
    const bool has_even = newcamd_cw_half_nonzero(&cw[0]);
    const bool has_odd = newcamd_cw_half_nonzero(&cw[NEWCAMD_CW_HALF_SIZE]);
    newcamd_cw_cache_slot_t *slot = newcamd_cw_cache_find(cache, scope);

    if(has_even && has_odd)
    {
        if(!slot)
            slot = newcamd_cw_cache_allocate(cache);
        memcpy(slot->half[0], &cw[0], NEWCAMD_CW_HALF_SIZE);
        memcpy(slot->half[1], &cw[NEWCAMD_CW_HALF_SIZE], NEWCAMD_CW_HALF_SIZE);
        slot->valid[0] = true;
        slot->valid[1] = true;
        slot->scope = scope;
        slot->scope_valid = true;
        return NEWCAMD_CW_ACCEPTED;
    }

    if(!has_even && !has_odd)
        return NEWCAMD_CW_REJECTED_NO_CACHE;
    if(!slot)
    {
        size_t i;
        for(i = 0; i < NEWCAMD_CW_CACHE_SLOTS; ++i)
        {
            if(cache->slot[i].scope_valid)
                return NEWCAMD_CW_REJECTED_SCOPE;
        }
        return NEWCAMD_CW_REJECTED_NO_CACHE;
    }

    if(!has_even)
    {
        if(!slot->valid[0])
            return NEWCAMD_CW_REJECTED_NO_CACHE;
        memcpy(&cw[0], slot->half[0], NEWCAMD_CW_HALF_SIZE);
    }
    else
    {
        if(!slot->valid[1])
            return NEWCAMD_CW_REJECTED_NO_CACHE;
        memcpy(&cw[NEWCAMD_CW_HALF_SIZE], slot->half[1], NEWCAMD_CW_HALF_SIZE);
    }

    memcpy(slot->half[0], &cw[0], NEWCAMD_CW_HALF_SIZE);
    memcpy(slot->half[1], &cw[NEWCAMD_CW_HALF_SIZE], NEWCAMD_CW_HALF_SIZE);
    slot->valid[0] = true;
    slot->valid[1] = true;
    return NEWCAMD_CW_ACCEPTED;
}

#endif
