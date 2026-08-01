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

#define SHIM_FN(name, params, args)                                                    \
    __attribute__((used)) static __typeof__(&name) real_##name = NULL;                 \
    static __typeof__(&name) resolve_##name(void) {                                    \
        if (!real_##name) real_##name = (__typeof__(&name))dlsym(RTLD_NEXT, #name);    \
        return real_##name;                                                            \
    }                                                                                  \
    __typeof__(&name) name params { return resolve_##name() args; }

/* ---- fd-based file I/O ---- */
SHIM_FN(close, (int fd), (fd))
SHIM_FN(read, (int fd, void *buf, size_t n), (fd, buf, n))
SHIM_FN(write, (int fd, const void *buf, size_t n), (fd, buf, n))
SHIM_FN(pread, (int fd, void *buf, size_t n, off_t off), (fd, buf, n, off))
SHIM_FN(pwrite, (int fd, const void *buf, size_t n, off_t off), (fd, buf, n, off))
SHIM_FN(lseek, (int fd, off_t off, int whence), (fd, off, whence))
SHIM_FN(readv, (int fd, const struct iovec *iov, int cnt), (fd, iov, cnt))
SHIM_FN(writev, (int fd, const struct iovec *iov, int cnt), (fd, iov, cnt))
SHIM_FN(dup, (int fd), (fd))
SHIM_FN(dup2, (int fd, int fd2), (fd, fd2))
SHIM_FN(fsync, (int fd), (fd))
SHIM_FN(ftruncate, (int fd, off_t len), (fd, len))
SHIM_FN(fchmod, (int fd, mode_t mode), (fd, mode))
SHIM_FN(fchown, (int fd, uid_t uid, gid_t gid), (fd, uid, gid))
SHIM_FN(fstat, (int fd, struct stat *sb), (fd, sb))
SHIM_FN(isatty, (int fd), (fd))
SHIM_FN(pipe, (int p[2]), (p))

/* ---- path-based I/O ---- */
SHIM_FN(stat, (const char *path, struct stat *sb), (path, sb))
SHIM_FN(lstat, (const char *path, struct stat *sb), (path, sb))
SHIM_FN(access, (const char *path, int mode), (path, mode))
SHIM_FN(mkdir, (const char *path, mode_t mode), (path, mode))
SHIM_FN(rmdir, (const char *path), (path))
SHIM_FN(unlink, (const char *path), (path))
SHIM_FN(remove, (const char *path), (path))
SHIM_FN(rename, (const char *a, const char *b), (a, b))
SHIM_FN(symlink, (const char *a, const char *b), (a, b))
SHIM_FN(readlink, (const char *path, char *buf, size_t n), (path, buf, n))
SHIM_FN(link, (const char *a, const char *b), (a, b))
SHIM_FN(chmod, (const char *path, mode_t mode), (path, mode))
SHIM_FN(chown, (const char *path, uid_t uid, gid_t gid), (path, uid, gid))
SHIM_FN(truncate, (const char *path, off_t len), (path, len))
SHIM_FN(chdir, (const char *path), (path))
SHIM_FN(fchdir, (int fd), (fd))
SHIM_FN(getcwd, (char *buf, size_t n), (buf, n))
SHIM_FN(umask, (mode_t mode), (mode))
SHIM_FN(realpath, (const char *path, char *resolved), (path, resolved))
SHIM_FN(statfs, (const char *path, struct statfs *sb), (path, sb))
SHIM_FN(fstatfs, (int fd, struct statfs *sb), (fd, sb))
SHIM_FN(statvfs, (const char *path, struct statvfs *sb), (path, sb))
SHIM_FN(fstatvfs, (int fd, struct statvfs *sb), (fd, sb))

/* ---- memory ---- */
SHIM_FN(mmap, (void *addr, size_t len, int prot, int flags, int fd, off_t off),
        (addr, len, prot, flags, fd, off))
SHIM_FN(munmap, (void *addr, size_t len), (addr, len))
SHIM_FN(mprotect, (void *addr, size_t len, int prot), (addr, len, prot))
SHIM_FN(msync, (void *addr, size_t len, int flags), (addr, len, flags))
SHIM_FN(madvise, (void *addr, size_t len, int advice), (addr, len, advice))

/* ---- stdio ---- */
SHIM_FN(fopen, (const char *path, const char *mode), (path, mode))
SHIM_FN(freopen, (const char *path, const char *mode, FILE *f), (path, mode, f))
SHIM_FN(fclose, (FILE *f), (f))
SHIM_FN(fread, (void *buf, size_t sz, size_t cnt, FILE *f), (buf, sz, cnt, f))
SHIM_FN(fwrite, (const void *buf, size_t sz, size_t cnt, FILE *f), (buf, sz, cnt, f))
SHIM_FN(fseek, (FILE *f, long off, int whence), (f, off, whence))
SHIM_FN(fseeko, (FILE *f, off_t off, int whence), (f, off, whence))
SHIM_FN(ftell, (FILE *f), (f))
SHIM_FN(ftello, (FILE *f), (f))
SHIM_FN(rewind, (FILE *f), (f))
SHIM_FN(fflush, (FILE *f), (f))
SHIM_FN(fgetc, (FILE *f), (f))
SHIM_FN(fgets, (char *buf, int n, FILE *f), (buf, n, f))
SHIM_FN(fputc, (int c, FILE *f), (c, f))
SHIM_FN(fputs, (const char *s, FILE *f), (s, f))
SHIM_FN(fileno, (FILE *f), (f))
SHIM_FN(ferror, (FILE *f), (f))
SHIM_FN(feof, (FILE *f), (f))
SHIM_FN(ungetc, (int c, FILE *f), (c, f))
SHIM_FN(popen, (const char *cmd, const char *mode), (cmd, mode))
SHIM_FN(pclose, (FILE *f), (f))
SHIM_FN(getline, (char **lp, size_t *n, FILE *f), (lp, n, f))
SHIM_FN(getdelim, (char **lp, size_t *n, int delim, FILE *f), (lp, n, delim, f))

/* ---- directory ---- */
SHIM_FN(opendir, (const char *path), (path))
SHIM_FN(fdopendir, (int fd), (fd))
SHIM_FN(readdir, (DIR *d), (d))
SHIM_FN(closedir, (DIR *d), (d))
SHIM_FN(rewinddir, (DIR *d), (d))
SHIM_FN(seekdir, (DIR *d, long off), (d, off))
SHIM_FN(telldir, (DIR *d), (d))

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
