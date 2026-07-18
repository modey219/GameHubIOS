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
struct epoll_event {
    uint32_t events;
    union {
        int fd;
        uint32_t u32;
        uint64_t u64;
        void *ptr;
    } data;
};

/* ======== Linux-specific mmap mmap flags ======== */
/* These are stubs — Box64 uses them but they don't exist on iOS */

#endif
