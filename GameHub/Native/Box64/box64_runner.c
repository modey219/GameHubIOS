#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <setjmp.h>

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

static sigjmp_buf g_jmp_buf;
static volatile int g_jmp_ready = 0;

static void raw_log(const char *msg) {
    if (g_log_fd >= 0) {
        write(g_log_fd, msg, strlen(msg));
        write(g_log_fd, "\n", 1);
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

/* box64_exit_intercept is defined in ios_stubs.c (compiled into libbox64.a)
   Box64 source files call exit() which the -Dexit macro redirects there.
   That function just returns, so the iOS app stays alive. */

static void signal_handler(int sig) {
    /* Everything here MUST be async-signal-safe. No snprintf, no strlen, no malloc. */

    if (g_log_fd >= 0) {
        /* Write crash marker using only write() */
        const char *prefix = "[CRASH] Signal ";
        write(g_log_fd, prefix, sizeof("[CRASH] Signal ") - 1);
        /* Write signal number as decimal */
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
        write(g_log_fd, sigbuf, siglen);
        write(g_log_fd, "\n", 1);
        close(g_log_fd);
        g_log_fd = -1;
    }

    g_runner_running = 0;

    /* Do NOT call _exit — that kills the entire iOS app.
       Use siglongjmp to return to the safe setjmp point in wine_thread_func.
       This avoids infinite SIGSEGV loop from retrying the faulting instruction. */
    if (g_jmp_ready) {
        siglongjmp(g_jmp_buf, sig);
    }
    /* If setjmp wasn't set up yet, we must exit — can't safely continue */
    _exit(128 + sig);
}

typedef struct {
    char *wine64_path;   /* strdup'd — must free after use */
    char *game_exe;      /* strdup'd — must free after use */
    char *prefix_path;   /* strdup'd — must free after use */
} wine_runner_args_t;

static void setup_logging(const char *prefix_path) {
    const char *home = getenv("HOME");
    if (!home) home = "/tmp";
    snprintf(g_log_path, sizeof(g_log_path), "%s/Documents/box64_runner.log", home);
    g_log_fd = open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (g_log_fd < 0) {
        snprintf(g_log_path, sizeof(g_log_path), "%s/box64_runner.log", home);
        g_log_fd = open(g_log_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    }
    runner_log("[Runner] ===== Box64 In-Process Runner =====");
    runner_log("[Runner] Log path: %s (fd=%d)", g_log_path, g_log_fd);
}

static void *wine_thread_func(void *arg) {
    wine_runner_args_t *wargs = (wine_runner_args_t *)arg;

    g_runner_running = 1;
    g_runner_exit_code = 0;
    g_runner_error[0] = 0;

    signal(SIGSEGV, signal_handler);
    signal(SIGBUS, signal_handler);
    signal(SIGABRT, signal_handler);
    signal(SIGFPE, signal_handler);
    signal(SIGILL, signal_handler);
    signal(SIGPIPE, SIG_IGN);

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

    /* Set up sigsetjmp so signal_handler can longjmp back here
       instead of calling _exit() which kills the entire iOS app. */
    g_jmp_ready = 1;
    int crash_sig = sigsetjmp(g_jmp_buf, 1);
    if (crash_sig != 0) {
        /* We got here via siglongjmp from the signal handler */
        runner_log("[Runner] Recovered from signal %d — thread exiting safely", crash_sig);
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Box64 crashed with signal %d", crash_sig);
        pthread_mutex_unlock(&g_runner_lock);
        g_runner_exit_code = -crash_sig;
        free(wargs->wine64_path); free(wargs->game_exe); free(wargs->prefix_path);
        free(wargs);
        if (g_log_fd >= 0) { close(g_log_fd); g_log_fd = -1; }
        return NULL;
    }

    runner_log("[Runner] Calling initialize(%d)", argc);
    int ret = initialize(argc, argv, environ, &emu, &elf_header, 1);
    runner_log("[Runner] initialize() returned %d", ret);
    
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
        if (g_log_fd >= 0) { close(g_log_fd); g_log_fd = -1; }
        return NULL;
    }

    pthread_mutex_lock(&g_runner_lock);
    snprintf(g_runner_status, sizeof(g_runner_status), "emulating");
    pthread_mutex_unlock(&g_runner_lock);
    runner_log("[Runner] Calling emulate()");

    ret = emulate(emu, elf_header);
    runner_log("[Runner] emulate() returned %d", ret);
    g_runner_exit_code = ret;
    g_runner_running = 0;

    free(wargs->wine64_path); free(wargs->game_exe); free(wargs->prefix_path);
    free(wargs);
    if (g_log_fd >= 0) { close(g_log_fd); g_log_fd = -1; }
    return NULL;
}

int box64_runner_start(const char *wine64_path, const char *game_exe, const char *prefix_path) {
    if (g_runner_running) {
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

    int ret = pthread_create(&thread, &attr, wine_thread_func, args);
    pthread_attr_destroy(&attr);

    if (ret != 0) {
        pthread_mutex_lock(&g_runner_lock);
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Failed to create runner thread: %d", ret);
        pthread_mutex_unlock(&g_runner_lock);
        g_runner_running = 0;
        free(args->wine64_path); free(args->game_exe); free(args->prefix_path);
        free(args);
        return -1;
    }

    runner_log("[Runner] Thread started successfully");
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
