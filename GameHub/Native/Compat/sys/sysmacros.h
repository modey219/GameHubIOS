#ifndef COMPAT_SYS_SYSMACROS_H
#define COMPAT_SYS_SYSMACROS_H
/* Stub: major/minor macros not needed on iOS */
#include <sys/types.h>
#ifndef major
#define major(x) ((int)((x) >> 8))
#define minor(x) ((int)((x) & 0xff))
#endif
#endif
