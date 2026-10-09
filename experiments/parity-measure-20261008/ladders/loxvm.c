/* PM-3 ladder 2: one Lox VM step (the mylang port's vm::run, heap::push/pop/peek).
 *
 * The bytecode is what the Lox compiler emits for experiments/.../lox/step.lox:
 *
 *   fun loop() { var n = N; var s = 0; var i = 0;
 *                while (i < n) { s = s + i; i = i + 1; } return s; }
 *
 * 16 dispatches per iteration: GET_LOCAL x5, ADD x2, SET_LOCAL x2, POP x3, LESS,
 * JUMP_IF_FALSE, CONSTANT, LOOP. The program prints `loop()` for N = argv[1].
 *
 * Rung 0 transcribes what mylang emits per dispatch today (counters of a
 * counting build of the port on this script, and the release asm):
 *   - read_byte: frame.code[frame.ip] with an index check and an overflow
 *     check on ip + 1;
 *   - `rt.frames[rt.frame_count - 1] = frame` twice per dispatch (after the
 *     opcode read and at the end of the iteration): an overflow check on
 *     frame_count - 1, an index check, a uniqueness test of the frames list,
 *     and a store of the frame's ip into the element (list_set_field);
 *   - push: an index check of stack_top, a uniqueness test of the stack list,
 *     a 16-byte Value store, stack_top + 1 with an overflow check, kept in rt;
 *   - pop: stack_top - 1 with an overflow check, an index check, a load;
 *   - peek(d): two overflow checks (stack_top - 1 - d), Python's negative-index
 *     wrap, an index check, a load;
 *   - GET_LOCAL / SET_LOCAL: frame.base + slot with an overflow check, the
 *     negative-index wrap, an index check (SET_LOCAL: and a uniqueness test);
 *   - ADD: is_string(peek 0) and is_string(peek 1), then is_number of both,
 *     two pops, a push; LESS the same without is_string;
 *   - CONSTANT: frame.function.chunk.constants[byte]: three retains and three
 *     releases of the blocks on that path (borrow inference misses it);
 *   - JUMP_IF_FALSE / LOOP: read_short, two index checks and overflow checks
 *     on `ip + 2`, `ip - 2`, `* 256`, `+`.
 * State lives in memory as in mylang: rt (stack, stack_top, frames,
 * frame_count) behind a pointer the compiler cannot see through, the frame
 * record in a stack slot reloaded every dispatch (in vm::run it is spilled:
 * its address escapes into the `mut frame` helpers), the frames list pointer
 * stored back into rt after each uniqueness test, Python's negative-index
 * wrap on every index the core cannot prove non-negative (the code offset
 * and frame_count - 1 included), and the frame's ip written back into
 * rt.frames every dispatch.
 *
 * Each later rung adds one change:
 *   1  overflow checks removed (ranges: ip, stack_top, frame_count bounded);
 *   2  index checks and negative-index wraps removed (stack depth and code
 *      offsets proven in range and non-negative);
 *   3  uniqueness tests hoisted out of the loop (the stack and frames lists
 *      are unique for the whole run), so the list pointers are not stored back;
 *   4  count traffic removed (CONSTANT borrows the constants list);
 *   5  the frame in registers: the record is not reloaded each dispatch and
 *      its ip is not written back into rt.frames (only around calls and
 *      returns);
 *   6  stack_top in a register (a local stack pointer, as clox keeps it);
 *   7  is_string/is_number/as_number on the popped values fused (each operand
 *      read once: the peeks and pops of ADD/LESS share one load).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef RUNG
#define RUNG 0
#endif

enum { OP_CONSTANT, OP_NIL, OP_POP, OP_GET_LOCAL, OP_SET_LOCAL, OP_LESS, OP_ADD, OP_JUMP_IF_FALSE, OP_LOOP, OP_RETURN };
enum { T_NIL = 0, T_BOOL = 1, T_NUMBER = 2, T_OBJ = 3 };

typedef struct block { uint32_t count, kind; int64_t len, cap; void *reserved; } block;
typedef struct value { uint8_t tag; union { double number; int64_t raw; } as; } value;
typedef struct chunk { block *code, *lines, *constants; } chunk;
typedef struct function_obj { int64_t arity, upvalue_count; chunk chunk; int64_t name; } function_obj;
typedef struct call_frame { int64_t closure; function_obj function; block *code; block *upvalues; int64_t ip, base; } call_frame;
typedef struct runtime { block *stack; int64_t stack_top; block *frames; int64_t frame_count; } runtime;

#define DATA(b, T) ((T *)((char *)(b) + 32))

static __attribute__((noinline, cold, noreturn)) void trap(int code) { fprintf(stderr, "trap %d\n", code); exit(1); }
static __attribute__((noinline, cold)) block *copy(block *b) { (void)b; trap(99); }
static __attribute__((noinline, cold)) void free_block(block *b) { (void)b; trap(98); }

#if RUNG >= 1
#define ADD_OV(a, b, r) ((*(r) = (a) + (b)), 0)
#define SUB_OV(a, b, r) ((*(r) = (a) - (b)), 0)
#define MUL_OV(a, b, r) ((*(r) = (a) * (b)), 0)
#else
#define ADD_OV(a, b, r) __builtin_add_overflow(a, b, r)
#define SUB_OV(a, b, r) __builtin_sub_overflow(a, b, r)
#define MUL_OV(a, b, r) __builtin_mul_overflow(a, b, r)
#endif
#if RUNG >= 2
#define CHECK(i, b) ((void)0)
#else
#define CHECK(i, b) do { if ((uint64_t)(i) >= (uint64_t)(b)->len) trap(2); } while (0)
#endif
#if RUNG >= 3
#define UNIQUE(b) ((void)0)
#else
#define UNIQUE(b) do { if ((b)->count != 1) (b) = copy(b); } while (0)
#endif

static block *list_new(int64_t len, int64_t size) {
    block *b = aligned_alloc(32, (size_t)(32 + len * size + 31) & ~(size_t)31);
    memset(b, 0, (size_t)(32 + len * size));
    b->count = 1; b->len = len; b->cap = len;
    return b;
}

static inline void retain(block *b) { if (b->count != UINT32_MAX) b->count += 1; }
static inline void release(block *b) { if (b->count != UINT32_MAX) { if (--b->count == 0) free_block(b); } }

/* Python's negative-index wrap that `xs[k]` keeps for a k the core cannot bound. */
static inline int64_t wrap(int64_t k, block *b) {
#if RUNG >= 2
    (void)b; return k;
#else
    return k < 0 ? k + b->len : k;
#endif
}

