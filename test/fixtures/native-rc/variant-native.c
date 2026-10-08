// spec-case: RC-NATIVE-VARIANT-1
#define _GNU_SOURCE
#include "glue.c"
#include <assert.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

typedef struct { uint32_t tag, pad; void *left, *right; } Choice;
extern int fast_take(myl_native_heap *, void *, void *, void *, unsigned);
extern int fast_take_private(myl_native_heap *, void *, void *, void *, unsigned);
extern void fast_drop(myl_native_heap *, void *);
extern void fast_unloan(myl_native_heap *, void *);
static unsigned takes, drops, unloans, fail_next;
int probe_rcg_take(myl_native_heap *heap, void *dst, void *src, unsigned region) {
    takes++;
    if (fail_next) {
        fail_next = 0;
        myl_rc_record_failure(heap, MYL_RC_REGION_ERROR);
        return 0;
    }
    return CHOICE_SYMBOL_rcg_take(heap, dst, src, region);
}
void probe_rcg_drop(myl_native_heap *heap, void *value) {
    drops++;
    CHOICE_SYMBOL_rcg_drop(heap, value);
}
void probe_rcg_unloan(myl_native_heap *heap, void *value) {
    unloans++;
    CHOICE_SYMBOL_rcg_unloan(heap, value);
}
int myl_qbe_rc_status(void *ctx, unsigned status) {
    assert(status == MYL_RC_REGION_ERROR);
    (*(unsigned *)ctx)++;
    return 0;
}
static Choice raw(unsigned tag) {
    Choice value;
    memset(&value, 0xa5, sizeof value);
    value.tag = tag;
    return value;
}
static void zeroed(const void *value) {
    unsigned char empty[sizeof(Choice)] = {0};
    assert(!memcmp(value, empty, sizeof empty));
}
static myl_rc_object *header(void *value) { return (myl_rc_object *)value - 1; }

/* Even malformed and inactive bytes are copied exactly, never interpreted as
 * pointers. Unknown tags must reach the original helper, not its fast case. */
static void tags(myl_native_heap *heap) {
    unsigned mapped = 0;
    const unsigned admitted[] = {0, 2};
    for (unsigned i = 0; i < 2; i++) {
        Choice source = raw(admitted[i]), expected = source, destination = {0};
        unsigned before = takes;
        assert(fast_take(heap, &mapped, &destination, &source, 0));
        assert(takes == before && !memcmp(&destination, &expected, sizeof source));
        zeroed(&source);
        source = expected;
        assert(fast_take_private(heap, &mapped, &destination, &source, 0));
        assert(takes == before && !memcmp(&destination, &expected, sizeof source));
        zeroed(&source);
        fast_drop(heap, &destination);
        zeroed(&destination);
        destination = expected;
        fast_unloan(heap, &destination);
        zeroed(&destination);
    }
    const unsigned refused[] = {4, UINT32_MAX};
    for (unsigned i = 0; i < 2; i++) {
        Choice source = raw(refused[i]), expected = source, destination = {0};
        unsigned before = takes;
        assert(fast_take(heap, &mapped, &destination, &source, 0));
        assert(takes == before + 1 && !memcmp(&destination, &expected, sizeof source));
        zeroed(&source);
        source = expected;
        assert(fast_take_private(heap, &mapped, &destination, &source, 0));
        assert(takes == before + 2 && !memcmp(&destination, &expected, sizeof source));
        zeroed(&source);
        before = drops;
        fast_drop(heap, &destination);
        assert(drops == before + 1);
        zeroed(&destination);
        destination = expected;
        before = unloans;
        fast_unloan(heap, &destination);
        assert(unloans == before + 1);
        zeroed(&destination);
    }
    assert(!mapped);
}

/* Compare the original helper's same-address and partial-overlap transaction,
 * in both directions, including source bytes outside the destination range. */
static void overlaps(myl_native_heap *heap) {
    const unsigned offsets[] = {0, 8, 16, 24};
    for (unsigned i = 0; i < 4; i++) for (unsigned reverse = 0; reverse < 2; reverse++) {
        _Alignas(8) unsigned char control[64], candidate[64];
        memset(control, 0xa5, sizeof control);
        unsigned src = reverse ? offsets[i] : 0, dst = reverse ? 0 : offsets[i];
        uint32_t tag = 2;
        memcpy(control + src, &tag, sizeof tag);
        memcpy(candidate, control, sizeof control);
        assert(CHOICE_SYMBOL_rcg_take(heap, control + dst, control + src, 0));
        unsigned mapped = 0, before = takes;
        assert(fast_take(heap, &mapped, candidate + dst, candidate + src, 0));
        assert(takes == before + (offsets[i] < sizeof(Choice)));
        assert(!mapped && !memcmp(control, candidate, sizeof control));
    }
}

/* Shared memory proves the checked abort occurs before either value changes.
 * This also rejects UINT32_MAX and confirms the helper's unsigned width. */
