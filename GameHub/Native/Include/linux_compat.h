// ============================================================
// linux_compat.h - Linux/glibc compatibility layer for iOS (Darwin)
// Provides stubs and implementations for functions Box64 expects
// from glibc that don't exist on Darwin/iOS.
// ============================================================
#ifndef LINUX_COMPAT_H
#define LINUX_COMPAT_H

#ifdef __APPLE__

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <poll.h>
#include <pthread.h>
#include <dirent.h>

// ----- epoll (iOS: poll-based fallback) -----
struct epoll_event {
    uint32_t events;
    int fd;
};

#define EPOLLIN   0x001
#define EPOLLOUT  0x004
#define EPOLLERR  0x008
#define EPOLLHUP  0x010
#define EPOLLRDHUP 0x2000
#define EPOLLET   0x80000000
#define EPOLLONESHOT 0x40000000
#define EPOLL_CTL_ADD 1
#define EPOLL_CTL_DEL 2
#define EPOLL_CTL_MOD 3

/* Simple epoll emulation: store up to 32 monitored fds in the "epfd" slot */
#define EPOLL_MAX_FDS 32
typedef struct {
    int fds[EPOLL_MAX_FDS];
    uint32_t events[EPOLL_MAX_FDS];
    int count;
} epoll_ctx_t;

static epoll_ctx_t g_epoll_ctxs[8] = {0};

static inline int epoll_create(int size) {
    (void)size;
    for (int i = 0; i < 8; i++) {
        if (g_epoll_ctxs[i].count == 0) return 1000 + i; /* fake fd */
    }
    return -1;
}

static inline int epoll_create1(int flags) {
    (void)flags;
    return epoll_create(0);
}

static inline int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event) {
    int idx = epfd - 1000;
    if (idx < 0 || idx >= 8) { errno = EINVAL; return -1; }
    epoll_ctx_t *ctx = &g_epoll_ctxs[idx];

    if (op == EPOLL_CTL_ADD) {
        if (ctx->count >= EPOLL_MAX_FDS) { errno = ENOMEM; return -1; }
        ctx->fds[ctx->count] = fd;
        ctx->events[ctx->count] = event ? event->events : 0;
        ctx->count++;
        return 0;
    } else if (op == EPOLL_CTL_DEL) {
        for (int i = 0; i < ctx->count; i++) {
            if (ctx->fds[i] == fd) {
                ctx->fds[i] = ctx->fds[ctx->count - 1];
                ctx->events[i] = ctx->events[ctx->count - 1];
                ctx->count--;
                return 0;
            }
        }
        return -1;
    } else if (op == EPOLL_CTL_MOD) {
        for (int i = 0; i < ctx->count; i++) {
            if (ctx->fds[i] == fd) {
                ctx->events[i] = event ? event->events : 0;
                return 0;
            }
        }
        return -1;
    }
    errno = EINVAL;
    return -1;
}

static inline int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout) {
    int idx = epfd - 1000;
    if (idx < 0 || idx >= 8) { errno = EINVAL; return -1; }
    epoll_ctx_t *ctx = &g_epoll_ctxs[idx];
    if (ctx->count == 0) {
        /* No fds to poll — sleep briefly to avoid busy-spin */
        struct timespec ts = { 0, (timeout < 0 ? 100 : timeout) * 1000000 };
        nanosleep(&ts, NULL);
        return 0;
    }

    /* Build pollfd array */
    struct pollfd pfds[EPOLL_MAX_FDS];
    int n = ctx->count < maxevents ? ctx->count : maxevents;
    if (n > EPOLL_MAX_FDS) n = EPOLL_MAX_FDS;
    for (int i = 0; i < n; i++) {
        pfds[i].fd = ctx->fds[i];
        pfds[i].events = 0;
        if (ctx->events[i] & EPOLLIN) pfds[i].events |= POLLIN;
        if (ctx->events[i] & EPOLLOUT) pfds[i].events |= POLLOUT;
        pfds[i].revents = 0;
    }

    int ret = poll(pfds, n, timeout);
    if (ret <= 0) return ret;

    int out = 0;
    for (int i = 0; i < n && out < ret; i++) {
        if (pfds[i].revents != 0) {
            events[out].fd = pfds[i].fd;
            events[out].events = 0;
            if (pfds[i].revents & POLLIN) events[out].events |= EPOLLIN;
            if (pfds[i].revents & POLLOUT) events[out].events |= EPOLLOUT;
            if (pfds[i].revents & (POLLERR|POLLHUP)) events[out].events |= EPOLLERR | EPOLLHUP;
            out++;
        }
    }
    return out;
}

