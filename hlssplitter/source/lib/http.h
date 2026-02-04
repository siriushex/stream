#ifndef _UTILS_HTTP_H_
#define _UTILS_HTTP_H_

#include <stdint.h>
#include <stdbool.h>
#include <netinet/in.h>

#ifdef __cplusplus
extern "C"
{
#endif

typedef enum
{
    lib_http_error_contex = 1,
    lib_http_error_dns,
    lib_http_error_fail_connect,
    lib_http_error_fail_ssl_connect,
    lib_http_error_fail_http_connect,
    lib_http_error_fail_http_error,
    lib_http_error_fail_io_error,
}lib_http_errors_t;

typedef enum
{
    lib_http_wait_write,
    lib_http_wait_read
}lib_http_wait_t;

// On success, the 0 is returned, else lib_http_errors_t error is returned.
void lib_http_clear_context(void *ctx);
int lib_http_open(void *ctx, int closeConnection, const char *uri, const char *user_agent, const char *content_type, const char *cookie, const char *post_data, int64_t offset, char *resource, unsigned int resource_len, struct sockaddr_in *interface);
int lib_http_open_first(void *ctx, int closeConnection, const char *uri, const char *user_agent, int64_t offset, char *resource, unsigned int resource_len, struct sockaddr_in *interface, lib_http_wait_t *waitinfo);
int lib_http_open_second(void *ctx, int *connected, lib_http_wait_t *waitinfo);
void lib_http_url_split(char *proto, int proto_size, char *authorization, int authorization_size, char *hostname, int hostname_size, int *port_ptr, char *path, int path_size, const char *url, int *https_proto);
// On success, the number of bytes read is returned (zero indicates end of http chunk or payload), else lib_http_errors_t error is returned.
int lib_http_read(void *ctx, char *buf, int size);
int lib_http_check_fill(void *ctx, bool flush);
int lib_http_get_fd(void *ctx);
void lib_http_copy_connection(void *dst, void *src);
bool lib_http_is_keepalive(void *ctx);
void lib_http_close(void *ctx);
int64_t lib_http_get_filesize(void *ctx);
uint32_t lib_get_http_context_size(void);

#ifdef __cplusplus
}
#endif

#endif // _UTILS_HTTP_H_
