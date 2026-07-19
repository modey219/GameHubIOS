#include "syscall_core.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <spawn.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/mman.h>
#if __has_include(<sys/shm.h>)
#include <sys/shm.h>
#endif
#include <netinet/in.h>
#include <arpa/inet.h>
#include <dirent.h>
#include <signal.h>
#include <pthread.h>
#include <poll.h>
#include <time.h>
#include <sys/utsname.h>
#include <dlfcn.h>
#include <stdatomic.h>

#ifdef __APPLE__
#include <mach/mach.h>
#if __has_include(<sys/kauth.h>)
#include <sys/kauth.h>
#endif
#endif

#ifndef MAP_JIT
#define MAP_JIT 0x0800
#endif

extern char **environ;

static _Atomic emulator_context_t *g_ctx = NULL;

void syscall_set_context(emulator_context_t *ctx) {
    atomic_store(&g_ctx, ctx);
}

emulator_context_t *syscall_get_context(void) {
    return atomic_load(&g_ctx);
}

void syscall_translation_init(void) {
    if (!atomic_load(&g_ctx)) {
        emulator_context_t *new_ctx = syscall_emulator_create();
        if (new_ctx) {
            emulator_context_t *expected = NULL;
            if (!atomic_compare_exchange_strong(&g_ctx, &expected, new_ctx)) {
                syscall_emulator_destroy(new_ctx);
            }
        }
    }
}

emulator_context_t *syscall_emulator_create(void) {
    size_t alloc_size = sizeof(emulator_context_t);
    fprintf(stderr, "[SyscallCore] syscall_emulator_create: allocating %zu bytes\n", alloc_size);
    emulator_context_t *ctx = calloc(1, alloc_size);
    if (!ctx) {
        fprintf(stderr, "[SyscallCore] syscall_emulator_create: calloc(%zu) returned NULL!\n", alloc_size);
        return NULL;
    }
    fprintf(stderr, "[SyscallCore] syscall_emulator_create: ctx=%p, writing pid...\n", (void*)ctx);
    ctx->process.pid = getpid();
    ctx->process.ppid = getppid();
    fprintf(stderr, "[SyscallCore] syscall_emulator_create: writing brk...\n");
    ctx->process.start_brk = (linux_addr_t)(uintptr_t)sbrk(0);
    ctx->process.brk = ctx->process.start_brk;
    ctx->process.mmap_base = 0x70000000ULL;
    fprintf(stderr, "[SyscallCore] syscall_emulator_create: writing cwd/root...\n");
    strcpy(ctx->process.cwd, "/");
    strcpy(ctx->process.root, "/");
    fprintf(stderr, "[SyscallCore] syscall_emulator_create: init fds...\n");
    for (int i = 0; i < MAX_TRANSLATED_FDS; i++) {
        ctx->process.fds[i].linux_fd = -1;
        ctx->process.fds[i].host_fd = -1;
    }
    fprintf(stderr, "[SyscallCore] syscall_emulator_create: init limits...\n");
    ctx->process.limits[LINUX_RLIMIT_NOFILE].rlim_cur = 1024;
    ctx->process.limits[LINUX_RLIMIT_NOFILE].rlim_max = 4096;
    ctx->initialized = 1;
    fprintf(stderr, "[SyscallCore] syscall_emulator_create: DONE ctx=%p\n", (void*)ctx);
    return ctx;
}

void syscall_emulator_destroy(emulator_context_t *ctx) {
    if (!ctx) return;
    for (int i = 0; i < MAX_TRANSLATED_FDS; i++) {
        if (ctx->process.fds[i].host_fd >= 0) close(ctx->process.fds[i].host_fd);
    }
    for (int i = 0; i < ctx->process.mmap_count; i++) {
        if (ctx->process.mmap_regions[i].host_addr)
            munmap(ctx->process.mmap_regions[i].host_addr, ctx->process.mmap_regions[i].size);
    }
    free(ctx);
}

int register_host_fd(emulator_context_t *ctx, int linux_fd, int host_fd, int flags) {
    if (!ctx) ctx = syscall_get_context();
    if (!ctx) return -1;
    if (linux_fd < 0 || linux_fd >= MAX_TRANSLATED_FDS) return -1;
    ctx->process.fds[linux_fd].linux_fd = linux_fd;
    ctx->process.fds[linux_fd].host_fd = host_fd;
    ctx->process.fds[linux_fd].flags = flags;
    ctx->process.fds[linux_fd].is_socket = 0;
    ctx->process.fds[linux_fd].is_epoll = 0;
    return 0;
}

