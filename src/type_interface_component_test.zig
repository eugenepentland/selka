//! Adversarial framing, ownership and raw-source provenance for interface batches.
const std = @import("std");
const value = @import("type_interface_value.zig");
const protocol = @import("type_interface_protocol.zig");
const validate = @import("type_interface_validate.zig");
const wire = @import("type_interface_wire_io.zig");
const declaration = @import("declaration_value.zig");
const Span = @import("source.zig").Span;
const t = std.testing;
fn module() value.Module {
    return .{
        .context = .{ .module = 0, .name = "sample", .path = "sample.my", .trusted_intrinsics = false, .is_imported = false, .source = "Thing f Thing" },
        .imports = &.{},
        .symbols = &.{
            .{ .name = "Thing", .kind = .type, .span = .{ .start = 0, .end = 5 }, .exported = true },
            .{ .name = "f", .kind = .function, .span = .{ .start = 6, .end = 7 }, .exported = true },
        },
        .import_used = &.{},
        .syntax = .{ .declarations = .{
            .records = &.{.{ .name = .{ .start = 0, .end = 5 }, .parameters = &.{}, .fields = &.{} }},
            .functions = &.{.{ .name = .{ .start = 6, .end = 7 }, .owner = null, .parameters = &.{}, .inputs = &.{}, .return_type = .{ .start = 8, .end = 13 }, .failure_type = null }},
        } },
    };
}
fn resolution() value.Resolution {
    return .{ .from = 0, .alias = null, .name = "Thing", .kind = .type, .span = .{ .start = 8, .end = 13 }, .identity = .{ .module = 0, .symbol = 0 } };
}
fn output(items: []const value.Resolution) value.Output {
    return .{ .order = &.{0}, .import_used = &.{&.{}}, .resolutions = items };
}
fn frame(result: value.Outcome, identity: [40]u8) ![]u8 {
    var writer: wire.Writer = .{ .allocator = t.allocator };
    defer writer.deinit();
    const header: [64]u8 = @splat(0);
    try writer.raw(&header);
    try writer.raw("SLKTYR01");
    switch (result) {
        .success => |reply| {
            try writer.integer(0);
            try writer.integer(reply.order.len);
            for (reply.order) |id| try writer.integer(id);
            try writer.integer(reply.import_used.len);
            for (reply.import_used) |flags| {
                try writer.integer(flags.len);
                for (flags) |flag| try writer.boolean(flag);
            }
            try writer.integer(reply.resolutions.len);
            for (reply.resolutions) |item| {
                try writer.integer(item.from);
                try writer.boolean(item.alias != null);
                if (item.alias) |alias| try writer.blob(alias);
                try writer.blob(item.name);
                try writer.integer(@backingInt(item.kind));
                try writer.span(item.span);
                try writer.integer(item.identity.module);
                try writer.integer(item.identity.symbol);
            }
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
    @memcpy(bytes[0..8], "SLKTIF01");
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
// spec: SELFHOST-TYPE-INTERFACE-1
test "type interface reply owns exact ordered usage and canonical resolution receipts" {
    const modules = [_]value.Module{module()};
    const in: value.Input = .{ .order = &.{0}, .modules = &modules };
    const resolutions = [_]value.Resolution{resolution()};
    const result: value.Outcome = .{ .success = output(&resolutions) };
    const request = try protocol.request(t.allocator, in, @splat(3));
    defer t.allocator.free(request.bytes);
    const bytes = try frame(result, request.identity);
    defer t.allocator.free(bytes);
    var decoded = try protocol.reply(t.allocator, bytes, request.identity, in);
    defer decoded.deinit();
    @memset(bytes, 0);
    try t.expect(value.equal(result, decoded.outcome));
    try t.expectEqualStrings("Thing", decoded.outcome.success.resolutions[0].name);
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface request identity binds source authority and preserves nonce separation" {
    var modules = [_]value.Module{module()};
    const in: value.Input = .{ .order = &.{0}, .modules = &modules };
    const first = try protocol.request(t.allocator, in, @splat(4));
    defer t.allocator.free(first.bytes);
    const repeat = try protocol.request(t.allocator, in, @splat(4));
    defer t.allocator.free(repeat.bytes);
    try t.expectEqualSlices(u8, first.bytes, repeat.bytes);
    modules[0].context.trusted_intrinsics = true;
    const changed = try protocol.request(t.allocator, in, @splat(4));
    defer t.allocator.free(changed.bytes);
    try t.expect(!std.mem.eql(u8, &first.identity, &changed.identity));
    const nonce = try protocol.request(t.allocator, in, @splat(5));
    defer t.allocator.free(nonce.bytes);
    try t.expectEqualSlices(u8, changed.identity[8..], nonce.identity[8..]);
    try t.expect(!std.mem.eql(u8, &changed.identity, &nonce.identity));
}
fn truncated(in: value.Input, bytes: []const u8, identity: [40]u8) !void {
    for ([_]usize{ 0, 63, 75, bytes.len - 1 }) |size| try reject(in, bytes[0..size], identity);
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface rejects malformed correlated frames counts and trailing bytes" {
    const modules = [_]value.Module{module()};
    const in: value.Input = .{ .order = &.{0}, .modules = &modules };
    const resolutions = [_]value.Resolution{resolution()};
    const identity: [40]u8 = @splat(6);
    const bytes = try frame(.{ .success = output(&resolutions) }, identity);
    defer t.allocator.free(bytes);
    for ([_]usize{ 0, 8, 12, 16, 20, 24, 32, 64, 72, 76 }) |at| {
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
    try reject(in, bytes, @splat(7));
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface rejects authenticated wrong names kinds identities and source sites" {
    const modules = [_]value.Module{module()};
    const in: value.Input = .{ .order = &.{0}, .modules = &modules };
    var rows = [_]value.Resolution{resolution()};
    const identity: [40]u8 = @splat(8);
    for (0..7) |change| {
        rows[0] = resolution();
        switch (change) {
            0 => rows[0].name = "forged",
            1 => rows[0].kind = .function,
            2 => rows[0].identity.symbol = 1,
            3 => rows[0].identity.module = 1,
            4 => rows[0].span = .{ .start = 0, .end = 5 },
            5 => rows[0].from = 1,
            else => rows[0].alias = "invented",
        }
        const bytes = try frame(.{ .success = output(&rows) }, identity);
        defer t.allocator.free(bytes);
        try reject(in, bytes, identity);
    }
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface requires exact traversal acknowledgement and usage shape" {
    const modules = [_]value.Module{module()};
    const in: value.Input = .{ .order = &.{0}, .modules = &modules };
    var result = output(&.{});
    result.order = &.{};
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = result }));
    result = output(&.{});
    result.import_used = &.{};
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = result }));
    result.import_used = &.{&.{true}};
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = result }));
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface diagnostics require exact catalog and original syntax provenance" {
    const modules = [_]value.Module{module()};
    const in: value.Input = .{ .order = &.{0}, .modules = &modules };
    var problem: declaration.Problem = .{
        .code = "E_PRIVATE_INTERFACE",
        .message = "exported interface exposes an unexported type",
        .site = .{ .module = 0, .span = .{ .start = 8, .end = 13 } },
        .related = .{ .module = 0, .span = .{ .start = 0, .end = 5 } },
    };
    try validate.outcome(t.allocator, in, .{ .failure = problem });
    problem.message = "forged";
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .failure = problem }));
    problem.message = "exported interface exposes an unexported type";
    problem.site.span = .{ .start = 1, .end = 4 };
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .failure = problem }));
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface admits exact source aggregate and path budgets rejects first excess" {
    const raw = try t.allocator.alloc(u8, 1048577);
    defer t.allocator.free(raw);
    @memset(raw, 'x');
    var modules: [8]value.Module = undefined;
    for (&modules, 0..) |*item, id| {
        item.* = module();
        item.context.module = id;
        item.context.source = raw[0..1048576];
        item.context.name = "";
        item.context.path = raw[0..16384];
        item.symbols = &.{};
        item.syntax = .{};
    }
    const in: value.Input = .{ .order = &.{ 0, 1, 2, 3, 4, 5, 6, 7 }, .modules = &modules };
    try validate.input(t.allocator, in);
    modules[0].context.source = raw;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    modules[0].context.source = raw[0..1048576];
    modules[0].context.path = raw[0..16385];
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface rejects malformed source graph order and noncanonical reexports" {
    var modules = [_]value.Module{module()};
    var in: value.Input = .{ .order = &.{1}, .modules = &modules };
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    in.order = &.{0};
    modules[0].context.is_imported = true;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    modules[0].context.is_imported = false;
    var symbols = [_]declaration.Symbol{module().symbols[0]};
    symbols[0].re_export = .{ .module = 0, .symbol = 0 };
    modules[0].symbols = &symbols;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface rejects recursive type self edges and depth first excess" {
    const raw = try t.allocator.alloc(u8, 258);
    defer t.allocator.free(raw);
    @memset(raw, 'x');
    var modules = [_]value.Module{module()};
    modules[0].context.source = raw;
    modules[0].symbols = &.{};
    modules[0].syntax = .{};
    const suffixes = try t.allocator.alloc(value.Suffix, 257);
    defer t.allocator.free(suffixes);
    for (suffixes, 0..) |*item, id| item.* = .{ .span = .{ .start = 0, .end = id + 2 }, .base = .{ .start = 0, .end = id + 1 } };
    modules[0].syntax.types.suffixes = suffixes[0..255];
    const in: value.Input = .{ .order = &.{0}, .modules = &modules };
    try validate.input(t.allocator, in);
    modules[0].syntax.types.suffixes = suffixes[0..256];
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
    modules[0].syntax.types.suffixes = suffixes[0..1];
    suffixes[0].base = suffixes[0].span;
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, in));
}
fn importedModules() [3]value.Module {
    var modules = [_]value.Module{ module(), module(), module() };
    modules[0].context.source = "f dep.Thing";
    modules[0].symbols = &.{.{ .name = "f", .kind = .function, .span = .{ .start = 0, .end = 1 }, .exported = true }};
    modules[0].imports = &.{.{ .name = "dep", .alias = "d", .span = .{ .start = 2, .end = 5 }, .target = 1 }};
    modules[0].import_used = &.{false};
    modules[0].syntax = .{ .declarations = .{ .functions = &.{.{ .name = .{ .start = 0, .end = 1 }, .owner = null, .parameters = &.{}, .inputs = &.{}, .return_type = .{ .start = 2, .end = 11 }, .failure_type = null }} } };
    modules[1].context = .{ .module = 1, .name = "dep", .path = "dep.my", .trusted_intrinsics = false, .is_imported = true, .source = "Thing" };
    modules[1].symbols = &.{.{ .name = "Thing", .kind = .type, .span = .{ .start = 0, .end = 5 }, .exported = true, .re_export = .{ .module = 2, .symbol = 0 } }};
    modules[1].imports = &.{.{ .name = "base", .alias = "base", .span = .{ .start = 0, .end = 5 }, .target = 2 }};
    modules[1].import_used = &.{true};
    modules[1].syntax = .{};
    modules[2].context = .{ .module = 2, .name = "base", .path = "base.my", .trusted_intrinsics = false, .is_imported = true, .source = "Thing" };
    modules[2].symbols = &.{.{ .name = "Thing", .kind = .type, .span = .{ .start = 0, .end = 5 }, .exported = true }};
    modules[2].syntax = .{};
    return modules;
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface receipts bind direct import usage and transitive defining identity" {
    const modules = importedModules();
    const in: value.Input = .{ .order = &.{ 2, 1, 0 }, .modules = &modules };
    try validate.input(t.allocator, in);
    var resolutions = [_]value.Resolution{.{ .from = 0, .alias = "dep", .name = "Thing", .kind = .type, .span = .{ .start = 2, .end = 11 }, .identity = .{ .module = 2, .symbol = 0 } }};
    var result: value.Output = .{ .order = in.order, .import_used = &.{ &.{true}, &.{true}, &.{} }, .resolutions = &resolutions };
    try validate.outcome(t.allocator, in, .{ .success = result });
    resolutions[0].identity.module = 1;
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = result }));
    resolutions[0].identity.module = 2;
    result.import_used = &.{ &.{true}, &.{false}, &.{} };
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = result }));
    result.import_used = &.{ &.{false}, &.{true}, &.{} };
    try t.expectError(error.ComponentProtocol, validate.outcome(t.allocator, in, .{ .success = result }));
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface preserves raw whitespace in qualified aliases and named bound provenance" {
    var modules = importedModules();
    modules[0].context.source = "f dep . Thing";
    modules[0].syntax.declarations.functions = &.{.{ .name = .{ .start = 0, .end = 1 }, .owner = null, .parameters = &.{}, .inputs = &.{}, .return_type = .{ .start = 2, .end = 13 }, .failure_type = null }};
    const in: value.Input = .{ .order = &.{ 2, 1, 0 }, .modules = &modules };
    const rows = [_]value.Resolution{.{ .from = 0, .alias = "dep", .name = "Thing", .kind = .type, .span = .{ .start = 2, .end = 13 }, .identity = .{ .module = 2, .symbol = 0 } }};
    const result: value.Output = .{ .order = in.order, .import_used = &.{ &.{true}, &.{true}, &.{} }, .resolutions = &rows };
    try validate.outcome(t.allocator, in, .{ .success = result });
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface permits empty project and rejects module first excess" {
    const empty: value.Input = .{ .order = &.{}, .modules = &.{} };
    try validate.input(t.allocator, empty);
    try validate.outcome(t.allocator, empty, .{ .success = .{ .order = &.{}, .import_used = &.{}, .resolutions = &.{} } });
    const modules = try t.allocator.alloc(value.Module, 4097);
    defer t.allocator.free(modules);
    const order = try t.allocator.alloc(usize, 4097);
    defer t.allocator.free(order);
    for (modules, order, 0..) |*item, *id, position| {
        item.* = module();
        item.context.module = position;
        item.context.source = "";
        item.context.name = "";
        item.context.path = "";
        item.symbols = &.{};
        item.syntax = .{};
        id.* = position;
    }
    try validate.input(t.allocator, .{ .order = order[0..4096], .modules = modules[0..4096] });
    try t.expectError(error.ComponentProtocol, validate.input(t.allocator, .{ .order = order, .modules = modules }));
}
fn shapeAllocation(a: std.mem.Allocator) !void {
    var modules = [_]value.Module{module()};
    modules[0].context.source = "xx";
    modules[0].symbols = &.{};
    modules[0].syntax = .{ .types = .{ .suffixes = &.{.{ .span = .{ .start = 0, .end = 2 }, .base = .{ .start = 0, .end = 1 } }} } };
    try validate.input(a, .{ .order = &.{0}, .modules = &modules });
}
// spec-case: SELFHOST-TYPE-INTERFACE-1
test "type interface childrenOf allocation failures release earlier shape storage" {
    try t.checkAllAllocationFailures(t.allocator, shapeAllocation, .{});
}
