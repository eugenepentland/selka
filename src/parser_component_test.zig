//! Complete syntax value comparison and verified parser process boundary tests.
const std = @import("std");
const t = std.testing;
const adapter = @import("parser_component.zig");
const wire = @import("parser_component_protocol.zig");
const values = @import("parser_value.zig");
const parser = @import("parser.zig");
const lexer = @import("lexer.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");

fn syntax(a: std.mem.Allocator, src: source.Source, tokens: []const lexer.Token) !@import("ast.zig").Program {
    var sink: diagnostic.Sink = .{ .allocator = a };
    var p: parser.Parser = .{ .storage = a, .src = src, .tokens = tokens, .sink = &sink };
    return p.parse();
}
fn replyBytes(a: std.mem.Allocator, request: wire.Request, payload: []const u8) ![]u8 {
    const bytes = try a.alloc(u8, 64 + payload.len);
    @memcpy(bytes[0..64], request.bytes[0..64]);
    std.mem.writeInt(u32, bytes[16..20], 1, .little);
    std.mem.writeInt(u32, bytes[20..24], @intCast(payload.len), .little);
    @memcpy(bytes[64..], payload);
    return bytes;
}
fn changed(a: std.mem.Allocator, bytes: []const u8, at: usize, value: u32) ![]u8 {
    const copy = try a.dupe(u8, bytes);
    std.mem.writeInt(u32, copy[at..][0..4], value, .little);
    return copy;
}

// spec-case: SELFHOST-PARSER-COMPONENT-1
test "parser component trust matches exact embedded standard source and explicit authority" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sink: diagnostic.Sink = .{ .allocator = a };
    const text = @import("standard_library.zig").source("math.my").?;
    var p: parser.Parser = .{ .storage = a, .src = try source.Source.init(a, "@stdlib/math.my", text), .tokens = &.{}, .sink = &sink };
    try t.expect(p.trustedStdlib());
    p.src = try source.Source.init(a, "@stdlib/math.my", "func impostor():\n    pass\n");
    try t.expect(!p.trustedStdlib());
    p.src = try source.Source.init(a, "math.my", text);
    try t.expect(!p.trustedStdlib());
    p.src.trusted_intrinsics = true;
    try t.expect(p.trustedStdlib());
}
// spec: SELFHOST-PARSER-COMPONENT-1
test "parser component binds full request and validates canonical syntax frame" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var src = try source.Source.init(a, "fixture", "");
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    const request = try wire.request(a, .{ .src = src, .tokens = tokens }, @splat(7));
    src.trusted_intrinsics = true;
    const trusted = try wire.request(a, .{ .src = src, .tokens = tokens, .module = true }, @splat(7));
    try t.expect(!std.mem.eql(u8, request.bytes[32..64], trusted.bytes[32..64]));
    try t.expectEqualStrings("SLKPAR01", request.bytes[64..72]);
    const program = try syntax(a, src, tokens);
    const payload = try values.encode(a, program);
    const bytes = try replyBytes(a, request, payload);
    var actual = try wire.reply(a, bytes, request.identity, src.bytes.len);
    defer actual.deinit();
    try adapter.compare(a, actual, program, &.{});
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 8, 2), request.identity, src.bytes.len));
    try t.expectError(error.ComponentProtocol, wire.reply(a, try changed(a, bytes, 24, 8), request.identity, src.bytes.len));
    try t.expectError(error.ComponentProtocol, wire.reply(a, bytes[0 .. bytes.len - 1], request.identity, src.bytes.len));
}
// spec-case: SELFHOST-PARSER-COMPONENT-1
test "parser component compares all recovered diagnostics prose notes and fixes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "fixture", "");
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    const request = try wire.request(a, .{ .src = src, .tokens = tokens }, @splat(1));
    const problems = [_]diagnostic.Diagnostic{.{ .code = "E_SYNTAX", .span = .{ .start = 0, .end = 0 }, .message = "expected syntax" }};
    const payload = try values.encodeErrors(a, &problems);
    var actual = try wire.reply(a, try replyBytes(a, request, payload), request.identity, src.bytes.len);
    defer actual.deinit();
    try adapter.compare(a, actual, null, &problems);
    const different = [_]diagnostic.Diagnostic{.{ .code = "E_SYNTAX", .span = .{ .start = 0, .end = 0 }, .message = "different prose" }};
    try t.expectError(error.ComponentShadowMismatch, adapter.compare(a, actual, null, &different));
    try t.expectError(error.ComponentShadowMismatch, adapter.compare(a, actual, try syntax(a, src, tokens), &.{}));
}
fn fixture(a: std.mem.Allocator, dir: std.Io.Dir, script: []const u8) !void {
    const io = t.io;
    try dir.writeFile(io, .{ .sub_path = "parser-pilot", .data = script });
    const file = try dir.openFile(io, "parser-pilot", .{});
    defer file.close(io);
    try file.setPermissions(io, .fromMode(0o700));
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(script, &digest, .{});
    const manifest = try std.fmt.allocPrint(a, "{{\"format\":1,\"component\":\"parser-pilot\",\"protocol\":1,\"schema\":1,\"artifact\":\"parser-pilot\",\"sha256\":\"{s}\"}}", .{std.fmt.bytesToHex(digest, .lower)});
    defer a.free(manifest);
    try dir.writeFile(io, .{ .sub_path = "parser-pilot.json", .data = manifest });
}
const echo_script =
    \\#!/usr/bin/python3
    \\import os,sys,struct
    \\b=open(sys.argv[2],'rb').read()
    \\body=open(os.environ['PARSER_TEST_PAYLOAD'],'rb').read()
    \\sys.stdout.buffer.write(b[:16]+struct.pack('<II',1,len(body))+b[24:64]+body)
    \\
