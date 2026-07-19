#include "../Include/box64_bridge.h"
#include "../Include/syscall_translation.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>
#include <pthread.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>

static box64_context_t *g_box64 = NULL;
static int g_wine_exit_code = 0;
static int g_wine_running = 0;
static char g_wine_error[1024] = {0};

box64_context_t *box64_create(void) {
    box64_context_t *ctx = calloc(1, sizeof(box64_context_t));
    if (!ctx) return NULL;
    ctx->emulator = emulator_create();
    ctx->child_pid = -1;
    g_box64 = ctx;
    return ctx;
}

void box64_destroy(box64_context_t *ctx) {
    if (!ctx) return;
    box64_stop(ctx);
    emulator_destroy(ctx->emulator);
    if (ctx == g_box64) g_box64 = NULL;
    free(ctx);
}

static int file_exists(const char *path) {
    struct stat s;
    return stat(path, &s) == 0 && s.st_size > 0;
}

static long file_size(const char *path) {
    struct stat s;
    if (stat(path, &s) != 0) return 0;
    return s.st_size;
}

int box64_init(box64_context_t *ctx, const char *bundle_path) {
    if (!ctx || !bundle_path) return -1;
    snprintf(ctx->box64_path, sizeof(ctx->box64_path), "%s/box64", bundle_path);
    snprintf(ctx->wine_path, sizeof(ctx->wine_path), "%s/wine", bundle_path);
    snprintf(ctx->prefix_path, sizeof(ctx->prefix_path), "%s/wineprefix", bundle_path);
    snprintf(ctx->game_path, sizeof(ctx->game_path), "%s/games", bundle_path);
    mkdir(ctx->prefix_path, 0755);
    ctx->initialized = 1;
    return 0;
}

int box64_set_wine_path(box64_context_t *ctx, const char *wine_path) {
    if (!ctx) return -1;
    strncpy(ctx->wine_path, wine_path, sizeof(ctx->wine_path) - 1);
    return 0;
}

int box64_set_prefix(box64_context_t *ctx, const char *prefix_path) {
    if (!ctx) return -1;
    strncpy(ctx->prefix_path, prefix_path, sizeof(ctx->prefix_path) - 1);
    return 0;
}

int box64_set_game(box64_context_t *ctx, const char *game_exe) {
    if (!ctx) return -1;
    strncpy(ctx->game_path, game_exe, sizeof(ctx->game_path) - 1);
    return 0;
}

int box64_launch_wine(box64_context_t *ctx, const char *exe_path, char **extra_envp) {
    if (!ctx || !ctx->initialized) return -1;
    g_wine_error[0] = 0;

    fprintf(stderr, "[Box64] Launching Wine in-process: %s\n", exe_path);
    fprintf(stderr, "[Box64] Wine path: %s\n", ctx->wine_path);

    setenv("WINEPREFIX", ctx->prefix_path, 1);
    setenv("WINEDEBUG", "-all", 1);
    setenv("WINEESYNC", "1", 1);
    setenv("WINEFSYNC", "1", 1);
    setenv("STAGING_SHARED_MEMORY", "1", 1);
    setenv("DXVK_ASYNC", "1", 1);
    setenv("DXVK_HUD", "fps", 1);

    if (extra_envp) {
        for (int i = 0; extra_envp[i]; i++) {
            char *eq = strchr(extra_envp[i], '=');
            if (eq) {
                char k[256] = {0};
                int kl = (int)(eq - extra_envp[i]);
                if (kl < 255) { strncpy(k, extra_envp[i], kl); k[kl]=0; setenv(k, eq+1, 1); }
            }
        }
    }

    char wine_bin[1024];
    snprintf(wine_bin, sizeof(wine_bin), "%s/bin/wine64", ctx->wine_path);

    if (!file_exists(wine_bin)) {
        snprintf(g_wine_error, sizeof(g_wine_error), "Wine binary not found: %s", wine_bin);
        fprintf(stderr, "[Box64] %s\n", g_wine_error);
        return -1;
    }

    strncpy(ctx->game_path, exe_path, sizeof(ctx->game_path) - 1);

    fprintf(stderr, "[Box64] Starting Wine in-process via box64_runner...\n");
    ctx->running = 1;
    g_wine_running = 1;

    int rc = box64_runner_start(wine_bin, exe_path, ctx->prefix_path);
    if (rc != 0) {
        snprintf(g_wine_error, sizeof(g_wine_error),
                 "box64_runner_start failed (code %d)", rc);
        fprintf(stderr, "[Box64] %s\n", g_wine_error);
        ctx->running = 0;
        g_wine_running = 0;
        return -1;
    }

    return 0;
}

int box64_launch_wine_prefix_init(box64_context_t *ctx) {
    if (!ctx || !ctx->initialized) return -1;
    fprintf(stderr, "[Box64] Init prefix: %s\n", ctx->prefix_path);
    mkdir(ctx->prefix_path, 0755);
    setenv("WINEPREFIX", ctx->prefix_path, 1);
    setenv("WINEDEBUG", "-all", 1);

    char wine_bin[1024];
    snprintf(wine_bin, sizeof(wine_bin), "%s/bin/wine64", ctx->wine_path);
    if (!file_exists(wine_bin)) return -1;

    return box64_runner_start(wine_bin, "wineboot --init", ctx->prefix_path);
}

void box64_stop(box64_context_t *ctx) {
    if (!ctx) return;
    box64_runner_stop();
    ctx->running = 0;
    g_wine_running = 0;
}

int box64_is_running(box64_context_t *ctx) {
    return ctx ? box64_runner_is_running() : 0;
}

const char *box64_get_status(box64_context_t *ctx) {
    if (!ctx) return "not initialized";
    const char *runner_err = box64_runner_get_error();
    if (runner_err && runner_err[0]) return runner_err;
    if (box64_runner_is_running()) return "running";
    const char *runner_status = box64_runner_get_status();
    if (runner_status && runner_status[0]) return runner_status;
    if (!ctx->initialized) return "not initialized";
    return "ready";
}

const char *box64_get_wine_error(void) {
    const char *runner_err = box64_runner_get_error();
    if (runner_err && runner_err[0]) return runner_err;
    return g_wine_error;
}

box64_status_t box64_get_status_detail(box64_context_t *ctx) {
    box64_status_t status;
    memset(&status, 0, sizeof(status));
    if (!ctx) return status;
    status.has_box64 = file_exists(ctx->box64_path);
    status.has_wine = file_exists(ctx->wine_path);
    char wp[1024];
    snprintf(wp, sizeof(wp), "%s/system.reg", ctx->prefix_path);
    status.has_wine_prefix = file_exists(wp);
    status.wine_prefix_ready = status.has_wine_prefix;
    status.box64_size = file_size(ctx->box64_path);
    status.wine_size = file_size(ctx->wine_path);
    strncpy(status.box64_version, "0.4.2", sizeof(status.box64_version));
    strncpy(status.wine_version, "9.21", sizeof(status.wine_version));
    return status;
}
