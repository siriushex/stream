#include "queue.h"
#include "log.h"
#include <errno.h>
#include <string.h>
#include <stdlib.h>

#define QUEUE_MAGIC_VALUE       0x432A8B1D

int int_create_queue(ComQueue_t *queue, unsigned int object_size, unsigned int max_messages, void *queue_mem)
{
    int result = EINVAL;

    if(queue && object_size && max_messages && queue_mem)
    {
        memset(queue, 0, sizeof(*queue));
        if(mutex_init(&queue->queueMutex, true))
        {
            queue->magic = QUEUE_MAGIC_VALUE;
            queue->queue_mem = queue_mem;
            queue->max_num_messages = max_messages;
            queue->object_size = object_size;
            queue->max_messages = max_messages;
            result = 0;
        }
        else
        {
            logout("%s %d: Failed mutex_init\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: Invalid arguments %p 0x%X 0x%X %p\n", __FUNCTION__, __LINE__, queue, (unsigned int)object_size, (unsigned int)max_messages, queue_mem);
    }

    return result;
}

int create_queue(ComQueue_t *queue, unsigned int object_size, unsigned int max_messages)
{
    int result = EINVAL;
    void *queue_mem;

    if(queue && object_size && max_messages)
    {
        queue_mem = malloc(object_size * max_messages);
        if(queue_mem)
        {
            result = int_create_queue(queue, object_size, max_messages, queue_mem);
            if(!result)
            {
                queue->need_free = 1;
            }
            else
            {
                free(queue_mem);
            }
        }
        else
        {
            logout("%s %d: Failed alloc %d bytes of memory\n", __FUNCTION__, __LINE__, (unsigned int) object_size * max_messages);
        }
    }
    else
    {
        logout("%s %d: Invalid arguments %p 0x%X 0x%X\n", __FUNCTION__, __LINE__, queue, (unsigned int)object_size, (unsigned int)max_messages);
    }

    return result;
}

int create_queue_noalloc(ComQueue_t *queue, unsigned int object_size, unsigned int max_messages, void *queue_addr)
{
    int result = EINVAL;
 
    if(queue && object_size && max_messages && queue_addr)
    {
        result = int_create_queue(queue, object_size, max_messages, queue_addr);
    }
    else
    {
        logout("%s %d: Invalid arguments %p 0x%X 0x%X %p\n", __FUNCTION__, __LINE__, queue, (unsigned int)object_size, (unsigned int)max_messages, queue_addr);
    }

    return result;
}

int destroy_queue(ComQueue_t *queue)
{
    int result = EINVAL;

    if(queue)
    {
        if(queue->magic == QUEUE_MAGIC_VALUE)
        {
            queue->magic = 0;
            mutex_term(&queue->queueMutex);
            if(queue->need_free)
                free(queue->queue_mem);
            result = 0;
        }
        else
        {
            logout("%s %d: Invalid magic value 0x%X\n", __FUNCTION__, __LINE__, (unsigned int)queue->magic);
        }
    }
    else
    {
        logout("%s %d: Invalid argument %p\n", __FUNCTION__, __LINE__, queue);
    }

    return result;
}

static void increment_pointer(ComQueue_t *queue, unsigned int *pointer)
{
    if(*pointer + 1 >= queue->max_num_messages)
        *pointer = 0;
    else
        (*pointer)++;
}

static unsigned int int_size(ComQueue_t *queue)
{
    unsigned int sizeOfQueue = 0;

    if(queue->get_pointer > queue->set_pointer)
        sizeOfQueue = queue->max_num_messages - queue->get_pointer + queue->set_pointer;
    else
        sizeOfQueue = queue->set_pointer - queue->get_pointer;

    return sizeOfQueue;
}

bool queue_getMessage(ComQueue_t *queue, void *mes, int miliseconds, bool need_eject)
{
    bool result = false;

    if(queue)
    {
        if(queue->magic == QUEUE_MAGIC_VALUE)
        {
            if(mutex_lock(&queue->queueMutex))
            {
                if(queue->set_pointer != queue->get_pointer)
                {
                    memcpy(mes, (unsigned char*)queue->queue_mem + queue->get_pointer * queue->object_size, queue->object_size);

                    if(need_eject)
                    {
                        increment_pointer(queue, &queue->get_pointer);
                    }
                    result = true;
                }
                else
                {
                    if(miliseconds < 0)
                    {
                        // skip wait
                    }
                    else if(miliseconds)
                    {
                        mutex_cond_timedwait(&queue->queueMutex, miliseconds);
                    }
                    else
                    {
                        mutex_cond_wait(&queue->queueMutex);
                    }

                    if(queue->set_pointer != queue->get_pointer)
                    {
                        memcpy(mes, (unsigned char*)queue->queue_mem + queue->get_pointer * queue->object_size, queue->object_size);
                        if (need_eject)
                        {
                            increment_pointer(queue, &queue->get_pointer);
                        }
                        result = true;
                    }
                }

                if(result && need_eject)
                    queue->unlocked_size = int_size(queue);
                mutex_unlock(&queue->queueMutex);
            }
            else
            {
                logout("%s %d: Failed mutex_lock\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s %d: Invalid magic value 0x%X\n", __FUNCTION__, __LINE__, (unsigned int)queue->magic);
        }
    }
    else
    {
        logout("%s %d: Invalid argument %p\n", __FUNCTION__, __LINE__, queue);
    }

    return result;
}

bool queue_setMessage(ComQueue_t *queue, void *mes)
{
    bool result = false;
    unsigned int freeSpace;

    if(queue)
    {
        if(queue->magic == QUEUE_MAGIC_VALUE)
        {
            if(mutex_lock(&queue->queueMutex))
            {
                freeSpace = queue->max_num_messages - queue->unlocked_size;

                if(freeSpace <= 1)
                {
                    // queue is full
                }
                else
                {
                    memcpy((unsigned char*)queue->queue_mem + queue->set_pointer * queue->object_size, mes, queue->object_size);
                    increment_pointer(queue, &queue->set_pointer);
                    queue->unlocked_size = int_size(queue);
                    result = true;
                }
                mutex_cond_signal(&queue->queueMutex);
                mutex_unlock(&queue->queueMutex);
            }
            else
            {
                logout("%s %d: Failed mutex_lock\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s %d: Invalid magic value 0x%X\n", __FUNCTION__, __LINE__, (unsigned int)queue->magic);
        }
    }
    else
    {
        logout("%s %d: Invalid argument %p\n", __FUNCTION__, __LINE__, queue);
    }

    return result;
}

unsigned int queue_size(ComQueue_t *queue)
{
    unsigned int result = 0;

    if(queue)
    {
        if(queue->magic == QUEUE_MAGIC_VALUE)
        {
            result = queue->unlocked_size;
        }
        else
        {
            logout("%s %d: Invalid magic value 0x%X\n", __FUNCTION__, __LINE__, (unsigned int)queue->magic);
        }
    }
    else
    {
        logout("%s %d: Invalid argument %p\n", __FUNCTION__, __LINE__, queue);
    }

    return result;
}

