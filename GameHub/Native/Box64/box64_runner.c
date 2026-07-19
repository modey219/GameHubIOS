#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>
#include <time.h>

extern char **environ;

typedef struct elfheader_s elfheader_t;
typedef struct x64emu_s x64emu_t;

extern int initialize(int argc, const char **argv, char **env, x64emu_t **emulator, elfheader_t **elfheader, int exec);
extern int emulate(x64emu_t *emu, elfheader_t *elf_header);
extern void endBox64(void);
extern int box64_quit;

static volatile int g_runner_running = 0;
static volatile int g_runner_exit_code = 0;
static char g_runner_error[1024] = {0};
static char g_runner_status[256] = {0};
static FILE *g_log_file = NULL;
static char g_log_path[512] = {0};

static void runner_log(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    if (g_log_file) {
        fprintf(g_log_file, "%s\n", buf);
        fflush(g_log_file);
    }
    fprintf(stderr, "%s\n", buf);
}

void runner_write_crash_log(const char *reason) {
    runner_log("[CRASH] %s", reason);
    if (g_log_file) {
        fflush(g_log_file);
        fclose(g_log_file);
        g_log_file = NULL;
    }
}

static void signal_handler(int sig) {
    const char *name = "unknown";
    switch(sig) {
        case SIGSEGV: name = "SIGSEGV"; break;
        case SIGBUS:  name = "SIGBUS"; break;
        case SIGABRT: name = "SIGABRT"; break;
        case SIGFPE:  name = "SIGFPE"; break;
        case SIGILL:  name = "SIGILL"; break;
    }
    char buf[256];
    snprintf(buf, sizeof(buf), "Caught signal %d (%s)", sig, name);
    runner_write_crash_log(buf);
    _exit(128 + sig);
}

typedef struct {
    const char *wine64_path;
    const char *game_exe;
    const char *prefix_path;
} wine_runner_args_t;

static void setup_logging(const char *prefix_path) {
    if (!prefix_path) {
        const char *home = getenv("HOME");
        if (!home) home = "/tmp";
        snprintf(g_log_path, sizeof(g_log_path), "%s/box64_runner.log", home);
    } else {
        snprintf(g_log_path, sizeof(g_log_path), "%s/box64_runner.log", prefix_path);
    }
    mkdir("/tmp", 0755);
    g_log_file = fopen(g_log_path, "w");
    if (!g_log_file) {
        snprintf(g_log_path, sizeof(g_log_path), "/tmp/box64_runner.log");
        g_log_file = fopen(g_log_path, "w");
    }
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

    runner_log("[Runner] ===== Box64 In-Process Runner =====");
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
    int ret = initialize(argc, argv, environ, &emu, &elf_header, 1);
    if (ret != 0) {
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Box64 initialize() failed (code %d)", ret);
        runner_log("[Runner] ERROR: %s", g_runner_error);
        g_runner_running = 0;
        g_runner_exit_code = -1;
        if (g_log_file) { fclose(g_log_file); g_log_file = NULL; }
        return NULL;
    }

    snprintf(g_runner_status, sizeof(g_runner_status), "emulating");
    runner_log("[Runner] Initialize OK, calling emulate()");

    ret = emulate(emu, elf_header);

    runner_log("[Runner] emulate() returned %d", ret);
    g_runner_exit_code = ret;
    g_runner_running = 0;
    snprintf(g_runner_status, sizeof(g_runner_status), "exited (%d)", ret);

    if (g_log_file) { fclose(g_log_file); g_log_file = NULL; }
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
