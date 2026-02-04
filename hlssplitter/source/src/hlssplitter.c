#include <sys/time.h>
#include <sys/poll.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/inotify.h>
#include <pthread.h>
#include <limits.h>
#include <unistd.h>
#include <string.h>
#include <signal.h>
#include <string.h>
#include <libgen.h>
#include <getopt.h>
#include <errno.h>
#include <stdio.h>

#include "httpserver.h"
#include "thread.h"
#include "ezxml.h"
#include "http.h"
#include "list.h"
#include "crc32.h"
#include "sha1.h"
#include "log.h"

#define HLS_LINK_SIZE                   1024
#define TS_PACKET_SIZE                  188
#define READ_BUFFER_SIZE                (TS_PACKET_SIZE * 512) // ~96kByte
#define DEFAULT_BANDWIDTH               2500000
#define DEFAULT_DURATION                1.0


typedef struct
{
    struct list_head list;
    char link[HLS_LINK_SIZE];
    char resource[HLS_LINK_SIZE];
    unsigned int bandwidth;
    float duration;
    threadHandle_t inputThread;
    unsigned int clients;
    pthread_mutex_t mutex;
    unsigned char readBuffer[READ_BUFFER_SIZE];
    unsigned char *storeBuffer;
    unsigned int storeBufferSize;
    unsigned int storePointer;
    unsigned int storedSize; // already in buffer
    unsigned int chunkSize; // size of current chunk
    unsigned int storedCrc;
    unsigned int executed;
    unsigned int crcVal;
    int have_in_interface;
    struct sockaddr_in in_interface;
}HLSLink_t;

typedef struct
{
    struct list_head list;
    unsigned int address;
}HLSAllowIp_t;

typedef struct
{
    struct list_head links;
    struct list_head allowIps;
    pthread_rwlock_t rwlock;
    unsigned short httpPort;
    httpServer_t server;
    int have_in_interface;
    int have_out_interface;
    struct sockaddr_in in_interface;
    struct sockaddr_in out_interface;
}HLSCoreData_t;

#pragma pack(push, 1)
typedef struct
{
    uint8_t tsHeader[4];
    uint32_t sig;
    uint64_t timestamp;
    uint64_t pts;
    uint64_t hls_seq;
    union {
        float duration;
        uint8_t _pad[8];
    };
    uint32_t x_channel_id;
    uint16_t x_bitrate;
    uint16_t x_bitrate_id;
    uint32_t prev_crc32, crc32;
    uint16_t chunk_index[50];
}streamSeeder_TsNullHeader_t;

#pragma pack(pop)

static void splitterReader(threadFunctionData_t *ctx);

static int send_header(httpServerGetData_t *data)
{
    char const send_ok[] = {
        "HTTP/1.%d 200 OK\r\n"
        "Content-Type: application/octet-stream\r\n"
        "Connection: close\r\n"
        "Cache-Control: no-cache\r\n"
        "Server: %s\r\n"
        "\r\n"
    };
    int length = 0;
    int result = 1;
    char buffer[512];

    length = snprintf(buffer, sizeof(buffer), send_ok, data->httpData.http_version, HTTP_SERVER_DESCRIPTION);
    if(length > 0)
    {
        result = send(data->httpData.socket, buffer, length, MSG_NOSIGNAL);
        if(result != length)
        {
            logout("%s:%d: Failed send %d != %d\n", __FUNCTION__, __LINE__, result, length);
            result = 1;
        }
        else
        {
            result = 0;
        }
    }
    else
    {
        logout("%s:%d: Failed create response\n", __FUNCTION__, __LINE__);
    }

    return result;
}

