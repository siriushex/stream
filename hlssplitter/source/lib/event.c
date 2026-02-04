#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include "event.h"
#include "log.h"

#define QUEUE_MAGIC_VALUE       0x7EA3C6F1

int event_create(event_t event)
{
    int result = -EINVAL;

    if(event)
    {
        if(mutex_init(&event->mutex_val, true))
        {
            event->magic = QUEUE_MAGIC_VALUE;
            event->have_event = 0;
            result = 0;
        }
        else
        {
            logout("%s:%d: Failed mutex_init\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s:%d: Invalid arguments %p\n", __FUNCTION__, __LINE__, event);
    }

    return result;
}

int event_destroy(event_t event)
{
    int result = -EINVAL;

    if(event)
    {
        if(event->magic == QUEUE_MAGIC_VALUE)
        {
            mutex_term(&event->mutex_val);
            result = 0;
        }
        else
        {
            logout("%s:%d: Invalid magic value 0x%X\n", __FUNCTION__, __LINE__, (unsigned int)event->magic);
        }
    }
    else
    {
        logout("%s:%d: Invalid arguments %p\n", __FUNCTION__, __LINE__, event);
    }

    return result;
}

int event_reset(event_t event)
{
    int result = -EINVAL;

    if(event)
    {
        if(event->magic == QUEUE_MAGIC_VALUE)
        {
            if(mutex_lock(&event->mutex_val))
            {
                event->have_event = 0;
                mutex_unlock(&event->mutex_val);
                result = 0;
            }
            else
            {
                logout("%s:%d: Failed mutex_lock\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s:%d: Invalid magic value 0x%X\n", __FUNCTION__, __LINE__, (unsigned int)event->magic);
        }
    }
    else
    {
        logout("%s:%d: Invalid arguments %p\n", __FUNCTION__, __LINE__, event);
    }

    return result;
}

int event_send(event_t event)
{
    int result = -EINVAL;

    if(event)
    {
        if(event->magic == QUEUE_MAGIC_VALUE)
        {
            if(mutex_lock(&event->mutex_val))
            {
                event->have_event = 1;
                mutex_cond_signal(&event->mutex_val);
                mutex_unlock(&event->mutex_val);
                result = 0;
            }
            else
            {
                logout("%s:%d: Failed mutex_lock\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s:%d: Invalid magic value 0x%X\n", __FUNCTION__, __LINE__, (unsigned int)event->magic);
        }
    }
    else
    {
        logout("%s:%d: Invalid arguments %p\n", __FUNCTION__, __LINE__, event);
    }

    return result;
}

int event_wait(event_t event, int msec)
{
    int result = -EINVAL;

    if(event)
    {
        if(event->magic == QUEUE_MAGIC_VALUE)
        {
            if(mutex_lock(&event->mutex_val))
            {
                if(event->have_event)
                {
                    result = 0;
                }
                else if(msec < 0)
                {
                    // skip wait and no event
                }
                else if(msec)
                {
                    mutex_cond_timedwait(&event->mutex_val, msec);
                    if(event->have_event)
                        result = 0;
                }
                else
                {
                    mutex_cond_wait(&event->mutex_val);
                    if(event->have_event)
                        result = 0;
                }
                mutex_unlock(&event->mutex_val);
            }
            else
            {
                logout("%s:%d: Failed mutex_lock\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s:%d: Invalid magic value 0x%X\n", __FUNCTION__, __LINE__, (unsigned int)event->magic);
        }
    }
    else
    {
        logout("%s:%d: Invalid arguments %p\n", __FUNCTION__, __LINE__, event);
    }

    return result;
}

