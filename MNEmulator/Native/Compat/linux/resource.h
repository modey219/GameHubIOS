#ifndef _COMPAT_LINUX_RESOURCE_H
#define _COMPAT_LINUX_RESOURCE_H
#include <stdint.h>
struct rlimit { unsigned long rlim_cur; unsigned long rlim_max; };
struct rusage { struct timeval ru_utime; struct timeval ru_stime; long ru_maxrss; long ru_ixrss; long ru_idrss; long ru_isrss; long ru_minflt; long ru_majflt; long ru_nswap; long ru_inblock; long ru_oublock; long ru_msgsnd; long ru_msgrcv; long ru_nsignals; long ru_nvcsw; long ru_nivcsw; };
#define RLIMIT_CPU 0
#define RLIMIT_FSIZE 1
#define RLIMIT_DATA 2
#define RLIMIT_STACK 3
#define RLIMIT_CORE 4
#define RLIMIT_RSS 5
#define RLIMIT_NPROC 6
#define RLIMIT_NOFILE 7
#define RLIMIT_MEMLOCK 8
#define RLIMIT_AS 9
#define RLIMITLOCKS 10
#define RLIMIT_SIGPENDING 11
#define RLIMIT_MSGQUEUE 12
#define RLIMIT_NICE 13
#define RLIMIT_RTPRIO 14
#define RLIMIT_RTTIME 15
#define RLIMIT_NLIMITS 16
#define RLIM_INFINITY (~0UL)
#define RUSAGE_SELF 0
#define RUSAGE_CHILDREN -1
#define RUSAGE_BOTH -2
static inline int getrlimit(int resource, struct rlimit *rlim) {
    (void)resource; if(rlim) { rlim->rlim_cur=RLIM_INFINITY; rlim->rlim_max=RLIM_INFINITY; }
    return 0;
}
static inline int setrlimit(int resource, const struct rlimit *rlim) {
    (void)resource; (void)rlim; return 0;
}
static inline int getrusage(int who, struct rusage *usage) {
    (void)who; if(usage) { memset(usage, 0, sizeof(*usage)); }
    return 0;
}
#endif
