#ifndef COMPAT_ELF_H
#define COMPAT_ELF_H

#include <stdint.h>

#define EI_NIDENT 16

#define EI_MAG0     0
#define EI_MAG1     1
#define EI_MAG2     2
#define EI_MAG3     3
#define EI_CLASS    4
#define EI_DATA     5
#define EI_VERSION  6
#define EI_OSABI    7

#define ELFCLASS32  1
#define ELFCLASS64  2
#define ELFDATA2LSB 1
#define ELFDATA2MSB 2

#define EV_NONE     0
#define EV_CURRENT  1

#define ELFOSABI_NONE      0
#define ELFOSABI_SYSV      0
#define ELFOSABI_LINUX     3

#define EM_MIPS     8
#define EM_PPC      20
#define EM_PPC64    21
#define EM_386      3
#define EM_ARM      40
#define EM_AARCH64  183
#define EM_RISCV    243
#define EM_X86_64   62

typedef uint16_t Elf32_Half;
typedef uint32_t Elf32_Word;
typedef int32_t Elf32_Sword;
typedef uint32_t Elf32_Addr;
typedef uint32_t Elf32_Off;

typedef struct {
    unsigned char e_ident[EI_NIDENT];
    Elf32_Half e_type;
    Elf32_Half e_machine;
    Elf32_Word e_version;
    Elf32_Addr e_entry;
    Elf32_Off e_phoff;
    Elf32_Off e_shoff;
    Elf32_Word e_flags;
    Elf32_Half e_ehsize;
    Elf32_Half e_phentsize;
    Elf32_Half e_phnum;
    Elf32_Half e_shentsize;
    Elf32_Half e_shnum;
    Elf32_Half e_shstrndx;
} Elf32_Ehdr;

typedef struct {
    Elf32_Word p_type;
    Elf32_Off p_offset;
    Elf32_Addr p_vaddr;
    Elf32_Addr p_paddr;
    Elf32_Word p_filesz;
    Elf32_Word p_memsz;
    Elf32_Word p_flags;
    Elf32_Word p_align;
} Elf32_Phdr;

typedef struct {
    Elf32_Word sh_name;
    Elf32_Word sh_type;
    Elf32_Word sh_flags;
    Elf32_Addr sh_addr;
    Elf32_Off sh_offset;
    Elf32_Word sh_size;
    Elf32_Word sh_link;
    Elf32_Word sh_info;
    Elf32_Word sh_addralign;
    Elf32_Word sh_entsize;
} Elf32_Shdr;

typedef struct {
    Elf32_Word st_name;
    Elf32_Addr st_value;
    Elf32_Word st_size;
    unsigned char st_info;
    unsigned char st_other;
    Elf32_Half st_shndx;
} Elf32_Sym;

typedef struct {
    Elf32_Sword d_tag;
    union { Elf32_Word d_val; Elf32_Addr d_ptr; } d_un;
} Elf32_Dyn;

typedef struct {
    Elf32_Addr r_offset;
    Elf32_Word r_info;
} Elf32_Rel;

typedef struct {
    Elf32_Addr r_offset;
    Elf32_Word r_info;
    Elf32_Sword r_addend;
} Elf32_Rela;

typedef uint16_t Elf64_Half;
typedef uint32_t Elf64_Word;
typedef int32_t Elf64_Sword;
typedef uint64_t Elf64_Xword;
typedef int64_t Elf64_Sxword;
typedef uint64_t Elf64_Addr;
typedef uint64_t Elf64_Off;

typedef struct {
    unsigned char e_ident[EI_NIDENT];
    Elf64_Half e_type;
    Elf64_Half e_machine;
    Elf64_Word e_version;
    Elf64_Addr e_entry;
    Elf64_Off e_phoff;
    Elf64_Off e_shoff;
    Elf64_Word e_flags;
    Elf64_Half e_ehsize;
    Elf64_Half e_phentsize;
    Elf64_Half e_phnum;
    Elf64_Half e_shentsize;
    Elf64_Half e_shnum;
    Elf64_Half e_shstrndx;
} Elf64_Ehdr;

