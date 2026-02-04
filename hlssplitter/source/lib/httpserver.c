#define _GNU_SOURCE
#include <sys/sysinfo.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/types.h>
#include <sys/poll.h>
#include <sys/time.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <ctype.h>
#include <sched.h>
#include <time.h>

#include "httpserver.h"
#include "threadpool.h"
#include "thread.h"
#include "list.h"
#include "log.h"

#define HTTP_MAGIC_VALUE            0x3E8C94A1
#define HTTP_THREAD_MAGIC_VALUE     0x67CE43B3
#define HTTP_USER_MAGIC_VALUE       0x3EA59462
#define HTTP_LISTEN_BACKLOG         64000
#define HTTP_CLOSE_TIMEOUT          3000 // 3sec

typedef struct
{
    unsigned int magic;
    httpServerCallBack_t callback;
    void *callback_ctx;
    struct sockaddr_in interface;
    unsigned int timeout;
    struct list_head threads; // list of httpServerMainThread_t
}httpServerPrivate_t;

typedef struct httpServerWorkInstance
{
    struct list_head list;
    httpServerPrivate_t *serverData;
    threadPoolHandle_t threadPool;
    threadHandle_t thread;
    unsigned int magic;
    int procnum;
    int socket;
}httpServerMainThread_t;

typedef struct
{
    unsigned int magic;
    int socket;
    httpServerPrivate_t *server;
    httpServerGetData_t data;
    unsigned char buffer[2048];
    unsigned char *buf_ptr;
    unsigned char *buf_end;
}httpServerCallbackData_t;

static const char response_header[] = {
    "HTTP/1.%d %d %s\r\n"
    "Content-Type: text/html\r\n"
    "Content-Length: %d\r\n"
    "Connection: %s\r\n"
    "Date: %s\r\n"
    "Server: %s\r\n"
};

static const char responce_body[] = {
        "<?xml version=\"1.0\" encoding=\"iso-8859-1\"?>\r\n"
        "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\"\r\n"
        "         \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\r\n"
        "<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">\r\n"
        "    <head>\r\n"
        "        <title>%d - %s</title>\r\n"
        "    </head>\r\n"
        "    <body>\r\n"
        "        <h1>%d - %s</h1>\r\n"
        "    </body>\r\n"
        "</html>\r\n"
    };

static int worker_getc(httpServerCallbackData_t *data)
{
    int len;

    if (data->buf_ptr >= data->buf_end)
    {
        len = recv(data->socket, data->buffer, sizeof(data->buffer), MSG_NOSIGNAL);
        if (len < 0)
            return len;
        else if (len == 0)
            return -1;
        else
        {
            data->buf_ptr = data->buffer;
            data->buf_end = data->buffer + len;
        }
    }
    return *data->buf_ptr++;
}

static int worker_get_line(httpServerCallbackData_t *data, char *line, int line_size)
{
    int ch;
    char *q;

    q = line;
    for(;;) {
        ch = worker_getc(data);
        if (ch < 0)
            return ch;
        if (ch == '\n') {
            /* process line */
            if (q > line && q[-1] == '\r')
                q--;
            *q = '\0';
            return 0;
        } else {
            if ((q - line) < line_size - 1)
                *q++ = ch;
        }
    }
}

