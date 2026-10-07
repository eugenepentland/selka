# S4-M implementation and qualification state

The pre-V implementation is frozen at `25d9e9531` after the bounded unwind
dependency correction; its initial production checkpoint is `7bc4a745f`, based on S4-F corrected
production checkpoint `7877aa5d369f57aeb8fb850e8198c08c520b3a51`. Final combined
package qualification is still pending. Negative runs remain evidence, never
successful gate receipts.

Project entries use strict shared configuration and policy/interface handling,
separate import and embedded-asset roots, and explicit refusals for unsupported
legacy sharing or configured frame/memory bounds. Source budgets and configured
step limits are enforced before execution.

Directory discovery inventories every source, follows actual project closures,
and includes mains, standalone test entries and orphan libraries. Every declaring
source must appear in a checked child inventory. One bounded worker budget covers
directory and trial workers. Inputs are inventoried and hashed again after workers
finish, so edits, additions and deletions cannot publish successful receipts.
The parent snapshot also covers imports outside the selected directory, distinct
provider closures, embedded assets, configuration/policy bytes, cases and required
API presence or absence, and each entry's resolved project location. The original
external dependency race accepts a stale cached child; corrected-run02 rejects
that exact race with SourceChanged after the cached child finished. Its installed
run12 compiler SHA256 is
`ae95edc2e2d473fe052810345335e3558ad553b325bd0394af48c39ceafcaf98`.

Provider fixtures use exact existing dependency paths and canonical discovered
test names. Replacements preserve both exported layouts and types reachable from
private test roots through the existing checked native-facts schema API; this API
reads checked facts and never invokes old lowering or the native driver. Provider
imports and embedded assets are included in dependency capture. Explicit arguments,
expectations, reasoned skips and invalid inputs are checked rather than ignored.

Successful result receipts include actual reachable LLVM, schema/adapters, limits,
seed/runs, compiler/runtime identity, configuration/policy/cases and environment.
Manifests only replay unchanged dependency bytes. Force/leak/fact verification
executes trials. Native external links and mutable loader environment bypass reuse
until a complete dependency proof exists. The shared tool helper captures complete
guest Zig content, the adjacent library and explicit library override, and native
CPU identity. Scripts and tools with an unproved dependency closure bypass reuse.
Its checksummed content memo still rechecks file generations, including ctime.

A directory parent lends this identity to the same compiler's children through
invocation-owned stdin files. Children verify parent provenance, executable
generation and CPU before read-only manifest replay. A miss discards the ticket
and establishes a full local identity before checking, building or publication.
The parent rechecks all tool generations after children and refuses the aggregate
on any change. The private hint is omitted from receipt keys and removed from
native guest environments. Local warm replay first buffers an untrusted candidate,
validates the complete tool generation, then revalidates dependencies before
accepting the buffered success. The static-delegate counterexample demonstrates
that ELF structural checks cannot prove a tool's dependency closure. Eligibility
now requires the reviewed executable and complete normalized library content;
unknown tools execute without persistent reuse. Native compilation explicitly
uses the bundled `x86_64-linux-gnu.2.31` headers and link inputs. The reviewed
default loader, libc, libm, libgcc, libpthread and loader-cache content also enter the captured tool
generation; unsupported runtime or environment closures bypass reuse. No system
input was modified. The inventory, generation, approval and CPU-policy domains
are v2 except inventory hints, now v3. The v3 hint key also includes every
expected runtime descriptor, so an older inventory cannot omit a newly reviewed
dependency. The opaque content-memo codec remains v1.

Execution outputs use invocation-owned directories and stable semantic helper
names. Focused run07 exposed the inherited fixed runtime-object partial race when
two directory children compile a cold runtime. The reduced fixture and scheduling
barrier precede backporting E's owned atomic publication helper. The original
focused receipt remains red. Focused run08 passed 22 tests and run09 passed 27;
the barrier reducer passed with run09's actual test artifact in corrected-run04.
Corrected-run03 used a stale installed binary and is retained as an unqualified
failed attempt. Focused run12 passes all 42 selected tests; its unfiltered preflight
also instantiates every test body successfully.
Final pre-V focused run14 passes all 48 project/helper tests in 125.64 seconds,
with zero failures or skips. The separate Guard/native-number run14 passes 6
tests in 94.62 seconds. Refreshed unfiltered preflight14 instantiates every test
body in 1.925 seconds using the actual named-module build recipe. These are
focused/preflight checks, not the full core or rebuild qualification gates.

The retained tool-publication-reduced-run02 observes both runtime and numeric
objects left published under a captured tool key after a private library input
changed during compilation and the command refused with SourceChanged. Both
native reducers precede the new per-object publication guards. Each object is
staged privately, validates the captured tool before its rename, and leaves no
partial on failure; numeric staging now also uses an invocation-owned random
nonce. Runtime object identity is full BLAKE3 with domain v2, and numeric objects
use the number-tool-v2 namespace, so earlier unsafe keys cannot be reused. The
final link guard remains. Fresh corrected-run03 copies the complete reviewed
library into an owned fixture, changes an input during each real compilation,
and observes refusal with no shared runtime or numeric object published under
the previous key (71.34 and 78.82 seconds). Its installed compiler SHA256 is
`67ad628f8743dd803c81bbd071f5c3e7816ff2977ad44bb10c52bb4e36672906`;
the retained production source hashes match initial checkpoint `7bc4a745f`. Earlier
negative receipts remain untouched.

Read-only bundled-target C and actual Core debug/release/numeric probes reveal
glibc's dynamically loaded `libgcc_s.so.1` unwinder; the C debug probe also loads
`libpthread.so.0`. Both exact files and their already captured ELF dependencies
are now reviewed inputs. The corrected helper passes 20 focused checks and all
88 Guardian checks, and its production probe inventories 20,907 inputs with
stable strict/candidate identities. Fresh installed Core SHA256 is
`2b79fc47b1c5c882d8fcc1c2b0b6fb0b909746b6f7752b4176f18ceac34328e0`.
The actual CLI smoke passes three directory tests cold and reuses all three
warm; strace observes only the parent and its two Core workers. Smoke elapsed
times include slot admission and are not qualification measurements.

Pre-V full-core run15 is a retained failed checkpoint, not qualification:
330/331 actual tests pass, with 20,853 shard skips; command wall is 440.616
seconds and the longest shard is 249.42 seconds. It ran beside other admitted
builds and exceeds the five-minute command target. The sole behavior failure is
the existing zero-trip list/record undef-phi fixture: expected exit zero, observed
232. Independent raw native diagnosis precedes any production correction. Final
combined qualification must resolve both this failure and the elapsed-time gate.

Copied propagation fixtures are byte-identical to tests/lang, which was not edited.
The focused CLI cases cover directory/orphan accounting, changed dependency versus
unaffected receipts, provider-only imports and embeds, provider public/private type
layouts, budgets, step/timeout bounds, import policy, stale generated interfaces,
nested entries and reserved embedded-module names. Failure-path unit tests cover
allocation failure, damaged receipts/manifests and source mutation.

After source freeze: full old gate, core64 under300 seconds, conformance with
retired arenas only and forced leak/verify execution, inherited strict50 kinds plus
50 generated project/provider comparisons and traced zero-child warm runs,
uncontended rebuild, all46 after qualified V, and both port inventories. Port
capability-field and assert-message repairs belong to S4-P after C and M merge.
