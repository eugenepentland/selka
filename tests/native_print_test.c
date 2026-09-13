#include "native_print.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const myl_native_type pointer={.size=sizeof(void *),.alignment=_Alignof(void *),.kind=MYL_NATIVE_POINTER};
static const myl_native_type number={.size=8,.alignment=8,.kind=MYL_NATIVE_PLAIN};
static MylPrint out;
static void reset(void) { out.length = 0; out.failed = 0; out.unprintable = 0; }
static void matches(const char *expected) {
    assert(!out.failed && !out.unprintable);
    assert(out.length == strlen(expected));
    assert(!out.length || !memcmp(out.bytes, expected, out.length));
    reset();
}
static void render_i64(MylPrint *sink, const void *value, unsigned depth) { myl_print_integer(sink, value, depth, 8, 1); }
static void render_text(MylPrint *sink, const void *value, unsigned depth) { myl_print_text(sink, value, depth); }
static void render_bytes(MylPrint *sink, const void *value, unsigned depth) { myl_print_bytes(sink, value, depth); }
static void render_numbers(MylPrint *sink, const void *value, unsigned depth) { myl_print_list(sink, value, depth, render_i64); }
static void render_ladder(MylPrint *sink, const void *value, unsigned depth) { myl_print_list(sink, value, depth, render_ladder); }
static void number_at(MylPrint *sink, double value) { myl_print_float(sink, &value, 0); }
int main(void) {
    myl_native_heap heap;
    myl_native_heap_init(&heap, 1 << 22);
    reset();
    /* Integers keep their declared width and signedness. */
    int64_t value = -9223372036854775807LL - 1;
    myl_print_integer(&out, &value, 0, 8, 1);
    matches("-9223372036854775808");
    uint64_t wide = 18446744073709551615ULL;
    myl_print_integer(&out, &wide, 0, 8, 0);
    matches("18446744073709551615");
    unsigned char narrow = 0x80;
    myl_print_integer(&out, &narrow, 0, 1, 1);
    matches("-128");
    myl_print_integer(&out, &narrow, 0, 1, 0);
    matches("128");
    unsigned char flag = 1;
    myl_print_bool(&out, &flag, 0);
    matches("True");
    myl_print_unit(&out, NULL, 0);
    matches("None");
    /* Floats keep the shortest round-tripping decimal spelling. */
    number_at(&out, 0.0); matches("0.0");
    number_at(&out, -0.0); matches("-0.0");
    number_at(&out, 1.0); matches("1.0");
    number_at(&out, 0.1); matches("0.1");
    number_at(&out, 2.5); matches("2.5");
    number_at(&out, 1e20); matches("100000000000000000000.0");
    number_at(&out, 1.5e-7); matches("0.00000015");
    number_at(&out, 3.0 / 7.0); matches("0.42857142857142855");
    number_at(&out, 1.0 / 0.0); matches("inf");
    number_at(&out, -1.0 / 0.0); matches("-inf");
    number_at(&out, 0.0 / 0.0); matches("nan");
    /* A value the VM's formatting frame cannot hold is unprintable on both. */
    double huge = 1e100;
    myl_print_float(&out, &huge, 0);
    assert(out.unprintable);
    reset();
    /* Text prints raw at the top level and repr-quoted inside a container. */
    myl_native_text *text = myl_native_text_from_utf8(&heap, (const unsigned char *)"h\xc3\xa9'\\\n", 6);
    assert(text);
    render_text(&out, &text, 0);
    matches("h\xc3\xa9'\\\n");
    render_text(&out, &text, 1);
    matches("'h\xc3\xa9\\'\\\\\\n'");
    unsigned char octets[] = {0, 0x1f, ' ', '~', 0x7f, 0xff, '\'', '\\', '\t'};
    /* Byte strings are one-byte-stride lists; build one directly. */
    static const myl_native_type octet_type = {.size = 1, .alignment = 1, .kind = MYL_NATIVE_PLAIN};
    myl_native_list *view = myl_native_list_new(&heap, &octet_type, sizeof octets);
    assert(view);
    memcpy(view->storage, octets, sizeof octets);
    view->length = sizeof octets;
    render_bytes(&out, &view, 0);
    matches("b'\\x00\\x1f ~\\x7f\\xff\\'\\\\\\t'");
    /* Lists and the depth cap. */
    myl_native_list *numbers = myl_native_list_new(&heap, &number, 0);
    assert(numbers);
    for (int64_t i = 1; i <= 3; ++i) assert(myl_native_list_append(&heap, numbers, &i));
    render_numbers(&out, &numbers, 0);
    matches("[1, 2, 3]");
    myl_native_list *ladder = myl_native_list_new(&heap, &pointer, 0);
    assert(ladder);
    assert(myl_native_list_append(&heap, ladder, &ladder));
    render_ladder(&out, &ladder, 0);
    /* A cyclic graph terminates at the depth cap rather than recurring forever. */
    assert(!out.failed && out.length == 2 * MYL_PRINT_MAX_DEPTH + 5);
    assert(!memcmp(out.bytes + MYL_PRINT_MAX_DEPTH + 1, "...", 3));
    reset();
    free(out.bytes);
    myl_native_heap_destroy(&heap);
    puts("native print tests passed");
    return 0;
}
