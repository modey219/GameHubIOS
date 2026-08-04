#!/usr/bin/env python3
# Fix: on hosts with pages larger than 4KB (iOS 16KB pages), the anonymous
# MAP_FIXED segment remap inside AllocLoadElfMemory rounds DOWN to a whole host
# page and therefore wipes the file bytes of EARLIER segments that share that
# same page. Small libs (libdl.so.2 / libpthread.so.0, ~0x4000 bytes = a single
# 16KB page) end up with zeroed ELF headers, so box64 discards them for "missing
# version GLIBC_2.2.5" and Wine never starts. After the MAP_FIXED remap, re-read
# the file data of every previously loaded segment that overlaps the remapped
# range, restoring what the kernel zeroed. Run from Box64Source/box64.
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
                // Large host pages (iOS 16KB / some ARM64 64KB): the anonymous
                // MAP_FIXED remap above covers whole host page(s), so it wipes
                // the file bytes of earlier segments that share the same page(s).
                // Re-read those segments' data from the ELF file to restore it.
                for (int j = 0; j < n; ++j) {
                    if(head->multiblocks[j].size &&
                       head->multiblocks[j].paddr < (paddr + asize) &&
                       (head->multiblocks[j].paddr + head->multiblocks[j].size) > paddr) {
                        fseeko64(head->file, head->multiblocks[j].offs, SEEK_SET);
                        if(fread((void*)head->multiblocks[j].paddr, head->multiblocks[j].size, 1, head->file)!=1) {
                            printf_log(LOG_NONE, "Cannot re-read elf block for \\"%s\\"\\n", head->name);
                            return 1;
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
