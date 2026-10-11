//! Authenticated process boundary for Selka-owned ordinary bodies and checked failures.
const std = @import("std");
const value = @import("body_check_value.zig");
const launch = @import("component_launch.zig");
const wire = @import("body_check_protocol.zig");
const config = @import("config/component_runtime.zig");
const reference_mode = config.reference_mode;
const component_mode = config.component_mode;
const component_name = "body-check";
/// Deployment and bounded transport failures cannot become source diagnostics.
pub const Error = launch.Error || error{ ComponentProtocol, ComponentTimeout, ComponentFailed, ComponentIo, ComponentShadowMismatch, ComponentMode, ComponentChanged };
/// Explicit process capabilities shared with the lexer and parser boundaries.
pub const Runtime = config.Runtime;
/// Body check analysis modes; reference is the default for pure and runtime callers.
pub const Mode = enum { reference, shadow, component };
/// Reject unknown mode strings before consulting reusable compiler state.
pub fn mode(runtime: ?Runtime) Error!Mode {
    const capabilities = runtime orelse return .reference;
    const text = capabilities.environ.get("MYLANG_BODY_CHECK_MODE") orelse reference_mode;
    return std.meta.stringToEnum(Mode, text) orelse error.ComponentMode;
}
/// Require complete value equality for shadow execution, including source failure provenance.
pub fn compare(a: std.mem.Allocator, actual: value.Outcome, expected: value.Outcome) Error!void {
    if (!try value.equal(a, actual, expected)) return error.ComponentShadowMismatch;
}
fn directory(a: std.mem.Allocator, runtime: Runtime) Error![]u8 {
    if (runtime.component_dir orelse runtime.environ.get("MYLANG_COMPONENT_DIR")) |dir| return a.dupe(u8, dir);
    const executable = std.process.executableDirPathAlloc(runtime.io, a) catch return error.ComponentIo;
    defer a.free(executable);
    return std.fs.path.join(a, &.{ executable, "..", "libexec", "mylang", "components" });
}
/// Bind selected body check analysis to mode, profile and verified executable bytes.
// twin-drift-ok: Each independent component binds its own mode, wire profile and authenticated package.
pub fn identity(a: std.mem.Allocator, runtime: Runtime) Error![32]u8 {
    const selected = runtime.environ.get("MYLANG_BODY_CHECK_MODE") orelse reference_mode;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("selka-body-check-v8/dictionary-set-bodies-v1/schema8/");
    hash.update(selected);
    if (std.mem.eql(u8, selected, "shadow") or std.mem.eql(u8, selected, component_mode)) {
        const dir = try directory(a, runtime);
        defer a.free(dir);
        const artifact = try runtime.artifact(a, dir, component_name);
        defer a.free(artifact.path);
        hash.update(&artifact.digest);
    } else if (std.mem.eql(u8, selected, reference_mode)) hash.update("host-reference-v1") else return error.ComponentMode;
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}
/// Execute one verified immutable body check request with bounded binary capture.
// twin-drift-ok: Independent body framing retains the sealed frontend launch lifecycle.
pub fn execute(a: std.mem.Allocator, input: wire.Input, runtime: Runtime) Error!value.Decoded {
    if (runtime.timeout_ms <= 0) return error.ComponentMode;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const dir = try directory(scratch, runtime);
    const snapshot = try runtime.snapshot(scratch, dir, component_name);
    defer snapshot.deinit(scratch);
    var nonce: [16]u8 = undefined;
    std.Io.random(runtime.io, &nonce);
    const request = try wire.request(scratch, input, nonce[0..8].*);
    const root = runtime.environ.get("TMPDIR") orelse config.temporary_root;
    const name = try std.fmt.allocPrint(scratch, "mylang-body-checks-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
    const temporary = try std.fs.path.join(scratch, &.{ if (root.len == 0) config.temporary_root else root, name });
    std.Io.Dir.cwd().createDir(runtime.io, temporary, .fromMode(0o700)) catch return error.ComponentIo;
    defer discard(runtime.io, temporary);
    const sealed = runtime.seal(snapshot.contents) catch return error.ComponentIo;
    defer sealed.close(runtime.io);
    const binary = try std.fmt.allocPrint(scratch, "/proc/{d}/fd/{d}", .{ std.os.linux.getpid(), sealed.file.handle });
    const path = try std.fs.path.join(scratch, &.{ temporary, "request.bin" });
    std.Io.Dir.cwd().writeFile(runtime.io, .{ .sub_path = path, .data = request.bytes }) catch return error.ComponentIo;
    const timeout: std.Io.Timeout = .{ .duration = .{ .clock = .awake, .raw = .fromMilliseconds(runtime.timeout_ms) } };
    const result = launch.runBounded(scratch, runtime.io, .{
        .argv = &.{ binary, "--exchange", path },
        .environ_map = runtime.environ,
        .timeout = timeout.toDeadline(runtime.io),
        .stdout_limit = .limited(wire.reply_limit),
        .stderr_limit = .limited(65536),
    }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.Timeout => error.ComponentTimeout,
        error.StreamTooLong => error.ComponentProtocol,
        else => error.ComponentIo,
    };
    switch (result.term) {
        .exited => |status| {
            if (status != 0) return error.ComponentFailed;
        },
        else => return error.ComponentFailed,
    }
    if (result.stderr.len != 0) return error.ComponentProtocol;
    const current = try runtime.artifact(scratch, dir, component_name);
    if (!std.mem.eql(u8, &snapshot.verified.digest, &current.digest) or !std.mem.eql(u8, snapshot.verified.path, current.path)) return error.ComponentChanged;
    return wire.reply(a, result.stdout, request.identity, input);
}

fn discard(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, path) catch |err| {
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "mylang: body check request cleanup failed: {t}\n", .{err}) catch return;
        std.Io.File.stderr().writeStreamingAll(io, message) catch return;
    };
}
