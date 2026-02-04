#ifndef _HTTP_SERVER_H_
#define _HTTP_SERVER_H_

#include <sys/time.h>
#include <netinet/in.h>

#define MAX_KV_PAIRS                    20
#define KEY_LINE_SIZE                   50
#define VALUE_LINE_SIZE                 1024
#ifndef HTTP_SERVER_DESCRIPTION
#define HTTP_SERVER_DESCRIPTION         "STB100/BasicServer"
#endif
#ifndef USER_BUFFER_SIZE
#define USER_BUFFER_SIZE                0x10000
#endif
#define HTTP_SAVE_DESCRIPTOR            0x7A4F232E

typedef enum
{
    httpMethod_GET,
    httpMethod_HEAD,

    // not supported method
    httpMethod_Unknown
}httpMethod_t;

typedef struct
{
    char key[KEY_LINE_SIZE];
    char val[VALUE_LINE_SIZE];
}httpServerKeyValue_t;

struct httpServerWorkInstance;

typedef struct
{
    httpMethod_t method; // GET ot HEAD
    int http_version;
    int keepalive;
    int socket; // write data to socket
    struct sockaddr_in clientaddr;
    struct httpServerWorkInstance *instance;
}httpClientCtx_t;

typedef struct
{
    char requestedResource[VALUE_LINE_SIZE];
    httpClientCtx_t httpData;
    int count_pairs;
    httpServerKeyValue_t pairs[MAX_KV_PAIRS];
    struct sockaddr_in interfaceaddr;
    // user data - for speedup
    unsigned char buffer[USER_BUFFER_SIZE];
    unsigned int buffersize;
    int secondstart;
}httpServerGetData_t;

typedef void * httpServer_t;
typedef int (*httpServerCallBack_t)(void *ctx, httpServerGetData_t *data);

int start_http_server(httpServer_t *server, struct sockaddr_in *interface, unsigned int timeout, httpServerCallBack_t callback, void *ctx);
int stop_http_server(httpServer_t server);
int get_date_line(char *buffer, uint32_t size);
int get_date_time_from_stamp(time_t timestamp, char *buffer, unsigned int size);
int process_http_connection(httpClientCtx_t *httpData, struct iovec *data, unsigned int datacount);
int putResponseToBuffer(char *outbuffer, int outsize, int http_version, int keepalive, int code, const char *cdesc);

#endif // _HTTP_SERVER_H_
