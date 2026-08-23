#ifndef STREAM_PLAYOUT_CLOCK_H
#define STREAM_PLAYOUT_CLOCK_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PLAYOUT_PCR_MAX_TICKS ((1ULL << 33) * 300ULL)
#define PLAYOUT_PCR_HZ 27000000ULL

typedef struct
{
    double bitrate_bps_ema;
    uint16_t pcr_pid;
    bool pcr_seen;
    uint64_t last_pcr;
    uint64_t packets_since_pcr;
} playout_clock_t;

static inline void playout_clock_reset(playout_clock_t *clock)
{
    *clock = (playout_clock_t){0};
}

static inline void playout_clock_count_packet(playout_clock_t *clock)
{
    if(clock->packets_since_pcr != UINT64_MAX)
        clock->packets_since_pcr++;
}

static inline bool playout_clock_observe(
      playout_clock_t *clock,
      uint16_t pid,
      uint64_t current,
      size_t packet_size,
      double *sample_bps)
{
    if(!clock->pcr_seen || pid != clock->pcr_pid)
    {
        clock->pcr_pid = pid;
        clock->last_pcr = current;
        clock->packets_since_pcr = 0;
        clock->pcr_seen = true;
        return false;
    }

    const uint64_t delta = current >= clock->last_pcr
        ? current - clock->last_pcr
        : PLAYOUT_PCR_MAX_TICKS - clock->last_pcr + current;
    const uint64_t packets = clock->packets_since_pcr;
    clock->last_pcr = current;
    clock->packets_since_pcr = 0;
    if(delta == 0 || delta > PLAYOUT_PCR_HZ * 5ULL || packets == 0)
        return false;

    const size_t bytes = packet_size ? packet_size : 188U;
    const double instant = ((double)packets * (double)bytes * 8.0)
        / ((double)delta / (double)PLAYOUT_PCR_HZ);
    if(instant < 100000.0 || instant > 200000000.0)
        return false;

    clock->bitrate_bps_ema = clock->bitrate_bps_ema <= 0.0
        ? instant : clock->bitrate_bps_ema * 0.8 + instant * 0.2;
    if(sample_bps)
        *sample_bps = instant;
    return true;
}

static inline bool playout_prebuffer_next(
      bool current,
      size_t count,
      uint64_t fill_ms,
      uint32_t min_fill_ms)
{
    if(min_fill_ms == 0)
        return false;
    if(current && count > 0 && fill_ms >= min_fill_ms)
        return false;
    if(!current && count == 0)
        return true;
    return current;
}

#endif
