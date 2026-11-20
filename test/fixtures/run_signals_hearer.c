#include <signal.h>
#include <stdint.h>
#include <string.h>
static volatile sig_atomic_t heard;
static void note(int signal) { (void)signal; heard = heard + 1; }
int64_t hear_stop(void) {
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_handler = note;
    sigaction(SIGINT, &action, 0);
    sigaction(SIGTERM, &action, 0);
    sigaction(SIGHUP, &action, 0);
    return 0;
}
int64_t stops_heard(void) { return heard; }
