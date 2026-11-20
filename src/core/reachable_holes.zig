//! The typed holes a built program reaches. A release build checks with holes kept as traps, as a debug build does, and builds
//! only the functions `main` can reach, a function value counting as a call of its function. A hole that survives in a built
//! function is therefore one `main` can reach, directly or through a function value, and a release build refuses it.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");

/// One typed hole in a function the build reached: where the `todo[T]()` is written and the function that holds it.
pub const Hole = struct { span: u32, function: []const u8 };

/// Every typed hole in the functions of `module`, in function order and then instruction order, one per source position: a generic
/// function built for several types holds the same hole once for each, and is reported once.
pub fn find(allocator: std.mem.Allocator, module: *const ir.Module) std.mem.Allocator.Error![]const Hole {
    var found: std.ArrayList(Hole) = .empty;
    var seen: std.AutoHashMapUnmanaged(u32, void) = .empty;
    defer seen.deinit(allocator);
    for (module.functions.items) |function| {
        for (function.insts.items) |inst| {
            if (inst.op != .@"unreachable" or inst.data != flags.typed_hole_trap) continue;
            if ((try seen.getOrPut(allocator, inst.span)).found_existing) continue;
            try found.append(allocator, .{ .span = inst.span, .function = function.name });
        }
    }
    return found.toOwnedSlice(allocator);
}
