#!/usr/bin/env python3
# Runtime relocation diagnostic for the SIGSEGV at guest 0x28270 (= raw .plt
# slot value in libc.so.6's .got.plt that was never biased by +delta, proving
# R_X86_64_JUMP_SLOT / PLT relocations are not being applied for some libs).
#
# The crash signature (first GOT.plt call lands on raw vaddr 0x28270 inside
# .plt 0x28000..0x28370) means either
#   (a) head->pltsz was parsed as 0 so RelocateElfPlt64 computed cnt = 0 and
#       never applied the 54 JUMP_SLOT relocs of libc.so.6, or
#   (b) head->delta was 0 during RelocateElfPlt so the lazy `*p += delta` bias
#       of the .got.plt self-entries did nothing.
# This patch logs, per emulated lib, the parse-time dynamic values, the runtime
# inputs to RelocateElfPlt64, and the post-state of .got.plt[2..4], so one
# device run pinpoints which of the two (or something else) is true.
#
# Anchors are from ptitSeb/box64 @ 3c670ef. Idempotent (skips if already
# applied) and fails loudly if an anchor drifted so we never silently build a
# non-diagnostic binary. Run from Box64Source/box64.
import sys

ELFPARSER = "src/elfs/elfparser.c"
ELFLOADER = "src/elfs/elfloader.c"


def apply(path, old, new, what, marker):
    src = open(path, encoding="utf-8").read()
    if marker in src:
        print("  %s: %s already present, skipping" % (path, marker))
        return
    i = src.find(old)
    if i < 0:
        print("ERROR: %s anchor not found in %s (box64 source changed?); fix this script before building" % (what, path))
        print("---- anchor was ----")
        print(old)
        sys.exit(1)
    open(path, "w", encoding="utf-8").write(src.replace(old, new, 1))
    print("  %s: patched (%s)" % (path, what))


def verify():
    checks = [
        (ELFPARSER, "[RELOC] %s parsed:", "parse-time dynamic fields"),
        (ELFPARSER, "[RELOC] %s sections:", "section-derived plt/gotplt"),
        (ELFLOADER, "[RELOC] %s PLT in:", "RelocateElfPlt64 inputs"),
        (ELFLOADER, "[RELOC] %s PLT out:", "RelocateElfPlt64 result"),
        (ELFLOADER, "[RELOC] %s RELA apply:", "RELA apply count"),
    ]
    ok = True
    for path, needle, what in checks:
        if needle in open(path, encoding="utf-8").read():
            print("  OK    %s (%s)" % (what, path))
        else:
            print("  MISS  %s (%s) needle=%s" % (what, path, needle))
            ok = False
    if not ok:
        print("ERROR: build would produce a non-diagnostic binary; aborting")
        sys.exit(1)
    print("Patch verification passed: [RELOC] diagnostics present")


# --- elfparser.c: right after the DT_* dynamic loop --------------------------
A_OLD = """        if(h->DynStrTab && h->szDynStrTab) {
            //DumpDynamicNeeded64(h); cannot dump now, it's not loaded yet
        }
    }
    // look for PLT Offset"""
A_NEW = """        if(h->DynStrTab && h->szDynStrTab) {
            //DumpDynamicNeeded64(h); cannot dump now, it's not loaded yet
        }
    }
    printf_log(LOG_INFO, "[RELOC] %s parsed: rela=0x%zx relasz=0x%zx relaent=%d rel=0x%zx relsz=0x%zx relr=0x%zx relrsz=0x%zx jmprel=0x%zx pltsz=0x%zx pltrel=%llu pltgot=0x%zx initarr=0x%zx initarrsz=0x%zu dynsym=%p\\n", name, h->rela, h->relasz, h->relaent, h->rel, h->relsz, h->relr, h->relrsz, h->jmprel, h->pltsz, (unsigned long long)h->pltrel, h->pltgot, h->initarray, h->initarray_sz, (void*)h->DynSym._64);
    // look for PLT Offset"""
apply(ELFPARSER, A_OLD, A_NEW, "parse-time dynamic fields", "[RELOC] %s parsed:")

# --- elfparser.c: after the .plt section lookup ------------------------------
B_OLD = """    ii = FindSection(h->SHEntries._64, h->numSHEntries, h->SHStrTab, ".plt");
    if(ii) {
        h->plt = h->SHEntries._64[ii].sh_addr;
        h->plt_end = h->plt + h->SHEntries._64[ii].sh_size;
        printf_dump(LOG_DEBUG, "The PLT Table is at address %p..%p\\n", (void*)h->plt, (void*)h->plt_end);
    }"""
