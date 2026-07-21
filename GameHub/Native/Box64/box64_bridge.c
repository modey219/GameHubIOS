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

static char g_crash_log_path[1024] = {0};
static char g_docs_path[1024] = {0};

static const char *g_signal_names[32] = {
    NULL, "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP",
    "SIGABRT", "SIGEMT", "SIGFPE", "SIGKILL", "SIGBUS",
    "SIGSEGV", "SIGSYS", "SIGPIPE", "SIGALRM", "SIGTERM",
    "SIGURG", "SIGSTOP", "SIGTSTP", "SIGCONT", "SIGCHLD",
    "SIGTTIN", "SIGTTOU", "SIGIO", "SIGXCPU", "SIGXFSZ",
    "SIGVTALRM", "SIGPROF", "SIGWINCH", "SIGINFO", "SIGUSR1", "SIGUSR2"
};

static void crash_signal_handler(int sig) {
    int fd = open(g_crash_log_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        const char *prefix = "[CRASH] Signal ";
        write(fd, prefix, 15);
        if (sig > 0 && sig < 32 && g_signal_names[sig]) {
            write(fd, g_signal_names[sig], strlen(g_signal_names[sig]));
        } else {
            char nbuf[16];
            int len = 0;
            int tmp = sig;
            if (tmp == 0) { nbuf[len++] = '0'; }
            else {
                char rev[16];
                int rlen = 0;
                while (tmp > 0) { rev[rlen++] = '0' + (tmp % 10); tmp /= 10; }
                for (int i = rlen - 1; i >= 0; i--) nbuf[len++] = rev[i];
            }
            write(fd, nbuf, len);
        }
        write(fd, "\n", 1);
        close(fd);
    }
    _exit(128 + sig);
}

void install_crash_handler(const char *log_path) {
    if (!log_path || !log_path[0]) return;
    strncpy(g_crash_log_path, log_path, sizeof(g_crash_log_path) - 1);
    g_crash_log_path[sizeof(g_crash_log_path) - 1] = '\0';
    // Also store the Documents directory by stripping "/crash.log"
    size_t lp_len = strlen(log_path);
    if (lp_len > 10) {
        size_t copy_len = lp_len - 10; // len of "/crash.log"
        if (copy_len > sizeof(g_docs_path) - 1) copy_len = sizeof(g_docs_path) - 1;
        memcpy(g_docs_path, log_path, copy_len);
        g_docs_path[copy_len] = '\0';
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sigfillset(&sa.sa_mask);
    sa.__sigaction_u.__sa_handler = crash_signal_handler;
    sa.sa_flags = SA_RESETHAND;

    sigaction(SIGSEGV, &sa, NULL);
    sigaction(SIGBUS, &sa, NULL);
    sigaction(SIGABRT, &sa, NULL);
    sigaction(SIGILL, &sa, NULL);
    sigaction(SIGFPE, &sa, NULL);
    sigaction(SIGTRAP, &sa, NULL);
}

static const char *get_docs_dir(void) {
    const char *crash_log = getenv("CRASH_LOG_PATH");
    if (crash_log && crash_log[0]) {
        size_t cl_len = strlen(crash_log);
        if (cl_len > 10) {
            size_t copy_len = cl_len - 10;
            static char docs[1024];
            if (copy_len < sizeof(docs) - 1) {
                memcpy(docs, crash_log, copy_len);
                docs[copy_len] = '\0';
                return docs;
            }
        }
    }
    if (g_docs_path[0]) return g_docs_path;
    return NULL;
}

static void bridge_log(const char *msg) {
    const char *docs = get_docs_dir();
    if (!docs) return;
    char path[1024];
    snprintf(path, sizeof(path), "%s/bridge.log", docs);
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        write(fd, msg, strlen(msg));
        write(fd, "\n", 1);
        close(fd);
    }
}

