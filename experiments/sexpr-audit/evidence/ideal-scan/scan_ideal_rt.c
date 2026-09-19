#include <stdio.h>
#include <stdlib.h>
void myl_fake_register(void *f) { (void)f; }
void myl_fake_fail(void *c, long pc, long i) { (void)c; fprintf(stderr, "trap at %ld (%ld)\n", pc, i); exit(1); }
