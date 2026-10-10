//! Full parser request framing and independently owned syntax reply values.
const std = @import("std");
const source = @import("source.zig");
const lexer = @import("lexer.zig");
const values = @import("parser_value.zig");
/// Maximum full source bytes in a parser operation.
pub const source_limit = 1048576;
/// Maximum request token rows.
pub const token_limit = 100000;
/// Maximum complete request envelope and payload.
pub const request_limit = 32 * 1024 * 1024;
/// Maximum complete reply envelope and syntax value payload.
pub const reply_limit = 64 + values.value_wire_limit;
/// Full source context, independently parsed tokens and top-level grammar mode.
pub const Input = struct { src: source.Source, tokens: []const lexer.Token, module: bool = false };
/// Owned framed request and immutable correlation/snapshot identity.
pub const Request = struct { bytes: []u8, identity: [40]u8 };
/// Independently owned complete syntax or recovered parser diagnostics.
pub const Reply = union(enum) {
    syntax: values.Decoded,
    failure: values.DecodedErrors,
    /// Release decoded ownership after comparison or explicit value adoption.
    pub fn deinit(self: *Reply) void {
        switch (self.*) {
            .syntax => |*value| value.deinit(),
            .failure => |*value| value.deinit(),
        }
        self.* = undefined;
    }
};
fn put(bytes: []u8, at: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[at..][0..4], value, .little);
}
fn get(bytes: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, bytes[at..][0..4], .little);
}
fn tokenBytes(tokens: []const lexer.Token, source_size: usize) error{ComponentProtocol}!usize {
    if (tokens.len == 0 or tokens.len > token_limit) return error.ComponentProtocol;
    var size: usize = 0;
    var previous: usize = 0;
    for (tokens, 0..) |token, index| {
        if (token.span.start < previous or token.span.start > token.span.end or token.span.end > source_size) return error.ComponentProtocol;
        if ((token.tag == .eof or token.tag == .dedent) and token.span.start != token.span.end) return error.ComponentProtocol;
        if (token.tag == .eof and index + 1 != tokens.len) return error.ComponentProtocol;
        if (token.tag != .eof and token.tag != .dedent and token.span.start == token.span.end) return error.ComponentProtocol;
        previous = token.span.end;
        size += 12 + @tagName(token.tag).len;
    }
    const last = tokens[tokens.len - 1];
    if (last.tag != .eof or last.span.start != source_size) return error.ComponentProtocol;
    return size;
}
/// Bind complete source/path/token/grammar/trust values to a framed request digest.
pub fn request(a: std.mem.Allocator, input: Input, nonce: [8]u8) values.Error!Request {
    if (input.src.bytes.len > source_limit or input.src.path.len > 16384) return error.ComponentProtocol;
    const size = 28 + input.src.path.len + input.src.bytes.len + try tokenBytes(input.tokens, input.src.bytes.len);
    if (size + 64 > request_limit) return error.ComponentProtocol;
    const bytes = try a.alloc(u8, 64 + size);
    @memcpy(bytes[0..8], "SLKPRS01");
    put(bytes, 8, 1);
    put(bytes, 12, 1);
    put(bytes, 16, 0);
    put(bytes, 20, @intCast(size));
    @memcpy(bytes[24..32], &nonce);
    @memcpy(bytes[64..72], "SLKPAR01");
    put(bytes, 72, @intCast(input.src.bytes.len));
    put(bytes, 76, @intCast(input.tokens.len));
    put(bytes, 80, @intFromBool(input.module));
    put(bytes, 84, @intFromBool(input.src.trusted_intrinsics));
    put(bytes, 88, @intCast(input.src.path.len));
    var at: usize = 92;
    @memcpy(bytes[at..][0..input.src.path.len], input.src.path);
    at += input.src.path.len;
    @memcpy(bytes[at..][0..input.src.bytes.len], input.src.bytes);
    at += input.src.bytes.len;
    for (input.tokens) |token| {
        const name = @tagName(token.tag);
        put(bytes, at, @intCast(name.len));
        at += 4;
        @memcpy(bytes[at..][0..name.len], name);
        at += name.len;
        put(bytes, at, @intCast(token.span.start));
        put(bytes, at + 4, @intCast(token.span.end));
        at += 8;
    }
    std.debug.assert(at == bytes.len);
    std.crypto.hash.sha2.Sha256.hash(bytes[64..], bytes[32..64], .{});
    return .{ .bytes = bytes, .identity = bytes[24..64].* };
}
/// Require exact framing/identity before validating the complete returned AST or errors.
pub fn reply(a: std.mem.Allocator, bytes: []const u8, identity: [40]u8, source_size: usize) values.Error!Reply {
    if (bytes.len < 80 or bytes.len > reply_limit) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[0..8], "SLKPRS01") or get(bytes, 8) != 1 or get(bytes, 12) != 1) return error.ComponentProtocol;
    if (get(bytes, 16) != 1 or get(bytes, 20) != bytes.len - 64) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[24..64], &identity)) return error.ComponentProtocol;
    if (std.mem.startsWith(u8, bytes[64..], "SLKERR01")) return .{ .failure = try values.decodeErrors(a, bytes[64..], source_size) };
    return .{ .syntax = try values.decode(a, bytes[64..], source_size) };
}
