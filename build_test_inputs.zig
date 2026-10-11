//! Repository files that cached test steps read while they run.
//!
//! A `zig build` Run step is re-executed only when something in its cache key
//! changes: its arguments, its environment, the artifacts it names and the
//! files declared as its inputs. A test binary that opens a fixture, or a
//! Python driver that compiles every probe under a directory, reads files the
//! build system cannot see, so each such step names a list here. On every build
//! `tests/input_manifest.py` expands each list and writes one content manifest
//! per list, and the step declares that manifest as its input: an edited, added,
//! removed or renamed file changes the manifest and re-runs the step. Every
//! `pub` list below is passed to it; a step names its list by the constant's
//! name.
//!
//! Entry syntax:
//! - `dir/` — every file under `dir`, recursively;
//! - `dir/*.ext` — the files directly in `dir` whose names end in `.ext`;
//! - `dir/**/*.ext` — every file under `dir`, recursively, ending in `.ext`;
//! - anything else — one file, which must exist.
//! Hidden entries, `__pycache__` and `*.pyc` are never inputs.
//!
//! The lists were measured by tracing every `open`/`stat` the steps made
//! (`strace -f`, see `docs/audits/test-loop-speed-2026-09-23.md`) and are
//! checked on every gate by `tests/test_inputs_coverage.py`, which fails when a
//! test source names a repository path no entry covers. When a test starts
//! reading a new file, declare it here; `-Dtest-rerun=true` re-runs every cached
//! test step regardless.

/// Complete independent tooling test implementation closure; no live fixtures.
pub const tooling_unit = [_][]const u8{
    "src/tooling_root_test.zig", "src/doc_coverage_test.zig", "src/doc_coverage.zig",
    "src/input_probe_test.zig",  "src/input_probe.zig",       "src/fix_plan_test.zig",
    "src/fix_plan.zig",          "src/timings_test.zig",      "src/timings.zig",
    "src/invalidation_test.zig", "src/invalidation.zig",
};

/// The independently gated named byte-ceiling module.
pub const memory_budget = [_][]const u8{"src/memory_budget.zig"};

/// `src/root_test.zig`, the unit root. Its guest programs also read the
/// runtime sources the compiler embeds, which `src/` covers.
pub const component_inputs = [_][]const u8{ "selfhost/components/", "selfhost/*.zig", "selfhost/component-seed.json" };

pub const unit = [_][]const u8{
    "selfhost/components/",
    "selfhost/*.zig",
    "selfhost/component-seed.json",
    "src/",
    "bench/parity/micro/dict_count.my",
    "bench/parity/suite/knucleotide.my",
    "tests/lang/rc_dictionary_keys.my",
    "tests/lang/rc_dictionary_loops.my",
    "tests/lang/rc_dictionary_text_loops.my",
    "tests/lang/memo_cache.my",
    "test/fixtures/",
    "test/core/c_environment_context.my",
    "test/core/c_environment_context_provider.c",
    "test/core/c_runner_properties.my",
    "test/core/c_runner_failures.my",
    "test/core/c_runner_standins.my",
    "test/core/c_runner_signal.my",
    "test/core/c_runner_state_capture.my",
    "experiments/new-core-s3-20261006/wave-b/s3-runner/c_runner_signal.c",
    "experiments/new-core-s3-20261006/wave-b/s3-runner/c_runner_exit.c",
    "docs/reference.md",
    "docs/standard-library.md",
    "velocity/friction/",
};

/// `test/integration.zig`, the CLI root: project examples, the guest suite
/// fixture and the compiler's own sources.
pub const cli = [_][]const u8{
    "selfhost/components/",
    "selfhost/*.zig",
    "selfhost/component-seed.json",
    "src/",
    "examples/",
    "tests/guest/",
    "test/fixtures/",
};

/// Conservative fixtures and embedded runtime inputs for the complete Core root.
pub const core = unit ++ [_][]const u8{
    "test/", "tests/", "examples/", "bench/", "benchmarks/", "selfhost/", "velocity/",
};

/// Document navigation and complete feature/standard-library coverage scope.
pub const doc_coverage = [_][]const u8{ "README.md", "SPEC.md", "docs/", "src/" };

/// Every Zig file selected by the normal format gate, including new files.
pub const zig_format = [_][]const u8{
    "build.zig",    "build_identity.zig", "build_test_inputs.zig", "build_verification.zig",
    "src/**/*.zig", "tests/**/*.zig",     "test/**/*.zig",         "selfhost/**/*.zig",
};

