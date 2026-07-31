#ifndef _COMPAT_SYS_EVENTFD_H
#define _COMPAT_SYS_EVENTFD_H
#include <stdint.h>
#define EFD_SEMAPHORE 0x001
#define EFD_NONBLOCK 0x800
#define EFD_CLOEXEC 0x80000
static inline int eventfd(unsigned int iv,int f){(void)iv;(void)f;return -1;}
#endif