B_NEW = """    ii = FindSection(h->SHEntries._64, h->numSHEntries, h->SHStrTab, ".plt");
    if(ii) {
        h->plt = h->SHEntries._64[ii].sh_addr;
        h->plt_end = h->plt + h->SHEntries._64[ii].sh_size;
        printf_dump(LOG_DEBUG, "The PLT Table is at address %p..%p\\n", (void*)h->plt, (void*)h->plt_end);
    }
    printf_log(LOG_INFO, "[RELOC] %s sections: plt=0x%zx..0x%zx gotplt=0x%zx got=0x%zx text=0x%zx\\n", name, h->plt, h->plt_end, h->gotplt, h->got, h->text);"""
apply(ELFPARSER, B_OLD, B_NEW, "section-derived plt/gotplt", "[RELOC] %s sections:")

# --- elfloader.c: RelocateElfPlt64 inputs ------------------------------------
C_OLD = """    int need_resolver = 0;
    if((head->flags&DF_BIND_NOW) && !bindnow) {"""
C_NEW = """    int need_resolver = 0;
    printf_log(LOG_INFO, "[RELOC] %s PLT in: pltsz=0x%zx pltent=%d pltrel=%llu jmprel=0x%zx delta=0x%llx plt=0x%zx..0x%zx gotplt=0x%zx got=0x%zx pltgot=0x%zx bindnow=%d deepbind=%d\\n", head->name?head->name:"?", head->pltsz, head->pltent, (unsigned long long)head->pltrel, head->jmprel, (unsigned long long)head->delta, head->plt, head->plt_end, head->gotplt, head->got, head->pltgot, bindnow, deepbind);
    if((head->flags&DF_BIND_NOW) && !bindnow) {"""
apply(ELFLOADER, C_OLD, C_NEW, "RelocateElfPlt64 inputs", "[RELOC] %s PLT in:")

# --- elfloader.c: RelocateElfPlt64 result ------------------------------------
D_OLD = """        }
    }

    return 0;
}

static uint32_t getElfPageProtection64(const elfheader_t* head, uintptr_t page)"""
D_NEW = """        }
    }
    printf_log(LOG_INFO, "[RELOC] %s PLT out: need_resolver=%d pltgot=0x%zx g2=%p g3=%p g4=%p\\n", head->name?head->name:"?", need_resolver, head->pltgot, (void*)(head->pltgot?*(uintptr_t*)(head->pltgot+head->delta+16):0), (void*)(head->pltgot?*(uintptr_t*)(head->pltgot+head->delta+24):0), (void*)(head->pltgot?*(uintptr_t*)(head->pltgot+head->delta+32):0));

    return 0;
}

static uint32_t getElfPageProtection64(const elfheader_t* head, uintptr_t page)"""
apply(ELFLOADER, D_OLD, D_NEW, "RelocateElfPlt64 result", "[RELOC] %s PLT out:")

# --- elfloader.c: RelocateElf64 RELA count -----------------------------------
E_OLD = """        printf_dump(LOG_DEBUG, "Applying %d Relocation(s) with Addend for %s bindnow=%d, deepbind=%d\\n", cnt, head->name, bindnow, deepbind);
        if(RelocateElfRELA(maplib, local_maplib, bindnow, deepbind, head, cnt, (Elf64_Rela *)(head->rela + head->delta), NULL))"""
E_NEW = """        printf_dump(LOG_DEBUG, "Applying %d Relocation(s) with Addend for %s bindnow=%d, deepbind=%d\\n", cnt, head->name, bindnow, deepbind);
        printf_log(LOG_INFO, "[RELOC] %s RELA apply: cnt=%d delta=0x%llx rela=0x%zx\\n", head->name?head->name:"?", cnt, (unsigned long long)head->delta, head->rela);
        if(RelocateElfRELA(maplib, local_maplib, bindnow, deepbind, head, cnt, (Elf64_Rela *)(head->rela + head->delta), NULL))"""
apply(ELFLOADER, E_OLD, E_NEW, "RELA apply count", "[RELOC] %s RELA apply:")

verify()
print("reloc-diag instrumentation applied and verified")