static int worker_process_line(httpServerCallbackData_t *data, char *line, int line_number)
{
    char *tag, *p;

    /* end of header */
    if (line[0] == '\0')
        return 0;

    p = line;
    if (line_number == 0)
    {
        int version_found = 0;
        int valid_request = 0;

        while (isspace(*p))
            p++;

        if(strncasecmp(p, "get ", 4) == 0)
        {
            valid_request = 1;
            data->data.httpData.method = httpMethod_GET;
            p += 3;
        }
        else if(strncasecmp(p, "head ", 5) == 0)
        {
            valid_request = 1;
            data->data.httpData.method = httpMethod_HEAD;
            p += 4;
        }

        if(valid_request)
        {
            int index;

            while(isspace(*p))
                p++;

            for(index = 0; index < (sizeof(data->data.requestedResource) - 1) && (!isspace(*p)) && *p; index++, p++)
                data->data.requestedResource[index] = *p;
            data->data.requestedResource[index] = 0;
        }

        do {
            while(isspace(*p))
                p++;

            if(*p == 0)
                break;

            if((strncasecmp(p, "http/1.", 7) == 0) && ((*(p + 7) == '1') || (*(p + 7) == '0')))
            {
                data->data.httpData.keepalive = (*(p + 7) == '1') ? 1 : 0;
                data->data.httpData.http_version = *(p + 7) - '0';
                version_found = 1;
            }
            else
            {
                while(!isspace(*p) && (*p))
                    p++;
            }
        }while(!version_found);

        if(!version_found)
        {
            // It's invalid request
            return -1;
        }
    }
    else
    {
        while (*p != '\0' && *p != ':')
            p++;
        if (*p != ':')
            return 1;

        *p = '\0';
        tag = line;
        p++;
        while (isspace(*p))
            p++;

        if(strcasecmp(tag, "connection") == 0)
        {
            data->data.httpData.keepalive = (strcasecmp(p, "keep-alive") == 0) ? 1 : 0;
        }
        else if(data->data.count_pairs < MAX_KV_PAIRS)
        {
            strncpy(data->data.pairs[data->data.count_pairs].key, tag, KEY_LINE_SIZE - 1);
            strncpy(data->data.pairs[data->data.count_pairs].val, p, VALUE_LINE_SIZE - 1);
            data->data.count_pairs++;
        }
        else
        {
            logout("%s %d: Failed to big header %d >= %d for %s : %s\n", __FUNCTION__, __LINE__, data->data.count_pairs, MAX_KV_PAIRS, tag, p);
        }
    }
    return 1;
}

int get_date_time_from_stamp(time_t timestamp, char *buffer, unsigned int size)
{
    struct tm mytime;
    const char *days[] = { "Sun", "Mon",  "Tue",  "Wed",  "Thu",  "Fri",  "Sat" };
    const char *months[] = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

    gmtime_r(&timestamp, &mytime);

    if((mytime.tm_wday < 0) || (mytime.tm_wday > 6))
        mytime.tm_wday = 0;
    if((mytime.tm_mon < 0) || (mytime.tm_mon > 11))
        mytime.tm_mon = 0;

    return snprintf(buffer, size, "%s, %02d %s %d %02d:%02d:%02d GMT", days[mytime.tm_wday], mytime.tm_mday, months[mytime.tm_mon], mytime.tm_year + 1900, mytime.tm_hour, mytime.tm_min, mytime.tm_sec);
}

int get_date_line(char *buffer, uint32_t size)
{
    struct timeval now;

    gettimeofday(&now, 0);

    return get_date_time_from_stamp(now.tv_sec, buffer, size);
}

int putResponseToBuffer(char *outbuffer, int outsize, int http_version, int keepalive, int code, const char *cdesc)
{
    int result = -EINVAL;
    int size = 0;
    char body_value[sizeof(responce_body) + 256];
    char curtime[32];
    int value;

    if(get_date_line(curtime, sizeof(curtime)) >= 0)
    {
        if(code >= 400)
            size = snprintf(body_value, sizeof(body_value), responce_body, code, cdesc, code, cdesc);
        if(size >= 0)
        {
            result = snprintf((char*)outbuffer, outsize, response_header, http_version, code, cdesc, size, keepalive ? "Keep-Alive" : "Close", curtime, HTTP_SERVER_DESCRIPTION);
            if(result > 0)
            {
                if(code == 503)
                {
                    value = snprintf((char*)outbuffer + result, outsize - result, "Retry-After: 120\r\n"); // retry after 120 seconds
                    if(value > 0)
                        result += value;
                }

                value = snprintf((char*)outbuffer + result, outsize - result, "\r\n");
                if(value > 0)
                    result += value;

                if(size)
                {
                    strncpy((char*)&outbuffer[result], body_value, outsize - result);
                    result += size;
                }
            }
        }
    }

    return result;
}

