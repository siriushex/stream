#ifndef __LOG_H__
#define __LOG_H__

typedef enum
{
    logType_none        = 0x00,
    logType_terminal    = 0x01,
    logType_file        = 0x02,
    logType_syslog      = 0x04
}logType_t;

#ifdef __cplusplus
extern "C"
{
#endif

void loginit(char *logname, logType_t type, int usePidInName);
void logdeinit(void);
void logout(const char *mes, ...) __attribute__((format(printf, 1, 2)));
void logrenew(void);

#ifdef __cplusplus
}
#endif

#endif // __LOG_H__
