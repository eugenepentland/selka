//! Repository files that cached test steps read while they run.
//!
//! A `zig build` Run step is re-executed only when something in its cache key
//! changes: its arguments, its environment, the artifacts it names and the
//! files declared as its inputs. A test binary that opens a fixture, or a
//! Python driver that compiles every probe under a directory, reads files the
//! build system cannot see, so each such step declares them here. `build.zig`
//! turns every entry into content inputs (`addFileInput`) at configure time and
//! asks the configure phase to re-run when a declared directory gains, loses or
//! renames an entry (`dependOnDirectory`), so a new fixture is picked up too.
//!
//! Entry syntax:
//! - `dir/` — every file under `dir`, recursively;
//! - `dir/*.ext` — the files directly in `dir` whose names end in `.ext`;
//! - `dir/**/*.ext` — every file under `dir`, recursively, ending in `.ext`;
//! - anything else — one file, which must exist.
//! Hidden entries, `__pycache__` and `*.pyc` are never inputs.
//!
//! The lists were measured by tracing every `open`/`stat` the steps made
//! (`strace -f`, recorded in `docs/audits/test-loop-speed-2026-09-23.md`) and
//! are checked on every gate by `tests/test_inputs_coverage.py`, which fails
//! when a test source names a repository path no entry covers. When a test
//! starts reading a new file, declare it here; `-Dtest-rerun=true` re-runs every
//! cached test step regardless.

/// The LLVM adapter's sources. A compiler that builds a guest reads them
/// through `MYLANG_LLVM_ADAPTER` whenever the release path is selected.
const llvm_adapter = "experiments/llvm-backend/*.py";

/// `src/root_test.zig`, the unit root. Its guest programs also read the
/// runtime sources the compiler embeds, which `src/` covers.
pub const unit = [_][]const u8{
    "src/",
    "tests/invoke/",
    "tests/native/",
    "test/fixtures/",
    "docs/reference.md",
    "docs/standard-library.md",
    "velocity/friction/",
    llvm_adapter,
};

/// `test/integration.zig`, the CLI root: project examples, the guest suite
/// fixture, and the host applications' guest projects under `src/`.
pub const cli = [_][]const u8{
    "src/",
    "examples/",
    "tests/guest/",
    "test/fixtures/",
    llvm_adapter,
};

/// `src/schematic/tests.zig`: the schematic guest and its Netlisp fixtures.
pub const schematic = [_][]const u8{
    "src/",
    "experiments/schematic/fixtures/",
    "experiments/schematic/straps-synth-lmx2595.svg",
    llvm_adapter,
};

/// `src/board_trial/tests.zig`: the board guest project.
pub const board = [_][]const u8{ "src/", llvm_adapter };

/// `src/byte_io/tests.zig`.
pub const byte_io = [_][]const u8{ "src/", llvm_adapter };

/// `test/golden_parity.zig` (`test-golden`): the golden corpora and the
/// repository fixtures their entries name.
pub const golden = [_][]const u8{ "src/", "tests/goldens/", "examples/", "test/fixtures/", llvm_adapter };

/// The native-test, C FFI and native-build roots under `test-qbe` and
/// `test-qbe-build`: their guests are written by the tests themselves.
pub const native_roots = [_][]const u8{ "src/", "tests/", llvm_adapter };

/// `tests/idiom_probes.py --compiler`: the probe corpus and its manifest.
pub const idioms = [_][]const u8{ "tests/idiom_probes.py", "tests/fixtures/idioms/", llvm_adapter };

/// `tests/idiom_probes.py --self-test`: the CPython oracle only.
pub const idioms_self = [_][]const u8{"tests/idiom_probes.py"};

/// `tests/parser_hints.py`, static and against the compiler.
pub const parser_hints = [_][]const u8{
    "tests/parser_hints.py",
    "src/parser.zig",
    "velocity/friction/",
    "velocity/suites/idioms/",
    llvm_adapter,
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

/// `mylang doctest .`: every page it walks, plus the adapter a release-path
/// example reads.
pub const doctest = [_][]const u8{ "README.md", "SPEC.md", "docs/**/*.md", llvm_adapter };

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
