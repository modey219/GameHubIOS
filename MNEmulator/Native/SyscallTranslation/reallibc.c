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
#include <sys/syscall.h>
#include "../Include/reallibc.h"

/* REALLIBC_DISABLED removes ALL strong libc definitions from the app image.
   Diagnosing: defining strong _open/_stat/_mmap/_fopen/... in the main
   executable is suspected of crashing dyld at load under LiveContainer's
   DYLD_INSERT_LIBRARIES interposer (instant vanish, zero logs, even the raw
   syscall constructor never runs). Set this to bisect: if the app launches
   with it defined, the strong symbols are the load-time killer. */
#ifndef REALLIBC_DISABLED

/* ---------- raw diagnostic writer (never goes through the shims) ---------- */

static char g_shim_log[1400] = {0};

static void shim_raw_write(int fd, const char *buf, size_t n) {
    if (!buf || !n) return;
    syscall(SYS_write, fd, buf, n);
}

static void shimlog(const char *buf) {
    size_t n = strlen(buf);
    shim_raw_write(2, buf, n);
    if (!g_shim_log[0]) {
        const char *home = getenv("HOME");
        if (home && home[0]) {
            snprintf(g_shim_log, sizeof(g_shim_log), "%s/Documents/shims.log", home);
        } else {
            snprintf(g_shim_log, sizeof(g_shim_log), "/tmp/shims.log");
        }
    }
    int fd = (int)syscall(SYS_open, g_shim_log, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0 && strncmp(g_shim_log, "/tmp/", 5) != 0) {
        snprintf(g_shim_log, sizeof(g_shim_log), "/tmp/shims.log");
        fd = (int)syscall(SYS_open, g_shim_log, O_WRONLY | O_CREAT | O_APPEND, 0644);
    }
    if (fd >= 0) {
        shim_raw_write(fd, buf, n);
        syscall(SYS_close, fd);
    }
}

/* Recorded once at image load: which dylib does dlsym(RTLD_NEXT) give us for
   each shimmed symbol? If we see LiveContainer's own dylib path here, the
   bypass is NOT working and the app will misbehave exactly like the interposer
   era. libSystem paths live in the dyld shared cache. */
static void shim_selftest(void) __attribute__((constructor));
static void shim_selftest(void) {
    const char *names[] = {
        "open", "openat", "fcntl",
        "close", "read", "write", "pread", "pwrite", "lseek", "readv", "writev",
        "dup", "dup2", "fsync", "ftruncate", "fchmod", "fchown", "fstat", "isatty",
        "pipe", "stat", "lstat", "access", "mkdir", "rmdir", "unlink", "remove",
        "rename", "symlink", "readlink", "link", "chmod", "chown", "truncate",
        "chdir", "fchdir", "getcwd", "umask", "realpath",
        "statfs", "fstatfs", "statvfs", "fstatvfs",
        "mmap", "munmap", "mprotect", "msync", "madvise",
        "fopen", "freopen", "fclose", "fread", "fwrite", "fseek", "fseeko", "ftell",
        "ftello", "rewind", "fflush", "fgetc", "fgets", "fputc", "fputs", "fileno",
        "ferror", "feof", "ungetc", "popen", "pclose", "getline", "getdelim",
        "opendir", "fdopendir", "readdir", "closedir", "rewinddir", "seekdir", "telldir"
    };
    const char *home = getenv("HOME");
    char line[512];
    snprintf(line, sizeof(line), "== reallibc selftest (libSystem-handle resolver) HOME=%s ==\n",
             home ? home : "(null)");
    shimlog(line);
    size_t n_names = sizeof(names) / sizeof(names[0]);
    for (size_t i = 0; i < n_names; i++) {
        void *p = reallibc_resolve(names[i]);
        if (!p) {
            void *rn = dlsym(RTLD_NEXT, names[i]);
            snprintf(line, sizeof(line),
                     "  %-12s -> RESOLVE NULL  (RTLD_NEXT gave %p)\n", names[i], rn);
        } else {
            Dl_info info;
            const char *img = "?";
            if (dladdr(p, &info) && info.dli_fname && info.dli_fname[0]) img = info.dli_fname;
            snprintf(line, sizeof(line), "  %-12s -> %p  [%s]\n", names[i], p, img);
        }
        shimlog(line);
    }
    /* end-to-end I/O smoke test using the resolved real libc (open/stat/realpath) */
    if (home && home[0]) {
        char docs[1400];
        snprintf(docs, sizeof(docs), "%s/Documents", home);
        char rp[1400];
        void *real_realpath = reallibc_resolve("realpath");
        void *real_stat = reallibc_resolve("stat");
        void *real_open = reallibc_resolve("open");
        if (real_realpath) {
            char *(*rr)(const char *, char *) = (char *(*)(const char *, char *))real_realpath;
            char *res = rr(docs, rp);
            snprintf(line, sizeof(line), "  realpath(docs)=%s\n", res ? res : "(null)");
            shimlog(line);
        }
        if (real_stat && real_realpath && ((char *(*)(const char *, char *))real_realpath)(docs, rp)) {
            struct stat st;
            int (*rs)(const char *, struct stat *) = (int (*)(const char *, struct stat *))real_stat;
            errno = 0;
            int s = rs(rp, &st);
            snprintf(line, sizeof(line), "  stat(%s)=%d errno=%d mode=%o\n", rp, s, errno,
                     s == 0 ? (int)st.st_mode : 0);
            shimlog(line);
        }
        if (real_open) {
            char probe[1400];
            snprintf(probe, sizeof(probe), "%s/shims_selftest.tmp", home);
            int (*ro)(const char *, int, ...) = (int (*)(const char *, int, ...))real_open;
            int fd = ro(probe, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            snprintf(line, sizeof(line), "  open(%s)=%d errno=%d\n", probe, fd, errno);
            shimlog(line);
            if (fd >= 0) syscall(SYS_close, fd);
        }
    }
    shimlog("== reallibc selftest done ==\n");
}

/* ---------- resolver: real libSystem via explicit handle ---------- */

/*
 * Resolve a libc symbol to the GENUINE libSystem implementation, immune to
 * LiveContainer's interposition. Strategy:
 *   1. dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY) — an explicit image
 *      handle. dlsym(handle, name) searches ONLY that image, so LiveContainer
 *      cannot redirect it regardless of load order.
 *   2. Fallback: dlsym(RTLD_NEXT, name), but only accepted if dladdr() shows
 *      the result lives in libSystem (shared cache). If RTLD_NEXT yields the
 *      interposer, it is rejected.
 */
void *reallibc_resolve(const char *name) {
    if (!name || !name[0]) return NULL;
    static void *g_libSystem = NULL;
    if (!g_libSystem) {
        g_libSystem = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY);
        if (!g_libSystem) g_libSystem = dlopen("/usr/lib/libSystem.dylib", RTLD_LAZY);
    }
    if (g_libSystem) {
        void *p = dlsym(g_libSystem, name);
        if (p) return p;
    }
    void *q = dlsym(RTLD_NEXT, name);
    if (q) {
        Dl_info info;
        if (dladdr(q, &info) && info.dli_fname && info.dli_fname[0]) {
            const char *f = info.dli_fname;
            if (strstr(f, "libSystem") || strstr(f, "libsystem") || strstr(f, "/usr/lib/")) {
                return q;
            }
        }
    }
    return NULL;
}

