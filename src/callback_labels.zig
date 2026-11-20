//! Parameter labels are source contracts shared by nominal and callable identities.
const std = @import("std");
const source = @import("source.zig");
/// Compare named labels, treating an omitted list as positional inputs.
pub fn equalLabels(a: []const []const u8, b: []const []const u8) bool {
    for (0..@max(a.len, b.len)) |index| {
        const left = if (index < a.len) a[index] else "";
        const right = if (index < b.len) b[index] else "";
        if (!std.mem.eql(u8, left, right)) return false;
    }
    return true;
}
/// Capture only named labels from a parsed callable type.
pub fn syntaxLabels(allocator: std.mem.Allocator, src: source.Source, callback: @import("ast.zig").CallbackType) error{OutOfMemory}![]const []const u8 {
    const labels = try allocator.alloc([]const u8, callback.parameters.len);
    for (labels, 0..) |*label, index| label.* = if (index < callback.parameter_modes.named.len and callback.parameter_modes.named[index]) src.text(callback.parameter_names[index].?) else "";
    return labels;
}