;
// spec-case: SELFHOST-PARSER-COMPONENT-1
test "parser component sealed process shadow succeeds and fails closed on deployment errors" {
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
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    const program = try syntax(a, src, tokens);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "payload", .data = try values.encode(a, program) });
    const payload_path = try std.fs.path.join(a, &.{ directory, "payload" });
    try environ.put("PARSER_TEST_PAYLOAD", payload_path);
    try fixture(a, temporary.dir, echo_script);
    const runtime: adapter.Runtime = .{ .io = t.io, .environ = &environ, .component_dir = directory };
    const reference_id = try adapter.identity(a, runtime);
    try environ.put("MYLANG_PARSER_MODE", "shadow");
    const shadow_id = try adapter.identity(a, runtime);
    try t.expect(!std.mem.eql(u8, &reference_id, &shadow_id));
    var p: parser.Parser = .{ .storage = a, .src = src, .tokens = tokens, .sink = &sink };
    const parsed = try adapter.parse(&p, false, runtime);
    try t.expectEqual(@as(usize, 0), parsed.functions.len);
    try temporary.dir.writeFile(t.io, .{ .sub_path = "parser-pilot", .data = "changed" });
    try t.expectError(error.ComponentDigest, adapter.execute(a, .{ .src = src, .tokens = tokens }, runtime));
    try temporary.dir.writeFile(t.io, .{ .sub_path = "parser-pilot.json", .data = "{}" });
    try t.expectError(error.ComponentManifest, adapter.execute(a, .{ .src = src, .tokens = tokens }, runtime));
}
// spec-case: SELFHOST-PARSER-COMPONENT-1
test "parser component child failure malformed reply and wait-after-EOF deadline are bounded" {
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
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    const input: wire.Input = .{ .src = src, .tokens = tokens };
    var runtime: adapter.Runtime = .{ .io = t.io, .environ = &environ, .component_dir = directory, .timeout_ms = 1000 };
    try fixture(a, temporary.dir, "#!/bin/sh\nexit 7\n");
    try t.expectError(error.ComponentFailed, adapter.execute(a, input, runtime));
    try fixture(a, temporary.dir, "#!/bin/sh\nprintf invalid\n");
    try t.expectError(error.ComponentProtocol, adapter.execute(a, input, runtime));
    try fixture(a, temporary.dir, "#!/bin/sh\nexec 1>&- 2>&-\nexec /bin/sleep 2\n");
    runtime.timeout_ms = 20;
    try t.expectError(error.ComponentTimeout, adapter.execute(a, input, runtime));
}
// spec-case: SELFHOST-PARSER-COMPONENT-1
test "parser component reference requires no deployment and unqualified modes or cursor fail closed" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environ: std.process.Environ.Map = .init(a);
    defer environ.deinit();
    const src = try source.Source.init(a, "fixture", "");
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    const runtime: adapter.Runtime = .{ .io = t.io, .environ = &environ, .component_dir = "/missing" };
    var p: parser.Parser = .{ .storage = a, .src = src, .tokens = tokens, .sink = &sink };
    const parsed = try adapter.parse(&p, false, runtime);
    try t.expectEqual(@as(usize, 0), parsed.functions.len);
    try environ.put("MYLANG_PARSER_MODE", "invalid");
    try t.expectError(error.ComponentMode, adapter.parse(&p, false, runtime));
    try environ.put("MYLANG_PARSER_MODE", "shadow");
    p.cursor.dialect = .migration;
    try t.expectError(error.ComponentProfile, adapter.parse(&p, false, runtime));
}
// spec-case: SELFHOST-FRONTEND-CACHE-1
test "parser component adoption owns syntax and complete diagnostic repair bytes after reply release" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const src = try source.Source.init(a, "fixture", "func main() -> int:\n    return 42\n");
    var sink: diagnostic.Sink = .{ .allocator = a };
    const tokens = try lexer.lex(a, src.bytes, &sink);
    const expected = try syntax(a, src, tokens);
    const encoded = try values.encode(a, expected);
    var p: parser.Parser = .{ .storage = a, .src = src, .tokens = tokens, .sink = &sink };
    var decoded = try values.decode(t.allocator, encoded, src.bytes.len);
    const adopted = try adapter.adopt(&p, .{ .syntax = decoded });
    decoded.deinit();
    try t.expectEqualStrings(encoded, try values.encode(a, adopted));
    const repair: diagnostic.Fix = .{
        .edit = .{ .span = .{ .start = 0, .end = 1 }, .text = "first" },
        .more = &.{.{ .span = .{ .start = 1, .end = 2 }, .text = "second" }},
    };
    const problem: diagnostic.Diagnostic = .{
        .code = "E_PARSE",
        .span = .{ .start = 0, .end = 1 },
        .message = "repair",
        .related = .{ .span = .{ .start = 1, .end = 2 }, .message = "related" },
        .provenance = .{ .fix = repair },
    };
    const errors = try values.encodeErrors(a, &.{problem});
    var failure = try values.decodeErrors(t.allocator, errors, src.bytes.len);
    try t.expectError(error.SourceError, adapter.adopt(&p, .{ .failure = failure }));
    failure.deinit();
    try t.expectEqualStrings(errors, try values.encodeErrors(a, sink.items.items));
}
