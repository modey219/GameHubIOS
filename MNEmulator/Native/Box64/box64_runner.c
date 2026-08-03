#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include <pthread.h>
#include <unistd.h>
#include <signal.h>
#include <sys/ucontext.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <setjmp.h>
#include <errno.h>
#include <dlfcn.h>
#include <sys/syscall.h>
#include "../Include/reallibc.h"
#include "../Include/rawlibc.h"

extern char **environ;

typedef struct elfheader_s elfheader_t;
typedef struct x64emu_s x64emu_t;

extern int initialize(int argc, const char **argv, char **env, x64emu_t **emulator, elfheader_t **elfheader, int exec);
extern int emulate(x64emu_t *emu, elfheader_t *elf_header);
extern void endBox64(void);
extern int box64_quit;

static volatile int g_runner_running = 0;
static volatile int g_runner_exit_code = 0;
static char g_runner_error[256] = {0};
static char g_runner_status[64] = {0};
static char g_log_path[256] = {0};
static volatile int g_log_fd = -1;
static pthread_mutex_t g_runner_lock = PTHREAD_MUTEX_INITIALIZER;

/* Preferred log directory, set from Swift (app Documents) via
   box64_runner_set_log_dir so the runner log lands somewhere reachable. */
static char g_runner_log_dir[512] = {0};

/* Exec-style argv handed to box64's initialize(): all strings live contiguously
   in one writable buffer (g_argv_block) and g_box64_argv[] points into it.
   Globals (not locals) so the value survives siglongjmp back to the crash/exit
   landing pads, which free them. Only one runner thread runs at a time. */
static char *g_argv_block = NULL;
static char **g_box64_argv = NULL;
static int g_box64_argc = 0;

static sigjmp_buf g_jmp_buf;
static volatile int g_jmp_ready = 0;
static pthread_t g_runner_thread_id;

/* Last SIGSEGV/SIGBUS context, captured async-safe in signal_handler and then
   symbolicated (dladdr is NOT async-signal-safe) after the runner recovers via
   siglongjmp, so the exact crash site in box64 is identifiable. */
static volatile uintptr_t g_crash_pc = 0;
static volatile uintptr_t g_crash_lr = 0;
static volatile uintptr_t g_crash_frames[12];
static volatile int g_crash_nframes = 0;

/* Exit landing pad: box64_exit_intercept (and the strong exit/_exit/_Exit
   interposers) NEVER return — exit() is noreturn, and returning into the call
   site is UB that silently killed the whole app in v375. They jump here instead
   so the runner thread ends cleanly and the iOS app stays alive. */
static sigjmp_buf g_exit_jmp_buf;
static volatile int g_exit_jmp_ready = 0;
static volatile int g_exit_status = 0;
static char g_exit_where[128] = {0};

/* Real libc pointers captured in setup_logging so the async-signal handler
   never calls the reallibc shims (dlsym is not async-signal-safe). */
static ssize_t (*g_real_write)(int, const void *, size_t) = NULL;
static int (*g_real_close)(int) = NULL;
static int (*g_real_fsync)(int) = NULL;

static const char *g_signal_names[32] = {
    NULL, "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP",
    "SIGABRT", "SIGEMT", "SIGFPE", "SIGKILL", "SIGBUS",
    "SIGSEGV", "SIGSYS", "SIGPIPE", "SIGALRM", "SIGTERM",
    "SIGURG", "SIGSTOP", "SIGTSTP", "SIGCONT", "SIGCHLD",
    "SIGTTIN", "SIGTTOU", "SIGIO", "SIGXCPU", "SIGXFSZ",
    "SIGVTALRM", "SIGPROF", "SIGWINCH", "SIGINFO", "SIGUSR1", "SIGUSR2"
};

/* Alternate stack so the crash handler can run safely even when the main
   thread stack is exhausted (stack overflow would otherwise hard-kill). */
static char g_altstack[128 * 1024];

static void runner_write(int fd, const char *buf, size_t n) {
    if (g_real_write) g_real_write(fd, buf, n);
    else syscall(SYS_write, fd, buf, n);
}
static void runner_close(int fd) {
    if (g_real_close) g_real_close(fd);
    else syscall(SYS_close, fd);
}
static void runner_fsync(void) {
    if (g_log_fd < 0) return;
    if (g_real_fsync) g_real_fsync(g_log_fd);
    else syscall(SYS_fsync, g_log_fd);
}

