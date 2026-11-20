/* An explicit native test helper: no guest Host operation or network access. */
#include <pthread.h>
#include <stdint.h>
#include <unistd.h>
extern uint64_t myl_core_test_read(void) __attribute__((weak));
static void exit_trial(void) { _exit(17); }
__attribute__((constructor)) static void install_exit(void) {
    if (myl_core_test_read) pthread_atfork(NULL, NULL, exit_trial);
    else exit_trial();
}
