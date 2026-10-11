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
    "scripts/verify_cache.py",
    "scripts/verification_snapshot.py",
    "scripts/verification_artifacts.py",
    "scripts/verify_cache_test.py",
    "scripts/verification_snapshot_test.py",
    "scripts/build-slot.sh",
    "tests/test_inputs_coverage.py",
};

/// Registry action coverage and qualified seed freshness policy.
pub const verification_registry = [_][]const u8{ "build_verification.zig", "build_test_inputs.zig" };

/// `tests/input_manifest.py --self-test`.
pub const manifest_self = [_][]const u8{"tests/input_manifest.py"};

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

/// Receipt-verified lexer qualification, pure tests, immutable corpus and driver.
pub const pilot_lexer = [_][]const u8{ "selfhost/test_pilots.py", "selfhost/components/lexer_pilot/", "selfhost/tests/fixtures/lexer_pilot/", "selfhost/tests/run_lexer_pilot.py", "selfhost/*.zig", "selfhost/component-seed.json" };

/// Parser qualification copies the complete production frontend oracle closure.
pub const pilot_parser = [_][]const u8{ "selfhost/test_pilots.py", "selfhost/components/parser_pilot/", "selfhost/components/lexer_pilot/", "selfhost/tests/fixtures/parser_pilot/", "selfhost/tests/run_parser_pilot.py", "selfhost/tests/run_parser_component.py", "selfhost/*.zig", "selfhost/component-seed.json", "src/", "tests/lang/", "tests/value_semantics/" };

/// Receipt-verified compiler-shaped pure tests and standalone driver.
pub const pilot_probes = [_][]const u8{ "selfhost/test_pilots.py", "selfhost/probes/compiler/", "selfhost/tests/run_compiler_probes.py", "selfhost/*.zig", "selfhost/component-seed.json" };

/// Adversarial pilot admission and directory-membership invalidation evidence.
pub const pilot_registration = [_][]const u8{ "selfhost/test_pilots.py", "selfhost/test_pilots_test.py", "build_test_inputs.zig", "tests/input_manifest.py", "tests/test_inputs_coverage.py" };

/// Installed frontend workflows and real coordinator edit qualification.
pub const frontend_qualification = [_][]const u8{"selfhost/"};

/// Adversarial checks of the frontend qualification driver's verdict accounting.
pub const frontend_qualification_self = [_][]const u8{ "selfhost/tests/run_frontend_qualification.py", "selfhost/tests/frontend_qualification_test.py", "selfhost/tests/fixtures/frontend_qualification/" };

/// Qualified declaration pure tests and installed workflow/protocol qualification.
pub const declaration_qualification = [_][]const u8{"selfhost/"};

/// Adversarial verdict accounting for declaration qualification.
pub const declaration_qualification_self = [_][]const u8{ "selfhost/test_declarations.py", "selfhost/test_pilots.py", "selfhost/tests/run_declaration_qualification.py", "selfhost/tests/run_frontend_qualification.py", "selfhost/tests/declaration_qualification_test.py", "selfhost/tests/fixtures/declaration_index/" };

/// Qualified type interface pure tests and installed workflow/protocol qualification.
pub const type_interface_qualification = [_][]const u8{"selfhost/"};

/// Adversarial verdict accounting for type interface qualification.
pub const type_interface_qualification_self = [_][]const u8{ "selfhost/test_type_interfaces.py", "selfhost/test_pilots.py", "selfhost/tests/run_type_interface_qualification.py", "selfhost/tests/run_declaration_qualification.py", "selfhost/tests/run_frontend_qualification.py", "selfhost/tests/type_interface_qualification_test.py", "selfhost/tests/fixtures/type_interface/" };

/// Qualified body check pure tests and installed workflow/protocol qualification.
pub const body_check_qualification = [_][]const u8{"selfhost/"};

/// Actual compiler libraries, transitive source closure, fixture controls and verified seed pin.
pub const body_library_admission = [_][]const u8{
    "selfhost/tests/run_body_library_admission.py",
    "selfhost/tests/run_body_library_join.py",
    "selfhost/tests/run_body_check_qualification.py",
    "selfhost/tests/run_frontend_qualification.py",
    "selfhost/tests/fixtures/body_library_followup/",
    "selfhost/components/",
    "selfhost/component-seed.json",
};

/// Adversarial selection and guest verdict accounting, including real test-root source inventories.
pub const body_library_admission_self = [_][]const u8{
    "selfhost/tests/body_library_admission_test.py",
    "selfhost/tests/run_body_library_admission.py",
    "selfhost/tests/run_body_library_join.py",
    "selfhost/tests/run_body_check_qualification.py",
    "selfhost/tests/run_frontend_qualification.py",
    "selfhost/tests/fixtures/body_library_followup/",
    "selfhost/components/",
};

/// Adversarial verdict accounting for body check qualification.
pub const body_check_qualification_self = [_][]const u8{ "selfhost/test_body_checks.py", "selfhost/test_pilots.py", "selfhost/tests/run_body_check_qualification.py", "selfhost/tests/run_declaration_qualification.py", "selfhost/tests/run_type_interface_qualification.py", "selfhost/tests/run_parser_pilot.py", "selfhost/tests/run_frontend_qualification.py", "selfhost/tests/measure_managed_body_adoption.py", "selfhost/tests/measure_frontend_adoption.py", "selfhost/tests/body_check_qualification_test.py", "selfhost/tests/fixtures/body_check/", "selfhost/tests/measure_performance_ratio.py", "selfhost/tests/performance_ratio_test.py", "selfhost/tests/fixtures/performance_ratio/" };

/// Fresh installed B7 captures, all source closures, seed verification and strict two-generation admission.
pub const body_entry_admission = [_][]const u8{"selfhost/"};

/// B7 accounting and protocol adversarial tests without compiler installation.
pub const body_entry_admission_self = [_][]const u8{
    "selfhost/test_body_entries.py",
    "selfhost/tests/run_body_entry_qualification.py",
    "selfhost/tests/generate_body_entry_requests.py",
    "selfhost/tests/run_body_entry_hostile.py",
    "selfhost/tests/run_body_library_join.py",
    "selfhost/tests/run_body_check_qualification.py",
    "selfhost/tests/run_frontend_qualification.py",
    "selfhost/tests/body_entry_qualification_test.py",
    "selfhost/tests/body_entry_requests_test.py",
    "selfhost/tests/body_entry_hostile_test.py",
    "selfhost/tests/fixtures/body_entry_candidate/",
    "selfhost/tests/fixtures/body_entry_hostile/",
};
