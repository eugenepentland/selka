//! The text of the `W_NEEDLESS_COPY` repair of a copy in a loop that may consume its list (COPY-A2c, `needless_copy.zig`
//! `loopRepair`): `own ` in the loop's header, the copy as `own x` or `own x.f` (a bare `x` where it is returned), and the
//! message. The pass decides whether the rewrite is certain; this file only writes it.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// Where a loop repair writes: the byte after `in ` in the loop's header, the copy, its operand, and whether the copy is
/// a returned name (`return x`, where `return own x` is `E_OWN_MARKER`).
pub const LoopEdit = struct { insert: usize, copy: source.Span, receiver: []const u8, returned: bool };

/// The repair of a copy in a loop that may consume its list: `own ` in the header, and the copy as `own x` (`x` when returned).
pub fn loopFix(memory: std.mem.Allocator, at: LoopEdit) std.mem.Allocator.Error!diagnostic.Fix {
    const replacement = if (at.returned) at.receiver else try std.fmt.allocPrint(memory, "own {s}", .{at.receiver});
    const more = try memory.dupe(diagnostic.Edit, &.{.{ .span = at.copy, .text = replacement }});
    return .{ .edit = .{ .span = .{ .start = at.insert, .end = at.insert }, .text = "own " }, .more = more };
}

/// The message of a loop repair inside one function: over a call's list (`fresh`, `list` its call) or an owned list.
pub fn moveMessage(memory: std.mem.Allocator, fresh: bool, list: []const u8, element: []const u8) std.mem.Allocator.Error![]const u8 {
    if (fresh) return std.fmt.allocPrint(
        memory,
        "the list `{s}` returns is named by nothing else, so `for {s} in own {s}` makes `{s}` an owned element and the copy becomes a move",
        .{ list, element, list, element },
    );
    return std.fmt.allocPrint(
        memory,
        "`{s}` is not used after the loop, so `for {s} in own {s}` makes `{s}` an owned element and the copy becomes a move",
        .{ list, element, list, element },
    );
}