static void send_short_response(httpServerCallbackData_t *data, int code, const char *cdesc)
{
    int result = -EINVAL;
    int size;

    if(data)
    {
        size = putResponseToBuffer((char*)data->buffer, sizeof(data->buffer), data->data.httpData.http_version, (code < 400) ? data->data.httpData.keepalive : 0, code, cdesc);
        if(size > 0)
        {
            result = send(data->socket, data->buffer, size, MSG_NOSIGNAL);
            if(result != size)
                logout("%s %d: Failed send data %d != %d: %s\n", __FUNCTION__, __LINE__, result, size, strerror(errno));
        }
        else
        {
            logout("%s %d: Failed prepare message\n", __FUNCTION__, __LINE__);
        }
    }
}

static void setSocketOptions(httpServerCallbackData_t *data)
{
    int one;

    one = 1;
    if(setsockopt(data->socket, SOL_SOCKET, SO_KEEPALIVE, &one, sizeof(one)) != 0)
        logout("%s %d: Failed set socket keepalive\n", __FUNCTION__, __LINE__);

    one = 3; // the number of unacknowledged probes to send before considering the connection dead and notifying the application layer
    if(setsockopt(data->socket, SOL_TCP, TCP_KEEPCNT, &one, sizeof(one)) != 0)
        logout("%s %d: Failed set socket keepalive\n", __FUNCTION__, __LINE__);

    one = 10; // the interval between the last data packet sent (simple ACKs are not considered data) and the first keepalive probe; after the connection is marked to need keepalive, this counter is not used any further
    if(setsockopt(data->socket, SOL_TCP, TCP_KEEPIDLE, &one, sizeof(one)) != 0)
        logout("%s %d: Failed set socket keepalive\n", __FUNCTION__, __LINE__);

    one = 10; // the interval between subsequential keepalive probes, regardless of what the connection has exchanged in the meantime
    if(setsockopt(data->socket, SOL_TCP, TCP_KEEPINTVL, &one, sizeof(one)) != 0)
        logout("%s %d: Failed set socket keepalive\n", __FUNCTION__, __LINE__);

    if(data->server && data->server->timeout)
    {
        struct timeval timeout = { data->server->timeout, 0 };

        if(setsockopt(data->socket, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout,sizeof(timeout)) < 0)
            logout("%s %d: Setsockopt failed\n", __FUNCTION__, __LINE__);

        if (setsockopt(data->socket, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout,sizeof(timeout)) < 0)
            logout("%s %d: Setsockopt failed\n", __FUNCTION__, __LINE__);
    }
}

