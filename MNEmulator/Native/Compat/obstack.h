#ifndef COMPAT_OBSTACK_H
#define COMPAT_OBSTACK_H

#include <stdlib.h>
#include <string.h>

struct obstack {
    char *object_base;
    char *next_free;
    char *chunk_limit;
    size_t chunk_size;
    void *(*chunk_alloc)(size_t);
    void (*chunk_free)(void *);
};

#define obstack_init(h, alloc, free) do { \
    (h)->chunk_size = 4096; \
    (h)->chunk_alloc = (alloc); \
    (h)->chunk_free = (free); \
    (h)->chunk_limit = (h)->next_free = (h)->object_base = NULL; \
} while(0)

#define obstack_object_size(h) ((h)->next_free - (h)->object_base)

#define obstack_grow(h, ptr, len) do { \
    size_t _len = (len); \
    memcpy((h)->next_free, (ptr), _len); \
    (h)->next_free += _len; \
} while(0)

#define obstack_grow0(h, ptr, len) do { \
    size_t _len = (len); \
    memcpy((h)->next_free, (ptr), _len); \
    (h)->next_free += _len; \
    *(h)->next_free++ = 0; \
} while(0)

#define obstack_1grow(h, c) do { *(h)->next_free++ = (c); } while(0)

#define obstack_finish(h) do { \
    size_t _size = (h)->next_free - (h)->object_base; \
    (h)->object_base = realloc((h)->object_base, _size); \
    (h)->next_free = (h)->object_base + _size; \
} while(0)

#define obstack_free(h, obj) do { \
    if (obj) { (h)->chunk_free(obj); } \
} while(0)

#define obstack_alloc(h, size) ({ \
    void *_p = malloc(size); _p; \
})

#define obstack_copy(h, ptr, len) ({ \
    void *_p = malloc(len); \
    if (_p) memcpy(_p, (ptr), (len)); \
    _p; \
})

#define obstack_copy0(h, ptr, len) ({ \
    void *_p = malloc(len + 1); \
    if (_p) { memcpy(_p, (ptr), (len)); ((char*)_p)[len] = 0; } \
    _p; \
})

#endif
