// tagged_stack ladder. Re-implements the `tagged_stack` case of benchmarks/runtime/ports/main.my
// (CONTRACT.md "tagged_stack"):
//   untimed: opcode[j] = (j + seed) % 4; stack = [Int(seed), Bool(False)]; cursor = 0
//   repeat ITERATIONS times (this is the timed loop; one iteration = one "step"):
//       popped = stack.pop(); base = as_integer(stack[0]); op = opcode[cursor]
//       delta  = Bool: 3/1 (op 0, by value), 7, 11, 13 for op 1, 2, else; Int n: n % 5, 7, 11, 13
//       new_base = (base + delta + op + 1) % 1000003
//       stack[0] = Int(new_base)
//       stack.push(Bool(new_base % 2 == 0) if op in (0, 2) else Int(new_base % 97))
//       cursor = (cursor + 1) % size
//   untimed: checksum = as_integer(stack[0]) * 101 + (1/0 for a Bool top, or the Int)
// Usage: tagged_stack VERSION SIZE ITERATIONS SEED [OPCODEFILE for versions >= 30]
// Prints "checksum elapsed_ns" (elapsed covers the step loop only, like the benchmark).
#include "common.h"
#include <emmintrin.h>

/* mylang's list[Value] where Value = union {integer: int, boolean: bool}: 16-byte elements
 * {tag (0 = integer, 1 = boolean), payload}, header {len, cap, gen, elem, data} behind the
 * RC object header {refcount, flags} (src/native_collections.h; offsets seen in the B0
 * disassembly: refcount at -0x20, flags at -0x10, len at 0, cap at 8, gen at 0x10, data at 0x20). */
typedef struct { uint32_t tag, pad; int64_t payload; } value_t;
typedef struct { int64_t len, cap, gen; const void *elem; value_t *data; } vlist;
typedef struct { uint64_t refcount, flags; vlist list; } vobject;
typedef struct { void *dead_head; const void *plain_word; } rc_state;
typedef struct { rc_state *rc; } heap_t;
static rc_state g_rc = { NULL, (const void *)&g_rc };
static heap_t g_heap = { &g_rc };
#define UNIQUE_MASK 0x6000000000000002ULL

/* myl_rc_list_plain_pop_ready: a call per pop (src/native_collections.c:1370). */
__attribute__((noinline)) static int plain_pop_ready(heap_t *h, const vlist *l) {
    if (!h || !h->rc || h->rc->dead_head || !l || !l->elem) return 0;
    return 1;
}
__attribute__((noinline)) static int plain_ready(heap_t *h, const vlist *l) {
    if (!h || !h->rc || h->rc->dead_head || !l || !l->elem) return 0;
    return 1;
}
__attribute__((noinline)) static void rc_unique_local(vobject *o) { (void)o; trap("shared stack"); }


/* How mylang materialises a 16-byte union value (visible in the B0 disassembly): the fields are
 * written into a stack temporary with narrow stores, then the temporary is copied with one 16-byte
 * vector load and store. The 16-byte load spans two earlier stores, so the CPU cannot forward them:
 * a store-forwarding stall of roughly a dozen cycles that sits on the loop-carried chain.
 * The empty asm with the temporary's address keeps the compiler from turning it into registers. */
#define ESCAPE(p) __asm__ volatile("" : : "r"(p) : "memory")
static inline void store_value_via_temp(value_t *dst, uint32_t tag, int64_t payload) {
    value_t tmp;
    tmp.tag = tag; tmp.pad = 0; tmp.payload = payload;
    ESCAPE(&tmp);
    _mm_storeu_si128((__m128i *)dst, _mm_loadu_si128((const __m128i *)&tmp));
}
static inline value_t load_value_via_vector(const value_t *src) {
    value_t out;
    _mm_storeu_si128((__m128i *)&out, _mm_loadu_si128((const __m128i *)src));
    ESCAPE(&out);
    return out;
}

