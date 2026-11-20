//! The words of an ownership refusal (`E_CORE_UNSUPPORTED`, rule Z3): the operation the scheduler could not place, the
//! function it is in, and, when the pass named one, the other place it conflicts with and a sentence saying how. The
//! other place is shown as the source text at its span (a path such as `ctx.block.rules`), cut to the depth of the
//! value the pass saw, and as a note with its line.
const std = @import("std");
const language = @import("selka");
const own = @import("own.zig");

/// The message of an ownership refusal: what could not be scheduled, where, and how it conflicts with the other place.
pub fn message(allocator: std.mem.Allocator, src: language.source.Source, refusal: own.Refusal) std.mem.Allocator.Error![]const u8 {
    const function = if (refusal.function.len == 0) "an unnamed function" else refusal.function;
    const inlined = if (refusal.conflict.caller.len == 0) "" else try std.fmt.allocPrint(allocator, " (inlined into {s})", .{refusal.conflict.caller});
    const conflict = try sentence(allocator, src, refusal);
    return std.fmt.allocPrint(allocator, "the ownership pass cannot schedule {s} in {s}{s}{s}{s}; this shape has no safe destruction schedule", .{
        scheduleWhat(refusal), function, inlined, if (conflict.len == 0) "" else ": ", conflict,
    });
}

/// The note that points at the other place, or null when the refusal names none.
pub fn note(allocator: std.mem.Allocator, src: language.source.Source, refusal: own.Refusal) std.mem.Allocator.Error!?language.diagnostic.Related {
    if (refusal.conflict.kind == .none or refusal.conflict.place == 0) return null;
    const text = place(src, refusal.conflict.place, refusal.conflict.depth);
    const words: []const u8 = switch (refusal.conflict.kind) {
        .none => unreachable,
        .takes_borrowed => try std.fmt.allocPrint(allocator, "`{s}` is read here as a borrow of `{s}`", .{ text, owner(text) }),
        .takes_live => try std.fmt.allocPrint(allocator, "`{s}` still reads the value here", .{text}),
        .takes_and_borrows, .takes_twice, .edge_live => try std.fmt.allocPrint(allocator, "`{s}` is read here", .{text}),
        .lent_unjoined => try std.fmt.allocPrint(allocator, "`{s}` is lent to the task here", .{text}),
        .return_undeclared => try std.fmt.allocPrint(allocator, "`{s}` is read here", .{text}),
    };
    const at = refusal.conflict.place;
    return .{ .span = .{ .start = at, .end = at }, .message = words };
}

/// What an ownership refusal could not schedule, phrased as a noun phrase: the
/// operation when the pass named one (a store for any field, element or entry
/// write), and "the value's owner" otherwise.
pub fn scheduleWhat(refusal: own.Refusal) []const u8 {
    const operation = refusal.operation;
    if (operation.len == 0) return "the value's owner";
    for ([_][]const u8{ "record_set", "list_set", "dict_set", "box_set", "elem_set", "store" }) |store| {
        if (std.mem.eql(u8, operation, store)) return "a store";
    }
    if (std.mem.eql(u8, operation, "ret")) return "a return";
    if (std.mem.eql(u8, operation, "call")) return "a call";
    return operation;
}

fn sentence(allocator: std.mem.Allocator, src: language.source.Source, refusal: own.Refusal) std.mem.Allocator.Error![]const u8 {
    const conflict = refusal.conflict;
    if (conflict.kind == .none) return "";
    const text = place(src, conflict.place, conflict.depth);
    // A place with no source position is named without a line.
    if (conflict.place == 0) return switch (conflict.kind) {
        .none => "",
        .takes_borrowed => "it takes ownership of a value that is a borrowed part of another at that point, not an owner",
        .takes_live => "it takes ownership of a value that is still read afterwards",
        .takes_and_borrows => "it takes ownership of a value while the same operation also borrows it",
        .takes_twice => "it takes ownership of one value twice",
        .edge_live => "a branch hands on a value while the code it branches to still reads it",
        .lent_unjoined => "a value is lent to a task that no join of its group waits for",
        .return_undeclared => "it returns a borrow that no source in the `from` clause owns",
    };
    const line = src.locate(conflict.place).line;
    return switch (conflict.kind) {
        .none => "",
        .takes_borrowed => std.fmt.allocPrint(allocator, "it takes ownership of `{s}` (line {d}), which is a borrowed part of `{s}` at that point, not an owner", .{ text, line, owner(text) }),
        .takes_live => std.fmt.allocPrint(allocator, "it takes ownership of a value that `{s}` still reads afterwards (line {d})", .{ text, line }),
        .takes_and_borrows => std.fmt.allocPrint(allocator, "it takes ownership of `{s}` (line {d}) while the same operation also borrows it", .{ text, line }),
        .takes_twice => std.fmt.allocPrint(allocator, "it takes ownership of `{s}` (line {d}) twice", .{ text, line }),
        .edge_live => std.fmt.allocPrint(allocator, "a branch hands on `{s}` (line {d}) while the code it branches to still reads it", .{ text, line }),
        .lent_unjoined => std.fmt.allocPrint(allocator, "`{s}` (line {d}) is lent to a task that no join of its group waits for", .{ text, line }),
        .return_undeclared => std.fmt.allocPrint(allocator, "it returns a borrow of `{s}` (line {d}), which no source in the `from` clause owns", .{ text, line }),
    };
}

/// The source text of the place at `span`: a dotted or indexed path, without a leading `mut` or `own`, cut to `depth`
/// field steps below its first name when the source spells a deeper path (the pass saw a shallower part). "the value"
/// when the span holds no path.
pub fn place(src: language.source.Source, span: u32, depth: u32) []const u8 {
    if (span == 0 or span >= src.bytes.len) return "the value";
    var rest = src.bytes[span..];
    for ([_][]const u8{ "mut ", "own " }) |marker| {
        if (std.mem.startsWith(u8, rest, marker)) rest = rest[marker.len..];
    }
    var end: usize = 0;
    var brackets: usize = 0;
    var steps: u32 = 0;
    while (end < rest.len and end < 80) : (end += 1) {
        const c = rest[end];
        if (c == '[') {
            if (brackets == 0) {
                if (depth != 0 and steps == depth) break;
                steps += 1;
            }
            brackets += 1;
        } else if (c == ']') {
            if (brackets == 0) break;
            brackets -= 1;
        } else if (c == '.' and brackets == 0) {
            if (depth != 0 and steps == depth) break;
            steps += 1;
        } else if (brackets == 0 and !(std.ascii.isAlphanumeric(c) or c == '_')) break;
    }
    while (end > 0 and (rest[end - 1] == '.' or rest[end - 1] == '[')) end -= 1;
    if (end == 0) return "the value";
    return rest[0..end];
}

/// The first name of a place path: the owner `ctx` of `ctx.block.rules`.
pub fn owner(path: []const u8) []const u8 {
    const end = std.mem.indexOfAny(u8, path, ".[") orelse return path;
    return path[0..end];
}
