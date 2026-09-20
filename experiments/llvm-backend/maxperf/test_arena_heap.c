#include "arena_heap.h"

#include <assert.h>
#include <stdint.h>
#include <string.h>

static const myl_native_type byte_type = {
    .size = 1, .alignment = 1, .kind = MYL_NATIVE_PLAIN,
    .trace_mode = MYL_NATIVE_TRACE_NONE
};
static const myl_native_type word_type = {
    .size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN,
    .trace_mode = MYL_NATIVE_TRACE_NONE
};
static const myl_native_type wide_type = {
    .size = 16, .alignment = 16, .kind = MYL_NATIVE_PLAIN,
    .trace_mode = MYL_NATIVE_TRACE_NONE
};

static void exercise(myl_native_heap *heap) {
    unsigned char *byte = myl_native_heap_alloc(heap, &byte_type, 3);
    uint64_t *word = myl_native_heap_alloc(heap, &word_type, 2);
    max_align_t *wide = myl_native_heap_alloc(heap, &wide_type, 1);
    assert(byte && word && wide);
    assert((uintptr_t)word % 8 == 0);
    assert((uintptr_t)wide % 16 == 0);
    assert((void *)byte != (void *)word && (void *)word != (void *)wide);
    assert(byte[0] == 0 && byte[2] == 0 && word[0] == 0 && word[1] == 0);
    memset(byte, 0xa5, 3);
    word[0] = UINT64_MAX;
    myl_native_heap_collect(heap);
    assert(byte[0] == 0xa5 && word[0] == UINT64_MAX);

    unsigned char *empty1 = myl_native_heap_alloc(heap, &byte_type, 0);
    unsigned char *empty2 = myl_native_heap_alloc(heap, &byte_type, 0);
    assert(empty1 && empty2 && empty1 != empty2);
#ifdef MYL_MAXPERF_ARENA_COMPACT
    assert(myl_native_object_region(word) == 0);
#else
    assert(myl_native_object_region(word) == heap->region_depth);
#endif
}

int main(void) {
    myl_native_heap first, second;
    myl_native_heap_init(&first, SIZE_MAX);
    myl_native_heap_init(&second, SIZE_MAX);
    exercise(&first);
    exercise(&second);
    void *large = myl_native_heap_alloc_block(&first, 1, (5u << 20));
    assert(large && ((unsigned char *)large)[0] == 0);
    myl_maxperf_arena_report report;
    assert(myl_maxperf_arena_get_report(&first, &report));
    assert(report.allocations == 6 && report.collections == 0);
    assert(report.chunks >= 2 && report.reserved_bytes >= (5u << 20));
    myl_native_heap_release(&first, large);
    assert(((unsigned char *)large)[0] == 0); /* retained until destroy */
    myl_native_heap_destroy(&first);
    assert(!myl_maxperf_arena_get_report(&first, &report));
    exercise(&second); /* independent heap remains live */
    myl_native_heap_destroy(&second);
    myl_native_heap_init(&first, SIZE_MAX); /* same address may be reused */
    exercise(&first);
    assert(myl_maxperf_arena_get_report(&first, &report));
    assert(report.allocations == 5 && report.collections == 0);
    myl_native_heap_destroy(&first);
    return 0;
}
