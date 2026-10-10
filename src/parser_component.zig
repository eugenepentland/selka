//! Verified parser comparison boundary. Complete native syntax and diagnostics remain the oracle.
const std = @import("std");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const values = @import("parser_value.zig");
const diagnostic = @import("diagnostic.zig");
const launch = @import("component_launch.zig");
const wire = @import("parser_component_protocol.zig");
const reference_mode = config.reference_mode;
const component_name = "parser-pilot";
const config = @import("config/component_runtime.zig");
/// Bounded component failures are host errors, never parser diagnostics.
pub const Error = launch.Error || error{ ComponentProtocol, ComponentTimeout, ComponentFailed, ComponentIo, ComponentShadowMismatch, ComponentMode, ComponentChanged, ComponentProfile };
/// Explicit host capabilities and full child lifecycle deadline.
pub const Runtime = struct { io: std.Io, environ: *const std.process.Environ.Map, component_dir: ?[]const u8 = null, timeout_ms: i64 = 30000 };
/// Parse through an explicit comparison boundary, preserving the native AST or errors.
pub fn parse(p: *parser.Parser, module: bool, runtime: Runtime) (diagnostic.Error || Error)!ast.Program {
    const mode = runtime.environ.get("MYLANG_PARSER_MODE") orelse reference_mode;
    if (!std.mem.eql(u8, mode, reference_mode) and !std.mem.eql(u8, mode, "shadow")) return error.ComponentMode;
    if (std.mem.eql(u8, mode, reference_mode)) return if (module) p.parseModule() else p.parse();
    if (p.cursor.pos != 0 or p.cursor.dialect != .target or p.module_syntax) return error.ComponentProfile;
    if (p.cursor.depth != 0 or p.cursor.delimiters != 0 or p.cursor.recovered) return error.ComponentProfile;
    const input: wire.Input = .{ .src = p.src, .tokens = p.tokens, .module = module };
    const before = p.sink.items.items.len;
    const reference = if (module) p.parseModule() else p.parse();
    const program = reference catch |err| blk: {
        if (err != error.SourceError) return err;
        break :blk null;
    };
    if (program != null and p.sink.items.items.len != before) return error.ComponentProfile;
    var actual = try execute(p.storage, input, runtime);
    defer actual.deinit();
    try compare(p.storage, actual, program, p.sink.items.items[before..]);
    return program orelse error.SourceError;
}
/// Compare every canonical AST or diagnostic field, including ordered recovery and fixes.
pub fn compare(a: std.mem.Allocator, actual: wire.Reply, expected: ?ast.Program, problems: []const diagnostic.Diagnostic) Error!void {
    const received = switch (actual) {
        .syntax => |syntax| try values.encode(a, syntax.program),
        .failure => |failure| try values.encodeReport(a, failure.report),
    };
    defer a.free(received);
    const reference = if (expected) |program| try values.encode(a, program) else try values.encodeErrors(a, problems);
    defer a.free(reference);
    if (!std.mem.eql(u8, received, reference)) return error.ComponentShadowMismatch;
}
fn directory(a: std.mem.Allocator, runtime: Runtime) Error![]u8 {
    if (runtime.component_dir orelse runtime.environ.get("MYLANG_COMPONENT_DIR")) |dir| return a.dupe(u8, dir);
    const executable = std.process.executableDirPathAlloc(runtime.io, a) catch return error.ComponentIo;
    defer a.free(executable);
    return std.fs.path.join(a, &.{ executable, "..", "libexec", "mylang", "components" });
}
/// Producer identity for future cache adoption: schema, mode and verified artifact digest.
// twin-drift-ok: Separate lexer/parser protocol identities deliberately share verified artifact hashing.
pub fn identity(a: std.mem.Allocator, runtime: Runtime) Error![32]u8 {
    const mode = runtime.environ.get("MYLANG_PARSER_MODE") orelse reference_mode;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("selka-parser-pilot-v1/full-source/");
    hash.update(mode);
    if (std.mem.eql(u8, mode, "shadow")) {
        const dir = try directory(a, runtime);
        defer a.free(dir);
        const artifact = try launch.artifact(a, runtime.io, dir, component_name);
        defer a.free(artifact.path);
        hash.update(&artifact.digest);
    } else if (std.mem.eql(u8, mode, reference_mode)) hash.update("host-reference-v1") else return error.ComponentMode;
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}
/// Execute one verified immutable full-source request with bounded binary capture.
// twin-drift-ok: Independently typed parser framing uses the same bounded sealed launch policy as lexer framing.
pub fn execute(a: std.mem.Allocator, input: wire.Input, runtime: Runtime) Error!wire.Reply {
    if (runtime.timeout_ms <= 0) return error.ComponentMode;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const dir = try directory(scratch, runtime);
    const snapshot = try launch.artifactSnapshot(scratch, runtime.io, dir, component_name);
    var nonce: [16]u8 = undefined;
    std.Io.random(runtime.io, &nonce);
    const request = try wire.request(scratch, input, nonce[0..8].*);
    const root = runtime.environ.get("TMPDIR") orelse config.temporary_root;
    const name = try std.fmt.allocPrint(scratch, "mylang-parser-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
    const temporary = try std.fs.path.join(scratch, &.{ if (root.len == 0) config.temporary_root else root, name });
    std.Io.Dir.cwd().createDir(runtime.io, temporary, .fromMode(0o700)) catch return error.ComponentIo;
    defer discard(runtime.io, temporary);
    const sealed = launch.sealedExecutable(runtime.io, snapshot.contents) catch return error.ComponentIo;
    defer sealed.close(runtime.io);
    const binary = try std.fmt.allocPrint(scratch, "/proc/{d}/fd/{d}", .{ std.os.linux.getpid(), sealed.handle });
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
    const current = try launch.artifact(scratch, runtime.io, dir, component_name);
    if (!std.mem.eql(u8, &snapshot.verified.digest, &current.digest) or !std.mem.eql(u8, snapshot.verified.path, current.path)) return error.ComponentChanged;
    return wire.reply(a, result.stdout, request.identity, input.src.bytes.len);
}

fn discard(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, path) catch |err| {
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "mylang: parser request cleanup failed: {t}\n", .{err}) catch return;
        std.Io.File.stderr().writeStreamingAll(io, message) catch return;
    };
}
