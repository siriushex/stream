#include "mutex.h"
#include "log.h"

bool mutex_init(mutex_t *mutex, bool withCond)
{
    bool result = false;

    if(mutex)
    {
        pthread_mutexattr_t mutex_attr;
        int res;

        mutex->withCond = withCond;

        if((res = pthread_mutexattr_init(&mutex_attr)) == 0)
        {
            if((res = pthread_mutexattr_settype(&mutex_attr, PTHREAD_MUTEX_NORMAL)) == 0) //PTHREAD_MUTEX_ERRORCHECK));
            {
                if((res = pthread_mutex_init(&mutex->mVal, &mutex_attr)) == 0)
                {
                    if (mutex->withCond)
                    {
                        if ((res = pthread_cond_init(&mutex->mCond, 0)) == 0)
                        {
                            result = true;
                        }
                        else
                        {
                            logout("%s %d: Error %d pthread_cond_init\n", __FUNCTION__, __LINE__, res);
                        }
                    }
                    else
                        result = true;

                    if (!result)
                    {
                        if((res = pthread_mutex_destroy(&mutex->mVal)) != 0)
                            logout("%s %d: Error %d pthread_mutex_destroy\n", __FUNCTION__, __LINE__, res);
                    }
                }
                else
                {
                    logout("%s %d: error %d pthread_mutex_init\n", __FUNCTION__, __LINE__, res);
                }
            }
            else
            {
                logout("%s %d: error %d pthread_mutexattr_settype\n", __FUNCTION__, __LINE__, res);
            }
            if((res = pthread_mutexattr_destroy(&mutex_attr)) != 0)
            {
                logout("%s %d: error pthread_mutexattr_destroy\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s %d: error %d pthread_mutexattr_init\n", __FUNCTION__, __LINE__, res);
        }
    }
    else
    {
        logout("%s %d: Invalid arguments\n", __FUNCTION__, __LINE__);
    }

    return result;
}

void mutex_term(mutex_t *mutex)
{
    if (mutex)
    {
        int res;
        res = pthread_mutex_destroy(&mutex->mVal);
        if(res != 0)
            logout("%s %d: Error %d pthread_mutex_destroy\n", __FUNCTION__, __LINE__, res);
        if(mutex->withCond)
        {
            res = pthread_cond_destroy(&mutex->mCond);
            if(res != 0)
                logout("%s %d: Error %d pthread_cond_destroy\n", __FUNCTION__, __LINE__, res);
        }
    }
    else
    {
        logout("%s %d: Invalid arguments\n", __FUNCTION__, __LINE__);
    }
}

bool mutex_lock(mutex_t *mutex)
{
    bool result = false;

    if (mutex)
    {
        int res = pthread_mutex_lock(&mutex->mVal);
        if(res == 0)
        {
            result = true;
        }
        else
        {
            logout("%s %d: Error %d pthread_mutex_lock\n", __FUNCTION__, __LINE__, res);
        }
    }
    else
    {
        logout("%s %d: Invalid arguments\n", __FUNCTION__, __LINE__);
    }

    return result;
}

void mutex_unlock(mutex_t *mutex)
{
    if (mutex)
    {
        int res = pthread_mutex_unlock(&mutex->mVal);
        if(res != 0)
            logout("%s %d: Error %d pthread_mutex_unlock\n", __FUNCTION__, __LINE__, res);
    }
    else
    {
        logout("%s %d: Invalid arguments\n", __FUNCTION__, __LINE__);
    }
}

void mutex_cond_timedwait(mutex_t *mutex, unsigned long msec)
{
    if (mutex)
    {
        if(mutex->withCond)
        {
            struct timespec abstime;

            clock_gettime(CLOCK_REALTIME, &abstime);
            if(msec > 1000)
            {
                abstime.tv_sec += msec / 1000;
                msec = msec % 1000;
            }
            msec *= 1000000;
            if(abstime.tv_nsec + msec > 1000000000)
            {
                abstime.tv_nsec = (abstime.tv_nsec + msec - 1000000000);
                abstime.tv_sec ++;
            }
            else
                abstime.tv_nsec += msec;

            pthread_cond_timedwait(&mutex->mCond, &mutex->mVal, &abstime); // don't check
        }
        else
        {
            logout("%s %d: Mutex without cond variable\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: Invalid arguments\n", __FUNCTION__, __LINE__);
    }
}

void mutex_cond_wait(mutex_t *mutex)
{
    if (mutex)
    {
        if(mutex->withCond)
        {
            int res = pthread_cond_wait(&mutex->mCond, &mutex->mVal);
            if(res != 0)
                logout("%s %d: Error %d pthread_cond_wait\n", __FUNCTION__, __LINE__, res);
        }
        else
        {
            logout("%s %d: Mutex without cond variable\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: Invalid arguments\n", __FUNCTION__, __LINE__);
    }
}

void mutex_cond_signal(mutex_t *mutex)
{
    if (mutex)
    {
        if(mutex->withCond)
        {
            int res = pthread_cond_signal(&mutex->mCond);
            if(res != 0)
                logout("%s %d: Error %d pthread_cond_signal\n", __FUNCTION__, __LINE__, res);
        }
        else
        {
            logout("%s %d: Mutex without cond variable\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: Invalid arguments\n", __FUNCTION__, __LINE__);
    }
}

