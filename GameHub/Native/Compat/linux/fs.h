#ifndef _COMPAT_LINUX_FS_H
#define _COMPAT_LINUX_FS_H
#include <stdint.h>
#define MS_RDONLY 1
#define MS_NOSUID 2
#define MS_NODEV 4
#define MS_NOEXEC 8
#define MS_SYNCHRONOUS 16
#define MS_MANDLOCK 64
#define MS_DIRSYNC 128
#define MS_NOATIME 1024
#define MS_NODIRATIME 2048
#define MS_BIND 4096
#define MS_MOVE 8192
#define MS_REC 16384
#define MS_VERBOSE 32768
#define MS_SILENT 32768
#define MS_POSIXACL (1<<16)
#define MS_UNBINDABLE (1<<17)
#define MS_PRIVATE (1<<18)
#define MS_SLAVE (1<<19)
#define MS_SHARED (1<<20)
#define MS_RELATIME (1<<21)
#define MS_KERNMOUNT (1<<22)
#define MS_I_VERSION (1<<23)
#define MS_STRICTATIME (1<<24)
#define MS_LAZYTIME (1<<25)
#define FSTYPE_MAX 16
#endif
