#define _GNU_SOURCE
#include <sys/prctl.h>
#include <pthread.h>
#include <stdlib.h>
#include <signal.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <sched.h>
#include "thread.h"
#include "log.h"

#define THREAD_MAGIC_VAL    0xE4D7BCA3

typedef struct
{
    pthread_t thread;
    unsigned int magic;
    threadFunction function;
    threadFunctionData_t data;
    allocatorHandle_t allocator;
    char threadName[32];
    int detached;
}threadIntHandle_t;

static void dummy_signal_handler(int sig __attribute__((unused)))
{
}

static void *threadEntryPoint(void *arg)
{
    threadIntHandle_t *handle = (threadIntHandle_t *)arg;
    int detached;
    sigset_t set;
    int res;

    signal(SIGUSR1, dummy_signal_handler); // set dummy handler

    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    res = pthread_sigmask(SIG_UNBLOCK, &set, NULL);
    if(res == 0)
    {
#if 0 // get affinity
        cpu_set_t cpuset;

        res = pthread_getaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
        if(res != 0)
            logout("%s %d: failed pthread_getaffinity_np\n", __FUNCTION__, __LINE__);
        else
        {
            printf("Set returned by pthread_getaffinity_np() contained:\n");
            for (res = 0; res < CPU_SETSIZE; res++)
                if (CPU_ISSET(res, &cpuset))
                    printf(" CPU%d \n", res);
        }
#endif
        if(handle)
        {
            if(strlen(handle->threadName))
                prctl(PR_SET_NAME, handle->threadName, 0, 0, 0);
            detached = handle->detached;
            if(detached)
                pthread_detach(pthread_self());
            handle->function(&handle->data);
            if(detached)
            {
                handle->magic = 0;
                if(handle->allocator)
                    allocator_put_object(handle->allocator, handle);
                else
                    free(handle);
            }
        }
    }
    return 0;
}

int thread_start(threadHandle_t *handle, threadFunction function, void *ctx, const char *name, threadPriority_t priority, allocatorHandle_t allocator, int detached)
{
    int result = EINVAL;
    const size_t stacksize = THREAD_STACK_SIZE;
    threadIntHandle_t *newHandle;
    struct sched_param param;
    sigset_t set, oldset;
    pthread_attr_t attr;
    int res;

    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, stacksize);

    switch(priority)
    {
        case threadPriority_Low:
            param.sched_priority = sched_get_priority_min(SCHED_RR);
            break;
        case threadPriority_Normal:
            param.sched_priority = sched_get_priority_min(SCHED_RR) + (sched_get_priority_max(SCHED_RR) - sched_get_priority_min(SCHED_RR)) / 3;
            break;
        case threadPriority_High:
            param.sched_priority = sched_get_priority_min(SCHED_RR) + 2 * (sched_get_priority_max(SCHED_RR) - sched_get_priority_min(SCHED_RR)) / 3;
            break;
        case threadPriority_Highest:
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
        if(allocator)
            newHandle = allocator_get_object(allocator, sizeof(threadIntHandle_t));
        else
            newHandle = malloc(sizeof(threadIntHandle_t));
        if(newHandle)
        {
            memset(newHandle, 0, sizeof(threadIntHandle_t));
            newHandle->magic = THREAD_MAGIC_VAL;
            newHandle->function = function;
            newHandle->data.needExecute = 1;
            newHandle->data.ctx = ctx;
            newHandle->allocator = allocator;
            newHandle->detached = detached;
            if(name)
                strncpy(newHandle->threadName, name, sizeof(newHandle->threadName) - 1);
            *handle = (threadHandle_t)newHandle;
            if((res = pthread_create(&newHandle->thread, &attr, threadEntryPoint, newHandle)) != 0)
            {
                char buffer[128] = {0, };
                char *ptr;
                ptr = strerror_r(res, buffer, sizeof(buffer));
                buffer[sizeof(buffer) - 1] = 0;

                logout("%s %d: failed create thread: %d(%s)\n", __FUNCTION__, __LINE__, res, ptr);
                newHandle->magic = 0;
                *handle = 0;
            }
            else
            {
                result = 0;
            }

            if(result)
            {
                if(allocator)
                    allocator_put_object(allocator, newHandle);
                else
                    free(newHandle);
            }
        }
        else
        {
            logout("%s %d: failed alloc %d bytes of memory\n", __FUNCTION__, __LINE__, (int)sizeof(threadIntHandle_t));
        }
    }
    else
    {
        logout("%s %d: failed set sigmask\n", __FUNCTION__, __LINE__);
    }

    pthread_sigmask(SIG_SETMASK, &oldset, NULL);
    pthread_attr_destroy(&attr);

    return result;
}

