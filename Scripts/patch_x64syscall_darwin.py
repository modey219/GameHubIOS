#!/usr/bin/env python3
# Rewire box64's x64 syscall dispatch (src/emu/x64syscall.c) for Darwin numbers.
#
# The Compat/asm/unistd.h rewrite maps every __NR_* to a real Darwin SYS_*
# number (or the ENOSYS sentinel 999 for Linux-only syscalls). The unguarded
# entries of the syscallwrap[] table that referenced Linux-only numbers are
# zeroed here so dispatch falls through to the switch, which then handles them
# with working libc/my_* implementations. The two table-dispatch call sites
# (and every direct syscall(__NR_*) call) are switched to box64_raw_syscall so
# LiveContainer's interposer cannot corrupt path syscalls.
#
# Guest exit/exit_group MUST NOT reach Darwin's exit syscall (Darwin exit(1)
# would kill the host app), so those cases fake the exit and set
# emu->quit/emu->exit like the 32-bit path already does (x86syscall.c:269-274).
#
# Run from Box64Source/box64. Fails loudly if any anchor is missing so the iOS
# build can never silently ship an unpatched dispatch.
import re
import subprocess
import sys

X64SYSCALL = "src/emu/x64syscall.c"

# syscallwrap[] entries whose nats number is now 0: their guest number has no
# safe 1:1 Darwin syscall, so they fall through to the switch cases added below.
TABLE_ZERO = [
    "    [24] = {__NR_sched_yield, 0},",
    "    [60] = {__NR_exit, 1},    // Needs wrapping?",
    "    [62] = {__NR_kill, 2 },",
    "    [79] = {__NR_getcwd, 2},",
    "    [96] = {__NR_gettimeofday, 2},",
    "    [201] = {__NR_time, 1},",
    "    [217] = {__NR_getdents64, 3},",
    "    [228] = {__NR_clock_gettime, 2},",
    "    [229] = {__NR_clock_getres, 2},",
    "    [230] = {__NR_clock_nanosleep, 4},",
    "    [231] = {__NR_exit_group, 1},",
]
TABLE_ZERO_REPL = [
    "    [24] = {0, 0},    // iOS: sched_yield via compat inline",
    "    [60] = {0, 0},    // iOS: exit via emu->quit/emu->exit",
    "    [62] = {0, 0},    // iOS: kill via libc (Darwin 3-arg posix)",
    "    [79] = {0, 0},    // iOS: getcwd via box64_raw_getcwd",
    "    [96] = {0, 0},    // iOS: gettimeofday via libc",
    "    [201] = {0, 0},   // iOS: time via libc",
    "    [217] = {0, 0},   // iOS: getdents64 via my_getdents64",
    "    [228] = {0, 0},   // iOS: clock_gettime via libc",
    "    [229] = {0, 0},   // iOS: clock_getres via libc",
    "    [230] = {0, 0},   // iOS: clock_nanosleep via libc",
    "    [231] = {0, 0},   // iOS: exit_group via emu->quit/emu->exit",
]

GETDENTS_MAIN_OLD = """        #ifndef __NR_getdents
        case 78:
            {
                size_t count = R_RDX;
                nat_linux_dirent64_t *d64 = (nat_linux_dirent64_t*)alloca(count);
                ssize_t ret = syscall(__NR_getdents64, R_EDI, d64, count);
                ret = DirentFromDirent64((void*)R_RSI, d64, ret);
                R_RAX = (uint64_t)ret;
                if(ret==-1)
                    R_RAX = (uint64_t)-errno;
            }
            break;
        #endif"""
GETDENTS_MAIN_NEW = """        #ifndef __NR_getdents
        case 78:
            S_RAX = my_getdents(emu, S_EDI, (void*)R_RSI, R_RDX);
            if(S_RAX==-1)
                S_RAX = -errno;
            break;
        #endif"""

GETDENTS_LIBC_OLD = """        #ifndef __NR_getdents
        case 78:
            {
                size_t count = R_RCX;
                nat_linux_dirent64_t *d64 = (nat_linux_dirent64_t*)alloca(count);
                ssize_t ret = syscall(__NR_getdents64, R_ESI, d64, count);
                ret = DirentFromDirent64((void*)R_RDX, d64, ret);
                return ret;
            }
        #endif"""
GETDENTS_LIBC_NEW = """        #ifndef __NR_getdents
        case 78:
            return my_getdents(emu, S_RSI, (void*)R_RDX, R_RCX);
        #endif"""

