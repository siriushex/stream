#include <assert.h>
#include <stdbool.h>
#include <stdint.h>

#include "decrypt_key_guard_timing.h"

int main(void)
{
    decrypt_key_guard_timing_t timing;
    uint64_t apply_seq = 0;

    decrypt_key_guard_timing_reset(&timing);

    assert(decrypt_key_guard_timing_observe(&timing, false, 90, &apply_seq)
           == DECRYPT_KEY_GUARD_WAIT);
    assert(decrypt_key_guard_timing_observe(&timing, false, 91, &apply_seq)
           == DECRYPT_KEY_GUARD_WAIT);

    assert(decrypt_key_guard_timing_observe(&timing, true, 100, &apply_seq)
           == DECRYPT_KEY_GUARD_WAIT);
    assert(decrypt_key_guard_timing_observe(&timing, true, 140, &apply_seq)
           == DECRYPT_KEY_GUARD_ACCEPT);
    assert(apply_seq == 100);

    assert(!decrypt_key_guard_timing_should_apply(99, apply_seq));
    assert(decrypt_key_guard_timing_should_apply(100, apply_seq));
    assert(decrypt_key_guard_timing_should_apply(101, apply_seq));

    assert(decrypt_key_guard_timing_apply_boundary(80, 140, 60) == 80);
    assert(decrypt_key_guard_timing_apply_boundary(80, 140, 90) == 140);
    assert(decrypt_key_guard_timing_apply_boundary(160, 140, 60) == 140);

    decrypt_key_guard_timing_reset(&timing);
    assert(decrypt_key_guard_timing_observe(&timing, false, 200, &apply_seq)
           == DECRYPT_KEY_GUARD_WAIT);
    assert(decrypt_key_guard_timing_observe(&timing, false, 201, &apply_seq)
           == DECRYPT_KEY_GUARD_WAIT);
    assert(decrypt_key_guard_timing_observe(&timing, false, 202, &apply_seq)
           == DECRYPT_KEY_GUARD_WAIT);
    assert(decrypt_key_guard_timing_observe(&timing, false, 203, &apply_seq)
           == DECRYPT_KEY_GUARD_REJECT);

    return 0;
}