static int wait_stop(pthread_t thread, unsigned int mseconds)
{
    int result = 1;
    struct timespec abstime;
    int error;

    clock_gettime(CLOCK_REALTIME, &abstime);
    if(mseconds > 1000)
    {
        abstime.tv_sec += mseconds / 1000;
        mseconds = mseconds % 1000;
    }

    mseconds *= 1000000;
    if(abstime.tv_nsec + mseconds > 1000000000)
    {
        abstime.tv_nsec = (abstime.tv_nsec + mseconds - 1000000000);
        abstime.tv_sec ++;
    }
    else
        abstime.tv_nsec += mseconds;

    if((error = pthread_timedjoin_np(thread, NULL, &abstime)) == 0)
    {
        result = 0;
    }
    else if((error == EINVAL) || (error == ESRCH))
    {
        // No thread found
        result = 0;
    }

    return result;
}

int thread_set_stop(threadHandle_t han)
{
    int result = EINVAL;
    threadIntHandle_t *handle = (threadIntHandle_t *)han;

    if(handle)
    {
        if(handle->magic == THREAD_MAGIC_VAL)
        {
            if(!pthread_equal(handle->thread, pthread_self()))
            {
                handle->data.needExecute = 0;
                pthread_kill(handle->thread, SIGUSR1);
                result = 0;
            }
            else
            {
                logout("%s %d: The thread can't stop self. %d == %d!\n", __FUNCTION__, __LINE__, (int)handle->thread, (int)pthread_self());
            }
        }
        else
        {
            logout("%s %d: invalid magic of handle\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: invalid handle\n", __FUNCTION__, __LINE__);
    }

    return result;
}

int thread_stop(threadHandle_t han)
{
    int result = EINVAL;
    threadIntHandle_t *handle = (threadIntHandle_t *)han;

    if(handle)
    {
        if(handle->magic == THREAD_MAGIC_VAL)
        {
            if(!pthread_equal(handle->thread, pthread_self()))
            {
                handle->data.needExecute = 0;
                do {
                    pthread_kill(handle->thread, SIGUSR1);
                    result = wait_stop(handle->thread, 50); // wait 50ms for exit
                }while(result);
            }
            else
            {
                logout("%s %d: The thread can't stop self. %d == %d!\n", __FUNCTION__, __LINE__, (int)handle->thread, (int)pthread_self());
            }
            handle->magic = 0;
            if(handle->allocator)
                allocator_put_object(handle->allocator, handle);
            else
                free(handle);
        }
        else
        {
            logout("%s %d: invalid magic of handle\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: invalid handle\n", __FUNCTION__, __LINE__);
    }

    return result;
}

int thread_wait(threadHandle_t han)
{
    int result = EINVAL;
    threadIntHandle_t *handle = (threadIntHandle_t *)han;

    if(handle)
    {
        if(handle->magic == THREAD_MAGIC_VAL)
        {
            if(!pthread_equal(handle->thread, pthread_self()))
            {
                result = pthread_join(handle->thread, 0);
            }
            else
            {
                logout("%s %d: The thread can't stop self. %d == %d!\n", __FUNCTION__, __LINE__, (int)handle->thread, (int)pthread_self());
            }
        }
        else
        {
            logout("%s %d: invalid magic of handle\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: invalid handle\n", __FUNCTION__, __LINE__);
    }

    return result;
}

void disable_signal()
{
    sigset_t set;

    sigemptyset(&set);
    sigaddset(&set, SIGUSR1);
    pthread_sigmask(SIG_BLOCK, &set, NULL);
}

