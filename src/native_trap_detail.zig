//! Shared structured native trap detail.
//!
//! A native child appends one bounded record `\x1eMYLANG-TRAP ` + JSON + `\n`
//! to stderr after its human-readable trap diagnostic. This module is the single
//! host-side representation: text and JSON are both rendered from `Detail`, so
//! neither path extracts numbers from the human message.
const std = @import("std");

/// Stderr marker beginning the one-line machine record.
pub const marker = "\x1eMYLANG-TRAP ";

/// Present bit for the original index.
pub const present_index: u32 = 1;
/// Present bit for the receiver length.
pub const present_length: u32 = 2;
/// Present bit for the left arithmetic operand.
pub const present_left: u32 = 4;
/// Present bit for the right arithmetic operand.
pub const present_right: u32 = 8;
/// Present bit for the element or integer width.
pub const present_width: u32 = 16;

/// Allocation failures while copying a cleaned diagnostic.
pub const StripError = std.mem.Allocator.Error;
/// Writer failures while rendering a text suffix.
pub const TextError = std.Io.Writer.Error;

/// The bounded operation names `qbe_runtime.c` emits. Unknown names degrade to
/// `operation` rather than inventing a new encoding.
pub const Operation = enum {
    index,
    pop,
    add,
    sub,
    mul,
    div,
    rem,
    floor_div,
    floor_rem,
    neg,
    cast,
    arithmetic,
    operation,

    /// Stable transport spelling.
    pub fn name(self: Operation) []const u8 {
        return @tagName(self);
    }
};

/// Captured numeric values; zero unless the matching present bit is set.
pub const Values = struct {
    index: i64 = 0,
    length: u64 = 0,
    left: i64 = 0,
    right: i64 = 0,
    width: u64 = 0,
};

/// Versioned bounded trap detail. Absent fields are zero and gated by `present`.
pub const Detail = struct {
    version: u32 = 0,
    present: u32 = 0,
    operation: Operation = .operation,
    values: Values = .{},

    /// Whether one present bit was captured.
    pub fn has(self: Detail, bit: u32) bool {
        return self.present & bit != 0;
    }

    /// Map a bounded operation name to the known set.
    pub fn operationFromName(name: []const u8) Operation {
        return std.meta.stringToEnum(Operation, name) orelse .operation;
    }

    /// Render the bounded suffix appended to the human trap message. The exact
    /// shape matches `detail_text` in `qbe_runtime.c` so both renderers quote
    /// the same values.
    pub fn writeText(self: Detail, writer: *std.Io.Writer) TextError!void {
        if (self.version == 0) return;
        const values = self.values;
        if (self.has(present_index)) {
            try writer.print(" (index {d}", .{values.index});
            if (self.has(present_length)) try writer.print(", length {d}", .{values.length});
            try writer.writeAll(")");
        } else if (self.has(present_length)) {
            try writer.print(" (length {d})", .{values.length});
        } else if (self.present & (present_left | present_right | present_width) != 0) {
            try writer.print(" ({s}:", .{self.operation.name()});
            if (self.has(present_left)) try writer.print(" left {d}", .{values.left});
            if (self.has(present_right)) try writer.print(", right {d}", .{values.right});
            if (self.has(present_width)) try writer.print(", width {d}", .{values.width});
            try writer.writeAll(")");
        }
    }
};

/// JSON shape emitted by `qbe_runtime.c`; only present numeric fields appear.
const Transport = struct {
    version: ?u32 = null,
    operation: ?[]const u8 = null,
    index: ?i64 = null,
    length: ?u64 = null,
    left: ?i64 = null,
    right: ?i64 = null,
    width: ?u64 = null,
};

/// The JSON body of the first record line, or null when the text carries none.
pub fn recordBody(text: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, text, marker) orelse return null;
    const from = start + marker.len;
    const end = std.mem.indexOfScalarPos(u8, text, from, '\n') orelse text.len;
    return text[from..end];
}

/// Parse the bounded transport record. A missing or malformed record yields
/// null so a host that sees no record behaves exactly as before.
pub fn parse(allocator: std.mem.Allocator, text: []const u8) ?Detail {
    const body = recordBody(text) orelse return null;
    var parsed = std.json.parseFromSlice(Transport, allocator, body, .{ .ignore_unknown_fields = true }) catch return null;
    defer parsed.deinit();
    const value = parsed.value;
    const version = value.version orelse return null;
    var detail = Detail{ .version = version, .operation = std.meta.stringToEnum(Operation, value.operation orelse "") orelse .operation };
    if (value.index) |index| {
        detail.present |= present_index;
        detail.values.index = index;
    }
    if (value.length) |length| {
        detail.present |= present_length;
        detail.values.length = length;
    }
    if (value.left) |left| {
        detail.present |= present_left;
        detail.values.left = left;
    }
    if (value.right) |right| {
        detail.present |= present_right;
        detail.values.right = right;
    }
    if (value.width) |width| {
        detail.present |= present_width;
        detail.values.width = width;
    }
    return detail;
}

/// Remove record lines from captured stderr, preserving every ordinary
/// diagnostic byte and line order. The returned slice is allocator-owned.
pub fn strip(allocator: std.mem.Allocator, text: []const u8) StripError![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var start: usize = 0;
    while (start < text.len) {
        const end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        const line = text[start..end];
        if (!std.mem.startsWith(u8, line, marker)) {
            try output.appendSlice(allocator, line);
            if (end < text.len) try output.append(allocator, '\n');
        }
        start = if (end < text.len) end + 1 else text.len;
    }
    return output.toOwnedSlice(allocator);
}

test "trap records parse into bounded detail and strip without touching other lines" {
    const captured = "main.my:2:12: error[R_LIST_BOUNDS]: native execution failed (index 14, length 1)\n" ++
        "  in at at main.my:2:12\n" ++
        marker ++ "{\"version\":1,\"operation\":\"index\",\"index\":14,\"length\":1}\n";
    const detail = parse(std.testing.allocator, captured).?;
    try std.testing.expectEqual(@as(u32, 1), detail.version);
    try std.testing.expectEqual(Operation.index, detail.operation);
    try std.testing.expectEqual(@as(i64, 14), detail.values.index);
    try std.testing.expectEqual(@as(u64, 1), detail.values.length);
    try std.testing.expect(detail.has(present_index) and detail.has(present_length));
    const cleaned = try strip(std.testing.allocator, captured);
    defer std.testing.allocator.free(cleaned);
    try std.testing.expectEqualStrings("main.my:2:12: error[R_LIST_BOUNDS]: native execution failed (index 14, length 1)\n  in at at main.my:2:12\n", cleaned);
    try std.testing.expectEqual(@as(?Detail, null), parse(std.testing.allocator, "plain diagnostic\n"));
}

test "trap detail text renders the same values as the structured fields" {
    var buffer: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buffer.deinit();
    const detail = Detail{ .version = 1, .present = present_index | present_length, .operation = .index, .values = .{ .index = -3, .length = 5 } };
    try detail.writeText(&buffer.writer);
    try std.testing.expectEqualStrings(" (index -3, length 5)", buffer.written());
}
