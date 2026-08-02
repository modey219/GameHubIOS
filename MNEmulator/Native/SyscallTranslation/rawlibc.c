/*
 * rawlibc.c — direct-kernel libc replacement layer for box64 (iOS).
 *
 * Every function here goes through raw syscall() invocations straight to
 * the kernel, bypassing any DYLD_INSERT_LIBRARIES interposer (LiveContainer)
 * that corrupts or hangs the legacy libc path functions.
 *
 * ABI note: box64 is compiled with iOS system headers (force-included via
 * ios_linux_compat.h), so `struct stat` here is the iOS layout the kernel
 * fills in for SYS_stat64/SYS_fstat64. Field access from box64 matches.
 */
#define _DARWIN_C_SOURCE 1

#include "../Include/rawlibc.h"

#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dirent.h>
#include <sys/syscall.h>
#include <sys/dirent.h>
#include <sys/uio.h>
#include <stdarg.h>

#define RAW_DIRBUF_BLKSIZ 8192

/* ================================================================== */
/*  raw syscall() shim                                                 */
/* ================================================================== */

/* NOTE: resolving the genuine libSystem syscall() via dlopen+dlsym was
   tried and ABANDONED — dlopen("/usr/lib/libSystem.B.dylib") HANGS at
   runtime under LiveContainer (both at image-load time in some builds and
   lazily on first use).

   build-372 then proved the plain libc `syscall` SYMBOL is itself interposed
   by LiveContainer for path-opening syscalls: `syscall(SYS_openat, ...)`
   HANGS while `syscall(SYS___getcwd, ...)` passes through. So even a
   syscall-number-based call to the `syscall` symbol cannot be trusted.

   box64_raw_syscall therefore issues a DIRECT kernel trap via inline
   `svc 0x80` (arm64) — no DYLD interposer can hook a raw trap. The
   varargs wrapper below supplies this, and rawlibc_syscall is kept as a
   thin 5-arg wrapper so every box64_raw_* path funnels through the trap. */

#if defined(__aarch64__)

static inline long raw_kernel_syscall(long num, long a1, long a2, long a3,
                                      long a4, long a5, long a6) {
    long result;
    __asm__ __volatile__(
        "mov x16, %[num]\n"
        "mov x0, %[a1]\n"
        "mov x1, %[a2]\n"
        "mov x2, %[a3]\n"
        "mov x3, %[a4]\n"
        "mov x4, %[a5]\n"
        "mov x5, %[a6]\n"
        "svc 0x80\n"
        "b.cc 1f\n"
        "neg x0, x0\n"
        "1:\n"
        "mov %[res], x0\n"
        : [res] "=r"(result)
        : [num] "r"(num), [a1] "r"(a1), [a2] "r"(a2), [a3] "r"(a3),
          [a4] "r"(a4), [a5] "r"(a5), [a6] "r"(a6)
        : "x0", "x1", "x2", "x3", "x4", "x5", "x16", "cc", "memory");
    return result;
}

#else

static inline long raw_kernel_syscall(long num, long a1, long a2, long a3,
                                      long a4, long a5, long a6) {
    (void)num; (void)a1; (void)a2; (void)a3; (void)a4; (void)a5; (void)a6;
    errno = ENOSYS;
    return -1;
}

#endif

long box64_raw_syscall(int num, ...) {
    long a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0;
    va_list ap;
    va_start(ap, num);
    a1 = va_arg(ap, long);
    a2 = va_arg(ap, long);
    a3 = va_arg(ap, long);
    a4 = va_arg(ap, long);
    a5 = va_arg(ap, long);
    a6 = va_arg(ap, long);
    va_end(ap);

    /* Darwin arm64 encodes the syscall CLASS in bits 31:28 of x16 (the arm64
       exception vector dispatches on it). Apple libsyscall and Go's
       darwin/arm64 stubs issue `mov x16, #SYSCALL_CONSTRUCT_UNIX(n); svc 0x80`
       where SYSCALL_CONSTRUCT_UNIX(n) = (n | 0x2000000). A bare number with no
       class bits is decoded under the MACH class on arm64, so e.g. raw 5
       (getpid) aliases a blocking mach trap and HANGS (build-374 probe died on
       exactly that trial). Always OR in the unix class bits; the raw-number
       form remains available as box64_raw_syscall_raw for the bridge probe's
       A/B comparison. */
    long r = raw_kernel_syscall((long)num | 0x2000000L, a1, a2, a3, a4, a5, a6);
    if (r < 0) {
        errno = (int)(-r);
        return -1;
    }
    return r;
}

