#ifndef _COMPAT_SYS_IPC_H
#define _COMPAT_SYS_IPC_H

#include <sys/types.h>
#include <sys/cdefs.h>

#define IPC_CREAT 0001000
#define IPC_EXCL 0002000
#define IPC_NOWAIT 0004000
#define IPC_RMID 0
#define IPC_SET 1
#define IPC_STAT 2
#define SHM_RDONLY 010000
#define SHM_RND 020000

struct ipc_perm {
    uid_t uid;
    gid_t gid;
    uid_t cuid;
    gid_t cgid;
    mode_t mode;
    unsigned short _seq;
    key_t _key;
};

#endif
