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

/// The independently gated named byte-ceiling module.
pub const memory_budget = [_][]const u8{"src/memory_budget.zig"};

/// `src/root_test.zig`, the unit root. Its guest programs also read the
/// runtime sources the compiler embeds, which `src/` covers.
pub const unit = [_][]const u8{
    "src/",
    "bench/parity/micro/dict_count.my",
    "bench/parity/suite/knucleotide.my",
    "tests/lang/rc_dictionary_keys.my",
    "tests/lang/rc_dictionary_loops.my",
    "tests/lang/rc_dictionary_text_loops.my",
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
    "src/",
    "examples/",
    "tests/guest/",
    "test/fixtures/",
};

/// `test/golden_parity.zig` (`test-golden`): the golden corpora and the
/// repository fixtures their entries name.
pub const golden = [_][]const u8{ "src/", "tests/goldens/", "examples/", "test/fixtures/" };

/// `tests/idiom_probes.py --compiler`: the probe corpus and its manifest.
pub const idioms = [_][]const u8{ "tests/idiom_probes.py", "tests/fixtures/idioms/" };

/// `tests/incremental_diff.py`: the mutation walk and its fixture project.
pub const incremental = [_][]const u8{ "tests/incremental_diff.py", "tests/fixtures/incremental/", "tests/fixtures/module_projects/" };

/// `tests/interface_diff.py`: the interface-hash mutation walk and its fixture.
pub const interfaces = [_][]const u8{ "tests/interface_diff.py", "tests/fixtures/interfaces/", "tests/fixtures/interfaces_generic/" };

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

/// Juice's isolated runner, format, comparison and calibration tests.
pub const juice = [_][]const u8{ "tests/test_juice.py", "tests/test_juice_native.py", "scripts/juice", "scripts/juice_tool/", "scripts/juice_validate.py", "examples/juice/" };

/// `mylang doctest .`: every page it walks.
pub const doctest = [_][]const u8{ "README.md", "SPEC.md", "docs/**/*.md" };

/// `tests/test_affected_tests.py`: `scripts/affected_tests.py`'s mapping,
/// pinned on a synthetic repository it writes itself.
pub const affected = [_][]const u8{
    "scripts/affected_tests.py",
    "scripts/focused_test.py",
    "tests/test_affected_tests.py",
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

/// `tests/input_manifest.py --self-test`.
pub const manifest_self = [_][]const u8{"tests/input_manifest.py"};

/// Isolated CLI cache, frame-diagnostic and guest-address-space probes.
pub const tooling_isolation = [_][]const u8{"tests/tooling_cache_isolation.py"};

/// The bootstrap lexer source and live-compiler numeric extent oracle.
pub const selfhost_numeric = [_][]const u8{"selfhost/"};

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