/* Raw-number variant: no class bits. Build-374's sanity trial proved a bare
   raw `svc 0x80` HANGS on this device (mach-class decode of the low bits);
   retained only so the bridge probe can confirm the encoding difference. */
long box64_raw_syscall_raw(int num, ...) {
    long a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0;
    va_list ap;
    va_start(ap, num);
    a1 = va_arg(ap, long);
    a2 = va_arg(ap, long);
    a3 = va_arg(ap, long);
    a4 = va_arg(ap, long);
    a5 = va_arg(ap, long);
    a6 = va_arg(ap, long);
    va_end(ap);

    long r = raw_kernel_syscall((long)num, a1, a2, a3, a4, a5, a6);
    if (r < 0) {
        errno = (int)(-r);
        return -1;
    }
    return r;
}

/* Class-encoded variant: identical to box64_raw_syscall, which now defaults
   to the SYSCALL_CONSTRUCT_UNIX class encoding. Kept as an alias so bridge
   call sites that name the encoding explicitly stay correct. */
long box64_raw_syscall_cls(int num, ...) {
    long a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0;
    va_list ap;
    va_start(ap, num);
    a1 = va_arg(ap, long);
    a2 = va_arg(ap, long);
    a3 = va_arg(ap, long);
    a4 = va_arg(ap, long);
    a5 = va_arg(ap, long);
    a6 = va_arg(ap, long);
    va_end(ap);
    return box64_raw_syscall(num, a1, a2, a3, a4, a5, a6);
}

static long rawlibc_syscall(int num, ...) {
    long a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0;
    va_list ap;
    va_start(ap, num);
    a1 = va_arg(ap, long);
    a2 = va_arg(ap, long);
    a3 = va_arg(ap, long);
    a4 = va_arg(ap, long);
    a5 = va_arg(ap, long);
    va_end(ap);
    return box64_raw_syscall(num, a1, a2, a3, a4, a5);
}

/* ================================================================== */
/*  fd / path syscalls                                                 */
/* ================================================================== */

int box64_raw_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
#ifdef SYS_openat
    /* Legacy SYS_open can hang under LiveContainer; openat is what libc's
       open() itself uses internally and is proven reachable. */
    return (int)rawlibc_syscall(SYS_openat, AT_FDCWD, path, flags, mode);
#else
    return (int)rawlibc_syscall(SYS_open, path, flags, mode);
#endif
}

int box64_raw_openat(int dirfd, const char *path, int flags, ...) {
    mode_t mode = 0;
    if (flags & O_CREAT) {
        va_list ap;
        va_start(ap, flags);
        mode = (mode_t)va_arg(ap, int);
        va_end(ap);
    }
#ifdef SYS_openat
    return (int)rawlibc_syscall(SYS_openat, dirfd, path, flags, mode);
#else
    if (dirfd == AT_FDCWD)
        return (int)rawlibc_syscall(SYS_open, path, flags, mode);
    errno = ENOSYS;
    return -1;
#endif
}

int box64_raw_close(int fd) {
    return (int)rawlibc_syscall(SYS_close, fd);
}

ssize_t box64_raw_read(int fd, void *buf, size_t n) {
    return (ssize_t)rawlibc_syscall(SYS_read, fd, buf, n);
}

ssize_t box64_raw_write(int fd, const void *buf, size_t n) {
    return (ssize_t)rawlibc_syscall(SYS_write, fd, buf, n);
}

ssize_t box64_raw_pread(int fd, void *buf, size_t n, off_t off) {
#ifdef SYS_pread
    return (ssize_t)rawlibc_syscall(SYS_pread, fd, buf, n, off);
#else
    (void)fd; (void)buf; (void)n; (void)off;
    errno = ENOSYS;
    return -1;
#endif
}

ssize_t box64_raw_pwrite(int fd, const void *buf, size_t n, off_t off) {
#ifdef SYS_pwrite
    return (ssize_t)rawlibc_syscall(SYS_pwrite, fd, buf, n, off);
#else
    (void)fd; (void)buf; (void)n; (void)off;
    errno = ENOSYS;
    return -1;
#endif
}

off_t box64_raw_lseek(int fd, off_t off, int whence) {
    return (off_t)rawlibc_syscall(SYS_lseek, fd, off, whence);
}

