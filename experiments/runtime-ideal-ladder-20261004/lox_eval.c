// lox_eval ladder: the dispatch loop of the bytecode executor in
// benchmarks/runtime/expanded/collections/main.my (`execute`). Per batch the VM runs a fixed 38-instruction
// program (a Lox-subset loop: SIZE iterations of `if i % 2 == 0: total = bump(total) else: total = (total + i) % 1000003`)
// with seed + batch, and the batch result is added to the checksum modulo 1000000007. Everything the
// executor does is timed, including creating and releasing its three lists (stack, returns, variables).
// Instruction set: 0 push seed, 1 push size, 2 push arg, 3 push variables[arg], 4 variables[arg] = pop,
// 5 add, 6 mul, 7 mod (floor), 8 less-than, 9 equal (both pop two ints, 8/9 push a bool), 10 pop a bool and
// jump to arg when false, 11 jump, 12 call (push the return address, jump), 13 return, otherwise return pop.
// Usage: lox_eval VERSION SIZE ITERATIONS SEED [PROGRAMFILE]
//   PROGRAMFILE: u64 count, then count * (i64 op, i64 arg); replaces the built-in program.
// Prints "checksum elapsed_ns". Build with -fno-strict-aliasing.
#include "common.h"
#include <emmintrin.h>

typedef struct { int64_t op, arg; } insn_t;

/* the benchmark's program, verbatim from collections/main.my */
static const insn_t PROGRAM[38] = {
    {0, 0}, {4, 0}, {2, 0}, {4, 1}, {3, 1}, {1, 0}, {8, 0}, {10, 29}, {3, 1}, {2, 2}, {7, 0}, {2, 0}, {9, 0}, {10, 18},
    {3, 0}, {12, 31}, {4, 0}, {11, 24}, {3, 0}, {3, 1}, {5, 0}, {2, 1000003}, {7, 0}, {4, 0}, {3, 1}, {2, 1}, {5, 0},
    {4, 1}, {11, 4}, {3, 0}, {14, 0}, {2, 3}, {6, 0}, {2, 7}, {5, 0}, {2, 1000003}, {7, 0}, {13, 0}};
/* a different program for the holdout: total = (total + i*i) % 1000003 for i in range(size) */
static const insn_t PROGRAM_B[24] = {
    {0, 0}, {4, 0}, {2, 0}, {4, 1}, {3, 1}, {1, 0}, {8, 0}, {10, 22}, {3, 0}, {3, 1}, {3, 1}, {6, 0}, {5, 0},
    {2, 1000003}, {7, 0}, {4, 0}, {3, 1}, {2, 1}, {5, 0}, {4, 1}, {11, 4}, {14, 0}, {3, 0}, {14, 0}};

/* ------------------------------------------------------------------------------------------------
 * Representations as in tagged_stack.c: a 16-byte tagged union element, RC list objects with checks and ready
 * calls, 16-byte vector copies that stall store forwarding (see that file for the evidence). */
typedef struct { uint32_t tag, pad; int64_t payload; } value_t;
typedef struct { int64_t len, cap, gen; const void *elem; void *data; } vlist;
typedef struct { uint64_t refcount, flags; vlist list; } vobject;
typedef struct { void *dead_head; const void *plain_word; } rc_state;
typedef struct { rc_state *rc; } heap_t;
static rc_state g_rc = { NULL, (const void *)&g_rc };
static heap_t g_heap = { &g_rc };
#define UNIQUE_MASK 0x6000000000000002ULL
#define ESCAPE(p) __asm__ volatile("" : : "r"(p) : "memory")

__attribute__((noinline)) static int plain_ready(heap_t *h, const vlist *l) {
    if (!h || !h->rc || h->rc->dead_head || !l || !l->elem) return 0;
    return 1;
}
__attribute__((noinline)) static int plain_pop_ready(heap_t *h, const vlist *l) {
    if (!h || !h->rc || h->rc->dead_head || !l || !l->elem) return 0;
    return 1;
}
__attribute__((noinline)) static void rc_unique_local(vobject *o) { (void)o; trap("shared list"); }

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
static vobject *new_list(size_t elem_size, int64_t cap) {
    vobject *o = calloc(1, sizeof *o);
    o->refcount = 1;
    o->list.cap = cap;
    o->list.elem = (const void *)&g_rc;
    o->list.data = cap ? calloc((size_t)cap, elem_size) : NULL;
    return o;
}
static void free_list(vobject *o) { free(o->list.data); free(o); }
static inline void unique_check(vobject *o) {
    if ((o->flags & UNIQUE_MASK) == 0 && o->refcount < 2) {} else rc_unique_local(o);
}
/* growth of a list's storage (doubling from 4) */
__attribute__((noinline)) static void list_grow(vlist *l, size_t elem_size) {
    int64_t cap = l->cap < 4 ? 4 : l->cap * 2;
    l->data = realloc(l->data, (size_t)cap * elem_size);
    l->cap = cap;
}

