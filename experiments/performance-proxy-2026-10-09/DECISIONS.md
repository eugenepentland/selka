# Decisions — general-purpose performance proxy

- Start `codex/performance-proxy` at completed P1 `a79413c3f` in an isolated
  worktree. Do not push or merge into main. No compiler/front-end/IR change is
  needed: native executable measurements and a mylang adapter supply the layers.
- Keep the tool in Python developer scripts, outside the installed compiler's
  Python-free build graph. Register integrity tests in `zig build test-juice`
  and the full gate, with declared cache inputs and affected-test selection.
- Juice v1 means instructions per completed application unit, baseline 100.
  Semantic counts, static sites/bytes, allocator-dependent footprint and atomic
  events remain distinct. They are never added together with arbitrary weights.
- Use task-scoped user instruction counts on one non-reserved CPU. Explicit
  PMU selection is necessary on this host's hybrid CPU. Reject uncounted,
  multiplexed or scaled events; do not wait for an idle host.
- Use software instruction counting only on bounded scenarios. Valgrind 3.26
  was unpacked from Ubuntu's package into a user cache to validate the optional
  collectors; no system package or repository dependency was installed.
- Capture in stable private build/run paths, with a fresh run directory for
  every ordinary, counted and software-instrumented execution. Retain incomplete
  attempts and immutable raw evidence; compare normalized semantic output and
  declared artifacts, not elapsed output fields or label-dependent paths.
- Version runtime hook meanings separately from the counter JSON format. The
  pre-P1 and P1 retain counters have different coverage. Suppress those semantic
  comparisons while retaining optimized instruction comparisons.
- Treat added/removed link dependencies as a program change (P1 adds a pthread
  dependency), report the change and its costs. Reject changed contents of a
  shared library present in both arms. Discover libraries for the staged binary
  under the actual runtime environment, including its `$ORIGIN` location.
- Default to a 0.1% material-change floor and a 0.5% repeat spread limit. Native
  startup can vary by a few instructions. Keep raw counts and repeat envelopes;
  the envelopes are observations, not confidence intervals.
- Validate short/large agreement instead of asserting it. The first native
  fixture (16 versus 128 rounds) disagreed by 5.4% on the ratio for a large
  algorithm improvement, because startup dominated the faster short case.
  Increase repetitions with the same data shape; retain that rejected example.
- Callgrind region profiles can omit trailing zero events in summary/totals.
  Parse them as zero, reconcile totals to self costs and exclude inclusive call
  arcs. Register-only `xchg` padding is not an atomic memory operation.
- Calibration accepts only explicit independent paired timings tied to exact
  comparison identities, with disjoint training/validation families and an
  error/direction gate. No production runtime model is claimed validated by
  instruction-count qualification or by synthetic calibration tests.
- Reclaim only the completed P1 worktree's generated `.zig-cache` after checking
  no process uses that tree. The shared disk had fallen to 5 GiB free; the new
  worktree needs its own cache for the required full gate.
- The first full gate passed. A later cached recheck hit `No space left on
  device` while other builds used the shared workspace filesystem. Reclaim
  completed P1's generated unit-test/runtime/language-test caches, retain its
  concurrency evidence and benchmark caches, and move this task's gate TMPDIR
  to its own directory on the home filesystem (179 GiB available at recovery).
  Retain the failed log and rerun; never count the disk failure as a pass.
- Integrate all six Juice commands into the compiler as native Zig modules. Keep
  Python solely as a developer reference and differential-test oracle; no script,
  checkout or interpreter is an installed runtime dependency. Resolve a mylang
  adapter's default compiler to the running executable.
- Preserve v1 record/report schemas, but name the native canonical JSON identity
  domain explicitly. Reuse existing raw captures; regenerate comparison identity
  fields through the native command instead of claiming Python/Zig float/JSON
  serializations are byte-identical.
- Keep platform process/collector/inventory code separate from contract and report
  logic. Implement only Linux x86_64 capture now; document future ARM, Windows and
  macOS capability adapters and a separate LLVM work-count fallback.
- Accept the documented TOML manifest forms and equivalent JSON. Fail explicitly
  on unsupported TOML constructs or advanced normalization regex; a bounded byte
  normalizer avoids an interpreter/host-regex dependency. Custom oracle commands
  handle advanced validation without silently changing normalization semantics.
- Move only this worktree's generated Zig and guest caches to task-specific home
  filesystem directories, retaining their workspace paths as ignored local
  symlinks. This avoids another shared-workspace disk exhaustion during the gate.
- Reuse the compiler's existing embedded source/toolchain/optimization identity
  for the native Juice implementation key, matching the original source-based
  Python implementation key. Keep executable SHA-256 for an external guest
  compiler; the running compiler uses an explicitly labeled embedded-build
  identity (`source_sha256`). Avoid repeatedly hashing the 156 MiB Debug host on
  every edit-loop capture. The independent artifact SHA-256 checks still read
  every byte, including final partial buffers.
