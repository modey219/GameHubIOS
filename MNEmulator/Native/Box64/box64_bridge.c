#include "../Include/box64_bridge.h"
#include "../Include/syscall_translation.h"
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

static box64_context_t *g_box64 = NULL;
static box64_context_t g_static_box64;
static int g_static_box64_used = 0;
static int g_wine_exit_code = 0;
static int g_wine_running = 0;
static char g_wine_error[1024] = {0};

static char g_crash_log_path[1024] = {0};
static char g_docs_path[1024] = {0};

static box64_log_callback g_probe_log_cb = NULL;
void box64_set_probe_log_cb(box64_log_callback cb) { g_probe_log_cb = cb; }

static char g_trace_path[1100] = {0};

#define PROBE_TRACE_MAX 16384
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
    char buf[512];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    probe_trace_append(buf);
    if (g_trace_path[0]) {
        int fd = open(g_trace_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            write(fd, buf, strlen(buf));
            write(fd, "\n", 1);
            close(fd);
        }
    }
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
    if (!docs) return;
    append_to_log(docs, "c_diag.log", s);
    append_to_log(docs, "diag.log", s);
}

void set_c_diag_docs_path(const char *path) {
    if (!path || !path[0]) return;
    strncpy(g_docs_path, path, sizeof(g_docs_path) - 1);
    g_docs_path[sizeof(g_docs_path) - 1] = '\0';

    char test_path[1032];
    snprintf(test_path, sizeof(test_path), "%s/c_diag_test.txt", g_docs_path);
    int fd = open(test_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        const char *msg = "C file IO works!\n";
        write(fd, msg, strlen(msg));
        close(fd);
    }

    c_diag("set_c_diag_docs_path: OK");
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
    int fd = open(rp, O_RDONLY);
    if (fd < 0) return 0;
    off_t sz = lseek(fd, 0, SEEK_END);
    if (fd > 2) close(fd);
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
    int st = stat(path, &s);
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
            int fd = open(tp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            plog("probe_one[%s]: open done fd=%d errno=%d", label, fd, errno);
            if (fd >= 0) { close(fd); unlink(tp); strcpy(access_kind, "dir-writable"); }
            else { snprintf(access_kind, sizeof(access_kind), "dir-readonly(errno=%d)", errno); }
        } else if (S_ISREG(s.st_mode)) {
            plog("probe_one[%s]: open-read %s", label, path);
            int fd = open(path, O_RDONLY);
            plog("probe_one[%s]: open-read done fd=%d errno=%d", label, fd, errno);
            if (fd >= 0) { close(fd); strcpy(access_kind, "file-readable"); }
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
    int fd = open(full, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    plog("write_file: open done fd=%d errno=%d", fd, errno);
    if (fd >= 0) {
        plog("write_file: write %zu bytes", strlen(content));
        write(fd, content, strlen(content));
        close(fd);
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
    int fd = open(rps, O_RDONLY);
    int o_errno = errno;
    plog("open_io[%s]: open done fd=%d errno=%d", label, fd, o_errno);
    if (fd < 0) {
        snprintf(line, sizeof(line), "OPENIO %s | open=fail(errno=%d) realpath=%s", label, o_errno, rps);
        probe_emit(out, used, cap, line);
        return;
    }
    struct stat st;
    errno = 0;
    int fst = fstat(fd, &st);
    int f_errno = errno;
    plog("open_io[%s]: fstat done=%d errno=%d", label, fst, f_errno);
    off_t sz = lseek(fd, 0, SEEK_END);
    int l_errno = errno;
    plog("open_io[%s]: lseek done sz=%lld errno=%d", label, (long long)sz, l_errno);
    char magic[16];
    int n = 0;
    if (sz >= 4) {
        lseek(fd, 0, SEEK_SET);
        n = (int)read(fd, magic, sizeof(magic));
    }
    int r_errno = errno;
    char hex[128] = "";
    for (int i = 0; i < n && i < (int)sizeof(magic); i++) {
        char part[8];
        snprintf(part, sizeof(part), "%02x", (unsigned char)magic[i]);
        strncat(hex, part, sizeof(hex) - strlen(hex) - 1);
        if (i < n - 1) strncat(hex, " ", sizeof(hex) - strlen(hex) - 1);
    }
    if (fd > 2) close(fd);
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
    int st = stat(path, &s);
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
        int fd = open(tp, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        plog("probe_root[%d]: open done fd=%d errno=%d", idx, fd, errno);
        if (fd >= 0) { close(fd); unlink(tp); snprintf(acc, sizeof(acc), "DIR-WRITABLE"); }
        else { snprintf(acc, sizeof(acc), "DIR-readonly(errno=%d)", errno); }
    } else if (st == 0 && S_ISREG(s.st_mode)) {
        plog("probe_root[%d]: open-read %s", idx, path);
        int fd = open(path, O_RDONLY);
        plog("probe_root[%d]: open-read done fd=%d errno=%d", idx, fd, errno);
        if (fd >= 0) { close(fd); snprintf(acc, sizeof(acc), "FILE-readable"); }
        else { snprintf(acc, sizeof(acc), "FILE-openfail(errno=%d)", errno); }
    }
    snprintf(line, sizeof(line), "ROOT %d stat=%s(errno=%d) access=%s realpath=%s | '%s'",
             idx, st == 0 ? "yes" : "no", st_errno, acc, rpstr ? rpstr : "(null)", path);
    probe_emit(out, used, cap, line);
    plog("probe_root[%d]: done", idx);
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

    probe_emit(out, &used, out_len, "==== box64_probe_paths v353 (reallibc shim) ====");
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
    const char *cwd = getcwd(cwd_buf, sizeof(cwd_buf));
    plog("getcwd=%s", cwd ? cwd : "(null)");
    snprintf(l1, sizeof(l1), "getcwd=%s", cwd ? cwd : "(null)");
    probe_emit(out, &used, out_len, l1);

    /* Open-based I/O probe FIRST: tells us whether box64's elfloader
       (open/fstat/read) can ever load wine64 under LiveContainer. */
    plog("open-io probe start");
    probe_emit(out, &used, out_len, "---- open-io probe ----");
    if (docs && docs[0]) {
        char w64[1400], bx[1400];
        snprintf(w64, sizeof(w64), "%s/Wine/bin/wine64", docs);
        snprintf(bx, sizeof(bx), "%s/Box64/box64", docs);
        probe_open_io(out, &used, out_len, "docs/Wine/bin/wine64", w64);
        probe_open_io(out, &used, out_len, "docs/Box64/box64", bx);
    }
    if (bundle && bundle[0]) {
        char bw[1400];
        snprintf(bw, sizeof(bw), "%s/BundledBinaries/Wine/bin/wine64", bundle);
        probe_open_io(out, &used, out_len, "bundle/Wine/bin/wine64", bw);
    }
    if (td && td[0]) {
        char realdocs[1400];
        snprintf(realdocs, sizeof(realdocs), "%s/../Documents", td);
        probe_open_io(out, &used, out_len, "realdocs(td/../Documents)", realdocs);
    }
    probe_open_io(out, &used, out_len, "/tmp", "/tmp");
    plog("open-io probe done");

    /* Candidate POSIX-accessible roots: stat + write test on each.
       Order matters: docs (fake LiveContainer container) HANGS in access(),
       so real-container paths are tested first. */
    char candb[14][1300];
    const char *cands[14];
    int nc = 0;
    /* 0: app bundle (read-only, inside real container Documents) */
    if (bundle && bundle[0]) { snprintf(candb[nc], sizeof(candb[nc]), "%s", bundle); cands[nc] = candb[nc]; nc++; }
    /* 1: TMPDIR (real container tmp) */
    if (tmpdir && tmpdir[0]) { snprintf(candb[nc], sizeof(candb[nc]), "%s", tmpdir); cands[nc] = candb[nc]; nc++; }
    /* 2: real container root = TMPDIR/.. */
    if (tmpdir && tmpdir[0]) { snprintf(candb[nc], sizeof(candb[nc]), "%s/..", tmpdir); cands[nc] = candb[nc]; nc++; }
    /* 3: real container Documents = TMPDIR/../Documents */
    if (tmpdir && tmpdir[0]) { snprintf(candb[nc], sizeof(candb[nc]), "%s/../Documents", tmpdir); cands[nc] = candb[nc]; nc++; }
    /* 4: /tmp */
    snprintf(candb[nc], sizeof(candb[nc]), "/tmp"); cands[nc] = candb[nc]; nc++;
    /* 5: home (fake LiveContainer home) */
    if (home && home[0]) { snprintf(candb[nc], sizeof(candb[nc]), "%s", home); cands[nc] = candb[nc]; nc++; }
    /* 6: env HOME */
    if (env_home && env_home[0]) { snprintf(candb[nc], sizeof(candb[nc]), "%s", env_home); cands[nc] = candb[nc]; nc++; }
    /* 7: home/Documents (fake container docs) */
    if (home && home[0]) { snprintf(candb[nc], sizeof(candb[nc]), "%s/Documents", home); cands[nc] = candb[nc]; nc++; }
    /* 8: env HOME/.. */
    if (env_home && env_home[0]) { snprintf(candb[nc], sizeof(candb[nc]), "%s/..", env_home); cands[nc] = candb[nc]; nc++; }
    /* 9: docs (fake LiveContainer docs — LAST, known to hang in access()) */
    if (docs && docs[0]) { snprintf(candb[nc], sizeof(candb[nc]), "%s", docs); cands[nc] = candb[nc]; nc++; }

    for (int i = 0; i < nc; i++) {
        plog("candidate[%d]='%s'", i, cands[i]);
        probe_root(out, &used, out_len, i, cands[i]);
        plog("candidate[%d] done", i);
    }

    /* Specific file checks */
    plog("specific file checks start");
    if (docs && docs[0]) {
        char w64[1400], bx[1400];
        snprintf(w64, sizeof(w64), "%s/Wine/bin/wine64", docs);
        snprintf(bx, sizeof(bx), "%s/Box64/box64", docs);
        probe_one(out, &used, out_len, "docs/Wine/bin/wine64", w64);
        probe_one(out, &used, out_len, "docs/Box64/box64", bx);
        probe_walk_up(out, &used, out_len, w64);
        probe_walk_up(out, &used, out_len, docs);
    }
    if (bundle && bundle[0]) {
        char bw[1400];
        snprintf(bw, sizeof(bw), "%s/BundledBinaries/Wine", bundle);
        probe_one(out, &used, out_len, "bundle/BundledBinaries/Wine", bw);
    }
    if (home && home[0]) {
        char hw[1400];
        snprintf(hw, sizeof(hw), "%s/Documents/Wine/bin/wine64", home);
        probe_one(out, &used, out_len, "home/Documents/Wine/bin/wine64", hw);
    }
    if (td && td[0]) {
        char realdocs[1400];
        snprintf(realdocs, sizeof(realdocs), "%s/../Documents", td);
        probe_one(out, &used, out_len, "realdocs(td/../Documents)", realdocs);
        probe_walk_up(out, &used, out_len, realdocs);
    }
    plog("specific file checks done");

    /* File-write self-tests: append result, then flush buffer to each candidate file */
    plog("file-write self-tests start");
    probe_emit(out, &used, out_len, "---- file-write self-tests ----");
    if (docs && docs[0]) {
        probe_emit(out, &used, out_len, "FILE-WRITE docs/box64_probe.log attempting...");
        probe_write_file(docs, "box64_probe.log", out);
        probe_emit(out, &used, out_len, "FILE-WRITE docs/box64_probe.log done (fd tried)");
    }
    if (tmpdir && tmpdir[0]) {
        probe_emit(out, &used, out_len, "FILE-WRITE tmpdir/box64_probe.log attempting...");
        probe_write_file(tmpdir, "box64_probe.log", out);
        probe_emit(out, &used, out_len, "FILE-WRITE tmpdir/box64_probe.log done (fd tried)");
    }
    probe_emit(out, &used, out_len, "FILE-WRITE /tmp/box64_probe.log attempting...");
    probe_write_file("/tmp", "box64_probe.log", out);
    probe_emit(out, &used, out_len, "FILE-WRITE /tmp/box64_probe.log done (fd tried)");
    if (home && home[0]) {
        probe_emit(out, &used, out_len, "FILE-WRITE home/box64_probe.log attempting...");
        probe_write_file(home, "box64_probe.log", out);
        probe_emit(out, &used, out_len, "FILE-WRITE home/box64_probe.log done (fd tried)");
    }
    if (env_home && env_home[0]) {
        probe_emit(out, &used, out_len, "FILE-WRITE envHOME/box64_probe.log attempting...");
        probe_write_file(env_home, "box64_probe.log", out);
        probe_emit(out, &used, out_len, "FILE-WRITE envHOME/box64_probe.log done (fd tried)");
    }
    probe_emit(out, &used, out_len, "==== box64_probe_paths END ====");
    plog("box64_probe_paths END used=%zu", used);
}