static void raw_log(const char *msg) {
    if (g_log_fd >= 0) {
        runner_write(g_log_fd, msg, strlen(msg));
        runner_write(g_log_fd, "\n", 1);
    }
}

static void runner_log(const char *fmt, ...) {
    char buf[512];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    raw_log(buf);
}

/* Flush a milestone to disk immediately so a hard kill still leaves a trail. */
static void runner_log_sync(void) {
    runner_fsync();
}

/* Noreturn sink for every intercepted exit. Declared in rawlibc.h.
   On the runner thread with the exit land-pad armed: siglongjmp back to
   wine_thread_func so the app survives and we get a definitive end-line in the
   runner log. Anywhere else (foreign thread, pad not armed): the real exit is
   the only sane action — raw syscall so it can't loop back into us.
   ra + where pin down the EXACT exit(0) call site (dlsym'd by ios_stubs.c),
   discriminating the candidates inside box64's initialize(). */
__attribute__((noreturn))
void box64_runner_handle_exit(int status, void *ra, const char *where) {
    int on_runner = pthread_equal(pthread_self(), g_runner_thread_id);
    const char *ex = getenv("BOX64_EXIT");
    const char *ver = getenv("BOX64_VERSION");
    const char *winedbg = getenv("BOX64_WINEDBG");
    const char *nobanner = getenv("BOX64_NOBANNER");
    runner_log("[Runner] box64_runner_handle_exit(%d) on_runner=%d pad_armed=%d RA=0x%llx where=%s",
               status, on_runner, g_exit_jmp_ready,
               (unsigned long long)(uintptr_t)ra, where ? where : "(none)");
    runner_log("[Runner]   env: BOX64_EXIT=%s BOX64_VERSION=%s BOX64_WINEDBG=%s BOX64_NOBANNER=%s",
               ex ? ex : "(unset)", ver ? ver : "(unset)",
               winedbg ? winedbg : "(unset)", nobanner ? nobanner : "(unset)");
    if (where) {
        strncpy(g_exit_where, where, sizeof(g_exit_where) - 1);
        g_exit_where[sizeof(g_exit_where) - 1] = '\0';
    }
    if (g_exit_jmp_ready && on_runner) {
        g_exit_status = status;
        g_exit_jmp_ready = 0;
        siglongjmp(g_exit_jmp_buf, 1);
    }
    runner_log("[Runner] exit(%d) not recoverable here — raw syscall exit", status);
    runner_log_sync();
    syscall(SYS_exit, status);
    for (;;) {}
}

/* box64_exit_intercept is defined in ios_stubs.c (compiled into libbox64.a)
   Box64 source files call exit()/_exit()/_Exit() which the -D macros redirect
   there. Those functions (and the strong interposers) never return — they route
   through box64_runner_handle_exit above, which lands on the exit pad armed in
   wine_thread_func so the app survives. */

/* Async-signal-safe 64-bit hex writer (no libc, no dlsym). */
static void runner_write_hex(uintptr_t v, int digits) {
    char hx[16];
    if (digits <= 0 || digits > 16) digits = 16;
    for (int i = 0; i < digits; i++) {
        int d = (int)((v >> (uintptr_t)((digits - 1 - i) * 4)) & 0xF);
        hx[i] = (char)(d < 10 ? '0' + d : 'a' + d - 10);
    }
    runner_write(g_log_fd, hx, (size_t)digits);
}