static int httpCallback(void *ctx, httpServerGetData_t *data)
{
    int result = 1;
    HLSCoreData_t *serverData;
    struct list_head *iterator;
    unsigned int cur_pointer;
    unsigned int pointer;
    unsigned int length;
    unsigned int size;
    unsigned int allow;
    unsigned int locked;
    struct pollfd ufds;
    int err;

    if(ctx && data)
    {
        serverData = (HLSCoreData_t *)ctx;

        allow = 0;
        pthread_rwlock_rdlock(&serverData->rwlock);
        locked = 1;
        list_for_each(iterator, &serverData->allowIps)
        {
            HLSAllowIp_t *allowIp = list_entry(iterator, HLSAllowIp_t, list);
            if(allowIp)
            {
                if(allowIp->address)
                {
                    if(allowIp->address == data->httpData.clientaddr.sin_addr.s_addr)
                    {
                        //logout("%s %d: ip address %d.%d.%d.%d == %d.%d.%d.%d\n", __FUNCTION__, __LINE__, (allowIp->address) & 0xFF, (allowIp->address >> 8) & 0xFF, (allowIp->address >> 16) & 0xFF, (allowIp->address >> 24) & 0xFF,
                        //                (data->clientaddr.sin_addr.s_addr) & 0xFF, (data->clientaddr.sin_addr.s_addr >> 8) & 0xFF, (data->clientaddr.sin_addr.s_addr >> 16) & 0xFF, (data->clientaddr.sin_addr.s_addr >> 24) & 0xFF);
                        allow = 1;
                        break;
                    }
                    else
                    {
                        //logout("%s %d: ip address %d.%d.%d.%d != %d.%d.%d.%d\n", __FUNCTION__, __LINE__, (allowIp->address) & 0xFF, (allowIp->address >> 8) & 0xFF, (allowIp->address >> 16) & 0xFF, (allowIp->address >> 24) & 0xFF,
                        //                (data->clientaddr.sin_addr.s_addr) & 0xFF, (data->clientaddr.sin_addr.s_addr >> 8) & 0xFF, (data->clientaddr.sin_addr.s_addr >> 16) & 0xFF, (data->clientaddr.sin_addr.s_addr >> 24) & 0xFF);
                    }
                }
                else
                {
                    allow = 1; // allow all IP addresses
                    break;
                }
            }
        }

        if(allow)
        {
            logout("%s %d: connected ip address %u.%u.%u.%u\n", __FUNCTION__, __LINE__, (data->httpData.clientaddr.sin_addr.s_addr) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 8) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 16) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 24) & 0xFF);

            list_for_each(iterator, &serverData->links)
            {
                HLSLink_t *link = list_entry(iterator, HLSLink_t, list);

                if(!strcmp(data->requestedResource, link->resource))
                {
                    int need_delete = 0;

                    pthread_mutex_lock(&link->mutex);
                    link->clients++;
                    pthread_mutex_unlock(&link->mutex);
                    if(locked)
                    {
                        locked = 0;
                        pthread_rwlock_unlock(&serverData->rwlock);
                    }
                    data->httpData.keepalive = 0;
                    result = send_header(data);
                    if(!result && (data->httpData.method == httpMethod_GET))
                    {
                        size = (link->bandwidth * link->duration) / 8;
                        if(size > link->storedSize) // if buffer is empty
                            size = link->storedSize;
                        if(size >= (link->storeBufferSize * 4 / 5)) // if buffer is big
                            size = (link->storeBufferSize * 4 / 5);

                        size = (size / TS_PACKET_SIZE) * TS_PACKET_SIZE;
                        pointer = link->storePointer;
                        if(pointer >= size)
                            pointer -= size;
                        else
                            pointer = link->storeBufferSize + pointer - size;
                        while(link->executed)
                        {
                            err = 0;

                            ufds.fd = data->httpData.socket;
                            ufds.events = POLLHUP | POLLERR;
                            ufds.revents = 0;

                            result = poll(&ufds, 1, 100);
                            if(result > 0)
                            {
                                if(ufds.revents & (POLLERR | POLLHUP)) // disconnected
                                {
                                    logout("%s:%d: Possible client %u.%u.%u.%u disconnected\n", __FUNCTION__, __LINE__, (data->httpData.clientaddr.sin_addr.s_addr) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 8) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 16) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 24) & 0xFF);
                                    err = 1;
                                    break;
                                }
                                else
                                {
                                    logout("%s:%d: Unknown event 0x%X\n", __FUNCTION__, __LINE__, ufds.revents);
                                    err = 1;
                                    break;
                                }
                            }
                            else
                            {
                                cur_pointer = link->storePointer;
                                while((pointer != cur_pointer) && link->storeBuffer)
                                {
                                    if(pointer > cur_pointer)
                                        length = link->storeBufferSize - pointer;
                                    else
                                        length = cur_pointer - pointer;
                                    result = send(data->httpData.socket, &link->storeBuffer[pointer], length, MSG_NOSIGNAL);
                                    if(result <= 0)
                                    {
                                        logout("%s:%d: Failed send %d != %d. Possible client %u.%u.%u.%u disconnected\n", __FUNCTION__, __LINE__, result, length, (data->httpData.clientaddr.sin_addr.s_addr) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 8) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 16) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 24) & 0xFF);
                                        err = 1;
                                        break;
                                    }
                                    pointer += result;
                                    if(pointer >= link->storeBufferSize)
                                        pointer -= link->storeBufferSize;
                                }
                            }
                            if(err)
                                break;
                        }
                        result = 0;
                    }
                    else if(result)
                        result = 2;

                    pthread_mutex_lock(&link->mutex);
                    link->clients--;
                    if(link->clients == 0)
                        need_delete = 1;
                    pthread_mutex_unlock(&link->mutex);

                    if(need_delete)
                    {
                        pthread_mutex_destroy(&link->mutex);
                        if(link->storeBuffer)
                        {
                            free(link->storeBuffer);
                            link->storeBuffer = 0;
                        }
                        free(link);
                    }

                    break;
                }
            }
        }
        else
        {
            logout("%s %d: Failed ip address %u.%u.%u.%u - not allowed\n", __FUNCTION__, __LINE__, (data->httpData.clientaddr.sin_addr.s_addr) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 8) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 16) & 0xFF, (data->httpData.clientaddr.sin_addr.s_addr >> 24) & 0xFF);
        }

        if(locked)
        {
            locked = 0;
            pthread_rwlock_unlock(&serverData->rwlock);
        }
    }

    return result;
}

