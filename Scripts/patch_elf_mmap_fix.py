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
# re-read is kept as a defensive net for any residual case. If the anchor drifts
# again (fresh clone, active upstream), WARN and skip instead of failing the
# build so an unrelated patch churn can never block the pipeline again.
import sys


def apply(path):
    src = open(path, encoding="utf-8").read()

    if "Cannot re-read elf block" in src:
        print("%s: re-read logic already present (upstream merged it); skipping" % path)
        return

    anchor = "setProtection_elf((uintptr_t)p, asize, prot);\n                head->multiblocks[n].p = p;\n                if (file_read_size) {"
    i = src.find(anchor)
    if i < 0:
        print("WARNING: anchor not found in %s (box64 source changed?); skipping ELF large-page re-read patch" % path)
        return

    if "Cannot re-read elf block" in src:
        print("%s: already patched, skipping" % path)
        return

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
        print("WARNING: diag marker anchor 1 not found in %s; skipping" % path)
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
        print("WARNING: diag marker anchor 2 not found in %s; skipping" % path)
    else:
        marker = ("                            if(file_read_size > e->p_filesz)\n"
                  "                                file_read_size = e->p_filesz;\n"
                  "                            printf_log(LOG_INFO, \"[DBG] %s file-map OK @%p size=0x%zx read=0x%zx\\n\", head->name, (void*)file_map_addr, file_size - file_map_delta, file_read_size);")
        src = src.replace(a2, marker, 1)
        print("  inserted file-map-OK marker")

    open(path, "w", encoding="utf-8").write(src)
    print("Patched %s: loader diag markers installed" % path)


apply("src/elfs/elfloader.c")
add_diag_markers("src/elfs/elfloader.c")
print("ELF segment large-page fix installed")