#if RUNG >= 6
#define TOP top
#define SYNC_TOP() (rt->stack_top = top)
#else
#define TOP rt->stack_top
#define SYNC_TOP() ((void)0)
#endif

__attribute__((noinline)) static double run(runtime *rt) {
    call_frame frame = DATA(rt->frames, call_frame)[rt->frame_count - 1];
#if RUNG >= 6
    int64_t top = rt->stack_top;
#endif
#if RUNG >= 5
    int64_t ip = frame.ip;
#define IP ip
#else
#define IP frame.ip
#endif
#if RUNG < 5
    call_frame *volatile escaped = &frame; (void)escaped;
#endif
    for (;;) {
#if RUNG < 5
        /* The frame record lives in a stack slot (its address escapes into the
           mut-parameter helpers), so every dispatch reloads it. */
        __asm__ volatile("" ::: "memory");
#endif
        int64_t at = wrap(IP, frame.code);
        CHECK(at, frame.code);
        uint8_t instruction = (uint8_t)DATA(frame.code, int64_t)[at];
        if (ADD_OV(at, 1, &IP)) trap(0);
#if RUNG < 5
        {
            int64_t k;
            if (SUB_OV(rt->frame_count, 1, &k)) trap(0);
            k = wrap(k, rt->frames);
            CHECK(k, rt->frames);
            block *frames = rt->frames;
            UNIQUE(frames);
#if RUNG < 3
            rt->frames = frames;
#endif
            DATA(frames, call_frame)[k].ip = frame.ip;
        }
#endif
        switch (instruction) {
        case OP_CONSTANT: {
            block *constants = frame.function.chunk.constants;
#if RUNG < 4
            retain(frame.function.chunk.code); retain(frame.function.chunk.code); retain(constants);
#endif
            int64_t c = IP; CHECK(c, frame.code);
            int64_t slot = DATA(frame.code, int64_t)[c];
            if (ADD_OV(c, 1, &IP)) trap(0);
            CHECK(slot, constants);
            value v = DATA(constants, value)[slot];
#if RUNG < 4
            release(constants); release(frame.function.chunk.code); release(frame.function.chunk.code);
#endif
            CHECK(TOP, rt->stack); UNIQUE(rt->stack);
            DATA(rt->stack, value)[TOP] = v;
            if (ADD_OV(TOP, 1, &TOP)) trap(0);
            break;
        }
        case OP_POP: {
            int64_t t; if (SUB_OV(TOP, 1, &t)) trap(0); TOP = t;
            CHECK(t, rt->stack);
            value v = DATA(rt->stack, value)[t]; (void)v;
            break;
        }
        case OP_GET_LOCAL: {
            int64_t c = IP; CHECK(c, frame.code);
            int64_t slot = DATA(frame.code, int64_t)[c];
            if (ADD_OV(c, 1, &IP)) trap(0);
            int64_t k; if (ADD_OV(frame.base, slot, &k)) trap(0);
            k = wrap(k, rt->stack); CHECK(k, rt->stack);
            value v = DATA(rt->stack, value)[k];
            CHECK(TOP, rt->stack); UNIQUE(rt->stack);
            DATA(rt->stack, value)[TOP] = v;
            if (ADD_OV(TOP, 1, &TOP)) trap(0);
            break;
        }
        case OP_SET_LOCAL: {
            int64_t c = IP; CHECK(c, frame.code);
            int64_t slot = DATA(frame.code, int64_t)[c];
            if (ADD_OV(c, 1, &IP)) trap(0);
            int64_t t, d; if (SUB_OV(TOP, 1, &t)) trap(0); if (SUB_OV(t, 0, &d)) trap(0);
            d = wrap(d, rt->stack); CHECK(d, rt->stack);
            value v = DATA(rt->stack, value)[d];
            int64_t k; if (ADD_OV(frame.base, slot, &k)) trap(0);
            k = wrap(k, rt->stack); UNIQUE(rt->stack); CHECK(k, rt->stack);
            DATA(rt->stack, value)[k] = v;
            break;
        }
        case OP_LESS:
        case OP_ADD: {
#if RUNG >= 7
            int64_t t = TOP - 2;
            value a = DATA(rt->stack, value)[t], b = DATA(rt->stack, value)[t + 1];
            if (a.tag != T_NUMBER || b.tag != T_NUMBER) trap(3);
            value r = instruction == OP_ADD ? (value){ T_NUMBER, { .number = a.as.number + b.as.number } }
                                            : (value){ T_BOOL, { .raw = a.as.number < b.as.number } };
            DATA(rt->stack, value)[t] = r;
            TOP = t + 1;
#else
            value p0, p1;
            for (int d = 0; d < 2; d++) {
                int64_t t, e; if (SUB_OV(TOP, 1, &t)) trap(0); if (SUB_OV(t, d, &e)) trap(0);
                e = wrap(e, rt->stack); CHECK(e, rt->stack);
                if (d == 0) p0 = DATA(rt->stack, value)[e]; else p1 = DATA(rt->stack, value)[e];
            }
            if (instruction == OP_ADD && p0.tag == T_OBJ && p1.tag == T_OBJ) trap(4);
            for (int d = 0; d < 2; d++) {
                int64_t t, e; if (SUB_OV(TOP, 1, &t)) trap(0); if (SUB_OV(t, d, &e)) trap(0);
                e = wrap(e, rt->stack); CHECK(e, rt->stack);
                if (DATA(rt->stack, value)[e].tag != T_NUMBER) trap(3);
            }
            double operands[2];
            for (int d = 0; d < 2; d++) {
                int64_t t; if (SUB_OV(TOP, 1, &t)) trap(0); TOP = t;
                CHECK(t, rt->stack);
                value v = DATA(rt->stack, value)[t];
                if (v.tag != T_NUMBER) trap(5);
                operands[d] = v.as.number;
            }
            value r = instruction == OP_ADD ? (value){ T_NUMBER, { .number = operands[1] + operands[0] } }
                                            : (value){ T_BOOL, { .raw = operands[1] < operands[0] } };
            CHECK(TOP, rt->stack); UNIQUE(rt->stack);
            DATA(rt->stack, value)[TOP] = r;
            if (ADD_OV(TOP, 1, &TOP)) trap(0);
#endif
            break;
        }
        case OP_JUMP_IF_FALSE:
        case OP_LOOP: {
            int64_t c; if (ADD_OV(IP, 2, &c)) trap(0); IP = c;
            int64_t h, l; if (SUB_OV(c, 2, &h)) trap(0); if (SUB_OV(c, 1, &l)) trap(0);
            CHECK(h, frame.code); CHECK(l, frame.code);
            int64_t hi = DATA(frame.code, int64_t)[h], lo = DATA(frame.code, int64_t)[l], offset;
            if (MUL_OV(hi, 256, &offset)) trap(0);
            if (ADD_OV(offset, lo, &offset)) trap(0);
            if (instruction == OP_LOOP) {
                if (SUB_OV(IP, offset, &IP)) trap(0);
            } else {
                int64_t t, e; if (SUB_OV(TOP, 1, &t)) trap(0); if (SUB_OV(t, 0, &e)) trap(0);
                e = wrap(e, rt->stack); CHECK(e, rt->stack);
                value v = DATA(rt->stack, value)[e];
                int falsey = v.tag == T_NIL || (v.tag == T_BOOL && !v.as.raw);
                if (falsey && ADD_OV(IP, offset, &IP)) trap(0);
            }
            break;
        }
        case OP_RETURN: {
            int64_t t = TOP - 1;
            SYNC_TOP();
            return DATA(rt->stack, value)[t].as.number;
        }
        default:
            trap(6);
        }
#if RUNG < 5
        {
            int64_t k;
            if (SUB_OV(rt->frame_count, 1, &k)) trap(0);
            k = wrap(k, rt->frames);
            CHECK(k, rt->frames);
            DATA(rt->frames, call_frame)[k].ip = frame.ip;
        }
#endif
    }
}