/* ---- v1: today. Every list operation goes through the RC list protocol: uniqueness test, ready call, header
 * length/generation traffic, bounds checks against the header, 16-byte element copies through stack
 * temporaries. The instruction record is copied out of the program list. The opcode test is an if/elif chain. */
typedef struct { vobject *stack, *returns, *variables, *program; heap_t *h; } vm1;

static inline void s_push(vm1 *m, uint32_t tag, int64_t payload) {
    vobject *so = m->stack;
    vlist *s = &so->list;
    unique_check(so);
    if (s->gen == INT64_MAX) trap("gen");
    if (s->len >= s->cap) list_grow(s, sizeof(value_t));
    if (!plain_ready(m->h, s)) trap("push");
    store_value_via_temp(&((value_t *)s->data)[s->len], tag, payload);
    s->len++;
    s->gen++;
}
static inline value_t s_pop(vm1 *m) {
    vobject *so = m->stack;
    vlist *s = &so->list;
    unique_check(so);
    int64_t len = s->len;
    if (len == 0 || s->gen == INT64_MAX) trap("pop");
    if (!plain_pop_ready(m->h, s)) trap("pop");
    value_t v = load_value_via_vector(&((value_t *)s->data)[len - 1]);
    memset(&((value_t *)s->data)[len - 1], 0, sizeof(value_t));
    s->len = len - 1;
    s->gen++;
    return v;
}
static inline int64_t as_integer(value_t v) { return v.tag == 0 ? v.payload : 0; }
static inline int as_boolean(value_t v) { return v.tag == 1 ? (int)v.payload : 0; }

__attribute__((noinline)) static int64_t exec1(vm1 *m, const insn_t *prog, int64_t program_len, int64_t size, int64_t seed) {
    vlist *vars = &m->variables->list, *ret = &m->returns->list;
    int64_t pc = 0;
    (void)program_len;
    for (;;) {
        if ((uint64_t)pc >= (uint64_t)m->program->list.len) trap("index");
        insn_t ins = prog[pc];
        int64_t npc;
        if (__builtin_add_overflow(pc, 1, &npc)) trap("overflow");
        pc = npc;
        if (ins.op == 0) s_push(m, 0, seed);
        else if (ins.op == 1) s_push(m, 0, size);
        else if (ins.op == 2) s_push(m, 0, ins.arg);
        else if (ins.op == 3) {
            if ((uint64_t)ins.arg >= (uint64_t)vars->len) trap("index");
            s_push(m, 0, ((int64_t *)vars->data)[ins.arg]);
        } else if (ins.op == 4) {
            int64_t v = as_integer(s_pop(m));
            unique_check(m->variables);
            if ((uint64_t)ins.arg >= (uint64_t)vars->len) trap("index");
            ((int64_t *)vars->data)[ins.arg] = v;
        } else if (ins.op >= 5 && ins.op <= 9) {
            int64_t b = as_integer(s_pop(m)), a = as_integer(s_pop(m)), r;
            if (ins.op == 5) { if (__builtin_add_overflow(a, b, &r)) trap("overflow"); s_push(m, 0, r); }
            else if (ins.op == 6) { if (__builtin_mul_overflow(a, b, &r)) trap("overflow"); s_push(m, 0, r); }
            else if (ins.op == 7) { if (b == 0) trap("division by zero"); s_push(m, 0, floormod(a, b)); }
            else if (ins.op == 8) s_push(m, 1, a < b);
            else s_push(m, 1, a == b);
        } else if (ins.op == 10) {
            if (!as_boolean(s_pop(m))) pc = ins.arg;
        } else if (ins.op == 11) pc = ins.arg;
        else if (ins.op == 12) {
            unique_check(m->returns);
            if (ret->gen == INT64_MAX) trap("gen");
            if (ret->len >= ret->cap) list_grow(ret, 8);
            if (!plain_ready(m->h, ret)) trap("push");
            ((int64_t *)ret->data)[ret->len++] = pc;
            ret->gen++;
            pc = ins.arg;
        } else if (ins.op == 13) {
            unique_check(m->returns);
            if (ret->len == 0 || ret->gen == INT64_MAX) trap("pop");
            if (!plain_pop_ready(m->h, ret)) trap("pop");
            pc = ((int64_t *)ret->data)[--ret->len];
            ret->gen++;
        } else return as_integer(s_pop(m));
    }
}
__attribute__((noinline)) static int64_t v1(heap_t *volatile hslot, const insn_t *prog, int64_t program_len, int64_t size,
                                            int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    vobject *program_obj = new_list(sizeof(insn_t), program_len);
    program_obj->list.len = program_len;
    memcpy(program_obj->list.data, prog, (size_t)program_len * sizeof(insn_t));
    for (int64_t batch = 0; batch < iterations; batch++) {
        vm1 m = { new_list(sizeof(value_t), 0), new_list(8, 0), new_list(8, 2), program_obj, hslot };
        m.variables->list.len = 2;
        int64_t sd;
        if (__builtin_add_overflow(seed, batch, &sd)) trap("overflow");
        int64_t r = exec1(&m, (const insn_t *)program_obj->list.data, program_len, size, sd);
        free_list(m.stack); free_list(m.returns); free_list(m.variables);
        checksum = floormod(checksum + r, MOD);
    }
    free_list(program_obj);
    return checksum;
}