typedef struct {
    Elf64_Word p_type;
    Elf64_Word p_flags;
    Elf64_Off p_offset;
    Elf64_Addr p_vaddr;
    Elf64_Addr p_paddr;
    Elf64_Xword p_filesz;
    Elf64_Xword p_memsz;
    Elf64_Xword p_align;
} Elf64_Phdr;

typedef struct {
    Elf64_Word sh_name;
    Elf64_Word sh_type;
    Elf64_Xword sh_flags;
    Elf64_Addr sh_addr;
    Elf64_Off sh_offset;
    Elf64_Xword sh_size;
    Elf64_Word sh_link;
    Elf64_Word sh_info;
    Elf64_Xword sh_addralign;
    Elf64_Xword sh_entsize;
} Elf64_Shdr;

typedef struct {
    Elf64_Word st_name;
    unsigned char st_info;
    unsigned char st_other;
    Elf64_Half st_shndx;
    Elf64_Addr st_value;
    Elf64_Xword st_size;
} Elf64_Sym;

typedef struct {
    Elf64_Sxword d_tag;
    union { Elf64_Xword d_val; Elf64_Addr d_ptr; } d_un;
} Elf64_Dyn;

typedef struct {
    Elf64_Addr r_offset;
    Elf64_Xword r_info;
} Elf64_Rel;

typedef struct {
    Elf64_Addr r_offset;
    Elf64_Xword r_info;
    Elf64_Sxword r_addend;
} Elf64_Rela;

typedef struct {
    Elf64_Half si_boundto;
    Elf64_Half si_flags;
} Elf64_Syminfo;

#define ET_NONE     0
#define ET_REL      1
#define ET_EXEC     2
#define ET_DYN      3
#define ET_CORE     4

#define PT_NULL     0
#define PT_LOAD     1
#define PT_DYNAMIC  2
#define PT_INTERP   3
#define PT_NOTE     4
#define PT_SHLIB    5
#define PT_PHDR     6
#define PT_LOPROC   0x70000000
#define PT_HIPROC   0x7fffffff

#define PF_X        1
#define PF_W        2
#define PF_R        4

#define SHT_NULL        0
#define SHT_PROGBITS    1
#define SHT_SYMTAB      2
#define SHT_STRTAB      3
#define SHT_RELA        4
#define SHT_HASH        5
#define SHT_DYNAMIC     6
#define SHT_NOTE        7
#define SHT_NOBITS      8
#define SHT_REL         9
#define SHT_SHLIB       10
#define SHT_DYNSYM      11
#define SHT_INIT_ARRAY  14
#define SHT_FINI_ARRAY  15
#define SHT_PREINIT_ARRAY 16
#define SHT_GROUP       17
#define SHT_SYMTAB_SHNDX 18
#define SHT_NUM         19
#define SHT_GNU_HASH    0x6ffffff6
#define SHT_GNU_VERSYM  0x6fffffff
#define SHT_GNU_VERNEED 0x6ffffffe
#define SHT_LOPROC      0x70000000
#define SHT_HIPROC      0x7fffffff
#define SHT_LOUSER      0x80000000
#define SHT_HIUSER      0xffffffff

#define SHN_UNDEF       0
#define SHN_ABS         0xfff1
#define SHN_COMMON      0xfff2
#define SHN_XINDEX      0xffff

#define STB_LOCAL       0
#define STB_GLOBAL      1
#define STB_WEAK        2

#define STT_NOTYPE      0
#define STT_OBJECT      1
#define STT_FUNC        2
#define STT_SECTION     3
#define STT_FILE        4
#define STT_COMMON      5
#define STT_TLS         6
#define STT_GNU_IFUNC   10

#define STV_DEFAULT     0
#define STV_INTERNAL    1
#define STV_HIDDEN      2
#define STV_PROTECTED   3

#define ELF64_ST_BIND(i)   ((i) >> 4)
#define ELF64_ST_TYPE(i)   ((i) & 0xf)
#define ELF64_ST_INFO(b,t) (((b)<<4)+((t)&0xf))
#define ELF64_ST_VISIBILITY(o) ((o) & 0x3)

