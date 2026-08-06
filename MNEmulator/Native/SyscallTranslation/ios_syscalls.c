/*
 * ios_syscalls.c — Darwin implementations of the box64 my_* syscall helpers.
 *
 * box64's own implementations live in src/wrapped/wrappedlibc.c, which is
 * EXCLUDED from the iOS build. x64syscall.c (compiled on iOS) references
 * my_open/my_mmap64/my_munmap/my_mprotect/my_stat/my_lstat/my_fstat/
 * my_fstatat/my_readlink from its active x64Syscall_linux dispatch switch;
 * without strong definitions here they fell into the auto-generated
 * `long sym(void){return 0;}` weak stubs, so every guest stat/open/mmap/
 * munmap/mprotect syscall silently failed.
 *
 * Compiled like ios_os.c: WITH the compat header + box64 include dirs, WITHOUT
 * the -Dexit macros. Host fd/path calls go through the box64_raw_* layer so
 * LiveContainer's interposer cannot corrupt them.
 *
 * The guest expects the x86_64 Linux struct stat (144-byte packed layout).
 * Darwin's struct stat has a different field order/sizes, so the Linux
 * UnalignStat64 helper is NOT usable here — the fields are copied by name.
 */

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include "../Include/rawlibc.h"

typedef struct x64emu_s x64emu_t;

#define X86_PAGE_SIZE 4096UL

/* box64 custommem/emulation state (src/custommem.c, src/libtools/env.c —
   both compiled on iOS). */
extern void *box_mmap(void *addr, size_t length, int prot, int flags, int fd, ssize_t offset);
extern int box_munmap(void *addr, size_t length);
extern void updateProtection(uintptr_t addr, size_t size, uint32_t prot);
extern void freeProtection(uintptr_t addr, size_t size);
extern uint32_t getProtection(uintptr_t addr);
extern void RemoveMapping(uintptr_t addr, size_t length);
extern uintptr_t box64_pagesize;

/* box64's per-mapping tracking flags (custommem.h), used to strip the custom
   bits out of the stored protection before merging it into a host mprotect. */
#define PROT_NEVERCLEAN 0x100
#define PROT_DYNAREC    0x80
#define PROT_DYNAREC_R  0x40
#define PROT_NOPROT     0x20
#define PROT_CUSTOM     (PROT_DYNAREC | PROT_DYNAREC_R | PROT_NOPROT | PROT_NEVERCLEAN)

#ifndef AT_EMPTY_PATH
#define AT_EMPTY_PATH 0x1000
#endif
#define LINUX_AT_FDCWD (-100)

/* x86_64 Linux struct stat, packed 144-byte layout (box64 myalign.h x64_stat64). */
struct ios_x64_stat64 {
    uint64_t st_dev;        /* 0   */
    uint64_t st_ino;        /* 8   */
    uint64_t st_nlink;      /* 16  */
    uint32_t st_mode;       /* 24  */
    uint32_t st_uid;        /* 28  */
    uint32_t st_gid;        /* 32  */
    uint64_t st_rdev;       /* 40  */
    int64_t st_size;        /* 48  */
    int64_t st_blksize;     /* 56  */
    uint64_t st_blocks;     /* 64  */
    struct timespec st_atim;      /* 72  */
    struct timespec st_mtim;      /* 88  */
    struct timespec st_ctim;      /* 104 */
    uint64_t __glibc_reserved[3]; /* 120 */
} __attribute__((packed));        /* 144 */

static void stat64_to_guest(const struct stat *st, void *buf)
{
    struct ios_x64_stat64 *d = (struct ios_x64_stat64 *)buf;
    d->st_dev = (uint64_t)st->st_dev;
    d->st_ino = (uint64_t)st->st_ino;
    d->st_nlink = (uint64_t)st->st_nlink;
    d->st_mode = (uint32_t)st->st_mode;
    d->st_uid = (uint32_t)st->st_uid;
    d->st_gid = (uint32_t)st->st_gid;
    d->st_rdev = (uint64_t)st->st_rdev;
    d->st_size = (int64_t)st->st_size;
    d->st_blksize = (int64_t)st->st_blksize;
    d->st_blocks = (uint64_t)st->st_blocks;
    d->st_atim.tv_sec = st->st_atimespec.tv_sec;
    d->st_atim.tv_nsec = st->st_atimespec.tv_nsec;
    d->st_mtim.tv_sec = st->st_mtimespec.tv_sec;
    d->st_mtim.tv_nsec = st->st_mtimespec.tv_nsec;
    d->st_ctim.tv_sec = st->st_ctimespec.tv_sec;
    d->st_ctim.tv_nsec = st->st_ctimespec.tv_nsec;
    d->__glibc_reserved[0] = 0;
    d->__glibc_reserved[1] = 0;
    d->__glibc_reserved[2] = 0;
}

