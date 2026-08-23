#ifndef ASTRA_DECRYPT_KEY_GUARD_TIMING_H
#define ASTRA_DECRYPT_KEY_GUARD_TIMING_H

#include <stdbool.h>
#include <stdint.h>

#define DECRYPT_KEY_GUARD_REQUIRED_OK 2
#define DECRYPT_KEY_GUARD_MAX_FAIL 4

typedef enum
{
    DECRYPT_KEY_GUARD_WAIT = 0,
    DECRYPT_KEY_GUARD_ACCEPT = 1,
    DECRYPT_KEY_GUARD_REJECT = 2,
} decrypt_key_guard_result_t;

typedef struct
{
    uint8_t ok_count;
    uint8_t fail_count;
    uint64_t first_ok_seq;
} decrypt_key_guard_timing_t;

static inline void decrypt_key_guard_timing_reset(decrypt_key_guard_timing_t *timing)
{
    timing->ok_count = 0;
    timing->fail_count = 0;
    timing->first_ok_seq = 0;
}

static inline decrypt_key_guard_result_t decrypt_key_guard_timing_observe(
      decrypt_key_guard_timing_t *timing,
      bool valid,
      uint64_t ingress_seq,
      uint64_t *apply_seq)
{
    if(valid)
    {
        if(timing->ok_count == 0)
            timing->first_ok_seq = ingress_seq;
        if(timing->ok_count < UINT8_MAX)
            timing->ok_count += 1;
        if(timing->ok_count >= DECRYPT_KEY_GUARD_REQUIRED_OK)
        {
            if(apply_seq)
                *apply_seq = timing->first_ok_seq;
            return DECRYPT_KEY_GUARD_ACCEPT;
        }
        return DECRYPT_KEY_GUARD_WAIT;
    }

    if(timing->fail_count < UINT8_MAX)
        timing->fail_count += 1;
    if(timing->fail_count >= DECRYPT_KEY_GUARD_MAX_FAIL)
        return DECRYPT_KEY_GUARD_REJECT;
    return DECRYPT_KEY_GUARD_WAIT;
}

static inline bool decrypt_key_guard_timing_should_apply(
      uint64_t egress_seq,
      uint64_t apply_seq)
{
    return apply_seq != 0 && egress_seq >= apply_seq;
}

static inline uint64_t decrypt_key_guard_timing_apply_boundary(
      uint64_t parity_start_seq,
      uint64_t validated_seq,
      uint64_t egress_seq)
{
    if(parity_start_seq > egress_seq && parity_start_seq <= validated_seq)
        return parity_start_seq;
    return validated_seq;
}

#endif