/* ---- v2: + value semantics and L2: stack, returns and variables are fresh locals nobody else can see: no
 * RC uniqueness test, no ready call, no generation counter, header = (len) in a register; storage still in
 * memory with capacity checks and bounds checks; elements still copied through temporaries (the stall remains);
 * `program` is immutable (pointer and length in registers). */
__attribute__((noinline)) static int64_t exec2(const insn_t *prog, int64_t plen, int64_t size, int64_t seed) {
    value_t *st = calloc(8, sizeof(value_t));
    int64_t stcap = 8, sp = 0;
    int64_t *rs = calloc(8, 8);
    int64_t rcap = 8, rp = 0;
    int64_t vars[2] = {0, 0};
    int64_t pc = 0, result;
#define PUSH(T, P) do { if (sp >= stcap) { stcap *= 2; st = realloc(st, (size_t)stcap * sizeof(value_t)); } store_value_via_temp(&st[sp++], (T), (P)); } while (0)
#define POP(V) do { if (sp == 0) trap("pop"); (V) = load_value_via_vector(&st[--sp]); } while (0)
    for (;;) {
        if ((uint64_t)pc >= (uint64_t)plen) trap("index");
        insn_t ins = prog[pc++];
        value_t v, w;
        int64_t a, b, r;
        switch (ins.op) {
        case 0: PUSH(0, seed); break;
        case 1: PUSH(0, size); break;
        case 2: PUSH(0, ins.arg); break;
        case 3: if ((uint64_t)ins.arg >= 2) trap("index"); PUSH(0, vars[ins.arg]); break;
        case 4: POP(v); if ((uint64_t)ins.arg >= 2) trap("index"); vars[ins.arg] = as_integer(v); break;
        case 5: case 6: case 7: case 8: case 9:
            POP(v); POP(w); b = as_integer(v); a = as_integer(w);
            if (ins.op == 5) { if (__builtin_add_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); }
            else if (ins.op == 6) { if (__builtin_mul_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); }
            else if (ins.op == 7) { if (b == 0) trap("division by zero"); PUSH(0, floormod(a, b)); }
            else if (ins.op == 8) PUSH(1, a < b);
            else PUSH(1, a == b);
            break;
        case 10: POP(v); if (!as_boolean(v)) pc = ins.arg; break;
        case 11: pc = ins.arg; break;
        case 12: if (rp >= rcap) { rcap *= 2; rs = realloc(rs, (size_t)rcap * 8); } rs[rp++] = pc; pc = ins.arg; break;
        case 13: if (rp == 0) trap("pop"); pc = rs[--rp]; break;
        default: POP(v); result = as_integer(v); goto done;
        }
    }
done:
    free(st); free(rs);
    return result;
#undef PUSH
#undef POP
}
__attribute__((noinline)) static int64_t v2(const insn_t *prog, int64_t plen, int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t sd;
        if (__builtin_add_overflow(seed, batch, &sd)) trap("overflow");
        checksum = floormod(checksum + exec2(prog, plen, size, sd), MOD);
    }
    return checksum;
}

/* ---- v3: + tagged values built in place: tag and payload are written into their stack slot and read back as
 * two scalars (no temporary, no 16-byte vector copy), so no store-forwarding stall. */
