//! End-to-end tests of the C interop additions (D-FFI-2 to D-FFI-5, D-FFI-7; `docs/c-ffi.md`): the fixtures under
//! `test/core/c_interop*` built with `--link test/core/c_interop.c` and run, the guest tests that reach C under
//! `selka test --allow-host`, and the cache keys of an `extern func` whose parameter changes kind.
const std = @import("std");
const options = @import("core_test_options");
const support = @import("test_support.zig");

const io = std.testing.io;
const report = std.debug.print;

/// The C side of every fixture here.
const c_source = "test/core/c_interop.c";

const Outcome = struct { stdout: []const u8, stderr: []const u8, status: u8 };

fn statusOf(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        else => 255,
    };
}

/// Build `test/core/NAME.selka` with the C fixture and `flags`, run it with `environment`, and answer what it printed.
fn buildAndRun(a: std.mem.Allocator, name: []const u8, flags: []const []const u8, environment: *std.process.Environ.Map) !Outcome {
    return buildAndRunWith(a, name, c_source, flags, environment);
}

/// `buildAndRun` with the C file `c` in place of the C fixture.
fn buildAndRunWith(a: std.mem.Allocator, name: []const u8, c: []const u8, flags: []const []const u8, environment: *std.process.Environ.Map) !Outcome {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const source = try std.fmt.allocPrint(a, "{s}/{s}.selka", .{ options.fixtures, name });
    const output = try std.fs.path.join(a, &.{ root, name });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "build", source, "-o", output, "--link", c, "--cache-dir", try options.suiteCache(a, @src()) });
    try argv.appendSlice(a, flags);
    try support.requireReleaseArgs(argv.items);
    const built = try std.process.run(a, io, .{ .argv = argv.items, .environ_map = environment });
    if (statusOf(built.term) != 0) {
        report("build of {s} failed:\n{s}{s}\n", .{ name, built.stdout, built.stderr });
        return error.BuildFailed;
    }
    const ran = try std.process.run(a, io, .{ .argv = &.{output}, .environ_map = environment });
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = statusOf(ran.term) };
}

const c_interop_output =
    \\259 514 0
    \\2000003 2000
    \\True 0 0
    \\2997
    \\7 19 5 True
    \\1 2
    \\10 22
    \\41 -1 False True
    \\41 True
    \\-1 0 -1
    \\0 65 1 True
    \\2 3
    \\0
    \\
;

fn expectFixture(a: std.mem.Allocator, flags: []const []const u8) !void {
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const got = try buildAndRun(a, "c_interop", flags, &environment);
    if (!std.mem.eql(u8, got.stdout, c_interop_output)) report("c_interop printed:\n{s}{s}\n", .{ got.stdout, got.stderr });
    try std.testing.expectEqualStrings(c_interop_output, got.stdout);
    try std.testing.expectEqual(@as(u8, 0), got.status);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "leakcheck") == null);
}

// spec-case: C-FFI-2
test "C interop: str and bytes spans, a copied bytes result, out-parameters and handles reach C and come back, with every validator on" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectFixture(arena.allocator(), &.{ "--verify-ownership", "--verify-facts-static" });
}

// Skipped by default: release builds run only with `-Dtest-release`.
test "C interop: the C interop fixture gives the same output in a release build with every validator on (release)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectFixture(arena.allocator(), &.{ "--release", "--verify-ownership", "--verify-facts-static" });
}

fn expectForeignTrap(a: std.mem.Allocator, name: []const u8, detail: []const u8) !void {
    var environment = try options.privateEnvironment(a);
    const got = try buildAndRun(a, name, &.{}, &environment);
    try std.testing.expectEqual(@as(u8, 1), got.status);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "error[R_FOREIGN_RESULT]") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, detail) != null);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, name) != null);
}

test "C interop: a bytes result with a negative length traps R_FOREIGN_RESULT at the call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectForeignTrap(arena.allocator(), "c_interop_trap_negative", "(length -1)");
}

test "C interop: a bytes result with a null pointer and a positive length traps R_FOREIGN_RESULT at the call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectForeignTrap(arena.allocator(), "c_interop_trap_null", "(null pointer, length 3)");
}

