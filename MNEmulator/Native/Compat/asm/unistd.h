#ifndef _COMPAT_ASM_UNISTD_H
#define _COMPAT_ASM_UNISTD_H
/*
 * Darwin (xnu) syscall numbers for box64's native syscall dispatch.
 *
 * Every __NR_* defined here MUST equal the real Darwin SYS_* number (so that
 * box64_raw_syscall(__NR_X, ...) traps into the raw arm64 "svc" layer with a
 * valid, 1:1-ABI-compatible syscall) or the sentinel 999 (Linux-only syscall
 * with no Darwin equivalent: box64_raw_syscall(999) reliably returns -ENOSYS
 * without hanging, because 999|0x2000000 is a valid unix-class trap number the
 * kernel rejects with ENOSYS).
 *
 * Deliberately OMITTED __NR_* (must stay undefined so the existing
 * #ifndef __NR_X guards in x64syscall.c compile in the correct libc/my_*
 * implementation for that syscall):
 *   exit, exit_group          -> handled by switch case via emu->quit/emu->exit
 *   getcwd                    -> switch case uses box64_raw_getcwd
 *   getdents, getdents64      -> switch case uses my_getdents64
 *   pipe                      -> switch case uses box64_raw_pipe
 *   pause                     -> libc pause fallback
 *   time                      -> libc time fallback
 *   stat/fstat/lstat/mmap/mprotect/munmap/read/write/open/close
 *                              -> switch case my_* implementations
 *   rt_sigaction, sigaltstack, readlink, uname, sigpending
 *                              -> switch case my_* / stubs
 *   epoll_*, inotify_*, eventfd, signalfd, timerfd_*, futex_waitv,
 *   copy_file_range, preadv2, pwritev2, statx, io_uring_*, pidfd_open,
 *   close_range, faccessat2, landlock_*  -> guarded my_* stubs
 */
#define __NR_ioctl 54          /* Darwin: 54 ioctl */
#define __NR_munmap 73         /* Darwin: 73 munmap (dispatch my_munmap) */
#define __NR_madvise 75        /* Darwin: 75 madvise */
#define __NR_mincore 78        /* Darwin: 78 mincore */
#define __NR_dup 41            /* Darwin: 41 dup */
#define __NR_dup2 90           /* Darwin: 90 dup2 */
#define __NR_poll 230          /* Darwin: 230 poll */
#define __NR_lseek 199         /* Darwin: 199 lseek */
#define __NR_pread64 153       /* Darwin: 153 pread */
#define __NR_pwrite64 154      /* Darwin: 154 pwrite */
#define __NR_readv 120         /* Darwin: 120 readv */
#define __NR_writev 121        /* Darwin: 121 writev */
#define __NR_access 33         /* Darwin: 33 access */
#define __NR_select 93         /* Darwin: 93 select */
#define __NR_getitimer 86      /* Darwin: 86 getitimer */
#define __NR_setitimer 83      /* Darwin: 83 setitimer */
#define __NR_getpid 20         /* Darwin: 20 getpid */
#define __NR_socket 97         /* Darwin: 97 socket */
#define __NR_connect 98        /* Darwin: 98 connect */
#define __NR_accept 30         /* Darwin: 30 accept */
#define __NR_sendto 133        /* Darwin: 133 sendto */
#define __NR_recvfrom 29       /* Darwin: 29 recvfrom */
#define __NR_sendmsg 28        /* Darwin: 28 sendmsg */
#define __NR_recvmsg 27        /* Darwin: 27 recvmsg */
#define __NR_shutdown 134      /* Darwin: 134 shutdown */
#define __NR_bind 104          /* Darwin: 104 bind */
#define __NR_listen 106        /* Darwin: 106 listen */
#define __NR_getsockname 32    /* Darwin: 32 getsockname */
#define __NR_getpeername 31    /* Darwin: 31 getpeername */
#define __NR_socketpair 135    /* Darwin: 135 socketpair */
#define __NR_setsockopt 105    /* Darwin: 105 setsockopt */
#define __NR_getsockopt 118    /* Darwin: 118 getsockopt */
#define __NR_wait4 7           /* Darwin: 7 wait4 */
#define __NR_semget 255        /* Darwin: 255 semget */
#define __NR_semop 256         /* Darwin: 256 semop */
#define __NR_semctl 254        /* Darwin: 254 semctl */
#define __NR_flock 131         /* Darwin: 131 flock */
#define __NR_fsync 95          /* Darwin: 95 fsync */
#define __NR_ftruncate 201     /* Darwin: 201 ftruncate */
#define __NR_chdir 12          /* Darwin: 12 chdir */
#define __NR_rename 128        /* Darwin: 128 rename */
#define __NR_mkdir 136         /* Darwin: 136 mkdir */
#define __NR_rmdir 137         /* Darwin: 137 rmdir */
#define __NR_unlink 10         /* Darwin: 10 unlink */
#define __NR_symlink 57        /* Darwin: 57 symlink */
#define __NR_chmod 15          /* Darwin: 15 chmod */
#define __NR_fchmod 124        /* Darwin: 124 fchmod */
#define __NR_fchown 123        /* Darwin: 123 fchown */
#define __NR_umask 60          /* Darwin: 60 umask */
#define __NR_getrlimit 194     /* Darwin: 194 getrlimit */
#define __NR_setrlimit 195     /* Darwin: 195 setrlimit */
#define __NR_getrusage 117     /* Darwin: 117 getrusage */
#define __NR_ptrace 26         /* Darwin: 26 ptrace */
#define __NR_getuid 24         /* Darwin: 24 getuid */
#define __NR_getgid 47         /* Darwin: 47 getgid */
#define __NR_setuid 23         /* Darwin: 23 setuid */
#define __NR_setgid 181        /* Darwin: 181 setgid */
#define __NR_geteuid 25        /* Darwin: 25 geteuid */
#define __NR_getegid 43        /* Darwin: 43 getegid */
#define __NR_setpgid 82        /* Darwin: 82 setpgid */
#define __NR_getppid 39        /* Darwin: 39 getppid */
#define __NR_setsid 147        /* Darwin: 147 setsid */
#define __NR_setreuid 126      /* Darwin: 126 setreuid */
#define __NR_setregid 127      /* Darwin: 127 setregid */
#define __NR_getgroups 79      /* Darwin: 79 getgroups */
#define __NR_setgroups 80      /* Darwin: 80 setgroups */
#define __NR_getpgid 151       /* Darwin: 151 getpgid */
#define __NR_getsid 310        /* Darwin: 310 getsid */
#define __NR_mknod 14          /* Darwin: 14 mknod */
#define __NR_getpriority 100   /* Darwin: 100 getpriority */
#define __NR_setpriority 96    /* Darwin: 96 setpriority */
#define __NR_mlock 203         /* Darwin: 203 mlock */
#define __NR_munlock 204       /* Darwin: 204 munlock */
#define __NR_chroot 61         /* Darwin: 61 chroot */
#define __NR_gettid 286        /* Darwin: 286 gettid */
#define __NR_openat 463        /* Darwin: 463 openat */
#define __NR_mkdirat 475       /* Darwin: 475 mkdirat */
#define __NR_fchownat 468      /* Darwin: 468 fchownat */
#define __NR_unlinkat 472      /* Darwin: 472 unlinkat */
#define __NR_renameat 465      /* Darwin: 465 renameat */
#define __NR_symlinkat 474     /* Darwin: 474 symlinkat */
#define __NR_fchmodat 467      /* Darwin: 467 fchmodat */
#define __NR_faccessat 466     /* Darwin: 466 faccessat */

