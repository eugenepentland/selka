//! Python-style rendering of checked runtime values for the `print` builtin.
const std = @import("std");
const typed = @import("typed.zig");
const numeric_surface = @import("numeric_surface.zig");
const runtime = @import("runtime_values.zig");

/// Failures returned by render; callers must handle these boundary errors.
pub const Error = std.Io.Writer.Error || error{Unprintable};
/// Nesting beyond this depth renders as `...`, so cyclic managed graphs terminate.
pub const max_depth: usize = 24;

/// Whether a checked type has a Python rendering, used to reject `print` arguments.
pub fn printable(ty: typed.Type, records: []const typed.Record) bool {
    if (ty == .unit or ty == .bool or ty.isInteger()) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.isCell() or record.collection.contains_cell) return false;
    if (record.contract.callback != null or record.shape.resource != null) return false;
    if (record.contract.move_only) return false;
    return true;
}

/// Render one value into caller-owned bytes, the way `print` would write it.
/// `str(value)` and an `f"{value}"` hole share this with `print`, so one value has
/// one spelling wherever it is written.
pub fn renderAlloc(allocator: std.mem.Allocator, records: []const typed.Record, value: typed.Value) error{ Unprintable, OutOfMemory }![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    render(&output.writer, records, value, 0) catch |err| switch (err) {
        // An allocating writer fails only by running out of memory.
        error.WriteFailed => return error.OutOfMemory,
        else => |failure| return failure,
    };
    return output.toOwnedSlice();
}

/// Strip a module qualification so printed records read like their source spelling.
pub fn shortName(name: []const u8) []const u8 {
    return if (std.mem.lastIndexOf(u8, name, "::")) |at| name[at + 2 ..] else name;
}

/// Map the canonical prelude case spellings back onto their constructor names.
fn caseSpelling(name: []const u8) []const u8 {
    inline for (.{ "ok", "err", "some", "none" }, .{ "Ok", "Err", "Some", "None" }) |canonical, surface| {
        if (std.mem.eql(u8, name, canonical)) return surface;
    }
    return name;
}

/// Render one value; depth zero prints text raw, deeper text uses `repr` quoting.
pub fn render(writer: *std.Io.Writer, records: []const typed.Record, value: typed.Value, depth: usize) Error!void {
    if (depth > max_depth) return writer.writeAll("...");
    switch (value) {
        .unit => try writer.writeAll("None"),
        .bool => |flag| try writer.writeAll(if (flag) "True" else "False"),
        .i64 => |number| try writer.print("{d}", .{number}),
        .integer => |number| try writer.print("{d}", .{number.value}),
        .capability, .owned => return error.Unprintable,
        .managed => |object| try collection(writer, records, object, depth),
        .aggregate => |record| try aggregate(writer, records, record, depth),
    }
}

fn collection(writer: *std.Io.Writer, records: []const typed.Record, object: *runtime.ManagedObject, depth: usize) Error!void {
    switch (object.collection.kind) {
        .string => try text(writer, object, depth != 0),
        .bytes => try bytes(writer, object),
        .list => {
            try writer.writeByte('[');
            for (object.items.items, 0..) |item, index| {
                if (index != 0) try writer.writeAll(", ");
                try render(writer, records, item, depth + 1);
            }
            try writer.writeByte(']');
        },
        .dictionary => {
            try writer.writeByte('{');
            var index: usize = 0;
            while (index + 1 < object.items.items.len) : (index += 2) {
                if (index != 0) try writer.writeAll(", ");
                try render(writer, records, object.items.items[index], depth + 1);
                try writer.writeAll(": ");
                try render(writer, records, object.items.items[index + 1], depth + 1);
            }
            try writer.writeByte('}');
        },
    }
}

fn text(writer: *std.Io.Writer, object: *runtime.ManagedObject, quoted: bool) Error!void {
    if (quoted) try writer.writeByte('\'');
    for (object.items.items) |point| {
        const scalar: u21 = @intCast(point.asInteger() catch return error.Unprintable);
        if (quoted and (scalar == '\'' or scalar == '\\')) try writer.writeByte('\\');
        if (quoted and escape(scalar) != null) {
            try writer.writeByte('\\');
            try writer.writeByte(escape(scalar).?);
            continue;
        }
        var buffer: [4]u8 = undefined;
        const size = std.unicode.utf8Encode(scalar, &buffer) catch return error.Unprintable;
        try writer.writeAll(buffer[0..size]);
    }
    if (quoted) try writer.writeByte('\'');
}

