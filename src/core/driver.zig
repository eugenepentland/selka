//! Turn emitted LLVM IR into an executable with the bundled clang (`zig cc`).
//!
//! The runtime is compiled once per content into the work directory at -O2,
//! whatever the program's level, so a debug build pays only for the program's
//! own code. The program's `.ll` is compiled at -O0 (debug) or -O3 for the
//! target CPU (release, L4; `target.zig`) and linked with the runtime and any `--link` C files.
//! A minimal driver rather than the old core's `qbe_build_llvm_compile.zig`:
//! that one is bound to the QBE manifest, fragment store and object cache.
const std = @import("std");
const target_policy = @import("target.zig");
const target = target_policy.current;
const number_runtime = @import("number_runtime.zig");
const tool_identity = @import("tool_identity.zig");

/// The runtime C source, compiled into every program.
pub const runtime_source = @embedFile("runtime/core_rt.c") ++ "\n" ++
    @embedFile("runtime/core_dict.c") ++ "\n" ++
    @embedFile("runtime/core_unicode_data.h") ++ "\n" ++
    @embedFile("runtime/core_text.c") ++ "\n" ++
    @embedFile("runtime/core_sort.c") ++ "\n" ++ @embedFile("runtime/core_number.c") ++ "\n" ++
    @embedFile("runtime/core_io.c") ++ "\n" ++ @embedFile("runtime/core_host.c") ++ "\n" ++
    @embedFile("runtime/core_bytes.c") ++ "\n" ++ @embedFile("runtime/core_values.c") ++ "\n" ++ @embedFile("runtime/core_test.c");

/// One build: tools, directories, the program and how to optimize it.
pub const Request = struct {
    /// The `zig` executable whose `cc` compiles and links.
    zig: []const u8,
    /// Scratch directory for the runtime object and clang's cache.
    work: []const u8,
    /// Where the program's `.ll` is written (unique per output, so builds can run at once).
    program: []const u8,
    output: []const u8,
    release: bool,
    /// Extra C sources to compile and link (`--link`).
    links: []const []const u8,
    llvm: []const u8,
};

/// Why a native build failed; the tool's output was written to `log`.
pub const Error = error{ ToolFailed, OutOfMemory, WriteFailed };

const Guard = struct {
    resources: tool_identity.Request,
    identity: tool_identity.Identity,

    /// Validate the captured tool before publishing a native object or accepting a link.
    pub fn check(self: Guard, log: *std.ArrayList(u8)) Error!void {
        const stable = tool_identity.unchanged(self.resources, self.identity) catch |err| changed: {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            break :changed false;
        };
        if (!stable) {
            try log.appendSlice(self.resources.arena, "error: guest toolchain changed during native compilation\n");
            return error.ToolFailed;
        }
    }
};

const NativeCache = struct { work: []const u8, isolate: bool };

/// Compile and link `request.llvm` into `request.output`; failures append the tool's stderr to `log`.
pub fn link(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, request: Request, log: *std.ArrayList(u8)) Error!void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, request.work) catch return error.WriteFailed;
    var environment = environ.clone(allocator) catch return error.OutOfMemory;
    defer environment.deinit();
    environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(allocator, &.{ request.work, "zig-local" })) catch return error.OutOfMemory;
    const resources: tool_identity.Request = .{ .arena = allocator, .io = io, .environment = &environment, .executable = request.zig, .cache = request.work };
    const guest = tool_identity.capture(resources) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try log.print(allocator, "error: cannot run {s}: cannot identify guest toolchain: {s}\n", .{ request.zig, @errorName(err) });
        return error.ToolFailed;
    };
    const guard: Guard = .{ .resources = resources, .identity = guest };
    var resolved = request;
    resolved.zig = guest.path;
    if (!guest.cacheable) {
        var nonce: [16]u8 = undefined;
        std.Io.random(io, &nonce);
        resolved.work = try std.fs.path.join(allocator, &.{ request.work, try std.fmt.allocPrint(allocator, "unproved-tool-{s}", .{std.fmt.bytesToHex(nonce, .lower)}) });
        cwd.createDirPath(io, resolved.work) catch return error.WriteFailed;
    }
    defer if (!guest.cacheable) removeDirectory(io, resolved.work);
    const runtime_object = try runtimeObject(allocator, io, &environment, resolved, log, guard);
    const program = request.program;
    cwd.writeFile(io, .{ .sub_path = program, .data = request.llvm }) catch return error.WriteFailed;
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ guest.path, "cc", if (request.release) "-O3" else "-O0" });
    try argv.appendSlice(allocator, &.{ "-target", target_policy.native_link_target });
    try argv.appendSlice(allocator, target.cpu_flags);
    try argv.appendSlice(allocator, &.{ "-Wno-override-module", "-o", request.output, program, runtime_object });
    if (number_runtime.needed(request.llvm)) {
        var numeric = resolved;
        numeric.work = try std.fs.path.join(allocator, &.{ resolved.work, try std.fmt.allocPrint(allocator, "number-tool-v2-{s}", .{std.fmt.bytesToHex(guest.digest, .lower)}) });
        try argv.append(allocator, try number_runtime.object(allocator, io, &environment, numeric, log, guard));
    }
    try argv.appendSlice(allocator, request.links);
    if (std.mem.indexOf(u8, request.llvm, "llvm.sin.f64") != null or std.mem.indexOf(u8, request.llvm, "llvm.cos.f64") != null) try argv.append(allocator, "-lm");
    try linkNative(allocator, io, &environment, .{ .work = resolved.work, .isolate = request.links.len != 0 or !guest.cacheable }, argv.items, log);
    try guard.check(log);
}

