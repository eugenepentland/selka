/* Runtime-only dictionary probe: the hot loop of bench/parity/micro/dict_count
 * (a read, then an overwrite of the same key) against the runtime sources in
 * one directory, so two runtimes' instruction counts can be compared without
 * rebuilding a compiler. `str` keys are 1000 texts "key<i>"; `int` keys are the
 * integers `i * 7919 - 1000`. `pop` removes and reinserts one key per step.
 *
 * usage: dict_bench str|int|pop [iterations]
 * build: zig cc -std=c11 -O2 -fPIC -I RT dict_bench.c RT/native_{heap,arena,dictionary,equal,text,collections,bytes}.c
 */
#include "native_dictionary.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const myl_native_type pointer = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER};
static const myl_native_type text_type = {.size = sizeof(void *), .alignment = _Alignof(void *), .kind = MYL_NATIVE_POINTER, .collection_kind = 2};
static const myl_native_type number = {.size = 8, .alignment = 8, .kind = MYL_NATIVE_PLAIN};
enum { KEYS = 1000 };
int main(int argc, char **argv) {
    const char *mode = argc > 1 ? argv[1] : "str";
    long iterations = argc > 2 ? atol(argv[2]) : 2000000;
    static myl_native_heap heap;
    myl_native_heap_init(&heap, (size_t)1 << 30);
    static myl_native_text *texts[KEYS];
    static myl_native_root roots[KEYS + 1];
    int strings = !strcmp(mode, "str");
    for (int i = 0; i < KEYS && strings; ++i) {
        char buffer[32];
        int length = snprintf(buffer, sizeof buffer, "key%d", i);
        texts[i] = myl_native_text_from_utf8(&heap, (const unsigned char *)buffer, (size_t)length);
        myl_native_root_push(&heap, &roots[i], &texts[i], &pointer);
    }
    myl_native_dictionary *dict = myl_native_dictionary_new(&heap, strings ? &text_type : &number, &number, strings);
    myl_native_root_push(&heap, &roots[KEYS], &dict, &pointer);
    int64_t total = 0;
    for (long i = 0; i < iterations; ++i) {
        size_t at = (size_t)((i * 7919) % KEYS);
        int64_t word = (int64_t)at * 7919 - 1000;
        const void *key = strings ? (const void *)&texts[at] : (const void *)&word;
        int64_t value = 0;
        if (!myl_native_dictionary_read(dict, key, &value)) value = 0;
        value += 1;
        if (!myl_native_dictionary_overwrite(dict, key, &value)) myl_native_dictionary_write(&heap, dict, key, &value);
        if (!strcmp(mode, "pop") && (i & 7) == 7) {
            int64_t out;
            myl_native_dictionary_pop(dict, key, &out);
            myl_native_dictionary_write(&heap, dict, key, &out);
        }
    }
    for (size_t i = 0; i < KEYS; ++i) {
        int64_t word = (int64_t)i * 7919 - 1000, value = 0;
        const void *key = strings ? (const void *)&texts[i] : (const void *)&word;
        if (myl_native_dictionary_read(dict, key, &value)) total += value * (int64_t)(i + 1);
    }
    printf("%lld\n", (long long)total);
    return 0;
}
