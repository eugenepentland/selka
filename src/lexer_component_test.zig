//! Native verification for the lexer pilot wire and sealed process boundary.
const std = @import("std");
const t = std.testing;
const adapter = @import("lexer_component.zig");
const wire = @import("lexer_component_protocol.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");

fn replyBytes(a: std.mem.Allocator, request: wire.Request) ![]u8 {
    const bytes = try a.alloc(u8, 84);
    @memcpy(bytes[0..64], request.bytes[0..64]);
    std.mem.writeInt(u32, bytes[16..20], 1, .little);
    std.mem.writeInt(u32, bytes[20..24], 20, .little);
    std.mem.writeInt(u32, bytes[64..68], 0, .little);
    std.mem.writeInt(u32, bytes[68..72], 1, .little);
    std.mem.writeInt(u32, bytes[72..76], 0, .little);
    std.mem.writeInt(u32, bytes[76..80], 0, .little);
    std.mem.writeInt(u32, bytes[80..84], 0, .little);
    return bytes;
}
fn changed(a: std.mem.Allocator, bytes: []const u8, at: usize, value: u32) ![]u8 {
    const copy = try a.dupe(u8, bytes);
    std.mem.writeInt(u32, copy[at..][0..4], value, .little);
    return copy;
}
// spec: SELFHOST-LEXER-COMPONENT-1
test "lexer component validates envelope identity kinds spans and shadow mismatch" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "fixture", "");
    const request = try wire.request(a, "", @splat(7));
    const bytes = try replyBytes(a, request);
    const actual = try wire.reply(a, bytes, request.identity, src);
    try t.expectEqual(@as(usize, 1), actual.tokens.len);
    try adapter.compare(actual, actual.tokens, &.{}, src);
    try t.expectError(error.ComponentShadowMismatch, adapter.compare(actual, &.{}, &.{}, src));
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 8, 2), request.identity, src));
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 24, 8), request.identity, src));
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 72, 9999), request.identity, src));
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 80, 1), request.identity, src));
    try t.expectError(error.ComponentProtocol, wire.reply(a, bytes[0..83], request.identity, src));
}
fn fixture(a: std.mem.Allocator, dir: std.Io.Dir, script: []const u8) !void {
    const io = t.io;
    try dir.writeFile(io, .{ .sub_path = "lexer-pilot", .data = script });
    const file = try dir.openFile(io, "lexer-pilot", .{});
    defer file.close(io);
    try file.setPermissions(io, .fromMode(0o700));
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(script, &digest, .{});
    const manifest = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"lexer-pilot\",\"protocol\":1,\"schema\":1,\"artifact\":\"lexer-pilot\",\"sha256\":\"{s}\"}}", .{std.fmt.bytesToHex(digest, .lower)});
    defer a.free(manifest);
    try dir.writeFile(io, .{ .sub_path = "lexer-pilot.json", .data = manifest });
}
// spec-case: SELFHOST-LEXER-COMPONENT-1
test "lexer component native transport digest failures malformed output and wait deadline" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [4096]u8 = undefined;
    const directory = buffer[0..try temporary.dir.realPath(t.io, &buffer)];
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    const src = try source.Source.init(a, "fixture", "");
    var runtime: adapter.Runtime = .{ .io = t.io, .environ = &environ, .component_dir = directory, .timeout_ms = 1000 };
    try fixture(a, temporary.dir, "#!/bin/sh\nexit 7\n");
    try t.expectError(error.ComponentFailed, adapter.execute(a, src, runtime));
    try fixture(a, temporary.dir, "#!/bin/sh\nprintf invalid\n");
    try t.expectError(error.ComponentProtocol, adapter.execute(a, src, runtime));
    try fixture(a, temporary.dir, "#!/bin/sh\nexec 1>&- 2>&-\nexec /bin/sleep 2\n");
    runtime.timeout_ms = 20;
    try t.expectError(error.ComponentTimeout, adapter.execute(a, src, runtime));
    runtime.timeout_ms = 1000;
    try fixture(a, temporary.dir, "#!/bin/sh\nexec /usr/bin/head -c 4000000 /dev/zero\n");
    try t.expectError(error.ComponentProtocol, adapter.execute(a, src, runtime));
    try fixture(a, temporary.dir, "#!/bin/sh\nexec /usr/bin/head -c 70000 /dev/zero >&2\n");
    try t.expectError(error.ComponentProtocol, adapter.execute(a, src, runtime));
    try temporary.dir.writeFile(t.io, .{ .sub_path = "lexer-pilot", .data = "changed" });
    try t.expectError(error.ComponentDigest, adapter.execute(a, src, runtime));
    try temporary.dir.writeFile(t.io, .{ .sub_path = "lexer-pilot.json", .data = "{}" });
    try t.expectError(error.ComponentManifest, adapter.execute(a, src, runtime));
}
// spec-case: SELFHOST-LEXER-COMPONENT-1
test "lexer component reference needs no deployment and direct component mode fails closed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "fixture", "x");
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    const runtime: adapter.Runtime = .{ .io = t.io, .environ = &environ, .component_dir = "/missing" };
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try adapter.lex(a, src, &sink, runtime);
    try t.expectEqual(@as(usize, 2), tokens.len);
    try environ.put("MYLANG_LEXER_MODE", "invalid");
    try t.expectError(error.ComponentMode, adapter.lex(a, src, &sink, runtime));
}

