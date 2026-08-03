/* Box64 os-layer functions that need box64's internal structs. They are
   provided separately from ios_stubs.c because os_linux.c/os_wine.c are
   excluded from the iOS build: they call Linux `syscall()` numbers which
   are wrong on Darwin, and they drag in signals.c/threads.c. The
   self-contained os functions (GetEnv/FileExist/ReadTSC/...) live in
   ios_stubs.c; the struct-dependent entry points live here.

   Compiled with the same CFLAGS as ios_stubs.c (WITH the compat header,
   WITHOUT the -Dexit/-D_exit macros). Symbols defined here collide with
   nothing in libSystem, so ios_os.o participates in the Pass-A
   dynamic_lookup link and its symbols are subtracted from the stub gap
   list via `nm objects/*.o`. */

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <dlfcn.h>

#include "os.h"
#include "debug.h"
#include "elfloader.h"
#include "env.h"
#include "bridge.h"
#include "emu/x64int_private.h"
#include "emu/x64emu_private.h"

void EmuInt3(void *emu, void *addr)
{
    x64Int3((x64emu_t *)emu, (uintptr_t *)addr);
}

void *EmuFork(void *emu, int forktype)
{
    return x64emu_fork((x64emu_t *)emu, forktype);
}

void EmuX64Syscall(void *emu)
{
    x64Syscall((x64emu_t *)emu);
}

void EmuX64Syscall_linux(void *emu)
{
    x64Syscall_linux((x64emu_t *)emu);
}

int IsNativeCall(uintptr_t addr, int is32bits, uintptr_t *calladdress, uint16_t *retn)
{
    return isNativeCallInternal(addr, is32bits, calladdress, retn);
}

void *GetSeg43Base(void *emu)
{
    tlsdatasize_t *ptr = ((x64emu_t *)emu)->tlsdata;
    return ptr ? ptr->data : NULL;
}

void *GetSegmentBase(void *emu, uint32_t desc)
{
    if (!desc) {
        printf_log(LOG_NONE, "Warning, accessing segment NULL\n");
        return NULL;
    }
    int base = desc >> 3;
    int is_ldt = !!(desc & 4);
    if (!box64_nolibs) {
        if (!box64_is32bits && (base == 0x8))
            return GetSeg43Base(emu);
        if (box64_is32bits && (base == 0x6))
            return GetSeg43Base(emu);
    }
    if (base > 15) {
        printf_log(LOG_NONE, "Warning, accessing segment unknown 0x%x or unset\n", desc);
        return NULL;
    }
    base_segment_t *segs = is_ldt ? ((x64emu_t *)emu)->segldt
                                  : ((base > 5) ? ((x64emu_t *)emu)->seggdt : my_context->seggdt);
    return (void *)segs[base].base;
}

int IsAddrElfOrFileMapped(uintptr_t addr)
{
    return FindElfAddress(my_context, addr) || IsAddrFileMappedNoMemFD(addr);
}
