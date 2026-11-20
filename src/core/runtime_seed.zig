//! A private object store that starts with the runtime object its builds would otherwise
//! compile (CORE-SUITE-RUNTIME-SEED-1).
//!
//! A core test that keeps its own `SELKA_CORE_RUNTIME_CACHE` so that its unit and program
//! counts are exact also pays for a cold runtime compile (about 4 s of CPU in `zig cc`),
//! although nothing it asserts is about that object. `seed` builds a one-line program with
//! the compiler under test into a store the suite shares, once for each runtime text and
//! each layout and sanitizer setting, and copies the runtime objects that build left into
//! the test's store. The object is the one the test's own build would have compiled: the
//! same compiler, flags and toolchain, under the same content key. `driver_cache_test`'s
//! layout and sanitizer tests seed each setting and count one runtime object per setting
//! in their store, which shows each setting keys its own; the seed builds still compile
//! every one of those runtimes whenever the runtime text changes. Only its cold-build test,
//! whose subject is the cold compile itself, keeps an empty store and does not call this.
//!
//! A variant of the shared store is made of two halves, the object `store` and the build's `work`
//! directory, and it must never be half-made for good. The `work` directory replays an unchanged build
//! without starting a process, so a `store` that went missing (the suite-cache trimmer once removed it
//! alone, as it was the half with the older stamp) was never refilled: the copy found nothing to copy
//! and every core test that seeds failed with `SeedFailed` until the directory was deleted by hand. The
//! seed now answers for what it hands out: when the replay leaves the `store` without a runtime object
//! it builds again in a work directory of its own, which has nothing to replay, and a build that still
//! leaves no object is a failed seed. The variant also leases itself, so that `worktree_cache_trim.py`
//! sees one unit with one last-use stamp (it takes the outermost directory that holds a lease) and
//! removes it whole or not at all, never while a seed is using it.
const std = @import("std");
const product = @import("selka").product;
const language = @import("selka");
const fast_blake3 = @import("fast_blake3.zig");
const options = @import("core_test_options");
const driver = @import("driver.zig");
const tool_identity = @import("tool_identity.zig");
const io = std.testing.io;
const cwd = std.Io.Dir.cwd();
const report = std.debug.print;

/// Why a store could not be seeded; the cause is printed where it happened.
pub const Error = error{ OutOfMemory, SeedFailed };

/// The variables that choose which runtime object a build compiles besides its text.
const variant_variables = [_][]const u8{ "SELKA_CORE_LAYOUT", "SELKA_CORE_SANITIZE" };
const seed_program = "func main() -> int:\n    return 0\n";

/// The name of the seed store for this runtime text, this toolchain, the runtime object's key domain and this
/// environment's layout and sanitizer. A runtime object's key holds the toolchain's identity, so a store that outlives
/// a change of it (an upgrade, or a change in what the identity covers) would hold both generations of objects.
fn variantName(a: std.mem.Allocator, environment: *const std.process.Environ.Map) ![]const u8 {
    return variantNameUnder(a, environment, driver.runtime_object_domain);
}

/// `variantName` for a runtime object key domain. The domain is in the name because the seed copies every runtime
/// object of its store: when the domain went from v4 to v5 (19 November 2026) with the name unchanged, a worktree that
/// had run the suite before held both generations in one variant, and every test that counts runtime objects failed.
fn variantNameUnder(a: std.mem.Allocator, environment: *const std.process.Environ.Map, domain: []const u8) ![]const u8 {
    var hash = fast_blake3.Blake3.init(.{});
    hash.update(domain);
    hash.update("\x00");
    hash.update(driver.runtime_source);
    const tool = try tool_identity.capture(.{ .arena = a, .io = io, .environment = environment, .executable = environment.get("SELKA_ZIG") orelse "zig", .cache = product.work_dir });
    hash.update(&tool.digest);
    for (variant_variables) |name| {
        hash.update(name);
        hash.update("=");
        hash.update(environment.get(name) orelse "");
        hash.update("\n");
    }
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    return std.fmt.allocPrint(a, "{x}", .{digest[0..12].*});
}

