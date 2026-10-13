//! Where the Zig test roots find the compiler and their fixtures (TEST-PATHS-1).
//!
//! A test binary carries no absolute path of the tree or build cache it was
//! built in, so two worktrees at one commit build the same test bytes outside
//! their debug sections. Repository paths are relative to the build root, which
//! `build.zig` makes the working directory of every test step; the compiler and
//! the component builder arrive at run time through the placement variables
//! `MYLANG_TEST_COMPILER` and `MYLANG_TEST_COMPONENT_BUILDER`, which the build
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
/// The variable naming the `mylang` executable a test runs.
pub const compiler_variable = "MYLANG_TEST_COMPILER";
/// The variable naming the `selka-components` executable a test runs.
pub const component_builder_variable = "MYLANG_TEST_COMPONENT_BUILDER";

/// The variables that select the shared compiler-artifact and native
/// test-receipt stores. An empty value disables a store (SHARED-STORE-4).
pub const shared_store_variables = [_][]const u8{ "MYLANG_COMPILER_SHARED_CACHE", "MYLANG_TEST_SHARED_CACHE" };

/// Disable both shared stores in an environment a test builds for a compiler
/// child, so the child's cache counts and verdicts come from its private cache
/// alone, whether the gate names a shared store or `default_sharing` would pick
/// the per-user one. Tests about sharing name their own store instead.
pub fn privateStores(environment: *std.process.Environ.Map) std.mem.Allocator.Error!void {
    for (shared_store_variables) |name| try environment.put(name, "");
}

/// A copy of the test process's environment with both shared stores disabled
/// (see `privateStores`); the caller owns it.
pub fn privateEnvironment(a: std.mem.Allocator) std.process.Environ.CreateMapError!std.process.Environ.Map {
    var environment = try std.testing.environ.createMap(a);
    errdefer environment.deinit();
    try privateStores(&environment);
    return environment;
}

/// The `mylang` executable under test, from `MYLANG_TEST_COMPILER`.
pub fn corePath() []const u8 {
    return required(compiler_variable);
}

/// The component builder under test, from `MYLANG_TEST_COMPONENT_BUILDER`.
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
