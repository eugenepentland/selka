//! Caller-owned bounded instruction/value observations; no heap or retained owners.
const bc = @import("bytecode.zig");
const typed = @import("typed.zig");
/// The top operand before an instruction; aggregates are identified without copying.
pub const Sample = union(enum) { empty, integer: i128, boolean: bool, aggregate_type: typed.Type };
/// One instruction and a bounded scalar/type sample at its original source span.
pub const Event = struct { function: typed.FunctionId, pc: usize, step: u64, operation: []const u8, span: @import("source.zig").Span, top: Sample };
/// Supply an output slice. Excess events increment omitted without affecting execution.
pub const Trace = struct {
    events: []Event,
    count: usize = 0,
    omitted: usize = 0,
    /// Record a source-mapped pre-instruction snapshot into bounded caller storage.
    pub fn record(self: *Trace, function: typed.FunctionId, pc: usize, step: u64, instruction: bc.Instruction, operands: []const typed.Value) void {
        if (self.count == self.events.len) {
            self.omitted +|= 1;
            return;
        }
        self.events[self.count] = .{ .function = function, .pc = pc, .step = step, .operation = @tagName(instruction.op), .span = instruction.span, .top = sample(operands) };
        self.count += 1;
    }
};
fn sample(operands: []const typed.Value) Sample {
    if (operands.len == 0) return .empty;
    const value = operands[operands.len - 1];
    return switch (value) {
        .i64 => |number| .{ .integer = number },
        .integer => |number| .{ .integer = number.value },
        .bool => |boolean| .{ .boolean = boolean },
        else => .{ .aggregate_type = value.typeOf() },
    };
}