# New switch cases, inserted ahead of case 0 in each dispatch switch.
# Main x64Syscall_linux switch: syscall args in RDI/RSI/RDX/R10/R8/R9.
CASES_MAIN = """        case 24: // sys_sched_yield (iOS: compat inline returns 0)
            S_RAX = sched_yield();
            break;
        case 60: // sys_exit (iOS: must NOT reach Darwin exit - would kill the app)
            emu->quit = 1;
            emu->exit = 1;
            S_RAX = R_RDI;
            break;
        case 62: // sys_kill (Darwin kill() adds a 3rd posix arg; use libc for BSD semantics)
            S_RAX = kill(S_EDI, S_ESI);
            if(S_RAX==-1)
                S_RAX = -errno;
            break;
        case 79: // sys_getcwd (getcwd macro -> box64_raw_getcwd)
            S_RAX = (uint64_t)(uintptr_t)getcwd((char*)R_RDI, (size_t)R_RSI);
            if(!S_RAX)
                S_RAX = -errno;
            break;
        case 96: // sys_gettimeofday
            S_RAX = gettimeofday((void*)R_RDI, (void*)R_RSI);
            if(S_RAX==-1)
                S_RAX = -errno;
            break;
        case 217: // sys_getdents64
            S_RAX = my_getdents64(emu, S_EDI, (void*)R_RSI, R_RDX);
            if(S_RAX==-1)
                S_RAX = -errno;
            break;
        case 228: // sys_clock_gettime
            S_RAX = clock_gettime(S_EDI, (void*)R_RSI);
            if(S_RAX==-1)
                S_RAX = -errno;
            break;
        case 229: // sys_clock_getres
            S_RAX = clock_getres(S_EDI, (void*)R_RSI);
            if(S_RAX==-1)
                S_RAX = -errno;
            break;
        case 230: // sys_clock_nanosleep
            S_RAX = clock_nanosleep(S_EDI, S_ESI, (void*)R_RDX, (void*)R_R10);
            if(S_RAX==-1)
                S_RAX = -errno;
            break;
        case 231: // sys_exit_group (iOS: must NOT reach Darwin exit)
            emu->quit = 1;
            emu->exit = 1;
            S_RAX = R_RDI;
            break;
"""

# my_syscall switch (guest libc syscall() wrapper): args in RSI/RDX/RCX/R8/R9.
CASES_LIBC = """        case 24: // sys_sched_yield (iOS: compat inline returns 0)
            return sched_yield();
        case 60: // sys_exit (iOS: must NOT reach Darwin exit)
            emu->quit = 1;
            emu->exit = 1;
            return S_RSI;
        case 62: // sys_kill (libc keeps Darwin's 3rd posix arg = 0)
            return kill(S_RSI, S_RDX);
        case 79: // sys_getcwd (getcwd macro -> box64_raw_getcwd)
            {
                char *ret = getcwd((char*)R_RSI, R_RDX);
                return ret ? (intptr_t)ret : -1;
            }
        case 96: // sys_gettimeofday
            return gettimeofday((void*)R_RSI, (void*)R_RDX);
        case 217: // sys_getdents64
            return my_getdents64(emu, S_RSI, (void*)R_RDX, R_RCX);
        case 228: // sys_clock_gettime
            return clock_gettime(S_RSI, (void*)R_RDX);
        case 229: // sys_clock_getres
            return clock_getres(S_RSI, (void*)R_RDX);
        case 230: // sys_clock_nanosleep
            return clock_nanosleep(S_RSI, S_RDX, (void*)R_RCX, (void*)R_R8);
        case 231: // sys_exit_group (iOS: must NOT reach Darwin exit)
            emu->quit = 1;
            emu->exit = 1;
            return S_RSI;
"""

DECLS = """int32_t my_execve(x64emu_t* emu, const char* path, char* const argv[], char* const envp[]);
ssize_t my_getdents(x64emu_t *emu, int fd, void *buf, size_t count);
ssize_t my_getdents64(x64emu_t *emu, int fd, void *buf, size_t count);"""

MAIN_CASE0 = "        case 0:  // sys_read\n            S_RAX = read(S_EDI, (void*)R_RSI, (size_t)R_RDX);"
LIBC_CASE0 = "        case 0:  // sys_read\n            return read(R_ESI, (void*)R_RDX, R_ECX);"


