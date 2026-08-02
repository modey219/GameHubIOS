#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include <pthread.h>
#include <unistd.h>
#include <signal.h>
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

static sigjmp_buf g_jmp_buf;
static volatile int g_jmp_ready = 0;
static pthread_t g_runner_thread_id;

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

/* box64_exit_intercept is defined in ios_stubs.c (compiled into libbox64.a)
   Box64 source files call exit()/_exit()/_Exit() which the -D macros redirect
   there. Those functions just return, so the iOS app stays alive. */

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
        char hx[16];
        for (int i = 0; i < 16; i++) {
            int d = (int)((addr >> (uintptr_t)(60 - i * 4)) & 0xF);
            hx[i] = (char)(d < 10 ? '0' + d : 'a' + d - 10);
        }
        runner_write(g_log_fd, hx, 16);
        runner_write(g_log_fd, "\n", 1);
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

    if (g_runner_log_dir[0]) {
        box64_raw_mkdir(g_runner_log_dir, 0755);
        snprintf(g_log_path, sizeof(g_log_path), "%s/box64_runner.log", g_runner_log_dir);
        g_log_fd = box64_raw_open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    }
    if (g_log_fd < 0) {
        char docs[1024];
        snprintf(docs, sizeof(docs), "%s/Documents", home);
        box64_raw_mkdir(docs, 0755);
        snprintf(g_log_path, sizeof(g_log_path), "%s/box64_runner.log", docs);
        g_log_fd = box64_raw_open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    }
    if (g_log_fd < 0) {
        snprintf(g_log_path, sizeof(g_log_path), "%s/box64_runner.log", home);
        g_log_fd = box64_raw_open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    }

    /* Capture real libc for use in the async-signal crash handler */
    g_real_write = (ssize_t (*)(int, const void *, size_t))reallibc_resolve("write");
    g_real_close = (int (*)(int))reallibc_resolve("close");
    g_real_fsync = (int (*)(int))reallibc_resolve("fsync");
    runner_log("[Runner] ===== Box64 In-Process Runner =====");
    runner_log("[Runner] Log path: %s (fd=%d)", g_log_path, g_log_fd);
    runner_log_sync();
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
        runner_log_sync();
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Box64 crashed with signal %d", crash_sig);
        pthread_mutex_unlock(&g_runner_lock);
        g_runner_exit_code = -crash_sig;
        free(wargs->wine64_path); free(wargs->game_exe); free(wargs->prefix_path);
        free(wargs);
        if (g_log_fd >= 0) { box64_raw_close(g_log_fd); g_log_fd = -1; }
        return NULL;
    }

    setup_altstack();
    install_runner_signals();

    runner_log("[Runner] wine64_path=%s", wargs->wine64_path);
    runner_log("[Runner] game_exe=%s", wargs->game_exe ? wargs->game_exe : "(null)");
    runner_log("[Runner] prefix_path=%s", wargs->prefix_path ? wargs->prefix_path : "(null)");

    const char *argv[] = {
        "box64",
        wargs->wine64_path,
        wargs->game_exe ? wargs->game_exe : "",
        NULL
    };
    int argc = wargs->game_exe ? 3 : 2;

    x64emu_t *emu = NULL;
    elfheader_t *elf_header = NULL;

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