__attribute__((noinline)) static int64_t exec3(const insn_t *prog, int64_t plen, int64_t size, int64_t seed) {
    value_t *st = calloc(8, sizeof(value_t));
    int64_t stcap = 8, sp = 0;
    int64_t *rs = calloc(8, 8);
    int64_t rcap = 8, rp = 0;
    int64_t vars[2] = {0, 0};
    int64_t pc = 0, result;
#define PUSH(T, P) do { if (sp >= stcap) { stcap *= 2; st = realloc(st, (size_t)stcap * sizeof(value_t)); } st[sp].tag = (T); st[sp].payload = (P); sp++; } while (0)
#define POP(TAG, PAY) do { if (sp == 0) trap("pop"); --sp; (TAG) = st[sp].tag; (PAY) = st[sp].payload; } while (0)
    for (;;) {
        if ((uint64_t)pc >= (uint64_t)plen) trap("index");
        insn_t ins = prog[pc++];
        uint32_t vt, wt;
        int64_t vp, wp, a, b, r;
        switch (ins.op) {
        case 0: PUSH(0, seed); break;
        case 1: PUSH(0, size); break;
        case 2: PUSH(0, ins.arg); break;
        case 3: if ((uint64_t)ins.arg >= 2) trap("index"); PUSH(0, vars[ins.arg]); break;
        case 4: POP(vt, vp); if ((uint64_t)ins.arg >= 2) trap("index"); vars[ins.arg] = vt == 0 ? vp : 0; break;
        case 5: case 6: case 7: case 8: case 9:
            POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0;
            if (ins.op == 5) { if (__builtin_add_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); }
            else if (ins.op == 6) { if (__builtin_mul_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); }
            else if (ins.op == 7) { if (b == 0) trap("division by zero"); PUSH(0, floormod(a, b)); }
            else if (ins.op == 8) PUSH(1, a < b);
            else PUSH(1, a == b);
            break;
        case 10: POP(vt, vp); if (!(vt == 1 ? vp : 0)) pc = ins.arg; break;
        case 11: pc = ins.arg; break;
        case 12: if (rp >= rcap) { rcap *= 2; rs = realloc(rs, (size_t)rcap * 8); } rs[rp++] = pc; pc = ins.arg; break;
        case 13: if (rp == 0) trap("pop"); pc = rs[--rp]; break;
        default: POP(vt, vp); result = vt == 0 ? vp : 0; goto done;
        }
    }
done:
    free(st); free(rs);
    return result;
#undef PUSH
#undef POP
}
__attribute__((noinline)) static int64_t v3(const insn_t *prog, int64_t plen, int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t sd;
        if (__builtin_add_overflow(seed, batch, &sd)) trap("overflow");
        checksum = floormod(checksum + exec3(prog, plen, size, sd), MOD);
    }
    return checksum;
}

/* ---- v4: + allocation hoisted: the three lists are non-escaping and their storage is reusable across
 * batches (L3 allocation elision without fusion): allocated once before the batch loop. Same code as v3 otherwise. */
static value_t *g4_st; static int64_t g4_stcap; static int64_t *g4_rs; static int64_t g4_rcap;
__attribute__((noinline)) static int64_t exec4(const insn_t *prog, int64_t plen, int64_t size, int64_t seed) {
    value_t *st = g4_st;
    int64_t stcap = g4_stcap, sp = 0;
    int64_t *rs = g4_rs;
    int64_t rcap = g4_rcap, rp = 0;
    int64_t vars[2] = {0, 0};
    int64_t pc = 0, result;
#define PUSH(T, P) do { if (sp >= stcap) { stcap *= 2; st = realloc(st, (size_t)stcap * sizeof(value_t)); } st[sp].tag = (T); st[sp].payload = (P); sp++; } while (0)
#define POP(TAG, PAY) do { if (sp == 0) trap("pop"); --sp; (TAG) = st[sp].tag; (PAY) = st[sp].payload; } while (0)
    for (;;) {
        if ((uint64_t)pc >= (uint64_t)plen) trap("index");
        insn_t ins = prog[pc++];
        uint32_t vt, wt;
        int64_t vp, wp, a, b, r;
        switch (ins.op) {
        case 0: PUSH(0, seed); break;
        case 1: PUSH(0, size); break;
        case 2: PUSH(0, ins.arg); break;
        case 3: if ((uint64_t)ins.arg >= 2) trap("index"); PUSH(0, vars[ins.arg]); break;
        case 4: POP(vt, vp); if ((uint64_t)ins.arg >= 2) trap("index"); vars[ins.arg] = vt == 0 ? vp : 0; break;
        case 5: case 6: case 7: case 8: case 9:
            POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0;
            if (ins.op == 5) { if (__builtin_add_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); }
            else if (ins.op == 6) { if (__builtin_mul_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); }
            else if (ins.op == 7) { if (b == 0) trap("division by zero"); PUSH(0, floormod(a, b)); }
            else if (ins.op == 8) PUSH(1, a < b);
            else PUSH(1, a == b);
            break;
        case 10: POP(vt, vp); if (!(vt == 1 ? vp : 0)) pc = ins.arg; break;
        case 11: pc = ins.arg; break;
        case 12: if (rp >= rcap) { rcap *= 2; rs = realloc(rs, (size_t)rcap * 8); } rs[rp++] = pc; pc = ins.arg; break;
        case 13: if (rp == 0) trap("pop"); pc = rs[--rp]; break;
        default: POP(vt, vp); result = vt == 0 ? vp : 0; goto done;
        }
    }
done:
    g4_st = st; g4_stcap = stcap; g4_rs = rs; g4_rcap = rcap;
    return result;
#undef PUSH
#undef POP
}
__attribute__((noinline)) static int64_t v4(const insn_t *prog, int64_t plen, int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    g4_stcap = 8; g4_st = calloc(8, sizeof(value_t)); g4_rcap = 8; g4_rs = calloc(8, 8);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t sd;
        if (__builtin_add_overflow(seed, batch, &sd)) trap("overflow");
        checksum = floormod(checksum + exec4(prog, plen, size, sd), MOD);
    }
    free(g4_st); free(g4_rs);
    return checksum;
}

