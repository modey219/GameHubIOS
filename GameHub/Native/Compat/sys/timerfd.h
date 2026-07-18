#ifndef _COMPAT_SYS_TIMERFD_H
#define _COMPAT_SYS_TIMERFD_H
#include <sys/time.h>
#define TFD_NONBLOCK 0x800
#define TFD_CLOEXEC 0x80000
#define TFD_TIMER_CANCEL_ON_SET 0x0002
static inline int timerfd_create(int c,int f){(void)c;(void)f;return -1;}
static inline int timerfd_settime(int f,int fl,const struct itimerval *n,struct itimerval *o){(void)f;(void)fl;(void)n;(void)o;return -1;}
static inline int timerfd_gettime(int f,struct itimerval *c){(void)f;(void)c;return -1;}
#endif
