#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
static volatile unsigned sink;
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size && data[0] == 'A') {
        sink = 1;
        if (size > 1 && data[1] == 'B') sink = 2;
    } else sink = 0;
    return 0;
}
