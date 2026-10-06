//! Turn emitted LLVM IR into an executable with the bundled clang (`zig cc`).
//!
//! The runtime is compiled once per content into the work directory at -O2,
//! whatever the program's level, so a debug build pays only for the program's
//! own code. The program's `.ll` is compiled at -O0 (debug) or -O3 for the
//! target CPU (release, L4; `target.zig`) and linked with the runtime and any `--link` C files.
//! A minimal driver rather than the old core's `qbe_build_llvm_compile.zig`:
//! that one is bound to the QBE manifest, fragment store and object cache.
const std = @import("std");
const target = @import("target.zig").current;

/// The runtime C source, compiled into every program.
pub const runtime_source = @embedFile("runtime/core_rt.c") ++ "\n" ++
    @embedFile("runtime/core_dict.c") ++ "\n" ++
    @embedFile("runtime/core_text.c") ++ "\n" ++
    @embedFile("runtime/core_sort.c") ++ "\n" ++ @embedFile("runtime/core_number.c") ++ "\n" ++
    @embedFile("runtime/core_io.c") ++ "\n" ++ @embedFile("runtime/core_bytes.c") ++ "\n" ++
    @embedFile("runtime/core_values.c");

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

/// Compile and link `request.llvm` into `request.output`; failures append the tool's stderr to `log`.
pub fn link(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, request: Request, log: *std.ArrayList(u8)) Error!void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, request.work) catch return error.WriteFailed;
    var environment = environ.clone(allocator) catch return error.OutOfMemory;
    defer environment.deinit();
    environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(allocator, &.{ request.work, "zig-local" })) catch return error.OutOfMemory;
    const runtime_object = try runtimeObject(allocator, io, &environment, request, log);
    const program = request.program;
    cwd.writeFile(io, .{ .sub_path = program, .data = request.llvm }) catch return error.WriteFailed;
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ request.zig, "cc", if (request.release) "-O3" else "-O0" });
    try argv.appendSlice(allocator, target.cpu_flags);
    try argv.appendSlice(allocator, &.{ "-Wno-override-module", "-o", request.output, program, runtime_object });
    try argv.appendSlice(allocator, request.links);
    try run(allocator, io, &environment, argv.items, log);
}

/// The runtime object for this runtime source, compiled on first use.
fn runtimeObject(allocator: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, request: Request, log: *std.ArrayList(u8)) Error![]const u8 {
    var digest: [8]u8 = undefined;
    std.crypto.hash.Blake3.hash(runtime_source, &digest, .{});
    const stem = try std.fmt.allocPrint(allocator, "core_rt-{x}", .{digest});
    const object = try std.fs.path.join(allocator, &.{ request.work, try std.fmt.allocPrint(allocator, "{s}.o", .{stem}) });
    const cwd = std.Io.Dir.cwd();
    if (cwd.access(io, object, .{})) |_| return object else |_| {}
    const source = try std.fs.path.join(allocator, &.{ request.work, try std.fmt.allocPrint(allocator, "{s}.c", .{stem}) });
    cwd.writeFile(io, .{ .sub_path = source, .data = runtime_source }) catch return error.WriteFailed;
    const partial = try std.fmt.allocPrint(allocator, "{s}.partial", .{object});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ request.zig, "cc", "-c", "-O2" });
    try argv.appendSlice(allocator, target.cpu_flags);
    try argv.appendSlice(allocator, &.{ "-std=c11", "-o", partial, source });
    try run(allocator, io, environment, argv.items, log);
    cwd.rename(partial, cwd, object, io) catch return error.WriteFailed;
    return object;
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
