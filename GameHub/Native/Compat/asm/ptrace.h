#ifndef _COMPAT_ASM_PTRACE_H
#define _COMPAT_ASM_PTRACE_H
#include <stdint.h>
struct user_regs_struct {
    uint64_t r15, r14, r13, r12;
    uint64_t rbp, rbx;
    uint64_t r11, r10, r9, r8;
    uint64_t rax, rcx, rdx, rsi, rdi;
    uint64_t orig_rax, rip, cs;
    uint64_t eflags, rsp, ss;
    uint64_t fs_base, gs_base;
    uint64_t ds, es, fs, gs;
};
#endif