def apply(path):
    src = open(path, encoding="utf-8").read()

    if "iOS: sched_yield via compat inline" in src:
        print("%s: leftover Darwin dispatch patch found (stale tree); restoring pristine file from git" % path)
        r = subprocess.run(["git", "checkout", "--", path], capture_output=True)
        if r.returncode != 0:
            print("ERROR: git checkout -- %s failed (%s); refusing to build a poisoned tree" % (path, r.stderr.decode(errors="replace").strip()))
            sys.exit(1)
        src = open(path, encoding="utf-8").read()

    # 1. Zero the unsafe table entries.
    for old, new in zip(TABLE_ZERO, TABLE_ZERO_REPL):
        if src.find(old) < 0:
            print("ERROR: table entry anchor not found: %s" % old.strip())
            sys.exit(1)
        src = src.replace(old, new, 1)

    # 2. getdents case bodies -> my_getdents (removes the __NR_getdents64 refs).
    if src.find(GETDENTS_MAIN_OLD) < 0:
        print("ERROR: main getdents case 78 anchor not found")
        sys.exit(1)
    src = src.replace(GETDENTS_MAIN_OLD, GETDENTS_MAIN_NEW, 1)
    if src.find(GETDENTS_LIBC_OLD) < 0:
        print("ERROR: libc getdents case 78 anchor not found")
        sys.exit(1)
    src = src.replace(GETDENTS_LIBC_OLD, GETDENTS_LIBC_NEW, 1)

    # 3. Route every raw trap through box64_raw_syscall (class-bit encoding).
    src = src.replace("syscall(sc", "box64_raw_syscall(sc")
    src = src.replace("syscall(__NR_", "box64_raw_syscall(__NR_")

    # 4. Declare the getdents helpers.
    src = src.replace(DECLS, DECLS, 1)  # no-op guard; replaced below
    src = src.replace(
        "int32_t my_execve(x64emu_t* emu, const char* path, char* const argv[], char* const envp[]);",
        DECLS, 1)

    # 5. Insert the new switch cases ahead of case 0 in both dispatch switches.
    if src.find(MAIN_CASE0) < 0:
        print("ERROR: main switch case 0 anchor not found")
        sys.exit(1)
    src = src.replace(MAIN_CASE0, CASES_MAIN + MAIN_CASE0, 1)
    if src.find(LIBC_CASE0) < 0:
        print("ERROR: libc switch case 0 anchor not found")
        sys.exit(1)
    src = src.replace(LIBC_CASE0, CASES_LIBC + LIBC_CASE0, 1)

    open(path, "w", encoding="utf-8").write(src)
    print("Patched %s: Darwin dispatch (raw traps, exit/kill/getcwd/time/getdents/clock cases)" % path)


def verify():
    src = open(X64SYSCALL, encoding="utf-8").read()
    ok = True
    checks = [
        ("[24] = {0, 0},", "sched_yield table zeroed"),
        ("[60] = {0, 0},", "exit table zeroed"),
        ("[62] = {0, 0},", "kill table zeroed"),
        ("[79] = {0, 0},", "getcwd table zeroed"),
        ("[96] = {0, 0},", "gettimeofday table zeroed"),
        ("[201] = {0, 0},", "time table zeroed"),
        ("[217] = {0, 0},", "getdents64 table zeroed"),
        ("[228] = {0, 0},", "clock_gettime table zeroed"),
        ("[229] = {0, 0},", "clock_getres table zeroed"),
        ("[230] = {0, 0},", "clock_nanosleep table zeroed"),
        ("[231] = {0, 0},", "exit_group table zeroed"),
        ("box64_raw_syscall(sc", "table dispatch uses raw trap"),
        ("box64_raw_syscall(__NR_openat", "openat direct call uses raw trap"),
        ("my_getdents(emu, S_EDI", "main getdents -> my_getdents"),
        ("my_getdents(emu, S_RSI", "libc getdents -> my_getdents"),
        ("my_getdents64(emu, S_EDI", "main getdents64 case inserted"),
        ("case 231: // sys_exit_group", "exit_group case inserted"),
        ("case 79: // sys_getcwd", "getcwd case inserted"),
        ("case 96: // sys_gettimeofday", "gettimeofday case inserted"),
        ("case 228: // sys_clock_gettime", "clock_gettime case inserted"),
        ("ssize_t my_getdents64(x64emu_t *emu", "getdents declarations"),
    ]
    for needle, what in checks:
        if needle in src:
            print("  OK    %s" % what)
        else:
            print("  MISS  %s (needle=%s)" % (what, needle))
            ok = False
    # Must NOT leave any direct libc syscall(...) call (they would hit the
    # interposer or a bare-number trap). Negative lookbehind so the legit
    # box64_raw_syscall(...) / my_syscall(...) identifiers do not match.
    for bad in ("syscall(sc", "syscall(__NR_"):
        if re.search(r"(?<![A-Za-z0-9_])" + re.escape(bad), src):
            print("  BAD   leftover direct libc syscall: %s" % bad)
            ok = False
    if "__NR_getdents64" in src:
        print("  BAD   __NR_getdents64 still referenced (would not compile)")
        ok = False
    if not ok:
        print("ERROR: Darwin dispatch patch verification failed; aborting")
        sys.exit(1)
    print("Patch verification passed: Darwin x64 syscall dispatch wired")


apply(X64SYSCALL)
verify()
print("Darwin x64 syscall dispatch patch installed and verified")
