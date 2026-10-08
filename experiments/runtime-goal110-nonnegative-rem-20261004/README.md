# Guarded nonnegative constant remainder diagnostic

Source `27de73d302d23a9efaf811d541f1cb723323c434` remains unintegrated: the
negative-input supplementary population is a performance blocker. The coordinator owns goal
acceptance and the frozen 80 LLVM targets. All benchmark ports, contracts and
oracles remain unchanged.

The base is accepted G4 production
`6cf7bdce11bc205862bf75b9d9ce72e46caad0a2`. The initial source pin
`073e450bf4ceaf1295d930434d19c2ea0f21ef21` is an untimed predecessor: its
QBE scalar policy consumes the new proof, while its LLVM scalar policy retains
signed remainder corrections. Actual LLVM ELF inspection exposed this gap
before any timing. Its official ReleaseFast host, 24 guests, compiler receipt,
manifest and untimed 720-cell qualification/516-cell holdouts are preserved
under `.mylang-cache/goal110-nonnegative-rem-rf` in the predecessor worktree.
The corrected pin `27de73d3` fixes LLVM emission. Its official RF host and all
24 guests are preserved separately in `goal110-nonnegative-rem-llvm-rf-20261004`.

The existing loop planner first proves a positive constant ascending latch
step. A separate lower-endpoint proof accepts addition and positive literal
scaling over private, nonescaping invariant i64 values and the counter entry.
Every speculative endpoint intermediate must fit the existing magnitude
bounds, and emitted leaf bounds precede endpoint arithmetic. The new guard
proves that endpoint nonnegative before the admitted copy may lower positive
literal i64 truncating/flooring remainder as unsigned remainder. The original
copy, index proof and per-append allocation/admission/publication remain intact.
Positive powers of two do not add a new sign guard.

Unavailable endpoint magnitude proofs retain the previous signed copy. An
optional privacy or size certificate refusal replans the function exactly once
with only new sign-proof generation disabled, before emission; the analysis
arena owns abandoned plans. Modeled ABI/caller scalar references and a valid
production-emission `move_local` case verify that exact previous-plan fallback.
The current language rejects scalar `ref_local` bytecode, so no fabricated
native scalar-reference claim is made. A real referenced aggregate plus
detached scalar has a valid native differential test.

When an admitted new guard receives a negative endpoint, it selects the full
checked original copy, even if the former signed range copy would have fit.
This is an explicit possible performance tradeoff requiring supplementary
measurement. `append_endpoint.my` is a separate diagnostic, with the same
append expression and weighted fold, and accepts signed seeds. Its source is
identical across matched G4/successor LLVM and QBE guests under ordinary RF
flags. It never changes a frozen goal target.

The supplementary size cap is 4,096 and iteration cap is 100,000. For seed
−1,048,576 every dividend is strictly negative:
`seed + max_batch + (max_size - 1) * 13 = -895342`.
The helper checks this bound on every actual plan. Seed, batch and counter fit
the old signed magnitude guard; exact emitted guard evidence accompanies the
final artifacts. Calibration records any cap-limited short duration. The cap
must never be raised silently. Seed 42 supplies positive controls, and the
oracle uses independent Python mathematical integers and flooring remainder.

The predecessor's pinned focused suite passed 56 tests and recorded 32 exact
native outcomes. The pinned correction passed a 59-test focused suite, adding
policy-explicit emitted forms and nine native comparisons labeled **LLVM
scalar policy executed by QBE**. A subsequent focused translation check passed
13 tests (one named plus twelve unnamed), and the real emitted calculator
translated through the in-process LLVM adapter contains `urem` plus signed
fallback `srem`. Fresh successor qualification passed 720 cells and holdouts
passed 516. Separately built actual LLVM accounted/unaccounted ELFs passed nine
exact boundary pairs (18 executions): five successes and four failures, with
the positive result 469/status 213, zero/negative endpoints, a zero-trip
overflowing endpoint expression, three overflow cases and first heap refusal.
Full raw outputs include status, streams,
value and complete traps; overflow and memory-refusal codes are asserted exactly.

