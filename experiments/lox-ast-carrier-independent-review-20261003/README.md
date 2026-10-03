# Independent AST handler review

Candidate `941b030cfa2ec49b0c6c4bdb88501d9785462a46` passes this read-only
review with the limits below. No actionable source defect was found. The
author's exact directory is `experiments/lox-tree-ast-carrier-20261003` in
`/home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-vm-20261003`.
Its frozen candidate changes only `interpreter.my`, whose SHA256 is
`6c4655266242ca4696a02f754ef5eac6646ceb8ba93b0869072c6d6161a87378`.
The overlay SHA256 is
`b1fc1359603b549f7a06ed00a958d0d5dcf6f91515b78e2d4bad8719942d6f9b`.

Both handlers replace an owning getter return with the same node lookup and
expected match arm. Independent strict in-memory patch replay matches all
37 candidate files and the author's disk replay. After removing indentation
and the original getter assignment, the expected-arm operations are
textually identical and ordered identically. Both old getters remain intact.
The existing 84-test declarations, all provider entries, AST layout and
Runtime helpers are unchanged.

`call_expr` still evaluates the callee first, then arguments in source order,
then calls `call_value` with the same count and source line. `?` returns occur
at the same operations. Callee and completed arguments stay on Runtime's
value stack across nested allocation; reassignment during arguments cannot
replace the chosen bound receiver. The new focused programs exercise nested
class/allocation calls, side effects before an argument error, and bound
receiver reassignment.

`class_declaration` still publishes the global nil placeholder before
superclass evaluation, roots the superclass and allocated class, copies
inherited methods, opens and populates the `super` environment, then creates
and publishes each method in order. It restores the environment, defines the
class and pops the same roots in the same order. No allocation, error return,
cost, collection threshold or publication point moves. Recursive subclass
construction is checked by a new focused program.

`interpret` resolves the caller-owned Program before execution and keeps it
alive through every call. Handler Program parameters are read-only, while
Runtime, Output and Interpreter are separate mutable parameters. No new
Program write, mutable alias, callback or escape is introduced. Managed node
payloads can remain anchored in the readonly Program throughout recursion
under the existing RC-READONLY-ANCHOR-1 contract. Native tracing GC keeps the
caller Program roots and their reachable arrays; the change does not alter
the compiler's root protocol. This is a source shaping review, not a new
compiler certificate audit or an authorization to weaken its checks.

Saved selected-d14 QBE SSA and linked assembly each show one old getter call
per handler and zero in the candidate. Their hashes and the exact binaries
match. Normalized index checks are preserved: the old call handler/getter
sum and new handler each have two sites; class has three. Physical managed
operation counts grow on cold arms, so total static sites are not a dynamic
ownership-cost or speed claim. LLVM may inline handlers; an absent standalone
symbol is not treated as absent work. This review does not redisassemble or
time the guests.

The selected native compiler is `d14a7040` with frozen QBE `99ad919d`. All
four recorded native RC/GC builds, compiler/QBE hashes, manifests and actual
runtime objects match. LLVM native guests use O3/full LTO; QBE uses its
recorded default mode. The 1,168 bounded comparisons comprise 416 RC, 416
ordinary tracing GC and 336 native tracing-GC-stress observations. They cover
both engines/backends, Lox stress off/on, all 13 smoke scripts, 16 prior
regression programs and 23 exact error programs per engine. Status, full
stdout, full stderr including Lox statistics, script hashes and target guest
identities match controls. Eighty expensive native-GC smoke cells remain
explicitly unrun; closures, instantiation and properties provide selected
smoke coverage. The four new programs add 96 exact comparisons in all three
runtime modes. Eight RC native-stress pairs return the same checked refusal
status 2; those are refusal checks, not Lox execution passes.

The original additional error fixture expected the tree prefix for VM and
failed on the control's `in script` suffix. Its process status 1, completed
1,168 comparisons and partial 60 focused comparisons remain immutable.
There were zero candidate rows for the failing VM fixture. The corrected
receipt retains the identical bounded rows through explicit resume provenance
and reruns all 96 focused comparisons with engine-specific prefixes. This
review does not double-count the reused matrix or partial focused rows.

All 84 public tests passed freshly in each of four accounted configurations,
with no cached, skipped, failed, missing or unexpected tests. That 336-test
suite used historical compiler `4cbaeafa`: QBE Debug and LLVM `--release`,
each ordinary RC and native tracing-GC stress, with step accounting enabled.
It is distinct from selected d14 native qualification. GC ELF bytes match
across compilers, whereas RC bytes differ and the selected d14 RC guests
were tested directly. This review does not claim a d14 accounted suite ran.

The same wrong-node assertions and normalized bounds checks still precede
handler mutations. Assertions now originate in handlers, so malformed
internal AST native source PCs/frame names and instruction-accounted step
cutoffs are not byte-for-byte unchanged. Exact public Lox error streams are
checked; exact internal native trace identity is not claimed. No checks or
capability refusals were disabled. There is no performance acceptance or
Rust/Go parity claim.

`review.py` reads the frozen evidence and emits a new receipt without guest,
test or performance execution and without changing root/lane artifacts:

```bash
taskset -c 16 python3 -B experiments/lox-ast-carrier-independent-review-20261003/review.py \
  --lane /home/epentland/ai/canopy/mylang-worktrees/codex-lox-parity-vm-20261003 \
  --out .tmp-lox-ast-carrier-review-20261003/new-review.json
```

This next-phase review is separate from the accepted source84 checkpoint
`44cd4307` and its sealed callee-table evidence archive. Neither the accepted
checkpoint nor its archive was changed. Root owns measurements, composition,
selection, integration and consolidated Guardian feedback.
