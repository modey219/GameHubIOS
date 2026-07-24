#ifndef _COMPAT_LINUX_FUTEX_H
#define _COMPAT_LINUX_FUTEX_H
#include <stdint.h>
#include <sys/time.h>
#define FUTEX_WAIT 0
#define FUTEX_WAKE 1
#define FUTEX_FD 2
#define FUTEX_REQUEUE 3
#define FUTEX_CMP_REQUEUE 4
#define FUTEX_WAKE_OP 5
#define FUTEX_LOCK_PI 6
#define FUTEX_UNLOCK_PI 7
#define FUTEX_TRYLOCK_PI 8
#define FUTEX_WAIT_BITSET 9
#define FUTEX_WAKE_BITSET 10
#define FUTEX_WAIT_PRIVATE 128
#define FUTEX_WAKE_PRIVATE 129
#define FUTEX_REQUEUE_PRIVATE 131
#define FUTEX_CMP_REQUEUE_PRIVATE 132
#define FUTEX_WAKE_OP_PRIVATE 133
#define FUTEX_WAIT_BITSET_PRIVATE 137
#define FUTEX_WAKE_BITSET_PRIVATE 138
struct robust_list { struct robust_list *next; };
static inline int futex(int *u,int o,int v,const struct timespec *t,const unsigned *m,int c){
    (void)u;(void)o;(void)v;(void)t;(void)m;(void)c;return -1;
}
#endif
