#ifndef IOS_LINUX_COMPAT_H
#define IOS_LINUX_COMPAT_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include <setjmp.h>
#include <sys/socket.h>
#include <stdio.h>

/* ======== Glibc type aliases ======== */
typedef sigset_t __sigset_t;
typedef uid_t __uid_t;
typedef gid_t __gid_t;
typedef int __pid_t;

typedef unsigned char u_char;
typedef unsigned short u_short;
typedef unsigned int u_int;
typedef unsigned long u_long;

/* timer_t */
typedef void *timer_t;

/* ======== mmap flags ======== */
#ifndef MAP_ANONYMOUS
#define MAP_ANONYMOUS 0x1000
#endif
#ifndef MAP_ANON
#define MAP_ANON MAP_ANONYMOUS
#endif
#ifndef MAP_NORESERVE
#define MAP_NORESERVE 0x0040
#endif
#ifndef MAP_GROWSDOWN
#define MAP_GROWSDOWN 0
#endif
#ifndef MAP_DENYWRITE
#define MAP_DENYWRITE 0
#endif
#ifndef MAP_STACK
#define MAP_STACK 0
#endif

/* ======== Clock constants ======== */
#ifndef CLOCK_MONOTONIC_COARSE
#define CLOCK_MONOTONIC_COARSE 6
#endif

/* ======== Dl_info struct (not on iOS by default) ======== */
#ifndef _DL_INFO_DEFINED
#define _DL_INFO_DEFINED
typedef struct {
    const char *dli_fname;
    void *dli_fbase;
    const char *dli_sname;
    void *dli_sbase;
} Dl_info;
#endif

/* ======== __jmp_buf / __jmp_buf_tag ======== */
/* On macOS/iOS, jmp_buf IS __jmp_buf_tag[1], so __jmp_buf_tag exists
   but may not be forward-declared. Define __jmp_buf as jmp_buf. */
#ifndef __jmp_buf
typedef jmp_buf __jmp_buf;
#endif

/* ======== Linux syscall numbers (stubs for iOS) ======== */
#ifndef __NR_lseek
#define __NR_lseek 8
#endif
#ifndef __NR_gettid
#define __NR_gettid 186
#endif
#ifndef __NR_prctl
#define __NR_prctl 157
#endif

/* ======== Linux-specific struct stubs ======== */
struct mmsghdr {
    struct sockaddr *msg_hdr;
    unsigned int msg_len;
};

/* ======== stat timestamp compat (macOS uses st_atimespec) ======== */
#ifndef st_atim
#define st_atim st_atimespec
#endif
#ifndef st_mtim
#define st_mtim st_mtimespec
#endif
#ifndef st_ctim
#define st_ctim st_ctimespec
#endif

/* ======== epoll compat (minimal) ======== */
/* epoll_event is defined in sys/epoll.h compat — do NOT redefine here */

/* ======== RTLD_NEXT ======== */
#ifndef RTLD_NEXT
#define RTLD_NEXT ((void *)-1)
#endif

/* ======== cpu_set_t — defined in sched.h compat, not here ======== */

/* ======== More Linux syscall numbers ======== */
#ifndef __NR_tgkill
#define __NR_tgkill 131
#endif
#ifndef __NR_futex
#define __NR_futex 202
#endif
#ifndef __NR_set_robust_list
#define __NR_set_robust_list 999
#endif
#ifndef __NR_get_robust_list
#define __NR_get_robust_list 999
#endif
#ifndef __NR_openat
#define __NR_openat 56
#endif
#ifndef __NR_close_range
#define __NR_close_range 999
#endif

/* ======== __jmp_buf_tag ======== */
/* On macOS/iOS, setjmp.h defines jmp_buf but NOT struct __jmp_buf_tag.
   Box64's dynarec expects: struct __jmp_buf_tag { __jmp_buf __jmpbuf; int __mask_was_saved; __sigset_t __saved_mask; } jmp_buf[1];
   We provide a compatible struct and redefine jmp_buf as an array of it. */
#ifndef __JMP_BUF_TAG_DEFINED
#define __JMP_BUF_TAG_DEFINED
struct __jmp_buf_tag {
    jmp_buf __jmpbuf;  /* actual jump buffer */
    int __mask_was_saved;
    __sigset_t __saved_mask;
};
/* On macOS/iOS, jmp_buf is already defined by setjmp.h as an opaque buffer.
   Box64 code declares `struct __jmp_buf_tag varname[1]` expecting it to BE jmp_buf.
   We don't redefine jmp_buf — the struct is enough for sizeof/declarations. */
#endif

/* ======== sched compat ======== */
static inline int sched_getcpu(void) { return 0; }
static inline int sched_yield(void) { return 0; }

#endif
