//! Close a unit's descriptor graph, then replace ephemeral type IDs by local IDs.
const std = @import("std");
const ir = @import("ir.zig");
const values = @import("emit_values.zig");
const Out = std.ArrayList(u8);
const render_prefix = "myl.render.";
const value_prefix = "myl.value.";

/// Invalid generated metadata or an allocation stops emission.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

/// One immutable index of the program's descriptor definitions; maps are lookup-only.
pub const Catalog = struct {
    globals: std.StringHashMapUnmanaged([]const u8) = .empty,
    prelude: []const u8 = "",

    /// Render descriptors once, retaining definitions by their generated LLVM symbol.
    pub fn init(a: std.mem.Allocator, module: *const ir.Module) Error!Catalog {
        var text: Out = .empty;
        errdefer text.deinit(a);
        try values.descriptors(a, module, &text);
        var result: Catalog = .{};
        errdefer result.globals.deinit(a);
        var header: Out = .empty;
        errdefer header.deinit(a);
        var lines = std.mem.splitScalar(u8, text.items, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            if (line[0] != '@') {
                try header.appendSlice(a, line);
                try header.append(a, '\n');
                continue;
            }
            var refs: Symbols = .{ .text = line };
            const name = refs.next() orelse return error.UnsupportedInstruction;
            try result.globals.put(a, name, line);
        }
        result.prelude = header.items;
        return result;
    }

    /// Append precisely the reached descriptor closure, in first-use order, and localize IDs.
    pub fn finish(self: *const Catalog, a: std.mem.Allocator, body: []const u8) Error![]u8 {
        var pending: std.ArrayList([]const u8) = .empty;
        var seen: std.StringHashMapUnmanaged(void) = .empty;
        try self.references(a, body, &pending, &seen);
        var out: Out = .empty;
        var names: Names = .{};
        // Normalize while appending the closure. Do not build and retain a
        // second complete module just to replace its descriptor symbols.
        try normalize(a, &names, &out, body);
        if (pending.items.len != 0) try normalize(a, &names, &out, self.prelude);
        var index: usize = 0;
        var number = false;
        while (index < pending.items.len) : (index += 1) {
            const definition = self.globals.get(pending.items[index]) orelse return error.UnsupportedInstruction;
            try normalize(a, &names, &out, definition);
            try out.append(a, '\n');
            // Source rendering of a float reaches the separately linked Zig formatter.
            // Its lowering declaration is not a source call, so carry it with this graph.
            if (std.mem.startsWith(u8, definition, "@myl.render.") and
                std.mem.indexOf(u8, definition, "= private constant %myl.value { i32 2,") != null) number = true;
            try self.references(a, definition, &pending, &seen);
        }
        if (number and std.mem.indexOf(u8, body, "@myl_core_str_from_f64(") == null)
            try out.appendSlice(a, "declare ptr @myl_core_str_from_f64(double) nounwind\n");
        return out.toOwnedSlice(a);
    }

    fn references(self: *const Catalog, a: std.mem.Allocator, text: []const u8, pending: *std.ArrayList([]const u8), seen: *std.StringHashMapUnmanaged(void)) Error!void {
        var refs: Symbols = .{ .text = text };
        while (refs.next()) |name| {
            if (!descriptor(name)) continue;
            if (!self.globals.contains(name)) return error.UnsupportedInstruction;
            const entry = try seen.getOrPut(a, name);
            if (!entry.found_existing) try pending.append(a, name);
        }
    }
};

fn descriptor(name: []const u8) bool {
    return std.mem.startsWith(u8, name, value_prefix) or std.mem.startsWith(u8, name, render_prefix);
}

/// LLVM symbol tokens, excluding quoted data and metadata strings.
pub const Symbols = struct {
    text: []const u8,
    cursor: usize = 0,
    start: usize = 0,
    end: usize = 0,

    /// Read the next global symbol without its leading at-sign.
    pub fn next(self: *Symbols) ?[]const u8 {
        while (self.cursor < self.text.len) {
            const at = self.cursor;
            self.cursor += 1;
            if (self.text[at] == '"') {
                self.quoted();
                continue;
            }
            if (self.text[at] != '@' or self.cursor == self.text.len) continue;
            self.start = at;
            if (self.text[self.cursor] == '"') {
                self.cursor += 1;
                self.quoted();
            } else {
                while (self.cursor < self.text.len and symbolByte(self.text[self.cursor])) self.cursor += 1;
            }
            self.end = self.cursor;
            return self.text[at + 1 .. self.cursor];
        }
        return null;
    }

    fn quoted(self: *Symbols) void {
        while (self.cursor < self.text.len) {
            const byte = self.text[self.cursor];
            self.cursor += 1;
            if (byte == '"') return;
            if (byte == '\\' and self.cursor < self.text.len) self.cursor += 1;
        }
    }
};

fn symbolByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.' or byte == '$' or byte == '-';
}

const Names = struct {
    values: std.StringHashMapUnmanaged(u32) = .empty,
    renders: std.StringHashMapUnmanaged(u32) = .empty,

    fn write(self: *Names, a: std.mem.Allocator, out: *Out, original: []const u8) Error!void {
        const render = std.mem.startsWith(u8, original, render_prefix);
        const prefix = if (render) render_prefix else value_prefix;
        var suffix = original[prefix.len..];
        var part: []const u8 = "";
        for ([_][]const u8{ "children.", "offsets.", "names.", "name." }) |candidate| {
            if (!std.mem.startsWith(u8, suffix, candidate)) continue;
            part = candidate;
            suffix = suffix[candidate.len..];
            break;
        }
        const end = std.mem.indexOfScalar(u8, suffix, '.') orelse suffix.len;
        const id = suffix[0..end];
        const table = if (render) &self.renders else &self.values;
        const entry = try table.getOrPut(a, id);
        if (!entry.found_existing) entry.value_ptr.* = @intCast(table.count() - 1);
        try out.print(a, "{s}{s}{d}{s}", .{ prefix, part, entry.value_ptr.*, suffix[end..] });
    }
};

fn normalize(a: std.mem.Allocator, names: *Names, out: *Out, text: []const u8) Error!void {
    var refs: Symbols = .{ .text = text };
    var copied: usize = 0;
    while (refs.next()) |name| {
        if (!descriptor(name)) continue;
        try out.appendSlice(a, text[copied .. refs.start + 1]);
        try names.write(a, out, name);
        copied = refs.end;
    }
    try out.appendSlice(a, text[copied..]);
}
