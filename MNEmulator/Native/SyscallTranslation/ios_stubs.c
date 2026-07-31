#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>

/* Box64 needs these Linux/glibc symbols that don't exist on iOS */

int __isnanf(float x) { return isnan((double)x); }
int __isinf(double x) { return isinf(x); }
int __isnan(double x) { return isnan(x); }

void sincos(double x, double *sinval, double *cosval) {
    *sinval = sin(x);
    *cosval = cos(x);
}
void sincosf(float x, float *sinval, float *cosval) {
    *sinval = sinf(x);
    *cosval = cosf(x);
}

typedef struct { void *emu; } x64emu_t;

void leave_critical_section(void *emu) { (void)emu; }
void enter_critical_section(void *emu) { (void)emu; }

int my_GetGthreadsGotInitialized(void) { return 0; }

x64emu_t *thread_get_emu(void) { return NULL; }

void *__libc_dlopen_mode(const char *name, int mode) { return dlopen(name, mode); }
void *__libc_dlsym(void *handle, const char *name) { return dlsym(handle, name); }
int __libc_dlclose(void *handle) { return dlclose(handle); }

int of_convert(int x) { return x; }

/* exit() interceptor — when Box64 source calls exit(), the -Dexit macro redirects here.
   We just return instead of exiting, so the iOS app stays alive. */
void box64_exit_intercept(int status) {
    /* Write to the runner log if it exists */
    const char *home = getenv("HOME");
    if (home) {
        char path[512];
        snprintf(path, sizeof(path), "%s/Documents/box64_runner.log", home);
        int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd >= 0) {
            char buf[128];
            int n = snprintf(buf, sizeof(buf), "[Stubs] exit(%d) intercepted — returning\n", status);
            write(fd, buf, n);
            close(fd);
        }
    }
    /* Just return — don't let Box64 kill the iOS app */
}
