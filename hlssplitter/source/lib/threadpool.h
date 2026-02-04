#ifndef __THREAD_POOL_H__
#define __THREAD_POOL_H__

#include <stdbool.h>

typedef void * threadPoolHandle_t;

typedef struct
{
    int needExecute;
    void *ctx;
}threadPoolFunctionData_t;

typedef void (*threadPoolFunction)(threadPoolFunctionData_t *ctx);

typedef enum
{
    threadPoolPriority_Low,
    threadPoolPriority_Normal,
    threadPoolPriority_High,
    threadPoolPriority_Highest
}threadPoolPriority_t;

int threadPool_create(threadPoolHandle_t *handle, const char *name);
void* threadPool_getContext(threadPoolHandle_t handle, unsigned int size);
int threadPool_startInContext(threadPoolHandle_t handle, threadPoolFunction function, void *ctx, const char *name, threadPoolPriority_t priority, bool manualControl);
int threadPool_set_stop(threadPoolHandle_t handle, void *ctx);
int threadPool_stop(threadPoolHandle_t handle, void *ctx);
int threadPool_putContext(threadPoolHandle_t handle, void *ctx);
int threadPool_destroy(threadPoolHandle_t handle);

#endif /* __THREAD_POOL_H__ */