int box64_raw_stat(const char *path, struct stat *sb) {
#ifdef SYS_stat64
    return (int)rawlibc_syscall(SYS_stat64, path, sb);
#else
    return (int)rawlibc_syscall(SYS_stat, path, sb);
#endif
}

int box64_raw_lstat(const char *path, struct stat *sb) {
#ifdef SYS_lstat64
    return (int)rawlibc_syscall(SYS_lstat64, path, sb);
#else
    return (int)rawlibc_syscall(SYS_lstat, path, sb);
#endif
}

int box64_raw_fstat(int fd, struct stat *sb) {
#ifdef SYS_fstat64
    return (int)rawlibc_syscall(SYS_fstat64, fd, sb);
#else
    return (int)rawlibc_syscall(SYS_fstat, fd, sb);
#endif
}

int box64_raw_access(const char *path, int mode) {
    return (int)rawlibc_syscall(SYS_access, path, mode);
}

int box64_raw_faccessat(int dirfd, const char *path, int mode, int flags) {
#ifdef SYS_faccessat
    return (int)rawlibc_syscall(SYS_faccessat, dirfd, path, mode, flags);
#else
    (void)flags;
    if (dirfd == AT_FDCWD)
        return (int)rawlibc_syscall(SYS_access, path, mode);
    errno = ENOSYS;
    return -1;
#endif
}

int box64_raw_mkdir(const char *path, mode_t mode) {
    return (int)rawlibc_syscall(SYS_mkdir, path, mode);
}

int box64_raw_rmdir(const char *path) {
    return (int)rawlibc_syscall(SYS_rmdir, path);
}

int box64_raw_unlink(const char *path) {
    return (int)rawlibc_syscall(SYS_unlink, path);
}

int box64_raw_rename(const char *a, const char *b) {
    return (int)rawlibc_syscall(SYS_rename, a, b);
}

int box64_raw_chmod(const char *path, mode_t mode) {
    return (int)rawlibc_syscall(SYS_chmod, path, mode);
}

int box64_raw_fchmod(int fd, mode_t mode) {
    return (int)rawlibc_syscall(SYS_fchmod, fd, mode);
}

int box64_raw_chown(const char *path, uid_t uid, gid_t gid) {
    return (int)rawlibc_syscall(SYS_chown, path, uid, gid);
}

int box64_raw_fchown(int fd, uid_t uid, gid_t gid) {
    return (int)rawlibc_syscall(SYS_fchown, fd, uid, gid);
}

int box64_raw_truncate(const char *path, off_t len) {
#ifdef SYS_truncate
    return (int)rawlibc_syscall(SYS_truncate, path, len);
#else
    (void)path; (void)len;
    errno = ENOSYS;
    return -1;
#endif
}

int box64_raw_ftruncate(int fd, off_t len) {
#ifdef SYS_ftruncate
    return (int)rawlibc_syscall(SYS_ftruncate, fd, len);
#else
    (void)fd; (void)len;
    errno = ENOSYS;
    return -1;
#endif
}

int box64_raw_fsync(int fd) {
    return (int)rawlibc_syscall(SYS_fsync, fd);
}

int box64_raw_dup(int fd) {
    return (int)rawlibc_syscall(SYS_dup, fd);
}

int box64_raw_dup2(int fd, int fd2) {
    return (int)rawlibc_syscall(SYS_dup2, fd, fd2);
}

int box64_raw_chdir(const char *path) {
    return (int)rawlibc_syscall(SYS_chdir, path);
}

int box64_raw_fchdir(int fd) {
    return (int)rawlibc_syscall(SYS_fchdir, fd);
}

char *box64_raw_getcwd(char *buf, size_t n) {
#if defined(SYS___getcwd) || defined(SYS_getcwd)
    long r;
#ifdef SYS___getcwd
    r = rawlibc_syscall(SYS___getcwd, buf, n);
#else
    r = rawlibc_syscall(SYS_getcwd, buf, n);
#endif
    if (r < 0)
        return NULL;
    return buf;
#else
    /* No getcwd syscall number exposed on this platform. libc getcwd is
       proven to work under LiveContainer (see probe traces). */
    return getcwd(buf, n);
#endif
}

int box64_raw_pipe(int fds[2]) {
#ifdef SYS_pipe
    return (int)rawlibc_syscall(SYS_pipe, fds);
#else
    (void)fds;
    errno = ENOSYS;
    return -1;
#endif
}

mode_t box64_raw_umask(mode_t mask) {
    return (mode_t)rawlibc_syscall(SYS_umask, mask);
}