fn escape(scalar: u21) ?u8 {
    return switch (scalar) {
        '\n' => 'n',
        '\r' => 'r',
        '\t' => 't',
        else => null,
    };
}

fn bytes(writer: *std.Io.Writer, object: *runtime.ManagedObject) Error!void {
    try writer.writeAll("b'");
    for (object.items.items) |item| {
        const byte: u8 = @intCast(item.asInteger() catch return error.Unprintable);
        if (byte == '\'' or byte == '\\') {
            try writer.writeByte('\\');
            try writer.writeByte(byte);
        } else if (escape(byte)) |code| {
            try writer.writeByte('\\');
            try writer.writeByte(code);
        } else if (byte >= 0x20 and byte < 0x7f) {
            try writer.writeByte(byte);
        } else try writer.print("\\x{x:0>2}", .{byte});
    }
    try writer.writeByte('\'');
}

fn aggregate(writer: *std.Io.Writer, records: []const typed.Record, record: *runtime.Aggregate, depth: usize) Error!void {
    if (!record.ty.isAggregate() or record.ty.recordIndex() >= records.len) return error.Unprintable;
    const schema = records[record.ty.recordIndex()];
    if (schema.contract.callback != null or schema.shape.resource != null) return error.Unprintable;
    if (numeric_surface.isFloat(record.ty, records)) return float(writer, record);
    if (schema.shape.variants) |variants| return variant(writer, records, .{ .record = record, .variants = variants }, depth);
    if (schema.shape.array != null) {
        try writer.writeByte('[');
        for (record.fields, 0..) |field, index| {
            if (index != 0) try writer.writeAll(", ");
            try render(writer, records, field, depth + 1);
        }
        return writer.writeByte(']');
    }
    if (schema.shape.domain != null) {
        try writer.print("{s}(", .{shortName(schema.name)});
        try render(writer, records, record.fields[0], depth + 1);
        return writer.writeByte(')');
    }
    try writer.print("{s}(", .{shortName(schema.name)});
    for (schema.fields, record.fields, 0..) |declared, field, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s}=", .{declared.name});
        if (record.moved_fields) |moved| if (moved[index]) {
            try writer.writeAll("<moved>");
            continue;
        };
        try render(writer, records, field, depth + 1);
    }
    try writer.writeByte(')');
}

/// Borrowed variant operands; the aggregate outlives this rendering call.
const VariantValue = struct { record: *runtime.Aggregate, variants: typed.Variants };

fn variant(writer: *std.Io.Writer, records: []const typed.Record, input: VariantValue, depth: usize) Error!void {
    const tag = input.record.active_tag orelse return error.Unprintable;
    if (tag >= input.variants.cases.len) return error.Unprintable;
    const case = input.variants.cases[tag];
    const owner = shortName(records[input.record.ty.recordIndex()].name);
    if (case.payload == null) {
        if (input.variants.fallible or std.mem.eql(u8, case.name, "none")) return writer.writeAll(caseSpelling(case.name));
        return writer.print("{s}.{s}", .{ owner, case.name });
    }
    if (input.variants.fallible or std.mem.eql(u8, case.name, "some")) {
        try writer.print("{s}(", .{caseSpelling(case.name)});
    } else try writer.print("{s}.{s}(", .{ owner, case.name });
    if (input.record.fields.len != 0) try render(writer, records, input.record.fields[0], depth + 1);
    try writer.writeByte(')');
}

fn float(writer: *std.Io.Writer, record: *runtime.Aggregate) Error!void {
    if (record.fields.len != 1) return error.Unprintable;
    const raw = record.fields[0].asInteger() catch return error.Unprintable;
    const number: f64 = @bitCast(@as(u64, @intCast(raw)));
    if (std.math.isNan(number)) return writer.writeAll("nan");
    if (std.math.isInf(number)) return writer.writeAll(if (number < 0) "-inf" else "inf");
    var buffer: [64]u8 = undefined;
    const rendered = std.fmt.bufPrint(&buffer, "{d}", .{number}) catch return error.Unprintable;
    try writer.writeAll(rendered);
    if (std.mem.indexOfAny(u8, rendered, ".eEn") == null) try writer.writeAll(".0");
}
