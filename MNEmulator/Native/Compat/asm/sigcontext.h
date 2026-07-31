#ifndef _COMPAT_ASM_SIGCONTEXT_H
#define _COMPAT_ASM_SIGCONTEXT_H
#include <stdint.h>
struct _fpstate { uint16_t cwd; uint16_t swd; uint16_t ftw; uint16_t fop; uint64_t rip; uint64_t rdp; uint32_t mxcsr; uint32_t mxcr_mask; struct { uint16_t significand[4]; uint16_t exponent; } _st[8]; struct { uint32_t element[2]; } _xmm[16]; uint64_t padding[12]; };
struct sigcontext { uint64_t r8; uint64_t r9; uint64_t r10; uint64_t r11; uint64_t r12; uint64_t r13; uint64_t r14; uint64_t r15; uint64_t rdi; uint64_t rsi; uint64_t rbp; uint64_t rbx; uint64_t rdx; uint64_t rax; uint64_t rcx; uint64_t rsp; uint64_t rip; uint64_t eflags; unsigned short cs; unsigned short gs; unsigned short fs; unsigned short __pad0; uint64_t err; uint64_t trapno; uint64_t oldmask; uint64_t cr2; struct _fpstate *fpstate; uint64_t __reserved1[8]; };
#endif
