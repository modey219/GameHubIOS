#include "../Include/box64_bridge.h"
#include "../Include/syscall_translation.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <unistd.h>
#include <spawn.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <pthread.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>

extern char **environ;

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

static int copy_file(const char *src, const char *dst) {
    FILE *fsrc = fopen(src, "rb");
    if (!fsrc) return -1;
    FILE *fdst = fopen(dst, "wb");
    if (!fdst) { fclose(fsrc); return -1; }
    char buf[8192];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fsrc)) > 0) {
        if (fwrite(buf, 1, n, fdst) != n) {
            fclose(fsrc); fclose(fdst); return -1;
        }
    }
    fclose(fsrc);
    fclose(fdst);
    chmod(dst, 0755);
    return 0;
}

static int try_execute(const char *binary, char *args[], int wait) {
    pid_t pid;
    int r = posix_spawn(&pid, binary, NULL, NULL, args, environ);
    if (r == 0) {
        fprintf(stderr, "[Box64] Spawned PID %d: %s\n", pid, binary);
        if (wait) {
            int status;
            waitpid(pid, &status, 0);
            return (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1;
        }
        return 0;
    }
    fprintf(stderr, "[Box64] posix_spawn(%s) failed: %d (%s)\n", binary, r, strerror(r));
    return -r;
}

static void *wine_thread_func(void *arg) {
    char *wine_bin = (char *)arg;
    char *args[] = { wine_bin, NULL, NULL };
    args[1] = g_box64 ? g_box64->game_path : NULL;

    fprintf(stderr, "[Box64-Wine] Thread started: %s %s\n", wine_bin, args[1] ? args[1] : "");

    g_wine_running = 1;
    g_wine_exit_code = 0;
    g_wine_error[0] = 0;

    pid_t pid;
    int r = posix_spawn(&pid, wine_bin, NULL, NULL, args, environ);
    if (r != 0) {
        snprintf(g_wine_error, sizeof(g_wine_error),
                 "posix_spawn failed (%d): %s\nBinary: %s\n"
                 "iOS cannot execute binaries from Documents folder (noexec).\n"
                 "Try: copy binary to /tmp first, or use a jailbroken device.",
                 r, strerror(r), wine_bin);
        fprintf(stderr, "[Box64-Wine] %s\n", g_wine_error);
        g_wine_exit_code = -1;
        g_wine_running = 0;
        return NULL;
    }

    if (g_box64) g_box64->child_pid = pid;
    fprintf(stderr, "[Box64-Wine] Wine PID: %d\n", pid);

    int status;
    waitpid(pid, &status, 0);
    g_wine_exit_code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1;
    g_wine_running = 0;
    if (g_box64) g_box64->child_pid = -1;
    fprintf(stderr, "[Box64-Wine] Wine exited with code %d\n", g_wine_exit_code);
    return NULL;
}

int box64_launch_wine(box64_context_t *ctx, const char *exe_path, char **extra_envp) {
    if (!ctx || !ctx->initialized) return -1;
    g_wine_error[0] = 0;

    fprintf(stderr, "[Box64] Launching Wine: %s\n", exe_path);
    fprintf(stderr, "[Box64] Box64: %s\n", ctx->box64_path);
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

    fprintf(stderr, "[Box64] Starting Wine thread...\n");
    ctx->running = 1;

    pthread_t wine_thread;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);

    if (pthread_create(&wine_thread, &attr, wine_thread_func, wine_bin) != 0) {
        snprintf(g_wine_error, sizeof(g_wine_error), "Failed to create Wine thread: %s", strerror(errno));
        fprintf(stderr, "[Box64] %s\n", g_wine_error);
        ctx->running = 0;
        pthread_attr_destroy(&attr);
        return -1;
    }
    pthread_attr_destroy(&attr);

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
    char *args[] = { wine_bin, "wineboot", "--init", NULL };
    pid_t pid;
    int r = posix_spawn(&pid, wine_bin, NULL, NULL, args, environ);
    if (r != 0) return -r;
    int status;
    waitpid(pid, &status, 0);
    return (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1;
}

void box64_stop(box64_context_t *ctx) {
    if (!ctx) return;
    if (ctx->child_pid > 0) {
        kill(ctx->child_pid, SIGTERM);
        usleep(100000);
        kill(ctx->child_pid, SIGKILL);
        ctx->child_pid = -1;
    }
    ctx->running = 0;
}

int box64_is_running(box64_context_t *ctx) {
    return ctx ? (ctx->running && g_wine_running) : 0;
}

const char *box64_get_status(box64_context_t *ctx) {
    if (!ctx) return "not initialized";
    if (g_wine_error[0]) return g_wine_error;
    if (ctx->running && g_wine_running) return "running";
    if (ctx->running && !g_wine_running) return "wine exited";
    if (!ctx->initialized) return "not initialized";
    return "ready";
}

const char *box64_get_wine_error(void) {
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
