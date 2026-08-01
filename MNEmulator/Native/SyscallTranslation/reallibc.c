/*
 * reallibc.c — bypass LiveContainer's broken libc file-I/O interposers.
 *
 * Evidence (build-352): under LiveContainer, open()/stat()/access()/fstat()
 * return garbage (a char* path pointer read as int — fd=1849884092,
 * errno=1769107503) or hang (fstat on the garbage fd -> 20s probe timeout).
 * realpath()/getcwd()/getenv()/setenv() work. This is a signature-mismatched
 * dyld interposer injected into the process.
 *
 * Our binaries live at REAL disk paths (realpath resolves them under
 * /private/var/mobile/...), so we do NOT need LiveContainer's path
 * redirection — we need the genuine libc. These strong symbol definitions
 * bind every reference inside this app image (box64 objects, bridge, runner)
 * to the shims below, which forward to the real libSystem functions resolved
 * once via dlsym(RTLD_NEXT). LiveContainer's dylib loads BEFORE this image,
 * so RTLD_NEXT skips it and returns the true function.
 */

#define _DARWIN_C_SOURCE
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <sys/statvfs.h>
#include <sys/mount.h>

#define SHIM_FN(ret, name, params, args)                                               \
    __attribute__((used)) static __typeof__(&name) real_##name = NULL;                 \
    static __typeof__(&name) resolve_##name(void) {                                    \
        if (!real_##name) real_##name = (__typeof__(&name))dlsym(RTLD_NEXT, #name);    \
        return real_##name;                                                            \
    }                                                                                  \
    ret name params { return resolve_##name() args; }

/* ---- fd-based file I/O ---- */
SHIM_FN(int, close, (int fd), (fd))
SHIM_FN(ssize_t, read, (int fd, void *buf, size_t n), (fd, buf, n))
SHIM_FN(ssize_t, write, (int fd, const void *buf, size_t n), (fd, buf, n))
SHIM_FN(ssize_t, pread, (int fd, void *buf, size_t n, off_t off), (fd, buf, n, off))
SHIM_FN(ssize_t, pwrite, (int fd, const void *buf, size_t n, off_t off), (fd, buf, n, off))
SHIM_FN(off_t, lseek, (int fd, off_t off, int whence), (fd, off, whence))
SHIM_FN(ssize_t, readv, (int fd, const struct iovec *iov, int cnt), (fd, iov, cnt))
SHIM_FN(ssize_t, writev, (int fd, const struct iovec *iov, int cnt), (fd, iov, cnt))
SHIM_FN(int, dup, (int fd), (fd))
SHIM_FN(int, dup2, (int fd, int fd2), (fd, fd2))
SHIM_FN(int, fsync, (int fd), (fd))
SHIM_FN(int, ftruncate, (int fd, off_t len), (fd, len))
SHIM_FN(int, fchmod, (int fd, mode_t mode), (fd, mode))
SHIM_FN(int, fchown, (int fd, uid_t uid, gid_t gid), (fd, uid, gid))
SHIM_FN(int, fstat, (int fd, struct stat *sb), (fd, sb))
SHIM_FN(int, isatty, (int fd), (fd))
SHIM_FN(int, pipe, (int p[2]), (p))

/* ---- path-based I/O ---- */
SHIM_FN(int, stat, (const char *path, struct stat *sb), (path, sb))
SHIM_FN(int, lstat, (const char *path, struct stat *sb), (path, sb))
SHIM_FN(int, access, (const char *path, int mode), (path, mode))
SHIM_FN(int, mkdir, (const char *path, mode_t mode), (path, mode))
SHIM_FN(int, rmdir, (const char *path), (path))
SHIM_FN(int, unlink, (const char *path), (path))
SHIM_FN(int, remove, (const char *path), (path))
SHIM_FN(int, rename, (const char *a, const char *b), (a, b))
SHIM_FN(int, symlink, (const char *a, const char *b), (a, b))
SHIM_FN(ssize_t, readlink, (const char *path, char *buf, size_t n), (path, buf, n))
SHIM_FN(int, link, (const char *a, const char *b), (a, b))
SHIM_FN(int, chmod, (const char *path, mode_t mode), (path, mode))
SHIM_FN(int, chown, (const char *path, uid_t uid, gid_t gid), (path, uid, gid))
SHIM_FN(int, truncate, (const char *path, off_t len), (path, len))
SHIM_FN(int, chdir, (const char *path), (path))
SHIM_FN(int, fchdir, (int fd), (fd))
SHIM_FN(char *, getcwd, (char *buf, size_t n), (buf, n))
SHIM_FN(mode_t, umask, (mode_t mode), (mode))
SHIM_FN(char *, realpath, (const char *path, char *resolved), (path, resolved))
SHIM_FN(int, statfs, (const char *path, struct statfs *sb), (path, sb))
SHIM_FN(int, fstatfs, (int fd, struct statfs *sb), (fd, sb))
SHIM_FN(int, statvfs, (const char *path, struct statvfs *sb), (path, sb))
SHIM_FN(int, fstatvfs, (int fd, struct statvfs *sb), (fd, sb))

/* ---- memory ---- */
SHIM_FN(void *, mmap, (void *addr, size_t len, int prot, int flags, int fd, off_t off),
        (addr, len, prot, flags, fd, off))
SHIM_FN(int, munmap, (void *addr, size_t len), (addr, len))
SHIM_FN(int, mprotect, (void *addr, size_t len, int prot), (addr, len, prot))
SHIM_FN(int, msync, (void *addr, size_t len, int flags), (addr, len, flags))
SHIM_FN(int, madvise, (void *addr, size_t len, int advice), (addr, len, advice))

/* ---- stdio ---- */
SHIM_FN(FILE *, fopen, (const char *path, const char *mode), (path, mode))
SHIM_FN(FILE *, freopen, (const char *path, const char *mode, FILE *f), (path, mode, f))
SHIM_FN(int, fclose, (FILE *f), (f))
SHIM_FN(size_t, fread, (void *buf, size_t sz, size_t cnt, FILE *f), (buf, sz, cnt, f))
SHIM_FN(size_t, fwrite, (const void *buf, size_t sz, size_t cnt, FILE *f), (buf, sz, cnt, f))
SHIM_FN(int, fseek, (FILE *f, long off, int whence), (f, off, whence))
SHIM_FN(int, fseeko, (FILE *f, off_t off, int whence), (f, off, whence))
SHIM_FN(long, ftell, (FILE *f), (f))
SHIM_FN(off_t, ftello, (FILE *f), (f))
SHIM_FN(void, rewind, (FILE *f), (f))
SHIM_FN(int, fflush, (FILE *f), (f))
SHIM_FN(int, fgetc, (FILE *f), (f))
SHIM_FN(char *, fgets, (char *buf, int n, FILE *f), (buf, n, f))
SHIM_FN(int, fputc, (int c, FILE *f), (c, f))
SHIM_FN(int, fputs, (const char *s, FILE *f), (s, f))
SHIM_FN(int, fileno, (FILE *f), (f))
SHIM_FN(int, ferror, (FILE *f), (f))
SHIM_FN(int, feof, (FILE *f), (f))
SHIM_FN(int, ungetc, (int c, FILE *f), (c, f))
SHIM_FN(FILE *, popen, (const char *cmd, const char *mode), (cmd, mode))
SHIM_FN(int, pclose, (FILE *f), (f))
SHIM_FN(ssize_t, getline, (char **lp, size_t *n, FILE *f), (lp, n, f))
SHIM_FN(ssize_t, getdelim, (char **lp, size_t *n, int delim, FILE *f), (lp, n, delim, f))

/* ---- directory ---- */
SHIM_FN(DIR *, opendir, (const char *path), (path))
SHIM_FN(DIR *, fdopendir, (int fd), (fd))
SHIM_FN(struct dirent *, readdir, (DIR *d), (d))
SHIM_FN(int, closedir, (DIR *d), (d))
SHIM_FN(void, rewinddir, (DIR *d), (d))
SHIM_FN(void, seekdir, (DIR *d, long off), (d, off))
SHIM_FN(long, telldir, (DIR *d), (d))

/* ---- variadic: open / openat / fcntl ---- */
static __typeof__(&open) real_open = NULL;
static __typeof__(&open) resolve_open(void) {
    if (!real_open) real_open = (__typeof__(&open))dlsym(RTLD_NEXT, "open");
    return real_open;
}
int open(const char *path, int flags, ...) {
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        return resolve_open()(path, flags, mode);
    }
    return resolve_open()(path, flags, 0);
}

static __typeof__(&openat) real_openat = NULL;
static __typeof__(&openat) resolve_openat(void) {
    if (!real_openat) real_openat = (__typeof__(&openat))dlsym(RTLD_NEXT, "openat");
    return real_openat;
}
int openat(int dirfd, const char *path, int flags, ...) {
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        return resolve_openat()(dirfd, path, flags, mode);
    }
    return resolve_openat()(dirfd, path, flags, 0);
}

static __typeof__(&fcntl) real_fcntl = NULL;
static __typeof__(&fcntl) resolve_fcntl(void) {
    if (!real_fcntl) real_fcntl = (__typeof__(&fcntl))dlsym(RTLD_NEXT, "fcntl");
    return real_fcntl;
}
int fcntl(int fd, int cmd, ...) {
    va_list ap; va_start(ap, cmd);
    void *arg = va_arg(ap, void *);
    va_end(ap);
    return resolve_fcntl()(fd, cmd, arg);
}
