//! Correlated declaration-index framing and independently owned reply decoding.
const std = @import("std");
const value = @import("declaration_value.zig");
const wire = @import("declaration_wire_io.zig");
const validate = @import("declaration_validate.zig");
const content_hash = @import("component_digest.zig");
/// Pure input schema shared with the Selka declaration producer.
pub const Input = value.Input;
/// Maximum complete request or reply frame.
pub const reply_limit = wire.wire_limit;
/// Wire allocations and validation fail before any result is adopted.
pub const Error = wire.Error;
/// Owned request and the correlation plus payload digest every reply must echo.
pub const Request = struct { bytes: []u8, identity: [40]u8 };
/// Encode source provenance, AST facts and direct-dependency symbols as one request.
pub fn request(a: std.mem.Allocator, input: Input, nonce: [8]u8) Error!Request {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    try validate.input(scratch.allocator(), input);
    var writer: wire.Writer = .{ .allocator = a };
    defer writer.deinit();
    const header: [64]u8 = @splat(0);
    try writer.raw(&header);
    try writer.raw("SLKDCL01");
    try writer.integer(input.context.module);
    try writer.boolean(input.context.is_imported);
    try writer.blob(input.context.name);
    try writer.blob(input.context.path);
    try writer.boolean(input.context.trusted_intrinsics);
    try writer.blob(input.context.source);
    try writer.integer(input.declarations.len);
    try writer.integer(input.imports.len);
    try writer.integer(input.exports.len);
    try writer.integer(input.public.len);
    try writer.integer(input.dependencies.len);
    for (input.declarations) |item| try declaration(&writer, item);
    for (input.imports) |item| try imported(&writer, item);
    for (input.exports) |item| try exported(&writer, item);
    for (input.public) |span| try writer.span(span);
    for (input.dependencies) |item| try dependency(&writer, item);
    const bytes = try writer.output.toOwnedSlice(a);
    @memcpy(bytes[0..8], "SLKDIX01");
    put(bytes, 8, 1);
    put(bytes, 12, 1);
    put(bytes, 16, 0);
    put(bytes, 20, @intCast(bytes.len - 64));
    @memcpy(bytes[24..32], &nonce);
    const digest = content_hash.hash(bytes[64..]);
    @memcpy(bytes[32..64], &digest);
    return .{ .bytes = bytes, .identity = bytes[24..64].* };
}
fn declaration(writer: *wire.Writer, item: value.Declaration) Error!void {
    try writer.integer(@backingInt(item.category));
    try writer.span(item.span);
    try writer.boolean(item.owner != null);
    try writer.span(item.owner orelse .{ .start = 0, .end = 0 });
    try writer.boolean(item.restricted);
}
fn imported(writer: *wire.Writer, item: value.Import) Error!void {
    try writer.blob(item.name);
    try writer.blob(item.alias);
    try writer.span(item.span);
    try writer.integer(item.target);
}
fn exported(writer: *wire.Writer, item: value.Export) Error!void {
    try writer.blob(item.name);
    try writer.boolean(item.alias != null);
    if (item.alias) |alias| try writer.blob(alias);
    try writer.span(item.span);
}
fn dependency(writer: *wire.Writer, item: value.Dependency) Error!void {
    try writer.integer(item.module);
    try writer.blob(item.name);
    try writer.integer(item.source_len);
    try writer.integer(item.symbols.len);
    for (item.symbols) |symbol| try writer.symbol(symbol);
}
fn put(bytes: []u8, at: usize, number: u32) void {
    std.mem.writeInt(u32, bytes[at..][0..4], number, .little);
}
fn get(bytes: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, bytes[at..][0..4], .little);
}
/// Reject stale, malformed or incomplete replies before validating symbol provenance.
pub fn reply(a: std.mem.Allocator, bytes: []const u8, identity: [40]u8, input: Input) Error!value.Decoded {
    if (bytes.len < 76 or bytes.len > reply_limit) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[0..8], "SLKDIX01") or get(bytes, 8) != 1 or get(bytes, 12) != 1) return error.ComponentProtocol;
    if (get(bytes, 16) != 1 or get(bytes, 20) != bytes.len - 64) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[24..64], &identity)) return error.ComponentProtocol;
    var arena = std.heap.ArenaAllocator.init(a);
    errdefer arena.deinit();
    var reader: wire.Reader = .{ .arena = &arena, .bytes = bytes[64..] };
    if (!std.mem.eql(u8, try reader.take(8), "SLKDCR01")) return error.ComponentProtocol;
    const outcome: value.Outcome = switch (try reader.integer()) {
        0 => .{ .success = try success(&reader) },
        1 => .{ .failure = try failure(&reader) },
        else => return error.ComponentProtocol,
    };
    if (reader.at != reader.bytes.len) return error.ComponentProtocol;
    try validate.input(arena.allocator(), input);
    try validate.outcome(arena.allocator(), input, outcome);
    return .{ .arena = arena, .outcome = outcome };
}
fn success(reader: *wire.Reader) Error!value.Output {
    const count = try reader.integer();
    const used_count = try reader.integer();
    if (count > 65536 or used_count > 4096) return error.ComponentProtocol;
    // Every symbol needs at least 32 fixed bytes; count admission precedes allocation.
    if (count > (reader.bytes.len - reader.at) / 32) return error.ComponentProtocol;
    const symbols = try reader.arena.allocator().alloc(value.Symbol, count);
    for (symbols) |*symbol| symbol.* = try reader.symbol();
    const used = try reader.arena.allocator().alloc(bool, used_count);
    for (used) |*item| item.* = try reader.boolean();
    return .{ .symbols = symbols, .import_used = used };
}
fn failure(reader: *wire.Reader) Error!value.Problem {
    const code = try reader.blob();
    const message = try reader.blob();
    const site = try reader.site();
    const related: ?value.Site = if (try reader.boolean()) try reader.site() else null;
    return .{ .code = code, .message = message, .site = site, .related = related };
}