/* ---- v5: + threaded dispatch: one indirect jump replicated at the end of every handler (computed goto) instead
 * of a single shared switch; the program is walked through a pointer, the stack through a pointer; the handlers
 * are separated by operation (the overflow, zero-divisor and tag checks stay). */
__attribute__((noinline)) static int64_t exec5(const insn_t *prog, int64_t plen, int64_t size, int64_t seed) {
    static const void *const labels[15] = { &&L0, &&L1, &&L2, &&L3, &&L4, &&L5, &&L6, &&L7, &&L8, &&L9, &&L10, &&L11, &&L12, &&L13, &&L14 };
    value_t *st = g4_st;
    int64_t stcap = g4_stcap, sp = 0;
    int64_t *rs = g4_rs;
    int64_t rcap = g4_rcap, rp = 0;
    int64_t vars[2] = {0, 0};
    const insn_t *pcp = prog;
    const insn_t *end = prog + plen;
    insn_t ins;
    uint32_t vt, wt;
    int64_t vp, wp, a, b, r, result;
#define DISPATCH() do { if ((uint64_t)(pcp - prog) >= (uint64_t)plen) trap("index"); ins = *pcp++; goto *labels[(uint64_t)ins.op > 14 ? 14 : ins.op]; } while (0)
#define PUSH(T, P) do { if (sp >= stcap) { stcap *= 2; st = realloc(st, (size_t)stcap * sizeof(value_t)); } st[sp].tag = (T); st[sp].payload = (P); sp++; } while (0)
#define POP(TAG, PAY) do { if (sp == 0) trap("pop"); --sp; (TAG) = st[sp].tag; (PAY) = st[sp].payload; } while (0)
    (void)end;
    DISPATCH();
L0: PUSH(0, seed); DISPATCH();
L1: PUSH(0, size); DISPATCH();
L2: PUSH(0, ins.arg); DISPATCH();
L3: if ((uint64_t)ins.arg >= 2) trap("index"); PUSH(0, vars[ins.arg]); DISPATCH();
L4: POP(vt, vp); if ((uint64_t)ins.arg >= 2) trap("index"); vars[ins.arg] = vt == 0 ? vp : 0; DISPATCH();
L5: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; if (__builtin_add_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); DISPATCH();
L6: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; if (__builtin_mul_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); DISPATCH();
L7: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; if (b == 0) trap("division by zero"); PUSH(0, floormod(a, b)); DISPATCH();
L8: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; PUSH(1, a < b); DISPATCH();
L9: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; PUSH(1, a == b); DISPATCH();
L10: POP(vt, vp); if (!(vt == 1 ? vp : 0)) pcp = prog + ins.arg; DISPATCH();
L11: pcp = prog + ins.arg; DISPATCH();
L12: if (rp >= rcap) { rcap *= 2; rs = realloc(rs, (size_t)rcap * 8); } rs[rp++] = pcp - prog; pcp = prog + ins.arg; DISPATCH();
L13: if (rp == 0) trap("pop"); pcp = prog + rs[--rp]; DISPATCH();
L14: POP(vt, vp); result = vt == 0 ? vp : 0;
    g4_st = st; g4_stcap = stcap; g4_rs = rs; g4_rcap = rcap;
    return result;
#undef DISPATCH
#undef PUSH
#undef POP
}
__attribute__((noinline)) static int64_t v5(const insn_t *prog, int64_t plen, int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    g4_stcap = 8; g4_st = calloc(8, sizeof(value_t)); g4_rcap = 8; g4_rs = calloc(8, 8);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t sd;
        if (__builtin_add_overflow(seed, batch, &sd)) trap("overflow");
        checksum = floormod(checksum + exec5(prog, plen, size, sd), MOD);
    }
    free(g4_st); free(g4_rs);
    return checksum;
}