int main(int argc, char **argv) {
    double n = argc > 1 ? atof(argv[1]) : 10000000.0;
    static const int64_t code[] = {
        OP_GET_LOCAL, 3, OP_GET_LOCAL, 1, OP_LESS, OP_JUMP_IF_FALSE, 0, 20, OP_POP,
        OP_GET_LOCAL, 2, OP_GET_LOCAL, 3, OP_ADD, OP_SET_LOCAL, 2, OP_POP,
        OP_GET_LOCAL, 3, OP_CONSTANT, 0, OP_ADD, OP_SET_LOCAL, 3, OP_POP,
        OP_LOOP, 0, 28,
        OP_POP, OP_GET_LOCAL, 2, OP_RETURN,
    };
    runtime *rt = malloc(sizeof *rt);
    block *code_list = list_new((int64_t)(sizeof code / sizeof code[0]), 8);
    memcpy(DATA(code_list, int64_t), code, sizeof code);
    block *constants = list_new(1, 16);
    DATA(constants, value)[0] = (value){ T_NUMBER, { .number = 1.0 } };
    rt->stack = list_new(16384, 16);
    DATA(rt->stack, value)[1] = (value){ T_NUMBER, { .number = n } };
    DATA(rt->stack, value)[2] = (value){ T_NUMBER, { .number = 0.0 } };
    DATA(rt->stack, value)[3] = (value){ T_NUMBER, { .number = 0.0 } };
    rt->stack_top = 4;
    rt->frames = list_new(64, sizeof(call_frame));
    call_frame *f = DATA(rt->frames, call_frame);
    f->function.chunk.code = code_list; f->function.chunk.constants = constants; f->code = code_list;
    f->ip = 0; f->base = 0;
    rt->frame_count = 1;
    printf("%.0f\n", run(rt));
    return 0;
}
