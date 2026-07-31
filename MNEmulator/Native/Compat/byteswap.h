#ifndef _COMPAT_BYTESWAP_H
#define _COMPAT_BYTESWAP_H
#include <stdint.h>
static inline uint16_t __builtin_bswap16(uint16_t x){return (x>>8)|(x<<8);}
#define bswap_16(x) __builtin_bswap16(x)
#define bswap_32(x) __builtin_bswap32(x)
#define bswap_64(x) __builtin_bswap64(x)
#endif