test "C interop: 100,000 copied bytes results and handle round trips leave nothing live under the leak check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const got = try buildAndRun(a, "c_interop_leak", &.{}, &environment);
    try std.testing.expectEqualStrings("666665 0\n", got.stdout);
    try std.testing.expectEqual(@as(u8, 0), got.status);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "leakcheck") == null);
}

/// `selka test` of the guest tests that call C, with `extra` flags.
fn guestTests(a: std.mem.Allocator, extra: []const []const u8) !Outcome {
    var environment = try options.privateEnvironment(a);
    var argv: std.ArrayList([]const u8) = .empty;
    const entry = try std.fmt.allocPrint(a, "{s}/c_interop_tests.selka", .{options.fixtures});
    try argv.appendSlice(a, &.{ options.corePath(), "test", entry, "--link", c_source, "--cache-dir", try options.suiteCache(a, @src()) });
    try argv.appendSlice(a, extra);
    const ran = try std.process.run(a, io, .{ .argv = argv.items, .environ_map = &environment });
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = statusOf(ran.term) };
}

// spec-case: C-FFI-7
test "C interop: selka test --allow-host hands the live Host to the tests that declare it, so they call C" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const got = try guestTests(arena.allocator(), &.{"--allow-host"});
    try std.testing.expectEqual(@as(u8, 0), got.status);
    try std.testing.expect(std.mem.indexOf(u8, got.stdout, "5 passed, 0 cached, 0 failed") != null);
}

// spec-case: C-FFI-7
test "C interop: without --allow-host a test that declares host: Host fails before it is built and names the flag" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const got = try guestTests(arena.allocator(), &.{});
    try std.testing.expectEqual(@as(u8, 1), got.status);
    try std.testing.expect(std.mem.indexOf(u8, got.stdout, "1 passed, 0 cached, 4 failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.stdout, "the Host capability is handed to a test only under `selka test --allow-host`") != null);
}

/// One version of the declaring module of the key test: its `extern func` parameter, the argument its `arg` builds,
/// the C definition and what the program prints.
const KeyVersion = struct { module: []const u8, c: []const u8, expected: []const u8 };

const key_versions = [_]KeyVersion{
    .{
        .module = "public extern func ffi_key(host: Host, value: i64) -> i64\n\n\npublic func arg() -> i64:\n    return 5\n",
        .c = "#include <stdint.h>\nint64_t ffi_key(int64_t value) { return value * 2; }\n",
        .expected = "10\n",
    },
    .{
        .module = "public extern func ffi_key(host: Host, value: str) -> i64\n\n\npublic func arg() -> str:\n    return \"hello\"\n",
        .c = "#include <stdint.h>\nint64_t ffi_key(const uint8_t *data, int64_t length) { return data ? length * 100 : -1; }\n",
        .expected = "500\n",
    },
    .{
        .module = "public extern type Thing\n\n\npublic extern func ffi_key(host: Host, value: Thing) -> i64\n\n\npublic func arg() -> Thing:\n    return Thing()\n",
        .c = "#include <stdint.h>\nint64_t ffi_key(void *thing) { return thing ? 7 : -7; }\n",
        .expected = "-7\n",
    },
};

/// The caller, whose text never changes: only the declaring module `keys` does.
const key_main = "import keys\n\n\nfunc main(host: Host, out: Stream) -> int:\n    print(out, keys.ffi_key(host, keys.arg()))\n    return 0\n";

/// Write version `version` of the key project into `root`, build it with `cache` and run it.
fn keyBuild(a: std.mem.Allocator, root: []const u8, version: KeyVersion, cache: []const u8, environment: *std.process.Environ.Map) ![]const u8 {
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    try dir.writeFile(io, .{ .sub_path = "main.selka", .data = key_main });
    try dir.writeFile(io, .{ .sub_path = "keys.selka", .data = version.module });
    try dir.writeFile(io, .{ .sub_path = "key.c", .data = version.c });
    const output = try std.fs.path.join(a, &.{ root, "app" });
    const built = try std.process.run(a, io, .{
        .argv = &.{ options.corePath(), "build", try std.fs.path.join(a, &.{ root, "main.selka" }), "-o", output, "--link", try std.fs.path.join(a, &.{ root, "key.c" }), "--cache-dir", cache },
        .environ_map = environment,
    });
    if (statusOf(built.term) != 0) {
        report("key build failed:\n{s}{s}\n", .{ built.stdout, built.stderr });
        return error.BuildFailed;
    }
    const ran = try std.process.run(a, io, .{ .argv = &.{output}, .environ_map = environment });
    return ran.stdout;
}

// spec-case: C-FFI-KEYS-1
test "C interop: changing an extern func parameter from i64 to str and to an extern type rebuilds its caller in a local cache" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try options.privateEnvironment(a);
    try environment.put("XDG_CACHE_HOME", try std.fs.path.join(a, &.{ root, "xdg" }));
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    try std.testing.expectEqualStrings(key_versions[0].expected, try keyBuild(a, root, key_versions[0], cache, &environment));
    try std.testing.expectEqualStrings(key_versions[1].expected, try keyBuild(a, root, key_versions[1], cache, &environment));
    try std.testing.expectEqualStrings(key_versions[2].expected, try keyBuild(a, root, key_versions[2], cache, &environment));
    try std.testing.expectEqualStrings(key_versions[0].expected, try keyBuild(a, root, key_versions[0], cache, &environment));
}

