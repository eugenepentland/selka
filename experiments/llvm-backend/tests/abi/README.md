# The ABI oracle: what the target actually does with the emitted signatures

These probes exist because the emitter's own signature shapes are not the C shapes
they resemble, and a backend that guesses gets a silently wrong program. Each
`aggN.ssa` declares one aggregate size as the emitted IL declares it,
`aggN.qbe.s` is the real assembler output of the real QBE binary
(`zig-out/bin/qbe -t amd64_sysv aggN.ssa -o aggN.qbe.s`), and the bytes below are
read off that output. They are the authority the LLVM arm had to reproduce.

## What the IL says, and what the target does

Every aggregate in the emitted IL is an opaque `:tN = align 8 { b N }`. A `:tN`
*value* is the address of its storage — `add %a0, 8` is address arithmetic and
`loadl`/`storel` read and write through it — so inside a function body an aggregate
is always a pointer-width integer. Only the **call boundary** is by value, and how
it is passed depends on the size:

| `:tN` | argument | result |
|---|---|---|
| 8 (one word) | one integer register (`%rsi`) | in `%rax` |
| 16 (two words) | two integer registers (`%rsi`, `%rdx`) | in `%rax`:`%rdx` |
| 24 and larger | on the **stack by value** | caller-provided buffer: its address in `%rdi`, returned in `%rax` |

Measured, from `take_N` (a callee reading byte 0 and byte N−1 of its parameter)
and `give_N`/`qbe_retcall_N` (a callee returning one and a caller reading it back):

```asm
take_16:                                # :t16 parameter → %rsi, %rdx
	movq	%rsi, 0(%rsp)
	movq	%rdx, 8(%rsp)
	movzbl	0(%rsp), %eax
	movzbl	15(%rsp), %ecx

take_24:                                # :t24 parameter → on the stack
	movzbl	8(%rsp), %eax             # the return address occupies 0(%rsp)
	movzbl	31(%rsp), %ecx

give_24:                                # :t24 result → hidden buffer in %rdi
	movq	%rdi, %rax
	movq	8(%rsp), %rcx
	movq	%rcx, 0(%rax)
```

An aggregate parameter larger than two words therefore arrives as a *copy* at a
known stack offset relative to the return address, and an aggregate result larger
than two words is written into caller storage whose address is the hidden first
argument — which is why a caller that declares such a function as returning `i64`
does not merely get the wrong value: the callee's hidden result pointer shifts
`ctx` out of `%rdi` and the callee dereferences a null context.

## How the LLVM arm satisfies it

The arm never has to interoperate with QBE at the object level — both ends of the
comparison come from the same emitted IL, and the generated C entry point hands the
guest only its context pointer and capability words — so it uses one convention
consistently:

* every parameter, aggregate or not, is an `i64` (an aggregate arrives as the
  address of the temporary at the call site, which is exactly what the IL body
  then uses it as);
* a result whose type is `:tN` is returned **by value** as `[N x i8]`, which makes
  LLVM produce a real address for the returned storage in registers for a two-word
  aggregate and through the caller's buffer above that;
* every scalar is passed and returned at its own QBE width (`i32`, `i64`,
  `float`, `double`), with `l`-typed values staying `i64` and each memory access
  inserting its own `inttoptr`.

That is verifiably consistent within the arm: the four benchmark workloads, the
port's 79 guest tests and the differential trap fixtures all agree with the QBE arm
byte for byte.

## Reproducing

```sh
cd experiments/llvm-backend/tests/abi
for f in agg*.ssa; do
  ../../../../zig-out/bin/qbe -t amd64_sysv "$f" -o "${f%.ssa}.qbe.s"
done
```

A probe is read like a unit test: the callee's parameter is a copy, so its bytes
are reachable from the IL's address; a mismatch shows up as a wrong byte in the
assembler, not as a failing assertion.
