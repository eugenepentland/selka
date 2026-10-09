//! Source-level contract for direct, fixed-arity C scalar imports.
const std = @import("std");
const typed = @import("typed.zig");
/// Diagnostic shared by parameter and result checking.
pub const signature_message = "extern signatures support fixed-width integers, bool, float (C double), and unit results (C void); pointers, aggregates and variadic calls are not supported";
/// Ordinary floating values retain their language identity at the foreign boundary.
pub fn isFloat(ty: typed.Type, records: []const typed.Record) bool {
    return @import("numeric_surface.zig").isFloat(ty, records);
}
/// Accepted foreign types; void is legal only as a result.
pub fn supported(ty: typed.Type, records: []const typed.Record, result: bool) bool {
    return ty.isInteger() or ty == .bool or (result and ty == .unit) or isFloat(ty, records);
}
/// Module qualification is a language namespace, never part of a C symbol.
pub fn symbol(name: []const u8) []const u8 {
    const offset = if (std.mem.lastIndexOf(u8, name, "::")) |at| at + 2 else 0;
    return name[offset..];
}
/// Restrict symbol spellings to portable identifiers and protect runtime symbols.
pub fn validSymbol(name: []const u8) bool {
    if (name.len == 0 or (!std.ascii.isAlphabetic(name[0]) and name[0] != '_')) return false;
    for (name) |c| if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
    return !std.mem.startsWith(u8, name, "myl_") and !std.mem.startsWith(u8, name, "selka_");
}
/// A C symbol has one prototype even when imported in multiple language modules.
pub fn validateImports(allocator: std.mem.Allocator, functions: []const typed.Function, sink: *@import("diagnostic.zig").Sink) @import("diagnostic.zig").Error!void {
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    defer names.deinit(allocator);
    for (functions, 0..) |function, i| {
        if (!function.policy.c_abi) continue;
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
