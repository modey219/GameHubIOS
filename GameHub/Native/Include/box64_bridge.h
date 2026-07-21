#ifndef BOX64_BRIDGE_H
#define BOX64_BRIDGE_H

#include <sys/types.h>

typedef void (*box64_log_callback)(const char *msg);

typedef struct emulator_context emulator_context_t;

typedef struct {
    emulator_context_t *emulator;
    char box64_path[256];
    char wine_path[256];
    char prefix_path[256];
    char game_path[256];
    int initialized;
    int running;
    pid_t child_pid;
    box64_log_callback log_callback;
} box64_context_t;

box64_context_t *box64_create(void);
void box64_destroy(box64_context_t *ctx);

int box64_init(box64_context_t *ctx, const char *bundle_path);
int box64_set_wine_path(box64_context_t *ctx, const char *wine_path);
int box64_set_prefix(box64_context_t *ctx, const char *prefix_path);
int box64_set_game(box64_context_t *ctx, const char *game_exe);

int box64_launch_wine(box64_context_t *ctx, const char *exe_path, char **extra_envp);
int box64_launch_wine_prefix_init(box64_context_t *ctx);
void box64_stop(box64_context_t *ctx);

int box64_is_running(box64_context_t *ctx);
const char *box64_get_status(box64_context_t *ctx);

typedef struct {
    int has_box64;
    int has_wine;
    int has_wine_prefix;
    int wine_prefix_ready;
    long box64_size;
    long wine_size;
    char box64_version[64];
    char wine_version[64];
} box64_status_t;

box64_status_t box64_get_status_detail(box64_context_t *ctx);

const char *box64_get_wine_error(void);

void install_crash_handler(const char *log_path);

int box64_runner_start(const char *wine64_path, const char *game_exe, const char *prefix_path);
int box64_runner_stop(void);
int box64_runner_is_running(void);
const char *box64_runner_get_error(void);
const char *box64_runner_get_status(void);
int box64_runner_get_exit_code(void);
const char *box64_runner_get_log_path(void);

#endif
