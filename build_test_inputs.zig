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

/// The environment identity contract behind the build graph's environment
/// manifest and projection (`build_env.zig`, ENV-PROJECTION-1/2): every step a
/// list below covers runs in the environment it projects, and every cached
/// one is keyed on the manifest it writes. Lists that already cover `src/`
/// include it.
pub const environment_contract = [_][]const u8{ "src/environment_identity.zon", "src/environment_identity.zig", "src/build_env_rules.zig" };

/// Complete independent tooling test implementation closure; no live fixtures.
pub const tooling_unit = [_][]const u8{
    "src/docstring_examples.zig",       "src/docstring_examples_test.zig",
    "src/release_foundations_test.zig", "src/release_project.zig",
    "src/release_decisions.zig",        "src/api_diff_baseline.zig",
    "src/release_config.zig",           "src/release_config_test.zig",
    "src/tooling_root_test.zig",        "src/doc_coverage_test.zig",
    "src/doc_coverage.zig",             "src/input_probe_test.zig",
    "src/input_probe.zig",              "src/fix_plan_test.zig",
    "src/fix_plan.zig",                 "src/timings_test.zig",
    "src/timings.zig",                  "src/invalidation_test.zig",
    "src/invalidation.zig",             "src/format_difference.zig",
    "src/format_difference_test.zig",   "src/product.zig",
} ++ [_][]const u8{ "scripts/verification_native_telemetry.py", "scripts/verification_telemetry.py" } ++ environment_contract;

/// Complete scalar-text implementation and embedded oracle closure.
pub const text_scalar_unit = [_][]const u8{
    "src/text_scalar_root_test.zig", "src/number_text.zig", "src/number_text_test.zig",
    "src/number_grammar.txt",        "src/format_spec.zig", "src/format_spec_test.zig",
    "src/format_spec_cases.tsv",
} ++ [_][]const u8{ "scripts/verification_native_telemetry.py", "scripts/verification_telemetry.py" } ++ environment_contract;

/// The independently gated named byte-ceiling module.
pub const memory_budget = [_][]const u8{"src/memory_budget.zig"} ++ [_][]const u8{ "scripts/verification_native_telemetry.py", "scripts/verification_telemetry.py" } ++ environment_contract;

/// `src/root_test.zig`, the unit root. Its guest programs also read the
/// runtime sources the compiler embeds, which `src/` covers.
pub const component_inputs = [_][]const u8{ "selfhost/components/", "selfhost/*.zig", "selfhost/*.json" };

pub const unit = [_][]const u8{
    "selfhost/components/",
    "selfhost/*.zig",
    "selfhost/*.json",
    // The resident worker tests build and drive the Selka echo worker.
    "selfhost/worker/",
    "src/",
    "bench/parity/micro/dict_count.selka",
    "bench/parity/suite/knucleotide.selka",
    "tests/lang/rc_dictionary_keys.selka",
    "tests/lang/rc_dictionary_loops.selka",
    "tests/lang/rc_dictionary_text_loops.selka",
    "tests/lang/memo_cache.selka",
    "test/fixtures/",
    "test/core/c_environment_context.selka",
    "test/core/c_environment_context_provider.c",
    "test/core/c_runner_properties.selka",
    "test/core/c_runner_failures.selka",
    "test/core/c_runner_standins.selka",
    "test/core/c_runner_signal.selka",
    "test/core/c_runner_state_capture.selka",
    "test/core/c_runner_signal.c",
    "test/core/c_runner_exit.c",
    "docs/reference.md",
    "docs/ownership-rules.md",
    "docs/standard-library.md",
    "docs/tooling/release-docs.md",
    // STDLIB-COUNT-1 reads every guide that states how many standard modules ship.
    "docs/current-language.md",
    "docs/python-syntax.md",
    "tools/friction/classifier.json",
} ++ [_][]const u8{ "scripts/verification_native_telemetry.py", "scripts/verification_telemetry.py" };

