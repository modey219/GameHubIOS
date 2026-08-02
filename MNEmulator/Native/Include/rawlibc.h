/*
 * rawlibc.h — direct-kernel libc replacement layer for box64.
 *
 * LiveContainer's DYLD_INSERT_LIBRARIES interposer breaks the legacy libc
 * path functions (open() returns a truncated pointer as an int, stat()/
 * access() hang, fstat() returns garbage). These box64_raw_* functions use
 * raw syscall() invocations that go straight to the kernel, so symbol
 * interposition cannot touch them.
 *
 * box64's source is redirected onto these via function-like macros in
 * ios_linux_compat.h (force-included into every box64 translation unit).
 */
#ifndef RAWLIBc_H
#define RAWLIBc_H

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <stdio.h>
#include <dirent.h>
#include <stddef.h>
#include <stdarg.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- direct kernel syscall (inline svc, bypasses DYLD interposers) ---- */
long box64_raw_syscall(int num, ...);

/* Class-encoded variant: ORs SYSCALL_CONSTRUCT_UNIX (2<<24 = 0x2000000) into
   the number before trapping. arm64 dispatches the syscall CLASS from bits
   31:28 of x16 (Apple libsyscall / Go darwin/arm64 stubs use this encoding);
   a bare number is decoded under the MACH class and can HANG. box64_raw_syscall
   now defaults to this encoding. */
long box64_raw_syscall_cls(int num, ...);

/* Raw-number variant: no class bits. Build-374's sanity trial proved a bare
   raw number HANGS at the trap on this device; kept only for the bridge
   probe's A/B comparison. */
long box64_raw_syscall_raw(int num, ...);

/* ---- fd/path syscalls ---- */
int box64_raw_open(const char *path, int flags, ...);
int box64_raw_openat(int dirfd, const char *path, int flags, ...);
int box64_raw_close(int fd);
ssize_t box64_raw_read(int fd, void *buf, size_t n);
ssize_t box64_raw_write(int fd, const void *buf, size_t n);
ssize_t box64_raw_pread(int fd, void *buf, size_t n, off_t off);
ssize_t box64_raw_pwrite(int fd, const void *buf, size_t n, off_t off);
off_t box64_raw_lseek(int fd, off_t off, int whence);
int box64_raw_stat(const char *path, struct stat *sb);
int box64_raw_lstat(const char *path, struct stat *sb);
int box64_raw_fstat(int fd, struct stat *sb);
int box64_raw_access(const char *path, int mode);
int box64_raw_faccessat(int dirfd, const char *path, int mode, int flags);
int box64_raw_mkdir(const char *path, mode_t mode);
int box64_raw_rmdir(const char *path);
int box64_raw_unlink(const char *path);
int box64_raw_rename(const char *a, const char *b);
int box64_raw_chmod(const char *path, mode_t mode);
int box64_raw_fchmod(int fd, mode_t mode);
int box64_raw_chown(const char *path, uid_t uid, gid_t gid);
int box64_raw_fchown(int fd, uid_t uid, gid_t gid);
int box64_raw_truncate(const char *path, off_t len);
int box64_raw_ftruncate(int fd, off_t len);
int box64_raw_fsync(int fd);
int box64_raw_dup(int fd);
int box64_raw_dup2(int fd, int fd2);
int box64_raw_chdir(const char *path);
int box64_raw_fchdir(int fd);
char *box64_raw_getcwd(char *buf, size_t n);
int box64_raw_pipe(int fds[2]);
mode_t box64_raw_umask(mode_t mask);
int box64_raw_symlink(const char *a, const char *b);
ssize_t box64_raw_readlink(const char *path, char *buf, size_t n);
int box64_raw_link(const char *a, const char *b);

/* ---- stdio over raw fds ---- */
FILE *box64_raw_fopen(const char *path, const char *mode);
int box64_raw_fclose(FILE *f);
size_t box64_raw_fread(void *buf, size_t sz, size_t cnt, FILE *f);
size_t box64_raw_fwrite(const void *buf, size_t sz, size_t cnt, FILE *f);
int box64_raw_fseek(FILE *f, long off, int whence);
int box64_raw_fseeko(FILE *f, off_t off, int whence);
long box64_raw_ftell(FILE *f);
off_t box64_raw_ftello(FILE *f);
void box64_raw_rewind(FILE *f);
int box64_raw_fflush(FILE *f);
int box64_raw_fgetc(FILE *f);
char *box64_raw_fgets(char *buf, int n, FILE *f);
int box64_raw_fputc(int c, FILE *f);
int box64_raw_fputs(const char *s, FILE *f);
int box64_raw_fileno(FILE *f);
int box64_raw_feof(FILE *f);
int box64_raw_ferror(FILE *f);
int box64_raw_ungetc(int c, FILE *f);

/* ---- directory over raw fds ---- */
DIR *box64_raw_opendir(const char *path);
DIR *box64_raw_fdopendir(int fd);
struct dirent *box64_raw_readdir(DIR *d);
int box64_raw_closedir(DIR *d);
void box64_raw_rewinddir(DIR *d);
void box64_raw_seekdir(DIR *d, long off);
long box64_raw_telldir(DIR *d);

/* ---- REAL-libc probe shims (build-376) ----
   rawlibc.c compiles WITHOUT the redirect macros, so these call the genuine
   (interposable) libc symbols — the "plain libc" baseline for the bridge
   probe. Every other box64 source has open/stat/read/mkdir/... macro-redirected
   onto the box64_raw_* traps, so this is the only place real libc file ops
   are reachable. */
int box64_libc_open(const char *path);
int box64_libc_stat(const char *path, struct stat *sb);
int box64_libc_fstat(int fd, struct stat *sb);
ssize_t box64_libc_read(int fd, void *buf, size_t n);
FILE *box64_libc_fopen(const char *path, const char *mode);
int box64_libc_mkdir(const char *path);
int box64_libc_syscall_openat(const char *path, int flags);
int box64_libc_syscall_getpid(void);
int box64_libc_getpid(void);
int box64_libc_getuid(void);

/* Point the process-wide exit/abort interposers (ios_stubs.c) at the same
   log file the runner uses, so every exit/abort call is captured. */
void box64_stub_set_log_path(const char *path);

/* Noreturn exit sink (box64_runner.c): exit() is noreturn, so box64_exit_intercept
   and the strong exit/_exit/_Exit interposers MUST NOT return into the call site
   (UB — silently killed the whole app in v375). On the runner thread with the exit
   land-pad armed this siglongjmps to the runner's pad so the app survives and the
   runner thread ends cleanly; otherwise it does a raw syscall(SYS_exit).
   ra + where carry the caller's return address and dlsym'd symbol (from
   ios_stubs.c) so the runner logs the EXACT exit(0) call site. */
__attribute__((noreturn)) void box64_runner_handle_exit(int status, void *ra, const char *where);

/* The runner wires its exit sink in at startup (setup_logging). ios_stubs.c
   calls this instead of referencing box64_runner_handle_exit directly so CI's
   libbox64.a (which has no box64_runner.o) stays linkable. */
void box64_stub_set_exit_sink(void (*fn)(int, void *, const char *));

#ifdef __cplusplus
}
#endif

#endif /* RAWLIBc_H */
