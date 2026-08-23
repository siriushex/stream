#include <assert.h>

#include "http_buffer_health_gate.h"

int main(void)
{
    http_buffer_health_gate_t gate = {0};
    http_buffer_health_gate_reset(&gate);

    assert(http_buffer_health_gate_observe(&gate, false, 1000, 5000, 2)
           == HTTP_BUFFER_HEALTH_HOLD);
    assert(http_buffer_health_gate_observe(&gate, false, 2000, 5000, 2)
           == HTTP_BUFFER_HEALTH_HOLD);
    assert(http_buffer_health_gate_observe(&gate, false, 5999, 5000, 2)
           == HTTP_BUFFER_HEALTH_HOLD);
    assert(http_buffer_health_gate_observe(&gate, false, 6000, 5000, 2)
           == HTTP_BUFFER_HEALTH_FAIL);

    assert(http_buffer_health_gate_observe(&gate, true, 7000, 5000, 2)
           == HTTP_BUFFER_HEALTH_OK);
    assert(gate.fail_checks == 0 && gate.unhealthy_since_ms == 0);

    http_buffer_health_gate_reset(&gate);
    assert(http_buffer_health_recovery_progress(&gate, true, 10000, 8000) == 0);
    assert(http_buffer_health_recovery_progress(&gate, true, 14000, 8000) == 4);
    assert(http_buffer_health_recovery_progress(&gate, true, 18000, 8000) == 8);
    assert(http_buffer_health_recovery_progress(&gate, false, 19000, 8000) == 0);
    return 0;
}