/// `test/integration.zig`, the CLI root: project examples, the guest suite
/// fixture and the compiler's own sources; the QEMU platform of a bare build and the five device programs whose code size
/// has a ceiling (`test/target_cli_test.zig`).
pub const cli = [_][]const u8{
    "README.md",
    "scripts/bare/qemu/platform.c",
    "test/bare/return0.selka",
    "test/bare/list_growth.selka",
    "test/bare/sorting.selka",
    "test/bare/core1_one_core.selka",
    "test/bare/freestanding_checksum.selka",
    "scripts/bare/qemu/link.ld",
    "selfhost/components/",
    "selfhost/*.zig",
    "selfhost/*.json",
    "src/",
    "examples/",
    "tests/guest/",
    "tests/view_shapes/",
    "test/fixtures/",
} ++ [_][]const u8{ "scripts/verification_native_telemetry.py", "scripts/verification_telemetry.py", "scripts/write-commit-file.sh" };

/// Conservative fixtures and embedded runtime inputs for the complete Core root.
pub const core = unit ++ [_][]const u8{
    "test/", "tests/", "examples/", "bench/", "benchmarks/", "selfhost/", "proofs/arith/templates.txt",
};

/// Language guest suites and their exact unsupported-verdict gate policy.
pub const language = [_][]const u8{
    "tests/",
    "test/",
    "examples/",
    "src/",
    "selfhost/",
    "scripts/test_lang.py",
    "scripts/ownership_corpus.py",
    "scripts/verification_telemetry.py",
};

/// The gate action `ownership-proof`: the language gate's inputs (it checks the certificates that gate writes), the Lean
/// model, the driver, the known disagreements and the programs the fault-injection mutants are made from. Its facts half
/// builds `proofs/facts`, which depends on `proofs/arith`, and compares the Lean checker with the validator (C7.3).
pub const ownership_proof = language ++ [_][]const u8{
    "scripts/ownership_proof.py", "scripts/ownership_verdict_store.py", "scripts/fuzz_campaign_store.py",
    "proofs/ownership/",          "tests/ownership-proof-known.json",   "test/fixtures/ownership-proof/",
    "scripts/fact_proof.py",      "test/fixtures/fact-proof/",          "proofs/facts/",
    "proofs/arith/",
};

/// The gate action `verify-ir-proof` (lane VL): the language gate's inputs (it reads the IR and fact certificates those runs write),
/// the Lean copy of the IR verifier with the developments it depends on, the two drivers, the translation fixture, and the C
/// interop programs and their C file, which it builds itself.
pub const verify_ir_proof = language ++ [_][]const u8{
    "scripts/verify_ir_proof.py",      "scripts/verify_ir_mutants.py",     "proofs/verify_ir/",         "proofs/facts/",
    "proofs/arith/",                   "test/fixtures/verify-ir-proof/",   "test/core/c_interop.c",     "test/core/c_interop.selka",
    "test/core/c_interop_tests.selka", "test/core/c_interop_linear.selka", "test/core/c_on_fail.selka",
};

/// The gate action `arith-proof`: the Lean arithmetic proofs and their driver. It runs no compiler; the emitter is compared with the
/// templates it renders by `src/core/arith_lowering_test.zig`, whose step declares `proofs/arith/templates.txt` (see `core`).
pub const arith_proof = [_][]const u8{ "scripts/arith_proof.py", "proofs/arith/" } ++ environment_contract;

/// The gate action `cache-proof` (K4): the compiler and its cache-plan component (the action runs `selka test` on a sample of a copy
/// of `tests/lang` and the component on random requests), the Lean model of the build cache, and the two drivers.
pub const cache_proof = [_][]const u8{ "src/", "tests/lang/", "scripts/cache_proof.py", "scripts/cache_plan_diff.py", "proofs/cache/" } ++ environment_contract;

/// Pure unsupported-guard contracts; no compiler or guest execution.
pub const language_guard = [_][]const u8{
    "scripts/test_lang.py", "scripts/ownership_corpus.py", "tests/test_test_lang.py", "tests/unsupported.json",
} ++ environment_contract;

/// Document navigation and complete feature/standard-library coverage scope.
pub const doc_coverage = [_][]const u8{ "README.md", "SPEC.md", "docs/", "src/" };