#define ELF64_R_SYM(i)      ((i) >> 32)
#define ELF64_R_TYPE(i)     ((i) & 0xffffffffL)
#define ELF64_R_INFO(s,t)   (((Elf64_Xword)(s)<<32)+((t)&0xffffffffL))

#define R_X86_64_NONE       0
#define R_X86_64_64         1
#define R_X86_64_PC32       2
#define R_X86_64_GOT32      3
#define R_X86_64_PLT32      4
#define R_X86_64_COPY       5
#define R_X86_64_GLOB_DAT   6
#define R_X86_64_JMP_SLOT   7
#define R_X86_64_RELATIVE   8
#define R_X86_64_GOTPCREL   9
#define R_X86_64_32         10
#define R_X86_64_32S        11
#define R_X86_64_16         12
#define R_X86_64_PC16       13
#define R_X86_64_8          14
#define R_X86_64_PC8        15
#define R_X86_64_DTPMOD64   16
#define R_X86_64_DTPOFF64   17
#define R_X86_64_TPOFF64    18
#define R_X86_64_TLSGD      19
#define R_X86_64_TLSLD      20
#define R_X86_64_DTPOFF32   21
#define R_X86_64_GOTTPOFF   22
#define R_X86_64_TPOFF32    23
#define R_X86_64_PC64       24
#define R_X86_64_GOTOFF64   25
#define R_X86_64_GOTPC32    26
#define R_X86_64_GOT64      27
#define R_X86_64_GOTPCREL64 28
#define R_X86_64_GOTPC64    29
#define R_X86_64_GOTPLT64   30
#define R_X86_64_PLTOFF64   31
#define R_X86_64_SIZE32     32
#define R_X86_64_SIZE64     33
#define R_X86_64_GOTPC32_TLSDESC 34
#define R_X86_64_TLSDESC_CALL 35
#define R_X86_64_TLSDESC    36
#define R_X86_64_IRELATIVE  37
#define R_X86_64_RELATIVE64 38
#define R_X86_64_GOTPCRELX  41
#define R_X86_64_REX_GOTPCRELX 42
#define R_X86_64_NUM        43
/* glibc spells it R_X86_64_JUMP_SLOT (box64 uses this); alias to be safe */
#define R_X86_64_JUMP_SLOT  7

#define DT_NULL         0
#define DT_NEEDED       1
/* v410 FIX: DT_PLTRELSZ (2) and DT_RELSZ (18) are DIFFERENT ELF tags.
   v373 incorrectly defined DT_RELSZ as 2 (the DT_PLTRELSZ value), which
   collided with `case DT_PLTRELSZ` in box64's elfparser.c under clang and
   forced the v373 hack of giving DT_PLTRELSZ a bogus 0x6ffffef6 dead-case
   value. Runtime effect: box64's `case DT_RELSZ` matched real tag 2 and
   swallowed DT_PLTRELSZ into h->relsz, so h->pltsz stayed 0, RelocateElfPlt64
   applied 0 JUMP_SLOT relocations and the first lazy GOT.plt call crashed
   (SIGSEGV addr=0x28270 in libc.so.6 Init[0]). Restored spec values. */
