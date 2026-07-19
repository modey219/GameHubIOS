#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <unistd.h>
#include <setjmp.h>

/* Box64 needs these Linux/glibc symbols that don't exist on iOS */

int __isnanf(float x) { return isnan(x); }
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

/* exit() interceptor - prevents Box64 from killing the iOS app */
static volatile jmp_buf *g_exit_jmp_ptr = NULL;

void box64_set_exit_jmp(volatile jmp_buf *buf) {
    g_exit_jmp_ptr = buf;
}

void box64_exit_intercept(int status) {
    if (g_exit_jmp_ptr) {
        longjmp((jmp_buf *)g_exit_jmp_ptr, status ? status : 1);
    }
    /* No jump buffer - just hang instead of killing the app */
    while(1) { sleep(3600); }
}
