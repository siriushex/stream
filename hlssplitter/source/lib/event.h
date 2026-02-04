#ifndef __EVENT_H__
#define __EVENT_H__

#include "mutex.h"

typedef struct event_data* event_t;

struct event_data
{
    unsigned int magic;
    unsigned int have_event;
    mutex_t mutex_val;
};

int event_create(event_t event);
int event_destroy(event_t event);
int event_reset(event_t event);
int event_send(event_t event);
int event_wait(event_t event, int msec);

#endif /* __EVENT_H__ */