test "C interop: changing an extern func parameter from i64 to str and to an extern type rebuilds its caller through the shared stage store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try options.privateEnvironment(a);
    try environment.put("XDG_CACHE_HOME", try std.fs.path.join(a, &.{ root, "xdg" }));
    try environment.put("SELKA_STAGE_SHARED_CACHE", try std.fs.path.join(a, &.{ root, "shared" }));
    // A fresh work directory per build: only the shared half of the stage store connects them.
    try std.testing.expectEqualStrings(key_versions[0].expected, try keyBuild(a, root, key_versions[0], try std.fs.path.join(a, &.{ root, "cache-0" }), &environment));
    try std.testing.expectEqualStrings(key_versions[1].expected, try keyBuild(a, root, key_versions[1], try std.fs.path.join(a, &.{ root, "cache-1" }), &environment));
    try std.testing.expectEqualStrings(key_versions[2].expected, try keyBuild(a, root, key_versions[2], try std.fs.path.join(a, &.{ root, "cache-2" }), &environment));
    try std.testing.expectEqualStrings(key_versions[0].expected, try keyBuild(a, root, key_versions[0], try std.fs.path.join(a, &.{ root, "cache-3" }), &environment));
}

fn expectLinearFixture(a: std.mem.Allocator, flags: []const []const u8) !void {
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const got = try buildAndRun(a, "c_interop_linear", flags, &environment);
    try std.testing.expectEqualStrings("28\n3\n1 1\n0\n", got.stdout);
    try std.testing.expectEqual(@as(u8, 0), got.status);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "leakcheck") == null);
}

fn expectOnFailFixture(a: std.mem.Allocator, flags: []const []const u8) !void {
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const got = try buildAndRun(a, "c_on_fail", flags, &environment);
    // Each shape and how many of its nine runs failed; every run left no C object live.
    try std.testing.expectEqualStrings("0 4\n1 6\n2 2\n3 3\n4 2\n5 3\n6 2\n7 2\n8 1\n9 2\n10 2\n11 3\nlive 0\n", got.stdout);
    try std.testing.expectEqual(@as(u8, 0), got.status);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "leakcheck") == null);
}

// spec-case: ON-FAIL-1
test "C interop: on fail closes every C object on every forced failure path, with every validator on" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectOnFailFixture(arena.allocator(), &.{ "--verify-ownership", "--verify-facts-static" });
}

// Skipped by default: release builds run only with `-Dtest-release`.
test "C interop: on fail gives the same output in a release build with every validator on (release)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectOnFailFixture(arena.allocator(), &.{ "--release", "--verify-ownership", "--verify-facts-static" });
}

// spec-case: LINEAR-RECORDS-2
test "C interop: @linear wrappers around handles close every C object, with every validator on" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectLinearFixture(arena.allocator(), &.{ "--verify-ownership", "--verify-facts-static" });
}

// Skipped by default: release builds run only with `-Dtest-release`.
test "C interop: @linear wrappers give the same output in a release build with every validator on (release)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectLinearFixture(arena.allocator(), &.{ "--release", "--verify-ownership", "--verify-facts-static" });
}

/// The C side of the `@address` fixtures (MCU-NOC3): getters that hand back function pointers.
const address_c = "test/core/c_address.c";