int host_fd_for_linux(emulator_context_t *ctx, int linux_fd) {
    if (!ctx) ctx = syscall_get_context();
    if (!ctx) return -1;
    if (linux_fd < 0 || linux_fd >= MAX_TRANSLATED_FDS) return -1;
    return ctx->process.fds[linux_fd].host_fd;
}

static int find_free_fd_slot(emulator_context_t *ctx) {
    if (!ctx) return -1;
    for (int i = 3; i < MAX_TRANSLATED_FDS; i++) {
        if (ctx->process.fds[i].linux_fd == -1) return i;
    }
    return -1;
}

static int to_host_flags(int lf) {
    int h = 0;
    if ((lf & 0x3) == 0x0) h |= O_RDONLY;
    else if ((lf & 0x3) == 0x1) h |= O_WRONLY;
    else if ((lf & 0x3) == 0x2) h |= O_RDWR;
    if (lf & 0x0040) h |= O_CREAT;
    if (lf & 0x0200) h |= O_TRUNC;
    if (lf & 0x0400) h |= O_APPEND;
    if (lf & 0x0800) h |= O_NONBLOCK;
    if (lf & 0x80000) h |= O_CLOEXEC;
    return h;
}

static void fill_stat(struct linux_stat *ls, struct stat *hs) {
    memset(ls, 0, sizeof(*ls));
    ls->st_dev = hs->st_dev;
    ls->st_ino = hs->st_ino;
    ls->st_nlink = hs->st_nlink;
    ls->st_mode = hs->st_mode;
    ls->st_uid = hs->st_uid;
    ls->st_gid = hs->st_gid;
    ls->st_rdev = hs->st_rdev;
    ls->st_size = hs->st_size;
    ls->st_blksize = hs->st_blksize;
    ls->st_blocks = hs->st_blocks;
#ifdef __APPLE__
    ls->st_atim.tv_sec = hs->st_atimespec.tv_sec;
    ls->st_atim.tv_nsec = hs->st_atimespec.tv_nsec;
    ls->st_mtim.tv_sec = hs->st_mtimespec.tv_sec;
    ls->st_mtim.tv_nsec = hs->st_mtimespec.tv_nsec;
    ls->st_ctim.tv_sec = hs->st_ctimespec.tv_sec;
    ls->st_ctim.tv_nsec = hs->st_ctimespec.tv_nsec;
#else
    ls->st_atim.tv_sec = hs->st_atim.tv_sec;
    ls->st_atim.tv_nsec = hs->st_atim.tv_nsec;
    ls->st_mtim.tv_sec = hs->st_mtim.tv_sec;
    ls->st_mtim.tv_nsec = hs->st_mtim.tv_nsec;
    ls->st_ctim.tv_sec = hs->st_ctim.tv_sec;
    ls->st_ctim.tv_nsec = hs->st_ctim.tv_nsec;
#endif
}

linux_addr_t emulator_mmap(emulator_context_t *ctx, linux_addr_t addr, size_t length, int prot, int flags, int fd, long offset) {
    if (!ctx) ctx = syscall_get_context();
    int hp = 0;
    if (prot & 1) hp |= PROT_READ;
    if (prot & 2) hp |= PROT_WRITE;
    if (prot & 4) hp |= PROT_EXEC;

    int hf = MAP_ANONYMOUS | MAP_PRIVATE;
    if (flags & 0x01) hf = (hf & ~MAP_PRIVATE) | MAP_SHARED;
    if (flags & 0x10) hf |= MAP_FIXED;
#ifdef MAP_JIT
    if (prot & 4) hf |= MAP_JIT;
#endif

    int hfd = -1;
    if (!(flags & 0x20) && fd >= 0) hfd = host_fd_for_linux(ctx, fd);
    void *req = (flags & 0x10) ? (void *)(uintptr_t)addr : NULL;
    void *r = mmap(req, length, hp, hf, hfd, offset);
    if (r == MAP_FAILED) return (linux_addr_t)(long)(-errno);
    if (ctx->process.mmap_count < MAX_MMAP_REGIONS) {
        mmap_region_t *reg = &ctx->process.mmap_regions[ctx->process.mmap_count++];
        linux_addr_t guest = (flags & 0x10) ? addr : (linux_addr_t)(uintptr_t)r;
        reg->guest_addr = (void *)(uintptr_t)guest; reg->host_addr = r; reg->size = length;
        reg->prot = prot; reg->flags = flags; reg->fd = fd; reg->offset = offset;
    }
    return (linux_addr_t)(uintptr_t)r;
}

