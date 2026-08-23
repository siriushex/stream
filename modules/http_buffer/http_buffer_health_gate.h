#ifndef STREAM_HTTP_BUFFER_HEALTH_GATE_H
#define STREAM_HTTP_BUFFER_HEALTH_GATE_H

#include <stdbool.h>
#include <stdint.h>

typedef enum
{
    HTTP_BUFFER_HEALTH_HOLD = 0,
    HTTP_BUFFER_HEALTH_OK = 1,
    HTTP_BUFFER_HEALTH_FAIL = 2,
} http_buffer_health_result_t;

typedef struct
{
    uint32_t fail_checks;
    uint64_t unhealthy_since_ms;
    uint64_t healthy_since_ms;
} http_buffer_health_gate_t;

static inline void http_buffer_health_gate_reset(http_buffer_health_gate_t *gate)
{
    *gate = (http_buffer_health_gate_t){0};
}

static inline http_buffer_health_result_t http_buffer_health_gate_observe(
      http_buffer_health_gate_t *gate,
      bool healthy,
      uint64_t now_ms,
      uint32_t failover_ms,
      uint32_t required_checks)
{
    if(healthy)
    {
        gate->fail_checks = 0;
        gate->unhealthy_since_ms = 0;
        if(gate->healthy_since_ms == 0)
            gate->healthy_since_ms = now_ms;
        return HTTP_BUFFER_HEALTH_OK;
    }

    gate->healthy_since_ms = 0;
    if(gate->unhealthy_since_ms == 0)
        gate->unhealthy_since_ms = now_ms;
    if(gate->fail_checks != UINT32_MAX)
        gate->fail_checks++;
    if(gate->fail_checks >= required_checks
       && now_ms - gate->unhealthy_since_ms >= failover_ms)
    {
        return HTTP_BUFFER_HEALTH_FAIL;
    }
    return HTTP_BUFFER_HEALTH_HOLD;
}

static inline uint32_t http_buffer_health_recovery_progress(
      http_buffer_health_gate_t *gate,
      bool healthy,
      uint64_t now_ms,
      uint32_t return_delay_ms)
{
    if(!healthy)
    {
        gate->healthy_since_ms = 0;
        return 0;
    }
    if(gate->healthy_since_ms == 0)
        gate->healthy_since_ms = now_ms;
    uint64_t elapsed = now_ms - gate->healthy_since_ms;
    if(elapsed > return_delay_ms)
        elapsed = return_delay_ms;
    return (uint32_t)(elapsed / 1000ULL);
}

#endif
