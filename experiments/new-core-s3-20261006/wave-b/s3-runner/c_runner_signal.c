#include <signal.h>
#include <pthread.h>
#include <stdint.h>
#include <unistd.h>
extern uint64_t myl_core_test_read(void) __attribute__((weak));
static void fault_trial(void) { raise(SIGSEGV); _exit(71); }
/* Core forks a trial; the old harness loads its guest library in its fresh
 * trial process. Fault at those boundaries without granting the guest Host. */
__attribute__((constructor)) static void install_fault(void) {
    if (myl_core_test_read) {
        if (pthread_atfork(NULL, NULL, fault_trial)) _exit(71);
    } else fault_trial();
}