Actual pinned LLVM append-PC55 remainder instructions decrease from 15 to 7;
QBE decreases from 21 to 7. The LLVM sequence uses `mulx`, unsigned shift and
subtraction, while its checked original still has signed correction and `jo`.
Both independently identified saved scalar policies retain the same normalized
original body. LLVM batch bytes decrease 52,552→52,025 and whole `.text`
295,746→295,186; QBE 133,468→133,404 and 420,214→420,150. Run
`static-remainder.py` with the two live manifests to reproduce the exact-ELF
inspection. It uses read-only `nm`, `readelf` and `objdump`; its machine ranges
are valid only for the explicitly pinned artifact hashes.

The frozen eight-row screen used all six arms, five rounds and one warmup,
then a separate matched G4→27de comparison used those exact plans. These are
exploratory screens, with paired bootstrap intervals, and cannot confirm any
of the frozen 80 targets. No benchmark contracts or inputs changed.

| Frozen row | LLVM after/before | QBE after/before |
|---|---:|---:|
| list_append small | 0.9905 | 0.9697 |
| list_append large | 0.9948 | 1.0047 |
| list_filter small | 0.9376 | 0.9982 |
| list_filter large | 0.9194 | 0.9963 |
| sort_int small | 0.8688 | 0.9697 |
| sort_int large | 0.9760 | 0.9992 |
| mutate_nested small | 0.9829 | 0.9972 |
| mutate_nested large | 0.9935 | 0.9976 |

The separate signed-input kernel exposes the guard narrowing:

| Supplementary population | LLVM after/before [paired 95% interval] | QBE after/before |
|---|---:|---:|
| negative, size 64 | 1.0686 [1.0162, 1.1041] | 1.1606 |
| positive, size 64 | 0.9617 [0.9414, 0.9825] | 0.9462 |
| negative, size 4096 | 1.1201 [1.1178, 1.1723] | 1.2680 |
| positive, size 4096 | 0.8585 [0.8541, 0.8678] | 0.8379 |

Both small plans reached the explicit 100,000-iteration cap, with measured
kernel durations around 21–39 ms. Large negative/positive plans used
6,456/7,727 iterations. The actual maximum negative dividends were −947,758
and −988,886. The archived old supplementary guard admits these inputs:
all four leaves lie in ±2^59 and both loop spans exceed 16. The new guard adds
`seed + batch + entry * 13 >= 0`, which is false for every measured negative
batch, so it selects the checked original. The slowdown is a runtime-path
change; it is not attributed solely to binary layout.

Raw sessions are `cdad3663-f557-4e6c-946d-4b4e578476d7` (six arms),
`214afcd5-6b57-488e-b4f2-fa82f4999c67` (matched frozen plans), and
`fc3b2e26-4a2e-44bb-bac4-f14a28993617` (signed supplement), on CPU 2 under
the ordinary internal timing lock. Complete raw reports preserve times,
guest/host policies, live hash checks and oracle outcomes. `archive-index.json`
binds compressed and uncompressed bytes. Run `python3
experiments/runtime-goal110-nonnegative-rem-20261004/verify-archive.py` from the
repository root to replay all saved checks without any build or timing.

Guardian passed the corrected source gate and commit hook 88/88, and the final
focused unit command passed 59/59 with actual exit 0. Initial Guardian findings
and repairs, as well as the rejected precursor, remain archived. The successor
builder also preserved its initial checkout-not-complete refusal: a clean retry
started only after the new worktree checkout finished. Two static-inspection
helper parser mistakes (comment spacing and byte continuations) were repaired;
their failure logs are retained. The coordinator consolidates Guardian feedback
in `guardian-zig/FEEDBACK.md`.

The proposed successor uses a bounded multiple-of-divisor bias inside the old
signed fast copy, avoiding a runtime sign test and additional loop clone.
It is a separate experiment; see `NEXT.md` for the proof and alternatives.
