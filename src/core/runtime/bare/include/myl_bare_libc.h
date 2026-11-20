/* The C library the runtime's kept files see in a bare build (-DMYL_BARE, no operating system).
 *
 * Every <header> a kept file includes (stdio.h, stdlib.h, pthread.h, ...) is a one-line file in this folder that
 * includes this one, so the hosted text keeps its own #include lines and the bare build is chosen by the include path
 * alone. Compiler headers (stdint.h, stddef.h, stdbool.h, stdatomic.h, limits.h, float.h, stdarg.h) are clang's own.
 *
 * What is here:
 *  - functions the target's compiler runtime does not supply (zig supplies memcpy, memmove, memset, memcmp, strlen,
 *    floor, sqrt and the 64-bit arithmetic helpers): the heap, memchr, memmem, strcmp, strncmp, strchr, strstr,
 *    strpbrk, a small snprintf, abort, getenv; defined in core_bare.c;
 *  - operating-system calls the hosted layer makes, as stand-ins with no threads and no files: a write goes to the
 *    platform's `myl_bare_write`, `_exit` to `myl_bare_exit`, a mutex does nothing, a once runs once, a clock reads
 *    zero, a backtrace finds no frames (so the frame reader is dead code and the optimiser drops it), a file open fails.
 *
 * A program that starts the second core (`registers.start_core1`) gets the two-core flavour of the runtime
 * (-DMYL_BARE_CORES, chosen by the driver, `driver.bareCores`): there a write goes to the platform one core at a time
 * (`myl_bare_log_write`), `_exit` ends the program on both cores (`myl_bare_finish`; both in core_bare_cores.c), a
 * mutex still does nothing (what it guards is each core's own: the runtime's per-thread and shared state is per core),
 * and a once runs once on either core. Every other program's runtime is the one-core runtime, byte for byte.
 */
#ifndef MYL_BARE_LIBC_H
#define MYL_BARE_LIBC_H
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MYL_BARE_INLINE static inline __attribute__((always_inline, unused))

/* ---- the platform's two hooks (weak defaults in core_bare.c) ---- */
void myl_bare_write(int stream, const unsigned char *bytes, size_t length);
__attribute__((noreturn)) void myl_bare_exit(int status);
#if defined(MYL_BARE_CORES)
/* The runtime's side of them (core_bare_cores.c): a write serialised between the cores, and the end of the program. */
void myl_bare_log_write(int stream, const unsigned char *bytes, size_t length);
__attribute__((noreturn)) void myl_bare_finish(int status);
/* The once of core_bare_cores.c: `run` runs once, and a core that arrives while the other runs it waits. */
void myl_bare_once(int *once, void (*run)(void));
#else
/* One core: the runtime's write and end are the platform's own. */
#define myl_bare_log_write myl_bare_write
#define myl_bare_finish myl_bare_exit
#endif

/* ---- errno.h ---- */
#if defined(MYL_BARE_CORES)
extern _Thread_local int myl_bare_errno;
#else
extern int myl_bare_errno;
#endif
#define errno myl_bare_errno
#define EIO 5
#define ENOMEM 12
#define EINVAL 22
#define EPIPE 32

/* ---- stdlib.h, malloc.h ---- */
void *malloc(size_t size);
void *calloc(size_t count, size_t size);
void *realloc(void *pointer, size_t size);
void free(void *pointer);
void *aligned_alloc(size_t alignment, size_t size);
size_t malloc_usable_size(void *pointer);
__attribute__((noreturn)) void abort(void);
__attribute__((noreturn)) void exit(int status);
char *getenv(const char *name);
double strtod(const char *text, char **end);
struct mallinfo { int arena, ordblks, smblks, hblks, hblkhd, usmblks, fsmblks, uordblks, fordblks, keepcost; };
#define M_TRIM_THRESHOLD (-1)
#define M_MMAP_THRESHOLD (-3)
MYL_BARE_INLINE int mallopt(int parameter, int value) { (void)parameter; (void)value; return 0; }
MYL_BARE_INLINE int malloc_trim(size_t pad) { (void)pad; return 0; }
MYL_BARE_INLINE struct mallinfo mallinfo(void) { struct mallinfo none = {0}; return none; }

/* The 128-bit product of two 64-bit integers (no __int128 on a 32-bit CPU): returns the low half, `*high` the high. */
MYL_BARE_INLINE uint64_t myl_bare_multiply_wide(uint64_t a, uint64_t b, uint64_t *high) {
    const uint64_t a0 = (uint32_t)a, a1 = a >> 32, b0 = (uint32_t)b, b1 = b >> 32;
    const uint64_t p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
    const uint64_t middle = (p00 >> 32) + (uint32_t)p01 + (uint32_t)p10;
    *high = p11 + (p01 >> 32) + (p10 >> 32) + (middle >> 32);
    return (middle << 32) | (uint32_t)p00;
}

/* ---- string.h ---- */
void *memcpy(void *restrict to, const void *restrict from, size_t length);
void *memmove(void *to, const void *from, size_t length);
void *memset(void *to, int value, size_t length);
int memcmp(const void *left, const void *right, size_t length);
void *memchr(const void *bytes, int value, size_t length);
void *memmem(const void *haystack, size_t haystack_length, const void *needle, size_t needle_length);
size_t strlen(const char *text);
int strcmp(const char *left, const char *right);
int strncmp(const char *left, const char *right, size_t length);
char *strchr(const char *text, int value);
char *strstr(const char *haystack, const char *needle);
char *strpbrk(const char *text, const char *accept);