static vobject *new_stack(void) {
    vobject *o = calloc(1, sizeof *o);
    o->refcount = 1;
    o->list.cap = 4;
    o->list.elem = (const void *)&g_rc;
    o->list.data = calloc(4, sizeof(value_t));
    return o;
}

/* ---- v1: today's semantics. The stack is a heap list; every pop checks uniqueness and calls
 * plain_pop_ready, copies the 16-byte element out and clears the slot, bumps len and gen;
 * stack[0] is bounds-checked and tag-checked; opcode[cursor] is bounds-checked; the match on the
 * popped tag and the opcode are branches, each remainder is a signed magic-number division
 * with floor fix-ups; additions are checked; the write to stack[0] and the push re-check
 * uniqueness, capacity and plain_ready; cursor wraps with a 64-bit idiv. */
__attribute__((noinline)) static int64_t v1(heap_t *volatile hslot, vobject *volatile slot, const int64_t *opcodes,
                                            int64_t size, int64_t iterations, int64_t seed, int64_t *top_out) {
    heap_t *h = hslot;
    vobject *so = slot;
    vlist *s = &so->list;
    int64_t cursor = 0;
    (void)seed;
    for (int64_t step = 0; step < iterations; step++) {
        /* pop */
        if ((so->flags & UNIQUE_MASK) == 0 && so->refcount < 2) {} else rc_unique_local(so);
        int64_t len = s->len;
        if (len == 0 || s->gen == INT64_MAX) trap("pop");
        if (!plain_pop_ready(h, s)) trap("pop");
        value_t popped = load_value_via_vector(&s->data[len - 1]);
        memset(&s->data[len - 1], 0, sizeof(value_t));
        s->len = len - 1;
        s->gen++;
        /* base = as_integer(stack[0]) */
        if ((uint64_t)0 >= (uint64_t)s->len) trap("index");
        value_t first = load_value_via_vector(&s->data[0]);
        int64_t base = first.tag == 0 ? first.payload : 0;
        /* op = opcodes[cursor] */
        if ((uint64_t)cursor >= (uint64_t)size) trap("index");
        int64_t op = opcodes[cursor];
        int64_t delta;
        if (popped.tag == 1) {
            if (op == 0) delta = popped.payload ? 3 : 1;
            else if (op == 1) delta = 7;
            else if (op == 2) delta = 11;
            else delta = 13;
        } else {
            int64_t n = popped.payload;
            if (op == 0) delta = floormod(n, 5);
            else if (op == 1) delta = floormod(n, 7);
            else if (op == 2) delta = floormod(n, 11);
            else delta = floormod(n, 13);
        }
        int64_t t;
        if (__builtin_add_overflow(base, delta, &t) || __builtin_add_overflow(t, op, &t) ||
            __builtin_add_overflow(t, 1, &t)) trap("overflow");
        int64_t new_base = floormod(t, 1000003);
        /* stack[0] = Value.integer(new_base) */
        if ((so->flags & UNIQUE_MASK) == 0 && so->refcount < 2) {} else rc_unique_local(so);
        if ((uint64_t)0 >= (uint64_t)s->len) trap("index");
        store_value_via_temp(&s->data[0], 0, new_base);
        /* push */
        uint32_t ptag;
        int64_t ppay;
        if (op == 0 || op == 2) { ptag = 1; ppay = floormod(new_base, 2) == 0; }
        else { ptag = 0; ppay = floormod(new_base, 97); }
        if (s->len >= s->cap || s->gen == INT64_MAX) trap("grow");
        if (!plain_ready(h, s)) trap("push");
        store_value_via_temp(&s->data[s->len], ptag, ppay);
        s->len++;
        s->gen++;
        /* cursor = (cursor + 1) % size */
        int64_t c1;
        if (__builtin_add_overflow(cursor, 1, &c1)) trap("overflow");
        cursor = floormod(c1, size);
    }
    value_t top = s->data[1];
    *top_out = top.tag == 1 ? top.payload : top.payload;
    return s->data[0].tag == 0 ? s->data[0].payload : 0;
}

