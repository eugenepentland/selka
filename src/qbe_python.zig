//! Python text/bytes search bounds, charsets and repr use statically selected helpers.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const operations = @import("buffer_operations.zig");
const allocation_failure = @import("qbe_format.zig").allocation_failure;
const Operation = @FieldType(@FieldType(bytecode.Instruction, "op"), "buffer_operation");
/// Errors shared with the text and byte emitters.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Checked operand slots and the statically selected receiver family.
pub const Site = struct { op: Operation, input: usize, base: usize, bytes: bool, stack: []const typed.Type };
/// Emit one new fixed-arity search, charset trim or scalar repr operation.
pub fn operation(comptime E: type, self: *E, site: Site) Error!void {
    if (operations.trim(site.op.kind) != null) return trim(E, self, site.op, site.input, site.base, site.bytes);
    if (site.op.kind == .text_repr) return repr(E, self, site.input, site.base, site.bytes);
    return search(E, self, site);
}

fn trim(comptime E: type, self: *E, op: Operation, input: usize, base: usize, bytes: bool) Error!void {
    const chars = if (op.kind.arity() == 1) try self.load("s", base) else self.temp();
    if (op.kind.arity() == 0) try self.print(" %v{d} =l copy 0\n", .{chars});
    const result = self.temp();
    const name = if (bytes) "myl_native_bytes_trim_chars" else "myl_native_text_trim_chars";
    try self.print(" %v{d} =l call ${s}(l %heap, l %v{d}, l %v{d}, w {d})\n", .{ result, name, input, chars, operations.trim(op.kind).? });
    try self.require(result, allocation_failure);
    try self.store(base, result);
}

fn repr(comptime E: type, self: *E, input: usize, base: usize, bytes: bool) Error!void {
    const result = self.temp();
    const name = if (bytes) "myl_native_bytes_repr" else "myl_native_text_repr";
    try self.print(" %v{d} =l call ${s}(l %heap, l %v{d})\n", .{ result, name, input });
    try self.require(result, allocation_failure);
    try self.store(base, result);
}

fn search(comptime E: type, self: *E, site: Site) Error!void {
    const needle = try self.load("s", site.base);
    const start = try bound(E, self, site, 1, 0);
    const end = try bound(E, self, site, 2, 9223372036854775807);
    const result = self.temp();
    const mode = operations.search(site.op.kind) orelse return error.InternalError;
    const name = if (site.bytes) "myl_native_bytes_search_range" else "myl_native_text_search_range";
    try self.print(" %v{d} =l call ${s}(l %v{d}, l %v{d}, l %v{d}, l %v{d}, w {d})\n", .{ result, name, site.input, needle, start, end, @backingInt(mode) });
    if (mode == .index or mode == .rindex) {
        const found = self.temp();
        try self.print(" %v{d} =l csgel %v{d}, 0\n", .{ found, result });
        try self.require(found, "myl_qbe_fail_substring");
    }
    try self.store(site.base, result);
}

/// Saturate unsigned64 bounds at signed maximum, which is beyond every payload,
/// rather than interpreting a high bit as a Python negative index.
fn bound(comptime E: type, self: *E, site: Site, index: usize, fallback: u64) Error!usize {
    if (site.op.kind.arity() <= index) {
        const result = self.temp();
        try self.print(" %v{d} =l copy {d}\n", .{ result, fallback });
        return result;
    }
    const value = try self.load("s", site.base + index);
    if (site.stack[site.base + index] != .u64) return value;
    const mask = self.temp();
    const low_mask = self.temp();
    const low = self.temp();
    const high = self.temp();
    const result = self.temp();
    try self.print(" %v{d} =l sar %v{d}, 63\n", .{ mask, value });
    try self.print(" %v{d} =l xor %v{d}, -1\n", .{ low_mask, mask });
    try self.print(" %v{d} =l and %v{d}, %v{d}\n", .{ low, value, low_mask });
    try self.print(" %v{d} =l and %v{d}, 9223372036854775807\n", .{ high, mask });
    try self.print(" %v{d} =l or %v{d}, %v{d}\n", .{ result, low, high });
    return result;
}
