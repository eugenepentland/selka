//! Which sources the build-time identities cover, and how a digest is formed.
//!
//! `build_identity.zig` (a host tool at the repository root) imports this file to
//! decide which files under `src` it reads and to hash them; unit tests import it
//! from `src/root_test.zig`. Two identities come out of one walk:
//!
//! - `compiler_identity` covers every production source;
//! - `runner_identity` covers the narrower set of sources that build a test
//!   executable's driver, fork its trials, apply budgets and judge outcomes.
//!   Execution receipts keyed on a linked program's bytes need it, because the
//!   program covers the emitted code and the runtime but not that side of the
//!   runner. When unsure whether a file belongs here, widen the list.
const std = @import("std");
const Sha = std.crypto.hash.sha2.Sha256;

/// Source bytes read once per tool run, keyed by path relative to `src`.
pub const Sources = std.array_hash_map.String([]const u8);
/// The toolchain and optimize mode every identity digest includes.
pub const Toolchain = struct { zig_version: []const u8, optimize: []const u8 };
/// Domain tag of `compiler_identity`. Changing it invalidates every cache keyed by it.
pub const compiler_domain = "mylang-compiler-identity-v2";
/// Domain tag of `runner_identity`.
pub const runner_domain = "mylang-runner-identity-v1";
/// Why a digest could not be formed: its text buffer could not grow.
pub const DigestError = error{ OutOfMemory, WriteFailed };

/// Path prefixes, relative to `src`, of runner sources: every `core/test_runner*`
/// and `core/property_*` file.
const runner_prefixes = [_][]const u8{ "core/test_runner", "core/property_" };
/// Exact runner sources relative to `src`. `pipeline.zig`, `driver.zig` and
/// `unit_cache.zig` decide how a program is linked and launched, not only what it holds.
const runner_files = [_][]const u8{
    "core/test_builder.zig",  "core/test_shared_store.zig", "core/run_budget.zig",
    "core/trap_contract.zig", "core/process_spawn.zig",     "core/native_receipt.zig",
    "core/cli_run.zig",       "core/cli_args.zig",          "core/pipeline.zig",
    "core/driver.zig",        "core/unit_cache.zig",        "core/target.zig",
    "core/version.zig",       "memory_budget.zig",
};

/// True when a source path is consumed only by a test root. The production
/// compiler never imports these, so they must not move `compiler_identity`; a
/// Zig test root already tracks them directly.
pub fn isTestOnly(path: []const u8) bool {
    const name = std.fs.path.basename(path);
    if (std.mem.endsWith(u8, name, "_test.zig")) return true;
    return std.mem.eql(u8, name, "test_support.zig") or
        std.mem.eql(u8, name, "unit_test.zig") or
        std.mem.eql(u8, name, "nominal_provider_fixture.zig") or
        std.mem.eql(u8, name, "stdlib_fixture.zig");
}

/// True when a production path relative to `src` is one of the test runner,
/// driver or pipeline sources `runner_identity` covers.
pub fn isRunnerSource(path: []const u8) bool {
    if (isTestOnly(path)) return false;
    for (runner_files) |file| if (std.mem.eql(u8, path, file)) return true;
    for (runner_prefixes) |prefix| if (std.mem.startsWith(u8, path, prefix)) return true;
    return false;
}

/// Every path of `sources` that `keep` accepts (all of them when it is null),
/// sorted bytewise. The caller owns the slice; the paths are borrowed.
pub fn sortedPaths(a: std.mem.Allocator, sources: Sources, keep: ?*const fn ([]const u8) bool) error{OutOfMemory}![]const []const u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    errdefer paths.deinit(a);
    for (sources.keys()) |path| if (keep == null or keep.?(path)) try paths.append(a, path);
    std.mem.sort([]const u8, paths.items, {}, order);
    return paths.toOwnedSlice(a);
}

/// SHA-256, as lowercase hexadecimal, over `domain`, the toolchain, the optimize
/// mode and each listed source's path, length and content hash, in the order of
/// `paths`. A path missing from `sources` is skipped.
pub fn digest(a: std.mem.Allocator, domain: []const u8, toolchain: Toolchain, sources: Sources, paths: []const []const u8) DigestError![64]u8 {
    var text: std.Io.Writer.Allocating = .init(a);
    defer text.deinit();
    try text.writer.print("{s}\n{s}\n{s}\n", .{ domain, toolchain.zig_version, toolchain.optimize });
    for (paths) |path| {
        const bytes = sources.get(path) orelse continue;
        try text.writer.print("{s}\x00{d}\x00{x}\n", .{ path, bytes.len, std.hash.Wyhash.hash(0, bytes) });
    }
    var hash: [32]u8 = undefined;
    Sha.hash(text.written(), &hash, .{});
    return std.fmt.bytesToHex(hash, .lower);
}

fn order(_: void, a: []const u8, c: []const u8) bool {
    return std.mem.lessThan(u8, a, c);
}
