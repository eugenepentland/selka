#define _DEFAULT_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    size_t mib = strtoul(argv[1], NULL, 10);
    if (mib == 0 || mib > 64) return 2;
    size_t size = mib * 1024 * 1024;
    volatile unsigned char *data = mmap(NULL, size, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (data == MAP_FAILED) return 3;
    size_t page = (size_t)sysconf(_SC_PAGESIZE);
    for (size_t i = 0; i < size; i += page) data[i] = 1;
    size_t checksum = 0;
    for (size_t i = 0; i < size; i += page) checksum += data[i];
    printf("%zu %zu\n", mib, checksum);
    munmap((void *)data, size);
    return 0;
}
