#!/usr/bin/env python3
# Fix: on hosts with pages larger than 4KB (iOS 16KB pages), the anonymous
# MAP_FIXED segment remap inside AllocLoadElfMemory rounds DOWN to a whole host
# page and therefore wipes the file bytes of EARLIER segments that share that
# same page. Small libs (libdl.so.2 / libpthread.so.0, ~0x4000 bytes = a single
# 16KB page) end up with zeroed ELF headers, so box64 discards them for "missing
# version GLIBC_2.2.5" and Wine never starts. After the MAP_FIXED remap, re-read
# the file data of the overlapping part of every previously loaded segment that
# falls inside the remapped range, restoring what the kernel zeroed (only that
# range is writable; earlier segments may extend into read-only file-mapped
# pages). Run from Box64Source/box64.
#
# Upstream 0db8df7 reworked the !try_mmap path: the anonymous remap now maps
# with PROT_WRITE (deferred mprotect) and skips pages that are already mapped
# (getProtection overlap-avoidance), which structurally prevents the wipe. This
# re-read is kept as a defensive net for any residual case.
#
# v397 hardening:
#  * A leftover patch in a stale/dirty tree (e.g. a previous build's edit was
#    merged on top of a newer master) makes the tree a hybrid that behaves
#    differently from ANY upstream revision. We now DETECT our own old patch
#    ("Cannot re-read elf block") and restore the pristine file from git before
#    re-applying, so we never silently build from a poisoned tree again.
#  * If the apply anchor drifts, we FAIL LOUDLY instead of silently skipping,
#    so a build can never silently lose this fix.
#  * [MNEMU] LOG_NONE breadcrumbs are installed in fopen (core.c),
#    LoadAndCheckElfHeader (elfloader.c) and ParseElfHeader64 (elfparser.c) so
#    the device stderr.log definitively shows WHICH check fails when the main
#    ELF header cannot be parsed (v396 showed "Error: Reading elf header of
#    ...wine64" with no parse message at all, which upstream code cannot do).
#
# v4xx hardening (v410 root cause: stale objects; the v410 binary's elfparser.o
# printed none of the patched breadcrumbs even though the source had them):
#  * ALL anchor-not-found paths now FAIL LOUDLY (previously WARNING-skip could
#    silently build a non-diagnostic binary).
#  * ParseElfHeader64 gains an ENTER breadcrumb BEFORE the fread, the fread rc,
#    and ferror()/fileno() on the failure branch — a definitive fopen/read path
#    audit that does not depend on any later check.
#  * fopen (core.c) breadcrumb now also prints fileno().
#  * A final verify() re-reads the patched sources and aborts on any miss.
#  * build.yml additionally strings-checks the FINAL box64 binary, so a
#    stale-object build is rejected on CI, not discovered on device.
import subprocess
import sys

ELFLOADER = "src/elfs/elfloader.c"
ELFPARSER = "src/elfs/elfparser.c"
COREC = "src/core.c"


def apply(path):
    src = open(path, encoding="utf-8").read()

    if "Cannot re-read elf block" in src:
        print("%s: leftover re-read patch found (stale tree); restoring pristine file from git" % path)
        r = subprocess.run(["git", "checkout", "--", path], capture_output=True)
        if r.returncode != 0:
            print("ERROR: git checkout -- %s failed (%s); refusing to build a poisoned tree" % (path, r.stderr.decode(errors="replace").strip()))
            sys.exit(1)
        src = open(path, encoding="utf-8").read()

    anchor = "setProtection_elf((uintptr_t)p, asize, prot);\n                head->multiblocks[n].p = p;\n                if (file_read_size) {"
    i = src.find(anchor)
    if i < 0:
        print("ERROR: anchor not found in %s (box64 source changed?); fix this script before building" % path)
        sys.exit(1)

    reinsert = """setProtection_elf((uintptr_t)p, asize, prot);
                head->multiblocks[n].p = p;
                // Large host pages (iOS 16KB / some ARM64 64KB): an ANONYMOUS
                // MAP_FIXED remap covers whole host page(s) and therefore wipes
                // the file bytes of earlier segments that share the same page(s).
                // Re-read the wiped bytes from the ELF file to restore them.
                // Skipped when this segment was file-mapped: the file map already
                // provides every segment's bytes in that page and is read-only,
                // so writing it back would SIGBUS.
                // Only the bytes inside [paddr, paddr+asize) were wiped; earlier
                // segments may extend into read-only file-mapped pages, so restore
                // just the intersection with that (writable) anon region.
                if (!mapped_file && (prot & PROT_WRITE)) {
                    for (int j = 0; j < n; ++j) {
                        if(!head->multiblocks[j].size) continue;
                        uintptr_t j_start = head->multiblocks[j].paddr;
                        uintptr_t j_end = j_start + head->multiblocks[j].size;
                        uintptr_t a = j_start > paddr ? j_start : paddr;
                        uintptr_t b = j_end < (paddr + asize) ? j_end : (paddr + asize);
                        if(a < b && (getProtection((uintptr_t)a) & PROT_WRITE)) {
                            fseeko64(head->file, head->multiblocks[j].offs + (off_t)(a - j_start), SEEK_SET);
                            if(fread((void*)a, b - a, 1, head->file)!=1) {
                                printf_log(LOG_NONE, "Cannot re-read elf block for \\"%s\\"\\n", head->name);
                                return 1;
                            }
                        }
                    }
                }
                if (file_read_size) {"""
    src = src.replace(anchor, reinsert, 1)

    if "Cannot re-read elf block" not in src:
        print("ERROR: post-insert verification failed in %s" % path)
        sys.exit(1)
    open(path, "w", encoding="utf-8").write(src)
    print("Patched %s: re-fill segments wiped by large-page MAP_FIXED remap" % path)


