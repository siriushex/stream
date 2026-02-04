#ifndef __THREAD_H__
#define __THREAD_H__

#include "allocator.h"

typedef void * threadHandle_t;

#ifndef THREAD_STACK_SIZE
#define THREAD_STACK_SIZE 0x8000
#endif

typedef struct
{
    int needExecute;
    void *ctx;
}threadFunctionData_t;

typedef void (*threadFunction)(threadFunctionData_t *ctx);

typedef enum
{
    threadPriority_Low,
    threadPriority_Normal,
    threadPriority_High,
    threadPriority_Highest
}threadPriority_t;

int thread_start(threadHandle_t *handle, threadFunction function, void *ctx, const char *name, threadPriority_t priority, allocatorHandle_t allocator, int detached);
int thread_set_stop(threadHandle_t handle);
int thread_stop(threadHandle_t handle);
int thread_wait(threadHandle_t handle);
void disable_signal(void);

#endif /* __THREAD_H__ */
