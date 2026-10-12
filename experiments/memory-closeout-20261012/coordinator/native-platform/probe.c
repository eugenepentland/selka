#include <execinfo.h>
#include <math.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
static void *trace(void *value) {
    void *frames[16];
    int n = backtrace(frames, 16);
    *(int *)value = n;
    return NULL;
}
int main(int argc, char **argv) {
    int frames = 0;
    pthread_t worker;
    if (pthread_create(&worker, NULL, trace, &frames) != 0) return 2;
    if (pthread_join(worker, NULL) != 0 || frames <= 0) return 3;
    double value = argc > 1 ? atof(argv[1]) : 0.5;
    printf("trace=yes sine=%.6f\n", sin(value));
    return 0;
}
