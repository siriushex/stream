#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include "allocator.h"
#include "mutex.h"
#include "list.h"
#include "log.h"

#define ALLOCATOR_MAGIC_VALUE           0xEBAC35F3
#define ALLOCATOR_ENTRY_MAGIC_VALUE     0xDC37A255
#define ALLOCATOR_DEFAULT_SIZE          0x1000000
#define ALLOCATOR_ALIGN_SIZE            0x10
#define ALLOCATOR_NAME_LEN              0x40

#define ALLOCATOR_ALIGNED_SIZE(x)       ( \
                                             ((unsigned int)(x) & (~(ALLOCATOR_ALIGN_SIZE - 1))) + \
                                             (((unsigned int)(x) & (ALLOCATOR_ALIGN_SIZE - 1)) ? ALLOCATOR_ALIGN_SIZE : 0) \
                                         )

// #define ALLOCATOR_DEBUG

typedef struct
{
    struct list_head list;
    unsigned int magic;
    unsigned int size;
    allocatorHandle_t handle;
}allocatorEntry_t;

typedef struct
{
    unsigned int magic;
    mutex_t mutex;
    struct list_head freeList;
    struct list_head usedList;
    struct list_head allocatedList;
    unsigned int countFree;
    unsigned int countUsed;
    unsigned int countAllocated;
    unsigned int objectSize;
    unsigned int privateSize;
    char name[ALLOCATOR_NAME_LEN];
}allocatorData_t;