/* Result assembly shared by all versions (untimed): base * 101 + top. */
static int64_t finish(int64_t base, int64_t top) { return base * 101 + top; }

/* ---- v2: + value semantics: the list is a fresh local that nothing else can see, so there is
 * no RC uniqueness test, no ready call, no generation counter, and the header is two registers
 * (len, data). Elements still live in memory as 16-byte tagged values, with their bounds and tag
 * checks, and the same arithmetic as v1. */
__attribute__((noinline)) static int64_t v2(const int64_t *opcodes, int64_t size, int64_t iterations, int64_t seed,
                                            int64_t *top_out) {
    value_t data[4] = {{0, 0, seed}, {1, 0, 0}};
    int64_t len = 2, cursor = 0;
    int bad = 0;
    for (int64_t step = 0; step < iterations; step++) {
        if (len == 0) trap("pop");
        value_t popped = load_value_via_vector(&data[--len]);
        if (0 >= len) trap("index");
        value_t first = load_value_via_vector(&data[0]);
        int64_t base = first.tag == 0 ? first.payload : 0;
        if ((uint64_t)cursor >= (uint64_t)size) trap("index");
        int64_t op = opcodes[cursor];
        int64_t delta;
        if (popped.tag == 1) {
            if (op == 0) delta = popped.payload ? 3 : 1;
            else if (op == 1) delta = 7;
            else if (op == 2) delta = 11;
            else delta = 13;
        } else {
            int64_t n = popped.payload;
            if (op == 0) delta = floormod(n, 5);
            else if (op == 1) delta = floormod(n, 7);
            else if (op == 2) delta = floormod(n, 11);
            else delta = floormod(n, 13);
        }
        int64_t t;
        bad |= __builtin_add_overflow(base, delta, &t);
        bad |= __builtin_add_overflow(t, op, &t);
        bad |= __builtin_add_overflow(t, 1, &t);
        int64_t new_base = floormod(t, 1000003);
        store_value_via_temp(&data[0], 0, new_base);
        uint32_t ptag = 0;
        int64_t ppay;
        if (op == 0 || op == 2) { ptag = 1; ppay = floormod(new_base, 2) == 0; }
        else ppay = floormod(new_base, 97);
        if (len >= 4) trap("grow");
        store_value_via_temp(&data[len++], ptag, ppay);
        int64_t c1;
        bad |= __builtin_add_overflow(cursor, 1, &c1);
        cursor = floormod(c1, size);
        if (bad) trap("overflow");
    }
    *top_out = data[1].payload;
    return data[0].payload;
}

/* ---- v8: + values built in place: the tag and payload are written straight into their list slot
 * and read back as two scalars (no stack temporary, no 16-byte vector copy), so the loop-carried
 * chain has only same-width store-to-load forwarding. Everything else as v2. */
__attribute__((noinline)) static int64_t v8(const int64_t *opcodes, int64_t size, int64_t iterations, int64_t seed,
                                            int64_t *top_out) {
    value_t data[4] = {{0, 0, seed}, {1, 0, 0}};
    int64_t len = 2, cursor = 0;
    int bad = 0;
    for (int64_t step = 0; step < iterations; step++) {
        if (len == 0) trap("pop");
        --len;
        uint32_t ptag = data[len].tag;
        int64_t ppay = data[len].payload;
        if (0 >= len) trap("index");
        int64_t base = data[0].tag == 0 ? data[0].payload : 0;
        if ((uint64_t)cursor >= (uint64_t)size) trap("index");
        int64_t op = opcodes[cursor];
        int64_t delta;
        if (ptag == 1) {
            if (op == 0) delta = ppay ? 3 : 1;
            else if (op == 1) delta = 7;
            else if (op == 2) delta = 11;
            else delta = 13;
        } else {
            if (op == 0) delta = floormod(ppay, 5);
            else if (op == 1) delta = floormod(ppay, 7);
            else if (op == 2) delta = floormod(ppay, 11);
            else delta = floormod(ppay, 13);
        }
        int64_t t;
        bad |= __builtin_add_overflow(base, delta, &t);
        bad |= __builtin_add_overflow(t, op, &t);
        bad |= __builtin_add_overflow(t, 1, &t);
        int64_t new_base = floormod(t, 1000003);
        data[0].tag = 0;
        data[0].payload = new_base;
        if (len >= 4) trap("grow");
        if (op == 0 || op == 2) { data[len].tag = 1; data[len].payload = floormod(new_base, 2) == 0; }
        else { data[len].tag = 0; data[len].payload = floormod(new_base, 97); }
        len++;
        int64_t c1;
        bad |= __builtin_add_overflow(cursor, 1, &c1);
        cursor = floormod(c1, size);
        if (bad) trap("overflow");
    }
    *top_out = data[1].payload;
    return data[0].payload;
}