int32_t my_open(x64emu_t *emu, void *pathname, int32_t flags, uint32_t mode)
{
    (void)emu;
    return box64_raw_open((const char *)pathname, flags, (int)mode);
}

ssize_t my_readlink(x64emu_t *emu, void *path, void *buf, size_t sz)
{
    (void)emu;
    return box64_raw_readlink((const char *)path, (char *)buf, sz);
}

int my_stat(x64emu_t *emu, void *filename, void *buf)
{
    (void)emu;
    struct stat st;
    int r = box64_raw_stat((const char *)filename, &st);
    if (!r)
        stat64_to_guest(&st, buf);
    return r;
}

int my_lstat(x64emu_t *emu, void *filename, void *buf)
{
    (void)emu;
    struct stat st;
    int r = box64_raw_lstat((const char *)filename, &st);
    if (!r)
        stat64_to_guest(&st, buf);
    return r;
}

int my_fstat(x64emu_t *emu, int fd, void *buf)
{
    (void)emu;
    struct stat st;
    int r = box64_raw_fstat(fd, &st);
    if (!r)
        stat64_to_guest(&st, buf);
    return r;
}

int my_fstatat(x64emu_t *emu, int fd, const char *path, void *buf, int flags)
{
    (void)emu;
    struct stat st;
    int r;
    if ((flags & AT_EMPTY_PATH) && path && !path[0])
        r = box64_raw_fstat(fd, &st);
    else if (fd == LINUX_AT_FDCWD || (path && path[0] == '/'))
        r = (flags & AT_SYMLINK_NOFOLLOW) ? box64_raw_lstat(path, &st) : box64_raw_stat(path, &st);
    else
        r = fstatat(fd, path, &st, flags);
    if (!r)
        stat64_to_guest(&st, buf);
    return r;
}

void *my_mmap64(x64emu_t *emu, void *addr, size_t length, int prot, int flags, int fd, ssize_t offset)
{
    (void)emu;
    return box_mmap(addr, length, prot, flags, fd, offset);
}

int my_munmap(x64emu_t *emu, void *addr, size_t length)
{
    (void)emu;
    int ret = box_munmap(addr, length);
    if (!ret) {
        freeProtection((uintptr_t)addr, length);
        RemoveMapping((uintptr_t)addr, length);
    }
    return ret;
}

int my_mprotect(x64emu_t *emu, void *addr, unsigned long len, int prot)
{
    (void)emu;
    if (prot & PROT_WRITE)
        prot |= PROT_READ;
    uintptr_t start = (uintptr_t)addr;
    if (box64_pagesize == X86_PAGE_SIZE) {
        int ret = mprotect(addr, len, prot);
        if (!ret && len)
            updateProtection(start, len, prot);
        return ret;
    }
    if (start & (X86_PAGE_SIZE - 1)) {
        errno = EINVAL;
        return -1;
    }
    if (!len)
        return 0;
    uintptr_t end = (start + len + X86_PAGE_SIZE - 1) & ~(X86_PAGE_SIZE - 1);
    uintptr_t host_start = start & ~(box64_pagesize - 1);
    uintptr_t host_end = (end + box64_pagesize - 1) & ~(box64_pagesize - 1);

    if (host_end - host_start == box64_pagesize && (start != host_start || end != host_end)) {
        prot |= getProtection(host_start) & ~PROT_CUSTOM;
        int ret = mprotect((void *)host_start, box64_pagesize, prot);
        if (!ret)
            updateProtection(host_start, box64_pagesize, prot);
        return ret;
    }

    if (start != host_start) {
        int host_prot = prot | (getProtection(host_start) & ~PROT_CUSTOM);
        int ret = mprotect((void *)host_start, box64_pagesize, host_prot);
        if (ret)
            return -1;
        updateProtection(host_start, box64_pagesize, host_prot);
        host_start += box64_pagesize;
    }
    if (end != host_end) {
        host_end -= box64_pagesize;
        int host_prot = prot | (getProtection(host_end) & ~PROT_CUSTOM);
        int ret = mprotect((void *)host_end, box64_pagesize, host_prot);
        if (ret)
            return -1;
        updateProtection(host_end, box64_pagesize, host_prot);
    }
    if (host_start == host_end)
        return 0;
    int ret = mprotect((void *)host_start, host_end - host_start, prot);
    if (!ret)
        updateProtection(host_start, host_end - host_start, prot);
    return ret;
}

