#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <pthread.h>
#include <stdarg.h>
#include <unistd.h>
#include <syslog.h>
#include <string.h>
#include <limits.h>
#include <fcntl.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>
#include "log.h"

#define LOG_FORMAT      "/tmp/%s_%d.log"
#define LOG_FORMAT_NP   "%s"
#define LOX_MAX_SIZE    (20 * 1024 * 1024)  // size of single logfile

static int outfd = -1;
static char filename[PATH_MAX];
static int gUsePidInName = 1;
static char curfilename[PATH_MAX];
static char oldfilename[PATH_MAX];
static pthread_mutex_t logmutex = PTHREAD_MUTEX_INITIALIZER;
unsigned int logSize = 0;
static logType_t gLogtype = logType_none;

void loginit(char *logname, logType_t type, int usePidInName)
{
    if(logname)
    {
        gUsePidInName = usePidInName;
        memset(filename, 0, sizeof(filename));
        strncpy(filename, logname, sizeof(filename) - 1);
        if(gUsePidInName)
            snprintf(curfilename, sizeof(curfilename), LOG_FORMAT, filename, (int)getpid());
        else
            snprintf(curfilename, sizeof(curfilename), LOG_FORMAT_NP, filename);
        gLogtype = type;
        if(type & logType_file)
        {
            outfd = open(curfilename, O_WRONLY | O_CREAT | O_TRUNC, S_IWUSR | S_IRUSR | S_IRGRP | S_IROTH);
            if(outfd == -1)
            {
                fprintf(stderr, "%s %d: Failed(%s) create log file(%s)\n", __FUNCTION__, __LINE__, strerror(errno), curfilename);
            }
            else
            {
                fchown(outfd, getuid(), getgid());
            }
        }
    }
}

void logdeinit()
{
    if(outfd != -1)
    {
        close(outfd);
        outfd = -1;
    }
    closelog();
}

static void renew_internal(int locked)
{
    if(!locked)
        pthread_mutex_lock(&logmutex);

    if(outfd != -1)
    {
        if(gUsePidInName)
            snprintf(oldfilename, sizeof(oldfilename), LOG_FORMAT ".old", filename, (int)getpid());
        else
            snprintf(oldfilename, sizeof(oldfilename), LOG_FORMAT_NP ".old", filename);
        close(outfd);
        unlink(oldfilename);
        rename(curfilename, oldfilename);
        outfd = -1;
    }

    if(gUsePidInName)
        snprintf(curfilename, sizeof(curfilename), LOG_FORMAT, filename, (int)getpid());
    else
        snprintf(curfilename, sizeof(curfilename), LOG_FORMAT_NP, filename);
    outfd = open(curfilename, O_WRONLY | O_CREAT | O_TRUNC, S_IWUSR | S_IRUSR | S_IRGRP | S_IROTH);
    if(outfd == -1)
    {
        fprintf(stderr, "%s %d: Failed create log file(%s)\n", __FUNCTION__, __LINE__, curfilename);
    }
    else
    {
        logSize = 0;
    }

    if(!locked)
        pthread_mutex_unlock(&logmutex);
}

void logout(const char *mes, ...)
{
    if(gLogtype & (logType_file | logType_terminal))
    {
        char buffer[2048];
        struct timeval curtime;
        struct tm humantime;
        va_list ap;
        int len;
        int n;

        gettimeofday(&curtime, 0);
        gmtime_r(&curtime.tv_sec, &humantime);
        buffer[sizeof(buffer) - 1] = 0;
        len = snprintf(buffer, sizeof(buffer) - 1, "%02d/%02d/%04d %02d:%02d:%02d:%06d ", humantime.tm_mday, humantime.tm_mon + 1, humantime.tm_year + 1900, humantime.tm_hour, humantime.tm_min, humantime.tm_sec, (int)curtime.tv_usec);

        va_start(ap, mes);
        n = vsnprintf(buffer + len, sizeof(buffer) - len - 1, mes, ap);
        va_end(ap);
        if(n > 0)
            len += n;
        if((len > 0) && (len < sizeof(buffer) - 1))
        {
            if(buffer[len - 1] != '\n')
            {
                buffer[len] = '\n';
                len++;
                buffer[len] = 0;
            }
        }

        if(len)
        {
            if(gLogtype & logType_terminal)
                fwrite(buffer, len, 1, stderr);

            if((outfd != -1) && (gLogtype & logType_file))
            {
                pthread_mutex_lock(&logmutex);
                n = write(outfd, buffer, len);
                if(n >= 0)
                {
                    logSize += n;
                    if(logSize > LOX_MAX_SIZE)
                        renew_internal(1);
                }
                pthread_mutex_unlock(&logmutex);
            }
        }
    }

    if(gLogtype & logType_syslog)
    {
        va_list ap;
        int error = 0;

        if(strcasestr(mes, "failed") != NULL)
            error = 1;
        else if(strcasestr(mes, "error") != NULL)
            error = 1;
        else if(strcasestr(mes, "invalid") != NULL)
            error = 1;

        va_start(ap, mes);
        vsyslog(error ? LOG_ERR : LOG_INFO, mes, ap);
        va_end(ap);
    }
}

void logrenew()
{
    renew_internal(0);
}

