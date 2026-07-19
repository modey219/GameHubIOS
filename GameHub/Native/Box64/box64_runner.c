#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <setjmp.h>

extern char **environ;

typedef struct elfheader_s elfheader_t;
typedef struct x64emu_s x64emu_t;

extern int initialize(int argc, const char **argv, char **env, x64emu_t **emulator, elfheader_t **elfheader, int exec);
extern int emulate(x64emu_t *emu, elfheader_t *elf_header);
extern void endBox64(void);
extern int box64_quit;

static jmp_buf g_exit_jmpbuf;
static volatile int g_exit_jmp_active = 0;
static volatile int g_runner_running = 0;
static volatile int g_runner_exit_code = 0;
static char g_runner_error[1024] = {0};
static char g_runner_status[256] = {0};

void box64_exit_intercept(int code) {
    if (g_exit_jmp_active) {
        g_runner_exit_code = code;
        g_runner_running = 0;
        snprintf(g_runner_status, sizeof(g_runner_status), "exit(%d)", code);
        longjmp(g_exit_jmpbuf, code + 1);
    }
    _exit(code);
}

typedef struct {
    const char *wine64_path;
    const char *game_exe;
    const char *prefix_path;
} wine_runner_args_t;

static void *wine_thread_func(void *arg) {
    wine_runner_args_t *wargs = (wine_runner_args_t *)arg;

    g_runner_running = 1;
    g_runner_exit_code = 0;
    g_runner_error[0] = 0;
    snprintf(g_runner_status, sizeof(g_runner_status), "initializing");

    fprintf(stderr, "[Runner] wine64_path=%s\n", wargs->wine64_path);
    fprintf(stderr, "[Runner] game_exe=%s\n", wargs->game_exe ? wargs->game_exe : "(null)");
    fprintf(stderr, "[Runner] prefix_path=%s\n", wargs->prefix_path ? wargs->prefix_path : "(null)");

    const char *argv[] = {
        "box64",
        wargs->wine64_path,
        wargs->game_exe ? wargs->game_exe : "",
        NULL
    };
    int argc = wargs->game_exe ? 3 : 2;

    x64emu_t *emu = NULL;
    elfheader_t *elf_header = NULL;

    int jmp_result = setjmp(g_exit_jmpbuf);
    if (jmp_result != 0) {
        fprintf(stderr, "[Runner] Caught exit (code=%d)\n", g_runner_exit_code);
        g_runner_running = 0;
        return NULL;
    }
    g_exit_jmp_active = 1;

    fprintf(stderr, "[Runner] Calling initialize(%d)\n", argc);
    int ret = initialize(argc, argv, environ, &emu, &elf_header, 1);
    if (ret != 0) {
        snprintf(g_runner_error, sizeof(g_runner_error),
                 "Box64 initialize() failed (code %d)", ret);
        fprintf(stderr, "[Runner] %s\n", g_runner_error);
        g_runner_running = 0;
        g_runner_exit_code = -1;
        g_exit_jmp_active = 0;
        return NULL;
    }

    snprintf(g_runner_status, sizeof(g_runner_status), "emulating");
    fprintf(stderr, "[Runner] Initialize OK, calling emulate()\n");

    ret = emulate(emu, elf_header);

    fprintf(stderr, "[Runner] emulate() returned %d\n", ret);
    g_runner_exit_code = ret;
    g_runner_running = 0;
    g_exit_jmp_active = 0;
    snprintf(g_runner_status, sizeof(g_runner_status), "exited (%d)", ret);

    return NULL;
}

int box64_runner_start(const char *wine64_path, const char *game_exe, const char *prefix_path) {
    if (g_runner_running) {
        fprintf(stderr, "[Runner] Already running\n");
        return -1;
    }

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

    fprintf(stderr, "[Runner] Thread started\n");
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