static void bad_region(myl_native_heap *heap, unsigned region, int fast) {
    Choice *values = mmap(NULL, 2 * sizeof(Choice), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    assert(values != MAP_FAILED);
    values[0] = raw(2);
    memset(&values[1], 0, sizeof values[1]);
    Choice original[2];
    memcpy(original, values, sizeof original);
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        struct rlimit core = {0, 0};
        assert(!setrlimit(RLIMIT_CORE, &core));
        assert(freopen("/dev/null", "w", stderr));
        unsigned mapped = 0;
        if (fast == 1) fast_take(heap, &mapped, &values[1], &values[0], region);
        else if (fast == 2) fast_take_private(heap, &mapped, &values[1], &values[0], region);
        else CHOICE_SYMBOL_rcg_take(heap, &values[1], &values[0], region);
        _exit(0);
    }
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFSIGNALED(status) && WTERMSIG(status) == SIGABRT);
    assert(!memcmp(original, values, sizeof original));
    assert(!munmap(values, sizeof original));
}
static void regions(myl_native_heap *heap) {
    bad_region(heap, 1, 0);
    bad_region(heap, 1, 1);
    bad_region(heap, 1, 2);
    bad_region(heap, UINT32_MAX, 0);
    bad_region(heap, UINT32_MAX, 1);
    bad_region(heap, UINT32_MAX, 2);
    assert(myl_native_region_begin(heap));
    Choice value = raw(0), output = {0};
    unsigned mapped = 0, before = takes;
    assert(fast_take(heap, &mapped, &output, &value, 1));
    assert(takes == before && !mapped);
    zeroed(&value);
    value = raw(2);
    assert(fast_take_private(heap, &mapped, &output, &value, 1));
    assert(takes == before && !mapped);
    zeroed(&value);
    fast_drop(heap, &output);
    myl_native_region_end(heap);
}

static void fallback_failure(myl_native_heap *heap) {
    Choice value = raw(UINT32_MAX), original = value, output = {0};
    unsigned mapped = 0, before = takes;
    fail_next = 1;
    assert(!fast_take(heap, &mapped, &output, &value, 0));
    assert(takes == before + 1 && mapped == 1 && !memcmp(&value, &original, sizeof value));
    zeroed(&output);
    assert(myl_rc_take_failure(heap) == MYL_RC_OK);
}

/* Queue a real death through the runtime's active-drain path, then return to
 * an idle boundary. Generated edge-free operations leave it pending; generic
 * native take drains it. No invalid pointer or fabricated queue is involved. */
static void pending(myl_native_heap *heap) {
    void *payload = myl_rc_storage_bytes(heap, 8, 0);
    assert(payload && !heap->rc->dead.head);
    heap->rc->dead.active = 1;
    myl_rc_edge_release(heap, payload);
    heap->rc->dead.active = 0;
    myl_rc_object *death = heap->rc->dead.head;
    assert(death == header(payload));
    Choice value = raw(2), output = {0};
    CHOICE_SYMBOL_rcg_drop(heap, &value);
    assert(heap->rc->dead.head == death);
    value = raw(0);
    fast_drop(heap, &value);
    assert(heap->rc->dead.head == death);
    value = raw(0);
    CHOICE_SYMBOL_rcg_unloan(heap, &value);
    assert(heap->rc->dead.head == death);
    value = raw(2);
    fast_unloan(heap, &value);
    assert(heap->rc->dead.head == death);
    value = raw(0);
    assert(CHOICE_SYMBOL_rcg_take(heap, &output, &value, 0));
    assert(heap->rc->dead.head == death);
    value = raw(2);
    unsigned mapped = 0;
    assert(fast_take(heap, &mapped, &output, &value, 0));
    assert(heap->rc->dead.head == death && !mapped);
    value = raw(2);
    assert(fast_take_private(heap, &mapped, &output, &value, 0));
    assert(heap->rc->dead.head == death && !mapped);
    value = raw(0);
    assert(myl_rc_native_take(heap, &CHOICE_SYMBOL, &output, &value, 0));
    assert(!heap->rc->dead.head);
}

static void managed(myl_native_heap *heap) {
    void *leaf = myl_rc_storage_bytes(heap, 8, 0);
    assert(leaf);
    assert(myl_rc_owner_acquire(heap, leaf) == MYL_RC_OK);
    Choice value = {.tag = 1, .left = leaf, .right = leaf}, output = {0};
    unsigned mapped = 0, before = takes;
    assert(fast_take_private(heap, &mapped, &output, &value, 0));
    assert(takes == before + 1 && header(leaf)->owners == 2 && !header(leaf)->holds);
    zeroed(&value);
    assert(CHOICE_SYMBOL_rcg_loan(heap, &value, &output));
    assert(header(leaf)->holds == 2);
    before = unloans;
    fast_unloan(heap, &value);
    assert(unloans == before + 1 && !header(leaf)->holds && header(leaf)->owners == 2);
    before = drops;
    fast_drop(heap, &output);
    assert(drops == before + 1);
    zeroed(&output);

}

int main(void) {
    myl_native_heap heap = {.limit = 64u << 20};
    assert(myl_rc_storage_init(&heap) == MYL_RC_OK);
    assert(myl_rc_module_register_image(&heap, &myl_rc_generated_module, &myl_rc_generated_image) == MYL_RC_OK);
    assert(sizeof(Choice) == CHOICE_SYMBOL.size);
    tags(&heap);
    overlaps(&heap);
    regions(&heap);
    fallback_failure(&heap);
    pending(&heap);
    managed(&heap);
    myl_native_heap_destroy(&heap);
    puts("variant native probes passed");
    return 0;
}