/* ---- v3: + the stack is scalar-replaced: its length is 2 at the top of every iteration and 1
 * between the pop and the push (a balanced local list with a length invariant), so the elements
 * are four scalars (base, top tag, top payload) and no memory and no length are touched. The
 * checks that referred to the length disappear with it. Arithmetic is still checked i64 with
 * floor semantics; opcode[cursor] is still bounds-checked. */
__attribute__((noinline)) static int64_t v3(const int64_t *opcodes, int64_t size, int64_t iterations, int64_t seed,
                                            int64_t *top_out) {
    int64_t base = seed, top = 0, top_is_bool = 1, cursor = 0;
    int bad = 0;
    for (int64_t step = 0; step < iterations; step++) {
        if ((uint64_t)cursor >= (uint64_t)size) trap("index");
        int64_t op = opcodes[cursor];
        int64_t delta;
        if (top_is_bool) {
            if (op == 0) delta = top ? 3 : 1;
            else if (op == 1) delta = 7;
            else if (op == 2) delta = 11;
            else delta = 13;
        } else {
            if (op == 0) delta = floormod(top, 5);
            else if (op == 1) delta = floormod(top, 7);
            else if (op == 2) delta = floormod(top, 11);
            else delta = floormod(top, 13);
        }
        int64_t t;
        bad |= __builtin_add_overflow(base, delta, &t);
        bad |= __builtin_add_overflow(t, op, &t);
        bad |= __builtin_add_overflow(t, 1, &t);
        base = floormod(t, 1000003);
        if (op == 0 || op == 2) { top_is_bool = 1; top = floormod(base, 2) == 0; }
        else { top_is_bool = 0; top = floormod(base, 97); }
        int64_t c1;
        bad |= __builtin_add_overflow(cursor, 1, &c1);
        cursor = floormod(c1, size);
        if (bad) trap("overflow");
    }
    *top_out = top;
    return base;
}

/* ---- v4: + range facts: seed in [1, 1e6] (checked on entry), opcode in [0, 4) (a `% 4`
 * comprehension), cursor in [0, size): every value stays non-negative, so floor == unsigned
 * remainder; overflow checks are provably dead (base < 1000003, delta <= 13); the index is in
 * bounds by induction. Still the same remainders by constants, `% 1000003` and an idiv for the
 * cursor. */
__attribute__((noinline)) static int64_t v4(const int64_t *opcodes, int64_t size, int64_t iterations, int64_t seed,
                                            int64_t *top_out) {
    uint64_t base = (uint64_t)seed, top = 0, cursor = 0;
    int top_is_bool = 1;
    for (int64_t step = 0; step < iterations; step++) {
        uint64_t op = (uint64_t)opcodes[cursor];
        __builtin_assume(op < 4); /* fact: list built by `(j + seed) % 4` */
        uint64_t delta;
        if (top_is_bool) {
            if (op == 0) delta = top ? 3 : 1;
            else if (op == 1) delta = 7;
            else if (op == 2) delta = 11;
            else delta = 13;
        } else {
            if (op == 0) delta = top % 5;
            else if (op == 1) delta = top % 7;
            else if (op == 2) delta = top % 11;
            else delta = top % 13;
        }
        base = (base + delta + op + 1) % 1000003;
        if (op == 0 || op == 2) { top_is_bool = 1; top = (base % 2) == 0; }
        else { top_is_bool = 0; top = base % 97; }
        cursor = (cursor + 1) % (uint64_t)size;
    }
    *top_out = (int64_t)top;
    return (int64_t)base;
}

