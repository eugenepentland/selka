/* A probe for batched test processes (NEW-CORE-TEST-BATCH-1), linked into a test
 * executable with --link. With MYL_BATCH_PROBE_LOG=PATH each test process appends
 * one line to PATH as it starts. With MYL_BATCH_PROBE_FAULT=1 the second trial a
 * process forks ends that process without answering, as a crashing extern would;
 * a test run alone forks one trial and never meets it. */
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
extern uint64_t myl_core_test_read(void) __attribute__((weak));
static unsigned forks;
static void count_fork(void) { ++forks; }
static void fault_second(void) {
    if (forks != 2) return;
    raise(SIGSEGV);
    _exit(71);
}
__attribute__((constructor)) static void install_probe(void) {
    if (!myl_core_test_read) return;
    const char *log = getenv("MYL_BATCH_PROBE_LOG");
    if (log) {
        int fd = open(log, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd < 0 || write(fd, "process\n", 8) != 8) _exit(71);
        close(fd);
    }
    const char *fault = getenv("MYL_BATCH_PROBE_FAULT");
    if (fault && !strcmp(fault, "1") && pthread_atfork(count_fork, NULL, fault_second)) _exit(71);
}