static int create_data(HLSCoreData_t *data, ezxml_t root)
{
    ezxml_t link = 0;
    ezxml_t allow = 0;
    int result = 1;

    link = ezxml_child(root, "link");
    if(link)
    {
        while(link)
        {
            if(link->txt)
            {
                HLSLink_t *hlsLink = malloc(sizeof(HLSLink_t));
                if(hlsLink)
                {
                    memset(hlsLink, 0, sizeof(*hlsLink));
                    strncpy(hlsLink->link, link->txt, sizeof(hlsLink->link) - 1);
                    hlsLink->bandwidth = DEFAULT_BANDWIDTH;
                    hlsLink->duration = DEFAULT_DURATION;
                    hlsLink->clients = 1;
                    hlsLink->have_in_interface = data->have_in_interface;
                    hlsLink->in_interface = data->in_interface;
                    pthread_mutex_init(&hlsLink->mutex, NULL);

                    if(ezxml_attr(link, "bandwidth"))
                        hlsLink->bandwidth = atoi(ezxml_attr(link, "bandwidth"));
                    if(ezxml_attr(link, "buffering"))
                        hlsLink->duration = (float)atof(ezxml_attr(link, "buffering"));
                    hlsLink->storeBufferSize = ((unsigned int)(hlsLink->duration * hlsLink->bandwidth * 1.5 / 8.0) / TS_PACKET_SIZE) * TS_PACKET_SIZE;
                    list_add_tail(&hlsLink->list, &data->links);
                    logout("Add %s with bandwidth %u and duration %.2f\n", hlsLink->link, hlsLink->bandwidth, hlsLink->duration);
                    result = 0;
                }
                else
                {
                    logout("%s %d: Failed alloc %d bytes of data\n", __FUNCTION__, __LINE__, (int)sizeof(HLSLink_t));
                }
            }
            link = link->next;
        }
    }
    else
    {
        logout("%s %d: Error: no link data\n", __FUNCTION__, __LINE__);
    }

    if(!result)
    {
        allow = ezxml_child(root, "allowRange"); 
        if(allow)
        {
            while(allow)
            {
                ezxml_t from = ezxml_child(allow, "from");
                ezxml_t to = ezxml_child(allow, "to");

                if(from && to && from->txt && to->txt)
                {
                    unsigned int from_address[4];
                    unsigned int to_address[4];

                    if(sscanf(from->txt, "%u.%u.%u.%u", &from_address[0], &from_address[1], &from_address[2], &from_address[3]) == 4)
                    {
                        if(sscanf(to->txt, "%u.%u.%u.%u", &to_address[0], &to_address[1], &to_address[2], &to_address[3]) == 4)
                        {
                            if((from_address[0] <= to_address[0]) && (from_address[1] <= to_address[1]) && (from_address[2] <= to_address[2]) && (from_address[3] <= to_address[3]))
                            {
                                while(from_address[0] <= to_address[0])
                                {
                                    while(from_address[1] <= to_address[1])
                                    {
                                        while(from_address[2] <= to_address[2])
                                        {
                                            while(from_address[3] <= to_address[3])
                                            {
                                                HLSAllowIp_t *hlsIp = malloc(sizeof(HLSAllowIp_t));
                                                if(hlsIp)
                                                {
                                                    memset(hlsIp, 0, sizeof(*hlsIp));
                                                    hlsIp->address = htonl((from_address[0] << 24) | (from_address[1] << 16) | (from_address[2] << 8) | (from_address[3]));
                                                    list_add_tail(&hlsIp->list, &data->allowIps);
                                                }
                                                else
                                                {
                                                    logout("%s %d: Failed alloc %d bytes of data\n", __FUNCTION__, __LINE__, (int)sizeof(HLSAllowIp_t));
                                                }
                                                from_address[3]++;
                                            }
                                            from_address[3] = 0;
                                            from_address[2]++;
                                        }
                                        from_address[2] = 0;
                                        from_address[1]++;
                                    }
                                    from_address[1] = 0;
                                    from_address[0]++;
                                }
                            }
                            else
                            {
                                logout("%s %d: Invalid range from %u.%u.%u.%u to %u.%u.%u.%u\n", __FUNCTION__, __LINE__, from_address[0], from_address[1], from_address[2], from_address[3], to_address[0], to_address[1], to_address[2], to_address[3]);
                            }
                        }
                        else
                        {
                            logout("%s %d: Invalid \"to\" ip address %s\n", __FUNCTION__, __LINE__, to->txt);
                        }
                    }
                    else
                    {
                        logout("%s %d: Invalid \"from\" ip address %s\n", __FUNCTION__, __LINE__, from->txt);
                    }
                }
                allow = allow->next;
            }
        }
        allow = ezxml_child(root, "allow"); 
        if(allow)
        {
            while(allow)
            {
                if(allow->txt)
                {
                    unsigned int address[4];

                    if(sscanf(allow->txt, "%u.%u.%u.%u", &address[0], &address[1], &address[2], &address[3]) == 4)
                    {
                        HLSAllowIp_t *hlsIp = malloc(sizeof(HLSAllowIp_t));
                        if(hlsIp)
                        {
                            memset(hlsIp, 0, sizeof(*hlsIp));
                            hlsIp->address = htonl((address[0] << 24) | (address[1] << 16) | (address[2] << 8) | (address[3]));
                            list_add_tail(&hlsIp->list, &data->allowIps);
                        }
                        else
                        {
                            logout("%s %d: Failed alloc %d bytes of data\n", __FUNCTION__, __LINE__, (int)sizeof(HLSAllowIp_t));
                        }
                    }
                    else
                    {
                        logout("%s %d: Invalid ip address %s\n", __FUNCTION__, __LINE__, allow->txt);
                    }
                }
                allow = allow->next;
            }
        }

        if(list_empty(&data->allowIps))
        {
            logout("%s %d: Error: no allow ip address enable\n", __FUNCTION__, __LINE__);
        }
    }

    return result;
}