fn expectAddressFixture(a: std.mem.Allocator, flags: []const []const u8) !void {
    var environment = try options.privateEnvironment(a);
    try environment.put("SELKA_CORE_LEAKCHECK", "1");
    const got = try buildAndRunWith(a, "c_address", address_c, flags, &environment);
    // Eight `i64` (two on the stack) and an `i64` result through a handle and a `u64`; narrow scalars; a span and an
    // out-parameter: each the C function's own answer.
    try std.testing.expectEqualStrings("8000000000140\n2999999999860\n1318\nTrue 4\n", got.stdout);
    try std.testing.expectEqual(@as(u8, 0), got.status);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "leakcheck") == null);
}

// spec-case: C-FFI-ADDRESS-2
test "C interop: @address extern funcs call the function pointers C hands back, as a handle and as a u64, with every validator on" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectAddressFixture(arena.allocator(), &.{ "--verify-ownership", "--verify-facts-static" });
}

// Skipped by default: release builds run only with `-Dtest-release`.
test "C interop: the @address fixture gives the same output in a release build (release)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try expectAddressFixture(arena.allocator(), &.{"--release"});
}

// spec-case: C-FFI-ADDRESS-3
test "C interop: a call through a null handle traps R_FOREIGN_TARGET at the call, after what ran before it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try options.privateEnvironment(a);
    const got = try buildAndRunWith(a, "c_address_trap", address_c, &.{}, &environment);
    try std.testing.expectEqual(@as(u8, 1), got.status);
    try std.testing.expectEqualStrings("before\n", got.stdout);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "c_address_trap.selka:15:16: error[R_FOREIGN_TARGET]") != null);
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "null handle or the address 0") != null);
}

// spec-case: C-FFI-ADDRESS-2
test "C interop: selka test --allow-host runs guest tests that call C through a handle and an address" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try options.privateEnvironment(a);
    const entry = try std.fmt.allocPrint(a, "{s}/c_address_tests.selka", .{options.fixtures});
    const ran = try std.process.run(a, io, .{
        .argv = &.{ options.corePath(), "test", entry, "--allow-host", "--link", address_c, "--cache-dir", try options.suiteCache(a, @src()) },
        .environ_map = &environment,
    });
    try std.testing.expectEqual(@as(u8, 0), statusOf(ran.term));
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "3 passed, 0 cached, 0 failed") != null);
}

/// Build `source` as `main.selka` in a fresh directory with `--link test/core/c_address.c` and `flags`.
fn addressBuild(a: std.mem.Allocator, root: []const u8, source: []const u8, flags: []const []const u8) !std.process.RunResult {
    var dir = try std.Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    try dir.writeFile(io, .{ .sub_path = "main.selka", .data = source });
    var environment = try options.privateEnvironment(a);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "build", try std.fs.path.join(a, &.{ root, "main.selka" }), "-o", try std.fs.path.join(a, &.{ root, "app" }), "--link", address_c, "--cache-dir", try options.suiteCache(a, @src()) });
    try argv.appendSlice(a, flags);
    return std.process.run(a, io, .{ .argv = argv.items, .environ_map = &environment });
}

// spec-case: C-FFI-ADDRESS-2
test "C interop: an @address call is an indirect call with the declared types, after a null check, and names no symbol" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const llvm = try std.fs.path.join(a, &.{ root, "main.ll" });
    const built = try addressBuild(a, root,
        \\extern func ffi_weigh_address(host: Host) -> u64
        \\
        \\
        \\@address
        \\extern func weigh_at(host: Host, target: u64, a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) -> i64
        \\
        \\
        \\func main(host: Host, out: Stream) -> int:
        \\    print(out, weigh_at(host, ffi_weigh_address(host), 1, 2, 3, 4, 5, 6, 7, 8))
        \\    return 0
        \\
    , &.{ "--emit-llvm", llvm });
    try std.testing.expectEqual(@as(u8, 0), statusOf(built.term));
    const text = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .unlimited);
    try std.testing.expect(std.mem.indexOf(u8, text, "weigh_at") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "declare i64 @ffi_weigh_address()") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "  %address.null.1 = icmp eq i64 %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, " = inttoptr i64 %v") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, " = call i64 %address.4(i64 1, i64 2, i64 3, i64 4, i64 5, i64 6, i64 7, i64 8)") != null);
}