static void signal_handler(int sig, siginfo_t *si, void *uc) {
    /* Everything here MUST be async-signal-safe. Manual conversions only. */

    if (g_log_fd >= 0) {
        runner_write(g_log_fd, "[CRASH] Signal ", 15);
        if (sig > 0 && sig < 32 && g_signal_names[sig]) {
            runner_write(g_log_fd, g_signal_names[sig], strlen(g_signal_names[sig]));
        } else {
            char sigbuf[16];
            int siglen = 0;
            int tmp = sig;
            if (tmp == 0) { sigbuf[siglen++] = '0'; }
            else {
                char rev[16];
                int rlen = 0;
                while (tmp > 0) { rev[rlen++] = '0' + (tmp % 10); tmp /= 10; }
                for (int i = rlen - 1; i >= 0; i--) sigbuf[siglen++] = rev[i];
            }
            runner_write(g_log_fd, sigbuf, (size_t)siglen);
        }
        runner_write(g_log_fd, " addr=0x", 8);
        uintptr_t addr = si ? (uintptr_t)si->si_addr : 0;
        runner_write_hex(addr, 16);
        /* arm64 ucontext: __ss has __pc/__lr/__fp(x29). Walk the frame-pointer
           chain to get a rough backtrace for pinpointing the SIGSEGV site. */
#if defined(__arm64__)
        {
            uintptr_t pc = 0, lr = 0, fp = 0;
            ucontext_t *u = (ucontext_t *)uc;
            if (u && u->uc_mcontext) {
                pc = (uintptr_t)u->uc_mcontext->__ss.__pc;
                lr = (uintptr_t)u->uc_mcontext->__ss.__lr;
                fp = (uintptr_t)u->uc_mcontext->__ss.__fp;
            }
            runner_write(g_log_fd, "\n[CRASH] pc=0x", 14);
            runner_write_hex(pc, 16);
            runner_write(g_log_fd, " lr=0x", 6);
            runner_write_hex(lr, 16);
            runner_write(g_log_fd, " fp=0x", 6);
            runner_write_hex(fp, 16);
            runner_write(g_log_fd, "\n[CRASH] frames:", 16);
            uintptr_t cur = fp;
            int nf = 0;
            for (int i = 0; i < 10; i++) {
                if (!cur || (cur & 0xF) != 0 || cur > 0x8000000000000000ULL)
                    break;
                uintptr_t next = 0, ret = 0;
                /* fp[0] = next fp, fp[1] = return address */
                next = ((uintptr_t *)cur)[0];
                ret = ((uintptr_t *)cur)[1];
                runner_write(g_log_fd, " 0x", 3);
                runner_write_hex(ret, 16);
                if (nf < 12) g_crash_frames[nf] = ret;
                nf++;
                if (!next || next <= cur) break;
                cur = next;
            }
            g_crash_nframes = nf;
            g_crash_pc = pc;
            g_crash_lr = lr;
            runner_write(g_log_fd, "\n", 1);
        }
#else
        (void)uc;
        runner_write(g_log_fd, "\n", 1);
#endif
        runner_fsync();
    }

    /* Only longjmp when the signal hit the runner thread. The sigaction is
       process-wide, so a crash on the main thread must NOT jump into the
       runner's jmp_buf (undefined behavior) — it falls through to _exit. */
    if (g_jmp_ready && pthread_equal(pthread_self(), g_runner_thread_id)) {
        siglongjmp(g_jmp_buf, sig);
    }
    /* If setjmp wasn't set up yet, or it's a foreign thread, exit — can't
       safely continue */
    _exit(128 + sig);
}

static void setup_altstack(void) {
    stack_t ss;
    memset(&ss, 0, sizeof(ss));
    ss.ss_sp = g_altstack;
    ss.ss_size = sizeof(g_altstack);
    ss.ss_flags = 0;
    sigaltstack(&ss, NULL);
}

static void install_runner_signals(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sigemptyset(&sa.sa_mask);
    sa.__sigaction_u.__sa_sigaction = signal_handler;
    sa.sa_flags = SA_SIGINFO | SA_ONSTACK;

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGFPE, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);
    sigaction(SIGTRAP, &sa, NULL);
    sigaction(SIGSYS, &sa, NULL);
    sigaction(SIGXCPU, &sa, NULL);
    sigaction(SIGXFSZ, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);
}

typedef struct {
    char *wine64_path;   /* strdup'd — must free after use */
    char *game_exe;      /* strdup'd — must free after use */
    char *prefix_path;   /* strdup'd — must free after use */
} wine_runner_args_t;

void box64_runner_set_log_dir(const char *dir) {
    if (!dir || !dir[0]) return;
    strncpy(g_runner_log_dir, dir, sizeof(g_runner_log_dir) - 1);
    g_runner_log_dir[sizeof(g_runner_log_dir) - 1] = '\0';
}

