#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdarg.h>
#include <errno.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <limits.h>
#include <sched.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include "../Include/rawlibc.h"

/* Box64 needs these Linux/glibc symbols that don't exist on iOS */

int __isnanf(float x) { return isnan((double)x); }
int __isinf(double x) { return isinf(x); }
int __isnan(double x) { return isnan(x); }

void sincos(double x, double *sinval, double *cosval) {
    *sinval = sin(x);
    *cosval = cos(x);
}
void sincosf(float x, float *sinval, float *cosval) {
    *sinval = sinf(x);
    *cosval = cosf(x);
}

typedef struct { void *emu; } x64emu_t;

void leave_critical_section(void *emu) { (void)emu; }
void enter_critical_section(void *emu) { (void)emu; }

int my_GetGthreadsGotInitialized(void) { return 0; }

x64emu_t *thread_get_emu(void) { return NULL; }

void *__libc_dlopen_mode(const char *name, int mode) { return dlopen(name, mode); }
void *__libc_dlsym(void *handle, const char *name) { return dlsym(handle, name); }
int __libc_dlclose(void *handle) { return dlclose(handle); }

/* ------------------------------------------------------------------ */
/* glibc heap aliases (box64's box_malloc family).                    */
/*                                                                     */
/* box64's src/include/debug.h maps box_malloc/box_realloc/box_calloc/ */
/* box_free/box_memalign to __libc_malloc/__libc_realloc/__libc_calloc */
/* /__libc_free/__libc_memalign unless ANDROID or STATICBUILD. The     */
/* file that normally defines those aliases is src/mallochook.c, which */
/* is EXCLUDED from the iOS build. Without real implementations here   */
/* the symbols fall into the auto-generated `long sym(void){return 0;}`*/
/* weak stubs, so box_malloc/box_realloc/box_calloc returned NULL.     */
/* The very first box_realloc in the process is at custommem.c:809     */
/* (map64_customMalloc, reached from rbtree_init("blockstree") via     */
/* wine_prereserve) — returning NULL there made rbtree.c write         */
/* p_blocks[i].block = NULL → SIGSEGV at addr=0x0 (v380 crash).        */
/* Strong definitions here override the weak auto-stubs at link time.  */
/*                                                                     */
/* libc malloc is NOT dyld-interposed (LiveContainer only interposes   */
/* path/fd functions), so plain malloc/calloc/realloc/free are safe.   */
/* ------------------------------------------------------------------ */
void *__libc_malloc(size_t size) { return malloc(size); }

void *__libc_calloc(size_t count, size_t size) { return calloc(count, size); }

void *__libc_realloc(void *ptr, size_t size) { return realloc(ptr, size); }

void __libc_free(void *ptr) { free(ptr); }

void *__libc_memalign(size_t alignment, size_t size)
{
    void *p = NULL;
    if (posix_memalign(&p, alignment, size) != 0)
        return NULL;
    return p;
}

/* box_strdup/box_realpath are also defined in the excluded mallochook.c.
   debug.h declares them extern, so without strong definitions here they
   fall into the same weak return-0 stubs and NULL out fullpath/argv/env
   (core.c:1268-1269, elfloader.c, pathcoll.c, etc.). Mirror the exact
   glibc-compatible semantics of mallochook.c. */
char *box_strdup(const char *s)
{
    size_t len = strlen(s);
    char *ret = (char *)calloc(1, len + 1);
    if (!ret)
        return NULL;
    memcpy(ret, s, len);
    return ret;
}

char *box_realpath(const char *path, char *ret)
{
    if (ret)
        return realpath(path, ret);
#ifdef PATH_MAX
    size_t path_max = PATH_MAX;
#else
    size_t path_max = pathconf(path, _PC_PATH_MAX);
    if (path_max <= 0)
        path_max = 4096;
#endif
    char tmp[path_max];
    char *p = realpath(path, tmp);
    if (!p)
        return NULL;
    return box_strdup(tmp);
}

int of_convert(int x) { return x; }