/* ---- stdio.h: no files; snprintf knows integers, text and characters (a float writes "<float>") ---- */
typedef struct myl_bare_file FILE;
#define stdout ((FILE *)1)
#define stderr ((FILE *)2)
int vsnprintf(char *out, size_t room, const char *format, va_list arguments);
int snprintf(char *out, size_t room, const char *format, ...) __attribute__((format(printf, 3, 4)));
int fprintf(FILE *stream, const char *format, ...) __attribute__((format(printf, 2, 3)));

/* ---- inttypes.h (ILP32: int64_t is long long) ---- */
#define PRId64 "lld"
#define PRIu64 "llu"
#define PRIx64 "llx"

/* ---- math.h: zig supplies floor and sqrt; the rest of what a kept file names ---- */
double floor(double value);
double ceil(double value);
double sqrt(double value);
double fabs(double value);
double fmod(double left, double right);
double trunc(double value);
double round(double value);
double pow(double base, double exponent);
#define isnan(x) __builtin_isnan(x)
#define isinf(x) __builtin_isinf(x)
#define isfinite(x) __builtin_isfinite(x)
#define signbit(x) __builtin_signbit(x)
#define INFINITY __builtin_inff()
#define NAN __builtin_nanf("")
#define HUGE_VAL __builtin_huge_val()

/* ---- unistd.h, fcntl.h, sys/stat.h, sys/mman.h, sys/syscall.h, sched.h ---- */
typedef int ssize_t;
typedef long off_t;
typedef int pid_t;
MYL_BARE_INLINE ssize_t write(int fd, const void *bytes, size_t length) {
    myl_bare_log_write(fd, (const unsigned char *)bytes, length);
    return (ssize_t)length;
}
MYL_BARE_INLINE __attribute__((noreturn)) void _exit(int status) { myl_bare_finish(status); }
MYL_BARE_INLINE __attribute__((noreturn)) void _Exit(int status) { myl_bare_finish(status); }
#define O_RDONLY 0
MYL_BARE_INLINE int open(const char *path, int flags, ...) { (void)path; (void)flags; errno = EINVAL; return -1; }
MYL_BARE_INLINE int close(int fd) { (void)fd; return 0; }
struct stat { off_t st_size; };
MYL_BARE_INLINE int fstat(int fd, struct stat *info) { (void)fd; (void)info; return -1; }
#define PROT_READ 1
#define MAP_PRIVATE 2
#define MAP_FAILED ((void *)-1)
MYL_BARE_INLINE void *mmap(void *at, size_t length, int protection, int flags, int fd, off_t offset) {
    (void)at; (void)length; (void)protection; (void)flags; (void)fd; (void)offset;
    return MAP_FAILED;
}
#define SYS_gettid 1
#define SYS_futex 2
#define FUTEX_WAIT_PRIVATE 128
#define FUTEX_WAKE_PRIVATE 129
MYL_BARE_INLINE long syscall(long number, ...) { (void)number; return 1; }
MYL_BARE_INLINE int sched_yield(void) { return 0; }

/* ---- time.h: no clock; time stands still at zero ---- */
typedef int clockid_t;
struct timespec { long long tv_sec; long tv_nsec; };
#define CLOCK_MONOTONIC 1
#define CLOCK_REALTIME 0
MYL_BARE_INLINE int clock_gettime(clockid_t clock, struct timespec *now) {
    (void)clock;
    now->tv_sec = 0;
    now->tv_nsec = 0;
    return 0;
}

/* ---- execinfo.h: no unwinder, so no frames ---- */
MYL_BARE_INLINE int backtrace(void **pcs, int capacity) { (void)pcs; (void)capacity; return 0; }

/* ---- pthread.h: no threads (with two cores, a mutex guards state each core keeps for itself) ---- */
typedef struct { int unused; } pthread_mutex_t;
typedef int pthread_once_t;
typedef int pthread_key_t;
typedef unsigned long pthread_t;
#define PTHREAD_MUTEX_INITIALIZER {0}
#define PTHREAD_ONCE_INIT 0
MYL_BARE_INLINE int pthread_mutex_lock(pthread_mutex_t *mutex) { (void)mutex; return 0; }
MYL_BARE_INLINE int pthread_mutex_unlock(pthread_mutex_t *mutex) { (void)mutex; return 0; }
MYL_BARE_INLINE int pthread_mutex_trylock(pthread_mutex_t *mutex) { (void)mutex; return 0; }
MYL_BARE_INLINE int pthread_once(pthread_once_t *once, void (*run)(void)) {
#if defined(MYL_BARE_CORES)
    myl_bare_once(once, run);
#else
    if (!*once) { *once = 1; run(); }
#endif
    return 0;
}
MYL_BARE_INLINE int pthread_key_create(pthread_key_t *key, void (*destroy)(void *)) { (void)destroy; *key = 0; return 0; }
MYL_BARE_INLINE int pthread_setspecific(pthread_key_t key, const void *value) { (void)key; (void)value; return 0; }

/* ---- signal.h ---- */
#define SIGPIPE 13

/* ---- elf.h: the types the frame reader names (it is dead code here: no frames are ever found) ---- */
typedef struct {
    unsigned char e_ident[16];
    uint16_t e_type, e_machine;
    uint32_t e_version;
    uint64_t e_entry, e_phoff, e_shoff;
    uint32_t e_flags;
    uint16_t e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx;
} Elf64_Ehdr;
typedef struct {
    uint32_t sh_name, sh_type;
    uint64_t sh_flags, sh_addr, sh_offset, sh_size;
    uint32_t sh_link, sh_info;
    uint64_t sh_addralign, sh_entsize;
} Elf64_Shdr;
typedef struct {
    uint32_t p_type, p_flags;
    uint64_t p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align;
} Elf64_Phdr;
#define PT_LOAD 1

#endif
