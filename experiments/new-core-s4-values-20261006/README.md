# S4-V value-path package, 2026-10-06

Functional commits: `d5d4cbb40`, `d4d8c4e56`, `a2daebc63` and `3c86c3122`, from the qualified
S4-0/R integration `491caf1c98e2aa647872064f23b3ae42b301c3b7`.
Test-only follow-ups `be7978a37`, `63c6cd4db` and `8923ce3f1` keep both
child-length inspection functions reachable, make the post-pop sample safe,
match the eight native fixtures with eight verdict slots and inspect each emitted
function independently of emission order. They change no compiler code or
measured executable. The initial null-lookup and later slice-order test crashes
and the array-length compilation failure remain in their original receipts.
The package owns branch `codex/new-core-s4-values` in its locked worktree.
No push, main merge, `ir.zig` edit or existing runtime ABI/layout change occurred.

Nested places detach each collection parent before transferring its selected
child's owner. Ordinary COW chooses a copy, a counted test or a proven unique
update. Actual block membership determines the transfer pairing; unreachable
cloned markers cannot claim a live slot. Verify mode asserts each transferred
parent and each proven unique child before mutation. Record-root places retain
their existing field-transfer route. Fresh-child proofs exclude escaped or
multiply stored children, retaining counted COW for repeated/shared rows.

Uniform child-length facts use only immutable parameter or constant lengths.
Empty parent values are neutral, and push, pop, replacement and phi transfers
retain a common length only when every child agrees. Verify mode checks each
loaded child's symbolic length. A counted fill's final length must be available at the child's capture point: copies or element writes trace that point back to the original fill phi, whose exit must dominate it. The conformance fixture rc_append_loops caught a growing snapshot incorrectly claimed to have final length 17; snapshot-length-repair/ retains the five-arm native red/green reduction, and both the regression fixture and custom generator cover insertion during fill and captures stored after exit. After stack promotion, a heap counted fill
reserves at most 4096 initial elements; after COW, pushes still consuming its
original unique phi use the loop counter within that prefix and retain ordinary
growth afterward. Only the recorded backedge's push receives that marker;
post-loop appends use the ordinary capacity check. Verify builds check actual
length and capacity at each store. The final core suite exposed this boundary
bug in `v_hull`: its post-fill append was incorrectly marked and verify mode
trapped at index 64/capacity 64. `fill-boundary-repair/` preserves a native reducer
before the fix and its passing counterpart. The fixture and custom generator
now cover later appends, including fill sizes 0, 1, 64, 4096 and 4097.

Small consuming mut helpers with at most 20 blocks and 100 instructions inline
by cloning blocks, predecessor order, loop metadata and trap spans. Call, print
and error-trace operations exclude a helper. Returns are joined in a continuation;
projected implicit mut return records become component SSA values before RC.
Native trap-frame provenance for this optimization remains an integration blocker,
documented below; retaining instruction spans alone does not retain callee frames.
The alternate cheaper return path was also implemented and measured in retained
LLVM: its independent alias test passes, but its measured union-find ratios
1.411/1.399 to Zig lose to the chosen CFG inlining path (1.083/1.068 before the
final fill optimization). See `alternatives/` and `cheaper-return-seven-v2.json`.

Numeric buffer append formats into bounded stack storage, reserves once and
copies once. Signed integer spelling handles both i64 endpoints; float spelling
reuses the canonical Zig formatter. Existing entrypoints retain their signatures.
Additive helpers are `myl_core_buffer_append_i64(ptr, i64) -> ptr`,
`myl_core_buffer_append_f64(ptr, f64) -> ptr`, and the implementation-only
`myl_core_buffer_append_spelled(ptr, ptr, u64) -> ptr`. The prefix-reserve LLVM
helper is internal to generated code, with ordinary C convention.

