//! The plain JSON form of a checked type (decisions CODEC-1 and CODEC-2, step 1): the `codec` bound means "has this
//! form", and `json.encode` and `json.decode` derive it. A type has one when everything it holds has one: every integer
//! width, `bool`, `float`, `f32`, `str`, records, enums (with or without case fields), options, lists and fixed arrays,
//! recursion through a list included (a value nests at most 1000 arrays and objects deep, `runtime/core_json.c`). A function, a capability, a resource, a class, a boxed (recursive) field
//! and anything else with no value form has none; a dictionary, a set, `bytes`, a tuple and a `json.Json` part have none
//! until step 2 builds them. `find` names the field path of the first part without a form, for the check-time refusal
//! (`E_NO_CODEC`). The Core derivation is `src/core/build_json.zig`.
const std = @import("std");
const typed = @import("typed.zig");

/// The code of a call of `json.encode` or `json.decode` (or any `codec` bound) with a type that has no plain form.
pub const code = "E_NO_CODEC";

/// One part of a type that has no plain form: its path from the type asked about (`tracker.tasks[].handle`, empty for
/// the type itself), its type, and whether it is one step 2 will build.
pub const Missing = struct { path: []const u8, part: typed.Type, later: bool };

/// What one type is, for the plain form, before its parts are looked at.
pub const Kind = enum { integer, boolean, float, text, record, variants, list, fixed_array, none, later };

/// The kind of `ty` alone.
pub fn kind(ty: typed.Type, records: []const typed.Record) Kind {
    if (ty.isInteger()) return .integer;
    if (ty == .bool) return .boolean;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return .none;
    const record = records[ty.recordIndex()];
    if (record.contract.move_only or record.contract.callback != null or record.shape.resource != null) return .none;
    if (record.shape.domain != null) {
        return if (std.mem.eql(u8, record.name, "float") or std.mem.eql(u8, record.name, "f32")) .float else .none;
    }
    if (record.isCollection()) return switch (record.collection.kind) {
        .string => .text,
        .list => if (record.collection.contains_cell or record.collection.box) .none else .list,
        .dictionary, .bytes => .later,
    };
    if (record.shape.buffer != null) return .none;
    if (record.shape.variants != null) return if (isJsonValue(record)) .later else .variants;
    if (record.shape.array) |array| return if (array.key != null or array.vector) .none else .fixed_array;
    if (record.managed or record.shape.builtin != .none) return .none;
    if (record.shape.tuple) return .later;
    return .record;
}

/// Whether `record` is the standard library's untyped `json.Json`, which step 2 lets a record hold.
fn isJsonValue(record: typed.Record) bool {
    return std.mem.eql(u8, record.name, "json::Json");
}

/// Whether `ty` and everything it holds have a plain form.
pub fn supports(ty: typed.Type, records: []const typed.Record) bool {
    var walk: Walk = .{ .records = records };
    return walk.firstMissing(null, ty) == null;
}

/// The first part of `ty` that has no plain form, with its path, or null when the whole type has one.
pub fn find(allocator: std.mem.Allocator, ty: typed.Type, records: []const typed.Record) std.mem.Allocator.Error!?Missing {
    var path: std.ArrayList(u8) = .empty;
    var walk: Walk = .{ .records = records };
    const found = walk.firstMissing(&.{ .allocator = allocator, .text = &path }, ty) orelse return null;
    if (path.items.len != 0 and path.items[0] == '.') _ = path.orderedRemove(0);
    return .{ .path = try path.toOwnedSlice(allocator), .part = found.part, .later = found.later };
}

/// The path text being built, when a caller wants one.
const Path = struct { allocator: std.mem.Allocator, text: *std.ArrayList(u8) };

const Found = struct { part: typed.Type, later: bool };

