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

/// The retired Python adapter, which the boundary matrix still names as the
/// legacy `--qbe` spelling of the LLVM backend (the compiler never reads it).
const llvm_adapter = "experiments/llvm-backend/qbe_llvm.py";

/// The independently gated named byte-ceiling module.
pub const memory_budget = [_][]const u8{"src/memory_budget.zig"};

/// `src/root_test.zig`, the unit root. Its guest programs also read the
/// runtime sources the compiler embeds, which `src/` covers.
pub const unit = [_][]const u8{
    "src/",
    "bench/parity/micro/dict_count.my",
    "tests/lang/rc_dictionary_keys.my",
    "tests/lang/rc_dictionary_loops.my",
    "tests/invoke/",
    "tests/native/",
    "test/fixtures/",
    "docs/reference.md",
    "docs/standard-library.md",
    "velocity/friction/",
};

/// `test/integration.zig`, the CLI root: project examples, the guest suite
/// fixture, and the host applications' guest projects under `src/`.
pub const cli = [_][]const u8{
    "src/",
    "examples/",
    "tests/guest/",
    "test/fixtures/",
};

/// `src/schematic/tests.zig`: the schematic guest and its Netlisp fixtures.
pub const schematic = [_][]const u8{
    "src/",
    "experiments/schematic/fixtures/",
    "experiments/schematic/straps-synth-lmx2595.svg",
};

/// `src/board_trial/tests.zig`: the board guest project.
pub const board = [_][]const u8{"src/"};

/// `src/byte_io/tests.zig`.
pub const byte_io = [_][]const u8{"src/"};

/// `test/golden_parity.zig` (`test-golden`): the golden corpora and the
/// repository fixtures their entries name.
pub const golden = [_][]const u8{ "src/", "tests/goldens/", "examples/", "test/fixtures/" };

/// The native-test, C FFI and native-build roots under `test-qbe` and
/// `test-qbe-build`: their guests are written by the tests themselves.
pub const native_roots = [_][]const u8{ "src/", "tests/" };

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

/// `tests/module_compile_oracle.py`, `tests/module_build_oracle.py` and
/// `tests/module_build_diff.py`: per-module compilation and the default
/// per-module build over `tests/lang` and the fixtures, and its build
/// differential.
pub const module_compile = [_][]const u8{
    "tests/module_compile_oracle.py",
    "tests/module_build_oracle.py",
    "tests/module_check_oracle.py",
    "tests/module_test_oracle.py",
    "tests/module_build_diff.py",
    "tests/lang/",
    "tests/fixtures/interfaces/",
    "tests/fixtures/interfaces_generic/",
    "tests/fixtures/incremental/",
    "tests/fixtures/module_compile/",
    "tests/fixtures/module_projects/",
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

/// `tests/native_boundary_matrix.py --self-test`.
pub const boundary_self = [_][]const u8{"tests/native_boundary_matrix.py"};

/// `tests/native_boundary_matrix.py --compiler`: the carried shapes, their
/// request fixtures and case files, run through both backends.
pub const boundary = [_][]const u8{
    "tests/native_boundary_matrix.py",
    "tests/invoke/",
    "tests/native/",
    "examples/invoke/",
    llvm_adapter,
};

/// `python3 -m unittest test_adapter` in `experiments/llvm-backend`: the
/// adapter, its evidence, the runtime sources it scans, and QBE's opcode table.
pub const adapter = [_][]const u8{
    "experiments/llvm-backend/",
    "src/*.c",
    "src/*.h",
    "vendor/qbe/ops.h",
};

/// `scripts/test_native_memory.py`: the C runtime and its C suites.
pub const native_memory = [_][]const u8{
    "scripts/test_native_memory.py",
    "src/*.c",
    "src/*.h",
    "tests/*.c",
    "tests/*.h",
};

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