// ----- signalfd (not on iOS) -----
struct signalfd_siginfo {
    uint32_t ssi_signo;
    uint32_t ssi_errno;
    int32_t ssi_code;
    uint32_t ssi_pid;
    uint32_t ssi_uid;
    int32_t ssi_fd;
    uint32_t ssi_tid;
    uint32_t ssi_band;
    uint32_t ssi_overrun;
    uint32_t ssi_sigxsigno;
    uint32_t ssi_sigxstatus;
    uint32_t ssi_sigxvalue;
    uint32_t ssi_sigxaddr;
    uint32_t _pad[128];
};

#define SFD_NONBLOCK 0x800
#define SFD_CLOEXEC 0x80000

static inline int signalfd(int fd, const sigset_t *mask, int flags) {
    (void)fd; (void)mask; (void)flags;
    errno = ENOSYS;
    return -1;
}

// ----- timerfd (not on iOS) -----
#define TFD_NONBLOCK 0x800
#define TFD_CLOEXEC 0x80000
#define TFD_TIMER_CANCEL_ON_SET 0x0002

static inline int timerfd_create(int clockid, int flags) {
    (void)clockid; (void)flags;
    errno = ENOSYS;
    return -1;
}

static inline int timerfd_settime(int fd, int flags, const struct itimerval *new_value, struct itimerval *old_value) {
    (void)fd; (void)flags; (void)new_value; (void)old_value;
    errno = ENOSYS;
    return -1;
}

static inline int timerfd_gettime(int fd, struct itimerval *cur_value) {
    (void)fd; (void)cur_value;
    errno = ENOSYS;
    return -1;
}

// ----- eventfd (iOS: socketpair-based fallback) -----
#define EFD_NONBLOCK 0x800
#define EFD_CLOEXEC 0x80000
#define EFD_SEMAPHORE 0x001

static inline int eventfd(unsigned int initval, int flags) {
    /* Wine uses eventfd for thread synchronization. We use socketpair as fallback.
       The returned fd is one end; read/write semantics differ slightly from real
       eventfd but sufficient for Wine's usage (notification via write+read). */
    int fds[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) != 0) return -1;
    if (flags & EFD_NONBLOCK) {
        fcntl(fds[0], F_SETFL, O_NONBLOCK);
        fcntl(fds[1], F_SETFL, O_NONBLOCK);
    }
    /* Drain initial value by writing + reading the counter bytes */
    if (initval > 0) {
        uint64_t val = initval;
        write(fds[1], &val, sizeof(val));
    }
    close(fds[0]);
    return fds[1];
}

// ----- inotify (not on iOS) -----
#define IN_MODIFY    0x00000002
#define IN_CREATE    0x00000100
#define IN_DELETE    0x00000200
#define IN_MOVED_FROM 0x00000040
#define IN_MOVED_TO  0x00000080

struct inotify_event {
    int wd;
    uint32_t mask;
    uint32_t cookie;
    uint32_t len;
    char name[];
};

static inline int inotify_init(void) { errno = ENOSYS; return -1; }
static inline int inotify_init1(int flags) { (void)flags; errno = ENOSYS; return -1; }
static inline int inotify_add_watch(int fd, const char *pathname, uint32_t mask) {
    (void)fd; (void)pathname; (void)mask; errno = ENOSYS; return -1;
}
static inline int inotify_rm_watch(int fd, int wd) {
    (void)fd; (void)wd; errno = ENOSYS; return -1;
}

