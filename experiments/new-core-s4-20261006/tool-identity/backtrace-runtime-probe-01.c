#include <execinfo.h>
#include <stdio.h>
int main(void) { void *frames[16]; int n = backtrace(frames, 16); printf("frames=%d\n", n); return n > 0 ? 0 : 1; }
