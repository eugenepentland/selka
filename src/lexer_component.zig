//! Verified lexer comparison boundary. Production diagnostics remain the Zig oracle.
const std = @import("std");
const lexer = @import("lexer.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const launch = @import("component_launch.zig");
const wire = @import("lexer_component_protocol.zig");
const reference_mode = config.reference_mode;
const component_mode = config.component_mode;
const component_name = "lexer-pilot";
const config = @import("config/component_runtime.zig");
/// Bounded component failures are host errors, never lexical diagnostics.
pub const Error = launch.Error || error{ ComponentProtocol, ComponentTimeout, ComponentFailed, ComponentIo, ComponentShadowMismatch, ComponentMode, ComponentChanged };
/// Explicit host capabilities and full child lifecycle deadline.
pub const Runtime = config.Runtime;
/// Select native, shadow, or validated component tokens; v1 lexical failures retain native repairs.
pub fn lex(a: std.mem.Allocator, src: source.Source, sink: *diagnostic.Sink, runtime: Runtime) (diagnostic.Error || Error)![]lexer.Token {
    const mode = runtime.environ.get("MYLANG_LEXER_MODE") orelse reference_mode;
    const known = std.mem.eql(u8, mode, reference_mode) or std.mem.eql(u8, mode, "shadow") or std.mem.eql(u8, mode, component_mode);
    if (!known) return error.ComponentMode;
    if (std.mem.eql(u8, mode, reference_mode)) return lexer.lex(a, src.bytes, sink);
    if (std.mem.eql(u8, mode, component_mode)) {
        const actual = try execute(a, src, runtime);
        switch (actual) {
            .tokens => |items| return items,
            .failure => {
                // The v1 lexer DTO carries code/spans only. Native failure enrichment
                // preserves established prose and structured repairs after validation.
                const before = sink.items.items.len;
                const native = lexer.lex(a, src.bytes, sink) catch |err| {
                    if (err != error.SourceError) return err;
                    try compare(actual, null, sink.items.items[before..], src);
                    return error.SourceError;
                };
                a.free(native);
                return error.ComponentShadowMismatch;
            },
        }
    }
    const before = sink.items.items.len;
    const reference = lexer.lex(a, src.bytes, sink);
    const tokens = reference catch |err| blk: {
        if (err != error.SourceError) return err;
        break :blk null;
    };
    errdefer if (tokens) |items| a.free(items);
    const actual = try execute(a, src, runtime);
    defer switch (actual) {
        .tokens => |items| a.free(items),
        .failure => {},
    };
    try compare(actual, tokens, sink.items.items[before..], src);
    return tokens orelse error.SourceError;
}
/// Compare token values or the first lexical diagnostic; messages and fixes stay native.
pub fn compare(actual: wire.Outcome, expected: ?[]const lexer.Token, problems: []const diagnostic.Diagnostic, src: source.Source) Error!void {
    switch (actual) {
        .tokens => |tokens| {
            const reference = expected orelse return error.ComponentShadowMismatch;
            if (tokens.len != reference.len) return error.ComponentShadowMismatch;
            for (tokens, reference) |left, right| if (left.tag != right.tag or left.span.start != right.span.start or left.span.end != right.span.end) return error.ComponentShadowMismatch;
        },
        .failure => |failure| {
            if (expected != null or problems.len == 0) return error.ComponentShadowMismatch;
            const item = problems[0];
            const loc = src.physicalLocation(item.span.start);
            if (!std.mem.eql(u8, failure.code, item.code) or failure.span.start != item.span.start or failure.span.end != item.span.end) return error.ComponentShadowMismatch;
            if (failure.line != loc.line or failure.column != loc.column) return error.ComponentShadowMismatch;
        },
    }
}
fn directory(a: std.mem.Allocator, runtime: Runtime) Error![]u8 {
    if (runtime.component_dir orelse runtime.environ.get("MYLANG_COMPONENT_DIR")) |dir| return a.dupe(u8, dir);
    const executable = std.process.executableDirPathAlloc(runtime.io, a) catch return error.ComponentIo;
    defer a.free(executable);
    return std.fs.path.join(a, &.{ executable, "..", "libexec", "mylang", "components" });
}
/// Producer identity for future cache adoption: schema, mode and verified artifact digest.
pub fn identity(a: std.mem.Allocator, runtime: Runtime) Error![32]u8 {
    const mode = runtime.environ.get("MYLANG_LEXER_MODE") orelse reference_mode;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("selka-lexer-pilot-v1/full-source/");
    hash.update(mode);
    if (std.mem.eql(u8, mode, "shadow") or std.mem.eql(u8, mode, component_mode)) {
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
pub fn execute(a: std.mem.Allocator, src: source.Source, runtime: Runtime) Error!wire.Outcome {
    if (runtime.timeout_ms <= 0) return error.ComponentMode;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const dir = try directory(scratch, runtime);
    const snapshot = try launch.artifactSnapshot(scratch, runtime.io, dir, component_name);
    var nonce: [16]u8 = undefined;
    std.Io.random(runtime.io, &nonce);
    const request = try wire.request(scratch, src.bytes, nonce[0..8].*);
    const root = runtime.environ.get("TMPDIR") orelse config.temporary_root;
    const name = try std.fmt.allocPrint(scratch, "mylang-lexer-{s}", .{std.fmt.bytesToHex(nonce, .lower)});
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
    return wire.reply(a, result.stdout, request.identity, src);
}

fn discard(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, path) catch |err| {
        var buffer: [256]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "mylang: lexer request cleanup failed: {t}\n", .{err}) catch return;
        std.Io.File.stderr().writeStreamingAll(io, message) catch return;
    };
}
