#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <signal.h>
#include <setjmp.h>
#include <sys/stat.h>
#include <fcntl.h>

extern char **environ;

typedef struct elfheader_s elfheader_t;
typedef struct x64emu_s x64emu_t;

extern void box64_set_exit_jmp(volatile jmp_buf *buf);

extern int initialize(int argc, const char **argv, char **env, x64emu_t **emulator, elfheader_t **elfheader, int exec);
extern int emulate(x64emu_t *emu, elfheader_t *elf_header);
extern void endBox64(void);
extern int box64_quit;

static volatile int g_runner_running = 0;
static volatile int g_runner_exit_code = 0;
static char g_runner_error[1024] = {0};
static char g_runner_status[256] = {0};
static char g_log_path[512] = {0};
static volatile int g_log_fd = -1;

static jmp_buf g_exit_jmp;
static volatile int g_exit_set = 0;

static void raw_log(const char *msg) {
    if (g_log_fd >= 0) {
        write(g_log_fd, msg, strlen(msg));
        write(g_log_fd, "\n", 1);
        fsync(g_log_fd);
    }
}

static void runner_log(const char *fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    raw_log(buf);
    fprintf(stderr, "%s\n", buf);
}

static void signal_handler(int sig) {
    const char *name = "unknown";
    switch(sig) {
        case SIGSEGV: name = "SIGSEGV"; break;
        case SIGBUS:  name = "SIGBUS"; break;
        case SIGABRT: name = "SIGABRT"; break;
        case SIGFPE:  name = "SIGFPE"; break;
        case SIGILL:  name = "SIGILL"; break;
        case SIGPIPE: name = "SIGPIPE"; break;
    }
    char buf[256];
    snprintf(buf, sizeof(buf), "[CRASH] Signal %d (%s)", sig, name);
    raw_log(buf);
    if (g_exit_set) {
        longjmp(g_exit_jmp, 128 + sig);
    }
    _exit(128 + sig);
}

typedef struct {
    const char *wine64_path;
    const char *game_exe;
    const char *prefix_path;
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
    snprintf(g_runner_status, sizeof(g_runner_status), "initializing");

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

    runner_log("[Runner] Setting up exit jump point...");
    int jump_val = setjmp(g_exit_jmp);
    if (jump_val != 0) {
        runner_log("[Runner] Caught exit/longjmp with code %d", jump_val);
        g_runner_exit_code = jump_val;
        g_runner_running = 0;
        snprintf(g_runner_status, sizeof(g_runner_status), "exited-via-intercept (%d)", jump_val);
        if (g_log_fd >= 0) { close(g_log_fd); g_log_fd = -1; }
        return NULL;
    }
    g_exit_set = 1;
    box64_set_exit_jmp(&g_exit_jmp);

    runner_log("[Runner] Calling initialize(%d)", argc);
    int ret = initialize(argc, argv, environ, &emu, &elf_header, 1);
    if (ret != 0) {
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Box64 initialize() failed (code %d)", ret);
        runner_log("[Runner] ERROR: %s", g_runner_error);
        g_runner_running = 0;
        g_runner_exit_code = -1;
        if (g_log_fd >= 0) { close(g_log_fd); g_log_fd = -1; }
        return NULL;
    }

    snprintf(g_runner_status, sizeof(g_runner_status), "emulating");
    runner_log("[Runner] Initialize OK, calling emulate()");

    ret = emulate(emu, elf_header);

    runner_log("[Runner] emulate() returned %d", ret);
    g_runner_exit_code = ret;
    g_runner_running = 0;
    snprintf(g_runner_status, sizeof(g_runner_status), "exited (%d)", ret);

    if (g_log_fd >= 0) { close(g_log_fd); g_log_fd = -1; }
    return NULL;
}

int box64_runner_start(const char *wine64_path, const char *game_exe, const char *prefix_path) {
    if (g_runner_running) {
        fprintf(stderr, "[Runner] Already running\n");
        return -1;
    }

    setup_logging(prefix_path);

    static wine_runner_args_t args;
    args.wine64_path = wine64_path;
    args.game_exe = game_exe;
    args.prefix_path = prefix_path;

    g_runner_error[0] = 0;
    g_runner_exit_code = 0;
    g_exit_set = 0;
    snprintf(g_runner_status, sizeof(g_runner_status), "starting");

    pthread_t thread;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

    int ret = pthread_create(&thread, &attr, wine_thread_func, &args);
    pthread_attr_destroy(&attr);

    if (ret != 0) {
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Failed to create runner thread: %d", ret);
        g_runner_running = 0;
        return -1;
    }

    runner_log("[Runner] Thread started successfully");
    return 0;
}

int box64_runner_stop(void) {
    if (!g_runner_running) return 0;
    box64_quit = 1;
    g_runner_running = 0;
    snprintf(g_runner_status, sizeof(g_runner_status), "stopping");
    return 0;
}

int box64_runner_is_running(void) {
    return g_runner_running;
}

const char *box64_runner_get_error(void) {
    return g_runner_error;
}

const char *box64_runner_get_status(void) {
    return g_runner_status;
}

int box64_runner_get_exit_code(void) {
    return g_runner_exit_code;
}

const char *box64_runner_get_log_path(void) {
    return g_log_path;
}
