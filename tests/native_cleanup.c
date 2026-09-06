/* Observe leaf destruction without adding production callback hooks. */
#include "native_memory.h"
#include <assert.h>
static void *watched[8];
static unsigned trace[8];
static size_t trace_count;
static void observe_free(void *pointer) {
    for (unsigned i = 0; i < 8; ++i) {
        if (pointer && pointer == watched[i]) {
            assert(trace_count < 8);
            trace[trace_count++] = i;
            watched[i] = NULL;
        }
    }
    test_free(pointer);
}
#undef free
#define free observe_free
#include "../src/native_providers.h"
#define MYLANG_GUEST_VALUE_BYTES 48
#include "../src/native_runtime.c"
#include "../src/native_resources.c"

static Slot leaf(unsigned id) {
    Aggregate *object = new_object(0, 0);
    watched[id] = object;
    return (Slot){0, object};
}
static void expect_trace(const unsigned *expected, size_t count) {
    assert(trace_count == count);
    for (size_t i = 0; i < count; ++i) assert(trace[i] == expected[i]);
    trace_count = 0;
}
static void expect_failed_cleanup(void) {
    assert(objects == NULL);
    expect_trace((unsigned[]){2, 1, 0}, 3);
}
static void fail_with_owned_values(const char *mode) {
    static const char *paths[] = {"cleanup.my"}, *names[] = {"main"};
    static const size_t positions[] = {1};
    source_paths = paths; function_names = names;
    source_lines = positions; source_columns = positions;
    enter(0, 1, 0, 0, 0, NULL);
    store_local(0, leaf(0)); push_value(leaf(1)); push_value(leaf(2));
    Slot temporary = pop_value();
    assert(atexit(expect_failed_cleanup) == 0);
    if (!strcmp(mode, "trap")) trap("R_TEST");
    if (!strcmp(mode, "push-oom")) {
        while (nv < cv) push(0);
        test_fail_at = test_attempts + 1;
        push_value(temporary);
    } else if (!strcmp(mode, "enter-oom")) {
        /* Locals and argument transfer succeed; reference storage fails. */
        test_fail_at = test_attempts + 2;
        enter(0, 1, 1, 0, 1, NULL);
    } else if (!strcmp(mode, "constructor-oom")) {
        test_fail_at = test_attempts + 2;
        (void)boxed_variant(0, boxed_variant(0, temporary, 1), 1);
    } else {
        assert(!strcmp(mode, "oom"));
        test_fail_at = test_attempts + 1;
        (void)boxed_variant(0, temporary, 1);
    }
    assert(!"expected host failure");
}
int main(int argc, char **argv) {
    if (argc == 2) { fail_with_owned_values(argv[1]); return 91; }
    /* Local slot order is independent of allocation order. Empty moved slots
       must not disturb reverse cleanup; a shared snapshot outlives the frame. */
    enter(0, 4, 0, 0, 0, NULL);
    Slot second = leaf(1), first = leaf(0), last = leaf(2);
    Slot snapshot = copy_value(first);
    store_local(0, first);
    store_local(1, second);
    store_local(3, last);
    leave_frame();
    expect_trace((unsigned[]){2, 1}, 2);
    release_value(snapshot);
    expect_trace((unsigned[]){0}, 1);

    /* Reverse schema order, depth first, regardless of construction order. */
    Slot a = leaf(0), b = leaf(1), c = leaf(2);
    Aggregate *nested = new_object(2, 0);
    nested->fields[0] = c; nested->fields[1] = a;
    Aggregate *outer = new_object(2, 0);
    outer->fields[0] = b; outer->fields[1] = (Slot){0, nested};
    release_value((Slot){0, outer});
    expect_trace((unsigned[]){0, 2, 1}, 3);

    enter(0, 0, 0, 0, 0, NULL);
    push_value(leaf(0)); push_value(leaf(1)); push_value(leaf(2));
    clear_values(0);
    expect_trace((unsigned[]){2, 1, 0}, 3);
    leave_frame();

    /* Destruction must not use the C call stack or allocate a work list. */
    Slot deep = leaf(0);
    for (size_t i = 0; i < 20000; ++i) {
        Aggregate *parent = new_object(1, 0);
        parent->fields[0] = deep; deep = (Slot){0, parent};
    }
    size_t before = test_attempts;
    release_value(deep);
    assert(test_attempts == before);
    expect_trace((unsigned[]){0}, 1);
    assert(objects == NULL);

    /* Temporary acquisition order differs from allocation order. Operand roots
       precede all locals, and an extra temporary reference must not free a
       shared local early. Cleanup itself must allocate nothing. */
    enter(0, 2, 0, 0, 0, NULL);
    store_local(0, leaf(0)); store_local(1, leaf(1));
    push_value(leaf(2)); push_value(leaf(3));
    push_value(leaf(4)); push_value(leaf(5));
    (void)pop_value(); (void)pop_value();
    (void)copy_value(frames[0].locals[0].value);
    before = test_attempts;
    cleanup();
    assert(test_attempts == before && objects == NULL);
    expect_trace((unsigned[]){4, 5, 3, 2, 1, 0}, 6);

    /* Emergency cleanup follows the ownership graph, including a temporary
       nested constructor whose children were allocated in a different order. */
    a = leaf(0); b = leaf(1); c = leaf(2);
    nested = new_object(2, 0);
    nested->fields[0] = c; nested->fields[1] = a;
    outer = new_object(2, 0);
    outer->fields[0] = b; outer->fields[1] = (Slot){0, nested};
    cleanup();
    assert(objects == NULL);
    expect_trace((unsigned[]){0, 2, 1}, 3);
    return 0;
}
