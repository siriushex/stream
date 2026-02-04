#ifndef __MUTEX_H__
#define __MUTEX_H__

#include <stdbool.h>
#include <pthread.h>

typedef struct
{
    pthread_mutex_t mVal;
    pthread_cond_t mCond;
    bool withCond;
}mutex_t;

bool mutex_init(mutex_t *mutex, bool withCond);
void mutex_term(mutex_t *mutex);
bool mutex_lock(mutex_t *mutex);
void mutex_unlock(mutex_t *mutex);
void mutex_cond_timedwait(mutex_t *mutex, unsigned long msec);
void mutex_cond_wait(mutex_t *mutex);
void mutex_cond_signal(mutex_t *mutex);

#endif /* __MUTEX_H__ */

