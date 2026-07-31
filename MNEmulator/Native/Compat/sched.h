#ifndef COMPAT_SCHED_H
#define COMPAT_SCHED_H

#include <stdint.h>
#include <string.h>

typedef struct {
    uint32_t bits[1024 / 32];
} cpu_set_t;

#define CPU_SETSIZE 1024
#define CPU_ZERO(cpuset) memset((cpuset), 0, sizeof(cpu_set_t))
#define CPU_SET(cpu, cpuset) ((cpuset)->bits[(cpu)/32] |= (1u << ((cpu)%32)))
#define CPU_ISSET(cpu, cpuset) ((cpuset)->bits[(cpu)/32] & (1u << ((cpu)%32)))

static inline int sched_getcpu(void) { return 0; }

#endif