/* ---- v5: + `% 1000003` by a conditional subtract: base < 1000003 and delta + op + 1 <= 17, so
 * the sum is below twice the modulus (a range fact about a loop-carried value, which holds by
 * induction), and the cursor wraps by compare-and-reset (an induction variable modulo size). */
__attribute__((noinline)) static int64_t v5(const int64_t *opcodes, int64_t size, int64_t iterations, int64_t seed,
                                            int64_t *top_out) {
    uint64_t base = (uint64_t)seed, top = 0, cursor = 0, n = (uint64_t)size;
    int top_is_bool = 1;
    for (int64_t step = 0; step < iterations; step++) {
        uint64_t op = (uint64_t)opcodes[cursor];
        __builtin_assume(op < 4); /* fact: list built by `(j + seed) % 4` */
        uint64_t delta;
        if (top_is_bool) {
            if (op == 0) delta = top ? 3 : 1;
            else if (op == 1) delta = 7;
            else if (op == 2) delta = 11;
            else delta = 13;
        } else {
            if (op == 0) delta = top % 5;
            else if (op == 1) delta = top % 7;
            else if (op == 2) delta = top % 11;
            else delta = top % 13;
        }
        uint64_t sum = base + delta + op + 1;
        base = sum >= 1000003 ? sum - 1000003 : sum;
        if (op == 0 || op == 2) { top_is_bool = 1; top = (base & 1) == 0; }
        else { top_is_bool = 0; top = base % 97; }
        cursor++;
        cursor = cursor == n ? 0 : cursor;
    }
    *top_out = (int64_t)top;
    return (int64_t)base;
}

/* ---- v6: + residue tracking: the only use of a popped Int is `top % k` where top is the
 * previous `base % 97`, so keep r = base mod 97 beside base (r' = r + c, reduced by one
 * conditional subtract; corrected only when base wraps at 1000003, 1000003 mod 97 = 30). The
 * critical chain is then r -> delta -> r' (no multiply-based remainder at all); base only adds. */
__attribute__((noinline)) static int64_t v6(const int64_t *opcodes, int64_t size, int64_t iterations, int64_t seed,
                                            int64_t *top_out) {
    uint64_t base = (uint64_t)seed, r = (uint64_t)seed % 97, tb = 0, cursor = 0, n = (uint64_t)size;
    int top_is_bool = 1;
    for (int64_t step = 0; step < iterations; step++) {
        uint64_t op = (uint64_t)opcodes[cursor];
        __builtin_assume(op < 4); /* fact: list built by `(j + seed) % 4` */
        uint64_t delta;
        if (top_is_bool) {
            if (op == 0) delta = tb ? 3 : 1;
            else if (op == 1) delta = 7;
            else if (op == 2) delta = 11;
            else delta = 13;
        } else {
            if (op == 0) delta = r % 5;
            else if (op == 1) delta = r % 7;
            else if (op == 2) delta = r % 11;
            else delta = r % 13;
        }
        uint64_t c = delta + op + 1;
        uint64_t sum = base + c;
        uint64_t rr = r + c;
        rr = rr >= 97 ? rr - 97 : rr;
        if (__builtin_expect(sum >= 1000003, 0)) {
            sum -= 1000003;
            rr = rr + 67; /* -30 mod 97 */
            rr = rr >= 97 ? rr - 97 : rr;
        }
        base = sum;
        r = rr;
        top_is_bool = (op == 0 || op == 2);
        tb = (base & 1) == 0;
        cursor++;
        cursor = cursor == n ? 0 : cursor;
    }
    *top_out = top_is_bool ? (int64_t)tb : (int64_t)r;
    return (int64_t)base;
}

