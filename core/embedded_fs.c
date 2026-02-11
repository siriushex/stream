#include <astra.h>

#include "embedded_fs.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef ASTRA_EMBEDDED_ASSETS_BLOB
extern const unsigned char astra_assets_tar[];
extern const unsigned int astra_assets_tar_len;
#else
extern const unsigned char _binary_assets_tar_start[];
extern const unsigned char _binary_assets_tar_end[];
#endif

typedef struct
{
    char *path;
    const uint8_t *data;
    size_t size;
} embedded_entry_t;

typedef struct
{
    bool init_done;
    bool ready;
    embedded_entry_t *items;
    size_t count;
    size_t cap;
} embedded_fs_state_t;

static embedded_fs_state_t g_embedded = { 0 };

#pragma pack(push, 1)
typedef struct
{
    char name[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char chksum[8];
    char typeflag;
    char linkname[100];
    char magic[6];
    char version[2];
    char uname[32];
    char gname[32];
    char devmajor[8];
    char devminor[8];
    char prefix[155];
    char pad[12];
} tar_header_t;
#pragma pack(pop)

static bool embedded_blob_view(const uint8_t **start, size_t *size)
{
#ifdef ASTRA_EMBEDDED_ASSETS_BLOB
    if(astra_assets_tar_len == 0)
        return false;
    *start = astra_assets_tar;
    *size = (size_t)astra_assets_tar_len;
    return true;
#else
    if(_binary_assets_tar_end <= _binary_assets_tar_start)
        return false;
    *start = _binary_assets_tar_start;
    *size = (size_t)(_binary_assets_tar_end - _binary_assets_tar_start);
    return true;
#endif
}

static bool is_zero_block(const uint8_t *block)
{
    for(size_t i = 0; i < 512; ++i)
    {
        if(block[i] != 0)
            return false;
    }
    return true;
}

static size_t parse_octal(const char *src, size_t len)
{
    size_t value = 0;
    size_t i = 0;

    while(i < len && (src[i] == ' ' || src[i] == '\0'))
        ++i;

    for(; i < len; ++i)
    {
        const unsigned char c = (unsigned char)src[i];
        if(c == '\0' || c == ' ')
            break;
        if(c < '0' || c > '7')
            break;
        value = (value << 3) + (size_t)(c - '0');
    }

    return value;
}

static bool normalize_path(const char *input, char *out, size_t out_size)
{
    if(!input || !out || out_size == 0)
        return false;

    size_t i = 0;
    size_t o = 0;

    while(input[i] == ' ')
        ++i;

    while(input[i] == '.' && input[i + 1] == '/')
        i += 2;

    while(input[i] == '/')
        ++i;

    bool last_slash = false;

    for(; input[i] != '\0'; ++i)
    {
        char c = input[i];
        if(c == '\\')
            c = '/';

        if(c == '/')
        {
            if(last_slash)
                continue;
            last_slash = true;
        }
        else
        {
            last_slash = false;
        }

        if(o + 1 >= out_size)
            return false;

        out[o++] = c;
    }

    while(o > 0 && out[o - 1] == '/')
        --o;

    out[o] = '\0';

    if(o == 0)
        return false;

    if(strstr(out, "../") || strstr(out, "/..") || strcmp(out, "..") == 0)
        return false;

    return true;
}

static int compare_entries(const void *a, const void *b)
{
    const embedded_entry_t *ea = (const embedded_entry_t *)a;
    const embedded_entry_t *eb = (const embedded_entry_t *)b;
    return strcmp(ea->path, eb->path);
}

static bool append_entry(const char *path, const uint8_t *data, size_t size)
{
    if(g_embedded.count == g_embedded.cap)
    {
        const size_t next_cap = g_embedded.cap ? g_embedded.cap * 2 : 256;
        embedded_entry_t *next = (embedded_entry_t *)realloc(g_embedded.items, next_cap * sizeof(embedded_entry_t));
        if(!next)
            return false;
        g_embedded.items = next;
        g_embedded.cap = next_cap;
    }

    char *dup = strdup(path);
    if(!dup)
        return false;

    embedded_entry_t *entry = &g_embedded.items[g_embedded.count++];
    entry->path = dup;
    entry->data = data;
    entry->size = size;
    return true;
}

static bool parse_tar_bundle(const uint8_t *blob, size_t blob_size)
{
    const uint8_t *ptr = blob;
    const uint8_t *end = blob + blob_size;

    while((size_t)(end - ptr) >= 512)
    {
        if(is_zero_block(ptr))
            break;

        const tar_header_t *hdr = (const tar_header_t *)ptr;

        char raw_path[320];
        raw_path[0] = '\0';

        if(hdr->prefix[0] != '\0')
        {
            snprintf(raw_path, sizeof(raw_path), "%s/%s", hdr->prefix, hdr->name);
        }
        else
        {
            snprintf(raw_path, sizeof(raw_path), "%s", hdr->name);
        }

        char path[320];
        if(!normalize_path(raw_path, path, sizeof(path)))
            path[0] = '\0';

        const size_t size = parse_octal(hdr->size, sizeof(hdr->size));
        const uint8_t *data = ptr + 512;

        if(data > end || size > (size_t)(end - data))
            return false;

        char type = hdr->typeflag;
        if(type == '\0')
            type = '0';

        if((type == '0' || type == '7') && path[0] != '\0')
        {
            if(!append_entry(path, data, size))
                return false;
        }

        const size_t padded = (size + 511) & ~(size_t)511;
        if((size_t)(end - data) < padded)
            return false;

        ptr = data + padded;
    }

    if(g_embedded.count == 0)
        return false;

    qsort(g_embedded.items, g_embedded.count, sizeof(embedded_entry_t), compare_entries);
    return true;
}

bool embedded_fs_init(void)
{
    if(g_embedded.init_done)
        return g_embedded.ready;

    g_embedded.init_done = true;

    const uint8_t *blob = NULL;
    size_t blob_size = 0;
    if(!embedded_blob_view(&blob, &blob_size))
    {
        asc_log_warning("[embedded_fs] assets bundle is empty");
        return false;
    }

    if(!parse_tar_bundle(blob, blob_size))
    {
        asc_log_error("[embedded_fs] failed to parse embedded assets tar");
        return false;
    }

    g_embedded.ready = true;
    asc_log_info("[embedded_fs] loaded %zu embedded files", g_embedded.count);
    return true;
}

void embedded_fs_destroy(void)
{
    if(g_embedded.items)
    {
        for(size_t i = 0; i < g_embedded.count; ++i)
            free(g_embedded.items[i].path);
        free(g_embedded.items);
    }

    memset(&g_embedded, 0, sizeof(g_embedded));
}

bool embedded_fs_enabled(void)
{
    return embedded_fs_init();
}

bool embedded_fs_get(const char *path, const uint8_t **data, size_t *size)
{
    if(!embedded_fs_init())
        return false;

    char key[320];
    if(!normalize_path(path, key, sizeof(key)))
        return false;

    size_t left = 0;
    size_t right = g_embedded.count;
    while(left < right)
    {
        const size_t mid = left + (right - left) / 2;
        const int cmp = strcmp(key, g_embedded.items[mid].path);
        if(cmp == 0)
        {
            if(data)
                *data = g_embedded.items[mid].data;
            if(size)
                *size = g_embedded.items[mid].size;
            return true;
        }
        if(cmp < 0)
            right = mid;
        else
            left = mid + 1;
    }

    return false;
}

bool embedded_fs_exists(const char *path)
{
    return embedded_fs_get(path, NULL, NULL);
}
