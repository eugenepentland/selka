# Caller-field lifetime evidence, 2026-09-27

Design-only follow-up to c1224f30; no production optimization. The immutable
corrected compiler and full N10 binaries remain fixed. Two fresh full-workload
instruction/LBR profiles ran on CPU3 with exact expected output. All 305 QBE and
234 LLVM samples throttled, with zero lost records: attribution is qualitative
only, with no cost percentages or projected speedup.

Branch attribution deduplicates a caller once per sampled branch stack and each
exact call site once per stack. `vm::read_byte` loan calls appear in 23 QBE and
54 LLVM stacks; `vm::run` in 36 and 64. Current read_byte emits two loans through
an incoming mutable ExecFrame; read_short has four but may fail the existing
complete interval grammar. Native assembly and exact emitted bodies are retained.

The thirteen remaining vm::run read pairs are five list[CallFrame] reads with
24-byte plain results and eight list[Value] reads with 16-byte plain variant
results. No scalar element read is hidden in those thirteen pairs. The table
maps original PCs/source lines, not dynamic weights. Some indexed expressions
contain callbacks. Extending caller authority alone cannot admit these reads.

The bounded first design is in
`docs/audits/d9-rc-caller-field-read-design-2026-09-27.md`. It distinguishes a
caller lifetime anchor from ordinary-owner/unique facts, retains the full safe
record refusal and scalar interval, and defers Runtime/plain-result broadening.
The runtime single-pointer alternative would retain journal/protocol work.

Existing c122 median instructions are 154,804,551,022 QBE and 118,368,631,962 LLVM,
21.372315× and 34.478071× archival accepted GC. They are inherited identity-linked
observations from the named-field implementation archive, not new medians here.
The full Stage 4 performance gate remains unmet.

`dump.stderr.gz` preserves a rejected attempt to use single-module dump-bytecode
on the project source (`module main` is not accepted in that command). All site
mapping instead uses the successful complete project emission already archived.

Run `python3 experiments/d9-rc-caller-field-read-design-20260927/verify.py --live`.
No duplicate native builds, compiler installs, caches or worktrees were created.
