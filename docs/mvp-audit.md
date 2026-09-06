# Scalar MVP acceptance audit

Scope: the scalar compiler and VM in plan sections 4–13, on Guardian's exact
Zig `0.17.0-dev.1683+5ceec001b` snapshot. Plan sections 15 and 18 explicitly
reserve ownership, effects, duplicate discovery, conversions, schemas, and
other quality contracts for later experiments. They are not implemented.

The previous milestones established M0–M4. This audit inspects their actual
source and adds missing boundary checks; checked plan boxes are not themselves
evidence. Tests named below are in `src/compiler_test.zig` unless identified
as CLI tests in `test/integration.zig`.

| Requirement | Implementation and inspected evidence |
| --- | --- |
| Native host build, exact toolchain, commands | `.zigversion`, manifest, `build.zig` exact-version guard and native target; README commands; CI installs manifest version and compares it with `.zigversion`. Fresh-checkout verification is recorded below. |
| `check`, `run`, `dump-bytecode` | `main.zig` dispatch; CLI success, dump golden, source/runtime/usage, missing files, and oversized-source tests assert exit statuses and stdout. |
| Complete program and entry signature | Signature collection checks exactly one no-argument integer main. Function-signature negative cases and all-command CLI tests reject missing/duplicate/parameterized/boolean main. |
| Every scalar operator and precedence | Precedence, unary/minimum, comparison/logical truth tables, signed division/remainder, and checked-overflow tests. Both host modes run the identical suite. |
| Literal bounds and no arithmetic folding | Lexer preserves integer spans; sema parses magnitude with direct-negation exception; `check` accepts trapping arithmetic. Minimum, maximum, oversized and indirectly-negated literals, and runtime traps are tested. |
| Checked compound assignment | Sema expands integer `+=`/`-=` into read, checked operation, store. Loop and compound-use tests exercise both; immutable and boolean targets are rejected. |
| Bindings, types, scopes | Explicit initialization, annotation checking, distinct bool/i64, per-function local IDs, active-name map. Local/scope tests cover use-before-definition, scope exit, shadowing, sibling reuse, immutable writes, and type errors. |
| Functions and parameters | Signatures precede all bodies; parameter slots come first and are immutable. Tests cover forward/nested calls, boolean arguments/results, mutual recursion, arity/type errors, duplicate names, function-name shadowing, and invalid uncalled helpers. |
| Control flow and returns | Conditions require bool; both branches checked; block/if termination is structural; every loop may fall through. Tests cover both outcomes, zero/many iterations, missing/wrong returns, and unreachable statements. |
| Explicit discard | Parser rejects bare expression/call statements with `E_EXPLICIT_DISCARD_REQUIRED`; lowering emits expression then POP. Tests cover both value types, skipped and retained traps, resolved reads, and repeated discarded calls. |
| Evaluation order | Lowering's explicit work stack emits operands and arguments left to right. Distinct-failure tests establish which operand/argument traps first; logical truth tables and skipped division establish short-circuit behavior. |
| Advisory warnings and declaration identity | Sema counts resolved reads/writes per local, emits warnings only after all functions pass, and sorts by span/code. Sibling/function identity tests, skipped branches, writes versus reads, and CLI golden output cover the contract. `_` remains an ordinary identifier in the lexer and resolver. |
| Stable located diagnostics | Source owns bytes/path and indexes lines; nodes/instructions retain spans. Tests assert warning declaration spans, arithmetic operator spans, exact LF/CRLF EOF positions, discard locations, and duplicate related locations. CLI renders only to stderr. |
| Phase and dependency boundaries | `compiler.zig` orchestrates source→lexer→AST→sema→typed program→lowering→bytecode→VM. The VM imports bytecode/types/diagnostic/source metadata, never lexer/parser/sema. |
| Typed identities and movable storage | Separate enums identify AST nodes, typed nodes, statements, functions, and locals. Tables are append-only; traversals retain IDs or copies across growth. Long flat expressions and allocation-failure scenarios exercise moving allocations. |
| Call/return contract | VM frame copies contain function, PC, local/operand bases, and entering span. Calls copy ordered arguments to parameters and retain caller operands; returns truncate locals/frames and push one typed value. Nested arithmetic and recursion tests exercise this behavior. |
| Iterative recursion and frame budget | VM loop manages explicit frames; main counts as one; default 1,024 and positive override. Tests cover boundary 1/2, zero/invalid options, and 20,000 recursive frames ending in a guest trap. |
| Instruction budget | Default 10,000,000; pre-dispatch check; positive u64 override. Exact dispatch-count and infinite-loop tests cover exhaustion; CLI tests cover malformed, duplicate, unsupported-command, and overflowing options. |
| Guest trace and host-failure separation | Traps include operator/call spans and newest 16 frames with omitted count. Trace tests verify names/lines/order. OOM remains an error, internal-invalid-bytecode remains InternalError, CLI host failures use status 2. |
| Bounded runtime storage | A 100,000-iteration program with calls, local declarations, and discarded values executes with only a 16 KiB fixed runtime allocator, including validator scratch. Repeating execution with the testing allocator checks cleanup. |
| Emission validation | `bytecode.validate` checks function/local IDs, parameter counts, jump bounds, underflow, return height, and join consistency. Invalid-reference/jump/join tests exercise rejection. This is not an untrusted-bytecode loader. |
| Request/runtime ownership | Compilation arena owns copied source and compiler tables; separate VM buffers use caller allocator and defer cleanup. Allocation-failure sweeps cover success, warning, source-error, call growth, runtime traps, dump, and diagnostic rendering. |
| Parser robustness | Recursive syntax shares a 256-level limit. Group/unary/call/block depth tests and a truncated/mutated source corpus produce normal bounded diagnostics. Flat expression checking/lowering is iterative. |
| Inspectable deterministic dump | `disassemble.zig` prints ordered function signatures, opcodes, call IDs/names, targets, and source locations. Arithmetic and warning-program goldens plus repeated dump tests assert output. |
| Actual CLI and same-mode tests | `build.zig` propagates optimization mode to core, compiler executable, and integration tests; integration tests spawn that executable. Both modes run the same fixtures. |
| Required example programs | Exact plan sum/GCD sources are in examples and CLI fixtures (4950/6). Factorial and nested-call tests and editable examples pass (factorial 5 = 120, nested arithmetic = 6). Collatz(27) additionally returns 111. |
| Supported/unsupported syntax and deliverables | All suggested modules exist; examples, positive/rejected/trapping fixtures, README, semantics, plan, progress, and this audit are present. Full exclusions remain in the plan and semantics document. |

## Verification record

On 2026-09-05 a fresh detached worktree of implementation commit `fb3458a`
was created outside the development directory, with no existing local Zig cache.
The following commands completed successfully there:

- `zig version`: `0.17.0-dev.1683+5ceec001b`.
- `zig build --summary all`: 3/3 steps succeeded; native executable installed.
- `zig build test --summary all`: 47/47 tests (35 core, 12 actual CLI).
- `zig build test -Doptimize=ReleaseFast --summary all`: same 47/47 tests.
- `zig build fmt-check --summary all`: passed.

The same suites passed in the development checkout. Source changes ended at
`fb3458a`; subsequent completion edits update documentation only. All M5 and
section 13 obligations have direct implementation and verification evidence in
the table above. This completes the scalar MVP as defined by the plan.
Hosted CI is configured but has not run: this repository has no remote. Guardian's
gates were not exercised; no Guardian feedback entry is required for these builds.