static void setup_logging(const char *prefix_path) {
    (void)prefix_path;
    const char *home = getenv("HOME");
    if (!home) home = "/tmp";

    /* O_APPEND is REQUIRED: box64_exit_intercept writes its [Stub] marker via a
       SEPARATE O_APPEND fd. If the runner's fd is not O_APPEND, the runner's next
       write lands at ITS OWN stale offset and overwrites the [Stub] line (v376's
       exit-intercept RA trace was silently clobbered this way). */
    if (g_runner_log_dir[0]) {
        box64_raw_mkdir(g_runner_log_dir, 0755);
        snprintf(g_log_path, sizeof(g_log_path), "%s/box64_runner.log", g_runner_log_dir);
        g_log_fd = box64_raw_open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
    }
    if (g_log_fd < 0) {
        char docs[1024];
        snprintf(docs, sizeof(docs), "%s/Documents", home);
        box64_raw_mkdir(docs, 0755);
        snprintf(g_log_path, sizeof(g_log_path), "%s/box64_runner.log", docs);
        g_log_fd = box64_raw_open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
    }
    if (g_log_fd < 0) {
        snprintf(g_log_path, sizeof(g_log_path), "%s/box64_runner.log", home);
        g_log_fd = box64_raw_open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0644);
    }

    /* Capture real libc for use in the async-signal crash handler */
    g_real_write = (ssize_t (*)(int, const void *, size_t))reallibc_resolve("write");
    g_real_close = (int (*)(int))reallibc_resolve("close");
    g_real_fsync = (int (*)(int))reallibc_resolve("fsync");
    /* Point the exit/abort interposers at the same log file */
    box64_stub_set_log_path(g_log_path);
    /* Wire the noreturn exit sink so box64's exit()/_exit()/_Exit() calls route
       through the exit land-pad below instead of hard-killing the app. */
    box64_stub_set_exit_sink((void (*)(int, void *, const char *))box64_runner_handle_exit);
    runner_log("[Runner] ===== Box64 In-Process Runner =====");
    runner_log("[Runner] Log path: %s (fd=%d)", g_log_path, g_log_fd);
    runner_log_sync();
}

static void free_box64_argv(void) {
    if (g_argv_block) { free(g_argv_block); g_argv_block = NULL; }
    if (g_box64_argv) { free(g_box64_argv); g_box64_argv = NULL; }
    g_box64_argc = 0;
}

/* v383 fix for the box64_runner strlen(NULL) SIGSEGV (core.c:1116):
   box64 resolves its OWN binary via ResolveFile(argv[0]="box64",
   &box64_path) at core.c:1050. The box64_path collection is loaded from the
   BOX64_PATH env var (NewBox64Context loadPath). The runner never set it, and
   "box64" is not in the app CWD, so ResolveFile fell through to
   box_realpath("box64") which fails → box64path stayed NULL →
   box_strdup(NULL) → strlen(NULL) → SIGSEGV addr=0x0 in _platform_strlen.
   Fix: point BOX64_PATH at the bundled Box64 dir, derived from wine64_path
   ("<root>/Wine/bin/wine64" → "<root>/Box64"). */
static void setup_box64_env(const char *wine64_path) {
    if (!wine64_path || !wine64_path[0]) return;
    const char *w = strstr(wine64_path, "/Wine/bin/wine64");
    if (!w) w = strstr(wine64_path, "/Wine/bin/wine");
    if (!w) return;
    size_t rootlen = (size_t)(w - wine64_path);
    char box64dir[1024];
    int n = snprintf(box64dir, sizeof(box64dir), "%.*s/Box64", (int)rootlen, wine64_path);
    if (n <= 0 || n >= (int)sizeof(box64dir)) return;
    runner_log("[Runner] BOX64_PATH dir=%s", box64dir);
    const char *existing = getenv("BOX64_PATH");
    if (existing && existing[0]) {
        char full[2048];
        if (snprintf(full, sizeof(full), "%s:%s", existing, box64dir) < (int)sizeof(full))
            setenv("BOX64_PATH", full, 1);
    } else {
        setenv("BOX64_PATH", box64dir, 1);
    }
    runner_log("[Runner] setenv BOX64_PATH -> %s", getenv("BOX64_PATH") ? getenv("BOX64_PATH") : "(nil)");

    /* v387: point box64's emulated-lib search at the bundled x86_64 glibc
       (<root>/glibc, next to <root>/Box64). Box64 reads BOX64_LD_LIBRARY_PATH
       during NewBox64Context (core.c:490), which runs after this function in
       wine_thread_func, so setting it here is guaranteed to take effect even
       if Swift's setupEnvironment ordering changes. */
    char glibcdir[1024];
    int gl = snprintf(glibcdir, sizeof(glibcdir), "%.*s/glibc", (int)rootlen, wine64_path);
    if (gl > 0 && gl < (int)sizeof(glibcdir)) {
        const char *existing_ld = getenv("BOX64_LD_LIBRARY_PATH");
        if (existing_ld && existing_ld[0]) {
            char full[2048];
            if (snprintf(full, sizeof(full), "%s:%s", glibcdir, existing_ld) < (int)sizeof(full))
                setenv("BOX64_LD_LIBRARY_PATH", full, 1);
        } else {
            setenv("BOX64_LD_LIBRARY_PATH", glibcdir, 1);
        }
        runner_log("[Runner] setenv BOX64_LD_LIBRARY_PATH -> %s",
                   getenv("BOX64_LD_LIBRARY_PATH") ? getenv("BOX64_LD_LIBRARY_PATH") : "(nil)");
    }
}

