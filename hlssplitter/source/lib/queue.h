#ifndef __VS_COM_QUEUE_H__
#define __VS_COM_QUEUE_H__

#include <stdbool.h>
#include "mutex.h"

typedef struct
{
    unsigned int magic;
    int need_free; // need call free for queue_mem
    void *queue_mem;
    unsigned int max_num_messages;
    unsigned int object_size;
    unsigned int max_messages;
    unsigned int set_pointer;
    unsigned int get_pointer;
    unsigned int unlocked_size;

    mutex_t queueMutex;
}ComQueue_t;

int create_queue(ComQueue_t *queue, unsigned int object_size, unsigned int max_messages);
int create_queue_noalloc(ComQueue_t *queue, unsigned int object_size, unsigned int max_messages, void *queue_addr);
int destroy_queue(ComQueue_t *queue);
bool queue_getMessage(ComQueue_t *queue, void *mes, int miliseconds, bool need_eject);
bool queue_setMessage(ComQueue_t *queue, void *mes);
unsigned int queue_size(ComQueue_t *queue);

#endif // __VS_COM_QUEUE_H__