static void append_to_log(const char *base_path, const char *filename, const char *msg) {
    char full[1032];
    size_t blen = strlen(base_path);
    size_t flen = strlen(filename);
    if (blen + flen + 2 > sizeof(full)) return;
    memcpy(full, base_path, blen);
    full[blen] = '/';
    memcpy(full + blen + 1, filename, flen);
    full[blen + 1 + flen] = '\0';
    int fd = open(full, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        write(fd, msg, strlen(msg));
        write(fd, "\n", 1);
        close(fd);
    }
}

void c_diag(const char *s) {
    const char *docs = get_docs_dir();
    if (!docs) {
        const char *home = getenv("HOME");
        if (!home) return;
        char buf[1032];
        snprintf(buf, sizeof(buf), "%s/Documents", home);
        append_to_log(buf, "c_diag.log", s);
        append_to_log(buf, "diag.log", s);
        return;
    }
    append_to_log(docs, "c_diag.log", s);
    append_to_log(docs, "diag.log", s);
}

box64_context_t *box64_create(void) {
    c_diag("box64_create called");
    bridge_log("[Bridge] box64_create() called");
    box64_context_t *ctx = calloc(1, sizeof(box64_context_t));
    c_diag("box64_create: calloc done");
    bridge_log("[Bridge] box64_create: calloc done");
    volatile box64_context_t *vctx = ctx;
    if (!vctx) { c_diag("box64_create: calloc failed"); bridge_log("[Bridge] box64_create: calloc failed"); return NULL; }
    memset((void *)vctx, 0, sizeof(box64_context_t));
    c_diag("box64_create: ctx allocated OK");
    bridge_log("[Bridge] box64_create: ctx allocated OK");
    ctx->emulator = syscall_emulator_create();
    if (!ctx->emulator) {
        c_diag("box64_create: syscall_emulator_create returned NULL");
        bridge_log("[Bridge] box64_create: syscall_emulator_create returned NULL");
        free(ctx);
        return NULL;
    }
    c_diag("box64_create: emulator created OK");
    bridge_log("[Bridge] box64_create: emulator created OK");
    syscall_set_context(ctx->emulator);
    c_diag("box64_create: context set OK");
    bridge_log("[Bridge] box64_create: context set OK");
    ctx->child_pid = -1;
    g_box64 = ctx;
    c_diag("box64_create: DONE");
    bridge_log("[Bridge] box64_create: DONE");
    return ctx;
}

void box64_destroy(box64_context_t *ctx) {
    if (!ctx) return;
    box64_stop(ctx);
    syscall_set_context(NULL);
    syscall_emulator_destroy(ctx->emulator);
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
    c_diag("box64_init called");
    if (!ctx || !bundle_path) { c_diag("box64_init: bad args"); bridge_log("[Bridge] box64_init: bad args"); return -1; }
    char buf[1024];
    snprintf(buf, sizeof(buf), "[Bridge] box64_init(bundle=%s)", bundle_path);
    bridge_log(buf);
    snprintf(ctx->box64_path, sizeof(ctx->box64_path), "%s/box64", bundle_path);
    snprintf(ctx->wine_path, sizeof(ctx->wine_path), "%s/wine", bundle_path);
    snprintf(ctx->prefix_path, sizeof(ctx->prefix_path), "%s/wineprefix", bundle_path);
    snprintf(ctx->game_path, sizeof(ctx->game_path), "%s/games", bundle_path);
    c_diag("box64_init: about to mkdir");
    mkdir(ctx->prefix_path, 0755);
    c_diag("box64_init: mkdir done");
    ctx->initialized = 1;
    c_diag("box64_init: DONE");
    snprintf(buf, sizeof(buf), "[Bridge] box64_init: wine_path=%s", ctx->wine_path);
    bridge_log(buf);
    return 0;
}

int box64_set_wine_path(box64_context_t *ctx, const char *wine_path) {
    if (!ctx || !wine_path) return -1;
    char buf[1024];
    snprintf(buf, sizeof(buf), "[Bridge] box64_set_wine_path(%s)", wine_path);
    bridge_log(buf);
    strncpy(ctx->wine_path, wine_path, sizeof(ctx->wine_path) - 1);
    ctx->wine_path[sizeof(ctx->wine_path) - 1] = '\0';
    return 0;
}