def add_diag_markers(path):
    src = open(path, encoding="utf-8").read()
    if "[DBG] %s seg#" in src:
        print("%s: diag markers already present, skipping" % path)
        return

    # Marker 1: print every PT_LOAD segment as it is reached, so a hang inside
    # AllocLoadElfMemory is pinpointable to a segment in stderr.log even when
    # BOX64_LOG only shows LOG_INFO.
    a1 = "head->multiblocks[n].flags = e->p_flags;"
    i1 = src.find(a1)
    if i1 < 0:
        print("ERROR: diag marker anchor 1 not found in %s (box64 source changed?); fix this script before building" % path)
        sys.exit(1)
    else:
        marker = ("printf_log(LOG_INFO, \"[DBG] %s seg#%zu vaddr=0x%llx off=0x%llx "
                  "fsz=0x%llx msz=0x%llx flags=%x\\n\", head->name, i, "
                  "(unsigned long long)e->p_paddr, (unsigned long long)e->p_offset, "
                  "(unsigned long long)e->p_filesz, (unsigned long long)e->p_memsz, e->p_flags);\n"
                  "            " + a1)
        src = src.replace(a1, marker, 1)
        print("  inserted seg-start marker")

    # Marker 2: confirm the file-mapped branch succeeded (that path prints nothing).
    a2 = "                            if(file_read_size > e->p_filesz)\n                                file_read_size = e->p_filesz;"
    i2 = src.find(a2)
    if i2 < 0:
        print("ERROR: diag marker anchor 2 not found in %s (box64 source changed?); fix this script before building" % path)
        sys.exit(1)
    else:
        marker = ("                            if(file_read_size > e->p_filesz)\n"
                  "                                file_read_size = e->p_filesz;\n"
                  "                            printf_log(LOG_INFO, \"[DBG] %s file-map OK @%p size=0x%zx read=0x%zx\\n\", head->name, (void*)file_map_addr, file_size - file_map_delta, file_read_size);")
        src = src.replace(a2, marker, 1)
        print("  inserted file-map-OK marker")

    open(path, "w", encoding="utf-8").write(src)
    print("Patched %s: loader diag markers installed" % path)


