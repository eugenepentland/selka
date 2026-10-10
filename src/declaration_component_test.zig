//! Adversarial declaration transport and provenance admission tests.
const std = @import("std");
const value = @import("declaration_value.zig");
const validate = @import("declaration_validate.zig");
const protocol = @import("declaration_component_protocol.zig");
const wire = @import("declaration_wire_io.zig");
const t = std.testing;
fn basic() value.Input {
    return .{
        .context = .{
            .module = 7,
            .name = "sample",
            .path = "sample.my",
            .trusted_intrinsics = false,
            .is_imported = false,
            .source = "Thing method",
        },
        .declarations = &.{ .{ .category = .record, .span = .{ .start = 0, .end = 5 } }, .{ .category = .function, .span = .{ .start = 6, .end = 12 }, .owner = .{ .start = 0, .end = 5 } } },
        .imports = &.{},
        .exports = &.{},
        .public = &.{.{ .start = 0, .end = 5 }},
        .dependencies = &.{},
    };
}
fn symbols() [2]value.Symbol {
    return .{ .{ .name = "Thing", .kind = .type, .span = .{ .start = 0, .end = 5 }, .exported = true }, .{ .name = "Thing.method", .kind = .function, .span = .{ .start = 6, .end = 12 }, .owner = "Thing", .exported = true } };
}
fn valid(in: value.Input, output: value.Output) !void {
    try validate.input(t.allocator, in);
    try validate.outcome(t.allocator, in, .{ .success = output });
}
fn frame(result: value.Outcome, identity: [40]u8) ![]u8 {
    var writer: wire.Writer = .{ .allocator = t.allocator };
    defer writer.deinit();
    const header: [64]u8 = @splat(0);
    try writer.raw(&header);
    try writer.raw("SLKDCR01");
    switch (result) {
        .success => |output| {
            try writer.integer(0);
            try writer.integer(output.symbols.len);
            try writer.integer(output.import_used.len);
            for (output.symbols) |symbol| try writer.symbol(symbol);
            for (output.import_used) |used| try writer.boolean(used);
        },
        .failure => |problem| {
            try writer.integer(1);
            try writer.blob(problem.code);
            try writer.blob(problem.message);
            try writer.integer(problem.site.module);
            try writer.span(problem.site.span);
            try writer.boolean(problem.related != null);
            if (problem.related) |related| {
                try writer.integer(related.module);
                try writer.span(related.span);
            }
        },
    }
    const bytes = try writer.output.toOwnedSlice(t.allocator);
    @memcpy(bytes[0..8], "SLKDIX01");
    put(bytes, 8, 1);
    put(bytes, 12, 1);
    put(bytes, 16, 1);
    put(bytes, 20, @intCast(bytes.len - 64));
    @memcpy(bytes[24..64], &identity);
    return bytes;
}
fn put(bytes: []u8, at: usize, number: u32) void {
    std.mem.writeInt(u32, bytes[at..][0..4], number, .little);
}
fn reject(in: value.Input, bytes: []const u8, identity: [40]u8) !void {
    try t.expectError(error.ComponentProtocol, protocol.reply(t.allocator, bytes, identity, in));
}
fn truncated(in: value.Input, bytes: []const u8, identity: [40]u8) !void {
    for ([_]usize{ 0, 63, 75, 83, bytes.len - 1 }) |size| try reject(in, bytes[0..size], identity);
}
// spec: SELFHOST-DECLARATION-1
test "declaration reply retains owned owner bytes and exact exported table" {
    const in = basic();
    const table = symbols();
    try valid(in, .{ .symbols = &table, .import_used = &.{} });
    const request = try protocol.request(t.allocator, in, @splat(1));
    defer t.allocator.free(request.bytes);
    const bytes = try frame(.{ .success = .{ .symbols = &table, .import_used = &.{} } }, request.identity);
    defer t.allocator.free(bytes);
    var decoded = try protocol.reply(t.allocator, bytes, request.identity, in);
    defer decoded.deinit();
    @memset(bytes, 0);
    try t.expectEqualStrings("Thing.method", decoded.outcome.success.symbols[1].name);
    try t.expectEqualStrings("Thing", decoded.outcome.success.symbols[1].owner.?);
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration request identity is stable and binds every source context" {
    var in = basic();
    const first = try protocol.request(t.allocator, in, @splat(3));
    defer t.allocator.free(first.bytes);
    const equal = try protocol.request(t.allocator, in, @splat(3));
    defer t.allocator.free(equal.bytes);
    try t.expectEqualSlices(u8, first.bytes, equal.bytes);
    in.context.trusted_intrinsics = true;
    const changed = try protocol.request(t.allocator, in, @splat(3));
    defer t.allocator.free(changed.bytes);
    try t.expect(!std.mem.eql(u8, &first.identity, &changed.identity));
    const nonce = try protocol.request(t.allocator, in, @splat(4));
    defer t.allocator.free(nonce.bytes);
    try t.expectEqualSlices(u8, changed.identity[8..], nonce.identity[8..]);
    try t.expect(!std.mem.eql(u8, &changed.identity, &nonce.identity));
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration reply rejects corrupt frame fields truncation trailing data and stale identity" {
    const in = basic();
    const table = symbols();
    const identity = @as([40]u8, @splat(5));
    const bytes = try frame(.{ .success = .{ .symbols = &table, .import_used = &.{} } }, identity);
    defer t.allocator.free(bytes);
    for ([_]usize{ 0, 8, 12, 16, 20, 24, 32, 64, 72 }) |at| {
        bytes[at] ^= 127;
        try reject(in, bytes, identity);
        bytes[at] ^= 127;
    }
    try truncated(in, bytes, identity);
    const trailing = try t.allocator.alloc(u8, bytes.len + 1);
    defer t.allocator.free(trailing);
    @memcpy(trailing[0..bytes.len], bytes);
    trailing[bytes.len] = 0;
    put(trailing, 20, @intCast(trailing.len - 64));
    try reject(in, trailing, identity);
    try reject(in, bytes, @splat(6));
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration reply rejects noncanonical booleans enums and absurd count before allocation" {
    const identity = @as([40]u8, @splat(9));
    const table = symbols();
    const bytes = try frame(.{ .success = .{ .symbols = &table, .import_used = &.{} } }, identity);
    defer t.allocator.free(bytes);
    // Prefix: inner magic8+outcome4+counts8, then name length4+Thing5.
    for ([_]usize{ 84 + 9, 84 + 9 + 12 }) |at| {
        const old = std.mem.readInt(u32, bytes[at..][0..4], .little);
        put(bytes, at, 99);
        try reject(basic(), bytes, identity);
        put(bytes, at, old);
    }
    put(bytes, 76, 65537);
    try reject(basic(), bytes, identity);
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration symbol order name kind owner visibility and range are all admitted" {
    var table = symbols();
    const output: value.Output = .{ .symbols = &table, .import_used = &.{} };
    table[0].kind = .function;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, basic(), .{ .success = output }));
    table = symbols();
    table[1].owner = "Other";
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, basic(), .{ .success = output }));
    table = symbols();
    table[1].name = table[0].name;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, basic(), .{ .success = output }));
    table = symbols();
    table[0].exported = false;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, basic(), .{ .success = output }));
    table = symbols();
    table[1].span.end += 1;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, basic(), .{ .success = output }));
    table = symbols();
    std.mem.swap(value.Symbol, &table[0], &table[1]);
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, basic(), .{ .success = output }));
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration input accepts exact source path name and row bounds and rejects first excess" {
    var in = basic();
    in.declarations = &.{};
    in.public = &.{};
    const raw = try t.allocator.alloc(u8, 1048577);
    defer t.allocator.free(raw);
    @memset(raw, 'x');
    in.context.source = raw[0..1048576];
    in.context.name = "";
    in.context.path = raw[0..16384];
    try validate.input(t.allocator, in);
    in.context.source = raw;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    in.context.source = raw[0..1048576];
    in.context.path = raw[0..16385];
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    in.context.path = "";
    in.context.name = raw[0..1048576];
    try validate.input(t.allocator, in);
    in.context.name = raw;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    in.context.name = "";
    const rows = try t.allocator.alloc(value.Declaration, 65537);
    defer t.allocator.free(rows);
    @memset(rows, .{ .category = .record, .span = .{ .start = 0, .end = 1 } });
    in.declarations = rows[0..65536];
    try validate.input(t.allocator, in);
    in.declarations = rows;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration failure requires known catalog and original local site" {
    var problem: value.Problem = .{
        .code = "E_DUPLICATE_SYMBOL",
        .message = "module declaration name is already bound",
        .site = .{ .module = 7, .span = .{ .start = 6, .end = 12 } },
        .related = .{ .module = 7, .span = .{ .start = 0, .end = 5 } },
    };
    try validate.outcome(t.allocator, basic(), .{ .failure = problem });
    problem.message = "invented";
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, basic(), .{ .failure = problem }));
    problem.message = "module declaration name is already bound";
    problem.site.module = 8;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, basic(), .{ .failure = problem }));
    problem.site.module = 7;
    problem.related = null;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, basic(), .{ .failure = problem }));
}
fn facade() value.Input {
    var in = basic();
    in.declarations = &.{};
    in.public = &.{};
    in.imports = &.{.{ .name = "dep", .alias = "d", .span = .{ .start = 0, .end = 5 }, .target = 9 }};
    in.exports = &.{.{ .name = "Item", .alias = "d", .span = .{ .start = 6, .end = 12 } }};
    in.dependencies = &.{.{ .module = 9, .name = "dep", .source_len = 8, .symbols = &.{.{ .name = "Item", .kind = .type, .span = .{ .start = 0, .end = 4 }, .exported = true, .re_export = .{ .module = 21, .symbol = 17 } }} }};
    return in;
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration facade preserves transitive canonical origin and exact import usage" {
    const in = facade();
    var table = [_]value.Symbol{.{ .name = "Item", .kind = .type, .span = .{ .start = 6, .end = 12 }, .exported = true, .re_export = .{ .module = 21, .symbol = 17 } }};
    var used = [_]bool{true};
    const output: value.Output = .{ .symbols = &table, .import_used = &used };
    try valid(in, output);
    table[0].re_export = .{ .module = 9, .symbol = 0 };
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = output }));
    table[0].re_export = .{ .module = 21, .symbol = 17 };
    used[0] = false;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = output }));
    used[0] = true;
    table[0].owner = "Item";
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = output }));
    table[0].owner = null;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = .{ .symbols = &table, .import_used = &.{} } }));
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration private failure identifies actual direct target not its transitive origin" {
    const in = facade();
    var problem: value.Problem = .{
        .code = "E_PRIVATE_SYMBOL",
        .message = "declaration is private to its module",
        .site = .{ .module = 7, .span = .{ .start = 6, .end = 12 } },
        .related = .{ .module = 9, .span = .{ .start = 0, .end = 4 } },
    };
    try validate.outcome(t.allocator, in, .{ .failure = problem });
    problem.related.?.module = 21;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .failure = problem }));
    problem.related.?.module = 9;
    problem.related.?.span.end = 5;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .failure = problem }));
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration input rejects invalid spans unresolved dependencies and repeated dependency identities" {
    var in = basic();
    in.context.source = "";
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    in = facade();
    in.dependencies = &.{};
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    in = facade();
    const duplicate = [_]value.Dependency{ in.dependencies[0], in.dependencies[0] };
    in.dependencies = &duplicate;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration wire byte budget rejects first excess without growth" {
    const bytes = try t.allocator.alloc(u8, wire.wire_limit + 1);
    defer t.allocator.free(bytes);
    @memset(bytes, 0);
    var writer: wire.Writer = .{ .allocator = t.allocator };
    defer writer.deinit();
    try writer.raw(bytes[0..wire.wire_limit]);
    try t.expectError(error.ComponentProtocol, writer.raw(bytes[wire.wire_limit..]));
    try t.expectEqual(wire.wire_limit, writer.output.items.len);
    try reject(basic(), bytes, @splat(0));
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration valid frames with incomplete or altered tables fail before adoption" {
    const identity: [40]u8 = @splat(11);
    var table = symbols();
    var output: value.Output = .{ .symbols = table[0..1], .import_used = &.{} };
    const omitted = try frame(.{ .success = output }, identity);
    defer t.allocator.free(omitted);
    try reject(basic(), omitted, identity);
    output.symbols = &table;
    for (0..5) |change| {
        table = symbols();
        switch (change) {
            0 => std.mem.swap(value.Symbol, &table[0], &table[1]),
            1 => table[0].kind = .constraint,
            2 => table[0].name = "Forged",
            3 => table[1].owner = null,
            else => table[0].re_export = .{ .module = 9, .symbol = 0 },
        }
        const altered = try frame(.{ .success = output }, identity);
        defer t.allocator.free(altered);
        try reject(basic(), altered, identity);
    }
}
// spec-case: SELFHOST-DECLARATION-1
test "declaration imports dependencies exports and public rows enforce exact count boundaries" {
    var in = basic();
    in.declarations = &.{};
    in.public = &.{};
    in.context.name = "";
    const deps = try t.allocator.alloc(value.Dependency, 4097);
    defer t.allocator.free(deps);
    const imports = try t.allocator.alloc(value.Import, 4097);
    defer t.allocator.free(imports);
    var names: [4097][2]u8 = undefined;
    for (deps, imports, 0..) |*dep, *imported, id| {
        names[id] = .{ @intCast(id / 256), @intCast(id % 256) };
        dep.* = .{ .module = id + 100, .name = &names[id], .source_len = 0, .symbols = &.{} };
        imported.* = .{ .name = &names[id], .alias = &names[id], .span = .{ .start = 0, .end = 0 }, .target = id + 100 };
    }
    in.dependencies = deps[0..4096];
    in.imports = imports[0..4096];
    try validate.input(t.allocator, in);
    in.imports = imports;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    in.imports = &.{};
    in.dependencies = deps;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    in.dependencies = &.{};
    const exports = try t.allocator.alloc(value.Export, 65537);
    defer t.allocator.free(exports);
    @memset(exports, .{ .name = "", .alias = null, .span = .{ .start = 0, .end = 0 } });
    in.exports = exports[0..65536];
    try validate.input(t.allocator, in);
    in.exports = exports;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    in.exports = &.{};
    const spans = try t.allocator.alloc(@import("source.zig").Span, 65537);
    defer t.allocator.free(spans);
    @memset(spans, .{ .start = 0, .end = 1 });
    in.public = spans[0..65536];
    try validate.input(t.allocator, in);
    in.public = spans;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
}
