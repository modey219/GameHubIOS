#ifndef _COMPAT_SYS_IPC_H
#define _COMPAT_SYS_IPC_H
#include <sys/types.h>
#define IPC_CREAT 0001000
#define IPC_EXCL 0002000
#define IPC_NOWAIT 0004000
#define IPC_RMID 0
#define IPC_SET 1
#define IPC_STAT 2
#define SHM_RDONLY 010000
#define SHM_RND 020000
#ifndef __key_t_defined
typedef __int32_t key_t;
#define __key_t_defined
#endif
#endif
