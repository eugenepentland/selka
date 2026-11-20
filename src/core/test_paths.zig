//! Where the Zig test roots find the compiler and their fixtures (TEST-PATHS-1).
//!
//! A test binary carries no absolute path of the tree or build cache it was
//! built in, so two worktrees at one commit build the same test bytes outside
//! their debug sections. Repository paths are relative to the build root, which
//! `build.zig` makes the working directory of every test step; the compiler and
//! the component builder arrive at run time through the placement variables
//! `SELKA_TEST_COMPILER` and `SELKA_TEST_COMPONENT_BUILDER`, which the build
//! graph's tool wrapper sets from the artifacts' paths (and keys by their
//! contents). The core root imports this module as `core_test_options`; the
//! unit, CLI and golden roots import it as `test_paths`.
const std = @import("std");

/// The differential mode compared the core slice with the retired back end; it
/// stays off, and `old_path` names no compiler.
pub const differential = false;
/// The retired back end's compiler, which the differential mode would run.
pub const old_path = "";
/// The core's end-to-end fixtures, relative to the build root.
pub const fixtures = "test/core";
/// The language tests some core tests also build, relative to the build root.
pub const lang_tests = "tests/lang";
/// The C clock helper the core's end-to-end programs link, relative to the build root.
pub const clock_path = "benchmarks/runtime/ports/native_clock.c";
/// The variable naming the `selka` executable a test runs.
pub const compiler_variable = "SELKA_TEST_COMPILER";
/// The variable naming the `selka-components` executable a test runs.
pub const component_builder_variable = "SELKA_TEST_COMPONENT_BUILDER";

/// The placement variable selecting the core root's shared build cache.
pub const suite_cache_variable = "SELKA_CORE_TEST_CACHE";

/// Failure to create or resolve the core root's suite build cache.
pub const SuiteCacheError = std.Io.Dir.CreateDirPathError || std.Io.Dir.RealPathFileAllocError;

/// Resolve the core root's content-addressed build cache independently of any
/// test's temporary sources, executable outputs or child working directory.
/// Cache-behaviour tests keep their private directories instead. The cache is a
/// subdirectory per test file (the stem of `where.file`, so call it with `@src()`):
/// a build's stage stores index every record they hold when a process opens them, so
/// one directory shared by the root's 1,350 tests made each `selka` child pay for
/// every other test's records. The caller owns the returned absolute path; the cache
/// outlives individual tests.
pub fn suiteCache(a: std.mem.Allocator, where: std.lang.SourceLocation) SuiteCacheError![:0]u8 {
    const base = lookup(std.testing.environ, suite_cache_variable) orelse ".selka-cache/core-tests";
    const relative = try std.fs.path.join(a, &.{ base, std.fs.path.stem(where.file) });
    defer a.free(relative);
    try std.Io.Dir.cwd().createDirPath(std.testing.io, relative);
    return std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, relative, a);
}

/// The variables that select the shared compiler-artifact and native
/// test-receipt stores. An empty value disables a store (SHARED-STORE-4).
pub const shared_store_variables = [_][]const u8{ "SELKA_COMPILER_SHARED_CACHE", "SELKA_TEST_SHARED_CACHE", "SELKA_STAGE_SHARED_CACHE" };

/// The variables that steer the incremental engine of a `selka test` child (its verify mode, its off switch, its log and
/// the log's tag). They are placement, so a shell that exports one (`SELKA_ENGINE_VERIFY=16` for a whole session) would
/// reach every test child and change which reason a reuse reports; a test that cares about one sets it itself.
pub const engine_variables = [_][]const u8{
    "SELKA_ENGINE_VERIFY",
    "SELKA_ENGINE_SHADOW",
    "SELKA_ENGINE_SHADOW_LOG",
    "SELKA_ENGINE_SHADOW_TAG",
    "SELKA_ENGINE_SHADOW_COMPILER",
    "SELKA_ENGINE_DECIDE_COMPILER",
    "SELKA_ENGINE_DECIDE_PASSES",
    "SELKA_LAZY_SYNTAX",
};

/// Remove the engine's variables (`engine_variables`) from an environment a test builds for a compiler child, so the
/// child decides reuse the way an unconfigured process does, whatever the shell that started the tests exported.
pub fn withoutEngineSettings(environment: *std.process.Environ.Map) void {
    for (engine_variables) |name| _ = environment.swapRemove(name);
}

/// Disable both shared stores in an environment a test builds for a compiler
/// child, so the child's cache counts and verdicts come from its private cache
/// alone, whether the gate names a shared store or `default_sharing` would pick
/// the per-user one, and drop the engine's settings (`withoutEngineSettings`) for the same reason.
/// Tests about sharing name their own store instead.
pub fn privateStores(environment: *std.process.Environ.Map) std.mem.Allocator.Error!void {
    for (shared_store_variables) |name| try environment.put(name, "");
    withoutEngineSettings(environment);
}

/// A copy of the test process's environment with both shared stores disabled and
/// the engine's settings removed (see `privateStores`); the caller owns it.
pub fn privateEnvironment(a: std.mem.Allocator) std.process.Environ.CreateMapError!std.process.Environ.Map {
    var environment = try std.testing.environ.createMap(a);
    errdefer environment.deinit();
    try privateStores(&environment);
    return environment;
}

