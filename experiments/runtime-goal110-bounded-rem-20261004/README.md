# Bounded floor-remainder bias, 2026-10-04

Production source `5e97db47f08f667d97419abafd098df263a2aec3`, based on accepted
`6cf7bdce11bc205862bf75b9d9ce72e46caad0a2`, remains unintegrated. The coordinator
requested an LLVM-only successor because this version repeats an approximately
12% QBE nested-large cost. This archive preserves the original source,
validation, static receipts and exploratory timings; no goal confirmation or
new goal pass is claimed.

The old final guard supplies `M = coefficient * 2^(bits * degree)`. Checked
u128 calculation requires `M <= MAXi64`, `B = d * ceil(M/d)` and
`M + B <= MAXu64`. For every admitted `-M <= x <= M`, adding B with wrapping
bit semantics gives the unsigned representation of mathematical `x+B`, and
`floor_mod(x,d) = unsigned_rem(x+B,d)`. Only positive literal flooring divisors
are eligible; powers of two and truncating remainder keep their old recipe.
For the append expression, M is 8646911284551352320 and B is
8646911284551353149 for divisor1009.

Metadata attaches after the previous plan's finish. Every nonconstant proof
leaf must already be bounded by that guard and privately owned. Optional
unsupported, missing-leaf, overflow, cap or privacy refusals preserve the old
signed plan; privacy refusal replans once with optional metadata disabled.
There is no extra clone, new guard or per-iteration sign decision. Magnitude
and privacy work each have a shared262144-node budget, with4096 function/node
caps. The analysis arena owns abandoned plans; allocation-failure replay
covers the valid moved-scalar refusal path.

The compiler host is explicitly Debug. All guests retain ordinary ReleaseFast
backend policy; LLVM uses O3/fullLTO. The G4 control host is ReleaseFast and its
guests are reused without modification. The initial canonical Zig invocation
path was rejected by frozen reference identity checks; the preserved retry
uses the original invocation path, without relaxing policy. The supplementary
before-guests are verified immutable G4 artifacts from the earlier diagnostic.

Validation passed57 focused tests,720 fresh qualification cells,516 holdouts,
38 complete QBE-executed native pairs and18 actual LLVM accounted/unaccounted
pairs. The latter include B>MAXi64, exact dividend endpoints±M, positive and
negative admission, short/empty loops, prior output, checked overflow and
first heap refusal. Four unit pairs use LLVM scalar policy executed by QBE;
they are explicitly distinguished from actual LLVM ELF executions. Raw
streams, exit status, structured trap detail and every frame are retained.

Guardian passed88 source checks, and the source commit hook confirmed cached
green. Initial source-gate findings were fixed through helper documentation,
the explicitly supported file-scope test logging alias, shared literals and a
multiline fixture. Policies are unchanged. The initial overbroad test-region
assertion, module-name rejection and wrapper-prefix comparison rejection are
retained. Zig printed a misleading failed-command line beside PASS even
though the final process exited0; the actual exit and test counts were checked.

The actual LLVM append remainder region falls from15 to7 instructions; QBE
falls from21 to9. LLVM hoists the bias before the loop. Both saved policies'
normalized guards and original fallbacks are identical. Batch/.text sizes are
52552/295746 ->52057/295234 for LLVM and133468/420214 ->133356/420070 for QBE.

The initial5r1w matched LLVM effects are filter small/large0.9409/0.9236 and
sort_int small0.9479. The independent15r3w repeat gives0.9401/0.9256 and0.9482.
Append stays approximately unchanged. Nested LLVM remains approximately1.0.
QBE nested-large repeats1.1252 then1.1199. The signed supplementary kernel
improves LLVM negative small/large0.9523/0.8582, removing the earlier27de
negative-admission blocker in this screen. Its unchanged100000 iteration cap
preserves negative endpoints; small samples are cap-limited. These are
exploratory measurements outside normal acceptance policy.

The QBE diagnosis is more specific than address-only equivalence: all2648
nested-arm instructions retain their arithmetic/register sequence and byte
lengths, but1060 stack-address references move and the batch frame grows16
bytes. Only generated batch_result and main change among403 named functions;
the401 other functions and nested direct native-call closure retain normalized
instructions. A frame/placement interaction is a hypothesis; this receipt does
not prove a microarchitectural cause or compare external shared-library bodies.

`archive-index.json` binds every gzip archive to its original raw bytes and
path. Eleven production-source snapshots and the exact6cf-to5e patch preserve
the candidate independently of the checkout receiving this archive. Offline
verification checks those snapshots; live verification checks the source root
bound by the pinned compiler receipt. `verify-archive.py --live` replays raw
identities, all48 six-arm groups, saved paired samples/intervals and live
artifact bindings. Static helpers use read-only
objdump/nm/readelf; they never rewrite an input ELF. Timing plans and helpers
are separate files, preserving the already pinned initial helpers unchanged.
