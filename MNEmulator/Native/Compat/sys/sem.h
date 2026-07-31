#ifndef _COMPAT_SYS_SEM_H
#define _COMPAT_SYS_SEM_H
#include <sys/types.h>
struct semid_ds { void *sem_base; unsigned short sem_nsems; time_t sem_otime; time_t sem_ctime; };
struct sembuf { unsigned short sem_num; short sem_op; short sem_flg; };
union semun { int val; struct semid_ds *buf; unsigned short *array; };
#define SETVAL 16
#define IPC_STAT 2
#define SEM_STAT 18
static inline int semget(key_t k,int n,int f){(void)k;(void)n;(void)f;return -1;}
static inline int semop(int s,struct sembuf *o,size_t n){(void)s;(void)o;(void)n;return -1;}
static inline int semctl(int s,int n,int c,...){(void)s;(void)n;(void)c;return -1;}
#endif
