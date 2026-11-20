/* A small cache-contract fixture. Real runtime accounting stays in its tests. */
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    const char *path = getenv("SELKA_COUNTERS");
    if (path == NULL) return 2;
    FILE *output = fopen(path, "w");
    if (output == NULL) return 3;
    int wrote = fputs("{\"cache_probe\":true}\n", output);
    int closed = fclose(output);
    if (wrote < 0 || closed != 0) return 4;
    puts("cache probe executed");
    return 0;
}
