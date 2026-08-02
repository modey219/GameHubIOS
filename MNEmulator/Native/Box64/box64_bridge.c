#include "../Include/box64_bridge.h"
#include "../Include/syscall_translation.h"
#include "../Include/reallibc.h"
#include "../Include/rawlibc.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>
#include <pthread.h>
#include <errno.h>
#include <fcntl.h>
#include <dirent.h>
#include <dlfcn.h>
#include <sys/syscall.h>
#include <time.h>

static box64_context_t *g_box64 = NULL;
static box64_context_t g_static_box64;
static int g_static_box64_used = 0;
static int g_wine_exit_code = 0;
static int g_wine_running = 0;
static char g_wine_error[1024] = {0};

static char g_crash_log_path[1024] = {0};
static char g_docs_path[1024] = {0};

/* Real libc pointers captured at install time (NOT the reallibc shims) so the
   async-signal crash handler never calls dlsym(). Fall back to raw syscalls. */
static int (*g_real_open)(const char *, int, ...) = NULL;
static ssize_t (*g_real_write)(int, const void *, size_t) = NULL;
static int (*g_real_close)(int) = NULL;
static size_t (*g_real_strlen)(const char *) = NULL;

static void crash_write(int fd, const char *buf, size_t n) {
    if (g_real_write) g_real_write(fd, buf, n);
    else syscall(SYS_write, fd, buf, n);
}
static int crash_open(const char *p, int flags, mode_t mode) {
    if (g_real_open) return g_real_open(p, flags, mode);
    return (int)syscall(SYS_open, p, flags, mode);
}
static size_t crash_strlen(const char *s) {
    if (g_real_strlen) return g_real_strlen(s);
    const char *p = s;
    while (*p) p++;
    return (size_t)(p - s);
}

static box64_log_callback g_probe_log_cb = NULL;
void box64_set_probe_log_cb(box64_log_callback cb) { g_probe_log_cb = cb; }

static char g_trace_path[1100] = {0};

#define PROBE_TRACE_MAX 65536
static char g_probe_trace[PROBE_TRACE_MAX];
static size_t g_probe_trace_len = 0;
static pthread_mutex_t g_probe_trace_lock = PTHREAD_MUTEX_INITIALIZER;

static void probe_trace_clear(void) {
    pthread_mutex_lock(&g_probe_trace_lock);
    g_probe_trace_len = 0;
    g_probe_trace[0] = 0;
    pthread_mutex_unlock(&g_probe_trace_lock);
}

static void probe_trace_append(const char *s) {
    size_t n = strlen(s);
    pthread_mutex_lock(&g_probe_trace_lock);
    if (n >= sizeof(g_probe_trace)) n = sizeof(g_probe_trace) - 1;
    if (g_probe_trace_len + n > sizeof(g_probe_trace) - 1) {
        size_t keep = sizeof(g_probe_trace) - 1 - n;
        if (keep > g_probe_trace_len) keep = g_probe_trace_len;
        memmove(g_probe_trace, g_probe_trace + g_probe_trace_len - keep, keep);
        g_probe_trace_len = keep;
    }
    memcpy(g_probe_trace + g_probe_trace_len, s, n);
    g_probe_trace_len += n;
    g_probe_trace[g_probe_trace_len] = 0;
    pthread_mutex_unlock(&g_probe_trace_lock);
}

void box64_probe_trace_snapshot(char *dst, size_t cap) {
    if (!dst || cap == 0) return;
    pthread_mutex_lock(&g_probe_trace_lock);
    size_t n = g_probe_trace_len;
    if (n > cap - 1) n = cap - 1;
    memcpy(dst, g_probe_trace, n);
    dst[n] = 0;
    pthread_mutex_unlock(&g_probe_trace_lock);
}

static void plog(const char *fmt, ...) {
    char buf[2048];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    probe_trace_append(buf);
}

static const char *g_signal_names[32] = {
    NULL, "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP",
    "SIGABRT", "SIGEMT", "SIGFPE", "SIGKILL", "SIGBUS",
    "SIGSEGV", "SIGSYS", "SIGPIPE", "SIGALRM", "SIGTERM",
    "SIGURG", "SIGSTOP", "SIGTSTP", "SIGCONT", "SIGCHLD",
    "SIGTTIN", "SIGTTOU", "SIGIO", "SIGXCPU", "SIGXFSZ",
    "SIGVTALRM", "SIGPROF", "SIGWINCH", "SIGINFO", "SIGUSR1", "SIGUSR2"
};

static void crash_signal_handler(int sig) {
    int fd = crash_open(g_crash_log_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        const char *prefix = "[CRASH] Signal ";
        crash_write(fd, prefix, 15);
        if (sig > 0 && sig < 32 && g_signal_names[sig]) {
            crash_write(fd, g_signal_names[sig], crash_strlen(g_signal_names[sig]));
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
            crash_write(fd, nbuf, (size_t)len);
        }
        crash_write(fd, "\n", 1);
        if (g_real_close) g_real_close(fd);
        else syscall(SYS_close, fd);
    }
    _exit(128 + sig);
}

void install_crash_handler(const char *log_path) {
    if (!log_path || !log_path[0]) return;
    strncpy(g_crash_log_path, log_path, sizeof(g_crash_log_path) - 1);
    g_crash_log_path[sizeof(g_crash_log_path) - 1] = '\0';
    size_t lp_len = strlen(log_path);
    if (lp_len > 10) {
        size_t copy_len = lp_len - 10;
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

    /* Capture the real libc functions for use inside the signal handler.
       Done here (normal context) so the handler never needs dlsym(). */
    g_real_open = (int (*)(const char *, int, ...))reallibc_resolve("open");
    g_real_write = (ssize_t (*)(int, const void *, size_t))reallibc_resolve("write");
    g_real_close = (int (*)(int))reallibc_resolve("close");
    g_real_strlen = (size_t (*)(const char *))reallibc_resolve("strlen");
}

static const char *get_docs_dir(void) {
    if (g_docs_path[0]) return g_docs_path;
    return NULL;
}

static void bridge_log(const char *msg) {
    const char *docs = get_docs_dir();
    if (!docs) return;
    char path[1024];
    snprintf(path, sizeof(path), "%s/bridge.log", docs);
    int fd = box64_raw_open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        box64_raw_write(fd, msg, strlen(msg));
        box64_raw_write(fd, "\n", 1);
        box64_raw_close(fd);
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
    int fd = box64_raw_open(full, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) {
        box64_raw_write(fd, msg, strlen(msg));
        box64_raw_write(fd, "\n", 1);
        box64_raw_close(fd);
    }
}

void c_diag(const char *s) {
    const char *docs = get_docs_dir();
    if (!docs) return;
    append_to_log(docs, "c_diag.log", s);
    append_to_log(docs, "diag.log", s);
}

void set_c_diag_docs_path(const char *path) {
    if (!path || !path[0]) return;
    strncpy(g_docs_path, path, sizeof(g_docs_path) - 1);
    g_docs_path[sizeof(g_docs_path) - 1] = '\0';
    /* Point the runner at the same reachable Documents dir so box64_runner.log
       always lands next to diag.log. (The earlier file-write test here hung the
       launch thread under LiveContainer; raw probes stay on their own thread.) */
    box64_runner_set_log_dir(path);
}

box64_context_t *box64_create(void) {
    return box64_create_step1();
}

box64_context_t *box64_create_step1(void) {
    memset(&g_static_box64, 0, sizeof(box64_context_t));
    g_static_box64_used = 1;
    return &g_static_box64;
}

int box64_create_step2(box64_context_t *ctx) {
    return box64_create_step2a(ctx);
}

int box64_create_step2a(box64_context_t *ctx) {
    if (!ctx) return -1;
    ctx->emulator = syscall_emulator_create_alloc();
    if (!ctx->emulator) return -2;
    return 0;
}

int box64_create_step2b(box64_context_t *ctx) {
    if (!ctx || !ctx->emulator) return -1;
    emulator_context_t *em = ctx->emulator;
    em->process.pid = getpid();
    em->process.ppid = getppid();
    em->process.start_brk = 0x70000000ULL;
    em->process.brk = 0x70000000ULL;
    em->process.mmap_base = 0x70000000ULL;
    em->process.cwd[0] = '/'; em->process.cwd[1] = '\0';
    em->process.root[0] = '/'; em->process.root[1] = '\0';
    em->process.limits[7].rlim_cur = 1024;
    em->process.limits[7].rlim_max = 4096;
    em->initialized = 1;
    return 0;
}

void box64_create_step3(box64_context_t *ctx) {
    if (!ctx || !ctx->emulator) return;
    syscall_set_context(ctx->emulator);
    ctx->child_pid = -1;
    g_box64 = ctx;
}

void box64_destroy(box64_context_t *ctx) {
    if (!ctx) return;
    box64_stop(ctx);
    syscall_set_context(NULL);
    syscall_emulator_destroy(ctx->emulator);
    if (ctx == g_box64) g_box64 = NULL;
    if (ctx == &g_static_box64) {
        memset(ctx, 0, sizeof(box64_context_t));
        g_static_box64_used = 0;
    } else {
        free(ctx);
    }
}

/* stat()/access() are broken under LiveContainer interposition (build-351:
   stat returns garbage, access hangs). realpath() is proven to work on every
   path in-process, so use it for existence checks instead of stat(). */
static int file_exists(const char *path) {
    char rp[1100];
    return path && realpath(path, rp) != NULL;
}

static long file_size(const char *path) {
    char rp[1100];
    if (!path || !realpath(path, rp)) return 0;
    int fd = box64_raw_open(rp, O_RDONLY);
    if (fd < 0) return 0;
    off_t sz = box64_raw_lseek(fd, 0, SEEK_END);
    if (fd > 2) box64_raw_close(fd);
    return sz > 0 ? (long)sz : 0;
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
    box64_raw_mkdir(ctx->prefix_path, 0755);
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
    g_wine_error[0] = 0;
    if (!ctx) {
        snprintf(g_wine_error, sizeof(g_wine_error), "box64_launch_wine: ctx is NULL");
        return -10;
    }
    if (!ctx->initialized) {
        snprintf(g_wine_error, sizeof(g_wine_error),
                 "box64_launch_wine: ctx NOT initialized (rc=-11)");
        return -11;
    }
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
                     "Wine binary not found. Tried: '%s' and '%s' (rc=-12)",
                     ctx->wine_path, wine_bin);
            fprintf(stderr, "[Box64] %s\n", g_wine_error);
            return -12;
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
    snprintf(buf, sizeof(buf), "[Bridge] runner log=%s", box64_runner_get_log_path());
    bridge_log(buf);
    if (rc != 0) {
        snprintf(g_wine_error, sizeof(g_wine_error),
                 "box64_runner_start failed (code %d, errno=%d) (rc=-20)", rc, errno);
        ctx->running = 0;
        g_wine_running = 0;
        return -20;
    }

    bridge_log("[Bridge] box64_launch_wine: SUCCESS");
    return 0;
}

