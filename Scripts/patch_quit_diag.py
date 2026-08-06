#!/usr/bin/env python3
# Instrument box64's emulation lifecycle to pinpoint when emu->quit gets set
# before the main DynaRun (root cause of "Emulation finished, EAX=0" with zero
# guest syscalls / zero guest output / no exit breadcrumb).
#
# Symptom: emulate() prints "Start x64emu on Main" then instantly
# "Emulation finished, EAX=0". Run() (src/emu/x64run.c) bails at its very first
# `if(emu->quit) return 0;` — the interpreter never decodes a single guest
# instruction, so wine64's _start never runs. This adds [iOS] breadcrumbs at:
#   * NewX64Emu creation            (quit should be 0)
#   * after RunDeferredElfInit      (quit must still be 0)
#   * EmuRun() entry                (both the main run and every DynaCall)
#   * Run() quit-bail               (the smoking gun, with RIP/old_ip)
#   * emulate() right before/after DynaRun
#
# Run from Box64Source/box64 (CI clones ptitSeb/box64 @ BOX64_REF then runs
# this via .github/workflows/build.yml). Idempotent: detects a stale patch and
# restores pristine files via git before re-applying. Fails loudly if an anchor
# is missing so the iOS build can never silently ship an un-instrumented run.
import re
import subprocess
import sys

CORE = "src/core.c"
XRUN = "src/emu/x64run.c"
DYNAREC = "src/dynarec/dynarec.c"

# ---------------------------------------------------------------- core.c ----
CORE_CREATE_OLD = """    // init x86_64 emu
    x64emu_t *emu = NewX64Emu(my_context, my_context->ep, (uintptr_t)my_context->stack, my_context->stacksz, 0);"""
CORE_CREATE_NEW = """    // init x86_64 emu
    x64emu_t *emu = NewX64Emu(my_context, my_context->ep, (uintptr_t)my_context->stack, my_context->stacksz, 0);
    printf_log(LOG_INFO, "[iOS] emu-created: quit=%d exit=%d RIP=0x%llx RSP=0x%llx\\n",
        emu->quit, emu->exit, (unsigned long long)R_RIP, (unsigned long long)R_RSP);"""

CORE_INIT_OLD = """    // deferred init
    setupTraceInit();
    RunDeferredElfInit(emu);"""
CORE_INIT_NEW = """    // deferred init
    setupTraceInit();
    RunDeferredElfInit(emu);
    printf_log(LOG_INFO, "[iOS] post-deferred-init: quit=%d exit=%d RIP=0x%llx\\n",
        emu->quit, emu->exit, (unsigned long long)R_RIP);"""

CORE_RUN_OLD = """        if(!box64_hasinterp) SetRDX(emu, 0);
    }
    DynaRun(emu);"""
CORE_RUN_NEW = """        if(!box64_hasinterp) SetRDX(emu, 0);
    }
    printf_log(LOG_INFO, "[iOS] emulate: pre-DynaRun quit=%d exit=%d RIP=0x%llx RSP=0x%llx ep=0x%llx bridge=0x%llx hasinterp=%d\\n",
        emu->quit, emu->exit, (unsigned long long)R_RIP, (unsigned long long)R_RSP,
        (unsigned long long)my_context->ep, (unsigned long long)my_context->exit_bridge, box64_hasinterp);
    DynaRun(emu);
    printf_log(LOG_INFO, "[iOS] emulate: post-DynaRun EAX=0x%llx quit=%d exit=%d RIP=0x%llx RSP=0x%llx\\n",
        (unsigned long long)GetEAX(emu), emu->quit, emu->exit,
        (unsigned long long)R_RIP, (unsigned long long)R_RSP);"""

# ---------------------------------------------------------------- x64run.c --
XRUN_OLD = """    if(emu->quit)
        return 0;"""
XRUN_NEW = """    if(emu->quit) {
        printf_log(LOG_INFO, "[iOS] Run-bail: quit=%d exit=%d RIP=0x%llx old_ip=0x%llx is32bits=%d\\n",
            emu->quit, emu->exit, (unsigned long long)R_RIP,
            (unsigned long long)emu->old_ip, is32bits);
        return 0;
    }"""

# --------------------------------------------------------------- dynarec.c --
DYN_OLD = """    int is32bits = (emu->segs[_CS]==0x23);
    while(!(emu->quit)) {"""
DYN_NEW = """    int is32bits = (emu->segs[_CS]==0x23);
    printf_log(LOG_INFO, "[iOS] EmuRun: entry quit=%d exit=%d RIP=0x%llx use_dynarec=%d no_alt=%d\\n",
        emu->quit, emu->exit, (unsigned long long)R_RIP, use_dynarec, no_alt);
    while(!(emu->quit)) {"""

# Per-file stale-patch marker (the string each patch injects).
FILE_MARKER = {
    CORE: "iOS] emulate: pre-DynaRun",
    XRUN: "iOS] Run-bail",
    DYNAREC: "iOS] EmuRun: entry",
}


def restore(path):
    print("%s: leftover quit-diag patch found (stale tree); restoring pristine file from git" % path)
    r = subprocess.run(["git", "checkout", "--", path], capture_output=True)
    if r.returncode != 0:
        print("ERROR: git checkout -- %s failed (%s); refusing to build a poisoned tree" % (path, r.stderr.decode(errors="replace").strip()))
        sys.exit(1)


def apply_pair(path, old, new):
    src = open(path, encoding="utf-8").read()
    if old not in src:
        print("ERROR: anchor not found in %s:\n%s" % (path, old.strip()))
        sys.exit(1)
    if new in src:
        print("  %s: patch already present (skipped)" % path)
        return
    open(path, "w", encoding="utf-8").write(src.replace(old, new, 1))
    print("  %s: patched" % path)


def main():
    for path, marker in FILE_MARKER.items():
        if marker in open(path, encoding="utf-8").read():
            restore(path)

    apply_pair(CORE, CORE_CREATE_OLD, CORE_CREATE_NEW)
    apply_pair(CORE, CORE_INIT_OLD, CORE_INIT_NEW)
    apply_pair(CORE, CORE_RUN_OLD, CORE_RUN_NEW)
    apply_pair(XRUN, XRUN_OLD, XRUN_NEW)
    apply_pair(DYNAREC, DYN_OLD, DYN_NEW)
    print("quit-diag instrumentation applied.")


if __name__ == "__main__":
    main()