/* ---- v6: + stack top cached in registers: the top-of-stack (tag and payload) lives in two locals, deeper
 * elements in memory, so push/pop of the common one-deep patterns touch no memory; tag checks stay.
 * Hand-structured (a stack-caching interpreter), valid for any program. */
__attribute__((noinline)) static int64_t exec6(const insn_t *prog, int64_t plen, int64_t size, int64_t seed) {
    static const void *const labels[15] = { &&L0, &&L1, &&L2, &&L3, &&L4, &&L5, &&L6, &&L7, &&L8, &&L9, &&L10, &&L11, &&L12, &&L13, &&L14 };
    value_t *st = g4_st;
    int64_t stcap = g4_stcap, sp = 0;       /* elements below the cached top */
    int64_t *rs = g4_rs;
    int64_t rcap = g4_rcap, rp = 0;
    int64_t vars[2] = {0, 0};
    const insn_t *pcp = prog;
    insn_t ins;
    uint32_t ttag = 0;
    int64_t tpay = 0, a, b;
    int have = 0;                           /* 1 when the cached top is a live stack element */
    int64_t result;
#define DISPATCH() do { if ((uint64_t)(pcp - prog) >= (uint64_t)plen) trap("index"); ins = *pcp++; goto *labels[(uint64_t)ins.op > 14 ? 14 : ins.op]; } while (0)
#define SPILL() do { if (have) { if (sp >= stcap) { stcap *= 2; st = realloc(st, (size_t)stcap * sizeof(value_t)); } st[sp].tag = ttag; st[sp].payload = tpay; sp++; } } while (0)
#define PUSH(T, P) do { SPILL(); ttag = (T); tpay = (P); have = 1; } while (0)
#define POP(TAG, PAY) do { if (!have) trap("pop"); (TAG) = ttag; (PAY) = tpay; if (sp > 0) { --sp; ttag = st[sp].tag; tpay = st[sp].payload; } else have = 0; } while (0)
    uint32_t vt, wt;
    int64_t vp, wp, r;
    DISPATCH();
L0: PUSH(0, seed); DISPATCH();
L1: PUSH(0, size); DISPATCH();
L2: PUSH(0, ins.arg); DISPATCH();
L3: if ((uint64_t)ins.arg >= 2) trap("index"); PUSH(0, vars[ins.arg]); DISPATCH();
L4: POP(vt, vp); if ((uint64_t)ins.arg >= 2) trap("index"); vars[ins.arg] = vt == 0 ? vp : 0; DISPATCH();
L5: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; if (__builtin_add_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); DISPATCH();
L6: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; if (__builtin_mul_overflow(a, b, &r)) trap("overflow"); PUSH(0, r); DISPATCH();
L7: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; if (b == 0) trap("division by zero"); PUSH(0, floormod(a, b)); DISPATCH();
L8: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; PUSH(1, a < b); DISPATCH();
L9: POP(vt, vp); POP(wt, wp); b = vt == 0 ? vp : 0; a = wt == 0 ? wp : 0; PUSH(1, a == b); DISPATCH();
L10: POP(vt, vp); if (!(vt == 1 ? vp : 0)) pcp = prog + ins.arg; DISPATCH();
L11: pcp = prog + ins.arg; DISPATCH();
L12: if (rp >= rcap) { rcap *= 2; rs = realloc(rs, (size_t)rcap * 8); } rs[rp++] = pcp - prog; pcp = prog + ins.arg; DISPATCH();
L13: if (rp == 0) trap("pop"); pcp = prog + rs[--rp]; DISPATCH();
L14: POP(vt, vp); result = vt == 0 ? vp : 0;
    g4_st = st; g4_stcap = stcap; g4_rs = rs; g4_rcap = rcap;
    return result;
#undef DISPATCH
#undef SPILL
#undef PUSH
#undef POP
}
__attribute__((noinline)) static int64_t v6(const insn_t *prog, int64_t plen, int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    g4_stcap = 8; g4_st = calloc(8, sizeof(value_t)); g4_rcap = 8; g4_rs = calloc(8, 8);
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t sd;
        if (__builtin_add_overflow(seed, batch, &sd)) trap("overflow");
        checksum = floormod(checksum + exec6(prog, plen, size, sd), MOD);
    }
    free(g4_st); free(g4_rs);
    return checksum;
}