int box64_raw_symlink(const char *a, const char *b) {
    return (int)rawlibc_syscall(SYS_symlink, a, b);
}

ssize_t box64_raw_readlink(const char *path, char *buf, size_t n) {
    return (ssize_t)rawlibc_syscall(SYS_readlink, path, buf, n);
}

int box64_raw_link(const char *a, const char *b) {
    return (int)rawlibc_syscall(SYS_link, a, b);
}

/* ================================================================== */
/*  stdio over raw fds                                                 */
/* ================================================================== */

/* We reuse libc's FILE plumbing but feed it raw syscalls for the fd level.
 * FILE itself is not intercepted by LiveContainer's path interposers. */
FILE *box64_raw_fopen(const char *path, const char *mode) {
    int flags = O_RDONLY;
    if (strcmp(mode, "w") == 0) flags = O_WRONLY | O_CREAT | O_TRUNC;
    else if (strcmp(mode, "w+") == 0) flags = O_RDWR | O_CREAT | O_TRUNC;
    else if (strcmp(mode, "a") == 0) flags = O_WRONLY | O_CREAT | O_APPEND;
    else if (strcmp(mode, "a+") == 0) flags = O_RDWR | O_CREAT | O_APPEND;
    else if (strcmp(mode, "r+") == 0) flags = O_RDWR;
    else if (strncmp(mode, "rb", 2) == 0) flags = O_RDONLY;
    else if (strncmp(mode, "wb", 2) == 0) flags = O_WRONLY | O_CREAT | O_TRUNC;
    else if (strncmp(mode, "ab", 2) == 0) flags = O_WRONLY | O_CREAT | O_APPEND;
    else if (strncmp(mode, "r+b", 3) == 0 || strcmp(mode, "rb+") == 0) flags = O_RDWR;
    else if (strncmp(mode, "w+b", 3) == 0 || strcmp(mode, "wb+") == 0) flags = O_RDWR | O_CREAT | O_TRUNC;
    else if (strncmp(mode, "a+b", 3) == 0 || strcmp(mode, "ab+") == 0) flags = O_RDWR | O_CREAT | O_APPEND;
    int fd = box64_raw_open(path, flags, 0666);
    if (fd < 0)
        return NULL;
    FILE *f = fdopen(fd, mode);
    if (!f) {
        box64_raw_close(fd);
        return NULL;
    }
    return f;
}

int box64_raw_fclose(FILE *f) {
    return fclose(f);
}

size_t box64_raw_fread(void *buf, size_t sz, size_t cnt, FILE *f) {
    return fread(buf, sz, cnt, f);
}

size_t box64_raw_fwrite(const void *buf, size_t sz, size_t cnt, FILE *f) {
    return fwrite(buf, sz, cnt, f);
}

int box64_raw_fseek(FILE *f, long off, int whence) {
    return fseek(f, off, whence);
}

int box64_raw_fseeko(FILE *f, off_t off, int whence) {
    return fseeko(f, off, whence);
}

long box64_raw_ftell(FILE *f) {
    return ftell(f);
}

off_t box64_raw_ftello(FILE *f) {
    return ftello(f);
}

void box64_raw_rewind(FILE *f) {
    rewind(f);
}

int box64_raw_fflush(FILE *f) {
    return fflush(f);
}

int box64_raw_fgetc(FILE *f) {
    return fgetc(f);
}

char *box64_raw_fgets(char *buf, int n, FILE *f) {
    return fgets(buf, n, f);
}

int box64_raw_fputc(int c, FILE *f) {
    return fputc(c, f);
}

int box64_raw_fputs(const char *s, FILE *f) {
    return fputs(s, f);
}

int box64_raw_fileno(FILE *f) {
    return fileno(f);
}

int box64_raw_feof(FILE *f) {
    return feof(f);
}

int box64_raw_ferror(FILE *f) {
    return ferror(f);
}

int box64_raw_ungetc(int c, FILE *f) {
    return ungetc(c, f);
}

/* ================================================================== */
/*  directory over raw fds                                             */
/* ================================================================== */

struct _RawDir {
    int fd;
    struct stat st;
    char buf[RAW_DIRBUF_BLKSIZ];
    size_t pos;
    size_t total;
    struct dirent *ent;
    int err;
};

static int raw_getdirentries(int fd, char *buf, size_t n, off_t *basep) {
#if defined(SYS_getdirentries64)
    long r = rawlibc_syscall(SYS_getdirentries64, fd, buf, n, basep);
    return (int)r;
#elif defined(SYS_getdirentries)
    return (int)rawlibc_syscall(SYS_getdirentries, fd, buf, n, basep);
#else
    (void)fd; (void)buf; (void)n; (void)basep;
    errno = ENOSYS;
    return -1;
#endif
}

