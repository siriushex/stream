#define _GNU_SOURCE
#include <sys/prctl.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <stdio.h>
#include <errno.h>

#include "threadpool.h"
#include "allocator.h"
#include "queue.h"
#include "event.h"
#include "list.h"
#include "log.h"

#define MAGIC_VALUE                 0xA6B493D7
#define MAGIC_THREAD_VALUE          0xEB7AF2D5
#define MAGIC_WAIT_THREAD_VALUE     0x3AD412C1
#define MAGIC_RUN_THREAD_VALUE      0x4523ACE2
#define THREADPOOL_NAME_LEN         0x40
#define THREADPOOL_ALIGN_SIZE       0x10
#define THREADPOOL_STACK_SIZE       0x8000
#define THREADPOOL_MES_MAX          4
#define THREADPOOL_THREAD_IDLE_TIME 60000


#define THREADPOOL_ALIGNED_SIZE(x)  ({  unsigned int aLsize = (unsigned int)(x) & (~(THREADPOOL_ALIGN_SIZE - 1)); \
                                        if((unsigned int)(x) & (THREADPOOL_ALIGN_SIZE - 1)) \
                                            aLsize += THREADPOOL_ALIGN_SIZE; \
                                        aLsize; \
                                    })

typedef enum
{
    threadPool_Event_Exit,
    threadPool_Event_Continue
}threadPool_Event_t;

typedef struct
{
    unsigned int magic;
    allocatorHandle_t handle;
    unsigned int objectSize;
    unsigned int countUsed;
    pthread_mutex_t cachedMutex;
    struct list_head cachedObjects; // list of threadPool_IntContext_t
    char name[THREADPOOL_NAME_LEN];
    cpu_set_t cpuset;
}threadPool_data_t;

typedef struct
{
    unsigned int magic;
    pthread_t thread;
    bool manualControl;
    struct list_head list; // used for store threads
    threadPoolFunction function;
    threadPoolFunctionData_t data;
    threadPool_data_t *parrent;
    char threadName[32];
    cpu_set_t cpuset;
    struct event_data stopEvent;
    ComQueue_t queue; // for threadPool_Event_t
    unsigned char mem[sizeof(threadPool_Event_t) * THREADPOOL_MES_MAX];
}threadPool_IntContext_t;

