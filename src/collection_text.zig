//! `str(x)` and `repr(x)` of a list, a set, a dictionary, an option, a record, a result or a fixed array (F-38,
//! D-F38-1 and the user's decision of 14 November 2026, F-38b): which types take them, and the refusal of every type that
//! does not.
//!
//! The text is the one `print` writes. `str` and `repr` do not format anything themselves: the checker types the call
//! as a `cast` to `str`, and Core lowers that exactly as it lowers a `print` argument and a format string's hole, through
//! `FnBuilder.textOf` and the descriptor-driven renderer `myl_core_values_render` (`src/core/build_render.zig`,
//! `src/core/runtime/core_values.c`). So the three spellings cannot drift, and this file decides only what is accepted.
//!
//! A value is accepted when it and everything inside it has a text: integers, `bool`, `float`, `str`, `bytes`, records,
//! enums, unions, options, results, fixed arrays and collections do; capabilities, open files, owned resources, callbacks
//! and `extern type` handles do not. A top-level enum, union or `bytes` keeps its refusal (an enum's bare name is
//! `case_name`, and `PY-BYTES-1` keeps `str(bytes)` refused): `str(Kind.alpha)` is refused and says `case_name(value)`,
//! and `str(b"ab")` is refused and says `repr(value)`.
const std = @import("std");
const typed = @import("typed.zig");
const io_render = @import("io_render.zig");

/// The kinds of value `str` and `repr` take on their own, whatever their parts are: the four collections of F-38 and the
/// record, result and fixed array a collection already showed as a part (F-38b).
pub const Kind = enum { list, set, dictionary, option, record, result, fixed_array };

/// What the rule says of one type.
pub const Verdict = union(enum) {
    /// One of the kinds above, and every part of it has a text.
    accepted,
    /// Not one of those kinds (a scalar, an enum or a union, `bytes`, a domain); the type keeps its own refusal.
    other,
    /// One of the kinds above, with a part that has no text: the type of that part.
    part_without_text: typed.Type,
};

/// Which kind `ty` is, or null for any other type. A plain record is any record with no variants, array, domain or buffer;
/// a table (an array indexed by an enum) and a SIMD vector are not fixed arrays here and keep their refusal.
pub fn kind(ty: typed.Type, records: []const typed.Record) ?Kind {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const record = records[ty.recordIndex()];
    if (record.shape.variants) |variants| {
        if (typed.surfaceOptionalPayload(record) != null) return .option;
        return if (variants.fallible) .result else null;
    }
    if (record.shape.array) |array| return if (array.key == null and !array.vector) .fixed_array else null;
    if (record.isRecord()) return .record;
    if (!record.isCollection()) return null;
    return switch (record.collection.kind) {
        .list => .list,
        .dictionary => if (record.collection.set) .set else .dictionary,
        else => null,
    };
}

/// Whether `str(x)` and `repr(x)` take a value of type `ty`, and if not why: the one rule of the two functions.
pub fn classify(ty: typed.Type, records: []const typed.Record) Verdict {
    if (kind(ty, records) == null) return .other;
    var work: usize = 4096;
    if (withoutText(ty, records, 0, &work)) |part| return .{ .part_without_text = part };
    return .accepted;
}

/// Whether `ty` is a type `print` can show, including everything inside it (a type that `classify` accepts, or any other
/// type with a text). Core cannot render a part that is not a value; the check names it here instead.
pub fn shown(ty: typed.Type, records: []const typed.Record) bool {
    var work: usize = 4096;
    return withoutText(ty, records, 0, &work) == null;
}

/// The first type inside `ty` (or `ty` itself) that has no text, or null when every part has one: the rule `print`, `str`, `repr`
/// and a format string's hole share (PRINT-1).
pub fn partWithoutText(ty: typed.Type, records: []const typed.Record) ?typed.Type {
    var work: usize = 4096;
    return withoutText(ty, records, 0, &work);
}

/// The refusal of `print` or a format string's hole for a value of type `ty` that has `part` inside it with no text (PRINT-1):
/// what the value is and what it holds, which cannot be shown, and what to write instead. `subject` opens the sentence
/// (`` `print` of `Stream[]` ``). The caller owns the result.
pub fn printRefusal(allocator: std.mem.Allocator, subject: []const u8, ty: typed.Type, part: typed.Type, records: []const typed.Record) std.mem.Allocator.Error![]const u8 {
    const name = try typed.surfaceTypeName(allocator, ty, records);
    defer allocator.free(name);
    const instead = "capabilities, open files, owned resources and callbacks cannot be shown, so write a name or a count that describes them";
    if (part == ty) return std.fmt.allocPrint(allocator, "{s} of `{s}` is refused: it has no text; {s}", .{ subject, name, instead });
    const part_name = try typed.surfaceTypeName(allocator, part, records);
    defer allocator.free(part_name);
    return std.fmt.allocPrint(allocator, "{s} of `{s}` is refused: it holds a `{s}`, which has no text; {s}", .{ subject, name, part_name, instead });
}