DIR *box64_raw_opendir(const char *path) {
    int fd = box64_raw_open(path, O_RDONLY | O_DIRECTORY);
    if (fd < 0)
        return NULL;
    return box64_raw_fdopendir(fd);
}

DIR *box64_raw_fdopendir(int fd) {
    struct stat sb;
    if (box64_raw_fstat(fd, &sb) != 0) {
        box64_raw_close(fd);
        return NULL;
    }
    struct _RawDir *d = calloc(1, sizeof(struct _RawDir));
    if (!d) {
        box64_raw_close(fd);
        return NULL;
    }
    d->fd = fd;
    return (DIR *)d;
}

static int raw_fill(struct _RawDir *d) {
    off_t base = 0;
    d->pos = 0;
    d->total = 0;
    int n = raw_getdirentries(d->fd, d->buf, sizeof(d->buf), &base);
    if (n < 0) {
        d->err = errno;
        return -1;
    }
    d->total = (size_t)n;
    return n;
}

struct dirent *box64_raw_readdir(DIR *dir) {
    struct _RawDir *d = (struct _RawDir *)dir;
    if (!d)
        return NULL;
    for (;;) {
        if (d->pos >= d->total) {
            if (raw_fill(d) <= 0)
                return NULL;
        }
        d->ent = (struct dirent *)(d->buf + d->pos);
        d->pos += d->ent->d_reclen;
        /* skip "." and ".." */
        if (d->ent->d_name[0] == '.' &&
            (d->ent->d_name[1] == '\0' ||
             (d->ent->d_name[1] == '.' && d->ent->d_name[2] == '\0')))
            continue;
        return d->ent;
    }
}

int box64_raw_closedir(DIR *dir) {
    struct _RawDir *d = (struct _RawDir *)dir;
    if (!d)
        return EBADF;
    int fd = d->fd;
    free(d);
    return box64_raw_close(fd);
}

void box64_raw_rewinddir(DIR *dir) {
    struct _RawDir *d = (struct _RawDir *)dir;
    if (!d)
        return;
    box64_raw_lseek(d->fd, 0, SEEK_SET);
    d->pos = 0;
    d->total = 0;
    d->err = 0;
}

void box64_raw_seekdir(DIR *dir, long off) {
    box64_raw_lseek(((struct _RawDir *)dir)->fd, (off_t)off, SEEK_SET);
    ((struct _RawDir *)dir)->pos = 0;
    ((struct _RawDir *)dir)->total = 0;
}

long box64_raw_telldir(DIR *dir) {
    return (long)box64_raw_lseek(((struct _RawDir *)dir)->fd, 0, SEEK_CUR);
}

/* ================================================================== */
/*  REAL-libc probe shims (build-376)                                  */
/* ================================================================== */
/*  rawlibc.c is compiled WITHOUT the ios_linux_compat.h redirect macros,
    so every symbol referenced below is the genuine libc entry point —
    exactly the ones LiveContainer interposes. The bridge probe calls these
    to establish a "plain libc" baseline on-device: once the redirect macros
    are gone, does real libc open/stat/fopen actually work? Which call hangs?
    (Every other box64 source has open/stat/read/... macro-redirected onto
    the box64_raw_* traps, so there is currently ZERO real-libc file-op data.) */

int box64_libc_open(const char *path) {
    return open(path, O_RDONLY);
}

int box64_libc_stat(const char *path, struct stat *sb) {
    return stat(path, sb);
}

int box64_libc_fstat(int fd, struct stat *sb) {
    return fstat(fd, sb);
}

ssize_t box64_libc_read(int fd, void *buf, size_t n) {
    return read(fd, buf, n);
}

FILE *box64_libc_fopen(const char *path, const char *mode) {
    return fopen(path, mode);
}

int box64_libc_mkdir(const char *path) {
    return mkdir(path, 0755);
}

/* Interposed `syscall` symbol — build-372 proved syscall(SYS_openat, ...)
   HANGS under LiveContainer while syscall(SYS___getcwd) passes through. */
int box64_libc_syscall_openat(const char *path, int flags) {
    return (int)syscall(SYS_openat, AT_FDCWD, path, flags, 0L);
}

int box64_libc_syscall_getpid(void) {
    return (int)syscall(SYS_getpid);
}
