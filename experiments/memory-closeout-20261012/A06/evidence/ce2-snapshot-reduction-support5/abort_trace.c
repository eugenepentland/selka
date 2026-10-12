#include <execinfo.h>
#include <signal.h>
#include <unistd.h>

static void trace_abort(int signal_number) {
    void *frames[64];
    int count = backtrace(frames, 64);
    backtrace_symbols_fd(frames, count, STDERR_FILENO);
    _exit(128 + signal_number);
}

__attribute__((constructor)) static void install_trace(void) {
    void *warm[1];
    (void)backtrace(warm, 1);
    signal(SIGABRT, trace_abort);
}
