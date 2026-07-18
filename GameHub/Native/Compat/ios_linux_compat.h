#ifndef IOS_LINUX_COMPAT_H
#define IOS_LINUX_COMPAT_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <setjmp.h>

/* __sigset_t — glibc uses this name, iOS uses sigset_t */
typedef sigset_t __sigset_t;

/* __uid_t / __gid_t */
#ifndef __uid_t
typedef uid_t __uid_t;
#endif
#ifndef __gid_t
typedef gid_t __gid_t;
#endif

/* u_char / u_short / u_int / u_long */
#ifndef __u_char_defined
typedef unsigned char u_char;
typedef unsigned short u_short;
typedef unsigned int u_int;
typedef unsigned long u_long;
#define __u_char_defined
#endif

/* MAP_ANONYMOUS / MAP_ANON */
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS 0x1000
#endif
#ifndef MAP_ANON
#define MAP_ANON MAP_ANONYMOUS
#endif

/* CLOCK_MONOTONIC_COARSE */
#ifndef CLOCK_MONOTONIC_COARSE
#define CLOCK_MONOTONIC_COARSE 6
#endif

/* Dl_info struct */
typedef struct {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_sbase;
} Dl_info;

/* timer_t */
typedef void *timer_t;

/* si_call_addr — not in Darwin's siginfo */
#ifndef si_call_addr
#define si_call_addr _si_fields._sigfault._addr
#endif

/* __jmp_buf — glibc name for what iOS/macOS calls jmp_buf */
#ifndef __jmp_buf
typedef jmp_buf __jmp_buf;
#endif

/* sys/sysmacros.h — empty, macros provided elsewhere */
/* sys/vfs.h — redirect to sys/mount.h or provide minimal */
/* linux/auxvec.h — AT_* constants already in elf.h compat */

#endif