/* v383 fix for box64's argv shuffle (core.c:1465-1473): box64 rewrites the
   guest args in place, shifting them down to argv[0], and requires the argv
   strings to be contiguous and writable like a real shell invocation. The
   previous layout passed a read-only literal ("box64") plus separately
   strdup'd heap strings, so diff = prog - argv[0] was garbage and the shuffle
   would write out of bounds / into read-only memory. Build one contiguous
   writable buffer holding "box64\0<wine64>\0<game>\0" and a pointer array
   into it, mirroring the old {box64, wine64, game, NULL} shape exactly. */
static int build_box64_argv(const char *wine64_path, const char *game_exe) {
    free_box64_argv();
    const char *a0 = "box64";
    const char *a1 = wine64_path ? wine64_path : "";
    const char *a2 = game_exe ? game_exe : "";
    size_t a0len = strlen(a0), a1len = strlen(a1), a2len = strlen(a2);
    size_t total = a0len + 1 + a1len + 1 + a2len + 1;
    g_argv_block = (char *)malloc(total);
    if (!g_argv_block) return -1;
    char *p = g_argv_block;
    memcpy(p, a0, a0len + 1); p += a0len + 1;
    memcpy(p, a1, a1len + 1); p += a1len + 1;
    memcpy(p, a2, a2len + 1); p += a2len + 1;

    g_box64_argc = game_exe ? 3 : 2;
    g_box64_argv = (char **)calloc((size_t)g_box64_argc + 1, sizeof(char *));
    if (!g_box64_argv) {
        free(g_argv_block);
        g_argv_block = NULL;
        g_box64_argc = 0;
        return -1;
    }
    g_box64_argv[0] = g_argv_block;
    g_box64_argv[1] = g_argv_block + a0len + 1;
    g_box64_argv[2] = g_argv_block + a0len + 1 + a1len + 1;
    g_box64_argv[g_box64_argc] = NULL;
    return 0;
}

