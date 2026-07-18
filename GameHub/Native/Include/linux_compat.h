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
#include <pthread.h>
#include <dirent.h>

// ----- epoll (not on iOS, use poll fallback) -----
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

static inline int epoll_create(int size) {
    (void)size;
    return -1;
}

static inline int epoll_create1(int flags) {
    (void)flags;
    return -1;
}

static inline int epoll_ctl(int epfd, int op, int fd, struct epoll_event *event) {
    (void)epfd; (void)op; (void)fd; (void)event;
    errno = ENOSYS;
    return -1;
}

static inline int epoll_wait(int epfd, struct epoll_event *events, int maxevents, int timeout) {
    (void)epfd; (void)events; (void)maxevents; (void)timeout;
    errno = ENOSYS;
    return -1;
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

// ----- eventfd (not on iOS) -----
#define EFD_NONBLOCK 0x800
#define EFD_CLOEXEC 0x80000
#define EFD_SEMAPHORE 0x001

static inline int eventfd(unsigned int initval, int flags) {
    (void)initval; (void)flags;
    errno = ENOSYS;
    return -1;
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
#define S_ISVTX 0x0002
#endif
#ifndef S_ISGID
#define S_ISGID 0x0002
#endif
#ifndef S_ISUID
#define S_ISUID 0x0004
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
#define CLONE_CHILD_SETTID 0x00200000
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

// ----- futex (not on iOS, use pthread equivalents) -----
#define FUTEX_WAIT 0
#define FUTEX_WAKE 1
#define FUTEX_WAIT_PRIVATE 0
#define FUTEX_WAKE_PRIVATE 1

static inline int futex(int *uaddr, int op, int val, const struct timespec *timeout) {
    (void)uaddr; (void)op; (void)val; (void)timeout;
    errno = ENOSYS;
    return -1;
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
