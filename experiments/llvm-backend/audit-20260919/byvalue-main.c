#include <inttypes.h>
#include <stdio.h>
extern int64_t test(void);
int main(void) { printf("%" PRId64 "\n", test()); }
