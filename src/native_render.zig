//! Generated Python-style renderers for the native `print` surface. One C
//! function per printable type, emitted only for the types a program actually
//! prints, so rendering is descriptor-driven without a second type table.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const native = @import("native_types.zig");
const numeric_surface = @import("numeric_surface.zig");
const typed = @import("typed.zig");
/// Invalid schemas, unsupported layouts or allocation failure.
pub const Error = native.Error;
const Item = struct { ty: typed.Type, name: []const u8 };

/// Renderer symbols identify semantic types independently of catalog order.
pub fn symbol(allocator: std.mem.Allocator, catalog: *const native.Catalog, ty: typed.Type) Error![]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(try catalog.identity(ty), &digest, .{});
    return std.fmt.allocPrint(allocator, "myl_r_{s}", .{std.fmt.bytesToHex(digest, .lower)});
}

/// Emit one renderer per type reachable from a `print` operand, in symbol order.
pub fn generate(allocator: std.mem.Allocator, catalog: *native.Catalog, program: bytecode.Program) Error![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var wanted: std.array_hash_map.Auto(typed.Type, void) = .empty;
    for (program.functions) |function| {
        for (function.scope.instructions) |instruction| {
            if (instruction.op != .print) continue;
            for (instruction.op.print.types) |ty| try discover(a, catalog, ty, &wanted);
        }
    }
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    if (wanted.count() == 0) return output.toOwnedSlice();
    const items = try a.alloc(Item, wanted.count());
    for (wanted.keys(), items) |ty, *item| item.* = .{ .ty = ty, .name = try symbol(a, catalog, ty) };
    std.mem.sort(Item, items, {}, lessThan);
    const writer = &output.writer;
    writer.writeAll("#include \"native_print.h\"\n") catch return error.OutOfMemory;
    for (items) |item| writer.print("void {s}(MylPrint *, const void *, unsigned);\n", .{item.name}) catch return error.OutOfMemory;
    for (items) |item| try emit(a, writer, catalog, item);
    return output.toOwnedSlice();
}

fn lessThan(_: void, left: Item, right: Item) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// Add one type and every type reachable from its printed contents.
fn discover(a: std.mem.Allocator, catalog: *native.Catalog, ty: typed.Type, wanted: *std.array_hash_map.Auto(typed.Type, void)) Error!void {
    if ((try wanted.getOrPut(a, ty)).found_existing) return;
    if (!ty.isAggregate() or ty.recordIndex() >= catalog.records.len) return;
    const record = catalog.records[ty.recordIndex()];
    if (numeric_surface.isFloat(ty, catalog.records)) return;
    if (record.managed) {
        switch (record.collection.kind) {
            .string, .bytes => {},
            .list => try discover(a, catalog, record.shape.buffer orelse return error.InvalidType, wanted),
            .dictionary => {
                try discover(a, catalog, record.collection.key orelse return error.InvalidType, wanted);
                try discover(a, catalog, record.shape.buffer orelse return error.InvalidType, wanted);
            },
        }
        return;
    }
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| try discover(a, catalog, payload, wanted);
        return;
    }
    if (record.shape.array) |array| return discover(a, catalog, array.element, wanted);
    if (record.shape.domain) |backing| return discover(a, catalog, backing, wanted);
    if (record.contract.callback != null or record.shape.hasRuntimeIdentity()) return;
    for (record.fields) |field| try discover(a, catalog, field.ty, wanted);
}

const header = "void {s}(MylPrint *o, const void *v, unsigned d) {{ ";

fn emit(a: std.mem.Allocator, writer: *std.Io.Writer, catalog: *native.Catalog, item: Item) Error!void {
    if (!item.ty.isAggregate()) return scalar(writer, catalog.records, item);
    const record = catalog.records[item.ty.recordIndex()];
    if (numeric_surface.isFloat(item.ty, catalog.records)) return body(writer, item.name, "myl_print_float(o, v, d);");
    if (record.managed) return collection(a, writer, catalog, item, record);
    if (record.shape.variants != null) return variant(a, writer, catalog, item, record);
    if (record.shape.array) |array| {
        const layout = try catalog.layout(item.ty);
        const element = try symbol(a, catalog, array.element);
        return body(writer, item.name, try std.fmt.allocPrint(a, "myl_print_array(o, v, d, {d}, {d}, {s});", .{ layout.count, layout.stride, element }));
    }
    if (record.shape.domain) |backing| {
        const inner = try symbol(a, catalog, backing);
        return body(writer, item.name, try std.fmt.allocPrint(a, "myl_print_domain(o, v, d, {s}, {s});", .{ try quoted(a, shortName(record.name)), inner }));
    }
    if (record.contract.callback != null or record.shape.hasRuntimeIdentity()) return body(writer, item.name, "myl_print_unprintable(o, v, d);");
    return fields(a, writer, catalog, item, record);
}

fn body(writer: *std.Io.Writer, name: []const u8, call: []const u8) Error!void {
    writer.print(header ++ "{s} }}\n", .{ name, call }) catch return error.OutOfMemory;
}