/// The first type inside `ty` (or `ty` itself) that has no text, or null when every part has one. A budget of visits and a
/// depth bound end a recursive type, which `print` shows to 24 levels and then as `...`.
fn withoutText(ty: typed.Type, records: []const typed.Record, depth: usize, work: *usize) ?typed.Type {
    if (ty == .unit or ty == .bool or ty.isInteger()) return null;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return ty;
    if (work.* == 0 or depth > 64) return null;
    work.* -= 1;
    const record = records[ty.recordIndex()];
    if (!io_render.printable(ty, records)) return ty;
    if (record.shape.domain) |wire| return withoutText(wire, records, depth + 1, work);
    if (record.shape.buffer) |element| if (withoutText(element, records, depth + 1, work)) |part| return part;
    if (record.collection.key) |key| if (withoutText(key, records, depth + 1, work)) |part| return part;
    if (record.shape.array) |array| if (withoutText(array.element, records, depth + 1, work)) |part| return part;
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| if (withoutText(payload, records, depth + 1, work)) |part| return part;
    }
    for (record.fields) |field| if (withoutText(field.ty, records, depth + 1, work)) |part| return part;
    return null;
}

/// What a conversion function takes, for the sentence that names it.
pub const Function = enum {
    str,
    repr,

    /// The accepted types, spelled for the refusal.
    fn accepts(self: Function) []const u8 {
        return switch (self) {
            .str => "an int, float, bool or str, or a list, set, dictionary, option, record, result or fixed array",
            .repr => "a str, bytes, int, float or bool, or a list, set, dictionary, option, record, result or fixed array",
        };
    }
};

/// The refusal of `function(x)` for a value of type `ty`, which is not `accepted`: what the value is, and what makes text
/// of it instead. The caller owns the result.
pub fn refusal(allocator: std.mem.Allocator, function: Function, ty: typed.Type, records: []const typed.Record) std.mem.Allocator.Error![]const u8 {
    const name = try typed.surfaceTypeName(allocator, ty, records);
    defer allocator.free(name);
    const label = @tagName(function);
    switch (classify(ty, records)) {
        .accepted => unreachable,
        .part_without_text => |part| {
            const part_name = try typed.surfaceTypeName(allocator, part, records);
            defer allocator.free(part_name);
            if (part == ty) return std.fmt.allocPrint(allocator, "`{s}` of `{s}` is refused: it has no text; capabilities, open files, owned resources and callbacks cannot be shown", .{ label, name });
            return std.fmt.allocPrint(allocator, "`{s}` of `{s}` is refused: it holds a `{s}`, which has no text; capabilities, open files, owned resources and callbacks cannot be shown", .{ label, name, part_name });
        },
        .other => {},
    }
    if (!shown(ty, records)) return std.fmt.allocPrint(allocator, "`{s}` of `{s}` is refused: it has no text; capabilities, open files, owned resources and callbacks cannot be shown", .{ label, name });
    if (function == .str and ty.isAggregate() and typed.isByteString(records[ty.recordIndex()]))
        return std.fmt.allocPrint(allocator, "`str` of `bytes` is refused: bytes are not text; `repr(value)` is the `b'...'` spelling `print` shows", .{});
    if (ty.isAggregate() and isEnumLike(records[ty.recordIndex()]))
        return std.fmt.allocPrint(allocator, "`{s}` of `{s}` is refused: `case_name(value)` is the name of its case, and `f\"{{value}}\"` shows it as `print` does", .{ label, name });
    return std.fmt.allocPrint(allocator, "`{s}` of `{s}` is refused: `{s}` takes {s} that `print` can show; `f\"{{value}}\"` gives the text `print` shows for any value", .{ label, name, label, function.accepts() });
}

/// Whether a record is a declared enum or tagged union: variants that are neither an option nor a checked result.
fn isEnumLike(record: typed.Record) bool {
    const variants = record.shape.variants orelse return false;
    return !variants.fallible and typed.surfaceOptionalPayload(record) == null;
}