int box64_set_prefix(box64_context_t *ctx, const char *prefix_path) {
    if (!ctx || !prefix_path) return -1;
    char buf[1024];
    snprintf(buf, sizeof(buf), "[Bridge] box64_set_prefix(%s)", prefix_path);
    bridge_log(buf);
    strncpy(ctx->prefix_path, prefix_path, sizeof(ctx->prefix_path) - 1);
    ctx->prefix_path[sizeof(ctx->prefix_path) - 1] = '\0';
    return 0;
}

int box64_set_game(box64_context_t *ctx, const char *game_exe) {
    if (!ctx || !game_exe) return -1;
    char buf[1024];
    snprintf(buf, sizeof(buf), "[Bridge] box64_set_game(%s)", game_exe);
    bridge_log(buf);
    strncpy(ctx->game_path, game_exe, sizeof(ctx->game_path) - 1);
    ctx->game_path[sizeof(ctx->game_path) - 1] = '\0';
    return 0;
}

int box64_launch_wine(box64_context_t *ctx, const char *exe_path, char **extra_envp) {
    if (!ctx || !ctx->initialized) { bridge_log("[Bridge] box64_launch_wine: not initialized"); return -1; }
    g_wine_error[0] = 0;
    char buf[1024];

    snprintf(buf, sizeof(buf), "[Bridge] box64_launch_wine(exe=%s)", exe_path);
    bridge_log(buf);
    snprintf(buf, sizeof(buf), "[Bridge] wine_path=%s prefix=%s", ctx->wine_path, ctx->prefix_path);
    bridge_log(buf);

    /* Environment variables are set by Swift's safeSetenv() before this
       function is called. Do NOT duplicate them here with raw setenv()
       as that bypasses the thread-safe lock. */

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

    /* Determine wine binary path. ctx->wine_path may be either the binary
       path (e.g. .../Wine/bin/wine64) or the wine directory (.../Wine). */
    char wine_bin[1024];
    if (file_exists(ctx->wine_path)) {
        /* wine_path IS the binary — use it directly */
        snprintf(wine_bin, sizeof(wine_bin), "%s", ctx->wine_path);
    } else {
        /* Try appending /bin/wine64 (wine_path is the Wine directory) */
        snprintf(wine_bin, sizeof(wine_bin), "%s/bin/wine64", ctx->wine_path);
        if (!file_exists(wine_bin)) {
            snprintf(g_wine_error, sizeof(g_wine_error),
                     "Wine binary not found. Tried: '%s' and '%s'",
                     ctx->wine_path, wine_bin);
            fprintf(stderr, "[Box64] %s\n", g_wine_error);
            return -1;
        }
    }

    strncpy(ctx->game_path, exe_path, sizeof(ctx->game_path) - 1);
    ctx->game_path[sizeof(ctx->game_path) - 1] = '\0';

    snprintf(buf, sizeof(buf), "[Bridge] resolved wine_bin=%s", wine_bin);
    bridge_log(buf);

    ctx->running = 1;
    g_wine_running = 1;

    bridge_log("[Bridge] calling box64_runner_start()...");
    int rc = box64_runner_start(wine_bin, exe_path, ctx->prefix_path);
    snprintf(buf, sizeof(buf), "[Bridge] box64_runner_start returned %d", rc);
    bridge_log(buf);
    if (rc != 0) {
        snprintf(g_wine_error, sizeof(g_wine_error),
                 "box64_runner_start failed (code %d)", rc);
        ctx->running = 0;
        g_wine_running = 0;
        return -1;
    }

    bridge_log("[Bridge] box64_launch_wine: SUCCESS");
    return 0;
}

int box64_launch_wine_prefix_init(box64_context_t *ctx) {
    if (!ctx || !ctx->initialized) return -1;
    fprintf(stderr, "[Box64] Init prefix: %s\n", ctx->prefix_path);
    mkdir(ctx->prefix_path, 0755);
    /* Environment variables are set by Swift before calling this function. */

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
