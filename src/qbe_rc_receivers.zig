//! Shared physical receiver ancestry for uniqueness and guarded release.
const cow = @import("cow_plan.zig");

/// Resolve a compiler mutation receiver to its immediate physical parent.
pub fn receiverParent(comptime E: type, self: *E, index: usize) ?u32 {
    const plan = self.cow.?.plan;
    if (index >= plan.aliases.len or plan.aliases[index] == cow.none) return null;
    for (self.function.scope.instructions) |instruction| {
        const operation = switch (instruction.op) {
            .buffer_operation => |operation| operation,
            else => continue,
        };
        if (!operation.kind.writesReceiver() and operation.kind != .set_add and operation.kind != .set_discard) continue;
        var at: usize = @backingInt(operation.owner);
        var remaining = plan.aliases.len;
        while (remaining != 0) : (remaining -= 1) {
            if (at == index) return plan.aliases[index];
            if (plan.place(at)) |place| {
                at = place.parent;
            } else if (at < plan.aliases.len and plan.aliases[at] != cow.none) {
                at = plan.aliases[at];
            } else break;
        }
    }
    return null;
}