int box64_launch_wine_prefix_init(box64_context_t *ctx) {
    if (!ctx || !ctx->initialized) return -1;
    fprintf(stderr, "[Box64] Init prefix: %s\n", ctx->prefix_path);
    box64_raw_mkdir(ctx->prefix_path, 0755);
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

static void probe_emit(char *out, size_t *used, size_t cap, const char *line) {
    size_t n = strlen(line);
    if (*used + n + 1 >= cap) return;
    memcpy(out + *used, line, n);
    *used += n;
    out[(*used)++] = '\n';
    out[*used] = 0;
}

static void probe_one(char *out, size_t *used, size_t cap, const char *label, const char *path) {
    char line[1400];
    plog("probe_one[%s]: stat(%s)", label, path ? path : "(null)");
    if (!path || !path[0]) {
        snprintf(line, sizeof(line), "PROBE %s | (empty path)", label);
        probe_emit(out, used, cap, line);
        return;
    }
    struct stat s;
    errno = 0;
    int st = box64_raw_stat(path, &s);
    int st_errno = errno;
    plog("probe_one[%s]: stat done st=%d errno=%d", label, st, st_errno);
    char rp[1100];
    plog("probe_one[%s]: realpath(%s)", label, path);
    const char *rpstr = realpath(path, rp);
    plog("probe_one[%s]: realpath done=%s", label, rpstr ? rpstr : "(null)");
    char access_kind[32] = "n/a";
    if (st == 0) {
        if (S_ISDIR(s.st_mode)) {
            char tp[1400];
            snprintf(tp, sizeof(tp), "%s/.__mn_probe", path);
            plog("probe_one[%s]: open-write-test %s", label, tp);
            int fd = box64_raw_open(tp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            plog("probe_one[%s]: open done fd=%d errno=%d", label, fd, errno);
            if (fd >= 0) { box64_raw_close(fd); box64_raw_unlink(tp); strcpy(access_kind, "dir-writable"); }
            else { snprintf(access_kind, sizeof(access_kind), "dir-readonly(errno=%d)", errno); }
        } else if (S_ISREG(s.st_mode)) {
            plog("probe_one[%s]: open-read %s", label, path);
            int fd = box64_raw_open(path, O_RDONLY);
            plog("probe_one[%s]: open-read done fd=%d errno=%d", label, fd, errno);
            if (fd >= 0) { box64_raw_close(fd); strcpy(access_kind, "file-readable"); }
            else { snprintf(access_kind, sizeof(access_kind), "file-openfail(errno=%d)", errno); }
        } else {
            strcpy(access_kind, "other");
        }
    }
    snprintf(line, sizeof(line), "PROBE %s | stat=%s(errno=%d) access=%s realpath=%s",
             label, st == 0 ? "yes" : "no", st_errno, access_kind,
             rpstr ? rpstr : "(null)");
    probe_emit(out, used, cap, line);
    plog("probe_one[%s]: done", label);
}

static void probe_walk_up(char *out, size_t *used, size_t cap, const char *path) {
    char cur[1100];
    snprintf(cur, sizeof(cur), "%s", path);
    for (int i = 0; i < 14; i++) {
        char rp[1100];
        errno = 0;
        plog("walk_up[%d]: realpath(%s)", i, cur);
        const char *rpstr = realpath(cur, rp);
        plog("walk_up[%d]: realpath done=%s", i, rpstr ? rpstr : "(null)");
        if (rpstr) {
            char line[1200];
            snprintf(line, sizeof(line), "WALK-UP level %d ACCESSIBLE: '%s'", i, rpstr);
            probe_emit(out, used, cap, line);
            return;
        }
        char *slash = strrchr(cur, '/');
        if (!slash || slash == cur) return;
        *slash = 0;
    }
}

int box64_probe_magic(void) {
    return 0xB0C0;
}

static void probe_write_file(const char *base_path, const char *fname, const char *content) {
    char full[1100];
    if (!base_path || !base_path[0] || !content) return;
    size_t blen = strlen(base_path);
    size_t flen = strlen(fname);
    if (blen + flen + 2 > sizeof(full)) return;
    memcpy(full, base_path, blen);
    full[blen] = '/';
    memcpy(full + blen + 1, fname, flen);
    full[blen + 1 + flen] = '\0';
    plog("write_file: open(%s)", full);
    int fd = box64_raw_open(full, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    plog("write_file: open done fd=%d errno=%d", fd, errno);
    if (fd >= 0) {
        plog("write_file: write %zu bytes", strlen(content));
        box64_raw_write(fd, content, strlen(content));
        box64_raw_close(fd);
        plog("write_file: closed");
    }
}

/* The critical unknown: box64's elfloader loads wine64 via open()/fstat()/
   read(). stat() is broken under interposition, but open() may still work —
   build-351's probe_one only attempted open-read when stat()==0, which never
   happened. Test open-based I/O directly here. */
static void probe_open_io(char *out, size_t *used, size_t cap, const char *label, const char *path) {
    char line[1600];
    char rp[1300];
    plog("open_io[%s]: realpath(%s)", label, path ? path : "(null)");
    const char *rps = path ? realpath(path, rp) : NULL;
    plog("open_io[%s]: realpath done=%s", label, rps ? rps : "(null)");
    if (!rps) {
        snprintf(line, sizeof(line), "OPENIO %s | realpath=NULL (no such file)", label);
        probe_emit(out, used, cap, line);
        return;
    }
    plog("open_io[%s]: open(O_RDONLY) %s", label, rps);
    errno = 0;
    int fd = box64_raw_open(rps, O_RDONLY);
    int o_errno = errno;
    plog("open_io[%s]: open done fd=%d errno=%d", label, fd, o_errno);
    if (fd < 0) {
        snprintf(line, sizeof(line), "OPENIO %s | open=fail(errno=%d) realpath=%s", label, o_errno, rps);
        probe_emit(out, used, cap, line);
        return;
    }
    struct stat st;
    errno = 0;
    int fst = box64_raw_fstat(fd, &st);
    int f_errno = errno;
    plog("open_io[%s]: fstat done=%d errno=%d", label, fst, f_errno);
    off_t sz = box64_raw_lseek(fd, 0, SEEK_END);
    int l_errno = errno;
    plog("open_io[%s]: lseek done sz=%lld errno=%d", label, (long long)sz, l_errno);
    char magic[16];
    int n = 0;
    if (sz >= 4) {
        box64_raw_lseek(fd, 0, SEEK_SET);
        n = (int)box64_raw_read(fd, magic, sizeof(magic));
    }
    int r_errno = errno;
    char hex[128] = "";
    for (int i = 0; i < n && i < (int)sizeof(magic); i++) {
        char part[8];
        snprintf(part, sizeof(part), "%02x", (unsigned char)magic[i]);
        strncat(hex, part, sizeof(hex) - strlen(hex) - 1);
        if (i < n - 1) strncat(hex, " ", sizeof(hex) - strlen(hex) - 1);
    }
    if (fd > 2) box64_raw_close(fd);
    snprintf(line, sizeof(line),
             "OPENIO %s | open=fd%d fstat=%d(errno=%d) size=%lld read=%dbytes(errno=%d) magic=[%s] realpath=%s",
             label, fd, fst, f_errno, (long long)sz, n, r_errno, hex, rps);
    probe_emit(out, used, cap, line);
    plog("open_io[%s]: done", label);
}

static void probe_root(char *out, size_t *used, size_t cap, int idx, const char *path) {
    char line[1600];
    struct stat s;
    errno = 0;
    plog("probe_root[%d]: stat(%s)", idx, path ? path : "(null)");
    int st = box64_raw_stat(path, &s);
    int st_errno = errno;
    plog("probe_root[%d]: stat done st=%d errno=%d", idx, st, st_errno);
    char rp[1300];
    plog("probe_root[%d]: realpath(%s)", idx, path);
    const char *rpstr = realpath(path, rp);
    plog("probe_root[%d]: realpath done=%s", idx, rpstr ? rpstr : "(null)");
    char acc[96] = "n/a";
    if (st == 0 && S_ISDIR(s.st_mode)) {
        char tp[1400];
        snprintf(tp, sizeof(tp), "%s/.wtest", path);
        plog("probe_root[%d]: open-write %s", idx, tp);
        int fd = box64_raw_open(tp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        plog("probe_root[%d]: open done fd=%d errno=%d", idx, fd, errno);
        if (fd >= 0) { box64_raw_close(fd); box64_raw_unlink(tp); snprintf(acc, sizeof(acc), "DIR-WRITABLE"); }
        else { snprintf(acc, sizeof(acc), "DIR-readonly(errno=%d)", errno); }
    } else if (st == 0 && S_ISREG(s.st_mode)) {
        plog("probe_root[%d]: open-read %s", idx, path);
        int fd = box64_raw_open(path, O_RDONLY);
        plog("probe_root[%d]: open-read done fd=%d errno=%d", idx, fd, errno);
        if (fd >= 0) { box64_raw_close(fd); snprintf(acc, sizeof(acc), "FILE-readable"); }
        else { snprintf(acc, sizeof(acc), "FILE-openfail(errno=%d)", errno); }
    }
    snprintf(line, sizeof(line), "ROOT %d stat=%s(errno=%d) access=%s realpath=%s | '%s'",
             idx, st == 0 ? "yes" : "no", st_errno, acc, rpstr ? rpstr : "(null)", path);
    probe_emit(out, used, cap, line);
    plog("probe_root[%d]: done", idx);
}

/* ================================================================== */
/*  forensic open/stat matrix (watchdog-guarded trials)               */
/* ================================================================== */

/* build-366: probe died at raw open() of the wine64 realpath — raw
   syscall(SYS_open) hangs while libc realpath()/getcwd() work. We need to
   know WHICH mechanism (plain syscall symbol / dlsym'd libSystem syscall /
   dlsym'd libc open / interposed libc open / openat vs open / stat64 vs
   fstat) actually works under LiveContainer. Each trial runs on its own
   thread so a hung syscall is recorded as HANG and the probe continues. */

static void *g_libc_handle = NULL;
static long (*g_libc_syscall_fn)(int, ...) = NULL;
static int (*g_libc_open_fn)(const char *, int, ...) = NULL;
static int (*g_libc_stat_fn)(const char *, struct stat *) = NULL;
static int (*g_libc_fstat_fn)(int, struct stat *) = NULL;
static ssize_t (*g_libc_read_fn)(int, void *, size_t) = NULL;
static FILE *(*g_libc_fopen_fn)(const char *, const char *) = NULL;

static void resolve_libc_pointers(void) {
    if (g_libc_handle) return;
    g_libc_handle = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY);
    if (!g_libc_handle) g_libc_handle = dlopen("/usr/lib/libSystem.dylib", RTLD_LAZY);
    if (!g_libc_handle) return;
    g_libc_syscall_fn = (long (*)(int, ...))dlsym(g_libc_handle, "syscall");
    g_libc_open_fn = (int (*)(const char *, int, ...))dlsym(g_libc_handle, "open");
    g_libc_stat_fn = (int (*)(const char *, struct stat *))dlsym(g_libc_handle, "stat");
    g_libc_fstat_fn = (int (*)(int, struct stat *))dlsym(g_libc_handle, "fstat");
    g_libc_read_fn = (ssize_t (*)(int, void *, size_t))dlsym(g_libc_handle, "read");
    g_libc_fopen_fn = (FILE *(*)(const char *, const char *))dlsym(g_libc_handle, "fopen");
}

enum {
    TK_REAL_SC_OPEN = 0,     /* dlsym'd libSystem syscall(SYS_open) */
    TK_REAL_SC_OPENAT = 1,   /* dlsym'd libSystem syscall(SYS_openat,AT_FDCWD) */
    TK_RAW_OPEN = 2,         /* plain syscall symbol SYS_open (current failure) */
    TK_RAW_OPENAT = 3,       /* plain syscall symbol SYS_openat */
    TK_RAW_STAT64 = 4,       /* plain syscall symbol SYS_stat64 */
    TK_LIBC_OPEN_DL = 5,     /* dlsym'd libSystem open */
    TK_LIBC_STAT_DL = 6,     /* dlsym'd libSystem stat */
    TK_LIBC_FOPEN_DL = 7,    /* dlsym'd libSystem fopen */
    TK_LIBC_OPEN = 8,        /* interposed plain open() */
    TK_RAW_FSTAT64 = 9,      /* plain syscall SYS_fstat64 on t->fd */
    TK_RAW_READ4 = 10,       /* plain syscall SYS_read 4 bytes on t->fd */
    TK_LIBC_FSTAT_DL = 11,   /* dlsym'd libSystem fstat on t->fd */
    TK_LIBC_READ4_DL = 12,   /* dlsym'd libSystem read on t->fd */
    TK_RAW_GETDENTS64 = 13,  /* plain syscall SYS_getdirentries64 on t->fd */
    TK_REAL_SC_MKDIR = 14,   /* dlsym'd libSystem syscall(SYS_mkdir) */
    TK_REAL_SC_UNLINK = 15,  /* dlsym'd libSystem syscall(SYS_unlink) */
    TK_REAL_SC_CREATE = 16,  /* dlsym'd syscall openat O_WRONLY|O_CREAT + write + close */
    TK_KERNEL_GETCWD = 17,   /* box64_raw_syscall(SYS___getcwd) — direct svc proof */
    TK_KERNEL_OPENAT = 18,   /* box64_raw_syscall(SYS_openat, AT_FDCWD) — direct svc */
    TK_KERNEL_OPEN = 19,     /* box64_raw_syscall(SYS_open) — direct svc */
    TK_KERNEL_STAT64 = 20,   /* box64_raw_syscall(SYS_stat64) — direct svc */
    TK_KERNEL_GETDENTS64 = 21, /* box64_raw_syscall(SYS_getdirentries64) — direct svc */
    TK_KERNEL_CREATE = 22,   /* box64_raw_syscall openat+write+close — direct svc */
    TK_KERNEL_MKDIR = 23,    /* box64_raw_syscall(SYS_mkdir) — direct svc */
    TK_KERNEL_UNLINK = 24,   /* box64_raw_syscall(SYS_unlink) — direct svc */
    TK_KERNEL_FSTAT64 = 25,  /* box64_raw_syscall(SYS_fstat64) on t->fd — direct svc */
    TK_KERNEL_READ = 26,     /* box64_raw_syscall(SYS_read) on t->fd — direct svc */
    TK_KERNEL_GETPID_RAW = 27, /* svc raw SYS_getpid — trap sanity */
    TK_KERNEL_GETPID_CLS = 28, /* svc class-encoded SYS_getpid */
    TK_KERNEL_GETCWD_CLS = 29, /* svc class-encoded SYS___getcwd */
    TK_KERNEL_OPENAT_CLS = 30, /* svc class-encoded SYS_openat */
    TK_KERNEL_OPENAT_RAW = 31, /* svc raw SYS_openat (KNOWN HANG — gated) */
    TK_LIBC_FOPEN_PLAIN = 32,  /* interposed plain fopen() */
    TK_LIBC_STAT_PLAIN = 33,   /* interposed plain stat() */
    TK_LIBC_OPENDIR_PLAIN = 34,/* interposed plain opendir()+readdir */
    TK_LIBC_FSTAT_PLAIN = 35,  /* interposed plain fstat() */
    TK_LIBC_READ_PLAIN = 36,   /* interposed plain read() */
    TK_LIBC_CREATE_PLAIN = 37, /* interposed plain open O_CREAT+write+close */
    TK_LIBC_UNLINK_PLAIN = 38, /* interposed plain unlink() */
    TK_LIBC_MKDIR_PLAIN = 39,  /* interposed plain mkdir() */
    TK_LIBC_REAL_OPEN = 40,    /* real-libc open (rawlibc.c, no redirect macros) */
    TK_LIBC_REAL_STAT = 41,    /* real-libc stat */
    TK_LIBC_REAL_FOPEN = 42,   /* real-libc fopen */
    TK_LIBC_REAL_FSTAT = 43,   /* real-libc fstat on t->fd */
    TK_LIBC_REAL_READ = 44,    /* real-libc read on t->fd */
    TK_LIBC_REAL_SYSCALL_OPENAT = 45, /* interposed syscall(SYS_openat) */
    TK_LIBC_REAL_SYSCALL_GETPID = 46, /* interposed syscall(SYS_getpid) */
    TK_LIBC_REAL_MKDIR = 47,   /* real-libc mkdir */
    TK_KERNEL_MKDIR_RAW = 48,  /* svc raw SYS_mkdir — does the raw encoding work at all? */
    TK_KERNEL_OPEN_RAW = 49,   /* svc raw SYS_open (low number 5) */
    TK_KERNEL_STAT64_RAW = 50, /* svc raw SYS_stat64 */
    TK_KERNEL_GETUID_CLS = 51, /* svc cls SYS_getuid (argless id family) */
    TK_KERNEL_GETEUID_CLS = 52,/* svc cls SYS_geteuid */
    TK_KERNEL_GETGID_CLS = 53, /* svc cls SYS_getgid */
    TK_KERNEL_GETEGID_CLS = 54,/* svc cls SYS_getegid */
    TK_LIBC_REAL_GETPID = 55,  /* direct libc getpid() — ABI-sanity control */
    TK_LIBC_REAL_GETUID = 56,  /* direct libc getuid() — ABI-sanity control */
    TK_COUNT
};

typedef struct {
    volatile int state;          /* 1=running, 2=done, 3=abandoned(hung) */
    int kind;
    const char *path;
    int fd;
    int r1;
    int r2;
    int r_errno;
    unsigned char rbuf[16];
} trial_t;

static const char *trial_name(int kind) {
    switch (kind) {
    case TK_REAL_SC_OPEN: return "real-syscall-open";
    case TK_REAL_SC_OPENAT: return "real-syscall-openat";
    case TK_RAW_OPEN: return "raw-open";
    case TK_RAW_OPENAT: return "raw-openat";
    case TK_RAW_STAT64: return "raw-stat64";
    case TK_LIBC_OPEN_DL: return "libc-open(dlsym)";
    case TK_LIBC_STAT_DL: return "libc-stat(dlsym)";
    case TK_LIBC_FOPEN_DL: return "libc-fopen(dlsym)";
    case TK_LIBC_OPEN: return "libc-open(plain)";
    case TK_RAW_FSTAT64: return "raw-fstat64";
    case TK_RAW_READ4: return "raw-read4";
    case TK_LIBC_FSTAT_DL: return "libc-fstat(dlsym)";
    case TK_LIBC_READ4_DL: return "libc-read4(dlsym)";
    case TK_RAW_GETDENTS64: return "raw-getdents64";
    case TK_REAL_SC_MKDIR: return "real-syscall-mkdir";
    case TK_REAL_SC_UNLINK: return "real-syscall-unlink";
    case TK_REAL_SC_CREATE: return "real-syscall-create+write";
    case TK_KERNEL_GETCWD: return "kernel-svc-getcwd";
    case TK_KERNEL_OPENAT: return "kernel-svc-openat";
    case TK_KERNEL_OPEN: return "kernel-svc-open";
    case TK_KERNEL_STAT64: return "kernel-svc-stat64";
    case TK_KERNEL_GETDENTS64: return "kernel-svc-getdents64";
    case TK_KERNEL_CREATE: return "kernel-svc-create+write";
    case TK_KERNEL_MKDIR: return "kernel-svc-mkdir";
    case TK_KERNEL_UNLINK: return "kernel-svc-unlink";
    case TK_KERNEL_FSTAT64: return "kernel-svc-fstat64";
    case TK_KERNEL_READ: return "kernel-svc-read";
    case TK_KERNEL_GETPID_RAW: return "kernel-svc-getpid(raw)";
    case TK_KERNEL_GETPID_CLS: return "kernel-svc-getpid(cls)";
    case TK_KERNEL_GETCWD_CLS: return "kernel-svc-getcwd(cls)";
    case TK_KERNEL_OPENAT_CLS: return "kernel-svc-openat(cls)";
    case TK_KERNEL_OPENAT_RAW: return "kernel-svc-openat(raw)";
    case TK_LIBC_FOPEN_PLAIN: return "libc-fopen(plain)";
    case TK_LIBC_STAT_PLAIN: return "libc-stat(plain)";
    case TK_LIBC_OPENDIR_PLAIN: return "libc-opendir(plain)";
    case TK_LIBC_FSTAT_PLAIN: return "libc-fstat(plain)";
    case TK_LIBC_READ_PLAIN: return "libc-read(plain)";
    case TK_LIBC_CREATE_PLAIN: return "libc-create+write(plain)";
    case TK_LIBC_UNLINK_PLAIN: return "libc-unlink(plain)";
    case TK_LIBC_MKDIR_PLAIN: return "libc-mkdir(plain)";
    case TK_LIBC_REAL_OPEN: return "libc-real-open";
    case TK_LIBC_REAL_STAT: return "libc-real-stat";
    case TK_LIBC_REAL_FOPEN: return "libc-real-fopen";
    case TK_LIBC_REAL_FSTAT: return "libc-real-fstat";
    case TK_LIBC_REAL_READ: return "libc-real-read";
    case TK_LIBC_REAL_SYSCALL_OPENAT: return "libc-real-syscall-openat";
    case TK_LIBC_REAL_SYSCALL_GETPID: return "libc-real-syscall-getpid";
    case TK_LIBC_REAL_MKDIR: return "libc-real-mkdir";
    case TK_KERNEL_MKDIR_RAW: return "kernel-svc-mkdir(raw)";
    case TK_KERNEL_OPEN_RAW: return "kernel-svc-open(raw)";
    case TK_KERNEL_STAT64_RAW: return "kernel-svc-stat64(raw)";
    case TK_KERNEL_GETUID_CLS: return "kernel-svc-getuid(cls)";
    case TK_KERNEL_GETEUID_CLS: return "kernel-svc-geteuid(cls)";
    case TK_KERNEL_GETGID_CLS: return "kernel-svc-getgid(cls)";
    case TK_KERNEL_GETEGID_CLS: return "kernel-svc-getegid(cls)";
    case TK_LIBC_REAL_GETPID: return "libc-real-getpid";
    case TK_LIBC_REAL_GETUID: return "libc-real-getuid";
    default: return "?";
    }
}

static void bridge_trial_execute(trial_t *t) {
    struct stat sb;
    errno = 0;
    switch (t->kind) {
    case TK_REAL_SC_OPEN:
        t->r1 = (int)syscall(SYS_open, t->path, O_RDONLY, 0L);
        t->r_errno = errno; break;
    case TK_REAL_SC_OPENAT:
        t->r1 = (int)syscall(SYS_openat, AT_FDCWD, t->path, O_RDONLY, 0L);
        t->r_errno = errno; break;
    case TK_RAW_OPEN:
        t->r1 = (int)syscall(SYS_open, t->path, O_RDONLY, 0L);
        t->r_errno = errno; break;
    case TK_RAW_OPENAT:
        t->r1 = (int)syscall(SYS_openat, AT_FDCWD, t->path, O_RDONLY, 0L);
        t->r_errno = errno; break;
    case TK_RAW_STAT64:
        t->r1 = (int)syscall(SYS_stat64, t->path, &sb);
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_LIBC_OPEN_DL:
        t->r1 = g_libc_open_fn ? g_libc_open_fn(t->path, O_RDONLY) : -1;
        t->r_errno = errno; break;
    case TK_LIBC_STAT_DL:
        t->r1 = g_libc_stat_fn ? g_libc_stat_fn(t->path, &sb) : -1;
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_LIBC_FOPEN_DL: {
        FILE *f = g_libc_fopen_fn ? g_libc_fopen_fn(t->path, "rb") : NULL;
        t->r1 = f ? fileno(f) : -1;
        if (f) fclose(f);
        t->r_errno = errno; break;
    }
    case TK_LIBC_OPEN:
        t->r1 = open(t->path, O_RDONLY);
        t->r_errno = errno; break;
    case TK_RAW_FSTAT64:
        t->r1 = (int)syscall(SYS_fstat64, t->fd, &sb);
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_RAW_READ4:
        t->r1 = (int)syscall(SYS_read, t->fd, t->rbuf, 4);
        t->r_errno = errno; break;
    case TK_LIBC_FSTAT_DL:
        t->r1 = g_libc_fstat_fn ? g_libc_fstat_fn(t->fd, &sb) : -1;
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_LIBC_READ4_DL:
        t->r1 = g_libc_read_fn ? (int)g_libc_read_fn(t->fd, t->rbuf, 4) : -1;
        t->r_errno = errno; break;
    case TK_RAW_GETDENTS64: {
        off_t base = 0;
        char db[4096];
        t->r1 = (int)syscall(SYS_getdirentries64, t->fd, db, (size_t)sizeof(db), &base);
        t->r_errno = errno; break;
    }
    case TK_REAL_SC_MKDIR:
        t->r1 = (int)syscall(SYS_mkdir, t->path, 0755);
        t->r_errno = errno; break;
    case TK_REAL_SC_UNLINK:
        t->r1 = (int)syscall(SYS_unlink, t->path);
        t->r_errno = errno; break;
    case TK_REAL_SC_CREATE: {
        int fd = (int)syscall(SYS_openat, AT_FDCWD, t->path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            syscall(SYS_write, fd, "OK", 2L);
            syscall(SYS_close, fd);
        }
        t->r1 = fd;
        t->r_errno = errno; break;
    }
    case TK_KERNEL_GETCWD: {
        /* Log which constant (or fallback) produced the result: build-373
           reported errno=78 (ENOSYS) here, which is indistinguishable between
           "SYS___getcwd undefined -> #else fallback" and "kernel rejected the
           number". */
        char kb[1024];
#if defined(SYS___getcwd)
        long r = box64_raw_syscall_raw(SYS___getcwd, kb, (long)sizeof(kb));
        plog("getcwd-raw: using SYS___getcwd=%d", (int)SYS___getcwd);
#elif defined(SYS_getcwd)
        long r = box64_raw_syscall_raw(SYS_getcwd, kb, (long)sizeof(kb));
        plog("getcwd-raw: using SYS_getcwd=%d", (int)SYS_getcwd);
#else
        long r = -1;
        errno = ENOSYS;
        plog("getcwd-raw: NO getcwd SYS_* constant defined - #else fallback ENOSYS");
#endif
        t->r1 = (int)r;
        if (r >= 0) memcpy(t->rbuf, kb, sizeof(t->rbuf));
        t->r_errno = errno; break;
    }
    case TK_KERNEL_GETCWD_CLS: {
        char kb[1024];
#if defined(SYS___getcwd)
        long r = box64_raw_syscall_cls(SYS___getcwd, kb, (long)sizeof(kb));
#elif defined(SYS_getcwd)
        long r = box64_raw_syscall_cls(SYS_getcwd, kb, (long)sizeof(kb));
#else
        long r = -1;
        errno = ENOSYS;
#endif
        t->r1 = (int)r;
        if (r >= 0) memcpy(t->rbuf, kb, sizeof(t->rbuf));
        t->r_errno = errno; break;
    }
    case TK_KERNEL_GETPID_RAW:
        t->r1 = (int)box64_raw_syscall_raw(SYS_getpid);
        t->r_errno = errno; break;
    case TK_KERNEL_GETPID_CLS:
        t->r1 = (int)box64_raw_syscall_cls(SYS_getpid);
        t->r_errno = errno; break;
    case TK_KERNEL_OPENAT:
        t->r1 = (int)box64_raw_syscall(SYS_openat, AT_FDCWD, t->path, O_RDONLY, 0L);
        t->r_errno = errno; break;
    case TK_KERNEL_OPEN:
        t->r1 = (int)box64_raw_syscall(SYS_open, t->path, O_RDONLY, 0L);
        t->r_errno = errno; break;
    case TK_KERNEL_STAT64:
        t->r1 = (int)box64_raw_syscall(SYS_stat64, t->path, &sb);
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_KERNEL_GETDENTS64: {
        off_t base = 0;
        char db[4096];
        t->r1 = (int)box64_raw_syscall(SYS_getdirentries64, t->fd, db, (long)sizeof(db), (long)&base);
        t->r_errno = errno; break;
    }
    case TK_KERNEL_CREATE: {
        int fd = (int)box64_raw_syscall(SYS_openat, AT_FDCWD, t->path,
                                        O_WRONLY | O_CREAT | O_TRUNC, 0644L);
        if (fd >= 0) {
            box64_raw_syscall(SYS_write, fd, (long)"OK", 2L);
            box64_raw_syscall(SYS_close, fd);
        }
        t->r1 = fd;
        t->r_errno = errno; break;
    }
    case TK_KERNEL_MKDIR:
        t->r1 = (int)box64_raw_syscall(SYS_mkdir, t->path, 0755L);
        t->r_errno = errno; break;
    case TK_KERNEL_UNLINK:
        t->r1 = (int)box64_raw_syscall(SYS_unlink, t->path);
        t->r_errno = errno; break;
    case TK_KERNEL_FSTAT64:
        t->r1 = (int)box64_raw_syscall(SYS_fstat64, t->fd, &sb);
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_KERNEL_READ:
        t->r1 = (int)box64_raw_syscall(SYS_read, t->fd, t->rbuf, 4L);
        t->r2 = (t->r1 >= 0) ? (int)t->r1 : -1;
        t->r_errno = errno; break;
    case TK_KERNEL_OPENAT_CLS:
        t->r1 = (int)box64_raw_syscall_cls(SYS_openat, AT_FDCWD, t->path, O_RDONLY, 0L);
        t->r_errno = errno; break;
    case TK_KERNEL_OPENAT_RAW:
        t->r1 = (int)box64_raw_syscall_raw(SYS_openat, AT_FDCWD, t->path, O_RDONLY, 0L);
        t->r_errno = errno; break;
    case TK_LIBC_FOPEN_PLAIN: {
        FILE *f = fopen(t->path, "rb");
        t->r1 = f ? fileno(f) : -1;
        if (f) fclose(f);
        t->r_errno = errno; break;
    }
    case TK_LIBC_STAT_PLAIN:
        t->r1 = stat(t->path, &sb);
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_LIBC_OPENDIR_PLAIN: {
        DIR *d = opendir(t->path);
        t->r1 = d ? 0 : -1;
        t->r2 = 0;
        if (d) {
            struct dirent *e = readdir(d);
            t->r2 = e ? 1 : 0;
            closedir(d);
        }
        t->r_errno = errno; break;
    }
    case TK_LIBC_FSTAT_PLAIN:
        t->r1 = fstat(t->fd, &sb);
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_LIBC_READ_PLAIN:
        t->r1 = (int)read(t->fd, t->rbuf, 4);
        t->r_errno = errno; break;
    case TK_LIBC_CREATE_PLAIN: {
        int fd = open(t->path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd >= 0) {
            write(fd, "OK", 2);
            close(fd);
        }
        t->r1 = fd;
        t->r_errno = errno; break;
    }
    case TK_LIBC_UNLINK_PLAIN:
        t->r1 = unlink(t->path);
        t->r_errno = errno; break;
    case TK_LIBC_MKDIR_PLAIN:
        t->r1 = mkdir(t->path, 0755);
        t->r_errno = errno; break;
    case TK_LIBC_REAL_OPEN:
        t->r1 = box64_libc_open(t->path);
        t->r_errno = errno; break;
    case TK_LIBC_REAL_STAT:
        t->r1 = box64_libc_stat(t->path, &sb);
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_LIBC_REAL_FOPEN: {
        FILE *f = box64_libc_fopen(t->path, "rb");
        t->r1 = f ? fileno(f) : -1;
        if (f) fclose(f);
        t->r_errno = errno; break;
    }
    case TK_LIBC_REAL_FSTAT:
        t->r1 = box64_libc_fstat(t->fd, &sb);
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_LIBC_REAL_READ:
        t->r1 = (int)box64_libc_read(t->fd, t->rbuf, 4);
        t->r_errno = errno; break;
    case TK_LIBC_REAL_SYSCALL_OPENAT:
        t->r1 = box64_libc_syscall_openat(t->path, O_RDONLY);
        t->r_errno = errno; break;
    case TK_LIBC_REAL_SYSCALL_GETPID:
        t->r1 = box64_libc_syscall_getpid();
        t->r_errno = errno; break;
    case TK_LIBC_REAL_MKDIR:
        t->r1 = box64_libc_mkdir(t->path);
        t->r_errno = errno; break;
    case TK_KERNEL_MKDIR_RAW:
        t->r1 = (int)box64_raw_syscall_raw(SYS_mkdir, t->path, 0755L);
        t->r_errno = errno; break;
    case TK_KERNEL_OPEN_RAW:
        t->r1 = (int)box64_raw_syscall_raw(SYS_open, t->path, O_RDONLY, 0L);
        t->r_errno = errno; break;
    case TK_KERNEL_STAT64_RAW:
        t->r1 = (int)box64_raw_syscall_raw(SYS_stat64, t->path, &sb);
        t->r2 = (t->r1 == 0) ? (int)sb.st_size : -1;
        t->r_errno = errno; break;
    case TK_KERNEL_GETUID_CLS:
        t->r1 = (int)box64_raw_syscall(SYS_getuid);
        t->r_errno = errno; break;
    case TK_KERNEL_GETEUID_CLS:
        t->r1 = (int)box64_raw_syscall(SYS_geteuid);
        t->r_errno = errno; break;
    case TK_KERNEL_GETGID_CLS:
        t->r1 = (int)box64_raw_syscall(SYS_getgid);
        t->r_errno = errno; break;
    case TK_KERNEL_GETEGID_CLS:
        t->r1 = (int)box64_raw_syscall(SYS_getegid);
        t->r_errno = errno; break;
    case TK_LIBC_REAL_GETPID:
        t->r1 = box64_libc_getpid();
        t->r_errno = errno; break;
    case TK_LIBC_REAL_GETUID:
        t->r1 = box64_libc_getuid();
        t->r_errno = errno; break;
    default:
        t->r1 = -1;
        t->r_errno = ENOSYS;
        break;
    }
}

/* Runs a SINGLE trial in the caller's context and returns its raw results.
   build-376: the Swift side spawns one thread per trial with a per-trial
   timeout, so a hung svc kills only that trial thread — the rest of the
   probe matrix still completes. Returns 1; out_* written (0 on bad kind).
   No plog here (threads may fire concurrently); trace stays clean. */
static void probe_syscall_report(char *out, size_t *used, size_t cap);

int box64_probe_trial(int kind, const char *path, int fd,
                      int *out_r1, int *out_r2, int *out_errno) {
    trial_t t;
    memset(&t, 0, sizeof(t));
    t.kind = kind;
    t.path = path;
    t.fd = fd;
    if (out_r1) *out_r1 = -1;
    if (out_r2) *out_r2 = -1;
    if (out_errno) *out_errno = ENOSYS;
    if (kind < 0 || kind >= TK_COUNT)
        return 0;
    bridge_trial_execute(&t);
    if (out_r1) *out_r1 = t.r1;
    if (out_r2) *out_r2 = t.r2;
    if (out_errno) *out_errno = t.r_errno;
    return 1;
}

/* Emits the syscall-number report into `out` for the Swift-side probe. */
int box64_probe_sysnums(char *out, size_t cap) {
    if (!out || cap < 64) return -1;
    out[0] = 0;
    size_t used = 0;
    probe_syscall_report(out, &used, cap);
    return (int)used;
}

/* Runs one trial directly on the probe thread. Every raw syscall is bracketed
   by plog so that if one HANGS the trace snapshot pinpoints the exact call.
   No watchdog threads: LiveContainer's interposer makes pthread_create/
   nanosleep unreliable, and leaked trial threads crashed the app on launch
   (build-369). Returns 0 always; result appended to `out` as a MATRIX line. */
static int bridge_run_trial(trial_t *t, const char *lbl, char *out, size_t *used, size_t cap) {
    char line[320];
    plog("trial[%s] %s ENTER", lbl, trial_name(t->kind));
    bridge_trial_execute(t);
    plog("trial[%s] %s DONE r1=%d errno=%d", lbl, trial_name(t->kind), t->r1, t->r_errno);

    const char *op = trial_name(t->kind);
    if (t->r1 >= 0) {
        char extra[96] = "";
        if (t->kind == TK_RAW_STAT64 || t->kind == TK_LIBC_STAT_DL ||
            t->kind == TK_RAW_FSTAT64 || t->kind == TK_LIBC_FSTAT_DL ||
            t->kind == TK_KERNEL_STAT64 || t->kind == TK_KERNEL_FSTAT64)
            snprintf(extra, sizeof(extra), " size=%d", t->r2);
        else if (t->kind == TK_RAW_READ4 || t->kind == TK_LIBC_READ4_DL ||
                 t->kind == TK_KERNEL_READ)
            snprintf(extra, sizeof(extra), " got=%d", t->r2);
        snprintf(line, sizeof(line), "MATRIX %s | %s = OK r1=%d%s", lbl, op, t->r1, extra);
    } else {
        snprintf(line, sizeof(line), "MATRIX %s | %s = FAIL errno=%d", lbl, op, t->r_errno);
    }
    probe_emit(out, used, cap, line);
    return 0;
}

/* Runs `kinds` (len `nk`) against `path`, in order. `ok` bitmask of kinds
   that returned is written to *okmask. Returns the first fd>=0 obtained
   (for pipeline tests) or -1. NOTE: execution is sequential; a hung syscall
   never returns, so only the ops before it get tested on this path. */
static int probe_matrix_path(const char *lbl, const char *path, const int *kinds, int nk,
                              unsigned long long *okmask, int first_fd, char *out, size_t *used, size_t cap) {
    int got_fd = -1;
    for (int i = 0; i < nk; i++) {
        trial_t t;
        memset(&t, 0, sizeof(t));
        t.kind = kinds[i];
        t.path = path;
        t.fd = first_fd;
        bridge_run_trial(&t, lbl, out, used, cap);
        *okmask |= (1ULL << (unsigned)kinds[i]);
        if (got_fd < 0 && t.r1 >= 0 &&
            (kinds[i] == TK_REAL_SC_OPEN || kinds[i] == TK_REAL_SC_OPENAT ||
             kinds[i] == TK_RAW_OPEN || kinds[i] == TK_RAW_OPENAT ||
             kinds[i] == TK_LIBC_OPEN_DL || kinds[i] == TK_LIBC_OPEN ||
             kinds[i] == TK_LIBC_FOPEN_PLAIN ||
             kinds[i] == TK_KERNEL_OPENAT || kinds[i] == TK_KERNEL_OPEN ||
             kinds[i] == TK_KERNEL_OPENAT_CLS || kinds[i] == TK_KERNEL_OPENAT_RAW))
            got_fd = t.r1;
    }
    return got_fd;
}

static void probe_syscall_report(char *out, size_t *used, size_t cap) {
    char line[512];
    snprintf(line, sizeof(line),
             "SYSNUMS SYS_open=%d SYS_openat=%d SYS_stat64=%d SYS_fstat64=%d "
             "SYS_lseek=%d SYS_read=%d SYS_getdirentries64=%d SYS_mkdir=%d SYS_unlink=%d",
             (int)SYS_open, (int)SYS_openat, (int)SYS_stat64, (int)SYS_fstat64,
             (int)SYS_lseek, (int)SYS_read, (int)SYS_getdirentries64,
             (int)SYS_mkdir, (int)SYS_unlink);
    probe_emit(out, used, cap, line);
    plog("syscall report: %s", line + 8);
#ifdef SYS_getpid
    snprintf(line, sizeof(line), "SYSNUM SYS_getpid=%d", (int)SYS_getpid);
    probe_emit(out, used, cap, line);
#endif
#ifdef SYS___getcwd
    snprintf(line, sizeof(line), "SYSNUM SYS___getcwd=%d", (int)SYS___getcwd);
    probe_emit(out, used, cap, line);
#endif
#ifdef SYS_getcwd
    snprintf(line, sizeof(line), "SYSNUM SYS_getcwd=%d", (int)SYS_getcwd);
    probe_emit(out, used, cap, line);
#endif
#ifdef SYS_close
    snprintf(line, sizeof(line), "SYSNUM SYS_close=%d", (int)SYS_close);
    probe_emit(out, used, cap, line);
#endif
#ifdef SYS_write
    snprintf(line, sizeof(line), "SYSNUM SYS_write=%d", (int)SYS_write);
    probe_emit(out, used, cap, line);
#endif
#ifdef SYS_access
    snprintf(line, sizeof(line), "SYSNUM SYS_access=%d", (int)SYS_access);
    probe_emit(out, used, cap, line);
#endif
}

void box64_probe_paths(const char *docs, const char *bundle, const char *tmpdir, const char *home, char *out, size_t out_len) {
    if (docs && docs[0]) {
        snprintf(g_trace_path, sizeof(g_trace_path), "%s/probe_trace.log", docs);
    }
    probe_trace_clear();
    plog("box64_probe_paths ENTER docs=%s bundle=%s tmpdir=%s home=%s",
         docs ? docs : "(null)", bundle ? bundle : "(null)",
         tmpdir ? tmpdir : "(null)", home ? home : "(null)");
    if (!out || out_len < 64) return;
    out[0] = 0;
    size_t used = 0;

    /* dlopen of libSystem.B.dylib HANGS at runtime under LiveContainer, so the
       dlsym'd real-libc mechanisms are unavailable. Every REAL-SC and LIBC-DL
       trial below will report FAIL via the g_libc_* == NULL guards. */
    plog("NOTE: libSystem dlsym skipped (dlopen hangs under LiveContainer)");
    probe_emit(out, &used, out_len, "==== box64_probe_paths v368 (per-trial threads + real-libc baseline) ====");
    probe_syscall_report(out, &used, out_len);
    const char *env_home = getenv("HOME");
    const char *td = getenv("TMPDIR");
    plog("env HOME=%s TMPDIR=%s", env_home ? env_home : "(null)", td ? td : "(null)");

    char l1[1400];
    snprintf(l1, sizeof(l1), "ARG docs=%s", docs ? docs : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "ARG bundle=%s", bundle ? bundle : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "ARG tmpdir=%s", tmpdir ? tmpdir : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "ARG home=%s", home ? home : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "ENV HOME=%s", env_home ? env_home : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "ENV TMPDIR=%s", td ? td : "(null)");
    probe_emit(out, &used, out_len, l1);
    char cwd_buf[1024];
    plog("getcwd...");
    const char *cwd = box64_raw_getcwd(cwd_buf, sizeof(cwd_buf));
    plog("getcwd=%s", cwd ? cwd : "(null)");
    snprintf(l1, sizeof(l1), "getcwd=%s", cwd ? cwd : "(null)");
    probe_emit(out, &used, out_len, l1);

    static char w64raw[1400], realdocs[1400], bw[1400];
    w64raw[0] = realdocs[0] = bw[0] = 0;
    if (docs && docs[0]) snprintf(w64raw, sizeof(w64raw), "%s/Wine/bin/wine64", docs);
    if (td && td[0]) snprintf(realdocs, sizeof(realdocs), "%s/../Documents", td);
    if (bundle && bundle[0]) snprintf(bw, sizeof(bw), "%s/BundledBinaries/Wine/bin/wine64", bundle);

    /* Resolve realpaths for the paths we care about (realpath is proven to
       work under LiveContainer). */
    char rp_w64[1300], rp_bw[1300], rp_docs[1300], rp_rd[1300], rp_tmp[1300];
    rp_w64[0] = rp_bw[0] = rp_docs[0] = rp_rd[0] = rp_tmp[0] = 0;
    if (w64raw[0]) { const char *r = realpath(w64raw, rp_w64); if (!r) rp_w64[0] = 0; }
    if (bw[0]) { const char *r = realpath(bw, rp_bw); if (!r) rp_bw[0] = 0; }
    if (docs && docs[0]) { const char *r = realpath(docs, rp_docs); if (!r) rp_docs[0] = 0; }
    if (realdocs[0]) { const char *r = realpath(realdocs, rp_rd); if (!r) rp_rd[0] = 0; }
    const char *r = realpath("/tmp", rp_tmp); if (!r) rp_tmp[0] = 0;

    probe_emit(out, &used, out_len, "---- paths ----");
    snprintf(l1, sizeof(l1), "PATH w64-raw=%s", w64raw[0] ? w64raw : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "PATH w64-real=%s", rp_w64[0] ? rp_w64 : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "PATH docs-real=%s", rp_docs[0] ? rp_docs : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "PATH realdocs=%s", rp_rd[0] ? rp_rd : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "PATH bundle-w64-real=%s", rp_bw[0] ? rp_bw : "(null)");
    probe_emit(out, &used, out_len, l1);
    snprintf(l1, sizeof(l1), "PATH /tmp=%s", rp_tmp[0] ? rp_tmp : "(null)");
    probe_emit(out, &used, out_len, l1);

    /* ---- Phase 1: pure kernel sanity — no paths, cannot hang ----
       getpid/getcwd through the raw svc trap. build-374 died on the very
       first sanity trial (raw getpid HANGS — mach-class decode of the bare
       number), so the CLASS-ENCODED trials run FIRST here and the raw ones
       last; box64_raw_syscall now defaults to the 0x2000000 encoding. */
    probe_emit(out, &used, out_len, "---- kernel sanity: getpid/getcwd (svc raw vs cls) ----");
    unsigned long long okmask = 0;
    {
        static const int sanity_ops[] = { TK_KERNEL_GETPID_CLS, TK_KERNEL_GETCWD_CLS,
                                          TK_KERNEL_GETPID_RAW, TK_KERNEL_GETCWD };
        probe_matrix_path("sanity", NULL, sanity_ops,
                          (int)(sizeof(sanity_ops) / sizeof(sanity_ops[0])),
                          &okmask, -1, out, &used, out_len);
    }

    /* ---- Phase 2: stat64 on wine64 (path but no open; stat is a separate
           syscall class and may behave differently from openat) ---- */
    probe_emit(out, &used, out_len, "---- stat64: wine64 (realpath) ----");
    {
        static const int stat_ops[] = { TK_KERNEL_STAT64 };
        probe_matrix_path("w64-stat", rp_w64[0] ? rp_w64 : w64raw, stat_ops, 1,
                          &okmask, -1, out, &used, out_len);
    }

    /* ---- Phase 3: opens on trivial paths first. If openat even of
           /dev/null hangs, the hang is syscall-level (trap/encoding); if
           /dev/null and /tmp work but wine64 hangs, it is path-level. ---- */
    probe_emit(out, &used, out_len, "---- matrix: /dev/null ----");
    int p0_fd = -1;
    {
        static const int devnull_ops[] = { TK_KERNEL_OPENAT, TK_KERNEL_OPEN,
                                           TK_KERNEL_OPENAT_CLS };
        p0_fd = probe_matrix_path("devnull", "/dev/null", devnull_ops,
                                  (int)(sizeof(devnull_ops) / sizeof(devnull_ops[0])),
                                  &okmask, -1, out, &used, out_len);
    }
    int tmp_fd = -1;
    if (rp_tmp[0]) {
        probe_emit(out, &used, out_len, "---- matrix: /tmp ----");
        static const int tmp_ops[] = { TK_KERNEL_OPENAT, TK_KERNEL_OPEN,
                                       TK_KERNEL_OPENAT_CLS };
        tmp_fd = probe_matrix_path("tmp", rp_tmp, tmp_ops,
                                   (int)(sizeof(tmp_ops) / sizeof(tmp_ops[0])),
                                   &okmask, -1, out, &used, out_len);
    }

    /* ---- Phase 4: the critical open: wine64 itself. openat(raw) is a
           KNOWN hang on this path (build-373), so try the class-encoded and
           legacy SYS_open forms FIRST and keep the known-hang last. ---- */
    probe_emit(out, &used, out_len, "---- matrix: wine64 (realpath) ----");
    int w64_fd = -1;
    {
        static const int w64_ops[] = { TK_KERNEL_OPENAT_CLS, TK_KERNEL_OPEN,
                                       TK_KERNEL_OPENAT };
        w64_fd = probe_matrix_path("w64-real", rp_w64[0] ? rp_w64 : w64raw, w64_ops,
                                   (int)(sizeof(w64_ops) / sizeof(w64_ops[0])),
                                   &okmask, -1, out, &used, out_len);
        if (w64_fd < 0 && rp_w64[0] && w64raw[0] && strcmp(rp_w64, w64raw) != 0) {
            probe_emit(out, &used, out_len, "---- matrix: wine64 (as-given) ----");
            w64_fd = probe_matrix_path("w64-raw", w64raw, w64_ops,
                                       (int)(sizeof(w64_ops) / sizeof(w64_ops[0])),
                                       &okmask, -1, out, &used, out_len);
        }
        if (w64_fd < 0 && rp_bw[0]) {
            probe_emit(out, &used, out_len, "---- matrix: bundled wine64 ----");
            w64_fd = probe_matrix_path("bundle-w64", rp_bw, w64_ops,
                                       (int)(sizeof(w64_ops) / sizeof(w64_ops[0])),
                                       &okmask, -1, out, &used, out_len);
        }
    }
    plog("matrix wine64 okmask=0x%llx p0_fd=%d tmp_fd=%d w64_fd=%d", okmask, p0_fd, tmp_fd, w64_fd);

    /* ---- Phase 5: symbol/interposer trials (GATED: syscall(SYS_openat)
           HANGS under LiveContainer, build-372). Read-only ops on wine64;
           write ops on a /tmp scratch path so nothing destroys wine64. ---- */
    if (getenv("MN_PROBE_SYSCALL_SYMBOL")) {
        probe_emit(out, &used, out_len, "---- matrix: wine64 (symbol/gated) ----");
        static const int sym_ops[] = { TK_REAL_SC_OPEN, TK_REAL_SC_OPENAT,
                                       TK_LIBC_OPEN_DL, TK_LIBC_STAT_DL,
                                       TK_LIBC_FOPEN_DL, TK_LIBC_FSTAT_DL,
                                       TK_LIBC_READ4_DL,
                                       TK_LIBC_OPEN, TK_LIBC_FOPEN_PLAIN,
                                       TK_LIBC_STAT_PLAIN, TK_LIBC_OPENDIR_PLAIN,
                                       TK_RAW_STAT64,
                                       TK_RAW_OPEN, TK_RAW_OPENAT,
                                       TK_KERNEL_OPENAT_RAW };
        probe_matrix_path("w64-gated", rp_w64[0] ? rp_w64 : w64raw, sym_ops,
                          (int)(sizeof(sym_ops) / sizeof(sym_ops[0])),
                          &okmask, -1, out, &used, out_len);
        char wpath[1400];
        snprintf(wpath, sizeof(wpath), "/tmp/.__mn_gated_%ld", (long)getpid());
        probe_emit(out, &used, out_len, "---- write ops (gated, /tmp scratch) ----");
        static const int write_ops[] = { TK_LIBC_MKDIR_PLAIN, TK_LIBC_CREATE_PLAIN,
                                         TK_LIBC_UNLINK_PLAIN, TK_REAL_SC_MKDIR,
                                         TK_REAL_SC_CREATE, TK_REAL_SC_UNLINK };
        probe_matrix_path("tmp-gated", wpath, write_ops,
                          (int)(sizeof(write_ops) / sizeof(write_ops[0])),
                          &okmask, -1, out, &used, out_len);
        plog("gated write scratch=%s", wpath);
    }

    /* ---- Phase 6: full elfloader pipeline (open→fstat→read) ---- */
    probe_emit(out, &used, out_len, "---- pipeline: open→fstat→read ----");
    int pipe_fd = (w64_fd >= 0) ? w64_fd : p0_fd;
    if (pipe_fd < 0) {
        probe_emit(out, &used, out_len, "PIPELINE | no working open — skipped");
    } else {
        int pipe_ops[8];
        int n_pipe = 0;
        pipe_ops[n_pipe++] = TK_KERNEL_FSTAT64;
        pipe_ops[n_pipe++] = TK_KERNEL_READ;
        if (getenv("MN_PROBE_SYSCALL_SYMBOL")) {
            pipe_ops[n_pipe++] = TK_RAW_FSTAT64;
            pipe_ops[n_pipe++] = TK_LIBC_FSTAT_DL;
            pipe_ops[n_pipe++] = TK_RAW_READ4;
            pipe_ops[n_pipe++] = TK_LIBC_READ4_DL;
            pipe_ops[n_pipe++] = TK_LIBC_FSTAT_PLAIN;
            pipe_ops[n_pipe++] = TK_LIBC_READ_PLAIN;
        }
        probe_matrix_path("pipe", NULL, pipe_ops, n_pipe, &okmask, pipe_fd, out, &used, out_len);
    }

    /* ---- Phase 7: directory readdir on TMPDIR (reuse tmp_fd if opened) ---- */
    probe_emit(out, &used, out_len, "---- readdir: TMPDIR ----");
    {
        int dirfd = tmp_fd;
        if (dirfd < 0) {
            trial_t t;
            memset(&t, 0, sizeof(t));
            t.kind = TK_KERNEL_OPENAT_CLS;   /* cls first; raw may hang */
            t.path = td ? td : "/tmp";
            bridge_run_trial(&t, "tmpdir-open", out, &used, out_len);
            dirfd = t.r1;
        }
        if (dirfd >= 0) {
            int got[] = { TK_KERNEL_GETDENTS64 };
            probe_matrix_path("tmpdir-readdir", NULL, got, 1, &okmask, dirfd, out, &used, out_len);
        } else {
            probe_emit(out, &used, out_len, "READDIR tmpdir | no working open — skipped");
        }
    }

    /* ---- Phase 8: write/create/delete on /tmp ---- */
    probe_emit(out, &used, out_len, "---- write test: /tmp ----");
    {
        char wpath[1400];
        snprintf(wpath, sizeof(wpath), "/tmp/.__mn_probe_%ld", (long)getpid());
        trial_t t;
        memset(&t, 0, sizeof(t));
        t.kind = TK_KERNEL_CREATE;
        t.path = wpath;
        bridge_run_trial(&t, "tmp-write", out, &used, out_len);
        trial_t u;
        memset(&u, 0, sizeof(u));
        u.kind = TK_KERNEL_UNLINK;
        u.path = wpath;
        bridge_run_trial(&u, "tmp-unlink", out, &used, out_len);
        trial_t m;
        memset(&m, 0, sizeof(m));
        m.kind = TK_KERNEL_MKDIR;
        m.path = "/tmp/.__mn_dir";
        bridge_run_trial(&m, "tmp-mkdir", out, &used, out_len);
        trial_t r;
        memset(&r, 0, sizeof(r));
        r.kind = TK_KERNEL_UNLINK;
        r.path = "/tmp/.__mn_dir";
        bridge_run_trial(&r, "tmp-rmdir", out, &used, out_len);
    }

    /* build-371: calloc() itself HANGS on the probe thread (trace died right
       before the first trial). Deliberately LAST so a heap hang cannot lose
       the matrix/pipeline data above. */
    plog("heap-test: malloc(64)...");
    {
        void *hp = malloc(64);
        plog("heap-test: malloc done hp=%s", hp ? "ok" : "FAIL");
        if (hp) {
            free(hp);
            plog("heap-test: free ok");
        }
    }
    plog("heap-test: calloc(1,64)...");
    {
        void *cp = calloc(1, 64);
        plog("heap-test: calloc done cp=%s", cp ? "ok" : "FAIL");
        if (cp) {
            free(cp);
            plog("heap-test: calloc free ok");
        }
    }
    probe_emit(out, &used, out_len, "HEAP malloc(64) calloc(1,64) tested (see trace for result)");

    probe_emit(out, &used, out_len, "==== box64_probe_paths END ====");
    plog("box64_probe_paths END used=%zu okmask=0x%llx", used, okmask);
}