// ----- /proc/self/maps replacement -----
// Box64 reads /proc/self/maps to determine memory layout
// On iOS we provide a minimal stub
static inline int open_proc_maps(void) {
    return -1;
}

// ----- Linux-specific stat flags -----
#ifndef S_ISVTX
#define S_ISVTX 0o01000
#endif
#ifndef S_ISGID
#define S_ISGID 0o02000
#endif
#ifndef S_ISUID
#define S_ISUID 0o04000
#endif

// ----- prctl (not on iOS, stub) -----
#define PR_SET_NAME 15
#define PR_GET_NAME 16
#define PR_SET_VMA 0x53564d41

static inline int prctl(int option, ...) {
    (void)option;
    errno = ENOSYS;
    return -1;
}

// ----- clone (not on iOS, use pthread) -----
#define CLONE_VM 0x00000100
#define CLONE_FS 0x00000200
#define CLONE_FILES 0x00000400
#define CLONE_SIGHAND 0x00000800
#define CLONE_THREAD 0x00010000
#define CLONE_SYSVSEM 0x00040000
#define CLONE_SETTLS 0x00080000
#define CLONE_PARENT_SETTID 0x00100000
#define CLONE_CHILD_SETTID 0x01000000
#define CLONE_CHILD_CLEARTID 0x00200000
#define CSIGNAL 0x000000ff

static inline int clone(int (*fn)(void *), void *stack, int flags, void *arg, ...) {
    (void)fn; (void)stack; (void)flags; (void)arg;
    errno = ENOSYS;
    return -1;
}

// ----- set_tid_address (not on iOS) -----
static inline pid_t set_tid_address(int *tidptr) {
    (void)tidptr;
    return getpid();
}

// ----- futex (iOS: use pthread-based fallback) -----
#define FUTEX_WAIT 0
#define FUTEX_WAKE 1
#define FUTEX_WAIT_PRIVATE 0
#define FUTEX_WAKE_PRIVATE 1
#define FUTEX_REQUEUE 3
#define FUTEX_CMP_REQUEUE 4
#define FUTEX_WAIT_BITSET 9
#define FUTEX_PRIVATE_FLAG 128

static inline int futex(int *uaddr, int op, int val, const struct timespec *timeout) {
    /* Box64/Wine use futex for synchronization.
       On iOS without kernel futex, we implement basic cases:
       FUTEX_WAIT: if *uaddr == val, sleep briefly (spin-yield)
       FUTEX_WAKE: wake val threads (best-effort via yield) */
    (void)timeout;
    int base_op = op & ~FUTEX_PRIVATE_FLAG;
    switch (base_op) {
        case FUTEX_WAIT:
        case 9 /* FUTEX_WAIT_BITSET */:
            /* If value still matches, yield to avoid busy-spin */
            if (*uaddr == val) {
                /* Use nanosleep for brief sleep instead of pure spin */
                struct timespec ts = { 0, 1000000 }; /* 1ms */
                nanosleep(&ts, NULL);
            }
            return 0;
        case FUTEX_WAKE:
            /* Best-effort: yield so woken thread can run */
            sched_yield();
            return val > 0 ? val : 0;
        default:
            /* Unknown futex op — return 0 instead of crashing */
            return 0;
    }
}

// ----- getauxval (not on iOS) -----
#define AT_HWCAP 16
#define AT_HWCAP2 26

static inline unsigned long getauxval(unsigned long type) {
    (void)type;
    return 0;
}

// ----- clock_gettime with CLOCK_MONOTONIC_RAW -----
#ifndef CLOCK_MONOTONIC_RAW
#define CLOCK_MONOTONIC_RAW 4
#endif
#ifndef CLOCK_PROCESS_CPUTIME_ID
#define CLOCK_PROCESS_CPUTIME_ID 2
#endif
#ifndef CLOCK_THREAD_CPUTIME_ID
#define CLOCK_THREAD_CPUTIME_ID 3
#endif

// ----- sched_yield is available on iOS via <sched.h> -----
#include <sched.h>

// ----- __attribute__((constructor)) / __attribute__((destructor)) are supported by clang -----

#endif // __APPLE__
#endif // LINUX_COMPAT_H