/// Write `bytes` to `path` unless it already holds them, through a rename so that a
/// shard reading it at the same moment sees either whole version.
fn publishProgram(a: std.mem.Allocator, path: []const u8) !void {
    const found = cwd.readFileAlloc(io, path, a, .limited(1 << 16)) catch null;
    if (found) |bytes| if (std.mem.eql(u8, bytes, seed_program)) return;
    var nonce: [8]u8 = undefined;
    std.Io.random(io, &nonce);
    const staging = try std.fmt.allocPrint(a, "{s}.{x}.partial", .{ path, nonce });
    try cwd.writeFile(io, .{ .sub_path = staging, .data = seed_program });
    try cwd.rename(staging, cwd, path, io);
}

/// Make `store` hold the runtime object a build under `environment` would compile into it.
/// The build runs in a store the whole suite shares, with the compiler's shared stores off,
/// so it leaves nothing in the test's own caches; `store` receives only the runtime objects.
pub fn seed(a: std.mem.Allocator, environment: *const std.process.Environ.Map, store: []const u8) Error!void {
    return seedStore(a, environment, store) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => {
            report("runtime seed: {s}\n", .{@errorName(err)});
            return error.SeedFailed;
        },
    };
}

fn seedStore(a: std.mem.Allocator, environment: *const std.process.Environ.Map, store: []const u8) !void {
    return seedVariant(a, environment, try options.suiteCache(a, @src()), store);
}

/// The directory of this environment's variant under `root`: the program, the object `store` and the `work` directory.
fn variantDirectory(a: std.mem.Allocator, environment: *const std.process.Environ.Map, root: []const u8) ![]const u8 {
    return std.fs.path.join(a, &.{ root, try variantName(a, environment) });
}

/// Seed `store` from the variant of `root` that matches `environment`, making the variant first when it is missing,
/// half-made or stale.
fn seedVariant(a: std.mem.Allocator, environment: *const std.process.Environ.Map, root: []const u8, store: []const u8) !void {
    const shared = try variantDirectory(a, environment, root);
    try cwd.createDirPath(io, shared);
    // The variant is one unit to the cache trimmer; its stamp is the last seed.
    const unit = try language.native_cache_work.lease(a, io, shared);
    defer unit.close(io);
    try cwd.setTimestampsNow(io, try std.fs.path.join(a, &.{ shared, lease_name }), .{});
    const program = try std.fs.path.join(a, &.{ shared, "seed.selka" });
    try publishProgram(a, program);
    const objects = try std.fs.path.join(a, &.{ shared, "store" });
    try buildSeed(a, environment, .{ .program = program, .store = objects, .work = try std.fs.path.join(a, &.{ shared, "work" }) });
    if (!try holdsRuntimeObject(objects)) {
        // The replay of an earlier build hid an object that is gone: build again with nothing to replay.
        var fresh = std.testing.tmpDir(.{});
        defer fresh.cleanup();
        try buildSeed(a, environment, .{ .program = program, .store = objects, .work = try fresh.dir.realPathFileAlloc(io, ".", a) });
        if (!try holdsRuntimeObject(objects)) {
            report("runtime seed: the build left no runtime object in {s}\n", .{objects});
            return error.FileNotFound;
        }
    }
    try copyRuntimeObjects(a, objects, store);
}

/// The lease file a work directory is held by (`native_cache_retention`'s name for it).
const lease_name = ".retention.lock";

/// The places one seed build uses: its program, the store it fills and the work directory it keeps its replay in.
const Build = struct { program: []const u8, store: []const u8, work: []const u8 };