/* ---- v7: v6 with the remainders by k <= 13 of r < 97 done by a table lookup of the
 * (op, r) pair (L1-resident, built once) instead of a multiply sequence. */
__attribute__((noinline)) static int64_t v7(const int64_t *opcodes, int64_t size, int64_t iterations, int64_t seed,
                                            int64_t *top_out) {
    static const uint8_t K[4] = {5, 7, 11, 13};
    uint8_t lut[4][97];
    for (int o = 0; o < 4; o++) for (int x = 0; x < 97; x++) lut[o][x] = (uint8_t)(x % K[o]);
    uint64_t base = (uint64_t)seed, r = (uint64_t)seed % 97, tb = 0, cursor = 0, n = (uint64_t)size;
    int top_is_bool = 1;
    for (int64_t step = 0; step < iterations; step++) {
        uint64_t op = (uint64_t)opcodes[cursor];
        __builtin_assume(op < 4); /* fact: list built by `(j + seed) % 4` */
        uint64_t delta;
        if (top_is_bool) {
            static const uint8_t boolean_delta[4] = {1, 7, 11, 13};
            delta = (op == 0 && tb) ? 3 : boolean_delta[op];
        } else {
            delta = lut[op][r];
        }
        uint64_t c = delta + op + 1;
        uint64_t sum = base + c;
        uint64_t rr = r + c;
        rr = rr >= 97 ? rr - 97 : rr;
        if (__builtin_expect(sum >= 1000003, 0)) {
            sum -= 1000003;
            rr = rr + 67;
            rr = rr >= 97 ? rr - 97 : rr;
        }
        base = sum;
        r = rr;
        top_is_bool = (op == 0 || op == 2);
        tb = (base & 1) == 0;
        cursor++;
        cursor = cursor == n ? 0 : cursor;
    }
    *top_out = top_is_bool ? (int64_t)tb : (int64_t)r;
    return (int64_t)base;
}

/* ======================= holdout: the opcodes come from a file ====================== */

/* v30: the best version without range facts on the opcodes (their content is unknown): v3's
 * scalar-replaced stack with sticky checks hoisted out of the dependent chain and the cursor
 * as a compare-and-reset induction; floor remainders and the generic `else` dispatch remain.
 * An opcode outside 0..3 behaves as `else` (13) in the delta, like the mylang source. */
__attribute__((noinline)) static int64_t v30(const int64_t *opcodes, int64_t size, int64_t iterations, int64_t seed,
                                             int64_t *top_out) {
    int64_t base = seed, top = 0, top_is_bool = 1, cursor = 0;
    int bad = 0;
    for (int64_t step = 0; step < iterations; step++) {
        int64_t op = opcodes[cursor];
        int64_t delta;
        if (top_is_bool) {
            if (op == 0) delta = top ? 3 : 1;
            else if (op == 1) delta = 7;
            else if (op == 2) delta = 11;
            else delta = 13;
        } else {
            if (op == 0) delta = floormod(top, 5);
            else if (op == 1) delta = floormod(top, 7);
            else if (op == 2) delta = floormod(top, 11);
            else delta = floormod(top, 13);
        }
        int64_t t;
        bad |= __builtin_add_overflow(base, delta, &t);
        bad |= __builtin_add_overflow(t, op, &t);
        bad |= __builtin_add_overflow(t, 1, &t);
        base = floormod(t, 1000003);
        if (op == 0 || op == 2) { top_is_bool = 1; top = floormod(base, 2) == 0; }
        else { top_is_bool = 0; top = floormod(base, 97); }
        cursor++;
        cursor = cursor == size ? 0 : cursor;
    }
    if (bad) trap("overflow");
    *top_out = top;
    return base;
}

/* v31: a runtime guard over the immutable opcode list (one pass, before the loop: all in
 * [0, 4)) selects v7's fast path; any other content takes v30. */