// A device library declares its ROM calls with `u32` targets and still builds, and tests, on a 64-bit host: a `u32`
// address fits in a wider pointer, so only a target wider than the machine's addresses is refused.
test "C interop: an @address target of u32 builds where addresses are 64 bits, zero-extended into the pointer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const llvm = try std.fs.path.join(a, &.{ root, "main.ll" });
    const built = try addressBuild(a, root,
        \\@address
        \\extern func at(host: Host, target: u32, a: i64) -> i64
        \\
        \\
        \\func main(host: Host) -> int:
        \\    return at(host, u32(16), 1)
        \\
    , &.{ "--emit-llvm", llvm });
    // The program is built, not run: nothing lives at address 16.
    try std.testing.expectEqual(@as(u8, 0), statusOf(built.term));
    const text = try std.Io.Dir.cwd().readFileAlloc(io, llvm, a, .unlimited);
    try std.testing.expect(std.mem.indexOf(u8, built.stderr, "an `@address` extern target") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, " = inttoptr i32 ") != null);
}

/// Build `source` as `main.selka` with `--link test/core/c_address.c` and run it (MCU-NOC2C, freestanding functions on Linux).
fn freestandingRun(a: std.mem.Allocator, root: []const u8, source: []const u8) !Outcome {
    const built = try addressBuild(a, root, source, &.{});
    if (statusOf(built.term) != 0) {
        report("build failed:\n{s}{s}\n", .{ built.stdout, built.stderr });
        return error.BuildFailed;
    }
    var environment = try options.privateEnvironment(a);
    const ran = try std.process.run(a, io, .{ .argv = &.{try std.fs.path.join(a, &.{ root, "app" })}, .environ_map = &environment });
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = statusOf(ran.term) };
}

// spec-case: MCU-NOC2C
test "C interop: a freestanding function calls C by name and through an address on Linux" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const got = try freestandingRun(a, root,
        \\extern func ffi_weigh_address(host: Host) -> u64
        \\
        \\
        \\@address
        \\extern func weigh_at(host: Host, target: u64, a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) -> i64
        \\
        \\
        \\@freestanding
        \\func through(host: Host, a: i64) -> i64:
        \\    return weigh_at(host, ffi_weigh_address(host), a, 2, 0, 0, 0, 0, 0, 0)
        \\
        \\
        \\func main(host: Host, out: Stream) -> int:
        \\    print(out, through(host, 48))
        \\    return 0
        \\
    );
    try std.testing.expectEqualStrings("52\n", got.stdout);
    try std.testing.expectEqual(@as(u8, 0), got.status);
}

// spec-case: MCU-NOC2C
test "C interop: a freestanding call through the address 0 is a fault reported as error[R_FOREIGN_TARGET] PATH:LINE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const got = try freestandingRun(a, root,
        \\extern func ffi_no_function(host: Host) -> u64
        \\
        \\
        \\@address
        \\extern func weigh_at(host: Host, target: u64, a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64, h: i64) -> i64
        \\
        \\
        \\@freestanding
        \\func through(host: Host, a: i64) -> i64:
        \\    return weigh_at(host, ffi_no_function(host), a, 2, 0, 0, 0, 0, 0, 0)
        \\
        \\
        \\func main(host: Host, out: Stream) -> int:
        \\    print(out, "before")
        \\    print(out, through(host, 48))
        \\    return 0
        \\
    );
    try std.testing.expectEqual(@as(u8, 1), got.status);
    try std.testing.expectEqualStrings("before\n", got.stdout);
    try std.testing.expect(std.mem.startsWith(u8, got.stderr, "error[R_FOREIGN_TARGET] "));
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "main.selka:10\n") != null);
}

/// A freestanding function whose index runs out of range on its fifth call, after `main` has written a line.
const freestanding_bounds_source =
    \\@freestanding
    \\func pick(words: FixedArray[u32, 4], index: int) -> u32:
    \\    return words[index]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, "before the fault")
    \\    const words = FixedArray[u32, 4]([1, 2, 3, 4])
    \\    mut total: u32 = 0
    \\    for i in range(6):
    \\        total = total + pick(words, i)
    \\    return int(total)
    \\
;

