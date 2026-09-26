#include <stddef.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
typedef struct Header { struct Header *previous, *next; max_align_t alignment; } Header;
extern void *__libc_calloc(size_t, size_t);
void *calloc(size_t count, size_t bytes) {
    if (count == 1 && bytes == 212736 + sizeof(Header)) {
        static const char refused[] = "FRAME_ALLOC_REFUSED\n";
        (void)write(2, refused, sizeof(refused)-1);
        errno = ENOMEM;
        return NULL;
    }
    return __libc_calloc(count, bytes);
}
