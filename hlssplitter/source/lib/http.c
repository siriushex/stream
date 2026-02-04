#include "http.h"
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdarg.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <errno.h>

#include <arpa/inet.h>
#include <netdb.h>

#include <arpa/nameser.h>
#include <resolv.h>
#include <poll.h>
#include <sys/time.h>
#include "log.h"

#define CLIENT_INDENTIFICATION "stb100client"
#define HTTP_URL_SIZE       2048
#define HTTP_PATH_SIZE      1024
#define HTTP_UAGENT_SIZE    256
#define MAX_REDIRECTS       8
#define READ_BUFFER_SIZE    7168

#define SPACE_CHARS " \t\r\n"
#define MINIMUM(a,b) (((a) < (b)) ? (a) : (b))
#define TRACE(x, ...) logout("%s %d: " x, __FUNCTION__, __LINE__, ##__VA_ARGS__)

typedef enum
{
    http_open_stage_init,
    http_open_stage_connect,
    http_open_stage_sendhttp,
    http_open_stage_readhttp,
    http_open_stage_connected
}http_open_stages_t;

typedef struct
{
    char location[HTTP_URL_SIZE];
    char user_agent[HTTP_UAGENT_SIZE];
    char path1[HTTP_PATH_SIZE];
    char hoststr[HTTP_PATH_SIZE];
    int64_t filesize;
    int64_t off;
    char buffer[READ_BUFFER_SIZE], *buf_ptr, *buf_end;
    int http_code;
    int line_count;
    int64_t chunksize;      /**< Used if "Transfer-Encoding: chunked" otherwise -1. */
    int willclose;          /**< Set if the server correctly handles Connection: close and will close the connection after feeding us the content. */
    int http_socket;
    int https_proto;
    char saved_hoststr[HTTP_PATH_SIZE];
    struct sockaddr_in servaddr;
    http_open_stages_t stage;
    bool need_keepalive;
}http_context_t;

static int http_strncpy(char *dest, const char *src, size_t n)
{
    if(dest)
    {
        strncpy(dest, src, n - 1);
        dest[n- 1] = 0;
    }
    return MINIMUM(strlen(src), n);
}

