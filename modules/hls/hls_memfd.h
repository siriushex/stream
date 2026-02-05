#ifndef _HLS_MEMFD_H_
#define _HLS_MEMFD_H_ 1

#include <astra.h>

typedef struct hls_memfd_segment_t hls_memfd_segment_t;

bool hls_memfd_touch(const char *stream_id);
char *hls_memfd_copy_playlist(const char *stream_id, size_t *len);
hls_memfd_segment_t *hls_memfd_segment_acquire(const char *stream_id, const char *name);
void hls_memfd_segment_release(hls_memfd_segment_t *seg);
int hls_memfd_segment_fd(const hls_memfd_segment_t *seg);
const uint8_t *hls_memfd_segment_data(const hls_memfd_segment_t *seg);
size_t hls_memfd_segment_size(const hls_memfd_segment_t *seg);
bool hls_memfd_segment_is_memfd(const hls_memfd_segment_t *seg);
void hls_memfd_sweep(uint64_t now_us, int idle_timeout_sec);

#endif /* _HLS_MEMFD_H_ */
