#include <assert.h>

#include "playout_clock.h"

int main(void)
{
    playout_clock_t clock = {0};
    double sample = 0.0;

    assert(!playout_clock_observe(&clock, 256, 1000, 188, &sample));
    clock.packets_since_pcr = 3990;
    assert(playout_clock_observe(&clock, 256, 27001000, 188, &sample));
    assert(sample > 5900000.0 && sample < 6100000.0);

    playout_clock_reset(&clock);
    assert(!playout_clock_observe(
          &clock, 256, PLAYOUT_PCR_MAX_TICKS - 1000, 188, &sample));
    clock.packets_since_pcr = 3990;
    assert(playout_clock_observe(&clock, 256, 26999000, 188, &sample));

    playout_clock_reset(&clock);
    assert(!playout_clock_observe(&clock, 256, 1000, 188, &sample));
    clock.packets_since_pcr = 3990;
    assert(!playout_clock_observe(
          &clock, 256, PLAYOUT_PCR_HZ * 6ULL + 1000, 188, &sample));

    assert(playout_prebuffer_next(true, 1, 499, 500));
    assert(!playout_prebuffer_next(true, 1, 500, 500));
    assert(!playout_prebuffer_next(false, 1, 100, 500));
    assert(playout_prebuffer_next(false, 0, 0, 500));
    return 0;
}