static void merge_data(HLSCoreData_t *data, HLSCoreData_t *newData)
{
    struct list_head *iterator;
    struct list_head *next;
    int result;

    pthread_rwlock_wrlock(&data->rwlock);
    // delete or modify available links
    list_for_each_safe(iterator, next, &data->links)
    {
        HLSLink_t *channel = list_entry(iterator, HLSLink_t, list);
        struct list_head *jterator;
        int need_delete = 1;

        list_for_each(jterator, &newData->links)
        {
            HLSLink_t *newChannel = list_entry(jterator, HLSLink_t, list);

            if(!strcmp(channel->link, newChannel->link))
            {
                // update buffer variables
                channel->bandwidth = newChannel->bandwidth;
                channel->duration = newChannel->duration;
                need_delete = 0;
                break;
            }
        }
        if(need_delete)
        {
            //logout("%s %d: Need destroy channel // remove\n", __FUNCTION__, __LINE__);
            if(channel->inputThread)
            {
                result = thread_stop(channel->inputThread);
                if(result)
                {
                    logout("%s %d: Failed stop read thread\n", __FUNCTION__, __LINE__);
                }
                channel->inputThread = 0;
            }
            list_del(&channel->list);

            pthread_mutex_lock(&channel->mutex);
            channel->clients--;
            if(channel->clients != 0)
                need_delete = 0;
            pthread_mutex_unlock(&channel->mutex);

            if(need_delete)
            {
                pthread_mutex_destroy(&channel->mutex);
                if(channel->storeBuffer)
                {
                    free(channel->storeBuffer);
                    channel->storeBuffer = 0;
                }
                free(channel);
            }
        }
    }
    // create of links
    list_for_each_safe(iterator, next, &newData->links)
    {
        HLSLink_t *newChannel = list_entry(iterator, HLSLink_t, list);
        struct list_head *jterator;
        int need_add = 1;

        list_for_each(jterator, &data->links)
        {
            HLSLink_t *channel = list_entry(jterator, HLSLink_t, list);

            if(!strcmp(channel->link, newChannel->link))
            {
                need_add = 0;
                break;
            }
        }

        if(need_add)
        {
            list_del(&newChannel->list);
            newChannel->executed = 1;
            result = thread_start(&newChannel->inputThread, splitterReader, newChannel, "splitterReader", threadPriority_Normal, 0, 0);
            if(result)
            {
                logout("%s %d: Failed start read thread\n", __FUNCTION__, __LINE__);
                pthread_mutex_destroy(&newChannel->mutex);
                free(newChannel);
            }
            else
            {
                list_add_tail(&newChannel->list, &data->links);
            }
        }
    }
    // delete invald ip addresses
    list_for_each_safe(iterator, next, &data->allowIps)
    {
        HLSAllowIp_t *ipAddress = list_entry(iterator, HLSAllowIp_t, list);
        struct list_head *jterator;
        int need_delete = 1;

        list_for_each(jterator, &newData->allowIps)
        {
            HLSAllowIp_t *newIpAddress = list_entry(jterator, HLSAllowIp_t, list);

            if(ipAddress->address == newIpAddress->address)
            {
                need_delete = 0;
                break;
            }
        }

        if(need_delete)
        {
            //logout("%s %d: Need remove ipaddres\n", __FUNCTION__, __LINE__);
            list_del(&ipAddress->list);
            free(ipAddress);
        }
    }
    // add ip address
    list_for_each_safe(iterator, next, &newData->allowIps)
    {
        HLSAllowIp_t *newIpAddress = list_entry(iterator, HLSAllowIp_t, list);
        struct list_head *jterator;
        int need_add = 1;

        list_for_each(jterator, &data->allowIps)
        {
            HLSAllowIp_t *ipAddress = list_entry(jterator, HLSAllowIp_t, list);

            if(ipAddress->address == newIpAddress->address)
            {
                need_add = 0;
                break;
            }
        }

        if(need_add)
        {
            //logout("%s %d: Need add ipaddres\n", __FUNCTION__, __LINE__);
            list_del(&newIpAddress->list);
            list_add_tail(&newIpAddress->list, &data->allowIps);
        }
    }
    pthread_rwlock_unlock(&data->rwlock);
}

static void destroy_data(HLSCoreData_t *data)
{
    struct list_head *iterator;
    struct list_head *next;

    pthread_rwlock_wrlock(&data->rwlock);
    list_for_each_safe(iterator, next, &data->links)
    {
        HLSLink_t *channel = list_entry(iterator, HLSLink_t, list);
        int need_delete = 1;

        list_del(&channel->list);
        pthread_mutex_lock(&channel->mutex);
        channel->clients--;
        if(channel->clients != 0)
            need_delete = 0;
        pthread_mutex_unlock(&channel->mutex);
        if(need_delete)
        {
            pthread_mutex_destroy(&channel->mutex);
            if(channel->storeBuffer)
            {
                free(channel->storeBuffer);
                channel->storeBuffer = 0;
            }
            free(channel);
        }
    }
    pthread_rwlock_unlock(&data->rwlock);
    usleep(10000); // for fix possible race conditions
    pthread_rwlock_wrlock(&data->rwlock);
    list_for_each_safe(iterator, next, &data->allowIps)
    {
        HLSAllowIp_t *allowIp = list_entry(iterator, HLSAllowIp_t, list);

        list_del(&allowIp->list);
        free(allowIp);
    }
    pthread_rwlock_unlock(&data->rwlock);
    usleep(10000); // for fix possible race conditions

    pthread_rwlock_destroy(&data->rwlock);
}

static volatile int needExecute = 1;
static int recreateLog = 0;

static void execute_handler(int signum)
{
    needExecute = 0;
}

static void recreatelog_handler(int signum)
{
    recreateLog = 1;
}

