//! Which types may key a dictionary or be the element of a set (HASH-KEYS-1).
//!
//! A key is hashed and compared by value, structurally and deterministically,
//! so it must be a value whose contents cannot change once stored and whose
//! equality is reflexive: every integer kind, `bool`, `str`, `bytes`, and the
//! value types built only from those — tuples, records, unions, enums, domains,
//! `Option` and fixed arrays. `float` is refused because NaN is not equal to
//! itself; a managed collection, `byte_buffer` or `class` because it is a
//! shared, mutable reference; a function value because it has no equality; a
//! capability, file or resource because it is not a value at all.
const std = @import("std");
const typed = @import("typed.zig");
const numeric_surface = @import("numeric_surface.zig");
const diagnostic = @import("diagnostic.zig");
const Span = @import("source.zig").Span;

/// Diagnostic code for a dictionary key type that cannot be hashed.
pub const dictionary_code = "E_DICT_KEY";
/// Diagnostic code for a set element type that cannot be hashed.
pub const set_code = "E_SET_ELEMENT";

/// Report `key` at `span` when it cannot key a dictionary (or, with `set`, be
/// a set element), naming the offending part.
pub fn require(allocator: std.mem.Allocator, records: []const typed.Record, sink: *diagnostic.Sink, key: typed.Type, span: Span, set: bool) diagnostic.Error!void {
    const found = (try refusal(allocator, records, key)) orelse return;
    return sink.fail(if (set) set_code else dictionary_code, span, try message(allocator, records, key, found, set));
}

/// Why one part of a key type cannot be hashed.
pub const Reason = enum { float, shared, callable, capability };

/// The first part of a key type that cannot be hashed: the path from the key
/// type down to it (`.field`, `[index]` for a tuple or array element, `.case`
/// for a union payload; empty when the key type itself is refused), the part's
/// own type and why it is refused.
pub const Refusal = struct { path: []const u8, part: typed.Type, reason: Reason };

/// The first unhashable part of `ty`, or null when `ty` can key a dictionary.
/// Fields are visited in declaration order and union cases in case order, so
/// one type always reports the same part.
pub fn refusal(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type) std.mem.Allocator.Error!?Refusal {
    var path: std.ArrayList(u8) = .empty;
    defer path.deinit(allocator);
    var seen: Seen = .empty;
    defer seen.deinit(allocator);
    return walk(allocator, records, ty, &path, &seen, 0);
}

/// The diagnostic text for a refused key type: which role it plays, the path
/// to the offending part, that part's type and the reason, with the
/// alternative a program can reach for.
pub fn message(allocator: std.mem.Allocator, records: []const typed.Record, key: typed.Type, found: Refusal, set: bool) std.mem.Allocator.Error![]const u8 {
    const key_name = try typed.surfaceTypeName(allocator, key, records);
    const part_name = try typed.surfaceTypeName(allocator, found.part, records);
    const role = if (set) "a set element" else "a dictionary key";
    const reason = switch (found.reason) {
        .float => "a float is not hashable because NaN is not equal to itself; use an integer or str instead",
        .shared => "a list, dict, set, byte_buffer or class value is a shared reference whose contents can change after it is stored; use a record, tuple, str or bytes instead",
        .callable => "a function value has no equality",
        .capability => "a capability, file or resource is not a value",
    };
    if (found.path.len == 0) return std.fmt.allocPrint(allocator, "`{s}` cannot be {s}: {s}", .{ key_name, role, reason });
    return std.fmt.allocPrint(allocator, "`{s}` cannot be {s}: `{s}{s}` is `{s}`, and {s}", .{ key_name, role, key_name, found.path, part_name, reason });
}

/// Value types already walked. A recursive value type (RECURSIVE-VALUES-2)
/// reaches itself again through a boxed field; the walk that got there first
/// already checks every part, so a repeat has nothing new to refuse.
const Seen = std.AutoHashMapUnmanaged(typed.Type, void);

fn walk(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type, path: *std.ArrayList(u8), seen: *Seen, depth: usize) std.mem.Allocator.Error!?Refusal {
    if (ty.isInteger() or ty == .bool or ty == .unit) return null;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return refuse(allocator, path, ty, .capability);
    const record = records[ty.recordIndex()];
    if (numeric_surface.isFloat(ty, records)) return refuse(allocator, path, ty, .float);
    if (record.contract.callback != null) return refuse(allocator, path, ty, .callable);
    if (record.shape.resource != null) return refuse(allocator, path, ty, .capability);
    if (record.managed) {
        if (record.collection.kind == .string or typed.isByteString(record)) return null;
        return refuse(allocator, path, ty, .shared);
    }
    if (record.isEnum()) return null;
    if ((try seen.getOrPut(allocator, ty)).found_existing) return null;
    // A value type nests only value types, so its depth is bounded by the
    // declarations; the bound here only guards a malformed catalog.
    if (depth == 64) return refuse(allocator, path, ty, .shared);
    if (record.shape.domain) |backing| return walk(allocator, records, backing, path, seen, depth + 1);
    const mark = path.items.len;
    if (record.shape.array) |array| {
        try path.appendSlice(allocator, "[]");
        if (try walk(allocator, records, array.element, path, seen, depth + 1)) |found| return found;
        path.shrinkRetainingCapacity(mark);
        return null;
    }
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| {
            try path.print(allocator, ".{s}", .{case.name});
            if (try walk(allocator, records, payload, path, seen, depth + 1)) |found| return found;
            path.shrinkRetainingCapacity(mark);
        };
        return null;
    }
    for (record.fields, 0..) |field, index| {
        if (record.shape.tuple) try path.print(allocator, "[{d}]", .{index}) else try path.print(allocator, ".{s}", .{field.name});
        if (try walk(allocator, records, field.ty, path, seen, depth + 1)) |found| return found;
        path.shrinkRetainingCapacity(mark);
    }
    return null;
}

fn refuse(allocator: std.mem.Allocator, path: *std.ArrayList(u8), part: typed.Type, reason: Reason) std.mem.Allocator.Error!?Refusal {
    const copied = try allocator.dupe(u8, path.items);
    return .{ .path = copied, .part = part, .reason = reason };
}
