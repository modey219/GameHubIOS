#ifndef _COMPAT_LINUX_SCHED_H
#define _COMPAT_LINUX_SCHED_H
#include <stdint.h>
#define CSIGNAL 0x000000ff
#define CLONE_VM 0x00000100
#define CLONE_FS 0x00000200
#define CLONE_FILES 0x00000400
#define CLONE_SIGHAND 0x00000800
#define CLONE_PTRACE 0x00002000
#define CLONE_VFORK 0x00004000
#define CLONE_PARENT 0x00008000
#define CLONE_THREAD 0x00010000
#define CLONE_NEWNS 0x00020000
#define CLONE_SYSVSEM 0x00040000
#define CLONE_SETTLS 0x00080000
#define CLONE_PARENT_SETTID 0x00100000
#define CLONE_CHILD_CLEARTID 0x00200000
#define CLONE_CHILD_SETTID 0x01000000
struct clone_args { uint64_t flags; uint64_t pidfd; uint64_t child_tid; uint64_t parent_tid; uint64_t exit_signal; uint64_t stack; uint64_t stack_size; uint64_t tls; };
#endif