static void clientFunction(threadPoolFunctionData_t *ctx)
{
    httpServerCallbackData_t *data;
    socklen_t namelen;
    int line_number;
    char line[1024];
    int complete;
    int result;

    if(ctx && ctx->ctx)
    {
        data = (httpServerCallbackData_t*)ctx->ctx;
        if(data->magic == HTTP_USER_MAGIC_VALUE)
        {
            if(data->server && !data->data.secondstart)
                setSocketOptions(data);

            do {
                data->data.count_pairs = 0;
                line_number = 0;
                complete = 0;

                if(data->data.secondstart)
                {
                    result = send(data->socket, data->data.buffer, data->data.buffersize, MSG_NOSIGNAL);
                    if(result == data->data.buffersize)
                    {
                        result = 0;
                    }
                    else
                    {
                        logout("%s %d: Failed %d send %d bytes: %s\n", __FUNCTION__, __LINE__, result, data->data.buffersize, strerror(errno));
                        result = -1;
                    }
                    data->data.secondstart = 0;
                    data->data.buffersize = 0;
                }
                else
                {
                    while(1)
                    {
                        if(worker_get_line(data, line, sizeof(line)) < 0)
                            break;
                        if((result = worker_process_line(data, line, line_number)) < 0)
                            break;
                        if(result == 0)
                        {
                            complete = 1;
                            break;
                        }
                        line_number++;
                    }

                    result = 1;
                    if(complete)
                    {
                        if((data->data.httpData.method == httpMethod_GET) || (data->data.httpData.method == httpMethod_HEAD))
                        {
                            result = 1;
                            if(data->server && data->server->callback)
                            {
                                data->data.httpData.socket = data->socket; // set socket
                                namelen = sizeof(data->data.interfaceaddr);
                                result = getsockname(data->socket, (struct sockaddr*)&data->data.interfaceaddr, &namelen);
                                if(result)
                                    logout("%s %d: Failed get socket address\n", __FUNCTION__, __LINE__);
                                result = data->server->callback(data->server->callback_ctx, &data->data);
                            }

                            if(result)
                            {
                                if(result == HTTP_SAVE_DESCRIPTOR)
                                {
                                    data->socket = -1;
                                    break;
                                }
                                else if(result != 1)
                                {
                                    send_short_response(data, 503, "Service Unavailable");
                                }
                                else
                                {
                                    send_short_response(data, 404, "Not Found");
                                }
                            }
                        }
                        else
                        {
                            send_short_response(data, 400, "Bad Request");
                        }
                    }
                }
            }while((result == 0) && data->data.httpData.keepalive);

            if(data->socket != -1)
            {
#if defined(HTTP_CLOSE_TIMEOUT) && (HTTP_CLOSE_TIMEOUT > 0)
                if(result == 0)
                {
                    struct pollfd mfd = { data->socket, POLLIN | POLLPRI | POLLERR | POLLHUP, 0 };
                    poll(&mfd, 1, HTTP_CLOSE_TIMEOUT);
                }
#endif
                shutdown(data->socket, SHUT_RDWR);
                close(data->socket);
            }
        }
        else
        {
            logout("%s %d: Invalid magic 0x%X != 0x%X\n", __FUNCTION__, __LINE__, data->magic, HTTP_USER_MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid context\n", __FUNCTION__, __LINE__);
    }
}

static void httpThreadFunction(threadFunctionData_t *ctx)
{
    httpServerCallbackData_t *userCallback;
    httpServerMainThread_t *data;
    struct sockaddr_in addr;
    struct pollfd ufds;
    socklen_t addrlen;
    cpu_set_t cpuset;
    int result;

    if(ctx)
    {
        data = (httpServerMainThread_t *)ctx->ctx;
        if(data && data->serverData)
        {
            if((data->magic == HTTP_THREAD_MAGIC_VALUE) && (data->serverData->magic == HTTP_MAGIC_VALUE))
            {
                CPU_ZERO(&cpuset);
                CPU_SET(data->procnum, &cpuset);
                result = pthread_setaffinity_np(pthread_self(), sizeof(cpu_set_t), &cpuset);
                if(result != 0)
                    logout("%s %d: Failed set affinity\n", __FUNCTION__, __LINE__);

                result = fcntl(data->socket, F_GETFL, 0);
                if(result != -1)
                {
                    result = fcntl(data->socket, F_SETFL, result| O_NONBLOCK);
                    if(result != -1)
                    {
                        result = threadPool_create(&data->threadPool, "threads");
                        if(result == 0)
                        {
                            userCallback = 0;

                            while(ctx->needExecute)
                            {
                                if(userCallback == 0)
                                {
                                    userCallback = threadPool_getContext(data->threadPool, sizeof(httpServerCallbackData_t));
                                    if(userCallback == 0)
                                    {
                                        logout("%s %d: Failed get %d bytes of memory\n", __FUNCTION__, __LINE__, (int)sizeof(httpServerCallbackData_t));
                                    }
                                }

                                ufds.fd = data->socket;
                                ufds.events = POLLIN;
                                ufds.revents = 0;

                                result = poll(&ufds, 1, -1); // infinite timeout
                                if(result > 0) // have incoming connections on a socket
                                {
                                    addrlen = sizeof(addr);
                                    result = accept(data->socket, (struct sockaddr*)&addr, &addrlen);
                                    if(result != -1)
                                    {
                                        if(userCallback)
                                        {
                                            memset(userCallback, 0, sizeof(*userCallback));
                                            userCallback->magic = HTTP_USER_MAGIC_VALUE;
                                            userCallback->socket = result;
                                            userCallback->server = data->serverData;
                                            userCallback->data.httpData.clientaddr = addr;
                                            userCallback->data.httpData.instance = data;

                                            if(threadPool_startInContext(data->threadPool, clientFunction, userCallback, "HttpClientFunc", threadPoolPriority_Normal, false) == 0)
                                            {
                                                // ok! userData already fried by clientFunction
                                                userCallback = 0;
                                            }
                                            else
                                            {
                                                logout("%s %d: Failed start client thread\n", __FUNCTION__, __LINE__);
                                                shutdown(result, SHUT_RDWR);
                                                close(result);
                                            }
                                        }
                                        else
                                        {
                                            logout("%s %d: Failed alloc %d bytes of memory\n", __FUNCTION__, __LINE__, (int)sizeof(httpServerCallbackData_t));
                                            shutdown(result, SHUT_RDWR);
                                            close(result);
                                        }
                                    }
                                }
                            }

                            if(userCallback)
                            {
                                result = threadPool_putContext(data->threadPool, userCallback);
                                if(result)
                                    logout("%s %d: Failed free context: %d\n", __FUNCTION__, __LINE__, result);
                            }

                            result = threadPool_destroy(data->threadPool);
                            if(result)
                                logout("%s %d: Failed destroy allocator: %d\n", __FUNCTION__, __LINE__, result);
                        }
                        else
                        {
                            logout("%s %d: Failed create thread pool: %d\n", __FUNCTION__, __LINE__, result);
                        }
                    }
                    else
                    {
                        logout("%s %d: Failed set flags\n", __FUNCTION__, __LINE__);
                    }
                }
                else
                {
                    logout("%s %d: Failed get flags\n", __FUNCTION__, __LINE__);
                }
            }
            else
            {
                logout("%s %d: Invalid data\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s %d: Invalid data\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: Invalid context\n", __FUNCTION__, __LINE__);
    }
}

static int createMainThread(httpServerMainThread_t *context)
{
    int result = EINVAL;

    result = thread_start(&context->thread, httpThreadFunction, context, "HttpServerFunc", threadPriority_Highest, 0, 0);
    if(result)
    {
        logout("%s %d: Failed start listen thread\n", __FUNCTION__, __LINE__);
    }

    return result;
}

static int createListenSocket(httpServerMainThread_t *context)
{
    int result = EINVAL;
    int yes = 1;
    int timeout;
    int sock;

    if(context && context->serverData)
    {
        sock = socket(PF_INET, SOCK_STREAM, IPPROTO_TCP);
        if(sock != -1)
        {
            if(setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes)) == -1)
            {
                logout("%s %d: Failed(%s) setsockopt\n", __FUNCTION__, __LINE__, strerror(errno));
            }
            if(setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &yes, sizeof(yes)) == -1)
            {
                logout("%s %d: Failed(%s) setsockopt\n", __FUNCTION__, __LINE__, strerror(errno));
            }

            if(context->serverData->timeout >> 1)
            {
                timeout = (context->serverData->timeout >> 1);
                if(setsockopt(sock, SOL_TCP, TCP_DEFER_ACCEPT, &timeout, sizeof(timeout)) == -1)
                {
                    logout("%s %d: Failed(%s) setsockopt\n", __FUNCTION__, __LINE__, strerror(errno));
                }
            }

            result = bind(sock, (struct sockaddr *)&context->serverData->interface, sizeof(struct sockaddr_in));
            if(result == 0)
            {
                result = listen(sock, HTTP_LISTEN_BACKLOG);
                if(result == 0)
                {
                    context->socket = sock;
                    result = 0;
                }
                else
                {
                    logout("%s %d: Failed(%s) listen\n", __FUNCTION__, __LINE__, strerror(errno));
                }
            }
            else
            {
                logout("%s %d: Can't bind port(%d). Please see in /proc/sys/net/ipv4/ip_local_port_range\n", __FUNCTION__, __LINE__, errno);
            }

            if(result)
            {
                shutdown(sock, SHUT_RDWR);
                close(sock);
            }
        }
        else
        {
            logout("%s %d: Failed(%s) create socket\n", __FUNCTION__, __LINE__, strerror(errno));
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

int start_http_server(httpServer_t *server, struct sockaddr_in *interface, unsigned int timeout, httpServerCallBack_t callback, void *ctx)
{
    int result = EINVAL;
    httpServerPrivate_t *newServer;
    httpServerMainThread_t *thread;
    struct list_head *iterator;
    int processes;
    uid_t origuid;
    gid_t origgid;
    int index;

    if(server && interface && callback)
    {
        processes = get_nprocs();
        if(processes > 0)
        {
            logout("%s %d: Have %d processes\n", __FUNCTION__, __LINE__, processes);

            newServer = malloc(sizeof(httpServerPrivate_t) + processes * sizeof(httpServerMainThread_t));
            if(newServer)
            {
                memset(newServer, 0, sizeof(httpServerPrivate_t) + processes * sizeof(httpServerMainThread_t));

                thread = (httpServerMainThread_t*)((uint8_t*)newServer + sizeof(httpServerPrivate_t));

                newServer->magic = HTTP_MAGIC_VALUE;
                newServer->callback = callback;
                newServer->callback_ctx = ctx;
                newServer->interface = *interface;
                newServer->timeout = timeout;
                INIT_LIST_HEAD(&newServer->threads);
                for(index = 0; index < processes; index++, thread++)
                {
                    thread->serverData = newServer;
                    thread->procnum = index;
                    thread->socket = -1;
                    thread->magic = HTTP_THREAD_MAGIC_VALUE;
                    list_add_tail(&thread->list, &newServer->threads);
                }
                origuid = getuid();
                origgid = getgid();
                setreuid(0, 0);
                setregid(0, 0);
                list_for_each(iterator, &newServer->threads)
                {
                    thread = list_entry(iterator, httpServerMainThread_t, list);
                    result = createListenSocket(thread);
                    if(result)
                        break;
                }
                setregid(origgid, origgid);
                setreuid(origuid, origuid);
                if(!result)
                {
                    list_for_each(iterator, &newServer->threads)
                    {
                        thread = list_entry(iterator, httpServerMainThread_t, list);
                        result = createMainThread(thread);
                        if(result)
                            break;
                    }

                    if(!result)
                    {
                        *server = (httpServer_t)newServer;
                    }
                }

                if(result)
                {
                    list_for_each(iterator, &newServer->threads)
                    {
                        thread = list_entry(iterator, httpServerMainThread_t, list);
                        if(thread->thread)
                        {
                            int status = thread_stop(thread->thread);
                            if(status)
                                logout("%s %d: Failed stop listen thread\n", __FUNCTION__, __LINE__);
                            thread->thread = 0;
                        }

                        if(thread->socket != -1)
                        {
                            shutdown(thread->socket, SHUT_RDWR);
                            close(thread->socket);
                            thread->socket = -1;
                        }
                    }
                    newServer->magic = 0;
                    free(newServer);
                }
            }
            else
            {
                logout("%s %d: Failed alloc memory %d bytes\n", __FUNCTION__, __LINE__, (int)sizeof(httpServerPrivate_t));
                result = ENOMEM;
            }
        }
        else
        {
            logout("%s %d: Failed get count cpu in system\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: Invalid arguments\n", __FUNCTION__, __LINE__);
    }

    return result;
}

int stop_http_server(httpServer_t server)
{
    int result = EINVAL;
    httpServerPrivate_t *newServer = (httpServerPrivate_t *)server;
    struct list_head *iterator;

    if(newServer)
    {
        if(newServer->magic == HTTP_MAGIC_VALUE)
        {
            list_for_each(iterator, &newServer->threads)
            {
                httpServerMainThread_t *thread = list_entry(iterator, httpServerMainThread_t, list);
                if(thread->thread)
                {
                    int status;

                    thread->magic = 0;
                    status = thread_stop(thread->thread);
                    if(status)
                        logout("%s %d: Failed stop listen thread\n", __FUNCTION__, __LINE__);
                    thread->thread = 0;
                }

                if(thread->socket != -1)
                {
                    shutdown(thread->socket, SHUT_RDWR);
                    close(thread->socket);
                    thread->socket = -1;
                }
            }
            newServer->magic = 0;
            free(newServer);
            result = 0;
        }
        else
        {
            logout("%s %d: Invalid magic 0x%X\n", __FUNCTION__, __LINE__, newServer->magic);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

int process_http_connection(httpClientCtx_t *httpData, struct iovec *data, unsigned int datacount)
{
    int result = EINVAL;
    unsigned int size = 0;
    httpServerCallbackData_t *userCallback;
    int index;

    if(httpData && data && datacount)
    {
        for(index = 0; index < datacount; index++)
            size += data[index].iov_len;

        if(size <= USER_BUFFER_SIZE)
        {
            if((httpData->socket != -1) && httpData->instance && (httpData->instance->magic == HTTP_THREAD_MAGIC_VALUE))
            {
                if(httpData->instance->serverData && httpData->instance->serverData->magic == HTTP_MAGIC_VALUE)
                {
                    userCallback = threadPool_getContext(httpData->instance->threadPool, sizeof(httpServerCallbackData_t));
                    if(userCallback == 0)
                    {
                        logout("%s %d: Failed get %d bytes of memory\n", __FUNCTION__, __LINE__, (int)sizeof(httpServerCallbackData_t));
                    }
                    else
                    {
                        memset(userCallback, 0, sizeof(*userCallback));
                        userCallback->magic = HTTP_USER_MAGIC_VALUE;
                        userCallback->socket = httpData->socket;
                        userCallback->server = httpData->instance->serverData;
                        userCallback->data.httpData = *httpData;

                        size = 0;
                        for(index = 0; index < datacount; index++)
                        {
                            memcpy(&userCallback->data.buffer[size], data[index].iov_base, data[index].iov_len);
                            size += data[index].iov_len;
                        }
                        userCallback->data.buffersize = size;
                        userCallback->data.secondstart = 1;
                        if(threadPool_startInContext(httpData->instance->threadPool, clientFunction, userCallback, "HttpClientFunc", threadPoolPriority_Normal, false) == 0)
                        {
                            result = 0;
                        }
                        else
                        {
                            logout("%s %d: Failed start client thread\n", __FUNCTION__, __LINE__);
                            result = threadPool_putContext(httpData->instance->threadPool, userCallback);
                            if(result)
                                logout("%s %d: Failed free context: %d\n", __FUNCTION__, __LINE__, result);
                        }
                    }
                }
                else
                {
                    logout("%s %d: Invalid magic\n", __FUNCTION__, __LINE__);
                }
            }
            else
            {
                logout("%s %d: Invalid data\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s %d: Size is too big: %d bytes\n", __FUNCTION__, __LINE__, size);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

