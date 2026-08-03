#!/usr/bin/env python3
# Temporary diagnostic patch: add [VERDBG] logging to box64's version-check
# path (isElfHasNeededVer / GetVersionIndice64) so we can see on-device WHY
# bundled libdl.so.2 / libpthread.so.0 are discarded for "missing version
# GLIBC_2.2.5" even though they define it. Run from Box64Source/box64.
import sys


def replace_func(path, sig, newbody):
    src = open(path, encoding="utf-8").read()
    i = src.find(sig)
    if i < 0:
        print("ERROR: signature not found in %s: %s" % (path, sig))
        sys.exit(1)
    j = src.find("{", i)
    depth = 0
    k = j
    while k < len(src):
        c = src[k]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    src = src[:i] + newbody + src[k + 1 :]
    open(path, "w", encoding="utf-8").write(src)
    print("Patched %s: %s" % (path, sig))


getver = '''int GetVersionIndice64(elfheader_t* h, const char* vername)
{
    if(!vername)
        return 0;
    if(h->VerDef._64 && h->DynStr) {
        Elf64_Verdef *def = (Elf64_Verdef*)((uintptr_t)h->VerDef._64 + h->delta);
        int d = 0;
        while(def) {
            Elf64_Verdaux *aux = (Elf64_Verdaux*)((uintptr_t)def + def->vd_aux);
            printf_log(LOG_NONE, "[VERDBG] GetVersionIndice64 lib=%s delta=%p VerDef=%p DynStr=%p def#%d def=%p ver=%u flags=%u ndx=%u cnt=%u hash=%x aux_off=%u next=%u vda_name=%u str=%s target=%s\\n", h->name?h->name:"(null)", (void*)h->delta, (void*)h->VerDef._64, (void*)h->DynStr, d, (void*)def, def->vd_version, def->vd_flags, def->vd_ndx, def->vd_cnt, def->vd_hash, def->vd_aux, def->vd_next, aux->vda_name, h->DynStr+aux->vda_name, vername);
            if(!strcmp(h->DynStr+aux->vda_name, vername))
                return def->vd_ndx;
            def = def->vd_next?((Elf64_Verdef*)((uintptr_t)def + def->vd_next)):NULL;
            ++d;
        }
    } else {
        printf_log(LOG_NONE, "[VERDBG] GetVersionIndice64 lib=%s VerDef=%p DynStr=%p MISSING-ONE\\n", h->name?h->name:"(null)", (void*)h->VerDef._64, (void*)h->DynStr);
    }
    return 0;
}
'''

isneed = '''int isElfHasNeededVer(elfheader_t* head, const char* libname, elfheader_t* verneeded)
{
    if(!verneeded || !head)
        return 1;
    if(!head->VerDef._64 || !verneeded->VerNeed._64) {
        printf_log(LOG_NONE, "[VERDBG] isElfHasNeededVer cand=%s libname=%s ACCEPT-early VerDef=%p VerNeed=%p\\n", head->name?head->name:"(null)", libname, (void*)head->VerDef._64, (void*)verneeded->VerNeed._64);
        return 1;
    }
    int cnt = GetNeededVersionCnt(verneeded, libname);
    printf_log(LOG_NONE, "[VERDBG] isElfHasNeededVer cand=%s libname=%s cnt=%d VerNeed=%p VerNeedDelta=%p\\n", head->name?head->name:"(null)", libname, cnt, (void*)verneeded->VerNeed._64, (void*)verneeded->delta);
    for (int i=0; i<cnt; ++i) {
        const char* vername = GetNeededVersionString(verneeded, libname, i);
        printf_log(LOG_NONE, "[VERDBG] isElfHasNeededVer i=%d vername=%s\\n", i, vername?vername:"(null)");
        if(vername && !GetVersionIndice(head, vername)) {
            printf_log(/*LOG_DEBUG*/LOG_INFO, "Discarding %s for missing version %s\\n", head->path, vername);
            return 0;
        }
    }
    return 1;
}
'''

replace_func("src/elfs/elfhash.c", "int GetVersionIndice64(elfheader_t* h, const char* vername)", getver)
replace_func("src/elfs/elfloader.c", "int isElfHasNeededVer(elfheader_t* head, const char* libname, elfheader_t* verneeded)", isneed)
print("Version-check debug logging installed")
