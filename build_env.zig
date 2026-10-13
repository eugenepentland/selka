//! The build graph's environment tool, `build-env` (ENV-PROJECTION-1,
//! ENV-PROJECTION-2): one definition both keys the environment a cached test
//! verdict depends on and projects the environment its command runs in, so a
//! variable that is not keyed cannot reach a test ("run what you key",
//! `docs/tooling/environment-identity.md`).
//!
//! Like `build_identity.zig`, the file has two halves. `tool` runs in
//! `build.zig`'s configure phase and only declares the host executable; `main`
//! is the same file compiled for the build host and run in the make phase:
//!
//! - `build-env digest OUT TOOL...` writes the environment manifest to `OUT`:
//!   the host-scope digest of `environment_identity.zig` over the live
//!   environment and the named tools on the first line, then the keyed
//!   `NAME=VALUE` lines and one `tool:NAME=SHA256` line per tool. A `TOOL` is
//!   `NAME=PATH`, or a bare `NAME` that is resolved on the live `PATH` here, at
//!   make time, so the configure phase never bakes a tool location.
//! - `build-env project -- CMD ARGS...` replaces itself with `CMD ARGS...`,
//!   passing only the variables the contract lets a child receive. The command
//!   keeps this process's pid, exit status and resource accounting, so it stays
//!   the build runner's own child. It exits with status 2 when `CMD` cannot be
//!   executed.
//!
//! The parsing, projection and manifest rendering are pure functions in
//! `src/build_env_rules.zig`, tested from the unit root.
const std = @import("std");
const identity = @import("src/environment_identity.zig");
const rules = @import("src/build_env_rules.zig");

/// Declare the `build-env` host executable. It is compiled for the build
/// host, optimized because `digest` hashes the whole Zig toolchain binary on
/// every build, and run by `build.zig` around every cached test step.
pub fn tool(b: *std.Build, compile_rss: u64) *std.Build.Step.Compile {
    return b.addExecutable(.{ .max_rss = compile_rss, .name = "build-env", .root_module = b.createModule(.{
        .root_source_file = b.path("build_env.zig"),
        .target = b.graph.host,
        .optimize = .ReleaseSafe,
    }) });
}

/// Make-phase entry point: `build-env digest OUT TOOL...` or
/// `build-env project -- CMD ARGS...`.
pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    const command = rules.parse(args[1..]) orelse fail("usage: build-env digest OUT [NAME[=PATH]...] | build-env project -- CMD [ARGS...]", .{});
    switch (command) {
        .digest => |request| try writeDigest(init, request.out, request.tools),
        .project => |argv| {
            var projected = std.process.Environ.Map.init(a);
            try rules.project(init.environ_map, &projected);
            const failure = std.process.replace(init.io, .{ .argv = argv, .environ_map = &projected });
            fail("cannot execute {s}: {t}", .{ argv[0], failure });
        },
    }
}

/// Report a usage or execution failure on standard error and exit with status 2.
fn fail(comptime format: []const u8, arguments: anytype) noreturn {
    std.debug.print("build-env: " ++ format ++ "\n", arguments);
    std.process.exit(2);
}

/// Write the manifest of the live environment and the named tools to `out`.
fn writeDigest(init: std.process.Init, out: []const u8, requests: []const []const u8) !void {
    const a = init.arena.allocator();
    const variables = rules.variablesOf(init.environ_map, try a.alloc(identity.Variable, init.environ_map.count()));
    const tools = try a.alloc(identity.Tool, requests.len);
    for (requests, 0..) |argument, index| {
        const request = rules.toolRequest(argument).?;
        for (tools[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.name, request.name)) fail("tool {s} is named twice", .{request.name});
        }
        const path = request.path orelse searchPath(init, request.name);
        tools[index] = .{ .name = request.name, .digest = if (path) |file| try fileDigest(init, file) else rules.absent_tool };
    }
    var text: std.Io.Writer.Allocating = .init(a);
    try rules.writeManifest(&text.writer, variables, tools);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = out, .data = text.written() });
}

/// The first executable `name` in a directory of the live `PATH`, as a shell
/// would find it, or null when there is none.
fn searchPath(init: std.process.Init, name: []const u8) ?[]const u8 {
    const a = init.arena.allocator();
    var directories = std.mem.splitScalar(u8, init.environ_map.get("PATH") orelse return null, ':');
    while (directories.next()) |directory| {
        const candidate = std.fs.path.join(a, &.{ if (directory.len == 0) "." else directory, name }) catch return null;
        const stat = std.Io.Dir.cwd().statFile(init.io, candidate, .{}) catch continue;
        if (stat.kind != .file) continue;
        std.Io.Dir.cwd().access(init.io, candidate, .{ .execute = true }) catch continue;
        return candidate;
    }
    return null;
}

/// Lowercase hex SHA-256 of the file at `path`, or `absent_tool` when it cannot be read.
fn fileDigest(init: std.process.Init, path: []const u8) ![]const u8 {
    const file = std.Io.Dir.cwd().openFile(init.io, path, .{}) catch return rules.absent_tool;
    defer file.close(init.io);
    var buffer: [1 << 16]u8 = undefined;
    var reader = file.reader(init.io, &buffer);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    var chunk: [1 << 16]u8 = undefined;
    while (true) {
        const count = reader.interface.readSliceShort(&chunk) catch return rules.absent_tool;
        if (count == 0) break;
        hash.update(chunk[0..count]);
    }
    var bytes: [32]u8 = undefined;
    hash.final(&bytes);
    return try init.arena.allocator().dupe(u8, &std.fmt.bytesToHex(bytes, .lower));
}
