//! Bounded correlated framing for one whole-project type/interface batch.
const std = @import("std");
const value = @import("type_interface_value.zig");
const declaration = @import("declaration_value.zig");
const wire = @import("type_interface_wire_io.zig");
const validate = @import("type_interface_validate.zig");
const digest = @import("component_digest.zig");
const Span = @import("source.zig").Span;
/// Project-wide raw syntax request.
pub const Input = value.Input;
/// Complete framed request/reply allocation limit.
pub const reply_limit = wire.wire_limit;
/// Allocation and malformed component values remain host failures.
pub const Error = wire.Error;
/// Owned encoded request with its required nonce and content-digest echo.
pub const Request = struct { bytes: []u8, identity: [40]u8 };
/// Validate raw facts, then encode without resolving names or types on the host.
pub fn request(a: std.mem.Allocator, input: Input, nonce: [8]u8) Error!Request {
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    try validate.input(arena.allocator(), input);
    var writer: wire.Writer = .{ .allocator = a };
    defer writer.deinit();
    const header: [64]u8 = @splat(0);
    try writer.raw(&header);
    try writer.raw("SLKTYI01");
    try integers(&writer, input.order);
    try writer.integer(input.modules.len);
    for (input.modules) |module| try moduleBytes(&writer, module);
    const bytes = try writer.output.toOwnedSlice(a);
    @memcpy(bytes[0..8], "SLKTIF01");
    put(bytes, 8, 1);
    put(bytes, 12, 1);
    put(bytes, 16, 0);
    put(bytes, 20, @intCast(bytes.len - 64));
    @memcpy(bytes[24..32], &nonce);
    const hash = digest.hash(bytes[64..]);
    @memcpy(bytes[32..64], &hash);
    return .{ .bytes = bytes, .identity = bytes[24..64].* };
}
fn integers(writer: *wire.Writer, items: []const usize) Error!void {
    try writer.integer(items.len);
    for (items) |item| try writer.integer(item);
}
fn spans(writer: *wire.Writer, items: []const Span) Error!void {
    try writer.integer(items.len);
    for (items) |item| try writer.span(item);
}
fn optionalSpan(writer: *wire.Writer, at: ?Span) Error!void {
    try writer.boolean(at != null);
    if (at) |location| try writer.span(location);
}
fn moduleBytes(writer: *wire.Writer, module: value.Module) Error!void {
    const context = module.context;
    try writer.integer(context.module);
    try writer.blob(context.name);
    try writer.blob(context.path);
    try writer.boolean(context.trusted_intrinsics);
    try writer.boolean(context.is_imported);
    try writer.blob(context.source);
    try writer.integer(module.imports.len);
    for (module.imports) |item| {
        try writer.blob(item.name);
        try writer.blob(item.alias);
        try writer.span(item.span);
        try writer.integer(item.target);
    }
    try writer.integer(module.symbols.len);
    for (module.symbols) |symbol| try writer.symbol(symbol);
    try writer.integer(module.import_used.len);
    for (module.import_used) |used| try writer.boolean(used);
    try declarations(writer, module.syntax.declarations);
    try types(writer, module.syntax.types);
}
fn fields(writer: *wire.Writer, items: []const value.Field) Error!void {
    try writer.integer(items.len);
    for (items) |item| {
        try writer.span(item.name);
        try writer.span(item.ty);
    }
}
fn generics(writer: *wire.Writer, items: []const value.Generic) Error!void {
    try writer.integer(items.len);
    for (items) |item| try generic(writer, item);
}
fn generic(writer: *wire.Writer, item: value.Generic) Error!void {
    try writer.span(item.name);
    try writer.boolean(item.default_copy);
    try writer.boolean(item.constant_length);
    try spans(writer, item.requirements);
    try fields(writer, item.fields);
    try writer.integer(item.operations.len);
    for (item.operations) |operation| {
        try writer.span(operation.name);
        try fields(writer, operation.parameters);
        try writer.span(operation.return_type);
    }
    try writer.integer(item.named.len);
    for (item.named) |reference| {
        try optionalSpan(writer, reference.alias);
        try writer.span(reference.name);
    }
}
fn declarations(writer: *wire.Writer, catalog: value.Declarations) Error!void {
    try writer.integer(catalog.records.len);
    for (catalog.records) |item| {
        try writer.span(item.name);
        try generics(writer, item.parameters);
        try spans(writer, item.fields);
    }
    try writer.integer(catalog.variants.len);
    for (catalog.variants) |item| {
        try writer.span(item.name);
        try generics(writer, item.parameters);
        try writer.integer(item.cases.len);
        for (item.cases) |case| {
            try optionalSpan(writer, case.payload);
            try spans(writer, case.fields);
        }
    }
    inline for (.{ "aliases", "domains" }) |field| {
        const items = @field(catalog, field);
        try writer.integer(items.len);
        for (items) |item| {
            try writer.span(item.name);
            try writer.span(item.target);
        }
    }
    try writer.integer(catalog.constraints.len);
    for (catalog.constraints) |item| {
        try writer.span(item.name);
        try writer.span(item.span);
        try generic(writer, item.subject);
    }
    try writer.integer(catalog.functions.len);
    for (catalog.functions) |item| {
        try writer.span(item.name);
        try optionalSpan(writer, item.owner);
        try generics(writer, item.parameters);
        try spans(writer, item.inputs);
        try writer.span(item.return_type);
        try optionalSpan(writer, item.failure_type);
    }
}
fn types(writer: *wire.Writer, catalog: value.Types) Error!void {
    try writer.integer(catalog.suffixes.len);
    for (catalog.suffixes) |item| {
        try writer.span(item.span);
        try writer.span(item.base);
    }
    try writer.integer(catalog.callbacks.len);
    for (catalog.callbacks) |item| {
        try writer.span(item.span);
        try spans(writer, item.parameters);
        try writer.span(item.return_type);
        try optionalSpan(writer, item.failure_type);
    }
    try writer.integer(catalog.arrays.len);
    for (catalog.arrays) |item| {
        try writer.span(item.span);
        try optionalSpan(writer, item.enum_index);
        try writer.span(item.element);
    }
    try writer.integer(catalog.applications.len);
    for (catalog.applications) |item| {
        try writer.span(item.span);
        try writer.span(item.name);
        try spans(writer, item.arguments);
    }
    try writer.integer(catalog.tuples.len);
    for (catalog.tuples) |item| {
        try writer.span(item.span);
        try spans(writer, item.elements);
    }
}
fn put(bytes: []u8, at: usize, number: u32) void {
    std.mem.writeInt(u32, bytes[at..][0..4], number, .little);
}
fn get(bytes: []const u8, at: usize) u32 {
    return std.mem.readInt(u32, bytes[at..][0..4], .little);
}
/// Decode independently owned values and reject every malformed or unassociated reply.
// twin-drift-ok: Independent declaration and interface schemas require different magic, budgets, result codecs and provenance validators.
pub fn reply(a: std.mem.Allocator, bytes: []const u8, identity: [40]u8, input: Input) Error!value.Decoded {
    if (bytes.len < 76 or bytes.len > reply_limit) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[0..8], "SLKTIF01") or get(bytes, 8) != 1 or get(bytes, 12) != 1) return error.ComponentProtocol;
    if (get(bytes, 16) != 1 or get(bytes, 20) != bytes.len - 64) return error.ComponentProtocol;
    if (!std.mem.eql(u8, bytes[24..64], &identity)) return error.ComponentProtocol;
    var arena = std.heap.ArenaAllocator.init(a);
    errdefer arena.deinit();
    var reader: wire.Reader = .{ .arena = &arena, .bytes = bytes[64..] };
    if (!std.mem.eql(u8, try reader.take(8), "SLKTYR01")) return error.ComponentProtocol;
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
fn count(reader: *wire.Reader, limit: usize, minimum: usize) Error!usize {
    const size = try reader.integer();
    if (size > limit or size > (reader.bytes.len - reader.at) / minimum) return error.ComponentProtocol;
    return size;
}
fn success(reader: *wire.Reader) Error!value.Output {
    const a = reader.arena.allocator();
    const order = try a.alloc(usize, try count(reader, 4096, 4));
    for (order) |*item| item.* = try reader.integer();
    const used = try a.alloc([]const bool, try count(reader, 4096, 4));
    var total: usize = 0;
    for (used) |*items| {
        const size = try count(reader, 4096, 4);
        if (size > 65536 - total) return error.ComponentProtocol;
        total += size;
        const flags = try a.alloc(bool, size);
        for (flags) |*flag| flag.* = try reader.boolean();
        items.* = flags;
    }
    const resolutions = try a.alloc(value.Resolution, try count(reader, 65536, 32));
    for (resolutions) |*item| {
        const from = try reader.integer();
        const alias: ?[]const u8 = if (try reader.boolean()) try reader.blob() else null;
        const name = try reader.blob();
        const kind = std.enums.fromInt(declaration.Kind, try reader.integer()) orelse return error.ComponentProtocol;
        item.* = .{ .from = from, .alias = alias, .name = name, .kind = kind, .span = try reader.span(), .identity = .{ .module = try reader.integer(), .symbol = try reader.integer() } };
    }
    return .{ .order = order, .import_used = used, .resolutions = resolutions };
}
fn failure(reader: *wire.Reader) Error!declaration.Problem {
    const code = try reader.blob();
    const message = try reader.blob();
    const site = try reader.site();
    const related: ?declaration.Site = if (try reader.boolean()) try reader.site() else null;
    return .{ .code = code, .message = message, .site = site, .related = related };
}