/// Every Zig file selected by the normal format gate, including new files.
pub const zig_format = [_][]const u8{
    "build.zig",    "build_env.zig",  "build_identity.zig", "build_test_inputs.zig", "build_verification.zig",
    "src/**/*.zig", "tests/**/*.zig", "test/**/*.zig",      "selfhost/**/*.zig",
};

/// `test/golden_parity.zig` (`test-golden`): the golden corpora and the
/// repository fixtures their entries name.
pub const golden = [_][]const u8{ "selfhost/components/", "selfhost/*.zig", "selfhost/*.json", "src/", "tests/goldens/", "examples/", "test/fixtures/" } ++ [_][]const u8{ "scripts/verification_native_telemetry.py", "scripts/verification_telemetry.py" };

/// `tests/idiom_probes.py --compiler`: the probe corpus and its manifest.
pub const idioms = [_][]const u8{ "tests/idiom_probes.py", "tests/fixtures/idioms/" } ++ environment_contract;

/// `tests/incremental_diff.py`: the mutation walk and its fixture project.
pub const incremental = [_][]const u8{ "tests/incremental_diff.py", "tests/differential_corpus.py", "tests/fixtures/incremental/", "tests/fixtures/module_projects/" } ++ environment_contract;

/// `tests/interface_diff.py`: the interface-hash mutation walk and its fixture.
pub const interfaces = [_][]const u8{ "tests/interface_diff.py", "tests/differential_corpus.py", "tests/fixtures/interfaces/", "tests/fixtures/interfaces_generic/" } ++ environment_contract;

/// `tests/interface_oracle.py`: the per-module check oracle over `tests/lang`
/// and the interface fixtures, with the refused callers of the ownership one.
pub const interface_oracle = [_][]const u8{
    "tests/interface_oracle.py",
    "tests/lang/",
    "tests/fixtures/interfaces/",
    "tests/fixtures/interfaces_generic/",
    "tests/fixtures/incremental/",
    "tests/fixtures/interfaces_ownership/",
} ++ environment_contract;

/// `tests/idiom_probes.py --self-test`: the CPython oracle only.
pub const idioms_self = [_][]const u8{"tests/idiom_probes.py"} ++ environment_contract;

/// `tests/parser_hints.py`, static and against the compiler.
pub const parser_hints = [_][]const u8{
    "tests/parser_hints.py",
    "src/parser.zig",
    "tools/friction/classifier.json",
    "tests/fixtures/parser-hints/",
} ++ environment_contract;

/// `tests/test_friction_harvest.py`: the harvester and its replay fixture.
pub const friction = [_][]const u8{ "tests/test_friction_harvest.py", "tools/friction/" } ++ environment_contract;

/// Synthetic contracts, parsers, reports and calibration; retain the complete
/// imported package closure and its membership, including CLI/engine imports.
pub const juice_pure = [_][]const u8{ "scripts/verification_code_identity.py", "tests/test_juice.py", "scripts/juice_tool/" } ++ environment_contract;

/// Juice's live runner and native collector integration tests.
pub const juice = [_][]const u8{ "scripts/verification_code_identity.py", "tests/test_juice.py", "tests/test_juice_native.py", "scripts/juice", "scripts/juice_tool/", "scripts/juice_validate.py", "examples/juice/" } ++ environment_contract;

/// Runtime collector experiments observe CPU, scheduler and current host state.
pub const juice_runtime = [_][]const u8{ "scripts/verification_code_identity.py", "tests/test_juice_runtime_bench.py", "scripts/juice_tool/", "scripts/juice_runtime_bench.py", "scripts/build_admission.py", "scripts/build_slot_legacy.sh", "scripts/verification/__init__.py", "scripts/verification/scheduler.py", "scripts/build-slot.sh" } ++ environment_contract;

/// `selka doctest .`: every page it walks.
pub const doctest = [_][]const u8{ "README.md", "SPEC.md", "docs/**/*.md" } ++ environment_contract;

