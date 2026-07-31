#ifndef _COMPAT_LINUX_SYSCTL_H
#define _COMPAT_LINUX_SYSCTL_H
#include <stdint.h>
struct __sysctl_args {
    int *name;
    int nlen;
    void *oldval;
    size_t *oldlenp;
    void *newval;
    size_t newlen;
    unsigned int __unused[4];
};
#define CTL_DEV 6
#define CTL_MAXNAME 24
#endif
