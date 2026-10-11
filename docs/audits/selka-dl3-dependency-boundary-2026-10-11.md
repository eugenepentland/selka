# DL3 first dependency boundary and remaining audit

Date: 11 October 2026. Base: `fab77294a`. Scope: one reviewed Juice
boundary; this does not complete DL3 or establish a speed improvement.

The original `juice` cohort combined `tests/test_juice.py` with
`tests/test_juice_native.py`. The latter registration made the entire cohort
fresh. The Python filename did not imply purity: its `Runner` class compiles C,
executes workloads, inspects native tools/libraries, corrupts build outputs and
exercises a real timeout. Those checks remain in fresh `juice`, along with the
unchanged native collector script. `juice-runtime` also remains fresh.

The new `juice_pure` cohort runs Contracts, Parsers, Reports and Calibration:
29 tests using synthetic records, private temporary manifests/source/input files,
synthetic perf/Callgrind text, and synthetic timing evidence. Their invoked paths
do not collect live counters, compile code or run workloads. The symlink escape
check rejects a path outside its private root. CLI checks reject malformed options
before opening their placeholder paths. Module import still obtains affinity for
the unused fake collector and probes `cc` for the unused Runner decorator; these
are not used to determine the selected tests' assertions. Environment/tool identity
remains conservative.

`juice_pure` declares `tests/test_juice.py` and all of `scripts/juice_tool/`,
including CLI and engine imports, rather than pretending the imported implementation
closure consists only of report code. Recursive directory manifests retain added,
deleted and renamed package files. No prepared native artifact is consumed, so its
artifact provider list is explicitly empty. The original `juice` recipe remains
broad and is shared by both fresh actions. All actions remain under `test-juice`
and the complete gate.

`--pure` uses the reviewed class allowlist; `--native` discovers every other local
TestCase class. Added methods follow their owning class and a new class defaults
to fresh execution until reviewed. The ordinary no-argument invocation still
independently discovers the complete suite. This avoids silently losing new tests
through an explicit build-time list of fresh classes.

## Focused evidence

- Pure cohort: 29 tests passed; native Runner cohort: 9 tests passed.
- Independent unittest discovery: complete 38 equals disjoint 29 + 9 cohorts.
  Injecting a new TestCase class places its test only in the fresh cohort.
- `tests/test_inputs_coverage.py`: existing Zig-root named-path coverage passes.
  This static checker does not certify Python paths; the Python closure above
  was reviewed directly.
- `tests/input_manifest.py --self-test`: passed, including additions and missing
  explicit paths. An independent probe against the exact `juice_pure` recipe
  confirms module addition/rename changes its manifest, deletion restores it, and
  a missing explicit module path fails. Temporary probes were removed.
- Pinned Zig formatting and exported inventory checks were queued through build
  admission and cancelled before execution at the integration owner's request.
  They remain pending for integration qualification, along with the complete gate.

The direct Python durations are correctness observations, not admitted isolated
latency measurements or a before/after comparison. Splitting this small cohort
adds one process to a forced run; cold preparation still builds the existing native
artifacts. No cold or warm performance acceptance is claimed.

## Remaining invalidation and ranked follow-ups

1. Separate local group contracts from common inventory identity. The coordinator
   still binds common inventory/configuration/implementation/tool/environment keys.
   Adding this group therefore conservatively invalidates old receipts across
   groups. Coverage discovery must continue to account for every new action.
2. Audit `src/root_test.zig` for independent pure tooling roots before building
   them separately. `unit` binds all `src/`, component inputs and many fixtures;
   shards share a complete executable digest. A fixture-only list split cannot
   establish reuse when the single test executable changes. Measure duplicate
   compiler build cost before selecting root boundaries.
3. Audit Core runner/cache integration versus pure IR/pass checks. `core` inherits
   `unit` and adds complete `test/`, `tests/`, `examples/`, `bench/`, `benchmarks/`,
   `selfhost/` and `velocity/` trees. Core also deliberately requires fresh execution.
   Preserve native effects, corruption and cold controls during any later split.
4. Split CLI packaging/project checks from compiler integration only after tracing
   negative lookups and project directory membership. `cli` currently binds all
   sources, examples, guest fixtures and shared fixture trees and shares one binary.
5. Narrow independently built component producers only after a complete source,
   seed, protocol, runtime/ABI and tool closure is qualified with the self-host owner.
   Broad golden/component corpora are evidence consumers, not proof of narrower
   producer identity.

Whole-compiler identity remains unchanged and covers production source edits.
Normal Zig cached drivers still bind the compiler binary and component manifests;
empty coordinator artifact lists alone do not narrow those underlying Zig keys.
Full native test-binary digests, the common inventory/configuration/tools and shared
implementation keys remain broad invalidation sources. This first change makes a
real freshness boundary reviewable; it does not establish function-level reuse,
remove all compiler invalidation, or qualify the roadmap's end-to-end targets.