/* ---- v8: BOUND ONLY (assumes a load-time bytecode verifier that this file does not contain): if the program had
 * been verified once (stack depth <= 64, operand kinds consistent, jump targets in range), the interpreter needs no
 * tags, no stack capacity or underflow checks and no program bounds check. Overflow and zero-divisor checks stay.
 * Valid only for programs that pass such a verifier (both built-in programs do); shown to bound the cost of the
 * generic checks. Not a claim about what a compiler can derive. */
__attribute__((noinline)) static int64_t exec8(const insn_t *prog, int64_t size, int64_t seed) {
    static const void *const labels[15] = { &&L0, &&L1, &&L2, &&L3, &&L4, &&L5, &&L6, &&L7, &&L8, &&L9, &&L10, &&L11, &&L12, &&L13, &&L14 };
    int64_t st[64];
    int64_t sp = 0, rs[64], rp = 0, vars[2] = {0, 0}, a, b, r;
    const insn_t *pcp = prog;
    insn_t ins;
#define DISPATCH() do { ins = *pcp++; goto *labels[ins.op]; } while (0)
    DISPATCH();
L0: st[sp++] = seed; DISPATCH();
L1: st[sp++] = size; DISPATCH();
L2: st[sp++] = ins.arg; DISPATCH();
L3: st[sp++] = vars[ins.arg]; DISPATCH();
L4: vars[ins.arg] = st[--sp]; DISPATCH();
L5: b = st[--sp]; a = st[--sp]; if (__builtin_add_overflow(a, b, &r)) trap("overflow"); st[sp++] = r; DISPATCH();
L6: b = st[--sp]; a = st[--sp]; if (__builtin_mul_overflow(a, b, &r)) trap("overflow"); st[sp++] = r; DISPATCH();
L7: b = st[--sp]; a = st[--sp]; if (b == 0) trap("division by zero"); st[sp++] = floormod(a, b); DISPATCH();
L8: b = st[--sp]; a = st[--sp]; st[sp++] = a < b; DISPATCH();
L9: b = st[--sp]; a = st[--sp]; st[sp++] = a == b; DISPATCH();
L10: if (!st[--sp]) pcp = prog + ins.arg; DISPATCH();
L11: pcp = prog + ins.arg; DISPATCH();
L12: rs[rp++] = pcp - prog; pcp = prog + ins.arg; DISPATCH();
L13: pcp = prog + rs[--rp]; DISPATCH();
L14: return st[--sp];
#undef DISPATCH
}
__attribute__((noinline)) static int64_t v8(const insn_t *prog, int64_t plen, int64_t size, int64_t iterations, int64_t seed) {
    for (int64_t i = 0; i < plen; i++) if ((uint64_t)prog[i].op > 14) trap("unverified opcode");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++)
        checksum = floormod(checksum + exec8(prog, size, seed + batch), MOD);
    return checksum;
}

/* ---- v9: v8 plus the division bypass: when both operands of `%` are non-negative and below 2^32 the remainder is a
 * 32-bit divide (much cheaper than the 64-bit idiv, and the divisor 1000003 / 2 are both small here). Same caveat as v8
 * (assumes a load-time bytecode verifier that this file does not contain): if the program had
 * been verified once (stack depth <= 64, operand kinds consistent, jump targets in range), the interpreter needs no
 * tags, no stack capacity or underflow checks and no program bounds check. Overflow and zero-divisor checks stay.
 * Valid only for programs that pass such a verifier (both built-in programs do); shown to bound the cost of the
 * generic checks. Not a claim about what a compiler can derive. */
