#ifndef _COMPAT_ENDIAN_H
#define _COMPAT_ENDIAN_H
#include <machine/endian.h>
#ifndef __BYTE_ORDER
#define __BYTE_ORDER __BYTE_ORDER__
#endif
#ifndef __LITTLE_ENDIAN
#define __LITTLE_ENDIAN __ORDER_LITTLE_ENDIAN__
#endif
#ifndef __BIG_ENDIAN
#define __BIG_ENDIAN __ORDER_BIG_ENDIAN__
#endif
#ifndef htobe32
#define htobe32(x) __DARWIN_OSSwapInt32(x)
#define be32toh(x) __DARWIN_OSSwapInt32(x)
#define htole32(x) (x)
#define le32toh(x) (x)
#define htobe64(x) __DARWIN_OSSwapInt64(x)
#define be64toh(x) __DARWIN_OSSwapInt64(x)
#define htole64(x) (x)
#define le64toh(x) (x)
#endif
#endif
