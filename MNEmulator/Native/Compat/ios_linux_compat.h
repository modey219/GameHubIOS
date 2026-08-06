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
#include <asm/unistd.h>   /* Darwin-mapped __NR_* table (Compat/asm/unistd.h) */

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

/* ======== Dl_info — provided by <dlfcn.h> with _DARWIN_C_SOURCE ======== */
/* No need to define; <dlfcn.h> above already provides it on iOS/macOS */

/* ======== __jmp_buf / __jmp_buf_tag ======== */
/* On macOS/iOS, jmp_buf IS __jmp_buf_tag[1], so __jmp_buf_tag exists
   but may not be forward-declared. Define __jmp_buf as jmp_buf. */
#ifndef __jmp_buf
typedef jmp_buf __jmp_buf;
#endif

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

/* ======== RTLD_DI_LINKMAP (glibc extension, not on macOS) ======== */
#ifndef RTLD_DI_LINKMAP
#define RTLD_DI_LINKMAP 2
#endif

/* ======== dlinfo stub ======== */
static inline int dlinfo(void *handle, int request, void *info) {
    (void)handle; (void)request; (void)info;
    return -1;
}

/* ======== cpu_set_t — defined in sched.h compat, not here ======== */

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

/* ======== sched compat — provided by sched.h compat ======== */
/* sched_getcpu() and cpu_set_t are in sched.h compat */
static inline int sched_yield(void) { return 0; }

/* ======== rawlibc redirect macros ========
   LiveContainer's DYLD_INSERT_LIBRARIES interposer corrupts/hangs the
   legacy libc path functions (open/stat/access/fstat). We redirect every
   libc path/fd call that box64 source makes onto box64_raw_* which invoke
   raw syscalls straight to the kernel (not interceptable by any interposer).
   This header is force-included (-include) into every box64 translation
   unit, so the macros below rewrite box64's calls at compile time. */
#include "../Include/rawlibc.h"

#define open(...)       box64_raw_open(__VA_ARGS__)
#define openat(...)     box64_raw_openat(__VA_ARGS__)
#define close(...)      box64_raw_close(__VA_ARGS__)
#define read(...)       box64_raw_read(__VA_ARGS__)
#define write(...)      box64_raw_write(__VA_ARGS__)
#define pread(...)      box64_raw_pread(__VA_ARGS__)
#define pwrite(...)     box64_raw_pwrite(__VA_ARGS__)
#define lseek(...)      box64_raw_lseek(__VA_ARGS__)
#define stat(...)       box64_raw_stat(__VA_ARGS__)
#define lstat(...)      box64_raw_lstat(__VA_ARGS__)
#define fstat(...)      box64_raw_fstat(__VA_ARGS__)
#define access(...)     box64_raw_access(__VA_ARGS__)
#define faccessat(...)  box64_raw_faccessat(__VA_ARGS__)
#define mkdir(...)      box64_raw_mkdir(__VA_ARGS__)
#define rmdir(...)      box64_raw_rmdir(__VA_ARGS__)
#define unlink(...)     box64_raw_unlink(__VA_ARGS__)
#define rename(...)     box64_raw_rename(__VA_ARGS__)
#define chmod(...)      box64_raw_chmod(__VA_ARGS__)
#define fchmod(...)     box64_raw_fchmod(__VA_ARGS__)
#define chown(...)      box64_raw_chown(__VA_ARGS__)
#define fchown(...)     box64_raw_fchown(__VA_ARGS__)
#define truncate(...)   box64_raw_truncate(__VA_ARGS__)
#define ftruncate(...)  box64_raw_ftruncate(__VA_ARGS__)
#define fsync(...)      box64_raw_fsync(__VA_ARGS__)
#define dup(...)        box64_raw_dup(__VA_ARGS__)
#define dup2(...)       box64_raw_dup2(__VA_ARGS__)
#define chdir(...)      box64_raw_chdir(__VA_ARGS__)
#define fchdir(...)     box64_raw_fchdir(__VA_ARGS__)
#define getcwd(...)     box64_raw_getcwd(__VA_ARGS__)
#define pipe(...)       box64_raw_pipe(__VA_ARGS__)
#define umask(...)      box64_raw_umask(__VA_ARGS__)
#define symlink(...)    box64_raw_symlink(__VA_ARGS__)
#define readlink(...)   box64_raw_readlink(__VA_ARGS__)
#define link(...)       box64_raw_link(__VA_ARGS__)
#define fopen(...)      box64_raw_fopen(__VA_ARGS__)
#define fclose(...)     box64_raw_fclose(__VA_ARGS__)
#define fread(...)      box64_raw_fread(__VA_ARGS__)
#define fwrite(...)     box64_raw_fwrite(__VA_ARGS__)
/* glibc 64-bit-offset aliases — route onto the same raw layer (off_t is
   64-bit on iOS anyway; these must NOT be left as undefined gaps or the ELF
   loader gets a weak empty stub and silently fails to parse wine64) */
#define fseeko64(...)   fseeko(__VA_ARGS__)
#define ftello64(...)   ftello(__VA_ARGS__)
#define fopen64(...)    fopen(__VA_ARGS__)
#define fseek(...)      box64_raw_fseek(__VA_ARGS__)
#define fseeko(...)     box64_raw_fseeko(__VA_ARGS__)
#define ftell(...)      box64_raw_ftell(__VA_ARGS__)
#define ftello(...)     box64_raw_ftello(__VA_ARGS__)
#define rewind(...)     box64_raw_rewind(__VA_ARGS__)
#define fflush(...)     box64_raw_fflush(__VA_ARGS__)
#define fgetc(...)      box64_raw_fgetc(__VA_ARGS__)
#define fgets(...)      box64_raw_fgets(__VA_ARGS__)
#define fputc(...)      box64_raw_fputc(__VA_ARGS__)
#define fputs(...)      box64_raw_fputs(__VA_ARGS__)
#define fileno(...)     box64_raw_fileno(__VA_ARGS__)
#define feof(...)       box64_raw_feof(__VA_ARGS__)
#define ferror(...)     box64_raw_ferror(__VA_ARGS__)
#define ungetc(...)     box64_raw_ungetc(__VA_ARGS__)
#define opendir(...)    box64_raw_opendir(__VA_ARGS__)
#define fdopendir(...)  box64_raw_fdopendir(__VA_ARGS__)
#define readdir(...)    box64_raw_readdir(__VA_ARGS__)
#define closedir(...)   box64_raw_closedir(__VA_ARGS__)
#define rewinddir(...)  box64_raw_rewinddir(__VA_ARGS__)
#define seekdir(...)    box64_raw_seekdir(__VA_ARGS__)
#define telldir(...)    box64_raw_telldir(__VA_ARGS__)

#endif