/// `test/golden_parity.zig` (`test-golden`): the golden corpora and the
/// repository fixtures their entries name.
pub const golden = [_][]const u8{ "selfhost/components/", "selfhost/*.zig", "selfhost/component-seed.json", "src/", "tests/goldens/", "examples/", "test/fixtures/" };

/// `tests/idiom_probes.py --compiler`: the probe corpus and its manifest.
pub const idioms = [_][]const u8{ "tests/idiom_probes.py", "tests/fixtures/idioms/" };

/// `tests/incremental_diff.py`: the mutation walk and its fixture project.
pub const incremental = [_][]const u8{ "tests/incremental_diff.py", "tests/differential_corpus.py", "tests/fixtures/incremental/", "tests/fixtures/module_projects/" };

/// `tests/interface_diff.py`: the interface-hash mutation walk and its fixture.
pub const interfaces = [_][]const u8{ "tests/interface_diff.py", "tests/differential_corpus.py", "tests/fixtures/interfaces/", "tests/fixtures/interfaces_generic/" };

/// `tests/interface_oracle.py`: the per-module check oracle over `tests/lang`
/// and the interface fixtures.
pub const interface_oracle = [_][]const u8{
    "tests/interface_oracle.py",
    "tests/lang/",
    "tests/fixtures/interfaces/",
    "tests/fixtures/interfaces_generic/",
    "tests/fixtures/incremental/",
};

/// `tests/idiom_probes.py --self-test`: the CPython oracle only.
pub const idioms_self = [_][]const u8{"tests/idiom_probes.py"};

/// `tests/parser_hints.py`, static and against the compiler.
pub const parser_hints = [_][]const u8{
    "tests/parser_hints.py",
    "src/parser.zig",
    "velocity/friction/",
    "velocity/suites/idioms/",
};

/// `tests/test_friction_harvest.py`: the harvester and its replay fixture.
pub const friction = [_][]const u8{ "tests/test_friction_harvest.py", "velocity/friction/" };

/// Synthetic contracts, parsers, reports and calibration; retain the complete
/// imported package closure and its membership, including CLI/engine imports.
pub const juice_pure = [_][]const u8{ "tests/test_juice.py", "scripts/juice_tool/" };

/// Juice's live runner and native collector integration tests.
pub const juice = [_][]const u8{ "tests/test_juice.py", "tests/test_juice_native.py", "scripts/juice", "scripts/juice_tool/", "scripts/juice_validate.py", "examples/juice/" };

/// Runtime collector experiments observe CPU, scheduler and current host state.
pub const juice_runtime = [_][]const u8{ "tests/test_juice_runtime_bench.py", "scripts/juice_tool/", "scripts/juice_runtime_bench.py" };

/// `mylang doctest .`: every page it walks.
pub const doctest = [_][]const u8{ "README.md", "SPEC.md", "docs/**/*.md" };

/// `tests/test_affected_tests.py`: `scripts/affected_tests.py`'s mapping,
/// pinned on a synthetic repository it writes itself.
pub const affected = [_][]const u8{
    "scripts/affected_tests.py",
    "scripts/focused_test.py",
    "tests/test_affected_tests.py",
    "tests/test_focused_test.py",
};

/// `tests/test_inputs_coverage.py`: this file and every Zig test source the
/// cached roots compile.
pub const coverage = [_][]const u8{
    "tests/test_inputs_coverage.py",
    "build_test_inputs.zig",
    "src/**/*.zig",
    "test/**/*.zig",
};

/// `tests/test_inputs_coverage.py --self-test`.
pub const coverage_self = [_][]const u8{"tests/test_inputs_coverage.py"};

/// Receipt admission and immutable-snapshot adversarial tests use fake actions.
pub const verification_cache = [_][]const u8{
    "scripts/cache_session.py",
    "scripts/fuzz_campaign_store.py",
    "scripts/verify_cache.py",
    "scripts/verification_snapshot.py",
    "scripts/verification_process.py",
    "scripts/verification_process_test.py",
    "scripts/verification_report.py",
    "scripts/verification_budgets.py",
    "scripts/verification_report_test.py",
    "scripts/verification_budgets_test.py",
    "scripts/verification_artifacts.py",
    "scripts/verify_cache_test.py",
    "scripts/verification_snapshot_test.py",
    "scripts/build-slot.sh",
    "tests/test_inputs_coverage.py",
};

