#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/syscall.h>
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

int of_convert(int x) { return x; }

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
   to a raw syscall exit. Keeps libbox64.a linkable without box64_runner.o. */
static void (*g_exit_sink)(int) = NULL;

void box64_stub_set_exit_sink(void (*fn)(int)) {
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

/* Exit hand-off: g_exit_sink is wired by the runner at startup. When set it never
   returns (siglongjmp to the pad, or raw syscall exit). When NULL (CI Pass B, or
   exit before runner init) we fall back to the raw syscall — still never
   returning, still noreturn. */
static __attribute__((noreturn)) void exit_via_runner_or_raw(int status) {
    if (g_exit_sink) {
        g_exit_sink(status);
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
    exit_via_runner_or_raw(status);
}

/* Strong interposers. Note: ios_stubs.c is compiled WITHOUT the
   -Dexit/-D_exit CFLAGS macros, so these are real function definitions.
   All exit-family calls route through box64_runner_handle_exit: on the runner
   thread it recovers via the exit land-pad (app survives); elsewhere it does
   the real raw syscall exit (a genuine exit still exits). */

__attribute__((noreturn)) void exit(int status) {
    stub_exit_log("exit", status);
    exit_via_runner_or_raw(status);
}

__attribute__((noreturn)) void _exit(int status) {
    stub_exit_log("_exit", status);
    exit_via_runner_or_raw(status);
}

__attribute__((noreturn)) void _Exit(int status) {
    stub_exit_log("_Exit", status);
    exit_via_runner_or_raw(status);
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