static void *wine_thread_func(void *arg) {
    wine_runner_args_t *wargs = (wine_runner_args_t *)arg;

    g_runner_running = 1;
    g_runner_exit_code = 0;
    g_runner_error[0] = 0;
    g_runner_thread_id = pthread_self();

    runner_log("[Runner] wine_thread_func ENTERED (thread started)");

    /* Arm the safe landing pad FIRST (before installing handlers) so a signal
       can never arrive while g_jmp_ready==0 (which would _exit the whole app). */
    g_jmp_ready = 1;
    int crash_sig = sigsetjmp(g_jmp_buf, 1);
    if (crash_sig != 0) {
        /* We got here via siglongjmp from the signal handler */
        runner_log("[Runner] Recovered from signal %d — thread exiting safely", crash_sig);
        if (g_crash_pc) {
            Dl_info di;
            char sym[256];
            if (dladdr((void *)g_crash_pc, &di) && di.dli_sname) {
                snprintf(sym, sizeof(sym), "%s+0x%lx", di.dli_sname,
                         (unsigned long)((uintptr_t)g_crash_pc - (uintptr_t)di.dli_saddr));
            } else {
                snprintf(sym, sizeof(sym), "(no-symbol)");
            }
            runner_log("[Runner] crash pc=%s lr=0x%llx", sym,
                       (unsigned long long)g_crash_lr);
            for (int i = 0; i < g_crash_nframes && i < 12; i++) {
                Dl_info fd;
                char fsym[256];
                if (dladdr((void *)g_crash_frames[i], &fd) && fd.dli_sname) {
                    snprintf(fsym, sizeof(fsym), "%s+0x%lx", fd.dli_sname,
                             (unsigned long)((uintptr_t)g_crash_frames[i] - (uintptr_t)fd.dli_saddr));
                } else {
                    snprintf(fsym, sizeof(fsym), "0x%llx", (unsigned long long)g_crash_frames[i]);
                }
                runner_log("[Runner]   #%d %s", i, fsym);
            }
        }
        runner_log_sync();
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Box64 crashed with signal %d", crash_sig);
        pthread_mutex_unlock(&g_runner_lock);
        g_runner_exit_code = -crash_sig;
        free_box64_argv();
        free(wargs->wine64_path); free(wargs->game_exe); free(wargs->prefix_path);
        free(wargs);
        if (g_log_fd >= 0) { box64_raw_close(g_log_fd); g_log_fd = -1; }
        return NULL;
    }

    setup_altstack();
    install_runner_signals();

    /* Second landing pad, armed before initialize(): if Box64 calls exit()
       (noreturn), box64_runner_handle_exit siglongjmps here instead of the
       v375 UB return that killed the whole app. */
    g_exit_jmp_ready = 1;
    int exit_ret = sigsetjmp(g_exit_jmp_buf, 1);
    if (exit_ret != 0) {
        int code = g_exit_status;
        runner_log("[Runner] Box64 exit(%d) intercepted — runner thread ending cleanly (where=%s)",
                   code, g_exit_where[0] ? g_exit_where : "(unknown)");
        runner_log_sync();
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Box64 exited with code %d", code);
        snprintf(g_runner_status, sizeof(g_runner_status), "exited");
        pthread_mutex_unlock(&g_runner_lock);
        g_runner_exit_code = code;
        g_runner_running = 0;
        free_box64_argv();
        free(wargs->wine64_path); free(wargs->game_exe); free(wargs->prefix_path);
        free(wargs);
        if (g_log_fd >= 0) { box64_raw_close(g_log_fd); g_log_fd = -1; }
        return NULL;
    }

    runner_log("[Runner] wine64_path=%s", wargs->wine64_path);
    runner_log("[Runner] game_exe=%s", wargs->game_exe ? wargs->game_exe : "(null)");
    runner_log("[Runner] prefix_path=%s", wargs->prefix_path ? wargs->prefix_path : "(null)");

    /* v383: let box64 resolve its own binary (BOX64_PATH) and hand it a real
       exec-style contiguous argv (see setup_box64_env / build_box64_argv). */
    setup_box64_env(wargs->wine64_path);
    if (build_box64_argv(wargs->wine64_path, wargs->game_exe) != 0) {
        runner_log("[Runner] FAILED to build box64 argv");
        runner_log_sync();
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Failed to build box64 argv");
        pthread_mutex_unlock(&g_runner_lock);
        g_runner_running = 0;
        g_runner_exit_code = -1;
        free(wargs->wine64_path); free(wargs->game_exe); free(wargs->prefix_path);
        free(wargs);
        if (g_log_fd >= 0) { box64_raw_close(g_log_fd); g_log_fd = -1; }
        return NULL;
    }
    int argc = g_box64_argc;
    const char **argv = (const char **)g_box64_argv;
    runner_log("[Runner] box64 argv: argv[0]=%s argv[1]=%s argv[2]=%s",
               argv[0], argv[1], g_box64_argc > 2 ? argv[2] : "(none)");
    runner_log_sync();

    x64emu_t *emu = NULL;
    elfheader_t *elf_header = NULL;

    /* v378 diagnostic: which box64rc source could have set BOX64_EXIT, and is
       NORCFILES actually active? Log existence of the two likely files and the
       relevant env vars so the culprit is identifiable in box64_runner.log. */
    {
        const char *norcfiles = getenv("BOX64_NORCFILES");
        const char *envfile = getenv("BOX64_ENVFILE");
        runner_log("[Runner] rcstate: BOX64_NORCFILES=%s BOX64_ENVFILE=%s",
                   norcfiles ? norcfiles : "(unset)", envfile ? envfile : "(unset)");
        const char *home = getenv("HOME");
        char rcpath[512];
        struct stat st;
        snprintf(rcpath, sizeof(rcpath), "%s/.box64rc", home ? home : "/");
        runner_log("[Runner] rcstate: %s -> %s", rcpath,
                   box64_raw_stat(rcpath, &st) == 0 ? "EXISTS" : "absent");
        runner_log("[Runner] rcstate: /etc/box64.box64rc -> %s",
                   box64_raw_stat("/etc/box64.box64rc", &st) == 0 ? "EXISTS" : "absent");
        runner_log_sync();
    }

    runner_log("[Runner] Calling initialize(%d)", argc);
    runner_log_sync();
    int ret = initialize(argc, argv, environ, &emu, &elf_header, 1);
    runner_log("[Runner] initialize() returned %d", ret);
    runner_log_sync();

    if (ret != 0) {
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Box64 initialize() failed (code %d)", ret);
        pthread_mutex_unlock(&g_runner_lock);
        runner_log("[Runner] ERROR: %s", g_runner_error);
        g_runner_running = 0;
        g_runner_exit_code = -1;
        free_box64_argv();
        free(wargs->wine64_path); free(wargs->game_exe); free(wargs->prefix_path);
        free(wargs);
        if (g_log_fd >= 0) { box64_raw_close(g_log_fd); g_log_fd = -1; }
        return NULL;
    }

    pthread_mutex_lock(&g_runner_lock);
    snprintf(g_runner_status, sizeof(g_runner_status), "emulating");
    pthread_mutex_unlock(&g_runner_lock);
    runner_log("[Runner] Calling emulate()");
    runner_log_sync();

    ret = emulate(emu, elf_header);
    runner_log("[Runner] emulate() returned %d", ret);
    runner_log_sync();
    g_runner_exit_code = ret;
    g_runner_running = 0;

    free_box64_argv();
    free(wargs->wine64_path); free(wargs->game_exe); free(wargs->prefix_path);
    free(wargs);
    if (g_log_fd >= 0) { box64_raw_close(g_log_fd); g_log_fd = -1; }
    return NULL;
}

