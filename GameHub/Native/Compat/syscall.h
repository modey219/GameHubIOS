#ifndef COMPAT_SYSCALL_H
#define COMPAT_SYSCALL_H

#include <stdint.h>
#include <unistd.h>

#define SYS_read        0
#define SYS_write       1
#define SYS_open        2
#define SYS_close       3
#define SYS_stat        4
#define SYS_fstat       5
#define SYS_lstat       6
#define SYS_lseek       8
#define SYS_mmap        9
#define SYS_mprotect    10
#define SYS_munmap      11
#define SYS_brk         12
#define SYS_ioctl       16
#define SYS_access      21
#define SYS_pipe        22
#define SYS_dup2        33
#define SYS_nanosleep   35
#define SYS_getpid      39
#define SYS_fork        57
#define SYS_execve      59
#define SYS_exit        60
#define SYS_wait4       61
#define SYS_kill        62
#define SYS_uname       63
#define SYS_fcntl       72
#define SYS_getcwd      79
#define SYS_mkdir       83
#define SYS_unlink      87
#define SYS_readlink    89
#define SYS_gettimeofday 96
#define SYS_getuid      102
#define SYS_getgid      104
#define SYS_geteuid     107
#define SYS_getegid     109
#define SYS_sigprocmask 14
#define SYS_rt_sigaction 13
#define SYS_rt_sigprocmask 14
#define SYS_clone       56
#define SYS_futex       202
#define SYS_set_tid_address 218
#define SYS_exit_group  231
#define SYS_openat      257
#define SYS_mkdirat     258
#define SYS_newfstatat  262
#define SYS_unlinkat    263
#define SYS_readlinkat  267

#ifndef _COMPAT_SYSCALL_FUNC
#define _COMPAT_SYSCALL_FUNC
/* syscall() is provided by <unistd.h> on macOS/iOS with _DARWIN_C_SOURCE.
   Only define if not already declared. */
#endif

#endif