#define DT_PLTRELSZ     2
#define DT_PLTGOT       3
#define DT_HASH         4
#define DT_STRTAB       5
#define DT_SYMTAB       6
#define DT_RELA         7
#define DT_RELASZ       8
#define DT_RELAENT      9
#define DT_STRSZ        10
#define DT_SYMENT       11
#define DT_INIT         12
#define DT_FINI         13
#define DT_SONAME       14
#define DT_RPATH        15
#define DT_SYMBOLIC     16
#define DT_REL          17
#define DT_PLTREL       20
#define DT_DEBUG        21
#define DT_TEXTREL      22
#define DT_JMPREL       23
#define DT_BIND_NOW     24
#define DT_INIT_ARRAY   25
#define DT_FINI_ARRAY   26
#define DT_INIT_ARRAYSZ 27
#define DT_FINI_ARRAYSZ 28
#define DT_GNU_HASH     0x6ffffef5
#define DT_GNU_VERSYM   0x6ffffff0
#define DT_GNU_VERNEED  0x6ffffffe
#define DT_RELACOUNT    0x6ffffff9
#define DT_RELCOUNT     0x6ffffffa
/* glibc spellings used by box64's elfloader/elfparser */
#define DT_VERSYM       0x6ffffff0
#define DT_VERDEF       0x6ffffffc
#define DT_VERDEFNUM    0x6ffffffd
#define DT_VERNEED      0x6ffffffe
#define DT_VERNEEDNUM   0x6fffffff
#define DT_RELSZ        18
#define DT_RELENT       19
#define DT_RUNPATH      29
#define DT_FLAGS        30
#define DT_PREINIT_ARRAY    32
#define DT_PREINIT_ARRAYSZ  33
#define DT_FLAGS_1      0x6ffffffb
/* DT_ENCODING is tag 21 in glibc, same as DT_DEBUG — box64's elfload_dump.c
   switches list both, a hard "duplicate case value" error under clang.
   DT_DEBUG precedes, so give DT_ENCODING a distinct dead-case value. Only
   affects dump formatting. (This collision is real in glibc's elf.h; keep.) */
#define DT_ENCODING     0x6ffffe00

#define DF_ORIGIN       0x00000001
#define DF_SYMBOLIC     0x00000002
#define DF_TEXTREL      0x00000004
#define DF_BIND_NOW     0x00000008
#define DF_STATIC_TLS   0x00000010

#define DF_1_NOW        0x00000001
#define DF_1_GLOBAL     0x00000002
#define DF_1_GROUP      0x00000004
#define DF_1_NODELETE   0x00000008
#define DF_1_LOADFLTR   0x00000010
#define DF_1_INITFIRST  0x00000020
#define DF_1_NOOPEN     0x00000040
#define DF_1_ORIGIN     0x00000080
#define DF_1_DIRECT     0x00000100
#define DF_1_TRANS      0x00000200
#define DF_1_INTERPOSE  0x00000400
#define DF_1_NODEFLIB   0x00000800
#define DF_1_NODUMP     0x00001000
#define DF_1_CONFALT    0x00002000
#define DF_1_ENDFILTEE  0x00004000
#define DF_1_DISPRELDNE 0x00008000
#define DF_1_DISPRELPND 0x00010000
#define DF_1_NODIRECT   0x00020000
#define DF_1_IGNMULDEF  0x00040000
#define DF_1_NOKSYMS    0x00080000
#define DF_1_NOHDR      0x00100000
#define DF_1_EDITED     0x00200000
#define DF_1_NORELOC    0x00400000
#define DF_1_SYMINTPOSE 0x00800000
#define DF_1_GLOBAUDIT  0x01000000
#define DF_1_SINGLETON  0x02000000
#define DF_1_STUB       0x04000000
#define DF_1_PIE        0x08000000

#define AT_NULL         0
#define AT_PHDR         3
#define AT_PHENT        4
#define AT_PHNUM        5
#define AT_PAGESZ       6
#define AT_BASE         7
#define AT_FLAGS        8
#define AT_ENTRY        9
#define AT_UID          11
#define AT_EUID         12
#define AT_GID          13
#define AT_EGID         14
#define AT_HWCAP        16
#define AT_CLKTCK       17
#define AT_SYSINFO_EHDR 33
#define AT_RANDOM       25
#define AT_HWCAP2       26
#define AT_EXECFN       31

#define NT_GNU_BUILD_ID 3

#define PT_GNU_STACK    0x6474e551
#define PT_GNU_RELRO    0x6474e552
#define PT_GNU_EH_FRAME 0x6474e550
#define PT_TLS          7

#define ELFMAG          "\177ELF"
#define SELFMAG         4

