#ifndef LINUX_TYPES_H
#define LINUX_TYPES_H

#include <stdint.h>
#include <stddef.h>

typedef int8_t __s8;
typedef uint8_t __u8;
typedef int16_t __s16;
typedef uint16_t __u16;
typedef int32_t __s32;
typedef uint32_t __u32;
typedef int64_t __s64;
typedef uint64_t __u64;

typedef __u32 linux_uid_t;
typedef __u32 linux_gid_t;
typedef __s32 linux_pid_t;
typedef __u32 linux_mode_t;
typedef __u64 linux_dev_t;
typedef __u64 linux_ino_t;
typedef __s64 linux_off_t;
typedef __s64 linux_loff_t;
typedef __s64 linux_time_t;
typedef __s64 linux_clock_t;
typedef __u64 linux_size_t;
typedef __s64 linux_ssize_t;
typedef __u64 linux_addr_t;
typedef __s64 linux_blksize_t;
typedef __s64 linux_blkcnt_t;

struct linux_timespec {
    linux_time_t tv_sec;
    long tv_nsec;
};

struct linux_timeval {
    linux_time_t tv_sec;
    long tv_usec;
};

struct linux_stat {
    __u64 st_dev;
    __u64 st_ino;
    __u64 st_nlink;
    __u32 st_mode;
    __u32 st_uid;
    __u32 st_gid;
    __u32 __pad0;
    __u64 st_rdev;
    __u64 st_size;
    __u64 st_blksize;
    __u64 st_blocks;
    struct linux_timespec st_atim;
    struct linux_timespec st_mtim;
    struct linux_timespec st_ctim;
    __s64 __reserved[3];
};

struct linux_sockaddr {
    unsigned short sa_family;
    char sa_data[14];
};

struct linux_sockaddr_in {
    unsigned short sin_family;
    uint16_t sin_port;
    uint32_t sin_addr;
    char sin_zero[8];
};

struct linux_sockaddr_in6 {
    unsigned short sin6_family;
    uint16_t sin6_port;
    uint32_t sin6_flowinfo;
    uint8_t sin6_addr[16];
    uint32_t sin6_scope_id;
};

struct linux_pollfd {
    int fd;
    short events;
    short revents;
};

struct linux_rlimit {
    __u64 rlim_cur;
    __u64 rlim_max;
};

struct linux_utsname {
    char sysname[65];
    char nodename[65];
    char release[65];
    char version[65];
    char machine[65];
    char domainname[65];
};

struct linux_epoll_event {
    uint32_t events;
    int fd;
};

struct linux_sigaction {
    void (*sa_handler)(int);
    unsigned long sa_flags;
    void (*sa_restorer)(void);
    __u64 sa_mask;
};

struct linux_flock {
    __s16 l_type;
    __s16 l_whence;
    __s64 l_start;
    __s64 l_len;
    __s32 l_pid;
};

#define LINUX_PATH_MAX 4096
#define LINUX_OPEN_MAX 1024
#define LINUX_ARG_MAX 131072
#define LINUX_ENV_MAX 131072

#define LINUX_O_RDONLY    0x0000
#define LINUX_O_WRONLY    0x0001
#define LINUX_O_RDWR      0x0002
#define LINUX_O_CREAT     0x0040
#define LINUX_O_TRUNC     0x0200
#define LINUX_O_APPEND    0x0400
#define LINUX_O_NONBLOCK  0x0800
#define LINUX_O_DIRECTORY 0x10000
#define LINUX_O_CLOEXEC   0x80000

#define LINUX PROT_NONE   0
#define LINUX PROT_READ   1
#define LINUX PROT_WRITE  2
#define LINUX PROT_EXEC   4

#define LINUX_MAP_SHARED    0x01
#define LINUX_MAP_PRIVATE   0x02
#define LINUX_MAP_ANONYMOUS 0x20
#define LINUX_MAP_FIXED     0x10
#define LINUX_MAP_JIT       0x0800

#define LINUX_MCL_CURRENT 1
#define LINUX_MCL_FUTURE  2

#define LINUX_SIG_DFL ((void (*)(int))0)
#define LINUX_SIG_IGN ((void (*)(int))1)

#define LINUX_SA_RESTART  0x10000000
#define LINUX_SA_SIGINFO  0x00000004
#define LINUX_SA_RESTORER 0x04000000

#define LINUX_SIGINT  2
#define LINUX_SIGILL  4
#define LINUX_SIGFPE  8
#define LINUX_SIGSEGV 11
#define LINUX_SIGTERM 15
#define LINUX_SIGCHLD 17
#define LINUX_SIGUSR1 10
#define LINUX_SIGUSR2 12

#define LINUX_WNOHANG   1
#define LINUX_WUNTRACED 2

#define LINUX_RLIMIT_NOFILE 7

#define LINUX_CLOCK_REALTIME  0
#define LINUX_CLOCK_MONOTONIC 1

#define LINUX_AF_INET   2
#define LINUX_AF_INET6  10
#define LINUX_SOCK_STREAM 1
#define LINUX_SOCK_DGRAM  2

#define LINUX_SOL_SOCKET  1
#define LINUX_SO_REUSEADDR 2

#define LINUX_EPOLLIN  1
#define LINUX_EPOLLOUT 4
#define LINUX_EPOLLERR 8
#define LINUX_EPOLLHUP 16

#define LINUX_F_DUPFD 0
#define LINUX_F_GETFD 1
#define LINUX_F_SETFD 2
#define LINUX_F_GETFL 3
#define LINUX_F_SETFL 4
#define LINUX_F_SETLK 5
#define LINUX_F_SETLKW 6
#define LINUX_F_GETLK 7

#define LINUX_SEEK_SET 0
#define LINUX_SEEK_CUR 1
#define LINUX_SEEK_END 2

#define LINUX_DT_UNKNOWN 0
#define LINUX_DT_DIR     4
#define LINUX_DT_REG     8

#define LINUX_GETDENTS_BUF_SIZE 4096

struct linux_dirent {
    __u64 d_ino;
    __s64 d_off;
    unsigned short d_reclen;
    unsigned char d_type;
    char d_name[];
};

#endif
