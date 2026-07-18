#ifndef _COMPAT_SYS_SIGNALFD_H
#define _COMPAT_SYS_SIGNALFD_H
#include <signal.h>
#define SFD_NONBLOCK 0x800
#define SFD_CLOEXEC 0x80000
struct signalfd_siginfo { uint32_t ssi_signo; uint32_t ssi_errno; int32_t ssi_code; uint32_t ssi_pid; uint32_t ssi_uid; int32_t ssi_fd; uint32_t ssi_tid; uint32_t ssi_band; uint32_t ssi_overrun; uint32_t _pad[128-5*4]; };
static inline int signalfd(int fd,const sigset_t *m,int f){(void)fd;(void)m;(void)f;return -1;}
#endif
