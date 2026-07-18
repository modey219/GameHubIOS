#ifndef _COMPAT_SYS_EPOLL_H
#define _COMPAT_SYS_EPOLL_H
#include <stdint.h>
struct epoll_event {
    uint32_t events;
    union {
        int fd;
        uint32_t u32;
        uint64_t u64;
        void *ptr;
    } data;
};
#define EPOLLIN 0x001
#define EPOLLOUT 0x004
#define EPOLLERR 0x008
#define EPOLLHUP 0x010
#define EPOLLRDHUP 0x2000
#define EPOLLET 0x80000000
#define EPOLLONESHOT 0x40000000
#define EPOLLPRI 0x002
static inline int epoll_create(int s){(void)s;return -1;}
static inline int epoll_create1(int f){(void)f;return -1;}
static inline int epoll_ctl(int e,int o,int f,struct epoll_event *ev){(void)e;(void)o;(void)f;(void)ev;return -1;}
static inline int epoll_wait(int e,struct epoll_event *ev,int m,int t){(void)e;(void)ev;(void)m;(void)t;return -1;}
#endif