/// `tests/goals_register.py`: the goals register (`docs/goals.md`), its pinned examples, and the kinds of file the register
/// names as evidence (audits and docs, Zig sources and tests, Lean sources, `proofs` notes, Python drivers, guest tests). The
/// driver fails when a path the page names falls outside this list, so a deleted or renamed evidence file always reruns it,
/// and says which entry to add when the page names a kind of file that is not here.
pub const goals_register = [_][]const u8{
    "docs/**/*.md",
    "src/**/*.zig",
    "test/**/*.zig",
    "test/fixtures/goals/",
    "proofs/**/*.lean",
    "proofs/**/*.md",
    "proofs/arith/",
    "scripts/**/*.py",
    "tests/**/*.py",
    "tests/**/*.selka",
    "CLAUDE.md",
    "build.zig",
    "build_test_inputs.zig",
    "tests/goals_register.py",
    "tests/test_inputs_coverage.py",
    // The compiler map (`docs/tooling/compiler-map.md`, checked by `tests/compiler_map.py` inside this action) names files of
    // every kind a change touches: the C runtime, the embedded library, the feature manifest, the syntax layout, the fix
    // corpus, the Core test programs and the type-size baseline. The page itself is under `docs/**/*.md`.
    "tests/compiler_map.py",
    "SPEC.md",
    "CHANGES.md",
    "src/**/*.c",
    "src/**/*.selka",
    "src/features.json",
    "src/syntax_layout.txt",
    "test/fixtures/fix-migration/",
    "test/core/",
    "scripts/build-slot.sh",
} ++ environment_contract;

/// `tests/mode_differential.py`: programs it generates from fixed seeds, built in several modes that must agree. It reads
/// no repository file but itself, so it reruns when the compiler or the driver changes.
pub const mode_differential = [_][]const u8{"tests/mode_differential.py"} ++ environment_contract;

/// `tests/test_affected_tests.py`: `scripts/affected_tests.py`'s mapping,
/// pinned on a synthetic repository it writes itself.
pub const affected = [_][]const u8{
    "scripts/affected_tests.py",
    "scripts/focused_test.py",
    "scripts/failure_report.py",
    "scripts/run-report-fixtures/",
    "scripts/lane/probe.sh",
    "scripts/lane/lib.sh",
    "scripts/lane/with-stores.sh",
    "scripts/edit_check.py",
    "scripts/edit_check_collect.py",
    "scripts/edit_check_refresh.py",
    "tests/test_affected_tests.py",
    "tests/test_focused_test.py",
    "tests/test_edit_check.py",
    "scripts/gate_cheap_checks.py",
} ++ environment_contract;

/// `tests/test_selka_tools.py`: each Selka tool under `tools/selka`, the Python script it ports, and the generator of the
/// fixtures both run on. The compiler that builds the tools is the step's artifact argument.
pub const selka_tools = [_][]const u8{
    "tests/test_selka_tools.py",
    "tools/selka/",
    "scripts/engine_shadow_summary.py",
    "scripts/gate_summary.py",
} ++ environment_contract;

/// `tests/test_inputs_coverage.py`: this file and every Zig test source the
/// cached roots compile.
pub const coverage = [_][]const u8{
    "tests/test_inputs_coverage.py",
    "build_test_inputs.zig",
    "src/**/*.zig",
    "test/**/*.zig",
} ++ environment_contract;

/// `tests/test_inputs_coverage.py --self-test`.
pub const coverage_self = [_][]const u8{"tests/test_inputs_coverage.py"} ++ environment_contract;

