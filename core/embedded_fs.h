#ifndef _ASC_EMBEDDED_FS_H_
#define _ASC_EMBEDDED_FS_H_ 1

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

bool embedded_fs_init(void);
void embedded_fs_destroy(void);

bool embedded_fs_enabled(void);
bool embedded_fs_exists(const char *path);
bool embedded_fs_get(const char *path, const uint8_t **data, size_t *size);

#endif /* _ASC_EMBEDDED_FS_H_ */