/* ================================================================== */
/*  getdents / getdents64 over Darwin getdirentries64 (=344)          */
/* ================================================================== */
/* Linux has no getdirents64-equivalent on Darwin. We read native
   struct dirent64 entries (Darwin layout: d_ino, d_seekoff, d_reclen,
   d_namlen, d_type, d_name) and repack them into the x86_64 Linux layouts:
     - getdents64 (syscall 217): linux_dirent64  -> d_name at 19, d_type at 18
     - getdents   (syscall 78):  linux_dirent    -> d_name at 18, d_type in the
                                                    trailing byte (d_reclen-1)
   Guest d_off is mapped from Darwin's d_seekoff (a valid lseek cookie), so
   guest lseek-resume works. Every guest entry is the same size or smaller
   than its native source, so reading `count` native bytes into a temp buffer
   can always be repacked into the guest's `count` bytes. */

typedef struct {
    uint64_t d_ino;
    int64_t  d_off;
    uint16_t d_reclen;
    uint8_t  d_type;
    char     d_name[];
} ios_linux_dirent64_t;   /* x86_64 Linux getdents64 layout */

typedef struct {
    uint64_t d_ino;
    uint64_t d_off;
    uint16_t d_reclen;
    char     d_name[];
} ios_x86_dirent_t;       /* x86_64 Linux old getdents layout */

static ssize_t getdents_read_native(int fd, void *buf, size_t count)
{
    long pos = 0;
    return box64_raw_getdirentries64(fd, buf, count, &pos);
}

ssize_t my_getdents64(x64emu_t *emu, int fd, void *guest, size_t count)
{
    (void)emu;
    struct dirent64 *nat;
    ssize_t n;
    size_t off = 0, used = 0;
    if (!guest || count < sizeof(ios_linux_dirent64_t)) {
        errno = EINVAL;
        return -1;
    }
    nat = (struct dirent64 *)malloc(count);
    if (!nat) {
        errno = ENOMEM;
        return -1;
    }
    n = getdents_read_native(fd, nat, count);
    if (n <= 0) {
        free(nat);
        return n;
    }
    while (off < (size_t)n) {
        struct dirent64 *e = (struct dirent64 *)((char *)nat + off);
        size_t namlen = e->d_namlen;
        uint16_t reclen = (uint16_t)((19 + namlen + 1 + 7) & ~7ULL);
        if (used + reclen > count)
            break;
        {
            ios_linux_dirent64_t *d = (ios_linux_dirent64_t *)((char *)guest + used);
            d->d_ino = (uint64_t)e->d_ino;
            d->d_off = (int64_t)e->d_seekoff;
            d->d_reclen = reclen;
            d->d_type = (uint8_t)e->d_type;
            memcpy(d->d_name, e->d_name, namlen);
            memset(d->d_name + namlen, 0, reclen - 19 - namlen);
            used += reclen;
        }
        off += e->d_reclen;
    }
    free(nat);
    return (ssize_t)used;
}

ssize_t my_getdents(x64emu_t *emu, int fd, void *guest, size_t count)
{
    (void)emu;
    struct dirent64 *nat;
    ssize_t n;
    size_t off = 0, used = 0;
    if (!guest || count < sizeof(ios_x86_dirent_t)) {
        errno = EINVAL;
        return -1;
    }
    nat = (struct dirent64 *)malloc(count);
    if (!nat) {
        errno = ENOMEM;
        return -1;
    }
    n = getdents_read_native(fd, nat, count);
    if (n <= 0) {
        free(nat);
        return n;
    }
    while (off < (size_t)n) {
        struct dirent64 *e = (struct dirent64 *)((char *)nat + off);
        size_t namlen = e->d_namlen;
        uint16_t reclen = (uint16_t)((18 + namlen + 1 + 7) & ~7ULL);
        if (used + reclen > count)
            break;
        {
            ios_x86_dirent_t *d = (ios_x86_dirent_t *)((char *)guest + used);
            d->d_ino = (uint64_t)e->d_ino;
            d->d_off = (uint64_t)e->d_seekoff;
            d->d_reclen = reclen;
            memcpy(d->d_name, e->d_name, namlen);
            memset(d->d_name + namlen, 0, reclen - 18 - namlen - 1);
            ((uint8_t *)d)[reclen - 1] = (uint8_t)e->d_type;
            used += reclen;
        }
        off += e->d_reclen;
    }
    free(nat);
    return (ssize_t)used;
}