fn scalar(writer: *std.Io.Writer, records: []const typed.Record, item: Item) Error!void {
    _ = records;
    if (item.ty.integer()) |info| {
        var frame: [64]u8 = undefined;
        const call = std.fmt.bufPrint(&frame, "myl_print_integer(o, v, d, {d}, {d});", .{ info.bits / 8, @intFromBool(info.signed) }) catch return error.OutOfMemory;
        return body(writer, item.name, call);
    }
    return body(writer, item.name, switch (item.ty) {
        .bool => "myl_print_bool(o, v, d);",
        .unit => "myl_print_unit(o, v, d);",
        else => "myl_print_unprintable(o, v, d);",
    });
}

fn collection(a: std.mem.Allocator, writer: *std.Io.Writer, catalog: *native.Catalog, item: Item, record: typed.Record) Error!void {
    switch (record.collection.kind) {
        .string => return body(writer, item.name, "myl_print_text(o, v, d);"),
        .bytes => return body(writer, item.name, "myl_print_bytes(o, v, d);"),
        .list => {
            const element = try symbol(a, catalog, record.shape.buffer orelse return error.InvalidType);
            return body(writer, item.name, try std.fmt.allocPrint(a, "myl_print_list(o, v, d, {s});", .{element}));
        },
        .dictionary => {
            const key = try symbol(a, catalog, record.collection.key orelse return error.InvalidType);
            const value = try symbol(a, catalog, record.shape.buffer orelse return error.InvalidType);
            return body(writer, item.name, try std.fmt.allocPrint(a, "myl_print_dictionary(o, v, d, {s}, {s});", .{ key, value }));
        },
    }
}

fn fields(a: std.mem.Allocator, writer: *std.Io.Writer, catalog: *native.Catalog, item: Item, record: typed.Record) Error!void {
    const layout = try catalog.layout(item.ty);
    writer.print("static const MylPrintField {s}_fields[] = {{\n", .{item.name}) catch return error.OutOfMemory;
    for (record.fields, 0..) |field, index| {
        const child = try symbol(a, catalog, field.ty);
        writer.print(" {{{d}, {s}, {s}, 0}},\n", .{ layout.fields[index].offset, child, try quoted(a, field.name) }) catch return error.OutOfMemory;
    }
    writer.writeAll("};\n") catch return error.OutOfMemory;
    const call = try std.fmt.allocPrint(a, "myl_print_record(o, v, d, {s}, {s}_fields, {d});", .{ try quoted(a, shortName(record.name)), item.name, record.fields.len });
    return body(writer, item.name, call);
}

fn variant(a: std.mem.Allocator, writer: *std.Io.Writer, catalog: *native.Catalog, item: Item, record: typed.Record) Error!void {
    const layout = try catalog.layout(item.ty);
    const variants = record.shape.variants.?;
    writer.print("static const MylPrintField {s}_cases[] = {{\n", .{item.name}) catch return error.OutOfMemory;
    for (variants.cases, 0..) |case, tag| {
        const render = if (case.payload) |payload| try symbol(a, catalog, payload) else "NULL";
        const label = try caseName(a, shortName(record.name), variants.fallible, case);
        writer.print(" {{{d}, {s}, {s}, {d}}},\n", .{ layout.payload_offset, render, try quoted(a, label), tag }) catch return error.OutOfMemory;
    }
    writer.writeAll("};\n") catch return error.OutOfMemory;
    const call = try std.fmt.allocPrint(a, "myl_print_variant(o, v, d, {s}_cases, {d});", .{ item.name, variants.cases.len });
    return body(writer, item.name, call);
}

/// The spelling one case prints: bare for results, options and `None`, and
/// `Owner.case` for an enum or an ordinary union.
fn caseName(a: std.mem.Allocator, owner: []const u8, fallible: bool, case: typed.Variant) Error![]const u8 {
    const anonymous = std.mem.eql(u8, case.name, if (case.payload != null) "some" else "none");
    if (fallible or anonymous) return spelling(case.name);
    return std.fmt.allocPrint(a, "{s}.{s}", .{ owner, case.name });
}

fn spelling(name: []const u8) []const u8 {
    inline for (.{ "ok", "err", "some", "none" }, .{ "Ok", "Err", "Some", "None" }) |canonical, surface| {
        if (std.mem.eql(u8, name, canonical)) return surface;
    }
    return name;
}

fn shortName(name: []const u8) []const u8 {
    return if (std.mem.lastIndexOf(u8, name, "::")) |at| name[at + 2 ..] else name;
}

/// Render one declared spelling as a C string literal without escape surprises.
fn quoted(a: std.mem.Allocator, text: []const u8) Error![]const u8 {
    var escaped: std.ArrayList(u8) = .empty;
    try escaped.append(a, '"');
    for (text) |character| {
        if (character == '"' or character == '\\') try escaped.append(a, '\\');
        if (character < 0x20 or character == 0x7f) {
            try escaped.appendSlice(a, try std.fmt.allocPrint(a, "\\x{x:0>2}", .{character}));
            continue;
        }
        try escaped.append(a, character);
    }
    try escaped.append(a, '"');
    return escaped.toOwnedSlice(a);
}