/// Receipt admission and immutable-snapshot adversarial tests use fake actions.
pub const verification_cache = [_][]const u8{
    "scripts/verification_watch_pool_test.py",
    "scripts/watch_pool_review_test.py",
    "scripts/object_diagnostics_review_test.py",
    "test/fixtures/verification-cache/object.zlib",
    "scripts/verification_publication_test.py",
    "scripts/verification_digest_request_test.py",
    "scripts/ownership_proof_test.py",
    "scripts/ownership_proof.py",
    "scripts/arith_proof_test.py",
    "scripts/arith_proof.py",
    "scripts/cache_proof_test.py",
    "scripts/cache_proof.py",
    "scripts/fact_proof_test.py",
    "scripts/fact_proof.py",
    "scripts/ownership_corpus_test.py",
    "scripts/ownership_corpus.py",
    "scripts/ownership_verdict_store_test.py",
    "scripts/ownership_verdict_store.py",
    "scripts/test_lang.py",
    "scripts/fuzz_campaign_store.py",
    "build.zig",
    "scripts/reuse_review_test.py",
    "scripts/verification_code_identity.py",
    "build_test_inputs.zig",
    // Producer tests copy these real closures into isolated mutation fixtures.
    "src/api_diff_baseline.zig",
    "src/release_config.zig",
    "src/release_config_test.zig",
    "src/release_decisions.zig",
    "src/release_foundations_test.zig",
    "src/release_project.zig",
    "src/doc_coverage.zig",
    "src/doc_coverage_test.zig",
    "src/docstring_examples.zig",
    "src/docstring_examples_test.zig",
    "src/fix_plan.zig",
    "src/fix_plan_test.zig",
    "src/format_spec.zig",
    "src/format_spec_cases.tsv",
    "src/format_difference.zig",
    "src/format_difference_test.zig",
    "src/format_spec_test.zig",
    // The tooling root's closure holds the product's names since GH-5.1.
    "src/product.zig",
    "src/input_probe.zig",
    "src/input_probe_test.zig",
    "src/invalidation.zig",
    "src/invalidation_test.zig",
    "src/number_grammar.txt",
    "src/number_text.zig",
    "src/number_text_test.zig",
    "src/product.zig",
    "src/text_scalar_root_test.zig",
    "src/timings.zig",
    "src/timings_test.zig",
    "src/tooling_root_test.zig",
    "scripts/verification_profiles_test.py",
    "scripts/verification_qualification_test.py",
    "test/fixtures/long-qualification/",
    "scripts/development_loop_workloads_test.py",
    "test/fixtures/verification-profiles/C0-inventory.json",
    "test/fixtures/long-qualification/oracle.py",
    "scripts/cache_session.py",
    "scripts/fuzz_campaign_store.py",
    "scripts/verify_cache.py",
    "scripts/verification_warm.py",
    "scripts/verification_warm_test.py",
    "scripts/verification_git_tree.py",
    "scripts/verification_git_tree_test.py",
    "scripts/verification_profiles.py",
    "scripts/verification_qualification.py",
    "scripts/verification_producers.py",
    "scripts/verification_telemetry.py",
    "scripts/verification_snapshot.py",
    "scripts/verification_watch_pool.py",
    "scripts/verification_process.py",
    "scripts/verification_process_test.py",
    "scripts/verification_ownership_watch_test.py",
    "scripts/verification_report.py",
    "scripts/verification_budgets.py",
    "scripts/verification_policy.py",
    "scripts/verification_report_test.py",
    "scripts/verification_budgets_test.py",
    "scripts/verification_policy_test.py",
    "scripts/verification_artifacts.py",
    "scripts/verification_producers_test.py",
    "scripts/verification_telemetry_test.py",
    "scripts/verification_shard_plan.py",
    "scripts/verification_shard_plan_test.py",
    "scripts/verify_cache_test.py",
    // verify_cache_test.py checks that the coordinator watches the test runner's sources.
    "tools/test_runner/",
    "scripts/verification_snapshot_test.py",
    "scripts/verification_snapshot_profile.py",
    "scripts/build-slot.sh",
    "scripts/build_admission.py",
    "scripts/build_slot_legacy.sh",
    "scripts/worktree_cache_trim.py",
    "test/fixtures/admission/",
    "scripts/verification/__init__.py",
    "scripts/verification/scheduler.py",
    "scripts/build_slot_test.py",
    "scripts/build_slot_watch_test.py",
    "scripts/dev_loop.py",
    "scripts/dev_loop_test.py",
    "scripts/focused_test.py",
    "scripts/failure_report.py",
    "scripts/run-report-fixtures/",
    ".zigversion",
    "tests/verification/test_scheduler.py",
    "scripts/verification/*.py",
    "scripts/verify.py",
    "tests/test_inputs_coverage.py",
    "scripts/verification_native_telemetry.py",
    "scripts/verification_native_telemetry_test.py",
    "scripts/gate_summary.py",
    "scripts/gate_summary_test.py",
    "scripts/corpus_exact.py",
    "scripts/corpus_exact_test.py",
    "tests/goals_register.py",
    "tests/goals_register_test.py",
    "tests/compiler_map.py",
    "tests/compiler_map_test.py",
    "scripts/application_cache_patience_test.py",
    "tests/application_cache.py",
    "scripts/edit_check.py",
    "scripts/edit_check_collect.py",
    "scripts/edit_check_map.py",
    "scripts/edit_check_refresh.py",
    "scripts/edit_check_test.py",
    "scripts/build_env_death_test.py",
    "scripts/quiet-driver.sh",
    "scripts/verification_guest_telemetry.py",
    "scripts/verification_guest_telemetry_test.py",
    "scripts/verification_measurement.py",
    "scripts/verification_measurement_test.py",
    "scripts/verification_code_identity_test.py",
    // The environment identity contract, its Python reader and golden fixture,
    // and the `build-env` tool's compile closure the coordinator must bind.
    "src/environment_identity.zon",
    "build_env.zig",
    "src/environment_identity.zig",
    "src/build_env_rules.zig",
    "scripts/verification_environment.py",
    "scripts/verification_environment_test.py",
    "test/fixtures/environment-identity/",
    "scripts/gate_cheap_checks.py",
    "scripts/check_my_format.py",
    "test/fixtures/gate-summary/",
    "scripts/edit_check_shadow.py",
    "scripts/verification_rerun.py",
};