/* Box64's env layer calls GetEnv() for every BOX64_* variable during
   LoadEnvVariables() (env.c:702-752). Its only real implementations live in
   os_linux.c/os_wine.c — BOTH excluded from the iOS build — so GetEnv used to
   fall into the auto-generated `void GetEnv(void){}` weak stub, which returns
   its first argument (the variable NAME pointer) on arm64. Every BOX64_* var
   then looked "set" with garbage: BOX64_EXIT → p="BOX64_EXIT" → p[0]=='B'!='0'
   → box64env.exit=1 → applyCustomRules() called exit(0) (env.c:302) right
   after initialize(). A real getenv() makes the env parsing honest. */
void *GetEnv(const char *name) { return getenv(name); }

/* Box64's os layer (os_linux.c/os_wine.c) is excluded from the iOS build, so
   every one of these used to fall into the auto-generated void/return-garbage
   weak stubs (arm64 leaves the first arg in x0). Real implementations here:
   FileExist/MakeDir/FileSize use the raw-syscall layer (LiveContainer's
   interposer corrupts stat/mkdir), PrintfFtrace restores box64's log output. */
#define IS_EXECUTABLE (1 << 0)
#define IS_FILE       (1 << 1)

int FileExist(const char *filename, int flags)
{
    struct stat sb;
    if (box64_raw_stat(filename, &sb) == -1)
        return 0;
    if (flags == -1)
        return 1;
    if (flags & IS_FILE) {
        if (!S_ISREG(sb.st_mode))
            return 0;
    } else if (!S_ISDIR(sb.st_mode))
        return 0;
    if (flags & IS_EXECUTABLE) {
        if ((sb.st_mode & S_IXUSR) != S_IXUSR)
            return 0;
    }
    return 1;
}

