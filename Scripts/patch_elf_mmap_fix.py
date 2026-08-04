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
import sys


def apply(path):
    src = open(path, encoding="utf-8").read()

    anchor = "setProtection_elf((uintptr_t)p, asize, prot);\n                head->multiblocks[n].p = p;\n                if (e->p_filesz && !mapped_file) {"
    i = src.find(anchor)
    if i < 0:
        print("ERROR: anchor not found in %s (box64 source changed?)" % path)
        sys.exit(1)

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
                        if(a < b) {
                            fseeko64(head->file, head->multiblocks[j].offs + (off_t)(a - j_start), SEEK_SET);
                            if(fread((void*)a, b - a, 1, head->file)!=1) {
                                printf_log(LOG_NONE, "Cannot re-read elf block for \\"%s\\"\\n", head->name);
                                return 1;
                            }
                        }
                    }
                }
                if (e->p_filesz && !mapped_file) {"""
    src = src.replace(anchor, reinsert, 1)

    if "Cannot re-read elf block" not in src:
        print("ERROR: post-insert verification failed in %s" % path)
        sys.exit(1)
    open(path, "w", encoding="utf-8").write(src)
    print("Patched %s: re-fill segments wiped by large-page MAP_FIXED remap" % path)


apply("src/elfs/elfloader.c")
print("ELF segment large-page fix installed")