int box64_runner_start(const char *wine64_path, const char *game_exe, const char *prefix_path) {
    if (g_runner_running) {
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "runner already running (g_runner_running=1)");
        pthread_mutex_unlock(&g_runner_lock);
        return -1;
    }

    setup_logging(prefix_path);

    wine_runner_args_t *args = malloc(sizeof(wine_runner_args_t));
    if (!args) {
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Failed to allocate runner args");
        pthread_mutex_unlock(&g_runner_lock);
        return -1;
    }
    args->wine64_path = wine64_path ? strdup(wine64_path) : NULL;
    args->game_exe = game_exe ? strdup(game_exe) : NULL;
    args->prefix_path = prefix_path ? strdup(prefix_path) : NULL;

    pthread_mutex_lock(&g_runner_lock);
    g_runner_error[0] = 0;
    snprintf(g_runner_status, sizeof(g_runner_status), "starting");
    pthread_mutex_unlock(&g_runner_lock);
    g_runner_exit_code = 0;

    pthread_t thread;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    /* 8MB stack: the box64 interpreter + wine startup are stack-hungry and the
       iOS default (512KB) caused stack-overflow hard kills. */
    pthread_attr_setstacksize(&attr, 8 * 1024 * 1024);

    int ret = pthread_create(&thread, &attr, wine_thread_func, args);
    pthread_attr_destroy(&attr);

    if (ret != 0) {
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Failed to create runner thread: %d", ret);
        pthread_mutex_unlock(&g_runner_lock);
        runner_log("[Runner] pthread_create FAILED ret=%d errno=%d", ret, errno);
        g_runner_running = 0;
        free(args->wine64_path); free(args->game_exe); free(args->prefix_path);
        free(args);
        return -1;
    }

    runner_log("[Runner] Thread started successfully");
    runner_log_sync();
    return 0;
}

int box64_runner_stop(void) {
    if (!g_runner_running) return 0;
    box64_quit = 1;
    g_runner_running = 0;
    pthread_mutex_lock(&g_runner_lock);
    snprintf(g_runner_status, sizeof(g_runner_status), "stopping");
    pthread_mutex_unlock(&g_runner_lock);
    return 0;
}

int box64_runner_is_running(void) {
    return g_runner_running;
}

const char *box64_runner_get_error(void) {
    pthread_mutex_lock(&g_runner_lock);
    static char snap[256];
    memcpy(snap, g_runner_error, sizeof(snap));
    pthread_mutex_unlock(&g_runner_lock);
    return snap;
}

const char *box64_runner_get_status(void) {
    pthread_mutex_lock(&g_runner_lock);
    static char snap[64];
    memcpy(snap, g_runner_status, sizeof(snap));
    pthread_mutex_unlock(&g_runner_lock);
    return snap;
}

int box64_runner_get_exit_code(void) {
    return g_runner_exit_code;
}

const char *box64_runner_get_log_path(void) {
    return g_log_path;
}
