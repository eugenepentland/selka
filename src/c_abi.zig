//! Source-level contract for direct, fixed-arity C scalar imports.
const std = @import("std");
const typed = @import("typed.zig");
/// Diagnostic shared by parameter and result checking.
pub const signature_message = "extern signatures support fixed-width integers, bool, float (C double), extern type handles, " ++
    "str and bytes parameters (a lent pointer and length), bytes and unit results; records, lists and variadic calls are not supported";
/// The refusal of a `byte_buffer` parameter, which names the snapshot that crosses instead.
pub const buffer_message = "a byte_buffer cannot cross into C; pass its snapshot `bytes(buffer)` to a `bytes` parameter";
/// Ordinary floating values retain their language identity at the foreign boundary.
pub fn isFloat(ty: typed.Type, records: []const typed.Record) bool {
    return @import("numeric_surface.zig").isFloat(ty, records);
}
/// Accepted foreign types; void is legal only as a result.
pub fn supported(ty: typed.Type, records: []const typed.Record, result: bool) bool {
    return ty.isInteger() or ty == .bool or (result and ty == .unit) or isFloat(ty, records) or foreignHandle(ty, records) or
        (!result and lentSpan(ty, records)) or (result and isBytes(ty, records));
}
/// The refusal of a `str` result, which names the `bytes` result that crosses instead.
pub const text_result_message = "an extern func cannot return `str`: C text may be invalid UTF-8; declare `-> bytes` (the runtime copies it) and call `.decode()`";
/// The refusal of a `mut` parameter that is no out-parameter.
pub const out_parameter_message = "a `mut` parameter of an extern func is an out-parameter, a pointer to an integer, bool, float or extern type";
/// The refusal of `mut` out-parameters beside a copied `bytes` result.
pub const bytes_out_message = "an extern func that returns `bytes` takes no `mut` out-parameters; its trailing argument is the length";
/// The immutable byte string, the one managed result an extern func may declare (a copy the runtime makes).
pub fn isBytes(ty: typed.Type, records: []const typed.Record) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and typed.isByteString(records[ty.recordIndex()]);
}
/// Whether a `mut` parameter of this type is an out-parameter C can write through a pointer.
pub fn outParameter(ty: typed.Type, records: []const typed.Record) bool {
    return ty.isInteger() or ty == .bool or isFloat(ty, records) or foreignHandle(ty, records);
}
/// The text type, refused as a result with its own message.
pub fn isText(ty: typed.Type, records: []const typed.Record) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and records[ty.recordIndex()].managed and records[ty.recordIndex()].collection.kind == .string;
}
/// An `extern type`: an opaque C pointer that crosses unchanged.
pub fn foreignHandle(ty: typed.Type, records: []const typed.Record) bool {
    return @import("extern_types.zig").is(ty, records);
}
/// A `str` or `bytes` parameter crosses as a read-only `(const uint8_t *, int64_t)` pair lent for the call.
pub fn lentSpan(ty: typed.Type, records: []const typed.Record) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    return record.managed and (record.collection.kind == .string or typed.isByteString(record));
}
/// The mutable octet buffer, refused with its own message.
pub fn isBuffer(ty: typed.Type, records: []const typed.Record) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    return record.managed and record.collection.kind == .bytes and !typed.isByteString(record);
}
/// Module qualification is a language namespace, never part of a C symbol.
pub fn symbol(name: []const u8) []const u8 {
    const offset = if (std.mem.lastIndexOf(u8, name, "::")) |at| at + 2 else 0;
    return name[offset..];
}
/// The prefixes of the runtime's symbols, which an extern name may not take. `selka_` is not one of them: the runtime keeps its
/// `myl_` names after the rename (decision GH-D16), and a project's own C functions are called `selka_...`.
const reserved_prefixes = [_][]const u8{ "myl_", "mylang_" }; // rename: keep
/// Restrict symbol spellings to portable identifiers and protect runtime symbols.
pub fn validSymbol(name: []const u8) bool {
    if (name.len == 0 or (!std.ascii.isAlphabetic(name[0]) and name[0] != '_')) return false;
    for (name) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    for (reserved_prefixes) |prefix| if (std.mem.startsWith(u8, name, prefix)) return false;
    return true;
}
/// A C symbol has one prototype even when imported in multiple language modules.
pub fn validateImports(allocator: std.mem.Allocator, functions: []const typed.Function, sink: *@import("diagnostic.zig").Sink) @import("diagnostic.zig").Error!void {
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    defer names.deinit(allocator);
    for (functions, 0..) |function, i| {
        // An `@address` extern names no symbol, so it cannot conflict with one.
        if (!function.policy.c_abi or function.policy.address) continue;
        const found = try names.getOrPut(allocator, symbol(function.name));
        if (!found.found_existing) {
            found.value_ptr.* = i;
            continue;
        }
        const previous = functions[found.value_ptr.*];
        var same = previous.signature.return_type == function.signature.return_type and previous.signature.parameter_count == function.signature.parameter_count;
        if (same) for (previous.scope.locals, function.scope.locals) |left, right| {
            if (left.ty != right.ty) same = false;
        };
        if (!same) return sink.failRelated("E_EXTERN_CONFLICT", function.declaration, "C symbol has conflicting imported signatures", .{ .span = previous.declaration, .message = "previous C declaration" });
    }
}