int MakeDir(const char *folder)
{
    int ret = box64_raw_mkdir(folder, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
    if (ret == 0)
        return 1;
    if (errno == EEXIST)
        return 1;
    return 0;
}

size_t FileSize(const char *filename)
{
    struct stat sb;
    if (box64_raw_stat(filename, &sb) == -1)
        return 0;
    if (!S_ISREG(sb.st_mode))
        return 0;
    return (size_t)sb.st_size;
}

/* All of box64's logging (printf_log -> PrintfFtrace, see debug.h) goes
   through this. Without it every [BOX64] line silently vanished. Writes raw
   to fd 2 so it lands in the app's captured stderr.log. */
void PrintfFtrace(int prefix, const char *fmt, ...)
{
    char tmp[8192];
    int n = 0;
    if (prefix > 0) {
        n = snprintf(tmp, sizeof(tmp), "[BOX64] ");
        if (n < 0) return;
    }
    va_list args;
    va_start(args, fmt);
    int m = vsnprintf(tmp + n, sizeof(tmp) - n, fmt, args);
    va_end(args);
    if (m < 0) return;
    if (m >= (int)sizeof(tmp) - n)
        m = (int)sizeof(tmp) - n - 1;
    box64_raw_write(2, tmp, (size_t)(n + m));
}

int GetTID(void)
{
#ifdef SYS_gettid
    return (int)box64_raw_syscall_cls(SYS_gettid);
#else
    return (int)getpid();
#endif
}

/* Custommem's Mmap/MmapAnon/ELF loader all funnel through InternalMmap. On
   iOS anonymous PROT_EXEC requires MAP_JIT + the JIT entitlement (kernel
   rejects RWX/RX otherwise). Box64's RWX bridge + guest text mappings call
   here with PROT_EXEC: on a JIT-enabled session (StikDebug) the first attempt
   with MAP_JIT succeeds; on a jitless session it fails with ENOTSUP/EPERM, so
   we retry WITHOUT PROT_EXEC. That is safe — the interpreter only READS guest
   code, it never executes host pages, so a non-exec RW mapping is sufficient.
   libc mmap is NOT DYLD-interposed, so plain mmap() is safe (only path/fd
   functions are). */
void *InternalMmap(void *addr, unsigned long length, int prot, int flags, int fd, ssize_t offset)
{
#ifdef MAP_JIT
    int want_exec = (prot & PROT_EXEC) != 0;
    if (want_exec)
        flags |= MAP_JIT;
#endif
    void *ret = mmap(addr, length, prot, flags, fd, offset);
#ifdef MAP_JIT
    if (ret == MAP_FAILED && want_exec) {
        int saved_errno = errno;
        ret = mmap(addr, length, (prot & ~PROT_EXEC) | PROT_READ, flags & ~MAP_JIT, fd, offset);
        if (ret == MAP_FAILED)
            errno = saved_errno;
    }
#endif
    return ret;
}

int InternalMunmap(void *addr, unsigned long length)
{
    return munmap(addr, length);
}

/* ------------------------------------------------------------------ */
/* Process-wide exit/abort interposers (strong symbols).              */
/*                                                                     */
/* The app binary defines exit/_exit/_Exit/abort, so dyld binds EVERY  */
/* call to these in the whole process (including Box64's function-     */
/* pointer calls that the -Dexit/-D_exit CFLAGS macros can NOT reach). */
/* Each one writes a marker line to the stub log, then performs the    */
/* real action (raw svc for exit family, raise(SIGABRT) for abort so   */
/* the runner's signal handler can catch and recover it).              */
/* ------------------------------------------------------------------ */

static char g_stub_log_path[512] = {0};

/* Set by box64_runner at startup (box64_stub_set_exit_sink): the noreturn exit
   handler that siglongjmps to the runner's exit land-pad. NULL when the runner
   hasn't started (e.g. CI links, or exit before runner init) — then we fall back
   to a raw syscall exit. Keeps libbox64.a linkable without box64_runner.o.
   Args: status, the caller's return address (RA pinpoints the exact exit(0) call
   site in box64), and a dlsym'd "symbol+0xoffset" string. */
static void (*g_exit_sink)(int, void *, const char *) = NULL;

void box64_stub_set_exit_sink(void (*fn)(int, void *, const char *)) {
    g_exit_sink = fn;
}

void box64_stub_set_log_path(const char *path) {
    if (!path || !path[0]) return;
    strncpy(g_stub_log_path, path, sizeof(g_stub_log_path) - 1);
    g_stub_log_path[sizeof(g_stub_log_path) - 1] = '\0';
}

static const char *stub_log_effective_path(char *buf, size_t cap) {
    if (g_stub_log_path[0]) {
        strncpy(buf, g_stub_log_path, cap - 1);
        buf[cap - 1] = '\0';
        return buf;
    }
    const char *home = getenv("HOME");
    if (!home) home = "/tmp";
    snprintf(buf, cap, "%s/Documents/box64_runner.log", home);
    return buf;
}

static void stub_log_raw(const char *msg) {
    char path[512];
    stub_log_effective_path(path, sizeof(path));
    int fd = box64_raw_open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    box64_raw_write(fd, msg, strlen(msg));
    box64_raw_write(fd, "\n", 1);
    box64_raw_fsync(fd);
    box64_raw_close(fd);
}

static void stub_exit_log(const char *what, int code) {
    char buf[160];
    int n = snprintf(buf, sizeof(buf), "[Stub] %s(%d) called from pid=%d",
                     what, code, (int)getpid());
    if (n < 0) n = 0;
    if ((size_t)n >= sizeof(buf)) n = (int)sizeof(buf) - 1;
    buf[n] = '\0';
    stub_log_raw(buf);
}

/* Best-effort "symbol+0xoffset" for a return address. Used by the exit sink so
   the runner logs exactly WHICH exit(0) call site fired. */
static void format_where(void *ra, char *buf, size_t cap) {
    if (!buf || cap == 0) return;
    Dl_info info;
    if (ra && dladdr(ra, &info) && info.dli_sname) {
        snprintf(buf, cap, "%s+0x%lx",
                 info.dli_sname,
                 (unsigned long)((uintptr_t)ra - (uintptr_t)info.dli_saddr));
    } else {
        snprintf(buf, cap, "(no-symbol)");
    }
}

/* Exit hand-off: g_exit_sink is wired by the runner at startup. When set it never
   returns (siglongjmp to the pad, or raw syscall exit). When NULL (CI Pass B, or
   exit before runner init) we fall back to the raw syscall — still never
   returning, still noreturn. */
static __attribute__((noreturn)) void exit_via_runner_or_raw(int status, void *ra, const char *where) {
    if (g_exit_sink) {
        g_exit_sink(status, ra, where);
    }
    syscall(SYS_exit, status);
    for (;;) {}
}

/* exit() interceptor — when Box64 source calls exit(), the -Dexit macro
   redirects here. exit() is noreturn, so RETURNING into the call site is UB
   that silently killed the whole app in v375. We NEVER return. RA + dlsym
   symbol pin down exactly which exit(0) call site fired. */
__attribute__((noreturn))
void box64_exit_intercept(int status) {
    void *ra = __builtin_return_address(0);
    char trc[240];
    int n = snprintf(trc, sizeof(trc),
                     "[Stub] exit-intercept(%d) called from pid=%d RA=0x%llx",
                     status, (int)getpid(), (unsigned long long)(uintptr_t)ra);
    Dl_info info;
    if (dladdr(ra, &info) && info.dli_sname && n > 0 && (size_t)n < sizeof(trc)) {
        snprintf(trc + n, sizeof(trc) - (size_t)n, " in %s+0x%lx",
                 info.dli_sname,
                 (unsigned long)((uintptr_t)ra - (uintptr_t)info.dli_saddr));
    }
    stub_log_raw(trc);
    char where[160];
    format_where(ra, where, sizeof(where));
    exit_via_runner_or_raw(status, ra, where);
}

/* Strong interposers. Note: ios_stubs.c is compiled WITHOUT the
   -Dexit/-D_exit CFLAGS macros, so these are real function definitions.
   All exit-family calls route through box64_runner_handle_exit: on the runner
   thread it recovers via the exit land-pad (app survives); elsewhere it does
   the real raw syscall exit (a genuine exit still exits). */

__attribute__((noreturn)) void exit(int status) {
    void *ra = __builtin_return_address(0);
    stub_exit_log("exit", status);
    char where[160];
    format_where(ra, where, sizeof(where));
    exit_via_runner_or_raw(status, ra, where);
}

__attribute__((noreturn)) void _exit(int status) {
    void *ra = __builtin_return_address(0);
    stub_exit_log("_exit", status);
    char where[160];
    format_where(ra, where, sizeof(where));
    exit_via_runner_or_raw(status, ra, where);
}

__attribute__((noreturn)) void _Exit(int status) {
    void *ra = __builtin_return_address(0);
    stub_exit_log("_Exit", status);
    char where[160];
    format_where(ra, where, sizeof(where));
    exit_via_runner_or_raw(status, ra, where);
}

__attribute__((noreturn)) void abort(void) {
    stub_exit_log("abort", 134);
    /* raise() delivers the signal; the runner's handler catches SIGABRT and
       recovers (writes a [CRASH] marker), instead of us exiting directly. */
    raise(SIGABRT);
    /* Fallback if the handler chose to return (not longjmp): die for real. */
    syscall(SYS_exit, 134);
    __builtin_unreachable();
}

/* ------------------------------------------------------------------ */
/* Remaining os-layer functions that are self-contained (no box64       */
/* internal structs needed). The box64-struct-dependent ones (segment  */
/* base, syscall emu entry points) live in ios_os.c.                   */
/*                                                                     */
/* Without strong definitions here these fell into the auto-generated  */
/* `long sym(void){return 0;}` weak stubs: IsBridgeSignature returned  */
/* 0 so box64 never recognized its own native-call bridges, ReadTSC/   */
/* ReadTSCFrequency returned 0 (garbage TSC timing), and the bridge    */
/* logging names were NULL.                                            */
/* ------------------------------------------------------------------ */

int IsBridgeSignature(char s, char c)
{
    return s == 'S' && c == 'C';
}

int SchedYield(void)
{
    return sched_yield();
}

/* Note: ReadTSC/ReadTSCFrequency are NOT defined here — src/os/freq_wine.c
   is compiled on iOS and already provides the arm64 cntvct_el0/cntfrq_el0
   implementations. Defining them here caused duplicate symbols at link. */

/* getBridgeName is defined in src/tools/bridge.c (compiled on iOS). */
extern const char *getBridgeName(void *addr);

const char *GetBridgeName(void *p)
{
    return getBridgeName(p);
}

const char *GetNativeName(void *p, int lib)
{
    const char *n = GetBridgeName(p);
    if (n)
        return n;
    Dl_info info;
    if (dladdr(p, &info) && info.dli_sname) {
        static __thread char native_name[500] = { 0 };
        strcpy(native_name, info.dli_sname);
        if (lib && info.dli_fname) {
            strcat(native_name, "(");
            strcat(native_name, info.dli_fname);
            strcat(native_name, ")");
        }
        return native_name;
    }
    return NULL;
}