static void process_buffer(HLSLink_t *link, unsigned char *address, unsigned int size, int *needExecute)
{
    streamSeeder_TsNullHeader_t *tsPacketHeader;
    int need_add_packet;
    int need_calculate_crc;
    int i;

    for(i = 0; (i < size) && (*needExecute); i += TS_PACKET_SIZE)
    {
        unsigned short pid = (((unsigned short)address[i + 1] & 0x1F) << 8) | (address[i + 2]);

        need_add_packet = 1;
        need_calculate_crc = 1;

        if(pid == 0x1FFF)
        {
            tsPacketHeader = (streamSeeder_TsNullHeader_t *)&address[i];
            if(tsPacketHeader->sig == 0xB675AF7A)
            {
                if(link->crcVal != link->storedCrc)
                    logout("%s %d: Error CRC doesn't match 0x%X != 0x%X for variant %s\n", __FUNCTION__, __LINE__, link->crcVal, link->storedCrc, link->link);
                if(link->chunkSize >= link->storeBufferSize)
                    logout("%s %d: Error size of chunk is too big %d bytes for bandwidth %d and duration %f for variant %s\n", __FUNCTION__, __LINE__, link->chunkSize, link->bandwidth, link->duration, link->link);
                //printf("pid 0x%X, sig 0x%X, timestamp 0x%llX, pts 0x%llX, hls_seq 0x%llX, duration %f, chanId 0x%X, bitrate 0x%X, bitrateId 0x%X, prevCrc 0x%X, crc 0x%X\n", pid, tsPacketHeader->sig, (unsigned long long)tsPacketHeader->timestamp, (unsigned long long)tsPacketHeader->pts, (unsigned long long)tsPacketHeader->hls_seq, tsPacketHeader->duration,
                //       tsPacketHeader->x_channel_id, tsPacketHeader->x_bitrate, tsPacketHeader->x_bitrate_id, tsPacketHeader->prev_crc32, tsPacketHeader->crc32);
                link->storedCrc = tsPacketHeader->crc32;
                link->crcVal = 0xFFFFFFFF;
                link->chunkSize = 0;
                need_calculate_crc = 0; // skip calculation of nullpackets
            }
        }

        if(need_add_packet)
        {
            if(need_calculate_crc)
                link->crcVal = crc32(link->crcVal, &address[i], TS_PACKET_SIZE);
            memcpy(link->storeBuffer + link->storePointer, &address[i], TS_PACKET_SIZE);
            if(link->storePointer + TS_PACKET_SIZE >= link->storeBufferSize)
                link->storePointer = 0;
            else
                link->storePointer += TS_PACKET_SIZE;
            link->chunkSize += TS_PACKET_SIZE;
            if(link->storedSize + TS_PACKET_SIZE < link->storeBufferSize)
                link->storedSize += TS_PACKET_SIZE;
        }
    }
}

static void splitterReader(threadFunctionData_t *ctx)
{
    HLSLink_t *link = 0;
    int have_connection = 0;
    unsigned int size = 0;
    int count_packets = 0;
    int have_sync = 0;
    unsigned char *tempaddr;
    unsigned int tempsize;
    struct pollfd ufds;
    void *httpContext;
    int result;
    int i, j;
    unsigned long long readed = 0;
    unsigned long long processed = 0;
    unsigned long long processedOn10sec = 0;
    time_t lastWakeUpTime = time(0);

    if(ctx)
    {
        link = (HLSLink_t*)ctx->ctx;
        if(link)
        {
            httpContext = malloc(lib_get_http_context_size());
            if(httpContext)
            {
                if(!link->storeBuffer)
                    link->storeBuffer = malloc(link->storeBufferSize);

                if(link->storeBuffer)
                {
                    logout("%s %d: Start thread for %s stream\n", __FUNCTION__, __LINE__, link->link);

                    while(ctx->needExecute)
                    {
                        if(have_connection)
                        {
                            ufds.fd = lib_http_get_fd(httpContext); 
                            ufds.events = POLLIN | POLLPRI | POLLHUP | POLLERR;
                            ufds.revents = 0;

                            if(lastWakeUpTime + 10 < time(0))
                            {
                                lastWakeUpTime = time(0);
                                logout("%s %d: From stream %s readed %lld bytes in 10 secs\n", __FUNCTION__, __LINE__, link->link, processedOn10sec);
                                processedOn10sec = 0;
                            }

                            result = poll(&ufds, 1, 1000);
                            if(result > 0)
                            {
                                if(ufds.revents & (POLLERR | POLLHUP)) // disconnected
                                {
                                    logout("%s %d: disconnected\n", __FUNCTION__, __LINE__);
                                    lib_http_close(httpContext);
                                    have_connection = 0;
                                }
                                else
                                {
                                    result = lib_http_read(httpContext, (char*)link->readBuffer + size, sizeof(link->readBuffer) - size);
                                    if(result > 0)
                                    {
                                        processedOn10sec += result;
                                        size += result;
                                        readed += result;
                                        if(size > TS_PACKET_SIZE)
                                        {
                                            // check for sync
                                            have_sync = 1;
                                            count_packets = 0;
                                            for(i = 0, tempaddr = link->readBuffer; i < size; i += TS_PACKET_SIZE, tempaddr += TS_PACKET_SIZE)
                                            {
                                                if(i + TS_PACKET_SIZE > size)
                                                    break;
                                                if(*tempaddr != 0x47)
                                                {
                                                    have_sync = 0;
                                                    break;
                                                }
                                                count_packets++;
                                            }

                                            if(have_sync || count_packets)
                                            {
                                                tempsize = count_packets * TS_PACKET_SIZE;
                                                process_buffer(link, link->readBuffer, tempsize, &ctx->needExecute);
                                                processed += tempsize;
                                                size -= tempsize;
                                                if(size)
                                                    memmove(link->readBuffer, link->readBuffer + tempsize, size);
                                            }
                                            else
                                            {
                                                // check for valid ts
                                                for(i = 0; i + TS_PACKET_SIZE < size; i++)
                                                {
                                                    if((link->readBuffer[i] == 0x47) && (link->readBuffer[i + TS_PACKET_SIZE] == 0x47))
                                                    {
                                                        have_sync = 1;
                                                        break;
                                                    }
                                                }
                                                if(have_sync)
                                                {
                                                    for(j = i; j < size; j += TS_PACKET_SIZE)
                                                    {
                                                        if(j + TS_PACKET_SIZE > size)
                                                            break;
                                                        if(link->readBuffer[j] == 0x47)
                                                        {
                                                            count_packets++;
                                                        }
                                                        else
                                                        {
                                                            break;
                                                        }
                                                    }
                                                    if(count_packets)
                                                    {
                                                        tempsize = count_packets * TS_PACKET_SIZE;
                                                        process_buffer(link, link->readBuffer + i, tempsize, &ctx->needExecute);
                                                        processed += tempsize;
                                                        size -= tempsize + i;
                                                        if(size)
                                                            memmove(link->readBuffer, link->readBuffer + tempsize + i, size);
                                                    }
                                                    else
                                                    {
                                                        logout("%s %d: no sync in %d\n", __FUNCTION__, __LINE__, size);
                                                        size = 0;
                                                    }
                                                }
                                                else
                                                {
                                                    logout("%s %d: no sync in %d\n", __FUNCTION__, __LINE__, size);
                                                    size = 0;
                                                }
                                            }
                                        }
                                    }
                                    else
                                    {
                                        logout("%s %d: Failed read stream\n", __FUNCTION__, __LINE__);
                                        lib_http_close(httpContext);
                                        have_connection = 0;
                                    }
                                }
                            }
                        }
                        else
                        {
                            lib_http_clear_context(httpContext);
                            result = lib_http_open(httpContext, 1, link->link, 0, 0, 0, 0, 0, link->resource, sizeof(link->resource) - 1, link->have_in_interface ? &link->in_interface : NULL);
                            if(!result)
                            {
                                logout("Connected to stream %s\n", link->link);
                                have_connection = 1;
                                size = 0;
                            }
                            else
                            {
                                logout("%s %d: Failed connect to stream %s\n", __FUNCTION__, __LINE__, link->link);
                                sleep(5);
                            }
                        }
                    }
                }
                else
                {
                    logout("%s %d: Failed alloc %d bytes of memory for store buffer\n", __FUNCTION__, __LINE__, link->storeBufferSize);
                }

                if(have_connection)
                {
                    have_connection = 0;
                    lib_http_close(httpContext); 
                }
                free(httpContext);
                logout("%s %d: Stop thread for %s stream, readed %lld processed %lld\n", __FUNCTION__, __LINE__, link->link, readed, processed);
            }
            else
            {
                logout("%s %d: Failed alloc memory for HTTP context\n", __FUNCTION__, __LINE__);
            }
            link->executed = 0;
        }
        else
        {
            logout("%s %d: Invalid seeder\n", __FUNCTION__, __LINE__);
        }
    }
    else
    {
        logout("%s %d: Failed context in thread\n", __FUNCTION__, __LINE__);
    }
}