/* Linux-only syscalls with no Darwin equivalent -> sentinel (ENOSYS). */
#define __NR_brk 999
#define __NR_rt_sigprocmask 999
#define __NR_rt_sigreturn 999
#define __NR_sched_yield 999
#define __NR_nanosleep 999
#define __NR_sendfile 999
#define __NR_gettimeofday 999
#define __NR_sysinfo 999
#define __NR_times 999
#define __NR_setresuid 999
#define __NR_getresuid 999
#define __NR_setresgid 999
#define __NR_getresgid 999
#define __NR_setfsuid 999
#define __NR_setfsgid 999
#define __NR_capget 999
#define __NR_capset 999
#define __NR_rt_sigpending 999
#define __NR_rt_sigtimedwait 999
#define __NR_statfs 999
#define __NR_fstatfs 999
#define __NR_sched_setparam 999
#define __NR_sched_getparam 999
#define __NR_sched_setscheduler 999
#define __NR_sched_getscheduler 999
#define __NR_sched_get_priority_max 999
#define __NR_sched_get_priority_min 999
#define __NR_sched_rr_get_interval 999
#define __NR_pivot_root 999
#define __NR_prctl 999
#define __NR_mount 999
#define __NR_listxattr 999
#define __NR_llistxattr 999
#define __NR_flistxattr 999
#define __NR_tkill 999
#define __NR_futex 999
#define __NR_clone 999
#define __NR_sched_setaffinity 999
#define __NR_sched_getaffinity 999
#define __NR_io_setup 999
#define __NR_io_destroy 999
#define __NR_io_getevents 999
#define __NR_io_submit 999
#define __NR_io_cancel 999
#define __NR_lookup_dcookie 999
#define __NR_set_tid_address 999
#define __NR_semtimedop 999
#define __NR_fadvise64 999
#define __NR_clock_gettime 999
#define __NR_clock_getres 999
#define __NR_clock_nanosleep 999
#define __NR_tgkill 999
#define __NR_mbind 999
#define __NR_set_mempolicy 999
#define __NR_get_mempolicy 999
#define __NR_waitid 999
#define __NR_ioprio_set 999
#define __NR_ioprio_get 999
#define __NR_inotify_add_watch 999
#define __NR_inotify_rm_watch 999
#define __NR_inotify_init1 999
#define __NR_pselect6 999
#define __NR_unshare 999
#define __NR_set_robust_list 999
#define __NR_get_robust_list 999
#define __NR_utimensat 999
#define __NR_timerfd_create 999
#define __NR_fallocate 999
#define __NR_timerfd_settime 999
#define __NR_accept4 999
#define __NR_signalfd4 999
#define __NR_eventfd2 999
#define __NR_dup3 999
#define __NR_pipe2 999
#define __NR_rt_tgsigqueueinfo 999
#define __NR_perf_event_open 999
#define __NR_prlimit64 999
#define __NR_getcpu 999
#define __NR_kcmp 999
#define __NR_sched_setattr 999
#define __NR_sched_getattr 999
#define __NR_renameat2 999
#define __NR_set_robust_list 999
#define __NR_get_robust_list 999
#define __NR_getrandom 999
#define __NR_memfd_create 999
#define __NR_membarrier 999
#define __NR_fork 999
#define __NR_socketcall 999 /* x86syscall.c: #ifndef __NR_socketcall -> include <linux/net.h> (absent on iOS) */
#endif
