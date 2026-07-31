#ifndef _COMPAT_SYS_PTRACE_H
#define _COMPAT_SYS_PTRACE_H
#include <sys/types.h>
#define PTRACE_TRACEME 0
#define PTRACE_PEEKTEXT 1
#define PTRACE_PEEKDATA 2
#define PTRACE_PEEKUSER 3
#define PTRACE_POKETEXT 4
#define PTRACE_POKEDATA 5
#define PTRACE_POKEUSER 6
#define PTRACE_CONT 7
#define PTRACE_SINGLESTEP 9
#define PTRACE_SYSCALL 24
#define PTRACE_SETREGS 13
#define PTRACE_GETREGS 12
#define PTRACE_ATTACH 16
#define PTRACE_DETACH 17
struct user_regs_struct { unsigned long long r[18]; };
static inline long ptrace(int r,int p,void *a,void *d){(void)r;(void)p;(void)a;(void)d;return -1;}
#endif
