//! Development-only complete typed entry-adapter oracle; no production routing.
const std = @import("std");
const typed = @import("src/typed.zig");
const adapter = @import("src/entry_adapter.zig");
const wire = @import("src/parser_value.zig");
extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;
extern "c" fn fopen([*:0]const u8, [*:0]const u8) ?*anyopaque;
extern "c" fn fread([*]u8, usize, usize, *anyopaque) usize;
extern "c" fn fwrite([*]const u8, usize, usize, *anyopaque) usize;
extern "c" fn fclose(*anyopaque) c_int;
extern "c" var stdout: *anyopaque;

fn read(a: std.mem.Allocator, path: [*:0]const u8) ![]const u8 {
    const file = fopen(path, "rb") orelse return error.Open;
    defer _ = fclose(file);
    const buffer = try a.alloc(u8, wire.value_wire_limit + 1);
    const size = fread(buffer.ptr, 1, buffer.len, file);
    if (size > wire.value_wire_limit) return error.SizeLimit;
    return buffer[0..size];
}

fn fixture(a: std.mem.Allocator, index: usize) !typed.Program {
    if (index >= 30) return error.Case;
    const parameter_counts = [_]usize{ 0, 1, 3 };
    const count = parameter_counts[index % 3];
    const family = index / 3;
    const result_type: typed.Type = if (family == 0) .i64 else if (family == 1) .unit else @fromBackingInt(19);
    const success: typed.Type = if ((family -| 2) % 2 == 0) .i64 else .unit;
    const failure: typed.Type = if (((family -| 2) / 2) % 2 == 0) .i64 else .bool;
    const reversed = family >= 6;
    const span: @import("src/source.zig").Span = .{ .start = 17, .end = 21 };
    const locals = try a.alloc(typed.Local, count);
    const kinds = [_]typed.Type{ .filesystem_cap, .stream_cap, .stream_cap };
    const names = [_][]const u8{ "fs", "out", "err" };
    for (locals, 0..) |*local, i| local.* = .{
        .name = names[i],
        .declaration = span,
        .ty = kinds[i],
        .mutable = i == 0,
        .origin = .parameter,
        .ownership = .{ .initialized = true, .transfer_span = span, .transfer_available = true },
        .usage = .{ .reads = 7, .writes = 2, .dead_write_reads = 3, .dead_write_span = span },
    };
    const nodes = try a.alloc(typed.Node, if (family >= 2) 3 else 2);
    nodes[0] = .{ .span = .{ .start = 0, .end = 4 }, .ty = .unit, .data = .unit };
    nodes[1] = .{ .span = span, .ty = if (family >= 2) success else result_type, .data = if (result_type == .unit or (family >= 2 and success == .unit)) .unit else .{ .integer = 7 } };
    if (family >= 2) nodes[2] = .{ .span = span, .ty = result_type, .data = .{ .variant = .{ .tag = @intFromBool(reversed), .value = @as(typed.NodeId, @fromBackingInt(1)) } } };
    const statements = try a.dupe(typed.Statement, &.{
        .{ .span = .{ .start = 0, .end = 4 }, .terminates = true, .data = .{ .ret = @fromBackingInt(0) } },
        .{ .span = span, .terminates = true, .data = .{ .ret = @fromBackingInt(nodes.len - 1) } },
    });
    const functions = try a.dupe(typed.Function, &.{
        .{ .id = @fromBackingInt(0), .name = "helper", .declaration = .{ .start = 0, .end = 4 }, .signature = .{ .return_type = .unit }, .scope = .{ .body = @fromBackingInt(0) } },
        .{ .id = @fromBackingInt(1), .name = "main", .declaration = span, .signature = .{ .return_type = result_type, .parameter_count = count }, .scope = .{ .locals = locals, .body = @fromBackingInt(1) } },
    });
    var records: []const typed.Record = &.{};
    if (family >= 2) {
        const cases = try a.alloc(typed.Variant, 2);
        cases[@intFromBool(reversed)] = .{ .name = "ok", .declaration = span, .payload = success };
        cases[@intFromBool(!reversed)] = .{ .name = "err", .declaration = span, .payload = failure };
        records = try a.dupe(typed.Record, &.{.{ .id = result_type, .name = "Result", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .fallible = true, .is_union = true, .cases = cases } } }});
    }
    const aliases = try a.dupe(typed.TypeAlias, &.{.{ .name = "ExitCode", .target = .i64, .declaration = span }});
    return .{ .aliases = aliases, .nodes = nodes, .statements = statements, .functions = functions, .main = @fromBackingInt(1), .records = records };
}

/// ENTRY_CASE selects one of thirty exact typed controls. ENTRY_ADAPT selects
/// native adaptation; ENTRY_REPLY verifies every candidate field canonically.
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const selected = getenv("ENTRY_CASE") orelse return error.NoCase;
    const index = try std.fmt.parseInt(usize, std.mem.span(selected), 10);
    var program = try fixture(a, index);
    if (getenv("ENTRY_ADAPT") != null) try adapter.adapt(a, &program);
    const magic = if (getenv("ENTRY_ADAPT") != null) "SLKBKR01" else "SLKBKI01";
    const expected = try wire.encodeTreeProfile(a, typed.Program, program, magic, .body);
    if (getenv("ENTRY_REPLY")) |path| {
        const bytes = try read(a, path);
        const candidate = try wire.decodeIntoProfile(typed.Program, a, bytes, "SLKBKR01", .body);
        const canonical = try wire.encodeTreeProfile(a, typed.Program, candidate, "SLKBKR01", .body);
        if (!std.mem.eql(u8, expected, canonical)) return error.EntryParity;
    }
    if (fwrite(expected.ptr, 1, expected.len, stdout) != expected.len) return error.Write;
}
