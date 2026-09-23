/* Build from the repository root:
 *   cc -O2 -std=c11 -I src src/native_heap.c src/native_arena.c src/native_collections.c \
 *      src/native_text.c src/native_dictionary.c src/native_equal.c <this file> */
/* Simulate binary_trees against the native heap: explicit roots per frame. */
#include "native_heap.h"
#include <stdio.h>
#include <stdlib.h>
typedef struct Node { struct Node *left, *right; } Node;
static const myl_native_type ptr = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_POINTER};
static const myl_native_field fields[] = {{.offset = 0, .type = &ptr}, {.offset = 8, .type = &ptr}};
static const myl_native_type node_t = {.size = 16, .alignment = 8, .kind = MYL_NATIVE_RECORD, .fields = fields, .field_count = 2, .cell = 1};
static myl_native_heap heap;
static Node *make(int d) {
    Node *l = NULL, *r = NULL;
    myl_native_root rl, rr;
    if (d > 0) {
        l = make(d - 1);
        myl_native_root_push(&heap, &rl, &l, &ptr);
        r = make(d - 1);
        myl_native_root_push(&heap, &rr, &r, &ptr);
    }
    Node *n = myl_native_heap_alloc_small(&heap, &node_t, 1);
    if (d > 0) { myl_native_root_pop(&heap, &rr); myl_native_root_pop(&heap, &rl); }
    n->left = l; n->right = r;
    return n;
}
static long check(Node *n) { return n->left ? 1 + check(n->left) + check(n->right) : 1; }
int main(void) {
    myl_native_heap_init(&heap, SIZE_MAX);
    int max = 16, min = 4;
    printf("stretch %ld\n", check(make(max + 1)));
    Node *longl = make(max);
    myl_native_root lr; myl_native_root_push(&heap, &lr, &longl, &ptr);
    for (int d = min; d <= max; d += 2) {
        long it = 1L << (max - d + min), t = 0;
        for (long i = 0; i < it; i++) t += check(make(d));
        printf("%ld trees depth %d check %ld  minors %zu fulls %zu old %zu KiB\n", it, d, t,
               heap.generations.minor_collections, heap.generations.full_collections, heap.generations.old_bytes >> 10);
    }
    printf("long %ld\n", check(longl));
    return 0;
}