The explicit shared checker change prevents a scalar repeat count from lending
its type to a list literal or comprehension. Both repetition operand orders
and contextual `list[u8]` constructors use the existing old/new lowering.
The final fresh old compiler SHA256 is
`abce00c53bb842b475b19c0815209207e89a859faebfc0714edd8d9d6b49049b`;
it includes this shared checker and was built in Debug from `3c86c3122`
(command 00189). Expanded fixture conformance and the dynamic repeat supplement
use its immutable copy, documented with core and tool hashes in
`final-frozen-source-v3.json`. The earlier `8923ce3f1` fresh old was
`5f9fd4599bb8de25c7db51de8191e5724026a5dcc49603dfd7221d41a0c6e460`.
Earlier
fixture supplements used the retained fresh checker binary with SHA256
`29a8662e86f113341f5f71c9c4fce5686481b4aa8fea223be47788f027797dbe`. Unchanged row/fuzz corpora use the pinned corrected-ENV
S3 oracle `d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79`.
See the source/compiler manifests for exact identities.

Commands run through `run.py` retain one unique command receipt each. Initial
trial failures and measurements remain intact. Commands 00001–00024 predate the
runner's separate stdout staging fix; their JSON command receipts remain exact,
but some very large positional stdout logs were incomplete. Later receipts stage
stdout separately before assembling a complete log. Preliminary nested wrappers
also lost the outer FD9 gate lock; their outcomes are explicitly preliminary.
Final qualification uses a retained bash gate wrapper, CPU10 timing flock and
one shared lock around the entire old or fuzz matrix. A queued first final
qualification was cancelled before execution when the grid target still missed.

The prior all-46 sweep (`final-all46-v1.json`, summarized in
`performance_summary.json`) passed both gates at both sizes, with seven
interleaved CPU10 rounds and zero gate exceptions. All available arm checksums
agree. The maximum new/old ratio is 1.0493 and maximum new/Zig ratio is 1.0907.
The immutable measured compiler copy is described in `immutable-core-d4.json`.

| Row/size | new / old | new / Zig |
| --- | ---: | ---: |
| grid_dp / 4096 | 0.686 | 0.982 |
| grid_dp / 64 | 0.232 | 1.028 |
| union_find / 4096 | 0.523 | 1.057 |
| union_find / 64 | 0.391 | 1.032 |
| float_format / 4096 | 0.579 | 0.747 |
| float_format / 64 | 0.571 | 0.747 |
| buffer_write / 4096 | 0.785 | 0.673 |
| buffer_write / 64 | 0.799 | 0.687 |

Prior additional receipts: `final-rows-leak-verify-v1/summary.json` records
46 rows and 414 native comparisons in debug/release/verified release at sizes
2, 64 and 4096, with blank leak stderr. `final-independent-oracles-v1/summary.json`
records all 210 independent probes. `final-supplement-v2/summary.json` records
25 direct old/new fixture runs, including dynamic repetition under the freshly
built old checker. The uncontended install component of
`final-core-conformance-v2` completed in 0.02 seconds with every build slot held;
the subsequently queued test step was cancelled, so that composite attempt is
not a complete correctness receipt. These measurements predate the counted-fill
repairs and are being rerun for the corrected compiler; they are historical
rather than final package qualifications.

The final unfiltered compile preflight (command 00185) passes in 2.1126 seconds; it compiles every test without executing it. The final whole-tree Guardian run (command 00209) passes all 88 checks. The full old gate
in `final-full-old-v2` passed at `be7978a37`, but it predates the two final test
repairs and is retained as a historical receipt rather than an exact final gate.
The first strict matrix attempt was cancelled before any cases; the second
strict matrix attempt refused a changed fresh-old executable hash before any
cases, preserving the oracle guard.

Corrected source 3c86c3122 passes all 279 core tests in 64 shards in 157.28 seconds; the longest shard is 57.88 seconds and maximum test RSS is 259 MiB. Full conformance matches 1518/1518 tests in both debug and verified release with leak checks in 171.27 seconds. Supplement-v6 records 25/25 exact-compiler native value comparisons. The protected functional compiler SHA is db0fb54873a05c0a7203a6933510c762d260c8da09ab8bc8ee7fb4815165b3d1.

The actual source-identical native Debug rebuild took 4.4463 seconds on CPU10 while all three build slots and the gate lock were held (final-rebuild-v1.json). Its rebuilt Debug ELF has a different hash, 47948b7a, and is retained separately. An objcopy section-inspection command rewrote the installed ELF; the immutable qualified compiler and private rebuilt artifact remained intact. Failed inspection, pure read-only section comparison and restoration receipts are retained. Installed Core was restored from protected db0, and all final row/fuzz invocations name that protected functional compiler explicitly.