static int start_readers(HLSCoreData_t *data)
{
    int result = 1;
    struct list_head *iterator;

    if(data)
    {
        list_for_each(iterator, &data->links)
        {
            HLSLink_t *link = list_entry(iterator, HLSLink_t, list);
            link->executed = 1;
            result = thread_start(&link->inputThread, splitterReader, link, "splitterReader", threadPriority_Normal, 0, 0);
            if(result)
            {
                logout("%s %d: Failed start read thread\n", __FUNCTION__, __LINE__);
            }
        }
    }
    else
    {
        logout("%s %d: Invalid context\n", __FUNCTION__, __LINE__);
    }

    return result;
}

static void stop_readers(HLSCoreData_t *data)
{
    int result = 1;
    struct list_head *iterator;

    if(data)
    {
        list_for_each(iterator, &data->links)
        {
            HLSLink_t *link = list_entry(iterator, HLSLink_t, list);
            if(link->inputThread)
            {
                result = thread_stop(link->inputThread);
                if(result)
                {
                    logout("%s %d: Failed stop read thread\n", __FUNCTION__, __LINE__);
                }
                link->inputThread = 0;
            }
        }
    }
    else
    {
        logout("%s %d: Invalid context\n", __FUNCTION__, __LINE__);
    }
}

int get_buffer_from_file(const char *filename, unsigned char **buffer, unsigned int *buffersize)
{
    int result = -1;
    int fd;
    unsigned int filesize;

    fd = open(filename, O_RDONLY);
    if(fd != -1)
    {
        filesize = lseek(fd, 0, SEEK_END);
        lseek(fd, 0, SEEK_SET);

        if(filesize)
        {
            *buffer = malloc(filesize);
            if(*buffer)
            {
                result = read(fd, *buffer, filesize);
                if(result == filesize)
                {
                    *buffersize = filesize;
                    result = 0;
                }
                else
                {
                    logout("%s %d: Failed read file %s\n", __FUNCTION__, __LINE__, filename);
                    result = -1;
                }

                if(result)
                    free(*buffer);
            }
            else
            {
                logout("%s %d: Failed alloc %d bytes of memmory\n", __FUNCTION__, __LINE__, filesize);
            }
        }
        else
        {
            logout("%s %d: Invalid filesize %d\n", __FUNCTION__, __LINE__, filesize);
        }
        close(fd);
        fd = -1;
    }

    return result;
}