int threadPool_create(threadPoolHandle_t *handle, const char *name)
{
    int result = EINVAL;
    char allocatorName[THREADPOOL_NAME_LEN];
    pthread_mutexattr_t mutex_attr;
    allocatorHandle_t allocHandle;
    threadPool_data_t *data;

    if(handle && name)
    {
        snprintf(allocatorName, sizeof(allocatorName), "%s-allocator", name);
        result = allocator_create(&allocHandle, allocatorName, (void**)&data, sizeof(threadPool_data_t));
        if(result == 0)
        {
            pthread_mutexattr_init(&mutex_attr);
            pthread_mutexattr_settype(&mutex_attr, PTHREAD_MUTEX_NORMAL); //PTHREAD_MUTEX_ERRORCHECK);
            pthread_mutex_init(&data->cachedMutex, &mutex_attr);
            pthread_mutexattr_destroy(&mutex_attr);
            INIT_LIST_HEAD(&data->cachedObjects);
            if(pthread_getaffinity_np(pthread_self(), sizeof(cpu_set_t), &data->cpuset))
                logout("%s %d: Failed get affinity\n", __FUNCTION__, __LINE__);
            data->handle = allocHandle;
            strncpy(data->name, name, sizeof(data->name) - 1);
            data->magic = MAGIC_VALUE;
            *handle = data;
        }
        else
        {
            logout("%s %d: Failed create allocator\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

void* threadPool_getContext(threadPoolHandle_t handle, unsigned int size)
{
    void *context = 0;
    threadPool_data_t *data;
    unsigned int chunkSize;
    int res;

    if(handle)
    {
        data = (threadPool_data_t *)handle;
        if(data->magic == MAGIC_VALUE)
        {
            chunkSize = THREADPOOL_ALIGNED_SIZE(sizeof(threadPool_IntContext_t)) + THREADPOOL_ALIGNED_SIZE(size);
            if((data->objectSize == chunkSize) || (data->objectSize == 0))
            {
                res = pthread_mutex_lock(&data->cachedMutex);
                if(res == 0)
                {
                    threadPool_IntContext_t *intContext = 0;

                    if(!list_empty(&data->cachedObjects))
                    {
                        intContext = list_entry(data->cachedObjects.next, threadPool_IntContext_t, list);
                        list_del_init(&intContext->list);
                    }
                    res = pthread_mutex_unlock(&data->cachedMutex);
                    if(res)
                        logout("%s %d: Failed (%d) unlock mutex\n", __FUNCTION__, __LINE__, res);

                    if(intContext)
                        context = (unsigned char*)intContext + THREADPOOL_ALIGNED_SIZE(sizeof(threadPool_IntContext_t));
                }
                else
                {
                    logout("%s %d: Failed (%d) lock mutex\n", __FUNCTION__, __LINE__, res);
                }

                if(!context)
                {
                    threadPool_IntContext_t *intContext = allocator_get_object(data->handle, chunkSize);
                    if(intContext)
                    {
                        memset(intContext, 0, THREADPOOL_ALIGNED_SIZE(sizeof(threadPool_IntContext_t)));
                        INIT_LIST_HEAD(&intContext->list); // used for check inserted
                        intContext->magic = MAGIC_THREAD_VALUE;
                        context = (unsigned char*)intContext + THREADPOOL_ALIGNED_SIZE(sizeof(threadPool_IntContext_t));
                        data->objectSize = chunkSize;
                    }
                    else
                    {
                        logout("%s %d: Failed alloc chunk with %u bytes\n", __FUNCTION__, __LINE__, chunkSize);
                    }
                }
            }
            else
            {
                logout("%s %d: Invalid object size %u != %u\n", __FUNCTION__, __LINE__, data->objectSize, chunkSize);
            }
        }
        else
        {
            logout("%s %d: Invalid magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, data->magic, MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return context;
}

static void dummy_signal_handler(int sig __attribute__((unused)))
{
}

static void *threadPoolEntryPoint(void *arg)
{
    threadPool_IntContext_t *context;
    threadPool_Event_t event;
    bool sendevent;
    int need_exit;
    sigset_t set;
    int res;

    signal(SIGUSR1, dummy_signal_handler); // set dummy handler

    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    res = pthread_sigmask(SIG_UNBLOCK, &set, NULL);
    if(res == 0)
    {
        if(arg)
        {
            context = (threadPool_IntContext_t *)arg;
            if(strlen(context->threadName))
                prctl(PR_SET_NAME, context->threadName, 0, 0, 0);
            pthread_detach(pthread_self());
            if(pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &context->cpuset))
                logout("%s %d: Failed get affinity\n", __FUNCTION__, __LINE__);

            while(true)
            {
                context->function(&context->data);
                res = pthread_mutex_lock(&context->parrent->cachedMutex);
                if(res == 0)
                {
                    context->magic = MAGIC_WAIT_THREAD_VALUE;
                    if(context->manualControl == false)
                    {
                        list_add(&context->list, &context->parrent->cachedObjects);
                        sendevent = false;
                    }
                    else
                        sendevent = true;
                    res = pthread_mutex_unlock(&context->parrent->cachedMutex);
                    if(res)
                        logout("%s %d: Failed (%d) unlock mutex\n", __FUNCTION__, __LINE__, res);

                    if(sendevent)
                    {
                        res = event_send(&context->stopEvent);
                        if(res)
                            logout("%s %d: Failed (%d) unlock mutex\n", __FUNCTION__, __LINE__, res);
                    }
                    need_exit = 0;
                    while(true)
                    {
                        if(queue_getMessage(&context->queue, &event, THREADPOOL_THREAD_IDLE_TIME, true))
                        {
                            if(event == threadPool_Event_Continue)
                            {
                                break; // continue without exit
                            }
                            else if(event == threadPool_Event_Exit)
                            {
                                res = pthread_mutex_lock(&context->parrent->cachedMutex);
                                if(res == 0)
                                {
                                    list_del(&context->list);
                                    res = pthread_mutex_unlock(&context->parrent->cachedMutex);
                                    if(res)
                                        logout("%s %d: Failed (%d) unlock mutex\n", __FUNCTION__, __LINE__, res);
                                }
                                else
                                {
                                    logout("%s %d: Failed (%d) lock mutex\n", __FUNCTION__, __LINE__, res);
                                }
                                need_exit = 1;
                                break;
                            }
                            else
                            {
                                logout("%s %d: Unknown event 0x%X\n", __FUNCTION__, __LINE__, event);
                                need_exit = 1;
                                break;
                            }
                        }
                        else // timeout
                        {
                            res = pthread_mutex_lock(&context->parrent->cachedMutex);
                            if(res == 0)
                            {
                                if(list_empty(&context->list))
                                {
                                    // deleted from cache - wait message
                                }
                                else
                                {
                                    list_del(&context->list);
                                    need_exit = 1;
                                }
                                res = pthread_mutex_unlock(&context->parrent->cachedMutex);
                                if(res)
                                    logout("%s %d: Failed (%d) unlock mutex\n", __FUNCTION__, __LINE__, res);
                            }
                            else
                            {
                                logout("%s %d: Failed (%d) lock mutex\n", __FUNCTION__, __LINE__, res);
                                need_exit = 1;
                            }
                            if(need_exit)
                                break;
                        }
                    }

                    if(need_exit)
                        break;
                }
                else
                {
                    logout("%s %d: Failed (%d) lock mutex\n", __FUNCTION__, __LINE__, res);
                }
            }
            context->magic = 0;
            res = destroy_queue(&context->queue);
            if(res)
                logout("%s %d: Failed destroy queue\n", __FUNCTION__, __LINE__);
            if(context->manualControl)
            {
                res = event_destroy(&context->stopEvent);
                if(res)
                    logout("%s %d: Failed destroy event\n", __FUNCTION__, __LINE__);
            }
            allocator_put_object(context->parrent->handle, context);
        }
        else
        {
            logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: Failed set sigmask %d\n", __FUNCTION__, __LINE__, res);
    }

    return 0;
}

int threadPool_startInContext(threadPoolHandle_t handle, threadPoolFunction function, void *ctx, const char *name, threadPoolPriority_t priority, bool manualControl)
{
    const size_t stacksize = THREADPOOL_STACK_SIZE;
    int result = EINVAL;
    threadPool_IntContext_t *intContext;
    struct sched_param param;
    threadPool_Event_t event;
    threadPool_data_t *data;
    sigset_t set, oldset;
    pthread_attr_t attr;
    int res;

    if(handle && function && ctx && name)
    {
        data = (threadPool_data_t *)handle;
        if(data->magic == MAGIC_VALUE)
        {
            intContext = (threadPool_IntContext_t *)((unsigned char *)ctx - THREADPOOL_ALIGNED_SIZE(sizeof(threadPool_IntContext_t)));
            if(intContext->magic == MAGIC_WAIT_THREAD_VALUE)
            {
                if(manualControl)
                {
                    res = event_reset(&intContext->stopEvent);
                    if(res)
                        logout("%s %d: failed reset event\n", __FUNCTION__, __LINE__);
                }
                intContext->function = function;
                intContext->data.needExecute = 1;
                intContext->data.ctx = ctx;
                intContext->manualControl = manualControl;
                intContext->magic = MAGIC_RUN_THREAD_VALUE;
                event = threadPool_Event_Continue;
                if(queue_setMessage(&intContext->queue, &event))
                {
                    result = 0;
                }
                else
                {
                    logout("%s %d: failed send message to thread\n", __FUNCTION__, __LINE__);
                    intContext->magic = MAGIC_THREAD_VALUE;
                }
            }
            else if(intContext->magic == MAGIC_THREAD_VALUE)
            {
                pthread_attr_init(&attr);
                pthread_attr_setstacksize(&attr, stacksize);

                switch(priority)
                {
                    case threadPoolPriority_Low:
                        param.sched_priority = sched_get_priority_min(SCHED_RR);
                        break;
                    case threadPoolPriority_Normal:
                        param.sched_priority = sched_get_priority_min(SCHED_RR) + (sched_get_priority_max(SCHED_RR) - sched_get_priority_min(SCHED_RR)) / 3;
                        break;
                    case threadPoolPriority_High:
                        param.sched_priority = sched_get_priority_min(SCHED_RR) + 2 * (sched_get_priority_max(SCHED_RR) - sched_get_priority_min(SCHED_RR)) / 3;
                        break;
                    case threadPoolPriority_Highest:
                        param.sched_priority = sched_get_priority_max(SCHED_RR);
                        break;
                }

                pthread_attr_setschedpolicy(&attr, SCHED_RR);
                pthread_attr_setschedparam(&attr, &param);

                sigemptyset(&set);
                sigaddset(&set, SIGUSR1);
                res = pthread_sigmask(SIG_BLOCK, &set, &oldset);
                if(res == 0)
                {
                    intContext->function = function;
                    intContext->data.needExecute = 1;
                    intContext->data.ctx = ctx;
                    intContext->parrent = data;
                    memset(intContext->threadName, 0, sizeof(intContext->threadName));
                    strncpy(intContext->threadName, name, sizeof(intContext->threadName) - 1);
                    intContext->manualControl = manualControl;
                    intContext->magic = MAGIC_RUN_THREAD_VALUE;
                    intContext->cpuset = data->cpuset;

                    res = create_queue_noalloc(&intContext->queue, sizeof(threadPool_Event_t), THREADPOOL_MES_MAX, intContext->mem);
                    if(res == 0)
                    {
                        if(manualControl)
                            res = event_create(&intContext->stopEvent);

                        if(res == 0)
                        {
                            if((res = pthread_create(&intContext->thread, &attr, threadPoolEntryPoint, intContext)) == 0)
                            {
                                result = 0;
                            }
                            else
                            {
                                char buffer[128] = {0, };
                                char *ptr;
                                ptr = strerror_r(res, buffer, sizeof(buffer));
                                buffer[sizeof(buffer) - 1] = 0;

                                logout("%s %d: failed create thread: %d(%s)\n", __FUNCTION__, __LINE__, res, ptr);

                                intContext->magic = MAGIC_THREAD_VALUE;
                            }
                        }
                        else
                        {
                            logout("%s %d: failed create event\n", __FUNCTION__, __LINE__);
                        }
                    }
                    else
                    {
                        logout("%s %d: failed create queue\n", __FUNCTION__, __LINE__);
                    }
                }
                else
                {
                    logout("%s %d: failed set sigmask\n", __FUNCTION__, __LINE__);
                }
                pthread_sigmask(SIG_SETMASK, &oldset, NULL);
                pthread_attr_destroy(&attr);
            }
            else
            {
                logout("%s %d: Invalid thread magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, intContext->magic, MAGIC_THREAD_VALUE);
            }
        }
        else
        {
            logout("%s %d: Invalid magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, data->magic, MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

int threadPool_set_stop(threadPoolHandle_t handle, void *ctx)
{
    int result = EINVAL;
    threadPool_IntContext_t *intContext;
    threadPool_data_t *data;

    if(handle && ctx)
    {
        data = (threadPool_data_t *)handle;
        if(data->magic == MAGIC_VALUE)
        {
            intContext = (threadPool_IntContext_t *)((unsigned char *)ctx - THREADPOOL_ALIGNED_SIZE(sizeof(threadPool_IntContext_t)));
            if(intContext->magic == MAGIC_RUN_THREAD_VALUE)
            {
                if(intContext->manualControl)
                {
                    intContext->data.needExecute = 0;
                    pthread_kill(intContext->thread, SIGUSR1);
                    result = 0;
                }
                else
                {
                    logout("%s %d: Thread without manual control\n", __FUNCTION__, __LINE__);
                }
            }
            else if((intContext->magic == MAGIC_THREAD_VALUE) || (intContext->magic == MAGIC_WAIT_THREAD_VALUE))
            {
                // already stoped
                result = 0;
            }
            else
            {
                logout("%s %d: Invalid thread magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, intContext->magic, MAGIC_THREAD_VALUE);
            }
        }
        else
        {
            logout("%s %d: Invalid magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, data->magic, MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

int threadPool_stop(threadPoolHandle_t handle, void *ctx)
{
    int result = EINVAL;
    threadPool_IntContext_t *intContext;
    threadPool_data_t *data;

    if(handle && ctx)
    {
        data = (threadPool_data_t *)handle;
        if(data->magic == MAGIC_VALUE)
        {
            intContext = (threadPool_IntContext_t *)((unsigned char *)ctx - THREADPOOL_ALIGNED_SIZE(sizeof(threadPool_IntContext_t)));
            if(intContext->magic == MAGIC_RUN_THREAD_VALUE)
            {
                if(intContext->manualControl)
                {
                    intContext->data.needExecute = 0;

                    while(intContext->magic == MAGIC_RUN_THREAD_VALUE)
                    {
                        pthread_kill(intContext->thread, SIGUSR1);
                        event_wait(&intContext->stopEvent, 100);
                    }
                    result = 0;
                }
                else
                {
                    logout("%s %d: Thread without manual control\n", __FUNCTION__, __LINE__);
                }
            }
            else if((intContext->magic == MAGIC_THREAD_VALUE) || (intContext->magic == MAGIC_WAIT_THREAD_VALUE))
            {
                // already stoped
                result = 0;
            }
            else
            {
                logout("%s %d: Invalid thread magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, intContext->magic, MAGIC_THREAD_VALUE);
            }
        }
        else
        {
            logout("%s %d: Invalid magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, data->magic, MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

int threadPool_putContext(threadPoolHandle_t handle, void *ctx)
{
    int result = EINVAL;
    threadPool_IntContext_t *intContext;
    threadPool_data_t *data;
    int res;

    if(handle && ctx)
    {
        data = (threadPool_data_t *)handle;
        if(data->magic == MAGIC_VALUE)
        {
            intContext = (threadPool_IntContext_t *)((unsigned char *)ctx - THREADPOOL_ALIGNED_SIZE(sizeof(threadPool_IntContext_t)));
            if(intContext->magic == MAGIC_WAIT_THREAD_VALUE)
            {
                res = pthread_mutex_lock(&data->cachedMutex);
                if(res == 0)
                {
                    if(list_empty(&intContext->list))
                    {
                        list_add(&intContext->list, &data->cachedObjects);
                        result = 0;
                    }
                    else
                    {
                        logout("%s %d: Failed put context\n", __FUNCTION__, __LINE__);
                    }
                    res = pthread_mutex_unlock(&data->cachedMutex);
                    if(res)
                        logout("%s %d: Failed (%d) unlock mutex\n", __FUNCTION__, __LINE__, res);
                }
                else
                {
                    logout("%s %d: Failed (%d) lock mutex\n", __FUNCTION__, __LINE__, res);
                }
            }
            else if(intContext->magic == MAGIC_THREAD_VALUE)
            {
                allocator_put_object(data->handle, intContext);
                result = 0;
            }
            else
            {
                logout("%s %d: Invalid thread magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, intContext->magic, MAGIC_THREAD_VALUE);
            }
        }
        else
        {
            logout("%s %d: Invalid magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, data->magic, MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

static void threadPool_iterator(void *ctx, allocatorHandle_t handle, void *address)
{
    threadPool_IntContext_t *intContext;
    threadPool_data_t *data;

    if(ctx && handle && address)
    {
        data = (threadPool_data_t *)ctx;
        if(data->magic == MAGIC_VALUE)
        {
            if(data->handle == handle)
            {
                intContext = (threadPool_IntContext_t *)address;

                if(intContext->magic == MAGIC_RUN_THREAD_VALUE)
                {
                    intContext->data.needExecute = 0;
                    pthread_kill(intContext->thread, SIGUSR1);
                    data->countUsed++;
                }
                else if(intContext->magic == MAGIC_WAIT_THREAD_VALUE)
                {
                    data->countUsed++;
                }
            }
            else
            {
                logout("%s %d: Invalid handle %p != %p\n", __FUNCTION__, __LINE__, data->handle, handle);
            }
        }
        else
        {
            logout("%s %d: Invalid magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, data->magic, MAGIC_VALUE);
        }
    }
}

int threadPool_destroy(threadPoolHandle_t handle)
{
    int result = EINVAL;
    struct list_head *iterator;
    threadPool_Event_t event;
    threadPool_data_t *data;
    int counter = 0;
    int res;

    if(handle)
    {
        data = (threadPool_data_t *)handle;
        if(data->magic == MAGIC_VALUE)
        {
            do{
                if(!list_empty(&data->cachedObjects))
                {
                    event = threadPool_Event_Exit;
                    res = pthread_mutex_lock(&data->cachedMutex);
                    if(res == 0)
                    {
                        list_for_each(iterator, &data->cachedObjects)
                        {
                            threadPool_IntContext_t *intContext = list_entry(iterator, threadPool_IntContext_t, list);
                            if(!queue_setMessage(&intContext->queue, &event))
                                logout("%s %d: Failed (%d) send message\n", __FUNCTION__, __LINE__, res);
                        }
                        res = pthread_mutex_unlock(&data->cachedMutex);
                        if(res)
                            logout("%s %d: Failed (%d) unlock mutex\n", __FUNCTION__, __LINE__, res);
                    }
                    else
                    {
                        logout("%s %d: Failed (%d) lock mutex\n", __FUNCTION__, __LINE__, res);
                    }
                }
                data->countUsed = 0;
                allocator_iterate_used(data->handle, threadPool_iterator, data);
                if(data->countUsed)
                {
                    logout("%s %d: Count used threads %u\n", __FUNCTION__, __LINE__, data->countUsed);
                    if(counter++ > 20)
                    {
                        logout("%s %d: No time to wait! Exit!\n", __FUNCTION__, __LINE__);
                        break;
                    }
                    sleep(1);
                }
                else
                {
                    break;
                }
            }while(data->countUsed);

            result = allocator_destroy(data->handle);
        }
        else
        {
            logout("%s %d: Invalid magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, data->magic, MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

