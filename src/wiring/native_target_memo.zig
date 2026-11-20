//! The native target digest of this process, remembered once it is detected
//! (NATIVE-TARGET-ONCE-1). The machine and the process's loader cannot change while
//! it runs, and detecting the target reads the loader and libc files: about 3 ms in
//! the Debug compiler, paid two to four times by every command that identifies the
//! toolchain. Only the process wiring owns mutable global state, so the cell lives
//! here and `core/tool_identity.zig` asks for it.
const std = @import("std");

/// The 32-byte digest the core derives from the native target.
pub const Digest = [32]u8;

/// A value written at most once. The first writer wins; readers see all of it or nothing.
pub const Cell = struct {
    state: std.atomic.Value(u32) = .init(0),
    value: Digest = @splat(0),

    /// The remembered digest, if one was stored.
    pub fn get(self: *const Cell) ?Digest {
        if (self.state.load(.acquire) != ready) return null;
        return self.value;
    }

    /// Remember `digest` unless another caller already did.
    pub fn put(self: *Cell, digest: Digest) void {
        if (self.state.cmpxchgStrong(empty, writing, .acq_rel, .acquire) != null) return;
        self.value = digest;
        self.state.store(ready, .release);
    }
};

const empty = 0;
const writing = 1;
const ready = 2;

var process: Cell = .{};

/// The digest this process detected, if it has.
pub fn recall() ?Digest {
    return process.get();
}

/// Remember the digest this process detected.
pub fn remember(digest: Digest) void {
    process.put(digest);
}

// spec: NATIVE-TARGET-ONCE-1
test "a cell keeps the first digest it is given and shows nothing before that" {
    var cell: Cell = .{};
    try std.testing.expectEqual(@as(?Digest, null), cell.get());
    cell.put(@splat(7));
    cell.put(@splat(9));
    try std.testing.expectEqual(@as(?Digest, @splat(7)), cell.get());
}