const echo_script =
    \\#!/usr/bin/python3
    \\import sys,struct
    \\b=open(sys.argv[2],'rb').read()
    \\body=struct.pack('<5I',0,1,0,0,0) if len(b)==64 else struct.pack('<7I',1,0,4,1,1,0,7)
    \\sys.stdout.buffer.write(b[:16]+struct.pack('<II',1,len(body))+b[24:64]+body)
    \\
;
// spec-case: SELFHOST-LEXER-COMPONENT-1
test "lexer component shadow keeps migration fixes and binds deployment identity" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [4096]u8 = undefined;
    const directory = buffer[0..try temporary.dir.realPath(t.io, &buffer)];
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    const runtime: adapter.Runtime = .{ .io = t.io, .environ = &environ, .component_dir = directory };
    try fixture(a, temporary.dir, echo_script);
    const reference_id = try adapter.identity(a, runtime);
    try environ.put("MYLANG_LEXER_MODE", "shadow");
    const shadow_id = try adapter.identity(a, runtime);
    try t.expect(!std.mem.eql(u8, &reference_id, &shadow_id));
    var sink: diagnostic.Sink = .{ .allocator = a };
    const empty = try source.Source.init(a, "empty", "");
    const tokens = try adapter.lex(a, empty, &sink, runtime);
    try t.expectEqual(@as(usize, 1), tokens.len);
    const removed = try source.Source.init(a, "removed", "f64_abs");
    try t.expectError(error.SourceError, adapter.lex(a, removed, &sink, runtime));
    try t.expectEqualStrings("abs", sink.items.items[0].provenance.fix.?.edit.text);
    try t.expect(std.mem.indexOf(u8, sink.items.items[0].message, "use `abs`") != null);
}

fn errorBytes(a: std.mem.Allocator, request: wire.Request) ![]u8 {
    const bytes = try a.alloc(u8, 92);
    @memcpy(bytes[0..64], request.bytes[0..64]);
    std.mem.writeInt(u32, bytes[16..20], 1, .little);
    std.mem.writeInt(u32, bytes[20..24], 28, .little);
    std.mem.writeInt(u32, bytes[64..68], 1, .little);
    std.mem.writeInt(u32, bytes[68..72], 0, .little);
    std.mem.writeInt(u32, bytes[72..76], 4, .little);
    std.mem.writeInt(u32, bytes[76..80], 1, .little);
    std.mem.writeInt(u32, bytes[80..84], 1, .little);
    std.mem.writeInt(u32, bytes[84..88], 0, .little);
    std.mem.writeInt(u32, bytes[88..92], 7, .little);
    return bytes;
}
// spec-case: SELFHOST-LEXER-COMPONENT-1
test "lexer component lexical error codes physical locations and request limit fail closed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "fixture", "f64_abs");
    const request = try wire.request(a, src.bytes, @splat(9));
    const bytes = try errorBytes(a, request);
    const actual = try wire.reply(a, bytes, request.identity, src);
    try t.expectEqualStrings("E_REMOVED_SPELLING", actual.failure.code);
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 76, 2), request.identity, src));
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 84, 8), request.identity, src));
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 72, 99), request.identity, src));
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 32, 0), request.identity, src));
    const over = try a.alloc(u8, wire.source_limit + 1);
    @memset(over, ' ');
    try t.expectError(error.ComponentProtocol, wire.request(a, over, @splat(0)));
}
// spec-case: SELFHOST-FRONTEND-CACHE-1
test "lexer component mode returns validated tokens and enriches matching errors with native fixes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [4096]u8 = undefined;
    const directory = buffer[0..try temporary.dir.realPath(t.io, &buffer)];
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    try environ.put("MYLANG_LEXER_MODE", "component");
    const runtime: adapter.Runtime = .{ .io = t.io, .environ = &environ, .component_dir = directory };
    try fixture(a, temporary.dir, echo_script);
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try adapter.lex(a, try source.Source.init(a, "fixture", ""), &sink, runtime);
    try t.expectEqual(@as(usize, 1), tokens.len);
    try t.expectError(error.SourceError, adapter.lex(a, try source.Source.init(a, "fixture", "f64_abs"), &sink, runtime));
    try t.expect(sink.items.items[0].provenance.fix != null);
}