The exact frozen full old gate (`final-full-old-v3/summary.json`) passes:
3004 tests, 520 QBE tests, 29 QBE build steps and format checks. Its source-at-gate
is `d6c52c86b`, whose frozen compiler/spec/test inputs match `3c86c3122`.
The old suite took 942.34 seconds, QBE tests 89.33 seconds, QBE build 3.59 seconds
and formatting 0.24 seconds, excluding admission.

Final performance (`final-all46-v2.json` and `performance_summary_v2.json`)
passes both 1.10 gates at both sizes for all 46 rows. Seven CPU10 rounds use
interleaved arms; all available checksums agree. Maximum new/old is 1.06270 and
maximum new/Zig is 1.09061. The compact summary records all 118 native binary
hashes; `final-performance-artifacts-v2/` archives 46 emitted LLVM files and
110 build logs. Failed archive attempts 00233 and 00237 misidentified shared
reference dispatcher arguments; their unchanged partial copies and receipts
remain alongside the completed archive.

| Row/size | new / old | new / Zig |
| --- | ---: | ---: |
| grid_dp / 4096 | 0.696 | 0.985 |
| grid_dp / 64 | 0.233 | 1.033 |
| union_find / 4096 | 0.523 | 1.056 |
| union_find / 64 | 0.391 | 1.031 |
| float_format / 4096 | 0.580 | 0.745 |
| float_format / 64 | 0.571 | 0.748 |
| buffer_write / 4096 | 0.787 | 0.671 |
| buffer_write / 64 | 0.798 | 0.687 |

`final-rows-leak-verify-v2/summary.json` passes all 414 native comparisons:
46 rows at sizes 2, 64 and 4096 in debug, release and verified release, with
blank leak stderr. `final-independent-oracles-v2/summary.json` passes all
210 independent probes for the six registered S4-R rows across all five arms.
Both use the exact qualified `db0fb548` compiler's measured or generated output.
The final strict matrix (`final-fuzz-v3/summary.json`) passes all eight kinds
with 50 accepted cases each: values, RC, rebinding, functions, S1, dictionary,
number and iteration. It completes 5700 native comparisons with zero rejected,
refused, build-failed, mismatching or fact-failed cases. The full matrix took
1612.8779 seconds; no full old gate overlapped it. Compiler hash guards pass
before and after the matrix. The custom values generator uses the existing
functions harness interface, so its per-kind summary retains `kind: functions`;
the `values/` directory, explicit harness argument and matrix result identify it.
The custom group uses the fresh shared-checker old compiler; the seven unchanged
groups retain the corrected-ENV S3 oracle and their original seeds.

S4-E's reduced native bounds/assert/overflow tests disclose a real Release trap
provenance bug in the consuming-mut CFG inliner. Old and S3 retain
`leaf::origin` and `app::main` frames; V Release retains only `app::main` at the
cloned leaf span. Debug retains separate functions. The reducer used historical
V `d4d8c4e56`, Core SHA `3c86ebb5`; `inline_cfg.zig` is byte-identical to final
V `3c86c3122` (SHA `23ee2cd1402eb3768a081fdc83d7f46d39c6b042f3df6bd4bc9e8614d348f0c5`).
Its 24 native builds/runs and exact output are copied without modification in
`provenance-reference-receipts/`; `provenance_integration_blocker.json` records
the attribution and qualification limit. The green standard gates above do not
establish correct callee trap frames for this case. The coordinator assigned
sparse provenance outside the frozen IR to the combined S4-E repair; V remains
frozen while that repair is implemented and qualified. S4 integration cannot
pass until the native trace reducers and combined gates pass.

`final_package_report.json` checks every completed receipt and frozen tool/input
hash and records the standard package gates as passed while retaining the native
provenance blocker. Guardian feedback was appended without altering prior entries
and committed in `guardian-zig` as
`2a926a0b44f6fe7b394b91dfef9bc9f2e536f674`; `guardian-feedback-commit.json`
records the before/after file hashes and commit. Every package evidence commit
also passes all 88 Guardian checks.

`ports_recipe.md` and `ports-lox-inventory.json` contain read-only S4-P preparation.
They preserve the ordinary directory and explicit provider commands, distinguish
65 unique Lox tests from repeated executions, and document warm orphan-test
skip/provider behavior for investigation after C/M integration. No protected
port or EDA original checkout was edited.
