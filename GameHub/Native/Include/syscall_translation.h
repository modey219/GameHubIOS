#ifndef SYSCALL_TRANSLATION_H
#define SYSCALL_TRANSLATION_H

#include "linux_types.h"
#include <pthread.h>

#define SYSCALL_TABLE_SIZE 450
#define MAX_TRANSLATED_FDS 128
#define MAX_MMAP_REGIONS 128

typedef struct {
    int linux_fd;
    int host_fd;
    int flags;
    int is_socket;
    int is_epoll;
    int epoll_fds[1];
    int epoll_count;
} fd_mapping_t;

typedef struct {
    void *guest_addr;
    void *host_addr;
    size_t size;
    int prot;
    int flags;
    int fd;
    long offset;
} mmap_region_t;

typedef struct {
    pthread_t thread;
    int tid;
    int active;
    void *stack;
    size_t stack_size;
} thread_info_t;

typedef struct {
    fd_mapping_t fds[MAX_TRANSLATED_FDS];
    mmap_region_t mmap_regions[MAX_MMAP_REGIONS];
    int mmap_count;
    thread_info_t threads[64];
    int thread_count;
    int pid;
    int ppid;
    unsigned long brk;
    unsigned long start_brk;
    unsigned long mmap_base;
    void *sig_handlers[32];
    unsigned long sig_mask;
    char cwd[256];
    char root[256];
    struct linux_rlimit limits[8];
} linux_process_t;

typedef struct emulator_context {
    linux_process_t process;
    int initialized;
    int running;
} emulator_context_t;

void syscall_translation_init(void);
emulator_context_t *syscall_emulator_create(void);
void syscall_emulator_destroy(emulator_context_t *ctx);
int emulator_run(emulator_context_t *ctx, const char *executable, char **argv, char **envp);
void emulator_stop(emulator_context_t *ctx);

long translate_syscall(emulator_context_t *ctx, long syscall_num, long a1, long a2, long a3, long a4, long a5, long a6);

linux_addr_t emulator_mmap(emulator_context_t *ctx, linux_addr_t addr, size_t length, int prot, int flags, int fd, long offset);
int emulator_mprotect(emulator_context_t *ctx, linux_addr_t addr, size_t length, int prot);
int emulator_munmap(emulator_context_t *ctx, linux_addr_t addr, size_t length);

int host_fd_for_linux(emulator_context_t *ctx, int linux_fd);
int register_host_fd(emulator_context_t *ctx, int linux_fd, int host_fd, int flags);

#endif