fn linkNative(allocator: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, cache: NativeCache, argv: []const []const u8, log: *std.ArrayList(u8)) Error!void {
    if (!cache.isolate) return run(allocator, io, environment, argv, log);
    // Zig's foreign-source cache can miss same-size header edits with restored
    // mtimes. Unproved inputs get fresh caches; the captured Guard environment
    // stays unchanged, and closed runtime/numeric objects keep their own keys.
    var linking = environment.clone(allocator) catch return error.OutOfMemory;
    defer linking.deinit();
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const private = try std.fs.path.join(allocator, &.{ cache.work, try std.fmt.allocPrint(allocator, "native-link-{s}", .{std.fmt.bytesToHex(nonce, .lower)}) });
    std.Io.Dir.cwd().createDirPath(io, private) catch return error.WriteFailed;
    defer removeDirectory(io, private);
    linking.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(allocator, &.{ private, "local" })) catch return error.OutOfMemory;
    linking.put("ZIG_GLOBAL_CACHE_DIR", try std.fs.path.join(allocator, &.{ private, "global" })) catch return error.OutOfMemory;
    try run(allocator, io, &linking, argv, log);
}

/// The runtime object for this runtime source, compiled on first use.
fn runtimeObject(allocator: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, request: Request, log: *std.ArrayList(u8), guard: Guard) Error![]const u8 {
    var digest: [32]u8 = undefined;
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("core-runtime-object-v2\x00-O2\x00-std=c11\x00");
    hash.update(target_policy.native_link_target);
    hash.update("\x00");
    hash.update(runtime_source);
    hash.update(&guard.identity.digest);
    hash.final(&digest);
    const stem = try std.fmt.allocPrint(allocator, "core_rt-{x}", .{digest});
    const object = try std.fs.path.join(allocator, &.{ request.work, try std.fmt.allocPrint(allocator, "{s}.o", .{stem}) });
    const cwd = std.Io.Dir.cwd();
    if (cwd.access(io, object, .{})) |_| return object else |_| {}
    const source = try std.fs.path.join(allocator, &.{ request.work, try std.fmt.allocPrint(allocator, "{s}.c", .{stem}) });
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const staging = try std.fmt.allocPrint(allocator, "{s}.{x}.partial", .{ source, nonce });
    defer removeFile(io, staging);
    cwd.writeFile(io, .{ .sub_path = staging, .data = runtime_source }) catch return error.WriteFailed;
    cwd.rename(staging, cwd, source, io) catch return error.WriteFailed;
    const partial = try std.fmt.allocPrint(allocator, "{s}.{x}.partial", .{ object, nonce });
    defer removeFile(io, partial);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ request.zig, "cc", "-c", "-O2" });
    try argv.appendSlice(allocator, &.{ "-target", target_policy.native_link_target });
    try argv.appendSlice(allocator, target.cpu_flags);
    try argv.appendSlice(allocator, &.{ "-std=c11", "-o", partial, source });
    try run(allocator, io, environment, argv.items, log);
    try guard.check(log);
    cwd.rename(partial, cwd, object, io) catch return error.WriteFailed;
    return object;
}

fn removeFile(io: std.Io, path: []const u8) void {
    // A successfully published file already moved away; cleanup is best effort.
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

fn removeDirectory(io: std.Io, path: []const u8) void {
    // Best-effort cleanup of this build's owned random runtime staging directory.
    std.Io.Dir.cwd().deleteTree(io, path) catch return;
}

fn run(allocator: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, argv: []const []const u8, log: *std.ArrayList(u8)) Error!void {
    const result = std.process.run(allocator, io, .{ .argv = argv, .environ_map = environment }) catch |err| {
        try log.print(allocator, "error: cannot run {s}: {s}\n", .{ argv[0], @errorName(err) });
        return error.ToolFailed;
    };
    try log.appendSlice(allocator, result.stderr);
    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!ok) return error.ToolFailed;
}

// spec-case: NEW-CORE-S4-TEST-3
test "Guard.check refuses changed and missing tool inputs and propagates allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "zig", .data = "first" });
    try directory.dir.setFilePermissions(std.testing.io, "zig", .executable_file, .{});
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = std.process.Environ.Map.init(a);
    const resources: tool_identity.Request = .{ .arena = a, .io = std.testing.io, .environment = &environment, .executable = try std.fs.path.join(a, &.{ root, "zig" }), .cache = try std.fs.path.join(a, &.{ root, "cache" }) };
    const guard: Guard = .{ .resources = resources, .identity = try tool_identity.capture(resources) };
    var log: std.ArrayList(u8) = .empty;
    try guard.check(&log);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "zig", .data = "other" });
    try std.testing.expectError(error.ToolFailed, guard.check(&log));
    try std.testing.expect(std.mem.indexOf(u8, log.items, "toolchain changed") != null);
    try directory.dir.deleteFile(std.testing.io, "zig");
    try std.testing.expectError(error.ToolFailed, guard.check(&log));
    var failing = guard;
    failing.resources.arena = std.testing.failing_allocator;
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "zig", .data = "other" });
    try directory.dir.setFilePermissions(std.testing.io, "zig", .executable_file, .{});
    try std.testing.expectError(error.OutOfMemory, failing.check(&log));
}