// spec-case: MCU-NOC2C
test "C interop: a freestanding bounds fault on Linux keeps earlier output, prints its code and place, and exits as a trap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const got = try freestandingRun(a, root, freestanding_bounds_source);
    try std.testing.expectEqual(@as(u8, 1), got.status);
    try std.testing.expectEqualStrings("before the fault\n", got.stdout);
    const line = std.mem.sliceTo(got.stderr, '\n');
    try std.testing.expect(std.mem.startsWith(u8, line, "error[R_LIST_BOUNDS] ") and std.mem.endsWith(u8, line, "main.selka:3"));
    try std.testing.expect(std.mem.indexOf(u8, got.stderr, "\x1eSELKA-TRAP {\"version\":1,\"operation\":\"freestanding fault\"}\n") != null);
}

// spec-case: MCU-NOC2C
test "C interop: under selka test a freestanding fault is a failed test with its code, not a crashed process" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "faults.selka", .data =
        \\@freestanding
        \\func pick(words: FixedArray[u32, 4], index: int) -> u32:
        \\    return words[index]
        \\
        \\
        \\public func test_fault() -> bool:
        \\    const words = FixedArray[u32, 4]([1, 2, 3, 4])
        \\    return pick(words, 6) == 1
        \\
        \\
        \\public func test_fine() -> bool:
        \\    const words = FixedArray[u32, 4]([1, 2, 3, 4])
        \\    return pick(words, 3) == 4
        \\
    });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    var environment = try options.privateEnvironment(a);
    const ran = try std.process.run(a, io, .{
        .argv = &.{ options.corePath(), "test", try std.fs.path.join(a, &.{ root, "faults.selka" }), "--cache-dir", try options.suiteCache(a, @src()) },
        .environ_map = &environment,
    });
    try std.testing.expectEqual(@as(u8, 1), statusOf(ran.term));
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "failed faults::test_fault: R_LIST_BOUNDS\n") != null);
    // The other test of the file ran in the same program and kept its answer (passed, or cached by a rerun of the suite).
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "faults::test_fine\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, "failed faults::test_fine") == null);
    try std.testing.expect(std.mem.indexOf(u8, ran.stdout, " 1 failed, 0 skipped") != null);
}

/// `selka COMMAND root/ENTRY` through the suite's cache: its status and its output.
fn freestandingCommand(a: std.mem.Allocator, root: []const u8, command: []const u8, cache: []const u8) !Outcome {
    var environment = try options.privateEnvironment(a);
    const ran = try std.process.run(a, io, .{
        .argv = &.{ options.corePath(), command, try std.fs.path.join(a, &.{ root, "importer.selka" }), "--cache-dir", cache },
        .environ_map = &environment,
    });
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = statusOf(ran.term) };
}

// spec-case: MCU-NOC2C
test "C interop: a freestanding function calls a public freestanding function of an imported module, and an edit of the attribute reaches it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const marked =
        \\@freestanding
        \\public func scaled(value: u32) -> u32:
        \\    return value * 3 + 1
        \\
    ;
    try dir.dir.writeFile(io, .{ .sub_path = "parts.selka", .data = marked });
    try dir.dir.writeFile(io, .{ .sub_path = "importer.selka", .data =
        \\import parts
        \\
        \\@freestanding
        \\func combined(value: u32) -> u32:
        \\    return parts.scaled(value) + 1
        \\
        \\
        \\public func test_combined() -> bool:
        \\    return combined(7) == 23
        \\
    });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    const cache = try options.suiteCache(a, @src());
    const first = try freestandingCommand(a, root, "test", cache);
    // Passed, or cached by a rerun of the suite: either way no failure.
    try std.testing.expect(std.mem.indexOf(u8, first.stdout, " 0 failed, 0 skipped") != null);
    // The callee loses the attribute: the cached importer is checked again and refused at its call.
    try dir.dir.writeFile(io, .{ .sub_path = "parts.selka", .data = marked["@freestanding\n".len..] });
    const refused = try freestandingCommand(a, root, "check", cache);
    try std.testing.expectEqual(@as(u8, 1), refused.status);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "importer.selka:5:12: error[E_FREESTANDING]") != null);
    try std.testing.expect(std.mem.indexOf(u8, refused.stderr, "`parts::scaled` is a function not marked @freestanding") != null);
    // And back: the attribute restored, the test passes again.
    try dir.dir.writeFile(io, .{ .sub_path = "parts.selka", .data = marked });
    const again = try freestandingCommand(a, root, "test", cache);
    try std.testing.expect(std.mem.indexOf(u8, again.stdout, "importer::test_combined\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, again.stdout, " 0 failed, 0 skipped") != null);
}