/// The `selka` executable under test, from `SELKA_TEST_COMPILER`.
pub fn corePath() []const u8 {
    return required(compiler_variable);
}

/// The component builder under test, from `SELKA_TEST_COMPONENT_BUILDER`.
pub fn componentBuilderPath() []const u8 {
    return required(component_builder_variable);
}

/// The value of `name` in the test process's environment; a test binary run
/// outside `zig build` without it stops with a message naming the variable.
fn required(name: []const u8) []const u8 {
    return lookup(std.testing.environ, name) orelse std.debug.panic("{s} is not set: run this test binary through `zig build`, which names the executable under test", .{name});
}

/// The non-empty value of `name` in `environ`, or null.
pub fn lookup(environ: std.process.Environ, name: []const u8) ?[]const u8 {
    const value = environ.getPosix(name) orelse return null;
    return if (value.len == 0) null else value;
}

/// Why `occurrencesOutsideDebug` could not scan a file.
pub const ScanError = error{ NotElf64, TruncatedElf } || std.Io.File.OpenError || std.Io.File.ReadPositionalError;

/// How many times `needle` occurs in the program sections of the ELF64 file
/// at `path` under `dir`: every section except `.debug_*`, `.comment`, the
/// symbol and string tables, and those that occupy no file bytes.
pub fn occurrencesOutsideDebug(io: std.Io, dir: std.Io.Dir, path: []const u8, needle: []const u8) ScanError!usize {
    const file = try dir.openFile(io, path, .{});
    defer file.close(io);
    var header: [64]u8 = undefined;
    if (try file.readPositionalAll(io, &header, 0) != header.len or !std.mem.eql(u8, header[0..5], "\x7fELF\x02")) return error.NotElf64;
    const table = std.mem.readInt(u64, header[0x28..0x30], .little);
    const count = std.mem.readInt(u16, header[0x3c..0x3e], .little);
    const names = try section(io, file, table, std.mem.readInt(u16, header[0x3e..0x40], .little));
    var found: usize = 0;
    var name: [64]u8 = undefined;
    for (0..count) |index| {
        const entry = try section(io, file, table, index);
        if (!scanned(try sectionName(io, file, names, entry.name, &name), entry.kind)) continue;
        found += try occurrences(io, file, entry, needle);
    }
    return found;
}

/// One ELF64 section header's name offset, type, file offset and size.
const Section = struct { name: u32, kind: u32, offset: u64, size: u64 };

/// The section header at `index` of the table at file offset `table`.
fn section(io: std.Io, file: std.Io.File, table: u64, index: usize) ScanError!Section {
    var bytes: [64]u8 = undefined;
    if (try file.readPositionalAll(io, &bytes, table + index * bytes.len) != bytes.len) return error.TruncatedElf;
    return .{
        .name = std.mem.readInt(u32, bytes[0..4], .little),
        .kind = std.mem.readInt(u32, bytes[4..8], .little),
        .offset = std.mem.readInt(u64, bytes[0x18..0x20], .little),
        .size = std.mem.readInt(u64, bytes[0x20..0x28], .little),
    };
}

/// A section name of up to `buffer.len` bytes, read into `buffer` from the
/// section-name table `names`.
fn sectionName(io: std.Io, file: std.Io.File, names: Section, offset: u32, buffer: []u8) ScanError![]const u8 {
    const read = try file.readPositionalAll(io, buffer, names.offset + offset);
    const name = buffer[0..read];
    return name[0 .. std.mem.indexOfScalar(u8, name, 0) orelse name.len];
}

/// Whether a section's bytes belong to the program image rather than to its
/// debug information or symbol tables.
fn scanned(name: []const u8, kind: u32) bool {
    if (kind == std.elf.SHT_NOBITS or kind == std.elf.SHT_SYMTAB or kind == std.elf.SHT_STRTAB) return false;
    return !std.mem.startsWith(u8, name, ".debug") and !std.mem.eql(u8, name, ".comment");
}

/// Occurrences of `needle` in one section, read in overlapping chunks.
fn occurrences(io: std.Io, file: std.Io.File, entry: Section, needle: []const u8) ScanError!usize {
    var chunk: [1 << 16]u8 = undefined;
    std.debug.assert(needle.len > 0);
    std.debug.assert(needle.len < chunk.len / 2);
    var found: usize = 0;
    var start: u64 = 0;
    while (start < entry.size) {
        const length: usize = @intCast(@min(entry.size - start, chunk.len));
        const read = try file.readPositionalAll(io, chunk[0..length], entry.offset + start);
        // Count only matches that start before the overlap the next chunk rereads.
        const fresh = if (start + read < entry.size) read - (needle.len - 1) else read;
        var at: usize = 0;
        while (std.mem.indexOfPos(u8, chunk[0..read], at, needle)) |match| : (at = match + 1) {
            if (match < fresh) found += 1;
        }
        if (start + read >= entry.size or read < needle.len) break;
        start += fresh;
    }
    return found;
}