/* ---------- NULL-safe resolver ---------- */

static void shim_fail_report(const char *name) {
    char line[256];
    int n = snprintf(line, sizeof(line), "[reallibc] reallibc_resolve(\"%s\") == NULL\n", name);
    if (n > 0) shimlog(line);
}

#define SHIM_FN(ret, name, params, args)                                               \
    __attribute__((used)) static __typeof__(&name) real_##name = NULL;                 \
    static __typeof__(&name) resolve_##name(void) {                                    \
        if (!real_##name) {                                                            \
            real_##name = (__typeof__(&name))reallibc_resolve(#name);                  \
            if (!real_##name) shim_fail_report(#name);                                 \
        }                                                                              \
        return real_##name;                                                            \
    }                                                                                  \
    ret name params {                                                                  \
        __typeof__(&name) f_ = resolve_##name();                                       \
        if (!f_) { errno = ENOSYS; return (ret)0; }                                    \
        return f_ args;                                                                \
    }

#define SHIM_VOID(name, params, args)                                                  \
    __attribute__((used)) static __typeof__(&name) real_##name = NULL;                 \
    static __typeof__(&name) resolve_##name(void) {                                    \
        if (!real_##name) {                                                            \
            real_##name = (__typeof__(&name))reallibc_resolve(#name);                  \
            if (!real_##name) shim_fail_report(#name);                                 \
        }                                                                              \
        return real_##name;                                                            \
    }                                                                                  \
    void name params {                                                                 \
        __typeof__(&name) f_ = resolve_##name();                                       \
        if (f_) { f_ args; }                                                           \
    }

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
SHIM_VOID(rewind, (FILE *f), (f))
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
SHIM_VOID(rewinddir, (DIR *d), (d))
SHIM_VOID(seekdir, (DIR *d, long off), (d, off))
SHIM_FN(long, telldir, (DIR *d), (d))

/* ---- variadic: open / openat / fcntl ---- */
static __typeof__(&open) real_open = NULL;
static __typeof__(&open) resolve_open(void) {
    if (!real_open) real_open = (__typeof__(&open))reallibc_resolve("open");
    return real_open;
}
int open(const char *path, int flags, ...) {
    __typeof__(&open) f_ = resolve_open();
    if (!f_) { errno = ENOSYS; return -1; }
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        return f_(path, flags, mode);
    }
    return f_(path, flags, 0);
}

static __typeof__(&openat) real_openat = NULL;
static __typeof__(&openat) resolve_openat(void) {
    if (!real_openat) real_openat = (__typeof__(&openat))reallibc_resolve("openat");
    return real_openat;
}
int openat(int dirfd, const char *path, int flags, ...) {
    __typeof__(&openat) f_ = resolve_openat();
    if (!f_) { errno = ENOSYS; return -1; }
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags);
        mode_t mode = (mode_t)va_arg(ap, int);
        va_end(ap);
        return f_(dirfd, path, flags, mode);
    }
    return f_(dirfd, path, flags, 0);
}

static __typeof__(&fcntl) real_fcntl = NULL;
static __typeof__(&fcntl) resolve_fcntl(void) {
    if (!real_fcntl) real_fcntl = (__typeof__(&fcntl))reallibc_resolve("fcntl");
    return real_fcntl;
}
int fcntl(int fd, int cmd, ...) {
    __typeof__(&fcntl) f_ = resolve_fcntl();
    if (!f_) { errno = ENOSYS; return -1; }
    va_list ap; va_start(ap, cmd);
    void *arg = va_arg(ap, void *);
    va_end(ap);
    return f_(fd, cmd, arg);
}

#else /* REALLIBC_DISABLED */

/* Keep the shared resolver symbol so box64_bridge.c / box64_runner.c link.
   Returns NULL: the async-signal crash handlers already fall back to raw
   syscalls when the real-libc captures are NULL. */
void *reallibc_resolve(const char *name) {
    (void)name;
    return NULL;
}

#endif /* REALLIBC_DISABLED */