int main(int argc, char *argv[])
{
    int result = 1;
    int newLoglevel = logType_syslog;
    char *logfilename = "hlssplitter";
    int usePid = 1;
    static char inotifydir[PATH_MAX];
    static char inotifyfile[PATH_MAX];
    unsigned char configHash[SHA_DIGEST_LENGTH];
    unsigned int filesize;
    unsigned char *buffer;
    HLSCoreData_t data;
    char *filename = 0;
    struct pollfd pfd;
    int inotifyfd;

    loginit(logfilename, logType_syslog, 1);

    memset(inotifydir, 0, sizeof(inotifydir));
    memset(inotifyfile, 0, sizeof(inotifyfile));

    memset(&data, 0, sizeof(data));
    INIT_LIST_HEAD(&data.links);
    INIT_LIST_HEAD(&data.allowIps);
    pthread_rwlock_init(&data.rwlock, 0);

    signal(SIGINT, execute_handler);
    signal(SIGHUP, recreatelog_handler);

    while(1)
    {
        static struct option long_options[] =
                {
                    {"help",    no_argument,       0, 'h'},
                    {"in_interface",  required_argument, 0, 'i'},
                    {"out_interface",  required_argument, 0, 'o'},
                    {"logtype",  required_argument, 0, 'l'},
                    {"logpath",  required_argument, 0, 'n'},
                    {0, 0, 0, 0}
                };

        /* getopt_long stores the option index here. */
        int option_index = 0;
        int c = getopt_long (argc, argv, "hi:o:l:n:", long_options, &option_index);
        uint32_t address[4];

        /* Detect the end of the options. */
        if (c == -1)
            break;

        switch (c)
        {
            case 'h':
                printf("Usage: hlssplitter [option] config.xml [port]\n");
                printf("Options:\n");
                printf("\t--help\t\t\t\tdisplay this help and exit\n");
                printf("\t--in_interface ipaddress\tuse specified interface for input\n");
                printf("\t--out_interface ipaddress\tuse specified interface for output\n");
                printf("\t--logtype value\t\t\tvalue can be:\t0 - no log output\n");
                printf("\t\t\t\t\t\t\t1 - log output only in the terminal\n");
                printf("\t\t\t\t\t\t\t2 - log output only in the file\n");
                printf("\t\t\t\t\t\t\t4 - use the logging daemon syslog (used by default)\n");
                printf("\t\t\t\t\tIt may be combination of this values:\n");
                printf("\t\t\t\t\t\t\t3 - terminal output + file output\n");
                printf("\t\t\t\t\t\t\t5 - terminal output + syslog output\n");
                printf("\t\t\t\t\t\t\t6 - file + syslog output\n");
                printf("\t\t\t\t\t\t\t7 - terminal + file + syslog output\n");
                printf("\t--logpath path\t\t\tUser-defined log file\n");
                return 0;

            case 'i':
            case 'o':
                // add interface
                if(optarg && (*optarg != 0) && sscanf(optarg, "%u.%u.%u.%u", &address[0], &address[1], &address[2], &address[3]) == 4)
                {
                    if(c == 'i')
                    {
                        data.in_interface.sin_family = AF_INET;
                        data.in_interface.sin_addr.s_addr = htonl((address[0] << 24) | (address[1] << 16) | (address[2] << 8) | (address[3]));
                        logout("%s %d: Added input interface %u.%u.%u.%u\n", __FUNCTION__, __LINE__, address[0], address[1], address[2], address[3]);
                        data.have_in_interface = 1;
                    }
                    else
                    {
                        data.out_interface.sin_family = AF_INET;
                        data.out_interface.sin_addr.s_addr = htonl((address[0] << 24) | (address[1] << 16) | (address[2] << 8) | (address[3]));
                        logout("%s %d: Added output interface %u.%u.%u.%u\n", __FUNCTION__, __LINE__, address[0], address[1], address[2], address[3]);
                        data.have_out_interface = 1;
                    }
                }
                else
                {
                    logout("%s %d: invalid interface: %s\n", __FUNCTION__, __LINE__, optarg);
                }
                break;
            case 'l':
                if(optarg && (*optarg != 0))
                {
                    newLoglevel = atoi(optarg);
                    //logout("%s %d: Set new log level %d\n", __FUNCTION__, __LINE__, newLoglevel);
                    logdeinit();
                    loginit(logfilename, newLoglevel, usePid);
                }
                break;
            case 'n':
                if(optarg && (*optarg != 0))
                {
                    logfilename = optarg;
                    usePid = 0;
                    //logout("%s %d: Set new log filepath %s\n", __FUNCTION__, __LINE__, optarg);
                    logdeinit();
                    loginit(logfilename, newLoglevel, usePid);
                }
                break;
            default:
                logout("%s %d: invalid option %d\n", __FUNCTION__, __LINE__, c);
                return 1;
        }
    }

    if (optind >= argc)
    {
        printf("Try to use: hlssplitter --help\n");
    }
    else
    {
        if(argc - optind >= 2)
            data.httpPort = atoi(argv[optind + 1]);
        if(!data.httpPort)
            data.httpPort = 80;

        if(!get_buffer_from_file(argv[optind], &buffer, &filesize))
        {
            // create hash of config file
            {
                SHA_CTXL c;

                SHA1L_Init(&c);
                SHA1L_Update(&c, buffer, filesize);
                SHA1L_Final(configHash, &c);
            }

            // create core data
            {
                ezxml_t root = ezxml_parse_str((char*)buffer, filesize);
                if(root)
                {
                    if(root->name && !strcmp(root->name, "resources"))
                    {
                        result = create_data(&data, root);
                    }
                    else
                    {
                        logout("%s %d: invalid xml\n", __FUNCTION__, __LINE__);
                    }
                    ezxml_free(root);
                }
                else
                {
                    logout("%s %d: failed parse xml\n", __FUNCTION__, __LINE__);
                }
            }
            // free buffer
            free(buffer);

            if(!result)
            {
                strncpy(inotifydir, argv[optind], sizeof(inotifydir));
                strncpy(inotifyfile, argv[optind], sizeof(inotifyfile));

                if(data.have_out_interface)
                {
                    data.out_interface.sin_port = htons(data.httpPort);
                }
                else
                {
                    memset(&data.out_interface, 0, sizeof(data.out_interface));
                    data.out_interface.sin_family = AF_INET;
                    data.out_interface.sin_port = htons(data.httpPort);
                    data.out_interface.sin_addr.s_addr = htonl(INADDR_ANY);
                }

                if(!start_http_server(&data.server, &data.out_interface, 30, httpCallback, &data))
                {
                    if(!start_readers(&data))
                    {
                        inotifyfd = inotify_init();
                        if(inotifyfd != -1)
                        {
                            char *iDir = dirname(inotifydir);

                            filename = basename(inotifyfile);

                            if(iDir && filename)
                            {
                                result = inotify_add_watch(inotifyfd, iDir, IN_CLOSE_WRITE | IN_MOVE_SELF | IN_MOVED_TO);
                                if(result >= 0)
                                {
                                    logout("%s %d: Inotify inited in directory [%s]\n", __FUNCTION__, __LINE__, iDir);
                                }
                                else
                                {
                                    logout("%s %d: Failed add %s to inotify\n", __FUNCTION__, __LINE__, iDir);
                                    close(inotifyfd);
                                    inotifyfd = -1;
                                }
                            }
                            else
                            {
                                logout("%s %d: Failed inotify path init\n", __FUNCTION__, __LINE__);
                                close(inotifyfd);
                                inotifyfd = -1;
                            }
                        }
                        else
                        {
                            logout("%s %d: Failed inotify init\n", __FUNCTION__, __LINE__);
                        }

                        while(needExecute)
                        {
                            if(inotifyfd != -1)
                            {
                                int have_event = 0;

                                pfd.fd = inotifyfd;
                                pfd.events = POLLIN | POLLPRI | POLLHUP;
                                pfd.revents = 0;
                                result = poll(&pfd, 1, -1);
                                if(result > 0)
                                {
                                    unsigned char buffer[0x1000];

                                    result = read(inotifyfd, buffer, sizeof(buffer));
                                    if(result > 0)
                                    {
                                        int len = 0;

                                        //logout("%s %d: Readed %d bytes\n", __FUNCTION__, __LINE__, result);
                                        while(len < result)
                                        {
                                            struct inotify_event *event = (struct inotify_event *)&buffer[len];
                                            //logout("%s %d: Have event 0x%X %s\n", __FUNCTION__, __LINE__, event->mask, event->name);

                                            if(!strcmp(filename, event->name))
                                                have_event = 1;

                                            len += sizeof(struct inotify_event) + event->len;
                                        }
                                    }
                                }
                                else if((result < 0) && (errno != EINTR))
                                {
                                    logout("%s %d: Failed inotify work\n", __FUNCTION__, __LINE__);
                                    close(inotifyfd);
                                    inotifyfd = -1;
                                }

                                if(have_event)
                                {
                                    //logout("%s %d: Need check config file %s for changes\n", __FUNCTION__, __LINE__, filename);
                                    if(!get_buffer_from_file(argv[optind], &buffer, &filesize))
                                    {
                                        SHA_CTXL c;
                                        unsigned char curHash[SHA_DIGEST_LENGTH];

                                        SHA1L_Init(&c);
                                        SHA1L_Update(&c, buffer, filesize);
                                        SHA1L_Final(curHash, &c);

                                        if(memcmp(curHash, configHash, SHA_DIGEST_LENGTH) != 0)
                                        {
                                            ezxml_t root = ezxml_parse_str((char*)buffer, filesize);
                                            HLSCoreData_t newData;

                                            memset(&newData, 0, sizeof(newData));
                                            INIT_LIST_HEAD(&newData.links);
                                            INIT_LIST_HEAD(&newData.allowIps);
                                            pthread_rwlock_init(&data.rwlock, 0);

                                            if(data.have_in_interface)
                                            {
                                                newData.have_in_interface = data.have_in_interface;
                                                newData.in_interface = data.in_interface;
                                            }
                                            if(data.have_out_interface) // for future features
                                            {
                                                newData.have_out_interface = data.have_out_interface;
                                                newData.out_interface = data.out_interface;
                                            }

                                            logout("%s %d: Need update data from config %s\n", __FUNCTION__, __LINE__, filename);

                                            if(root)
                                            {
                                                if(root->name && !strcmp(root->name, "resources"))
                                                {
                                                    result = create_data(&newData, root);
                                                    if(!result)
                                                    {
                                                        logout("%s %d: merge config\n", __FUNCTION__, __LINE__);
                                                        merge_data(&data, &newData);
                                                    }
                                                }
                                                else
                                                {
                                                    logout("%s %d: invalid xml\n", __FUNCTION__, __LINE__);
                                                }
                                                ezxml_free(root);
                                            }
                                            else
                                            {
                                                logout("%s %d: failed parse xml\n", __FUNCTION__, __LINE__);
                                            }
                                            destroy_data(&newData);
                                            memcpy(configHash, curHash, SHA_DIGEST_LENGTH);
                                        }
                                        else
                                        {
                                            logout("%s %d: Config file %s the same\n", __FUNCTION__, __LINE__, filename);
                                        }
                                        free(buffer);
                                    }
                                }

                                if(recreateLog)
                                {
                                    recreateLog = 0;
                                    logrenew();
                                }
                            }
                            else
                            {
                                sleep(3600);
                            }
                        }

                        if(inotifyfd != -1)
                        {
                            close(inotifyfd);
                            inotifyfd = -1;
                        }
                        stop_readers(&data);
                    }

                    if(stop_http_server(data.server))
                    {
                        logout("%s %d: Failed stop server\n", __FUNCTION__, __LINE__);
                    }
                }
                else
                {
                    logout("%s %d: Failed start http server\n", __FUNCTION__, __LINE__);
                }
            }
            destroy_data(&data);
        }
        else
        {
            logout("%s %d: Failed open file %s\n", __FUNCTION__, __LINE__, argv[optind]);
        }
    }
    logdeinit();

    return result;
}