__attribute__((noinline)) static int64_t exec9(const insn_t *prog, int64_t size, int64_t seed) {
    static const void *const labels[15] = { &&L0, &&L1, &&L2, &&L3, &&L4, &&L5, &&L6, &&L7, &&L8, &&L9, &&L10, &&L11, &&L12, &&L13, &&L14 };
    int64_t st[64];
    int64_t sp = 0, rs[64], rp = 0, vars[2] = {0, 0}, a, b, r;
    const insn_t *pcp = prog;
    insn_t ins;
#define DISPATCH() do { ins = *pcp++; goto *labels[ins.op]; } while (0)
    DISPATCH();
L0: st[sp++] = seed; DISPATCH();
L1: st[sp++] = size; DISPATCH();
L2: st[sp++] = ins.arg; DISPATCH();
L3: st[sp++] = vars[ins.arg]; DISPATCH();
L4: vars[ins.arg] = st[--sp]; DISPATCH();
L5: b = st[--sp]; a = st[--sp]; if (__builtin_add_overflow(a, b, &r)) trap("overflow"); st[sp++] = r; DISPATCH();
L6: b = st[--sp]; a = st[--sp]; if (__builtin_mul_overflow(a, b, &r)) trap("overflow"); st[sp++] = r; DISPATCH();
L7: b = st[--sp]; a = st[--sp]; if (b == 0) trap("division by zero"); st[sp++] = ((uint64_t)(a | b) >> 32) == 0 ? (int64_t)((uint32_t)a % (uint32_t)b) : floormod(a, b); DISPATCH();
L8: b = st[--sp]; a = st[--sp]; st[sp++] = a < b; DISPATCH();
L9: b = st[--sp]; a = st[--sp]; st[sp++] = a == b; DISPATCH();
L10: if (!st[--sp]) pcp = prog + ins.arg; DISPATCH();
L11: pcp = prog + ins.arg; DISPATCH();
L12: rs[rp++] = pcp - prog; pcp = prog + ins.arg; DISPATCH();
L13: pcp = prog + rs[--rp]; DISPATCH();
L14: return st[--sp];
#undef DISPATCH
}
__attribute__((noinline)) static int64_t v9(const insn_t *prog, int64_t plen, int64_t size, int64_t iterations, int64_t seed) {
    for (int64_t i = 0; i < plen; i++) if ((uint64_t)prog[i].op > 14) trap("unverified opcode");
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++)
        checksum = floormod(checksum + exec9(prog, size, seed + batch), MOD);
    return checksum;
}

/* ---- v7: WORK ELIMINATION (excluded from conclusions): the program is a constant, so the executor can be
 * partially evaluated on it. This is the bytecode compiled by hand: the loop is the scalar recurrence the
 * program computes. It only exists for the built-in program. */
__attribute__((noinline)) static int64_t v7(int64_t size, int64_t iterations, int64_t seed) {
    int64_t checksum = 0;
    for (int64_t batch = 0; batch < iterations; batch++) {
        int64_t total = seed + batch;
        for (int64_t i = 0; i < size; i++) {
            if (i % 2 == 0) total = (total * 3 + 7) % 1000003;
            else total = (total + i) % 1000003;
        }
        checksum = floormod(checksum + total, MOD);
    }
    return checksum;
}

int main(int argc, char **argv) {
    if (argc == 5 && (!strcmp(argv[1], "gen") || !strcmp(argv[1], "genb"))) { /* gen|genb SIZE SEED PATH: a program file */
        FILE *f = fopen(argv[4], "wb");
        int benchmark = !strcmp(argv[1], "gen");
        uint64_t n = benchmark ? 38 : 24;
        fwrite(&n, 8, 1, f);
        fwrite(benchmark ? (const void *)PROGRAM : (const void *)PROGRAM_B, sizeof(insn_t), n, f);
        fclose(f);
        return 0;
    }
    if (argc < 5) return 2;
    int which = atoi(argv[1]);
    int64_t size = atoll(argv[2]), iterations = atoll(argv[3]), seed = atoll(argv[4]);
    insn_t *prog = malloc(sizeof(insn_t) * 64);
    int64_t plen = 38;
    memcpy(prog, PROGRAM, sizeof PROGRAM);
    if (argc == 6) {
        FILE *f = fopen(argv[5], "rb");
        uint64_t n;
        if (!f || fread(&n, 8, 1, f) != 1 || n > 64 || fread(prog, sizeof(insn_t), n, f) != n) { fprintf(stderr, "bad program file\n"); return 2; }
        fclose(f);
        plen = (int64_t)n;
    } else if (which >= 30) return 2;
    heap_t *volatile hslot = &g_heap;
    int64_t start = now_ns(), checksum = 0;
    switch (which) {
    case 1: case 20: checksum = v1(hslot, prog, plen, size, iterations, seed); break;
    case 2: checksum = v2(prog, plen, size, iterations, seed); break;
    case 3: checksum = v3(prog, plen, size, iterations, seed); break;
    case 4: checksum = v4(prog, plen, size, iterations, seed); break;
    case 5: case 30: checksum = v5(prog, plen, size, iterations, seed); break;
    case 6: case 31: checksum = v6(prog, plen, size, iterations, seed); break;
    case 7: checksum = v7(size, iterations, seed); break;
    case 8: checksum = v8(prog, plen, size, iterations, seed); break;
    case 9: checksum = v9(prog, plen, size, iterations, seed); break;
    default: return 2;
    }
    printf("%lld %lld\n", (long long)checksum, (long long)(now_ns() - start));
    return 0;
}