/// Build the seed program with the compiler under test into `places.store`, with the compiler's shared stores off so
/// that it leaves nothing in the test's own caches.
fn buildSeed(a: std.mem.Allocator, environment: *const std.process.Environ.Map, places: Build) !void {
    var build = try environment.clone(a);
    defer build.deinit();
    try build.put("SELKA_CORE_RUNTIME_CACHE", places.store);
    try options.privateStores(&build);
    var output = std.testing.tmpDir(.{});
    defer output.cleanup();
    const result = try std.process.run(a, io, .{
        .argv = &.{ options.corePath(), "build", places.program, "-o", try std.fs.path.join(a, &.{ try output.dir.realPathFileAlloc(io, ".", a), "seed" }), "--cache-dir", places.work },
        .environ_map = &build,
    });
    if (result.term != .exited or result.term.exited != 0) report("runtime seed build: {s}{s}\n", .{ result.stdout, result.stderr });
    try std.testing.expect(result.term == .exited and result.term.exited == 0);
}

/// Whether `store` holds a finished runtime object; a missing store, and one that holds only the runtime's source or a
/// compile that never finished, hold none.
fn holdsRuntimeObject(store: []const u8) !bool {
    var directory = cwd.openDir(io, store, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer directory.close(io);
    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| if (isRuntimeObject(entry)) return true;
    return false;
}

fn isRuntimeObject(entry: std.Io.Dir.Entry) bool {
    if (entry.kind != .file) return false;
    return std.mem.startsWith(u8, entry.name, "core_rt-") and std.mem.endsWith(u8, entry.name, ".o");
}

fn copyRuntimeObjects(a: std.mem.Allocator, from: []const u8, to: []const u8) !void {
    try cwd.createDirPath(io, to);
    var directory = try cwd.openDir(io, from, .{ .iterate = true });
    defer directory.close(io);
    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| {
        if (!isRuntimeObject(entry)) continue;
        const destination = try std.fs.path.join(a, &.{ to, entry.name });
        const staging = try std.fmt.allocPrint(a, "{s}.partial", .{destination});
        try directory.copyFile(entry.name, cwd, staging, io, .{});
        try cwd.rename(staging, cwd, destination, io);
    }
}

// spec: CORE-SUITE-RUNTIME-SEED-1
test "a seeded store holds the runtime object and nothing else, and its first build compiles no runtime" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = try std.fs.path.join(a, &.{ root, "store" });
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    try environment.put("SELKA_CORE_RUNTIME_CACHE", store);
    try seed(a, &environment, store);
    var directory = try cwd.openDir(io, store, .{ .iterate = true });
    defer directory.close(io);
    var iterator = directory.iterate();
    const first = (try iterator.next(io)).?;
    try std.testing.expect(std.mem.startsWith(u8, first.name, "core_rt-") and std.mem.endsWith(u8, first.name, ".o"));
    try std.testing.expectEqual(@as(?std.Io.Dir.Entry, null), try iterator.next(io));
    // The test's own build finds the object: one unit, the entry and the link, no runtime compile.
    try temporary.dir.writeFile(io, .{ .sub_path = "app.selka", .data = seed_program });
    const built = try std.process.run(a, io, .{
        .argv = &.{ options.corePath(), "build", try std.fs.path.join(a, &.{ root, "app.selka" }), "-o", try std.fs.path.join(a, &.{ root, "program" }), "--cache-dir", try std.fs.path.join(a, &.{ root, "cache" }), "--report" },
        .environ_map = &environment,
    });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const cache_line = built.stderr[std.mem.indexOf(u8, built.stderr, "{\"version\":\"cache-report-v1\"").?..];
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, std.mem.sliceTo(cache_line, '\n'), .{});
    const compiled = parsed.object.get("compiled").?.integer;
    try std.testing.expectEqual(compiled + 1, parsed.object.get("processes").?.integer);
}