/// Persistent coordinator startup watches the complete developer implementation.
pub const verification_session = [_][]const u8{"scripts/"} ++ environment_contract;

/// Independent fuzz shards, concrete replay, evidence and native-worker lifecycle.
pub const fuzz_campaign = [_][]const u8{
    "scripts/service_worktree.py",
    "scripts/service_worktree_test.py",
    "scripts/install-nightly-integration-timer.py",
    "scripts/nightly-integration.sh",
    "scripts/systemd/",
    "scripts/maintenance_review_test.py",
    "scripts/verification_code_identity.py",
    "scripts/cache_session.py",
    "scripts/fuzz_campaign.py",
    "scripts/fuzz_campaign_identity.py",
    "scripts/fuzz_campaign_store.py",
    "scripts/fuzz_campaign_store_test.py",
    "scripts/cache_retention.py",
    "scripts/cache_retention_test.py",
    "scripts/core_store_gc.py",
    "scripts/core_store_gc_test.py",
    "scripts/audit_cache_reads.py",
    "scripts/audit_cache_reads_test.py",
    "scripts/prune-caches.sh",
    "scripts/fuzz_campaign_test.py",
    "scripts/fuzz_coverage.py",
    "scripts/fuzz_coverage_test.py",
    "scripts/verify_cache.py",
    "scripts/verification_warm.py",
    "scripts/verification_warm_test.py",
    "scripts/verification_git_tree.py",
    "scripts/verification_git_tree_test.py",
    "scripts/verification_profiles.py",
    "scripts/verification_qualification.py",
    "scripts/verification_producers.py",
    "scripts/verification_telemetry.py",
    "scripts/verification_snapshot.py",
    "scripts/verification_watch_pool.py",
    "scripts/verification_process.py",
    "scripts/verification_report.py",
    "scripts/verification_budgets.py",
    "scripts/verification_policy.py",
    "scripts/build-slot.sh",
    "tests/differential_corpus.py",
    "tests/test_differential_corpus.py",
    "tests/incremental_diff.py",
    "tests/interface_diff.py",
    "test/fixtures/fuzz-campaign/",
    "scripts/verification_measurement.py",
    "scripts/build_admission.py",
    "scripts/build_slot_legacy.sh",
    "scripts/verification/__init__.py",
    "scripts/verification/scheduler.py",
    "scripts/verification_guest_telemetry.py",
} ++ environment_contract;

/// `tests/input_manifest.py --self-test`.
pub const manifest_self = [_][]const u8{"tests/input_manifest.py"} ++ environment_contract;