int allocator_create(allocatorHandle_t *handle, const char *name, void **privateMem, unsigned int privateSize)
{
    int result = EINVAL;
    allocatorData_t *newHandle;

    if(handle && name)
    {
        if(privateMem && privateSize)
        {
            if(ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorData_t)) + ALLOCATOR_ALIGNED_SIZE(privateSize) >= ALLOCATOR_DEFAULT_SIZE)
            {
                logout("%s %d: Invalid private size %d bytes\n", __FUNCTION__, __LINE__, privateSize);
                return EINVAL;
            }
        }

        newHandle = mmap(0, ALLOCATOR_DEFAULT_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
        if((void *)newHandle != MAP_FAILED)
        {
            if(mutex_init(&newHandle->mutex, false))
            {
                newHandle->magic = ALLOCATOR_MAGIC_VALUE;
                INIT_LIST_HEAD(&newHandle->freeList);
                INIT_LIST_HEAD(&newHandle->usedList);
                INIT_LIST_HEAD(&newHandle->allocatedList);
                if(privateMem && privateSize)
                {
                    newHandle->privateSize = ALLOCATOR_ALIGNED_SIZE(privateSize);
                    *privateMem = (unsigned char*)newHandle + ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorData_t));
                }
                strncpy(newHandle->name, name, sizeof(newHandle->name) - 1);
                *handle = newHandle;
                result = 0;
            }
            else
            {
                logout("%s %d: Failed mutex_init\n", __FUNCTION__, __LINE__);
            }

            if(newHandle->magic != ALLOCATOR_MAGIC_VALUE)
            {
                if(munmap(newHandle, ALLOCATOR_DEFAULT_SIZE))
                    logout("%s %d: Failed munmap memory: %s\n", __FUNCTION__, __LINE__, strerror(errno));
            }
        }
        else
        {
            logout("%s %d: Failed mmap %d bytes of memory: %s\n", __FUNCTION__, __LINE__, ALLOCATOR_DEFAULT_SIZE, strerror(errno));
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

int allocator_destroy(allocatorHandle_t handle)
{
    int result = EINVAL;
    struct list_head *iterator, *next;
    allocatorData_t *inHandle;

    if(handle)
    {
        inHandle = handle;
        if(inHandle->magic == ALLOCATOR_MAGIC_VALUE)
        {
            inHandle->magic = 0;
            result = 0;
            if(!list_empty(&inHandle->usedList))
                logout("%s %d: We have allocated memory at %s: %d entries !!!!\n", __FUNCTION__, __LINE__, inHandle->name, inHandle->countUsed);
#ifdef ALLOCATOR_DEBUG
            logout("%s %d: Allocator %s stat: %d - free, %d - used, %d - maps!\n", __FUNCTION__, __LINE__, inHandle->name, inHandle->countFree, inHandle->countUsed, inHandle->countAllocated + 1);
#endif
            if(!list_empty(&inHandle->allocatedList))
            {
                list_for_each_safe(iterator, next, &inHandle->allocatedList)
                {
                    if(munmap(iterator, ALLOCATOR_DEFAULT_SIZE))
                        logout("%s %d: Failed munmap memory: %s\n", __FUNCTION__, __LINE__, strerror(errno));
                }
            }
            mutex_term(&inHandle->mutex);
            if(munmap(inHandle, ALLOCATOR_DEFAULT_SIZE))
                logout("%s %d: Failed munmap memory: %s\n", __FUNCTION__, __LINE__, strerror(errno));
        }
        else
        {
            logout("%s %d: Invalid magic value 0x%X != 0x%X\n", __FUNCTION__, __LINE__, inHandle->magic, ALLOCATOR_MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return result;
}

void *allocator_get_object(allocatorHandle_t handle, unsigned int size)
{
    void *resAddr = 0;
    allocatorData_t *inHandle;
    unsigned int chunkSize;
    unsigned int tmpSize;
    void *tmpAddr;

    if(handle)
    {
        inHandle = handle;
        if(inHandle->magic == ALLOCATOR_MAGIC_VALUE)
        {
            if(mutex_lock(&inHandle->mutex))
            {
                chunkSize = ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorEntry_t)) + ALLOCATOR_ALIGNED_SIZE(size);
                //logout("%s %d: Chunk size is %u == %u(%lu) + %u(%u)\n", __FUNCTION__, __LINE__, chunkSize, ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorEntry_t)), sizeof(allocatorEntry_t), ALLOCATOR_ALIGNED_SIZE(size), size);
                if(inHandle->objectSize == 0)
                {
                    tmpSize = ALLOCATOR_DEFAULT_SIZE - (ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorData_t)) + inHandle->privateSize);
                    tmpAddr = (unsigned char*)inHandle + ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorData_t)) + inHandle->privateSize;
                    if(tmpSize >= chunkSize)
                    {
                        inHandle->objectSize = chunkSize;
                        while(tmpSize >= chunkSize)
                        {
                            allocatorEntry_t *entry = (allocatorEntry_t *)tmpAddr;
                            entry->magic = ALLOCATOR_ENTRY_MAGIC_VALUE;
                            entry->size = chunkSize;
                            entry->handle = inHandle;
                            list_add_tail(&entry->list, &inHandle->freeList);
                            inHandle->countFree++;
                            tmpSize -= chunkSize;
                            tmpAddr = (unsigned char*)tmpAddr + chunkSize;
                        }
#ifdef ALLOCATOR_DEBUG
                        logout("%s %d: Allocator %s stat: %d - free, %d - used, %d - maps!\n", __FUNCTION__, __LINE__, inHandle->name, inHandle->countFree, inHandle->countUsed, inHandle->countAllocated + 1);
#endif
                    }
                    else
                    {
                        logout("%s %d: No memory for object with size %d bytes(limit: %d)\n", __FUNCTION__, __LINE__, chunkSize, tmpSize);
                    }
                }

                if((inHandle->objectSize != 0) && (inHandle->objectSize == chunkSize))
                {
                    if(list_empty(&inHandle->freeList))
                    {
                        tmpAddr = mmap(0, ALLOCATOR_DEFAULT_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
                        if((void *)tmpAddr != MAP_FAILED)
                        {
                            struct list_head *alEntry = (struct list_head *)tmpAddr;

                            list_add_tail(alEntry, &inHandle->allocatedList);
                            inHandle->countAllocated++;
                            tmpSize = ALLOCATOR_DEFAULT_SIZE - ALLOCATOR_ALIGNED_SIZE(sizeof(struct list_head));
                            tmpAddr = (unsigned char*)tmpAddr + ALLOCATOR_ALIGNED_SIZE(sizeof(struct list_head));
                            if(tmpSize >= chunkSize)
                            {
                                while(tmpSize >= chunkSize)
                                {
                                    allocatorEntry_t *entry = (allocatorEntry_t *)tmpAddr;
                                    entry->magic = ALLOCATOR_ENTRY_MAGIC_VALUE;
                                    entry->size = chunkSize;
                                    entry->handle = inHandle;
                                    list_add_tail(&entry->list, &inHandle->freeList);
                                    inHandle->countFree++;
                                    tmpSize -= chunkSize;
                                    tmpAddr = (unsigned char*)tmpAddr + chunkSize;
                                }
#ifdef ALLOCATOR_DEBUG
                                logout("%s %d: Allocator %s stat: %d - free, %d - used, %d - maps!\n", __FUNCTION__, __LINE__, inHandle->name, inHandle->countFree, inHandle->countUsed, inHandle->countAllocated + 1);
#endif
                            }
                            else
                            {
                                logout("%s %d: No memory for object with size %d bytes(limit: %d)\n", __FUNCTION__, __LINE__, chunkSize, tmpSize);
                            }
                        }
                        else
                        {
                            logout("%s %d: Failed mmap %d bytes of memory: %s\n", __FUNCTION__, __LINE__, ALLOCATOR_DEFAULT_SIZE, strerror(errno));
                        }
                    }

                    if(!list_empty(&inHandle->freeList))
                    {
                        allocatorEntry_t *entry = list_entry(inHandle->freeList.next, allocatorEntry_t, list);
                        list_del(&entry->list);
                        inHandle->countFree--;
                        if((entry->magic != ALLOCATOR_ENTRY_MAGIC_VALUE) || (entry->size != chunkSize) || (entry->handle != inHandle))
                        {
                            logout("%s %d: Detect crashed entry %p at %s !!!!\n", __FUNCTION__, __LINE__, entry, inHandle->name);
                        }
                        else
                        {
                            resAddr = (unsigned char*)entry + ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorEntry_t));
                            list_add_tail(&entry->list, &inHandle->usedList);
                            inHandle->countUsed++;
                        }
                    }
                }

                mutex_unlock(&inHandle->mutex);
            }
            else
            {
                logout("%s %d: Failed lock mutex\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s %d: Invalid magic value 0x%X != 0x%X\n", __FUNCTION__, __LINE__, inHandle->magic, ALLOCATOR_MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }

    return resAddr;
}

