#ifndef _COMPAT_SYS_RANDOM_H
#define _COMPAT_SYS_RANDOM_H
#include <stddef.h>
#include <sys/types.h>
#define GRND_NONBLOCK 0x0001
#define GRND_RANDOM 0x0002
static inline ssize_t getrandom(void *buf,size_t n,unsigned int f){(void)buf;(void)n;(void)f;return -1;}
#endif