/*-----------------------------------------------------------------------------------------------------------------*/
static size_t strlcatf(char *dst, size_t size, const char *fmt, ...)
{
    int len = strlen(dst);
    va_list vl;

    va_start(vl, fmt);
    len += vsnprintf(dst + len, (int)size > len ? size - len : 0, fmt, vl);
    va_end(vl);

    return len;
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int http_socket_read(http_context_t *ctx, char *ptr, int size)
{
    int result = -EIO;
    if(!ptr)
        return -EINVAL;
    if(ctx && (ctx->http_socket != -1))
    {
        result = recv(ctx->http_socket, ptr, size, MSG_NOSIGNAL);
    }
    return result;
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int lib_http_socket_write(http_context_t *ctx, char *ptr, int size)
{
    int result = -EIO;
    if(!ptr)
        return -EINVAL;
    if(ctx && (ctx->http_socket!= -1))
    {
        result = send(ctx->http_socket, ptr, size, MSG_NOSIGNAL);
    }
    return result;
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int http_getc(http_context_t *ctx)
{
    int len;

    if (ctx->buf_ptr >= ctx->buf_end)
    {
        len = http_socket_read(ctx, ctx->buffer, READ_BUFFER_SIZE);
        if (len < 0)
        {
            char buffer[128] = { 0, };
            strerror_r(errno, buffer, sizeof(buffer) - 1);
            TRACE("Read error %d [%d] - [%s]\n", len, errno, buffer);
            return len;
        }
        else if (len == 0)
        {
            TRACE("End of file\n");
            return -1;
        }
        else
        {
            ctx->buf_ptr = ctx->buffer;
            ctx->buf_end = ctx->buffer + len;
        }
    }
    return *ctx->buf_ptr++;
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int http_get_line(http_context_t *ctx, char *line, int line_size)
{
    int ch;
    char *q;
    int tolowcase = 1;

    q = line;
    for(;;) {
        ch = http_getc(ctx);
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
            {
                if((q - line) == 8)
                {
                    if(!strncmp(line, "location", 8))
                        tolowcase = 0;
                }

                if(tolowcase)
                    *q++ = tolower(ch);
                else
                    *q++ = ch;
            }
        }
    }
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int process_line(http_context_t *ctx, char *line, int line_count, int *new_location)
{
    char *tag, *p, *end;

    /* end of header */
    if (line[0] == '\0')
        return 0;

    p = line;
    if (line_count == 0) {
        while (!isspace(*p) && *p != '\0')
            p++;
        while (isspace(*p))
            p++;
        ctx->http_code = strtol(p, &end, 10);

        //TRACE("http_code=%d\n", ctx->http_code);
        if (ctx->http_code >= 400 && ctx->http_code < 600)
            return -lib_http_error_fail_http_error;
    } else {
        while (*p != '\0' && *p != ':')
            p++;
        if (*p != ':')
            return 1;

        *p = '\0';
        tag = line;
        p++;
        while (isspace(*p))
            p++;
        if (!strcmp(tag, "location")) {
            strcpy(ctx->location, p);
            *new_location = 1;
        } else if (!strcmp (tag, "content-length") && ctx->filesize == -1) {
            ctx->filesize = strtoull(p, NULL, 10);
        } else if (!strcmp (tag, "content-range")) {
            const char *slash;
            if (!strncmp (p, "bytes ", 6)) {
                p += 6;
                ctx->off = strtoull(p, NULL, 10);
                if ((slash = strchr(p, '/')) && (slash[0] != '\0'))
                    ctx->filesize = strtoull(slash + 1, NULL, 10);
            }
        } else if (!strcmp (tag, "transfer-encoding") && !strncasecmp(p, "chunked", 7)) {
            ctx->filesize = -1;
            ctx->chunksize = 0;
        }
        else if (!strcmp (tag, "www-authenticate"))
        {
            //ff_http_auth_handle_header(&ctx->auth_state, tag, p);
        }
        else if (!strcmp (tag, "authentication-info"))
        {
            //ff_http_auth_handle_header(&ctx->auth_state, tag, p);
        }
        else if (!strcmp (tag, "connection"))
        {
            if (!strcmp(p, "close"))
                ctx->willclose = 1;
        }
    }
    return 1;
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int http_connect_first(http_context_t *ctx, const char *path)
{
    int err = -lib_http_error_fail_http_connect;
    char headers[HTTP_PATH_SIZE] = "";
    int len = 0;

    /* set default headers if needed */
    if(ctx->user_agent[0] != 0)
        len += strlcatf(headers + len, sizeof(headers) - len, "User-Agent: %s\r\n", ctx->user_agent);
    else
        len += strlcatf(headers + len, sizeof(headers) - len, "User-Agent: %s\r\n", CLIENT_INDENTIFICATION);
    len += http_strncpy(headers + len, "Accept: */*\r\n", sizeof(headers) - len);
    if(ctx->off)
        len += strlcatf(headers + len, sizeof(headers) - len, "Range: bytes=%lld-\r\n", ctx->off);
    if(ctx->need_keepalive)
        len += http_strncpy(headers + len, "Connection: Keep-Alive\r\n", sizeof(headers)-len);
    else
        len += http_strncpy(headers + len, "Connection: Close\r\n", sizeof(headers)-len);
    len += strlcatf(headers + len, sizeof(headers) - len, "Host: %s\r\n", ctx->hoststr);
    snprintf(ctx->buffer, sizeof(ctx->buffer), "GET %s HTTP/1.1\r\n" "%s\r\n", path, headers);
    err = lib_http_socket_write(ctx, ctx->buffer, strlen(ctx->buffer));
    if(err < 0)
    {
        TRACE("Failed %d write data in socket\n", err);
        return -lib_http_error_fail_http_connect;
    }

    /* init input buffer */
    ctx->buf_ptr = ctx->buffer;
    ctx->buf_end = ctx->buffer;
    ctx->line_count = 0;
    ctx->off = 0;
    ctx->filesize = -1;
    ctx->willclose = 0;
    ctx->chunksize = -1;

    return 0;
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int http_connect_second(http_context_t *ctx, int *new_location)
{
    int err = -lib_http_error_fail_http_connect;
    char line[HTTP_PATH_SIZE];
    int64_t off = 0;

    /* wait for header */
    for(;;)
    {
        if (http_get_line(ctx, line, sizeof(line)) < 0)
        {
            TRACE("Error get line\n");
            return -lib_http_error_fail_http_connect;
        }
        err = process_line(ctx, line, ctx->line_count, new_location);
        if (err < 0)
        {
            TRACE("Error process line %s\n", line);
            return err;
        }
        if (err == 0)
            break;
        ctx->line_count++;
    }

    if(off == ctx->off)
        strncpy(ctx->saved_hoststr, ctx->hoststr, sizeof(ctx->saved_hoststr));

    return (off == ctx->off) ? 0 : -lib_http_error_fail_http_connect;
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int http_connect(http_context_t *ctx, const char *path, int *new_location)
{
    int err = -lib_http_error_fail_http_connect;
    char line[HTTP_PATH_SIZE];
    char headers[HTTP_PATH_SIZE] = "";
    int64_t off = ctx->off;
    int len = 0;

    /* set default headers if needed */
    if(ctx->user_agent[0] != 0)
        len += strlcatf(headers + len, sizeof(headers) - len, "User-Agent: %s\r\n", ctx->user_agent);
    else
        len += strlcatf(headers + len, sizeof(headers) - len, "User-Agent: %s\r\n", CLIENT_INDENTIFICATION);
    len += http_strncpy(headers + len, "Accept: */*\r\n", sizeof(headers) - len);
    if(ctx->off)
        len += strlcatf(headers + len, sizeof(headers) - len, "Range: bytes=%lld-\r\n", ctx->off);
    if(ctx->need_keepalive)
        len += http_strncpy(headers + len, "Connection: Keep-Alive\r\n", sizeof(headers)-len);
    else
        len += http_strncpy(headers + len, "Connection: Close\r\n", sizeof(headers)-len);
    len += strlcatf(headers + len, sizeof(headers) - len, "Host: %s\r\n", ctx->hoststr);
    snprintf(ctx->buffer, sizeof(ctx->buffer), "GET %s HTTP/1.1\r\n" "%s\r\n", path, headers);
    err = lib_http_socket_write(ctx, ctx->buffer, strlen(ctx->buffer));
    if(err < 0)
    {
        TRACE("Failed %d write data in socket\n", err);
        return -lib_http_error_fail_http_connect;
    }

    /* init input buffer */
    ctx->buf_ptr = ctx->buffer;
    ctx->buf_end = ctx->buffer;
    ctx->line_count = 0;
    ctx->off = 0;
    ctx->filesize = -1;
    ctx->willclose = 0;
    ctx->chunksize = -1;

    /* wait for header */
    for(;;)
    {
        if (http_get_line(ctx, line, sizeof(line)) < 0)
        {
            TRACE("Error get line\n");
            return -lib_http_error_fail_http_connect;
        }
        err = process_line(ctx, line, ctx->line_count, new_location);
        if (err < 0)
        {
            TRACE("Error process line %s\n", line);
            return err;
        }
        if (err == 0)
            break;
        ctx->line_count++;
    }
    if(off == ctx->off)
        strncpy(ctx->saved_hoststr, ctx->hoststr, sizeof(ctx->saved_hoststr));
    return (off == ctx->off) ? 0 : -lib_http_error_fail_http_connect;
}

/*-----------------------------------------------------------------------------------------------------------------*/
void lib_http_url_split(char *proto, int proto_size, char *authorization, int authorization_size,
                            char *hostname, int hostname_size, int *port_ptr, char *path, int path_size,
                            const char *url, int *https_proto)
{
    const char *p, *ls, *at, *col, *brk1;

    if(port_ptr)
        *port_ptr = -1;
    if(proto_size > 0)
        proto[0] = 0;
    if(authorization_size > 0)
        authorization[0] = 0;
    if(hostname_size > 0)
        hostname[0] = 0;
    if((path_size > 0) && path)
        path[0] = 0;

    if(https_proto)
    {
        if(!strncmp(url,"https:",6))
            *https_proto = 1;
        else
            *https_proto = 0;
    }

    /* parse protocol */
    if ((p = strchr(url, ':')))
    {
        http_strncpy(proto, url, MINIMUM(proto_size, p + 1 - url));
        p++; /* skip ':' */
        if (*p == '/') p++;
        if (*p == '/') p++;
    }
    else
    {
        /* no protocol means plain filename */
        if(path)
            http_strncpy(path, url, path_size);
        return;
    }
    /* separate path from hostname */
    ls = strchr(p, '/');
    if(!ls)
        ls = strchr(p, '?');
    if(ls)
    {
        if(path)
            http_strncpy(path, ls, path_size);
    }
    else
        ls = &p[strlen(p)]; // XXX
    /* the rest is hostname, use that to parse auth/port */
    if (ls != p)
    {
        /* authorization (user[:pass]@hostname) */
        if ((at = strchr(p, '@')) && at < ls)
        {
            if(authorization)
                http_strncpy(authorization, p, MINIMUM(authorization_size, at + 1 - p));
            p = at + 1; /* skip '@' */
        }

        if (*p == '[' && (brk1 = strchr(p, ']')) && brk1 < ls)
        {
            /* [host]:port */
            if(hostname)
                http_strncpy(hostname, p + 1, MINIMUM(hostname_size, brk1 - p));
            if (brk1[1] == ':' && port_ptr)
                *port_ptr = strtol(brk1 + 2, NULL, 10);
        }
        else if ((col = strchr(p, ':')) && col < ls)
        {
            if(hostname)
                http_strncpy (hostname, p, MINIMUM(col + 1 - p, hostname_size));
            if (port_ptr) *port_ptr = strtol(col + 1, NULL, 10);
        }
        else
        {
            if(hostname)
                http_strncpy(hostname, p, MINIMUM(ls + 1 - p, hostname_size));
        }
    }
}

/*-----------------------------------------------------------------------------------------------------------------*/
int url_join(char *str, int size, const char *proto, const char *authorization, const char *hostname,
                int port, const char *fmt, ...)
{
    str[0] = '\0';
    if (proto)
        strlcatf(str, size, "%s://", proto);
    if (authorization && authorization[0])
        strlcatf(str, size, "%s@", authorization);
    strncat(str, hostname, size);

    if (port >= 0)
        strlcatf(str, size, ":%d", port);
    if (fmt) {
        va_list vl;
        int len = strlen(str);

        va_start(vl, fmt);
        vsnprintf(str + len, size > len ? size - len : 0, fmt, vl);
        va_end(vl);
    }
    return strlen(str);
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int lib_http_create_socket(http_context_t *ctx, const char *host, int port, int blocking, struct sockaddr_in *interface)
{
    int result = -lib_http_error_contex;
    struct hostent *hostEnt=0, hostBuf;
    int tmpLen = 2048,herr;
    char tmp[tmpLen];
    in_addr_t ipaddr;
    int haveaddr;
    int one;

    if(host && ctx)
    {
        haveaddr = 0;
        ipaddr = inet_addr(host);
        if(ipaddr != -1)
            haveaddr = 1;

        if(haveaddr == 0)
        {
            gethostbyname_r(host, &hostBuf, tmp, tmpLen, &hostEnt, &herr);
            if(hostEnt)
            {
                if(hostEnt->h_length == sizeof(ipaddr))
                {
                    memcpy(&ipaddr, hostEnt->h_addr, hostEnt->h_length);
                    if(ipaddr != -1)
                        haveaddr = 1;
                }
            }
        }

        if(haveaddr)
        {
            ctx->http_socket = socket(PF_INET, blocking ? SOCK_STREAM : SOCK_STREAM | SOCK_NONBLOCK, IPPROTO_TCP);
            if(ctx->http_socket != -1)
            {
                struct timeval timeout = { 30, 0};

                if(setsockopt(ctx->http_socket, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout,sizeof(timeout)) < 0)
                    TRACE("setsockopt failed\n");

                if (setsockopt(ctx->http_socket, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout,sizeof(timeout)) < 0)
                    TRACE("setsockopt failed\n");

                result = 0;
                if(interface)
                {
                    result = bind(ctx->http_socket, (struct sockaddr *)interface, sizeof(*interface));
                    if(result)
                    {
                        TRACE("bind failed to address %s : %s\n", inet_ntoa(interface->sin_addr), strerror(errno));
                    }
                }

                if(!result)
                {
                    memset(&ctx->servaddr, 0, sizeof(ctx->servaddr));
                    ctx->servaddr.sin_family = AF_INET;
                    ctx->servaddr.sin_port = htons(port);
                    ctx->servaddr.sin_addr.s_addr = ipaddr;

                    one = 1;
                    if(setsockopt(ctx->http_socket, SOL_SOCKET, SO_KEEPALIVE, &one, sizeof(one)) != 0)
                        TRACE("Failed set socket keepalive\n");

                    one = 3; // the number of unacknowledged probes to send before considering the connection dead and notifying the application layer
                    if(setsockopt(ctx->http_socket, SOL_TCP, TCP_KEEPCNT, &one, sizeof(one)) != 0)
                        TRACE("Failed set socket keepalive\n");

                    one = 10; // the interval between the last data packet sent (simple ACKs are not considered data) and the first keepalive probe; after the connection is marked to need keepalive, this counter is not used any further
                    if(setsockopt(ctx->http_socket, SOL_TCP, TCP_KEEPIDLE, &one, sizeof(one)) != 0)
                        TRACE("Failed set socket keepalive\n");

                    one = 10; // the interval between subsequential keepalive probes, regardless of what the connection has exchanged in the meantime
                    if(setsockopt(ctx->http_socket, SOL_TCP, TCP_KEEPINTVL, &one, sizeof(one)) != 0)
                        TRACE("Failed set socket keepalive\n");

                    result = 0;
                }
                else
                {
                    shutdown(ctx->http_socket, SHUT_RDWR);
                    close(ctx->http_socket);
                    ctx->http_socket = -1;
                    result = -lib_http_error_fail_connect;
                }
            }
            else
            {
                TRACE("Failed(%d) create socket\n", result);
            }
        }
        else
        {
            // error translation.
            switch(herr)
            {
                case HOST_NOT_FOUND:
                    TRACE("Host not found: %s\n", host);
                    break;
                case NO_ADDRESS:
                    TRACE("The requested name does not have an IP address: \n");
                    break;
                case NO_RECOVERY:
                    TRACE("A non-recoverable name server error occurred while resolving \n");
                    break;
                case TRY_AGAIN:
                    TRACE("A temporary error occurred on an authoritative name server while resolving \n");
                    break;
                default:
                    TRACE("Unknown error code from gethostbyname_r for \n");
            }
            TRACE("Invalid address of host\n");
            result = -lib_http_error_dns;
        }
    }
    else
    {
        TRACE("invalid host value\n");
    }
    return result;
}

/*-----------------------------------------------------------------------------------------------------------------*/
static void lib_http_delete_socket(http_context_t *ctx)
{
    if(ctx)
    {
        if(ctx->http_socket != -1)
        {
            shutdown(ctx->http_socket, SHUT_RDWR);
            close(ctx->http_socket);
            ctx->http_socket = -1;
        }
    }
}

/*-----------------------------------------------------------------------------------------------------------------*/
static int http_open_cnx(http_context_t *ctx, char *resource, unsigned int resource_len, struct sockaddr_in *interface)
{
    int location_changed = 0, redirects = 0;
    int result = -lib_http_error_contex;
    const char *path;
    char hostname[HTTP_PATH_SIZE];
    char auth[HTTP_PATH_SIZE];
    int port;
    int https_proto = 0;
    int counter = 0;

    if(ctx)
        result = -lib_http_error_fail_http_error;

    while(ctx)
    {
        lib_http_url_split(NULL, 0, auth, sizeof(auth), hostname, sizeof(hostname), &port, ctx->path1, sizeof(ctx->path1), ctx->location, &https_proto);
        ctx->https_proto = https_proto;
        url_join(ctx->hoststr, sizeof(ctx->hoststr), NULL, NULL, hostname, port, NULL);
        //TRACE("hoststring %s host %s location %s\n", hoststr, hostname, ctx->location);
        if (ctx->path1[0] == '\0')
            path = "/";
        else
            path = ctx->path1;
        if (port < 0)
            port = (ctx->https_proto) ? 443 : 80;


        if(ctx->http_socket != -1)
        {
            int need_delete = 1;

            if(!ctx->willclose)
            {
                if(!strncmp(ctx->saved_hoststr, ctx->hoststr, sizeof(ctx->saved_hoststr)))
                    need_delete = 0;
            }
            if(need_delete == 0) //check socket valid or not
            {
                int ret = 0;
                struct pollfd ufd;

                memset(&ufd, 0, sizeof (ufd));
                ufd.fd = ctx->http_socket;
                ufd.events = POLLHUP;
                ret = poll(&ufd, 1, 100);
                if(ret > 0)
                {
                    if((ufd.revents & POLLHUP) || (ufd.revents & POLLERR) || (ufd.revents & POLLNVAL))
                        need_delete = 1;
                }
            }
            if(need_delete)
                lib_http_delete_socket(ctx);
        }

        if(ctx->https_proto)
        {
            result = -lib_http_error_fail_ssl_connect;
            TRACE("Failed ssl connect\n");
            break;
        }

        if(ctx->http_socket == -1)
        {
            result = lib_http_create_socket(ctx, hostname, port, true, interface);
            if(result != 0)
            {
                TRACE("%s:%d: Failed create socket for %s\n", __FUNCTION__, __LINE__, hostname);
                break;
            }
            else
            {
                result = connect(ctx->http_socket, (struct sockaddr*)&ctx->servaddr, sizeof(struct sockaddr_in));
                if(result != 0)
                {
                    char buffer[128] = { 0, };
                    strerror_r(errno, buffer, sizeof(buffer) - 1);
                    TRACE("Failed connect to host - %s\n", buffer);
                    shutdown(ctx->http_socket, SHUT_RDWR);
                    close(ctx->http_socket);
                    ctx->http_socket = -1;
                    result = -lib_http_error_fail_connect;
                }
            }
        }

        if(resource && resource_len)
            strncpy(resource, path, resource_len);

        result = http_connect(ctx, path, &location_changed);
        if(result != 0)
        {
            if(result == -lib_http_error_fail_http_connect)
            {
                if(counter++ < 1)
                {
                    lib_http_delete_socket(ctx);
                    continue;
                }
            }
            TRACE("Failed connect to %s\n", ctx->location);
            break;
        }

        if ((ctx->http_code == 301 || ctx->http_code == 302 || ctx->http_code == 303 || ctx->http_code == 307) && location_changed == 1)
        {
            // url moved, get next
            lib_http_delete_socket(ctx);
            if (redirects++ >= MAX_REDIRECTS)
            {
                TRACE("MAX Redirects count %d\n", redirects);
                result = -lib_http_error_fail_http_error;
                break;
            }
            location_changed = 0;
            continue;
        }
        break;
    }

    if(result && (ctx->http_socket != -1))
        lib_http_delete_socket(ctx);

    return result;
}

/*-----------------------------------------------------------------------------------------------------------------*/
void lib_http_clear_context(void *ctx)
{
    http_context_t *context = (http_context_t *)ctx;
    if(context)
    {
        memset(context, 0, sizeof(*context));
        context->http_socket = -1;
    }
}

int lib_http_open(void *ctx, int closeConnection, const char *uri, const char *user_agent, const char *content_type, const char *cookie, const char *post_data, int64_t offset, char *resource, unsigned int resource_len, struct sockaddr_in *interface)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -lib_http_error_contex;
    if(context)
    {
        http_strncpy(context->location, uri, sizeof(context->location));
        if(user_agent)
            http_strncpy(context->user_agent, user_agent, sizeof(context->user_agent));
        else
            context->user_agent[0] = 0;
        context->off = offset;
        context->need_keepalive = closeConnection ? false : true;
        result = http_open_cnx(context, resource, resource_len, interface);
    }
    return result;
}

int lib_http_open_first(void *ctx, int closeConnection, const char *uri, const char *user_agent, int64_t offset, char *resource, unsigned int resource_len, struct sockaddr_in *interface, lib_http_wait_t *waitinfo)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -lib_http_error_contex;
    int https_proto = 0;
    char hostname[HTTP_PATH_SIZE];
    char auth[HTTP_PATH_SIZE];
    int need_delete;
    int port;

    if(context)
    {
        http_strncpy(context->location, uri, sizeof(context->location));
        if(user_agent)
            http_strncpy(context->user_agent, user_agent, sizeof(context->user_agent));
        else
            context->user_agent[0] = 0;
        context->off = offset;
        context->need_keepalive = closeConnection ? false : true;
        context->stage = http_open_stage_init;

        lib_http_url_split(NULL, 0, auth, sizeof(auth), hostname, sizeof(hostname), &port, context->path1, sizeof(context->path1), context->location, &https_proto);
        context->https_proto = https_proto;
        url_join(context->hoststr, sizeof(context->hoststr), NULL, NULL, hostname, port, NULL);
        //TRACE("hoststring %s host %s location %s\n", hoststr, hostname, ctx->location);
        if (port < 0)
            port = (context->https_proto) ? 443 : 80;

        if(context->https_proto)
        {
            result = -lib_http_error_fail_ssl_connect;
            TRACE("Failed ssl connect\n");
        }
        else
        {
            if(context->http_socket != -1)
            {
                need_delete = 1;

                if(!context->willclose)
                {
                    if(!strncmp(context->saved_hoststr, context->hoststr, sizeof(context->saved_hoststr)))
                        need_delete = 0;
                }

                if(need_delete)
                {
                    TRACE("Need delete socket\n");
                    lib_http_delete_socket(context);
                }
            }

            if(context->http_socket == -1)
            {
                result = lib_http_create_socket(context, hostname, port, false, interface);
                if(result == 0)
                {
                    result = connect(context->http_socket, (struct sockaddr*)&context->servaddr, sizeof(struct sockaddr_in));
                    if(result == 0)
                    {
                        *waitinfo = lib_http_wait_write;
                        context->stage = http_open_stage_sendhttp;
                        result = lib_http_open_second(context, 0, waitinfo);
                    }
                    else if((result == -1) && (errno == EINPROGRESS))
                    {
                        *waitinfo = lib_http_wait_write;
                        context->stage = http_open_stage_connect;
                        result = 0;
                    }
                    else
                    {
                        result = -lib_http_error_fail_connect;
                    }
                }
                else
                {
                    TRACE("%s:%d: Failed create socket for %s\n", __FUNCTION__, __LINE__, hostname);
                }
            }
            else
            {
                context->stage = http_open_stage_sendhttp;
                *waitinfo = lib_http_wait_write;
                result = lib_http_open_second(context, 0, waitinfo);
            }
        }
    }
    return result;
}

int lib_http_open_second(void *ctx, int *connected, lib_http_wait_t *waitinfo)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -lib_http_error_contex;
    int new_location = 0;
    const char *path;

    if(connected)
        *connected = 0;

    if(context)
    {
        switch(context->stage)
        {
            case http_open_stage_init:
                logout("%s:%d: Invalid state 0x%X\n", __FUNCTION__, __LINE__, context->stage);
                break;
            case http_open_stage_connect:
                if(context->http_socket != -1)
                {
                    result = connect(context->http_socket, (struct sockaddr*)&context->servaddr, sizeof(struct sockaddr_in));
                    if(result == 0)
                    {
                        context->stage = http_open_stage_sendhttp;
                        *waitinfo = lib_http_wait_write;
                    }
                    else if((result == -1) && (errno == EINPROGRESS))
                    {
                        context->stage = http_open_stage_connect;
                        *waitinfo = lib_http_wait_write;
                        result = 0;
                        break;
                    }
                    else
                    {
                        logout("%s:%d: Failed connect: %s\n", __FUNCTION__, __LINE__, strerror(errno));
                        result = -lib_http_error_fail_connect;
                        break;
                    }
                }
            case http_open_stage_sendhttp:
                if (context->path1[0] == '\0')
                    path = "/";
                else
                    path = context->path1;
                result = http_connect_first(context, path);
                if(result == 0)
                {
                    context->stage = http_open_stage_readhttp;
                    *waitinfo = lib_http_wait_read;
                }
                else
                {
                    logout("%s:%d: Failed write http header\n", __FUNCTION__, __LINE__);
                }
                break;
            case http_open_stage_readhttp:
                result = http_connect_second(context, &new_location);
                if(result == 0)
                {
                    context->stage = http_open_stage_connected;
                    *waitinfo = lib_http_wait_read;
                    if(connected)
                        *connected = 1;
                }
                else
                {
                    logout("%s:%d: Failed read http header\n", __FUNCTION__, __LINE__);
                }
                break;
            case http_open_stage_connected:
                *waitinfo = lib_http_wait_read;
                if(connected)
                    *connected = 1;
                logout("%s:%d: Already connected\n", __FUNCTION__, __LINE__);
                break;
            default:
                logout("%s:%d: Unsupported state 0x%X\n", __FUNCTION__, __LINE__, context->stage);
                break;
        }
    }
    return result;
}

static int http_get_chunk_length(http_context_t *ctx)
{
    char line[64];
    int len = -EINVAL;

    if(!ctx->chunksize)
    {
        for(;;)
        {
            do {
                len = http_get_line(ctx, line, sizeof(line));
                if(len < 0)
                    return len;
            } while (!*line); // skip CR LF from last chunk
            ctx->chunksize = strtoull(line, 0, 16);
            if (!ctx->chunksize)
                return 0;
            break;
        }
    }
    else
    {
        logout("%s:%d: It's not chunked session\n", __FUNCTION__, __LINE__);
    }

    return len;
}

int lib_http_read(void *ctx, char *buf, int size)
{
    http_context_t *context = (http_context_t *)ctx;
    int len = -lib_http_error_contex, len2;
    int cnt = 10;

    if(context)
    {
        if(context->chunksize >= 0)
        {
            len2 = 0;
            while(len2 < size)
            {
                if(!context->chunksize)
                {
                    len = http_get_chunk_length(context);
                    if((len < 0) || (!context->chunksize))
                    {
                        break;
                    }
                }

                // read bytes from input buffer first
                len = context->buf_end - context->buf_ptr;
                if(len > 0)
                {
                    if(len > size)
                        len = size;
                    if(len > context->chunksize)
                        len = context->chunksize;
                    if(len > size - len2)
                        len = size - len2;
                    memcpy(buf + len2, context->buf_ptr, len);
                    context->buf_ptr += len;
                    context->chunksize -= len;
                    len2 += len;
                    if(!context->chunksize)
                        continue;
                }

                if(len2 < size)
                {
                    len = size - len2;
                    if(len > context->chunksize)
                        len = context->chunksize;
                    len = http_socket_read(context, buf + len2, len);
                    if(len > 0)
                    {
                        context->chunksize -= len;
                        len2 += len;
                        if(!context->chunksize)
                            continue;
                    }
                    else if(len < 0)
                    {
                        break;
                    }
                }
                if(!context->chunksize)
                    if(cnt-- == 0)
                        break;
            }
            len = len2 ? len2 : len;
            if(len > 0)
                context->off += len;
        }
        else
        {
            /* read bytes from input buffer first */
            len = context->buf_end - context->buf_ptr;
            if (len > 0)
            {
                if (len > size)
                    len = size;
                memcpy(buf, context->buf_ptr, len);
                context->buf_ptr += len;
            }
            if(len < size)
            {
                if ((context->filesize >= 0) && (context->off + len >= context->filesize))
                {
                    if(len > 0)
                        context->off += len;
                    return len;
                }
                len2 = http_socket_read(context, buf + len, size - len);
                if(len2 > 0)
                    len += len2;
                else if(!len)
                {
                    if(len2 < 0)
                        len = -lib_http_error_fail_io_error;
                    else
                        len = len2;
                }
            }

            if (len > 0)
                context->off += len;
        }
    }

    return len;
}

int lib_http_check_fill(void *ctx, bool flush)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -1;
    int len2;
    int len;

    if(context)
    {
        len = context->buf_end - context->buf_ptr;
        if(context->buf_ptr != context->buffer)
        {
            memmove(context->buffer, context->buf_ptr, len);
            context->buf_ptr = context->buffer;
            context->buf_end = context->buf_ptr + len;
        }

        if((len < sizeof(context->buffer)) && (((context->filesize >= 0) && (context->off + len < context->filesize)) || (context->filesize == -1)))
        {
            if(context->chunksize >= 0)
            {
                logout("%s:%d: Not implemented\n", __FUNCTION__, __LINE__);
            }
            else
            {
                len2 = http_socket_read(context, context->buf_end, sizeof(context->buffer) - len);
                if(len2 > 0)
                {
                    context->buf_end += len2;
                    len = context->buf_end - context->buf_ptr;
                }
            }
        }

        if((len == sizeof(context->buffer)) || (context->filesize == len))
        {
            if(flush)
            {
                context->buf_ptr = context->buffer;
                context->buf_end = context->buf_ptr;
                context->off += len;
            }
            result = 0;
        }

        if(!context->chunksize)
            http_get_chunk_length(context);
    }

    return result;
}

int lib_http_get_fd(void *ctx)
{
    http_context_t *context = (http_context_t *)ctx;
    int result = -1;

    if(context)
        result = context->http_socket;

    return result;
}

void lib_http_copy_connection(void *dst, void *src)
{
    http_context_t *dst_context = (http_context_t *)dst;
    http_context_t *src_context = (http_context_t *)src;

    if(dst_context && src_context)
    {
        memcpy(dst_context, src_context, sizeof(http_context_t));
        if(src_context->buf_ptr)
            dst_context->buf_ptr = dst_context->buffer + (src_context->buf_ptr - src_context->buffer);
        if(src_context->buf_end)
            dst_context->buf_end = dst_context->buffer + (src_context->buf_end - src_context->buffer);
        memset(src_context, 0, sizeof(http_context_t));
    }
}

bool lib_http_is_keepalive(void *ctx)
{
    http_context_t *context = (http_context_t *)ctx;
    bool result = false;

    if(context)
    {
        if((context->http_socket != -1) && !context->willclose)
        {
            if ((context->filesize >= 0) && (context->off >= context->filesize))
                result = true;
        }
    }

    return result;
}

void lib_http_close(void *ctx)
{
    http_context_t *context = (http_context_t *)ctx;

    if(context)
    {
        if(context->http_socket != -1)
            lib_http_delete_socket(context);
    }
}

int64_t lib_http_get_filesize(void *ctx)
{
    int64_t filesize = 0;
    http_context_t *context = (http_context_t *)ctx;

    if(context)
        filesize = context->filesize;

    return filesize;
}

uint32_t lib_get_http_context_size()
{
    return sizeof(http_context_t);
}

