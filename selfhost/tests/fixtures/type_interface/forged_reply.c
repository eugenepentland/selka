/* Developer-only hostile component fixture; no Python or compiler code used. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifndef FORGE_CASE
#define FORGE_CASE 0
#endif
static void put(uint8_t *bytes, size_t at, uint32_t value) {
    for (unsigned i = 0; i < 4; ++i) bytes[at+i] = (uint8_t)(value >> (8*i));
}
int main(int argc, char **argv) {
    if (argc != 3 || strcmp(argv[1], "--exchange")) return 2;
    FILE *request = fopen(argv[2], "rb");
    if (!request) return 2;
    uint8_t response[128] = {0};
    size_t read = fread(response, 1, 64, request);
    fclose(request);
    if (read != 64) return 2;
    memcpy(response + 64, "SLKTYR01", 8);
    size_t size = 88;
    put(response, 72, 0);
#if FORGE_CASE == 1
    put(response, 76, 65537); /* impossible order count */
#elif FORGE_CASE == 2
    put(response, 72, 2); /* undefined outcome */
#elif FORGE_CASE == 3
    put(response, 76, 1);
    put(response, 80, 0xffffffffu); /* impossible module identity */
    put(response, 84, 1);
    put(response, 88, 0);
    put(response, 92, 0);
    size = 96;
#endif
    /* Case0 is a structurally valid omission of the project order and all reference receipts. */
    put(response, 16, 1);
    put(response, 20, (uint32_t)(size - 64));
    return fwrite(response, 1, size, stdout) == size ? 0 : 2;
}