/// Qualified Juice evidence and admission tests use isolated simulated collectors.
pub const juice_cache = [_][]const u8{
    "scripts/verification_code_identity.py",
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
    "scripts/verification_warm.py",
    "scripts/verification_warm_test.py",
    "scripts/verification_git_tree.py",
    "scripts/verification_git_tree_test.py",
    "scripts/verification_profiles.py",
    "scripts/verification_qualification.py",
    "scripts/verification_producers.py",
    "scripts/verification_telemetry.py",
    "scripts/verification_snapshot.py",
    "scripts/verification_watch_pool.py",
    "scripts/verification_process.py",
    "scripts/verification_report.py",
    "scripts/verification_budgets.py",
    "scripts/verification_policy.py",
    "scripts/build-slot.sh",
    "scripts/verification_measurement.py",
    "scripts/build_admission.py",
    "scripts/build_slot_legacy.sh",
    "scripts/verification/__init__.py",
    "scripts/verification/scheduler.py",
    "scripts/verification_guest_telemetry.py",
} ++ environment_contract;

/// Isolated CLI cache, frame-diagnostic and guest-address-space probes.
pub const tooling_isolation = [_][]const u8{"tests/tooling_cache_isolation.py"} ++ environment_contract;

/// The bootstrap lexer source and live-compiler numeric extent oracle.
pub const selfhost_numeric = [_][]const u8{"selfhost/"} ++ environment_contract;

/// The syntax parity harness and its Zig-against-Zig run over the corpus in `selfhost/corpus.json` (the roots inside the repository).
pub const selfhost_syntax = [_][]const u8{
    "selfhost/", "tests/**/*.selka", "test/**/*.selka", "src/stdlib/", "src/core/**/*.selka", "bench/**/*.selka", "benchmarks/**/*.selka", "examples/**/*.selka",
} ++ environment_contract;

/// The independent component cache and qualification builder.
pub const component_builder = [_][]const u8{ "selfhost/*.zig", "selfhost/test_components.py", "selfhost/test_component_native.py", "selfhost/*.json" } ++ [_][]const u8{ "scripts/verification_native_telemetry.py", "scripts/verification_telemetry.py" } ++ environment_contract;

/// The components' pure tests with the built compiler, and the native protocol oracle.
pub const component_native = [_][]const u8{ "selfhost/components/", "selfhost/*.zig", "selfhost/*.json", "selfhost/test_component_native.py", "selfhost/tests/run_test_index_component.py", "selfhost/tests/run_cache_plan_component.py" } ++ environment_contract;

/// The live .selka formatting corpus, selection script and deliberate exclusions.
pub const my_format = [_][]const u8{
    "scripts/check_my_format.py",
    "scripts/my_format_exclusions.json",
    "bench/**/*.selka",
    "benchmarks/**/*.selka",
    "docs/**/*.selka",
    "examples/**/*.selka",
    "selfhost/**/*.selka",
    "src/**/*.selka",
    "test/**/*.selka",
    "tests/**/*.selka",
} ++ environment_contract;

/// Synthetic corpus selection and real formatter failure propagation.
pub const my_format_self = [_][]const u8{ "scripts/check_my_format.py", "tests/test_my_format.py" } ++ environment_contract;

/// The embedded-source migrator `selka fix` migrations reuse, its census
/// helper and the application observation harness; each test builds its own
/// scratch trees and reads no other repository file.
pub const migrate_embedded = [_][]const u8{
    "scripts/migrate_embedded.py",
    "scripts/spelling_census.py",
    "tests/test_migrate_embedded.py",
    "scripts/ownership_applications.py",
    "scripts/ownership_applications_test.py",
} ++ environment_contract;

/// The standalone programs `selka check` sweeps, with the project files
/// (`selka.json`, import policies, `.api` interfaces) a checked example reads.
pub const program_check = [_][]const u8{
    "scripts/check_programs.py",
    "bench/**/*.selka",
    "benchmarks/**/*.selka",
    "examples/",
    "src/stdlib/",
    "selfhost/components/",
} ++ environment_contract;

/// All live sources and selection policy read by the allocation-contract lint gate.
pub const noalloc_lint = my_format ++ [_][]const u8{"scripts/check_noalloc.py"};

/// Persistent application records, native provider failure and crash recovery driver.
pub const application_cache = [_][]const u8{ "tests/application_cache.py", "test/fixtures/application-cache/", "src/" };

/// Public default ownership, allocation contracts and selector behavior.
pub const ownership_commands = [_][]const u8{"scripts/test_ownership_default_cli.py"} ++ environment_contract;
