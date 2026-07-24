#ifndef COMPAT_LINK_H
#define COMPAT_LINK_H

#include <stdint.h>

struct link_map {
    uintptr_t l_addr;
    char *l_name;
    void *l_ld;
    struct link_map *l_next;
    struct link_map *l_prev;
};

struct r_debug {
    int r_version;
    struct link_map *r_map;
    void (*r_brk)(void);
    int r_state;
    void *r_ldbase;
};

#define RTLD_LAZY      1
#define RTLD_NOW       2
#define RTLD_GLOBAL    256
#define RTLD_LOCAL     0
#define RTLD_NOLOAD    4
#define RTLD_NODELETE  4096
#define RTLD_NEXT      ((void *)-1l)
#define RTLD_DEFAULT   ((void *)-2l)

#define PT_INTERP 3

#endif