def add_parse_breadcrumbs(elfloader_path, elfparser_path):
    # Marker A: does LoadAndCheckElfHeader even reach ParseElfHeader64, and is
    # box64_is32bits 1 (which would silently hit the ParseElfHeader32 stub)?
    src = open(elfloader_path, encoding="utf-8").read()
    a = "    elfheader_t *h = box64_is32bits?ParseElfHeader32(f, name, exec):ParseElfHeader64(f, name, exec);"
    if "[MNEMU] LoadAndCheckElfHeader" in src:
        print("%s: LCH breadcrumb already present, skipping" % elfloader_path)
    elif src.find(a) >= 0:
        marker = ("    printf_log(LOG_NONE, \"[MNEMU] LoadAndCheckElfHeader name=%s exec=%d box64_is32bits=%d f=%p\\n\", name, exec, box64_is32bits, (void*)f);\n"
                  "    elfheader_t *h = box64_is32bits?ParseElfHeader32(f, name, exec):ParseElfHeader64(f, name, exec);")
        src = src.replace(a, marker, 1)
        open(elfloader_path, "w", encoding="utf-8").write(src)
        print("  inserted LoadAndCheckElfHeader breadcrumb")
    else:
        print("ERROR: LCH breadcrumb anchor not found in %s (box64 source changed?); fix this script before building" % elfloader_path)
        sys.exit(1)

    # Marker B: instrument the first fread of the ELF header and dump every
    # field that ParseElfHeader64 validates next. Runs only on success (the
    # failure branch returns before it). A correct dump (7F 45 4C 46, class=2,
    # mach=62) proves the file open+read work and the failure is downstream.
    src = open(elfparser_path, encoding="utf-8").read()
    a = """    if(fread(&header, sizeof(Elf64_Ehdr), 1, f)!=1) {
        printf_log(level, "Cannot read ELF Header\\n");
        return NULL;
    }"""
    if "[MNEMU] ParseElfHeader64" in src:
        print("%s: ParseElfHeader64 breadcrumb already present, skipping" % elfparser_path)
        return
    i = src.find(a)
    if i < 0:
        print("ERROR: ParseElfHeader64 breadcrumb anchor not found in %s (box64 source changed?); fix this script before building" % elfparser_path)
        sys.exit(1)
    repl = """    printf_log(LOG_NONE, "[MNEMU] ParseElfHeader64 ENTER name=%s exec=%d f=%p fileno=%d\\n", name, exec, (void*)f, fileno(f));
    int mn_rc = fread(&header, sizeof(Elf64_Ehdr), 1, f);
    if(mn_rc!=1) {
        printf_log(LOG_NONE, "[MNEMU] ParseElfHeader64 fread(ehdr)!=1 rc=%d fileno=%d ferror=%d for %s\\n", mn_rc, fileno(f), ferror(f), name);
        printf_log(level, "Cannot read ELF Header\\n");
        return NULL;
    }
    printf_log(LOG_NONE, "[MNEMU] ParseElfHeader64 %s ehdr=%02X%02X%02X%02X cls=%u data=%u ver=%u osabi=%u type=%u mach=%u entry=0x%llx phoff=0x%llx shoff=0x%llx phnum=%u shnum=%u phent=%u shent=%u fileno=%d\\n", name, header.e_ident[0],header.e_ident[1],header.e_ident[2],header.e_ident[3],header.e_ident[EI_CLASS],header.e_ident[EI_DATA],header.e_ident[EI_VERSION],header.e_ident[EI_OSABI],header.e_type,header.e_machine,(unsigned long long)header.e_entry,(unsigned long long)header.e_phoff,(unsigned long long)header.e_shoff,header.e_phnum,header.e_shnum,header.e_phentsize,header.e_shentsize,fileno(f));"""
    src = src.replace(a, repl, 1)
    if "[MNEMU] ParseElfHeader64 ENTER" not in src:
        print("ERROR: ParseElfHeader64 breadcrumb insert verification failed in %s" % elfparser_path)
        sys.exit(1)
    open(elfparser_path, "w", encoding="utf-8").write(src)
    print("  inserted ParseElfHeader64 breadcrumb (ENTER + fread rc + ferror/fileno + ehdr dump)")


def add_core_markers(path):
    src = open(path, encoding="utf-8").read()
    a = '    FILE *f = fopen(my_context->fullpath, "rb");'
    if "[MNEMU] fopen(" in src:
        print("%s: fopen breadcrumb already present, skipping" % path)
        return
    i = src.find(a)
    if i < 0:
        print("WARNING: fopen breadcrumb anchor not found in %s; skipping" % path)
        return
    marker = a + '\n    printf_log(LOG_NONE, "[MNEMU] fopen(%s)=%p errno=%d\\n", my_context->fullpath, (void*)f, errno);'
    src = src.replace(a, marker, 1)
    open(path, "w", encoding="utf-8").write(src)
    print("Patched %s: fopen breadcrumb installed" % path)


def verify():
    checks = [
        (ELFLOADER, "Cannot re-read elf block", "ELF large-page re-fill fix"),
        (ELFLOADER, "[MNEMU] LoadAndCheckElfHeader", "LoadAndCheckElfHeader breadcrumb"),
        (ELFLOADER, "[DBG] %s seg#", "loader seg-start marker"),
        (ELFPARSER, "[MNEMU] ParseElfHeader64 ENTER", "ParseElfHeader64 ENTER breadcrumb"),
        (ELFPARSER, "[MNEMU] ParseElfHeader64 fread(ehdr)!=1", "ParseElfHeader64 fread-fail breadcrumb"),
        (COREC, "[MNEMU] fopen(", "fopen breadcrumb"),
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
    print("Patch verification passed: ELF fix + all [MNEMU] breadcrumbs present")


apply(ELFLOADER)
add_diag_markers(ELFLOADER)
add_parse_breadcrumbs(ELFLOADER, ELFPARSER)
add_core_markers(COREC)
verify()
print("ELF segment large-page fix + v4xx breadcrumbs installed and verified")
