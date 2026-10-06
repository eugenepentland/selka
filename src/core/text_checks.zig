//! Located text helper checks shared by the base and extended builders.
const ir = @import("ir.zig");
const flags = @import("flags.zig");

/// Allocation and precise feature refusal are the builder failures.
pub const Error = error{ OutOfMemory, Unsupported };

/// Branch to a located text trap unless the checked runtime condition holds.
pub fn require(comptime Context: type, context: Context, condition: ir.Ref, kind: u8, span: u32) Error!void {
    const good = try context.newBlock();
    const bad = try context.newBlock();
    try context.branch(condition, good, bad, span);
    try context.seal(bad);
    context.current = bad;
    _ = try context.emit(.{ .op = .@"unreachable", .ty = .void, .data = flags.text_trap | kind, .span = span });
    try context.seal(good);
    context.current = good;
}
