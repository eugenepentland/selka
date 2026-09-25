/* ERROR-TRACE-6: the error return trace recorders' calling conventions,
 * checked on the runtime's own compiled definitions.
 *
 * The LLVM translation calls the `preserve_most` twins and trusts every
 * general-purpose register but r11 to survive the call; QBE calls the
 * C-convention recorders and trusts only the C callee-saved registers. Each
 * recorder is called here from assembly with a distinct value in every
 * register, and the registers its convention promises are compared after the
 * call. Both pairs must also leave the same trace behind. */
// spec-case: ERROR-TRACE-6
#include "qbe_runtime.h"
#include <assert.h>
#include <stdint.h>
#include <string.h>

/* The registers `trace_abi_call` reports, in the order it stores them; a
 * register's index is also the low part of the value it is given. */
enum { RAX, RCX, RDX, RBX, RBP, RSI, RDI, R8, R9, R10, R12, R13, R14, R15, REGISTERS };

/* trace_abi_call(recorder, function, site, out): call `recorder(function,
 * site)` with every other general-purpose register but r11 and rsp holding
 * `0x5e57000000000000 + index`, then store every register into `out` in the
 * order above. The callee-saved registers are restored before returning. */
void trace_abi_call(void *recorder, const MylQbeFunction *function, uint64_t site, uint64_t *out);
__asm__(
    ".text\n"
    ".globl trace_abi_call\n"
    ".type trace_abi_call,@function\n"
    "trace_abi_call:\n"
    "    pushq %rbp\n"
    "    pushq %rbx\n"
    "    pushq %r12\n"
    "    pushq %r13\n"
    "    pushq %r14\n"
    "    pushq %r15\n"
    "    pushq %rcx\n"
    "    movq %rdi, %r11\n"
    "    movq %rsi, %rdi\n"
    "    movq %rdx, %rsi\n"
    "    movabsq $0x5e57000000000000, %rax\n"
    "    movabsq $0x5e57000000000001, %rcx\n"
    "    movabsq $0x5e57000000000002, %rdx\n"
    "    movabsq $0x5e57000000000003, %rbx\n"
    "    movabsq $0x5e57000000000004, %rbp\n"
    "    movabsq $0x5e57000000000007, %r8\n"
    "    movabsq $0x5e57000000000008, %r9\n"
    "    movabsq $0x5e57000000000009, %r10\n"
    "    movabsq $0x5e5700000000000a, %r12\n"
    "    movabsq $0x5e5700000000000b, %r13\n"
    "    movabsq $0x5e5700000000000c, %r14\n"
    "    movabsq $0x5e5700000000000d, %r15\n"
    "    call *%r11\n"
    "    movq (%rsp), %r11\n"
    "    movq %rax, 0(%r11)\n"
    "    movq %rcx, 8(%r11)\n"
    "    movq %rdx, 16(%r11)\n"
    "    movq %rbx, 24(%r11)\n"
    "    movq %rbp, 32(%r11)\n"
    "    movq %rsi, 40(%r11)\n"
    "    movq %rdi, 48(%r11)\n"
    "    movq %r8, 56(%r11)\n"
    "    movq %r9, 64(%r11)\n"
    "    movq %r10, 72(%r11)\n"
    "    movq %r12, 80(%r11)\n"
    "    movq %r13, 88(%r11)\n"
    "    movq %r14, 96(%r11)\n"
    "    movq %r15, 104(%r11)\n"
    "    popq %rcx\n"
    "    popq %r15\n"
    "    popq %r14\n"
    "    popq %r13\n"
    "    popq %r12\n"
    "    popq %rbx\n"
    "    popq %rbp\n"
    "    ret\n"
    ".size trace_abi_call, .-trace_abi_call\n");

/* What register `index` held going into the call: its value, or the argument. */
static uint64_t entered(int index, const MylQbeFunction *function, uint64_t site) {
    if (index == RDI) return (uint64_t)(uintptr_t)function;
    if (index == RSI) return site;
    return UINT64_C(0x5e57000000000000) + (uint64_t)index;
}

/* Call `recorder` through `trace_abi_call` and require every register in
 * `kept` to hold what it held going in. */
static void expect_kept(void *recorder, const MylQbeFunction *function, uint64_t site, const int *kept, int count) {
    uint64_t out[REGISTERS];
    memset(out, 0, sizeof out);
    trace_abi_call(recorder, function, site, out);
    for (int i = 0; i < count; ++i) assert(out[kept[i]] == entered(kept[i], function, site));
}

static const int c_callee_saved[] = { RBX, RBP, R12, R13, R14, R15 };
static const int preserve_most_saved[] = { RAX, RCX, RDX, RBX, RBP, RSI, RDI, R8, R9, R10, R12, R13, R14, R15 };

static MylQbeFunction functions[3];

static void conventions_test(void) {
    for (uint64_t site = 0; site < 3 * MYL_QBE_ERROR_TRACE_RING; ++site) {
        expect_kept((void *)myl_qbe_error_trace_origin, &functions[0], site, c_callee_saved, 6);
        expect_kept((void *)myl_qbe_error_trace_append, &functions[1], site, c_callee_saved, 6);
        expect_kept((void *)myl_qbe_error_trace_origin_preserve_most, &functions[0], site, preserve_most_saved, REGISTERS);
        expect_kept((void *)myl_qbe_error_trace_append_preserve_most, &functions[1], site, preserve_most_saved, REGISTERS);
    }
}

/* Record one origin and `appends` appended sites, through the twins when
 * `twins` is set and through the C-convention recorders otherwise. */
static MylQbeErrorTrace recorded(int twins, uint64_t appends) {
    memset(&myl_qbe_error_trace, 0, sizeof myl_qbe_error_trace);
    uint64_t origin = UINT64_C(7) | (MYL_QBE_ERROR_CREATED << 32);
    if (twins) myl_qbe_error_trace_origin_preserve_most(&functions[0], origin);
    else myl_qbe_error_trace_origin(&functions[0], origin);
    for (uint64_t i = 0; i < appends; ++i) {
        uint64_t site = i | (MYL_QBE_ERROR_PROPAGATED << 32);
        if (twins) myl_qbe_error_trace_append_preserve_most(&functions[1 + i % 2], site);
        else myl_qbe_error_trace_append(&functions[1 + i % 2], site);
    }
    return myl_qbe_error_trace;
}

static void same_trace_test(void) {
    const uint64_t lengths[] = { 0, 1, MYL_QBE_ERROR_TRACE_RING, MYL_QBE_ERROR_TRACE_RING + 5 };
    for (size_t i = 0; i < sizeof lengths / sizeof lengths[0]; ++i) {
        MylQbeErrorTrace plain = recorded(0, lengths[i]);
        MylQbeErrorTrace kept = recorded(1, lengths[i]);
        assert(plain.count == lengths[i] && plain.origin.function == &functions[0]);
        assert(memcmp(&plain, &kept, sizeof plain) == 0);
    }
}

int main(void) {
    conventions_test();
    same_trace_test();
    return 0;
}
