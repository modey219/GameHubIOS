#ifndef _COMPAT_ASM_BYTEORDER_H
#define _COMPAT_ASM_BYTEORDER_H
#include <stdint.h>
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#include <endian.h>
#else
#include <machine/endian.h>
#endif
#endif
