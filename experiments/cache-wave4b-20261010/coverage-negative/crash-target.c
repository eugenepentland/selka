#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size && data[0] == '!') abort();
    return 0;
}
