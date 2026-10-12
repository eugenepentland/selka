# Preserve record-loop writeback without weakening snapshot lifetimes

The existing ordinary-mode `ce_records_test` assertions still failed after the
ownership worklist and indirect-call fixes: `write_backs` and `pushes` each emitted
two 40-byte aggregate copies instead of zero. These tests build raw Core and emit
LLVM directly; they do not run `own.takeFields`. The failure therefore belonged
to memory-home planning, not ownership discovery.

The earlier snapshot safety fix made `fieldOrigin` use function entry for every
phi. For an exact loop writeback, this followed next-iteration and loop-exit reads
back through the previous loop body, preventing the child from living directly
inside its parent. The exact failing raw Core and LLVM are preserved in
`before-diagnostic/test-0.stderr`:

- `write_backs`: `%17 = phi(%10, %26)`;
  `%26 = record_set(%17, field1, %25)`.
- `pushes`: `%8 = phi(param0, %11)`;
  `%11 = record_set(%8, field1, %10)`.

The new exception recognizes only that bounded exact recurrence. Every incoming
parent must share the same home; an initial input must be a parameter or complete
record construction; every carried update must name the phi as its old parent,
write the exact field region and store the same candidate child home. Verified
SSA proves such a phi-dependent incoming update recurs after the header. The
predicate checks at most 64 incoming operands and performs no new CFG traversal.
The loop header then starts that iteration's field lifetime. Existing interference,
old-byte reads and writes still constrain embedding. Unproven joins, sibling-only
updates and ambiguous recurrences keep the conservative entry fallback.

The production patch is based on
`723d2281ae98df97cf1503ad21ad2c9b4336df0b`. Candidate SHA256:
`2e0c0386731c6ca4d8309b7b6673bc791609995d237e07a97017f3815c0a682f`.
Exact source/toolchain/component/compiler identities and commands are recorded
under `after/` and `a06-registered/`. Owned Support6 build helpers are an interim
component boundary, not final installed-package qualification.

Qualification passed:

- Entire `ce_records_test`: **10/10**, with the original zero-copy assertions
  unchanged. Both functions again emit zero aggregate memcpy/memmove calls.
- New readonly-parent, retained whole snapshot, different-field branch and
  later old-field-read controls retain necessary copies and preserve the output
  `509 5 509 92 2609` in ordinary debug, release and verified release.
- Both original A06 sibling-update snapshot tests: **2/2**, unchanged.
- Their three original source shapes: **21/21** native runs, covering five checked
  modes plus ordinary release/debug. All checked runs have RC0, exit-live managed
  bytes0 and clean emitted LLVM. Exact raw counters and hashes are in `native/`.

`summary.json` distinguishes aggregate copy instructions from heap allocation
traffic. This repair makes no measured runtime, RSS or compilation-speed claim.
Shared admission tickets: 1253 (initial broad-filter compile failure), 1255
(unmodified exact file), 1257 (raw diagnostic), 1278 (candidate record suite),
1280 (original A06 tests), 1284 (expanded native controls), 1298 (record suite
rerun after moving test plumbing into helpers), and 1300 (final reporter alias).

Guardian's first commit attempt rejected a test-level diagnostic conditional and
second top-level loop. Moving those into helpers preserves all assertions and
passes the full record suite again. The compiler binary hash is unchanged, so
the native matrix still names the exact final compiler. The prior test receipt
is retained in `before-test-plumbing/`; `guardian-test-plumbing.json` records the
rejection and correction.
The second hook required the standard file-scope reporter alias for that helper;
the final 10/10 receipt includes this correction, with the same compiler hash.

The initial broad `record` filter also selected an unrelated pre-existing cache
test error-set mismatch; that failed attempt remains in
`broad-filter-compile-failure/`. The file-qualified retry compiled normally and
reproduced both actual copy regressions. No original source, expected count or
historical result was discarded to obtain a passing result.
