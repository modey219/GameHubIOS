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
box64_context_t *box64_create_step1(void);
int box64_create_step2a(box64_context_t *ctx);
int box64_create_step2b(box64_context_t *ctx);
void box64_create_step3(box64_context_t *ctx);
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

void c_diag(const char *s);
void install_crash_handler(const char *log_path);
void set_c_diag_docs_path(const char *path);
int box64_probe_magic(void);
void box64_probe_paths(const char *docs, const char *bundle, const char *tmpdir, const char *home, char *out, size_t out_len);
void box64_probe_trace_snapshot(char *dst, size_t cap);
void box64_set_probe_log_cb(box64_log_callback cb);
/* build-376: single-trial probe (Swift runs each on its own thread with a
   per-trial timeout, so one hung svc can't truncate the matrix). */
int box64_probe_trial(int kind, const char *path, int fd, int *out_r1, int *out_r2, int *out_errno);
int box64_probe_sysnums(char *out, size_t cap);

int box64_runner_start(const char *wine64_path, const char *game_exe, const char *prefix_path);
int box64_runner_stop(void);
int box64_runner_is_running(void);
const char *box64_runner_get_error(void);
const char *box64_runner_get_status(void);
int box64_runner_get_exit_code(void);
const char *box64_runner_get_log_path(void);

#endif