__attribute__((noinline)) static int64_t v31(const int64_t *opcodes, int64_t size, int64_t iterations, int64_t seed,
                                             int64_t *top_out) {
    if (seed < 1 || seed > 1000000) return v30(opcodes, size, iterations, seed, top_out);
    for (int64_t j = 0; j < size; j++)
        if ((uint64_t)opcodes[j] >= 4) return v30(opcodes, size, iterations, seed, top_out);
    return v7(opcodes, size, iterations, seed, top_out);
}

/* ================================== main ================================== */
static int64_t *read_file(const char *path, int64_t n) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror("fopen"); exit(2); }
    int64_t *d = malloc(sizeof(int64_t) * (size_t)n);
    if (fread(d, 8, (size_t)n, f) != (size_t)n) { fprintf(stderr, "short data file\n"); exit(2); }
    fclose(f);
    return d;
}
int main(int argc, char **argv) {
    if (argc == 5 && !strcmp(argv[1], "gen")) { /* gen SIZE SEED PATH: opcode[j] = (j + seed) % 4 */
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]);
        FILE *f = fopen(argv[4], "wb");
        for (int64_t j = 0; j < size; j++) { int64_t v = (j + seed) % 4; fwrite(&v, 8, 1, f); }
        fclose(f);
        return 0;
    }
    if (argc == 6 && !strcmp(argv[1], "genwide")) { /* genwide SIZE SEED MAX PATH: arbitrary opcodes in [0, MAX] */
        int64_t size = atoll(argv[2]), seed = atoll(argv[3]), max = atoll(argv[4]);
        FILE *f = fopen(argv[5], "wb");
        uint64_t s = (uint64_t)seed * 6364136223846793005ULL + 1442695040888963407ULL;
        for (int64_t j = 0; j < size; j++) {
            s = s * 6364136223846793005ULL + 1442695040888963407ULL;
            int64_t v = (int64_t)((s >> 33) % (uint64_t)(max + 1));
            fwrite(&v, 8, 1, f);
        }
        fclose(f);
        return 0;
    }
    if (argc < 5) return 2;
    int which = atoi(argv[1]);
    int64_t size = atoll(argv[2]), iterations = atoll(argv[3]), seed = atoll(argv[4]);
    int64_t *opcodes;
    if (argc == 6) opcodes = read_file(argv[5], size);
    else {
        if (which >= 30) return 2;
        opcodes = malloc(sizeof(int64_t) * (size_t)size);
        for (int64_t j = 0; j < size; j++) opcodes[j] = (j + seed) % 4;
    }
    vobject *so = new_stack();
    so->list.data[0] = (value_t){0, 0, seed};
    so->list.data[1] = (value_t){1, 0, 0};
    so->list.len = 2;
    vobject *volatile sslot = so;
    heap_t *volatile hslot = &g_heap;
    int64_t top = 0, base = 0;
    int64_t start = now_ns();
    switch (which) {
    case 1: case 20: base = v1(hslot, sslot, opcodes, size, iterations, seed, &top); break;
    case 2: base = v2(opcodes, size, iterations, seed, &top); break;
    case 3: base = v3(opcodes, size, iterations, seed, &top); break;
    case 4: base = v4(opcodes, size, iterations, seed, &top); break;
    case 5: base = v5(opcodes, size, iterations, seed, &top); break;
    case 6: base = v6(opcodes, size, iterations, seed, &top); break;
    case 7: base = v7(opcodes, size, iterations, seed, &top); break;
    case 8: base = v8(opcodes, size, iterations, seed, &top); break;
    case 30: base = v30(opcodes, size, iterations, seed, &top); break;
    case 31: base = v31(opcodes, size, iterations, seed, &top); break;
    default: return 2;
    }
    int64_t elapsed = now_ns() - start;
    printf("%lld %lld\n", (long long)finish(base, top), (long long)elapsed);
    return 0;
}
