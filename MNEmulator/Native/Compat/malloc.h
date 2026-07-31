#ifndef COMPAT_MALLOC_H
#define COMPAT_MALLOC_H
#include <malloc/malloc.h>
#include <stdlib.h>

static inline void *memalign(size_t alignment, size_t size) {
    void *ptr = NULL;
    posix_memalign(&ptr, alignment, size);
    return ptr;
}

#endif