/// Persistent coordinator startup watches the complete developer implementation.
pub const verification_session = [_][]const u8{"scripts/"};

/// Independent fuzz shards, concrete replay, evidence and native-worker lifecycle.
pub const fuzz_campaign = [_][]const u8{
    "scripts/cache_session.py",
    "scripts/fuzz_campaign.py",
    "scripts/fuzz_campaign_identity.py",
    "scripts/fuzz_campaign_store.py",
    "scripts/fuzz_campaign_store_test.py",
    "scripts/cache_retention.py",
    "scripts/cache_retention_test.py",
    "scripts/prune-caches.sh",
    "scripts/fuzz_campaign_test.py",
    "scripts/fuzz_coverage.py",
    "scripts/fuzz_coverage_test.py",
    "scripts/verify_cache.py",
    "scripts/verification_snapshot.py",
    "scripts/verification_process.py",
    "scripts/verification_report.py",
    "scripts/verification_budgets.py",
    "scripts/build-slot.sh",
    "tests/differential_corpus.py",
    "tests/test_differential_corpus.py",
    "tests/incremental_diff.py",
    "tests/interface_diff.py",
    "test/fixtures/fuzz-campaign/",
};

/// `tests/input_manifest.py --self-test`.
pub const manifest_self = [_][]const u8{"tests/input_manifest.py"};

/// Qualified Juice evidence and admission tests use isolated simulated collectors.
pub const juice_cache = [_][]const u8{
    "scripts/cache_session.py",
    "scripts/juice_cache.py",
    "scripts/juice_cache_test.py",
    "scripts/juice_evidence.py",
    "scripts/juice_provider.py",
    "scripts/juice_provider_test.py",
    "scripts/juice_worker.py",
    "scripts/juice_worker_test.py",
    "tests/test_juice_evidence.py",
    "scripts/juice_tool/",
    "scripts/fuzz_campaign_identity.py",
    "scripts/fuzz_campaign_store.py",
    "scripts/verify_cache.py",
    "scripts/verification_snapshot.py",
    "scripts/verification_process.py",
    "scripts/verification_report.py",
    "scripts/verification_budgets.py",
    "scripts/build-slot.sh",
};

/// Isolated CLI cache, frame-diagnostic and guest-address-space probes.
pub const tooling_isolation = [_][]const u8{"tests/tooling_cache_isolation.py"};

/// The bootstrap lexer source and live-compiler numeric extent oracle.
pub const selfhost_numeric = [_][]const u8{"selfhost/"};

/// The independent component cache and qualification builder.
pub const component_builder = [_][]const u8{ "selfhost/*.zig", "selfhost/test_components.py", "selfhost/component-seed.json" };

/// Qualified-seed pure tests and native protocol oracle.
pub const component_native = [_][]const u8{ "selfhost/components/", "selfhost/*.zig", "selfhost/component-seed.json", "selfhost/test_component_native.py", "selfhost/tests/run_test_index_component.py", "selfhost/tests/run_cache_plan_component.py" };

/// The live .my formatting corpus, selection script and deliberate exclusions.
pub const my_format = [_][]const u8{
    "scripts/check_my_format.py",
    "scripts/my_format_exclusions.json",
    "bench/**/*.my",
    "benchmarks/**/*.my",
    "docs/**/*.my",
    "examples/**/*.my",
    "selfhost/**/*.my",
    "src/**/*.my",
    "test/**/*.my",
    "tests/**/*.my",
    "velocity/**/*.my",
};

/// Synthetic corpus selection and real formatter failure propagation.
pub const my_format_self = [_][]const u8{ "scripts/check_my_format.py", "tests/test_my_format.py" };

/// Embedded migration extraction, census evidence and atomic staging checks.
pub const embedded_migration = [_][]const u8{
    "scripts/migrate_embedded.py",
    "scripts/spelling_census.py",
    "tests/test_migrate_embedded.py",
};

/// All live sources and selection policy read by the allocation-contract lint gate.
pub const noalloc_lint = my_format ++ [_][]const u8{"scripts/check_noalloc.py"};

/// Persistent application records, native provider failure and crash recovery driver.
pub const application_cache = [_][]const u8{ "tests/application_cache.py", "test/fixtures/application-cache/", "src/" };
