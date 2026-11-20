//! The shape of what the optimizer made of each function, for the engine's shadow (`optimizer_shadow.zig` fills it). A leaf of its
//! own so that the optimizer's cache context can hold a pointer to it without importing the code that reads the context.
const std = @import("std");

/// A 32-byte digest.
pub const Digest = [32]u8;

/// One internal function in its final form.
pub const Entry = struct {
    key: []const u8,
    body: Digest,
    /// Whether this build analysed the function afresh, as opposed to restoring its stored final record.
    fresh: bool,
    /// The keys of the internal functions the final body calls or takes by reference, each once.
    callees: []const []const u8,
    /// The keys of the internal functions whose bodies were inlined into it, each once.
    contributors: []const []const u8,
};

/// The optimizer's output, once observed.
pub const Observed = struct {
    arena: std.mem.Allocator,
    collected: bool = false,
    entries: []const Entry = &.{},
    /// The physical functions the final stage analysed afresh in this build, as the passes reach them.
    analysed: std.ArrayList(u32) = .empty,

    /// Note that function `index` was analysed afresh, not restored from a stored final record.
    pub fn markFresh(self: *Observed, index: u32) std.mem.Allocator.Error!void {
        try self.analysed.append(self.arena, index);
    }
};
