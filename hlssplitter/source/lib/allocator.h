#ifndef __ALLOCATOR_H__
#define __ALLOCATOR_H__

typedef void * allocatorHandle_t;

typedef void (*itfunction)(void *ctx, allocatorHandle_t handle, void *address);

int allocator_create(allocatorHandle_t *handle, const char *name, void **privateMem, unsigned int privateSize);
int allocator_destroy(allocatorHandle_t handle);
void *allocator_get_object(allocatorHandle_t handle, unsigned int size);
void allocator_put_object(allocatorHandle_t handle, void *address);
void allocator_iterate_used(allocatorHandle_t handle, itfunction function, void *ctx);

#endif /* __ALLOCATOR_H__ */