// spec-case: CORE-SUITE-RUNTIME-SEED-1
test "a seed rebuilds a variant that holds its work directory but no store, rather than failing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    // A suite cache of this test's own, so that removing a half of the variant cannot reach a seed running in another test process.
    const suite = try std.fs.path.join(a, &.{ root, "suite" });
    const variant = try variantDirectory(a, &environment, suite);
    try seedVariant(a, &environment, suite, try std.fs.path.join(a, &.{ root, "first" }));
    try std.testing.expect(try holdsRuntimeObject(try std.fs.path.join(a, &.{ variant, "store" })));
    // The variant leases itself, which is what makes it one unit to the cache trimmer.
    try cwd.access(io, try std.fs.path.join(a, &.{ variant, lease_name }), .{});
    // What the trimmer once did: it removed the older half and left the `work` directory, whose replay hides the loss.
    try cwd.deleteTree(io, try std.fs.path.join(a, &.{ variant, "store" }));
    try cwd.access(io, try std.fs.path.join(a, &.{ variant, "work" }), .{});
    try seedVariant(a, &environment, suite, try std.fs.path.join(a, &.{ root, "second" }));
    try std.testing.expect(try holdsRuntimeObject(try std.fs.path.join(a, &.{ variant, "store" })));
    try std.testing.expect(try holdsRuntimeObject(try std.fs.path.join(a, &.{ root, "second" })));
}

// spec-case: CORE-SUITE-RUNTIME-SEED-1
test "a seed store holds a runtime object only once its compile has finished" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try std.testing.expect(!try holdsRuntimeObject(try std.fs.path.join(a, &.{ root, "missing" })));
    try temporary.dir.createDir(io, "interrupted", .default_dir);
    try temporary.dir.writeFile(io, .{ .sub_path = "interrupted/core_rt-1.c", .data = "source" });
    try temporary.dir.writeFile(io, .{ .sub_path = "interrupted/core_rt-1.o.ab.partial", .data = "half" });
    try temporary.dir.writeFile(io, .{ .sub_path = "interrupted/unit-1.o", .data = "not the runtime" });
    try std.testing.expect(!try holdsRuntimeObject(try std.fs.path.join(a, &.{ root, "interrupted" })));
    try temporary.dir.writeFile(io, .{ .sub_path = "interrupted/core_rt-1.o", .data = "object" });
    try std.testing.expect(try holdsRuntimeObject(try std.fs.path.join(a, &.{ root, "interrupted" })));
}

// spec-case: CORE-SUITE-RUNTIME-SEED-1
test "a store that cannot be created is a failed seed, not a silently empty one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(io, .{ .sub_path = "blocker", .data = "a file where a directory must go" });
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    try std.testing.expectError(error.SeedFailed, seed(a, &environment, try std.fs.path.join(a, &.{ root, "blocker", "store" })));
}

// spec-case: CORE-SUITE-RUNTIME-SEED-1
test "the seed store's name follows the toolchain, the runtime layout and the sanitizer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.writeFile(io, .{ .sub_path = "zig-first", .data = "first" });
    try temporary.dir.writeFile(io, .{ .sub_path = "zig-other", .data = "other" });
    try temporary.dir.setFilePermissions(io, "zig-first", .executable_file, .{});
    try temporary.dir.setFilePermissions(io, "zig-other", .executable_file, .{});
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    try environment.put("SELKA_ZIG", try std.fs.path.join(a, &.{ root, "zig-first" }));
    _ = environment.swapRemove("SELKA_CORE_LAYOUT");
    _ = environment.swapRemove("SELKA_CORE_SANITIZE");
    const first = try variantName(a, &environment);
    try std.testing.expectEqualStrings(first, try variantName(a, &environment));
    try environment.put("SELKA_ZIG", try std.fs.path.join(a, &.{ root, "zig-other" }));
    try std.testing.expect(!std.mem.eql(u8, first, try variantName(a, &environment)));
    try environment.put("SELKA_ZIG", try std.fs.path.join(a, &.{ root, "zig-first" }));
    try environment.put("SELKA_CORE_LAYOUT", "5");
    try std.testing.expect(!std.mem.eql(u8, first, try variantName(a, &environment)));
}

// spec-case: CORE-SUITE-RUNTIME-SEED-1
test "the seed store's name follows the runtime object's key domain, so two generations never share a store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try options.privateEnvironment(a);
    defer environment.deinit();
    const current = try variantName(a, &environment);
    try std.testing.expectEqualStrings(current, try variantNameUnder(a, &environment, driver.runtime_object_domain));
    try std.testing.expect(!std.mem.eql(u8, current, try variantNameUnder(a, &environment, "core-runtime-object-v4")));
}
