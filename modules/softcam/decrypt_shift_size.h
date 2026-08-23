#ifndef ASTRA_SOFTCAM_DECRYPT_SHIFT_SIZE_H
#define ASTRA_SOFTCAM_DECRYPT_SHIFT_SIZE_H

#include <stddef.h>
#include <stdint.h>

#define DECRYPT_SHIFT_PACKET_SIZE 188U
#define DECRYPT_SHIFT_ASSUME_MBIT 10U
#define DECRYPT_SHIFT_MAX_BYTES (16U * 1024U * 1024U)
#define DECRYPT_SHIFT_MAX_ALIGNED_BYTES \
    (DECRYPT_SHIFT_MAX_BYTES - (DECRYPT_SHIFT_MAX_BYTES % DECRYPT_SHIFT_PACKET_SIZE))

static inline size_t decrypt_shift_size_bytes(int shift)
{
    if(shift <= 0)
        return 0;

    uint64_t shift_ms = (uint64_t)shift;
    if(shift < 100)
        shift_ms *= 100ULL;

    const uint64_t bits_per_sec = (uint64_t)DECRYPT_SHIFT_ASSUME_MBIT * 1000ULL * 1000ULL;
    uint64_t bytes = (shift_ms * bits_per_sec) / 8ULL / 1000ULL;
    if(bytes < DECRYPT_SHIFT_PACKET_SIZE)
        bytes = DECRYPT_SHIFT_PACKET_SIZE;

    bytes = ((bytes + DECRYPT_SHIFT_PACKET_SIZE - 1U) / DECRYPT_SHIFT_PACKET_SIZE)
        * DECRYPT_SHIFT_PACKET_SIZE;
    if(bytes > DECRYPT_SHIFT_MAX_BYTES)
        bytes = DECRYPT_SHIFT_MAX_ALIGNED_BYTES;

    return (size_t)bytes;
}

#endif
