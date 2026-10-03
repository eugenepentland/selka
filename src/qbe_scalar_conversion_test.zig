//! Direct integer-to-binary64 conversions retain word-backed float storage.
const std = @import("std");
const t = std.testing;
const scalar = @import("qbe_scalar.zig");

const Emitter = struct {
    output: std.Io.Writer.Allocating,
    next: usize = 0,
    stored: ?usize = null,
    /// Allocate a fresh emitted temporary.
    pub fn temp(self: *Emitter) usize {
        const value = self.next;
        self.next += 1;
        return value;
    }
    /// Load the canonical input word of this one-operand test emitter.
    pub fn load(_: *Emitter, kind: []const u8, slot: usize) scalar.Error!usize {
        if (!std.mem.eql(u8, kind, "s") or slot != 0) return error.InternalError;
        return 17;
    }
    /// Record the result word rather than observing a hardware float register.
    pub fn store(self: *Emitter, slot: usize, value: usize) scalar.Error!void {
        if (slot != 0) return error.InternalError;
        self.stored = value;
    }
    /// Append exact target instructions to the test buffer.
    pub fn print(self: *Emitter, comptime format: []const u8, arguments: anytype) scalar.Error!void {
        try self.output.writer.print(format, arguments);
    }
};

// spec: QBE-INTEGER-FLOAT-DIRECT-1
test "integer float direct conversion preserves signedness and stores binary64 bits" {
    var signed: Emitter = .{ .output = .init(t.allocator) };
    defer signed.output.deinit();
    try t.expect(try scalar.Lower(Emitter).floatUnary(&signed, .f64_from_i64, 1));
    try t.expectEqualStrings(" %v0 =d sltof %v17\n %v1 =l cast %v0\n", signed.output.written());
    try t.expectEqual(@as(?usize, 1), signed.stored);
    var unsigned: Emitter = .{ .output = .init(t.allocator) };
    defer unsigned.output.deinit();
    try t.expect(try scalar.Lower(Emitter).floatUnary(&unsigned, .f64_from_u64, 1));
    try t.expectEqualStrings(" %v0 =d ultof %v17\n %v1 =l cast %v0\n", unsigned.output.written());
    try t.expectEqual(@as(?usize, 1), unsigned.stored);
    try t.expect(!try scalar.Lower(Emitter).floatUnary(&unsigned, .f64_to_i64, 1));
    try t.expect(!try scalar.Lower(Emitter).floatUnary(&unsigned, .f64_to_u8, 1));
}