#define R_386_NONE       0
#define R_386_32         1
#define R_386_PC32       2
#define R_386_GOT32      3
#define R_386_PLT32      4
#define R_386_COPY       5
#define R_386_GLOB_DAT  6
#define R_386_JMP_SLOT  7
#define R_386_RELATIVE  8
#define R_386_GOTOFF    9
#define R_386_GOTPC     10
#define R_386_TLS_TPOFF 14
#define R_386_TLS_GD_32 24
#define R_386_TLS_DTPMOD32 35
#define R_386_TLS_DTPOFF32 36
#define R_386_TLS_TPOFF32 37

#define GRP.jdesktop   1

/* ======== ElfW() macro ======== */
#ifdef DYNAREC
#define ElfW(type) Elf64_##type
#else
#define ElfW(type) Elf32_##type
#endif

/* ======== ELF Versioning structs ======== */
typedef struct {
    Elf64_Half vn_version;
    Elf64_Half vn_cnt;
    Elf64_Word vn_file;
    Elf64_Word vn_aux;
    Elf64_Word vn_next;
} Elf64_Verneed;

typedef struct {
    Elf64_Word vna_hash;
    Elf64_Half vna_flags;
    Elf64_Half vna_other;
    Elf64_Word vna_name;
    Elf64_Word vna_next;
} Elf64_Vernaux;

typedef struct {
    Elf64_Half vd_version;
    Elf64_Half vd_flags;
    Elf64_Half vd_ndx;
    Elf64_Half vd_cnt;
    Elf64_Word vd_hash;
    Elf64_Word vd_aux;
    Elf64_Word vd_next;
} Elf64_Verdef;

typedef struct {
    Elf64_Word vda_name;
    Elf64_Word vda_next;
} Elf64_Verdaux;

typedef struct {
    Elf32_Half vn_version;
    Elf32_Half vn_cnt;
    Elf32_Word vn_file;
    Elf32_Word vn_aux;
    Elf32_Word vn_next;
} Elf32_Verneed;

typedef struct {
    Elf32_Word vna_hash;
    Elf32_Half vna_flags;
    Elf32_Half vna_other;
    Elf32_Word vna_name;
    Elf32_Word vna_next;
} Elf32_Vernaux;

typedef struct {
    Elf32_Half vd_version;
    Elf32_Half vd_flags;
    Elf32_Half vd_ndx;
    Elf32_Half vd_cnt;
    Elf32_Word vd_hash;
    Elf32_Word vd_aux;
    Elf32_Word vd_next;
} Elf32_Verdef;

typedef struct {
    Elf32_Word vda_name;
    Elf32_Word vda_next;
} Elf32_Verdaux;

/* ======== ELF note types ======== */
typedef struct {
    Elf64_Word n_namesz;
    Elf64_Word n_descsz;
    Elf64_Word n_type;
} Elf64_Nhdr;

typedef struct {
    Elf32_Word n_namesz;
    Elf32_Word n_descsz;
    Elf32_Word n_type;
} Elf32_Nhdr;

/* ======== ELF hash ======== */
typedef struct {
    Elf64_Word nbucket;
    Elf64_Word nchain;
} Elf64_Hash;

typedef struct {
    Elf32_Word nbucket;
    Elf32_Word nchain;
} Elf32_Hash;

#define VER_FLG_BASE    1
#define VER_FLG_WEAK    2
#define VER_NEED_NONE       0
#define VER_NEED_CURRENT    1
#define VER_DEF_NONE        0
#define VER_DEF_CURRENT     1

/* ======== ELF32 macros ======== */
#define ELF32_ST_BIND(i)   ((i) >> 4)
#define ELF32_ST_TYPE(i)   ((i) & 0xf)
#define ELF32_ST_INFO(b,t) (((b)<<4)+((t)&0xf))
#define ELF32_ST_VISIBILITY(o) ((o) & 0x3)
#define ELF32_R_SYM(i)      ((i) >> 8)
#define ELF32_R_TYPE(i)     ((i) & 0xff)
#define ELF32_R_INFO(s,t)   (((Elf32_Word)(s)<<8)+((Elf32_Word)(t)&0xff))

#endif
