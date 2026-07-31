#ifndef _COMPAT_LINUX_PERSONALITY_H
#define _COMPAT_LINUX_PERSONALITY_H
#define PER_LINUX 0x0000
#define PER_LINUX_32BIT 0x0008
#define PER_SVR4 0x0003
#define PER_SVR3 0x0002
#define PER_SCOSVR3 0x0007
#define PER_WYSEV386 0x0009
#define PER_ISCR4 0x0005
#define PER_BSD 0x0006
#define PER_SOLARIS 0x006E
#define PER_SUNOS 0x0073
#define PER_OSF4 0x001B
#define PER_OSF 0x000F
#define PER_UW7 0x00A4
#define PER_MASK 0x00FF
static inline int personality(unsigned long p){(void)p;return -1;}
#endif