int emulator_mprotect(emulator_context_t *ctx, linux_addr_t addr, size_t length, int prot) {
    if (!ctx) ctx = syscall_get_context();
    int hp = 0;
    if (prot & 1) hp |= PROT_READ;
    if (prot & 2) hp |= PROT_WRITE;
    if (prot & 4) hp |= PROT_EXEC;
    return mprotect((void *)(uintptr_t)addr, length, hp);
}

int emulator_munmap(emulator_context_t *ctx, linux_addr_t addr, size_t length) {
    if (!ctx) ctx = syscall_get_context();
    int r = munmap((void *)(uintptr_t)addr, length);
    if (ctx) {
        for (int i = 0; i < ctx->process.mmap_count; i++) {
        if ((linux_addr_t)(uintptr_t)ctx->process.mmap_regions[i].host_addr == addr) {
            ctx->process.mmap_regions[i] = ctx->process.mmap_regions[--ctx->process.mmap_count];
            break;
        }
    }
    }
    return r;
}

long translate_syscall(emulator_context_t *ctx, long num, long a1, long a2, long a3, long a4, long a5, long a6) {
    if (!ctx) ctx = syscall_get_context();
    if (!ctx) {
        fprintf(stderr, "[Syscall] No context! syscall=%ld\n", num);
        return -ENOSYS;
    }

    switch (num) {
        case 0: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            ssize_t r = read(hfd, (void *)(uintptr_t)a2, a3);
            return r < 0 ? -errno : r;
        }
        case 1: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            ssize_t r = write(hfd, (const void *)(uintptr_t)a2, a3);
            return r < 0 ? -errno : r;
        }
        case 2: {
            int hf = to_host_flags(a2);
            int hfd = open((const char *)(uintptr_t)a1, hf, a3);
            if (hfd < 0) return -errno;
            int s = find_free_fd_slot(ctx);
            if (s < 0) { close(hfd); return -EMFILE; }
            register_host_fd(ctx, s, hfd, a2);
            return s;
        }
        case 3: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            close(hfd);
            ctx->process.fds[a1].linux_fd = -1;
            ctx->process.fds[a1].host_fd = -1;
            return 0;
        }
        case 4: case 5: {
            struct stat hs;
            int r;
            if (num == 4) r = stat((const char *)(uintptr_t)a1, &hs);
            else r = fstat(host_fd_for_linux(ctx, a1), &hs);
            if (r < 0) return -errno;
            fill_stat((struct linux_stat *)(uintptr_t)a2, &hs);
            return 0;
        }
        case 7: {
            int hs;
            pid_t r = waitpid(a1, &hs, (a3 & 1) ? WNOHANG : 0);
            if (r < 0) return -errno;
            if (a2) *(int *)(uintptr_t)a2 = hs;
            return r;
        }
        case 8: {
            int r = access((const char *)(uintptr_t)a1, a2);
            return r < 0 ? -errno : 0;
        }
        case 9:
            return emulator_mmap(ctx, a1, a2, a3, a4, a5, a6);
        case 10:
            return emulator_mprotect(ctx, a1, a2, a3);
        case 11:
            return emulator_munmap(ctx, a1, a2);
        case 12: {
            if (a1 == 0) return ctx->process.brk;
            ctx->process.brk = a1;
            return ctx->process.brk;
        }
        case 13:
            return 0;
        case 14:
            return 0;
        case 16: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            if ((unsigned long)a2 == 0x5413) {
                struct winsize *ws = (struct winsize *)(uintptr_t)a3;
                ws->ws_col = 80; ws->ws_row = 24;
                return 0;
            }
            if ((unsigned long)a2 == 0x5401 || (unsigned long)a2 == 0x5402 ||
                (unsigned long)a2 == 0x5403 || (unsigned long)a2 == 0x5404 ||
                (unsigned long)a2 == 0x5414 || (unsigned long)a2 == 0x5427) return 0;
            if ((unsigned long)a2 == 0x5421) {
                if (a3) *(int *)(uintptr_t)a3 = getpgrp();
                return 0;
            }
            if ((unsigned long)a2 == 0x5430) {
                int val = 0;
                ioctl(hfd, FIONREAD, &val);
                if (a3) *(int *)(uintptr_t)a3 = val;
                return 0;
            }
            int r = ioctl(hfd, a2, (void *)(uintptr_t)a3);
            return r < 0 ? -errno : 0;
        }
        case 17: {
            int hp[2];
            if (pipe(hp) < 0) return -errno;
            int s0 = find_free_fd_slot(ctx);
            int s1 = find_free_fd_slot(ctx);
            if (s0 < 0 || s1 < 0) { close(hp[0]); close(hp[1]); return -EMFILE; }
            register_host_fd(ctx, s0, hp[0], 0);
            register_host_fd(ctx, s1, hp[1], 0);
            int *fd = (int *)(uintptr_t)a1;
            fd[0] = s0; fd[1] = s1;
            return 0;
        }
        case 20: return getpid();
        case 21: { int r = unlink((const char *)(uintptr_t)a1); return r < 0 ? -errno : 0; }
        case 24: return getuid();
        case 25: return getgid();
        case 28: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            int r = fcntl(hfd, a2, a3);
            return r < 0 ? -errno : r;
        }
        case 32: {
            int ho = host_fd_for_linux(ctx, a1);
            if (ho < 0) return -EBADF;
            int dest_fd = host_fd_for_linux(ctx, a2);
            if (dest_fd >= 0) close(dest_fd);
            int hn;
            if (dest_fd >= 0) {
                hn = dup2(ho, dest_fd);
            } else {
                hn = dup(ho);
            }
            if (hn < 0) return -errno;
            register_host_fd(ctx, a2, hn, ctx->process.fds[a1].flags);
            return a2;
        }
        case 33: return getppid();
        case 35: {
            struct timespec hr;
            hr.tv_sec = ((struct linux_timespec *)(uintptr_t)a1)->tv_sec;
            hr.tv_nsec = ((struct linux_timespec *)(uintptr_t)a1)->tv_nsec;
            struct timespec rem;
            int r = nanosleep(&hr, &rem);
            if (a2) { ((struct linux_timespec *)(uintptr_t)a2)->tv_sec = rem.tv_sec; ((struct linux_timespec *)(uintptr_t)a2)->tv_nsec = rem.tv_nsec; }
            return r < 0 ? -errno : 0;
        }
        case 39: return getpid();
        case 41: {
            int hd = a1 == 2 ? AF_INET : (a1 == 10 ? AF_INET6 : a1);
            int ht = a2 & 0xf;
            if (ht == 1) ht = SOCK_STREAM;
            else if (ht == 2) ht = SOCK_DGRAM;
            int hfd = socket(hd, (a2 & ~0xf) | ht, a3);
            if (hfd < 0) return -errno;
            int s = find_free_fd_slot(ctx);
            if (s < 0) { close(hfd); return -EMFILE; }
            register_host_fd(ctx, s, hfd, 0);
            ctx->process.fds[s].is_socket = 1;
            return s;
        }
        case 42: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            struct linux_sockaddr_in *la = (struct linux_sockaddr_in *)(uintptr_t)a2;
            if (la && la->sin_family == LINUX_AF_INET) {
                struct sockaddr_in ha;
                ha.sin_family = AF_INET;
                ha.sin_port = la->sin_port;
                ha.sin_addr.s_addr = la->sin_addr;
                memset(ha.sin_zero, 0, 8);
                int r = connect(hfd, (struct sockaddr *)&ha, sizeof(ha));
                return r < 0 ? -errno : 0;
            }
            return -EAFNOSUPPORT;
        }
        case 49: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            struct linux_sockaddr_in *la = (struct linux_sockaddr_in *)(uintptr_t)a2;
            if (la && la->sin_family == LINUX_AF_INET) {
                struct sockaddr_in ha;
                ha.sin_family = AF_INET;
                ha.sin_port = la->sin_port;
                ha.sin_addr.s_addr = la->sin_addr;
                memset(ha.sin_zero, 0, 8);
                int r = bind(hfd, (struct sockaddr *)&ha, sizeof(ha));
                return r < 0 ? -errno : 0;
            }
            return -EAFNOSUPPORT;
        }
        case 50: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            int r = listen(hfd, a2);
            return r < 0 ? -errno : 0;
        }
        case 51: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            struct sockaddr sa; socklen_t sl = a3 ? *(int *)(uintptr_t)a3 : 0;
            int nf = accept(hfd, &sa, &sl);
            if (nf < 0) return -errno;
            int s = find_free_fd_slot(ctx);
            if (s < 0) { close(nf); return -EMFILE; }
            register_host_fd(ctx, s, nf, 0);
            ctx->process.fds[s].is_socket = 1;
            if (a3) *(int *)(uintptr_t)a3 = sl;
            return s;
        }
        case 54: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            int hl = a2 == LINUX_SOL_SOCKET ? SOL_SOCKET : a2;
            int r = setsockopt(hfd, hl, a3, (const void *)(uintptr_t)a4, a5);
            return r < 0 ? -errno : 0;
        }
        case 56: {
            // clone - stub: just return current pid (Wine can work with this for simple cases)
            return getpid();
        }
        case 57: {
            // fork - stub: return 0 (child) for Wine prefix init
            return 0;
        }
        case 59: {
            const char *path = (const char *)(uintptr_t)a1;
            char **argv = (char **)(uintptr_t)a2;
            char **envp = (char **)(uintptr_t)a3;
            if (envp) {
                for (int i = 0; envp[i]; i++) {
                    char *eq = strchr(envp[i], '=');
                    if (eq) {
                        char k[256] = {0};
                        int kl = eq - envp[i];
                        if (kl < 255) { strncpy(k, envp[i], kl); setenv(k, eq + 1, 1); }
                    }
                }
            }
            fprintf(stderr, "[Emulator] execve: %s\n", path);
            pid_t pid;
            int r = posix_spawn(&pid, path, NULL, NULL, argv, environ);
            if (r != 0) return -r;
            int status;
            waitpid(pid, &status, 0);
            return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
        }
        case 60: { ctx->running = 0; return a1; }
        case 63: {
            struct linux_utsname *n = (struct linux_utsname *)(uintptr_t)a1;
            memset(n, 0, sizeof(*n));
            strcpy(n->sysname, "Linux");
            strcpy(n->nodename, "gamehub");
            strcpy(n->release, "5.15.0-gamehub");
            strcpy(n->version, "#1 SMP");
            strcpy(n->machine, "aarch64");
            strcpy(n->domainname, "(none)");
            return 0;
        }
        case 66: return setuid(a1);
        case 67: return getuid();
        case 69: return setgid(a1);
        case 72: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            int r = fcntl(hfd, a2, a3);
            return r < 0 ? -errno : r;
        }
        case 78: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            DIR *dir = fdopendir(dup(hfd));
            if (!dir) return -errno;
            struct dirent *e;
            int off = 0;
            while (off < (int)a3) {
                e = readdir(dir);
                if (!e) break;
                struct linux_dirent *ld = (struct linux_dirent *)((char *)(uintptr_t)a2 + off);
                ld->d_ino = e->d_ino;
                size_t nl = strlen(e->d_name) + 1;
                ld->d_reclen = sizeof(struct linux_dirent) + nl;
                ld->d_type = e->d_type == DT_DIR ? 4 : (e->d_type == DT_REG ? 8 : 0);
                ld->d_off = off + ld->d_reclen;
                memcpy(ld->d_name, e->d_name, nl);
                off += ld->d_reclen;
            }
            closedir(dir);
            return off;
        }
        case 80: {
            int r = chdir((const char *)(uintptr_t)a1);
            if (r == 0) strncpy(ctx->process.cwd, (const char *)(uintptr_t)a1, LINUX_PATH_MAX - 1);
            return r < 0 ? -errno : 0;
        }
        case 82: { int r = rename((const char *)(uintptr_t)a1, (const char *)(uintptr_t)a2); return r < 0 ? -errno : 0; }
        case 83: { int r = mkdir((const char *)(uintptr_t)a1, a2); return r < 0 ? -errno : 0; }
        case 89: {
            ssize_t r = readlink((const char *)(uintptr_t)a1, (char *)(uintptr_t)a2, a3);
            return r < 0 ? -errno : r;
        }
        case 94: return geteuid();
        case 95: return getegid();
        case 104: {
            struct timeval itv;
            if (a2) { itv.tv_sec = ((long long *)a2)[0]; itv.tv_usec = ((long long *)a2)[1]; }
            int r = setitimer(a1, a2 ? &itv : NULL, NULL);
            return r < 0 ? -errno : 0;
        }
        case 107: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            struct sockaddr_storage ss; socklen_t sl = 128;
            int r = getpeername(hfd, (struct sockaddr *)&ss, &sl);
            return r < 0 ? -errno : 0;
        }
        case 110: return getppid();
        case 118: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            int r = fsync(hfd);
            return r < 0 ? -errno : 0;
        }
        case 125: return emulator_mprotect(ctx, a1, a2, a3);
        case 131: return 0;
        case 134: {
            // rt_sigaction - stub, return success
            return 0;
        }
        case 135: {
            // rt_sigprocmask - stub, return success
            return 0;
        }
        case 140: {
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            off_t off = ((off_t)a2 << 32) | (unsigned int)a3;
            off_t r = lseek(hfd, off, a5);
            if (r < 0) return -errno;
            if (a4) *(long long *)(uintptr_t)a4 = r;
            return 0;
        }
        case 157: return 0;
        case 158: return 0;
        case 160: {
            struct timeval tv;
            int r = gettimeofday(&tv, NULL);
            if (r < 0) return -errno;
            if (a1) { ((long *)(uintptr_t)a1)[0] = tv.tv_sec; ((long *)(uintptr_t)a1)[1] = tv.tv_usec; }
            return 0;
        }
        case 168: {
            struct pollfd *pfd = (struct pollfd *)(uintptr_t)a1;
            if (a2 > 1024) a2 = 1024;
            if (a2 <= 0) return -EINVAL;
            struct pollfd *hpfd = calloc(a2, sizeof(struct pollfd));
            int *map = calloc(a2, sizeof(int));
            if (!hpfd || !map) { free(hpfd); free(map); return -ENOMEM; }
            for (int i = 0; i < a2; i++) {
                hpfd[i].fd = host_fd_for_linux(ctx, pfd[i].fd);
                hpfd[i].events = pfd[i].events;
                map[i] = pfd[i].fd;
            }
            int r = poll(hpfd, a2, a3);
            if (r >= 0) { for (int i = 0; i < a2; i++) pfd[i].revents = hpfd[i].revents; }
            free(hpfd); free(map);
            return r < 0 ? -errno : r;
        }
        case 174: return getuid();
        case 175: return geteuid();
        case 176: return getgid();
        case 177: return getegid();
        case 186: return (long)pthread_self();
        case 199: return getuid();
        case 200: return getgid();
        case 201: return getuid();
        case 202: {
            // futex - basic implementation
            // op = a2 & 0xf: 0=FUTEX_WAIT, 1=FUTEX_WAKE, etc
            int futex_op = a2 & 0xf;
            int *uaddr = (int *)(uintptr_t)a1;
            if (futex_op == 0) {
                // FUTEX_WAIT: wait if *uaddr == val
                if (uaddr && *uaddr == (int)a3) {
                    struct timespec ts;
                    if (a4) {
                        ts.tv_sec = ((struct linux_timespec *)(uintptr_t)a4)->tv_sec;
                        ts.tv_nsec = ((struct linux_timespec *)(uintptr_t)a4)->tv_nsec;
                    } else {
                        ts.tv_sec = 10; ts.tv_nsec = 0;
                    }
                    nanosleep(&ts, NULL);
                }
                return 0;
            } else if (futex_op == 1) {
                // FUTEX_WAKE: wake up val threads
                return a3 > 0 ? a3 : 0;
            }
            return 0;
        }
        case 212: return 0;
        case 214: return getpgid(a1);
        case 218: return (long)pthread_self();
        case 228: {
            clockid_t c = a1 == 1 ? CLOCK_MONOTONIC : CLOCK_REALTIME;
            struct timespec ts;
            int r = clock_gettime(c, &ts);
            if (r < 0) return -errno;
            struct linux_timespec *lts = (struct linux_timespec *)(uintptr_t)a2;
            lts->tv_sec = ts.tv_sec; lts->tv_nsec = ts.tv_nsec;
            return 0;
        }
        case 231: { ctx->running = 0; return a1; }
        case 257: {
            int hf = to_host_flags(a3);
            int hfd = open((const char *)(uintptr_t)a2, hf, a4);
            if (hfd < 0) return -errno;
            int s = find_free_fd_slot(ctx);
            if (s < 0) { close(hfd); return -EMFILE; }
            register_host_fd(ctx, s, hfd, a3);
            return s;
        }
        case 262: {
            struct stat hs;
            int r = stat((const char *)(uintptr_t)a2, &hs);
            if (r < 0) return -errno;
            fill_stat((struct linux_stat *)(uintptr_t)a3, &hs);
            return 0;
        }
        case 291: {
            int s = find_free_fd_slot(ctx);
            if (s < 0) return -EMFILE;
            register_host_fd(ctx, s, -1, 0);
            ctx->process.fds[s].is_epoll = 1;
            return s;
        }
        case 281: {
            // epoll_wait - translate to poll-based fallback
            int efd = host_fd_for_linux(ctx, a1);
            if (efd < 0) return -EBADF;
            struct linux_epoll_event *levents = (struct linux_epoll_event *)(uintptr_t)a2;
            if (!levents) return -EINVAL;
            int timeout_ms = a4;
            struct timespec ts;
            ts.tv_sec = timeout_ms / 1000;
            ts.tv_nsec = (timeout_ms % 1000) * 1000000;
            // Simple fallback: check if any fds are readable
            int count = 0;
            for (int i = 0; i < MAX_TRANSLATED_FDS && count < a3; i++) {
                if (ctx->process.fds[i].host_fd >= 0 && !ctx->process.fds[i].is_socket) {
                    struct pollfd pfd;
                    pfd.fd = ctx->process.fds[i].host_fd;
                    pfd.events = POLLIN;
                    pfd.revents = 0;
                    int pr = poll(&pfd, 1, timeout_ms);
                    if (pr > 0) {
                        levents[count].fd = i;
                        levents[count].events = pfd.revents;
                        count++;
                    }
                }
            }
            return count;
        }
        case 292: {
            // epoll_ctl (op=a2, epfd=a1, fd=a3, event=a4)
            // Stub: return success - epoll is handled via poll fallback
            return 0;
        }
        case 293: {
            int hp[2];
            if (pipe(hp) < 0) return -errno;
            int s0 = find_free_fd_slot(ctx);
            int s1 = find_free_fd_slot(ctx);
            if (s0 < 0 || s1 < 0) { close(hp[0]); close(hp[1]); return -EMFILE; }
            register_host_fd(ctx, s0, hp[0], 0);
            register_host_fd(ctx, s1, hp[1], 0);
            int *fd = (int *)(uintptr_t)a1;
            fd[0] = s0; fd[1] = s1;
            return 0;
        }
        case 302: case 307: {
            if (a2 >= 0 && a2 < 16) {
                if (a4) memcpy((void *)(uintptr_t)a4, &ctx->process.limits[a2], sizeof(struct linux_rlimit));
                if (a3) memcpy(&ctx->process.limits[a2], (const void *)(uintptr_t)a3, sizeof(struct linux_rlimit));
            }
            return 0;
        }
        case 308: {
            // getdents64 - similar to getdents but with linux_dirent64
            int hfd = host_fd_for_linux(ctx, a1);
            if (hfd < 0) return -EBADF;
            DIR *dir = fdopendir(dup(hfd));
            if (!dir) return -errno;
            struct dirent *e;
            int off = 0;
            while (off < (int)a3) {
                e = readdir(dir);
                if (!e) break;
                struct linux_dirent *ld = (struct linux_dirent *)((char *)(uintptr_t)a2 + off);
                ld->d_ino = e->d_ino;
                size_t nl = strlen(e->d_name) + 1;
                ld->d_reclen = sizeof(struct linux_dirent) + nl;
                ld->d_type = e->d_type == DT_DIR ? 4 : (e->d_type == DT_REG ? 8 : 0);
                ld->d_off = off + ld->d_reclen;
                memcpy(ld->d_name, e->d_name, nl);
                off += ld->d_reclen;
            }
            closedir(dir);
            return off;
        }
        case 261: {
            // prlimit64 - get/set resource limits
            if (a3 >= 0 && a3 < 16) {
                if (a4) memcpy((void *)(uintptr_t)a4, &ctx->process.limits[a3], sizeof(struct linux_rlimit));
                if (a2) memcpy(&ctx->process.limits[a3], (const void *)(uintptr_t)a2, sizeof(struct linux_rlimit));
            }
            return 0;
        }
        case 318: {
            int fd = open("/dev/urandom", O_RDONLY);
            if (fd < 0) return -errno;
            ssize_t r = read(fd, (void *)(uintptr_t)a1, a2);
            close(fd);
            return r < 0 ? -errno : r;
        }
        case 319: {
            char p[256];
            snprintf(p, sizeof(p), "/tmp/memfd_%d_%d", (int)getpid(), rand());
            int fd = shm_open(p, O_RDWR | O_CREAT, 0600);
            if (fd < 0) return -errno;
            shm_unlink(p);
            int s = find_free_fd_slot(ctx);
            register_host_fd(ctx, s, fd, 0);
            return s;
        }
        case 425: return -ENOSYS;
        case 435: return -ENOSYS; // clone3
        case 434: return 0;      // pidfd_open - stub
        case 436: return 0;      // close_range - stub
        case 441: {              // execveat - stub
            return -ENOSYS;
        }
        case 449: {
            // set_robust_list - stub
            return 0;
        }
        case 300: {
            // get_robust_list - stub
            if (a3) *(long *)(uintptr_t)a3 = 0;
            return 0;
        }
        case 99: {
            // sysinfo - return memory info based on configured limit
            struct {
                long uptime;
                unsigned long loads[3];
                unsigned long totalram;
                unsigned long freeram;
                unsigned long sharedram;
                unsigned long bufferram;
                unsigned long totalswap;
                unsigned long freeswap;
                unsigned short procs;
            } *info = (void *)(uintptr_t)a1;
            if (info) {
                /* Read BOX64_MAXMEM or WINE_MAX_MEMORY_MB env var for limit */
                unsigned long limit_mb = 512; /* default 512MB */
                const char *env_mem = getenv("BOX64_MAXMEM");
                if (!env_mem) env_mem = getenv("WINE_MAX_MEMORY_MB");
                if (env_mem) {
                    unsigned long val = 0;
                    for (const char *p = env_mem; *p >= '0' && *p <= '9'; p++)
                        val = val * 10 + (*p - '0');
                    if (val > 0) limit_mb = val;
                }
                unsigned long total_bytes = limit_mb * 1024 * 1024;
                unsigned long free_bytes = total_bytes * 3 / 4; /* assume 75% free at startup */

                info->uptime = 0;
                info->loads[0] = 1024; info->loads[1] = 512; info->loads[2] = 256;
                info->totalram = total_bytes;
                info->freeram = free_bytes;
                info->sharedram = 256 * 1024 * 1024;
                info->bufferram = 128 * 1024 * 1024;
                info->totalswap = 256 * 1024 * 1024;
                info->freeswap = 256 * 1024 * 1024;
                info->procs = 64;
            }
            return 0;
        }
        default:
            fprintf(stderr, "[Syscall] Unhandled: %ld (%ld,%ld,%ld,%ld,%ld,%ld)\n", num, a1, a2, a3, a4, a5, a6);
            return -ENOSYS;
    }
}

int emulator_run(emulator_context_t *ctx, const char *executable, char **argv, char **envp) {
    ctx->running = 1;
    fprintf(stderr, "[Emulator] Starting: %s\n", executable);
    if (envp) {
        for (int i = 0; envp[i]; i++) {
            char *eq = strchr(envp[i], '=');
            if (eq) {
                char k[256] = {0};
                int kl = eq - envp[i];
                if (kl < 255) { strncpy(k, envp[i], kl); k[kl]=0; setenv(k, eq + 1, 1); }
            }
        }
    }
    pid_t pid;
    char **args = argv ? argv : (char *[]){ (char *)executable, NULL };
    int r = posix_spawn(&pid, executable, NULL, NULL, args, environ);
    if (r != 0) { fprintf(stderr, "[Emulator] posix_spawn failed: %s\n", strerror(r)); return -r; }
    fprintf(stderr, "[Emulator] Child PID: %d\n", pid);
    int status;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

void emulator_stop(emulator_context_t *ctx) { if (ctx) ctx->running = 0; }