/// The state of one walk: the types being walked (a type met again inside itself, through a list, is checked where it
/// first appears) and a bound on the work.
const Walk = struct {
    records: []const typed.Record,
    active: [256]typed.Type = undefined,
    depth: usize = 0,
    work: usize = 65536,

    /// Walk `ty` depth first; on the way back from a part without a form, prepend each step to the path.
    fn firstMissing(self: *Walk, path: ?*const Path, ty: typed.Type) ?Found {
        if (self.work == 0 or self.depth == self.active.len) return .{ .part = ty, .later = false };
        self.work -= 1;
        for (self.active[0..self.depth]) |outer| if (outer == ty) return null;
        self.active[self.depth] = ty;
        self.depth += 1;
        defer self.depth -= 1;
        const records = self.records;
        switch (kind(ty, records)) {
            .integer, .boolean, .float, .text => return null,
            .none => return .{ .part = ty, .later = false },
            .later => return .{ .part = ty, .later = true },
            .list => return step(path, "[]", self.firstMissing(path, records[ty.recordIndex()].shape.buffer.?)),
            .fixed_array => return step(path, "[]", self.firstMissing(path, records[ty.recordIndex()].shape.array.?.element)),
            .variants => {
                const record = records[ty.recordIndex()];
                const option = typed.surfaceOptionalPayload(record) != null;
                for (record.shape.variants.?.cases) |case| {
                    if (case.boxed) return step(path, if (option) "" else case.name, .{ .part = ty, .later = false });
                    const payload = case.payload orelse continue;
                    // An option inside an option has no plain form: `null` could be either.
                    if (option and kind(payload, records) == .variants and typed.surfaceOptionalPayload(records[payload.recordIndex()]) != null)
                        return .{ .part = ty, .later = false };
                    if (self.firstMissing(path, payload)) |found| return step(path, if (option) "" else case.name, found);
                }
                return null;
            },
            .record => {
                for (records[ty.recordIndex()].fields) |field| {
                    if (field.boxed) return step(path, field.name, .{ .part = field.ty, .later = false });
                    if (self.firstMissing(path, field.ty)) |found| return step(path, field.name, found);
                }
                return null;
            },
        }
    }
};

/// Prepend one step (`.name` or `[]`) to the path of a part found below it.
fn step(path: ?*const Path, name: []const u8, found: ?Found) ?Found {
    const result = found orelse return null;
    const p = path orelse return result;
    if (name.len == 0) return result;
    const text = if (std.mem.eql(u8, name, "[]")) name else blk: {
        const dotted = p.allocator.alloc(u8, name.len + 1) catch return result;
        dotted[0] = '.';
        @memcpy(dotted[1..], name);
        break :blk dotted;
    };
    p.text.insertSlice(p.allocator, 0, text) catch return result;
    return result;
}

/// The refusal of a type argument without a plain form: the part and its path, and for a step-2 type that it is not
/// built yet.
pub fn message(allocator: std.mem.Allocator, argument: []const u8, missing: Missing, part: []const u8) std.mem.Allocator.Error![]const u8 {
    const where = if (missing.path.len == 0)
        try std.fmt.allocPrint(allocator, "`{s}` has no plain JSON form", .{argument})
    else
        try std.fmt.allocPrint(allocator, "`{s}` has no plain JSON form: its part `{s}` is a `{s}`", .{ argument, missing.path, part });
    if (missing.later) return std.fmt.allocPrint(allocator, "{s}, and the plain form of a dictionary, a set, `bytes`, a tuple or a `json.Json` part is not built yet", .{where});
    return std.fmt.allocPrint(allocator, "{s}, which no JSON can hold (a function, a capability, a resource, a class or a recursive field); leave it out of the type you encode or decode", .{where});
}

/// The message refusing `ty` as the type argument of a `codec` bound, or null when it has a plain form.
pub fn refusal(allocator: std.mem.Allocator, ty: typed.Type, records: []const typed.Record) std.mem.Allocator.Error!?[]const u8 {
    if (supports(ty, records)) return null;
    const missing = try find(allocator, ty, records) orelse return null;
    const display = @import("display_name.zig");
    const argument = try display.spelled(allocator, typed.typeName(ty, records));
    const part = try display.spelled(allocator, typed.typeName(missing.part, records));
    const text = try message(allocator, argument, missing, part);
    return text;
}
