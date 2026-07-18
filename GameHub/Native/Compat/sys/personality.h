#ifndef COMPAT_SYS_PERSONALITY_H
#define COMPAT_SYS_PERSONALITY_H
/* Linux personality flags — stub for iOS */
#define PER_LINUX  0
#define PER_LINUX32 8
#define ADDR_NO_RANDOMIZE 0x0040000
#define UNAME26 0x0020000
static inline int personality(unsigned long persona) { (void)persona; return 0; }
#endif