void allocator_put_object(allocatorHandle_t handle, void *address)
{
#ifdef ALLOCATOR_DEBUG
    struct list_head *iterator;
    int valid;
#endif
    allocatorData_t *inHandle;

    if(handle)
    {
        inHandle = handle;
        if(inHandle->magic == ALLOCATOR_MAGIC_VALUE)
        {
            if(mutex_lock(&inHandle->mutex))
            {
#ifdef ALLOCATOR_DEBUG
                valid = 0;
                if(((unsigned long long)((unsigned char*)inHandle + ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorData_t)) + inHandle->privateSize) <= (unsigned long long)address) && 
                        ((unsigned long long)((unsigned char*)inHandle + ALLOCATOR_DEFAULT_SIZE) > (unsigned long long)address))
                {
                    valid = 1;
                }
                else
                {
                    list_for_each(iterator, &inHandle->allocatedList)
                    {
                        if(((unsigned long long)((unsigned char*)iterator + ALLOCATOR_ALIGNED_SIZE(sizeof(struct list_head))) <= (unsigned long long)address) && 
                            ((unsigned long long)((unsigned char*)iterator + ALLOCATOR_DEFAULT_SIZE) > (unsigned long long)address))
                        {
                            valid = 1;
                        }
                    }
                }

                if(valid)
                {
#endif
                    allocatorEntry_t *entry = (allocatorEntry_t *)((unsigned char*)address - ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorEntry_t)));

                    if((entry->magic == ALLOCATOR_ENTRY_MAGIC_VALUE) && (entry->handle == inHandle) && (entry->size == inHandle->objectSize))
                    {
                        list_del(&entry->list);
                        inHandle->countUsed--;
                        list_add_tail(&entry->list, &inHandle->freeList);
                        inHandle->countFree++;
                    }
                    else
                    {
                        logout("%s %d: Invalid magic value 0x%X != 0x%X at %p !!!!\n", __FUNCTION__, __LINE__, entry->magic, ALLOCATOR_ENTRY_MAGIC_VALUE, entry);
                    }
#ifdef ALLOCATOR_DEBUG
                }
                else
                {
                    logout("%s %d: Invalid address %p at %s\n", __FUNCTION__, __LINE__, address, inHandle->name);
                }
#endif
                mutex_unlock(&inHandle->mutex);
            }
            else
            {
                logout("%s %d: Failed mutex_lock\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s %d: Invalid magic value 0x%X != 0x%X\n", __FUNCTION__, __LINE__, inHandle->magic, ALLOCATOR_MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }
}

void allocator_iterate_used(allocatorHandle_t handle, itfunction function, void *ctx)
{
    struct list_head *iterator;
    allocatorData_t *inHandle;

    if(handle && function)
    {
        inHandle = handle;
        if(inHandle->magic == ALLOCATOR_MAGIC_VALUE)
        {
            if(mutex_lock(&inHandle->mutex))
            {
                if(!list_empty(&inHandle->usedList))
                {
                    list_for_each(iterator, &inHandle->usedList)
                    {
                        allocatorEntry_t *entry = list_entry(iterator, allocatorEntry_t, list);
                        if((entry->magic != ALLOCATOR_ENTRY_MAGIC_VALUE) || (entry->handle != inHandle))
                        {
                            logout("%s %d: Detect crashed entry %p at %s !!!!\n", __FUNCTION__, __LINE__, entry, inHandle->name);
                        }
                        else
                        {
                            void *addr = (unsigned char*)entry + ALLOCATOR_ALIGNED_SIZE(sizeof(allocatorEntry_t));
                            function(ctx, handle, addr);
                        }
                    }
                }
                mutex_unlock(&inHandle->mutex);
            }
            else
            {
                logout("%s %d: Failed mutex_lock\n", __FUNCTION__, __LINE__);
            }
        }
        else
        {
            logout("%s %d: Invalid magic value 0x%X != 0x%X\n", __FUNCTION__, __LINE__, inHandle->magic, ALLOCATOR_MAGIC_VALUE);
        }
    }
    else
    {
        logout("%s %d: Invalid argument\n", __FUNCTION__, __LINE__);
    }
}

