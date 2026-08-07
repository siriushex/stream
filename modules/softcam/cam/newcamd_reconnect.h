#ifndef STREAM_NEWCAMD_RECONNECT_H
#define STREAM_NEWCAMD_RECONNECT_H

#include <stdbool.h>

static inline bool newcamd_should_reconnect_immediately(int read_result)
{
    return read_result == 0;
}

#endif
