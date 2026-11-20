//! Memory a command leaves for the operating system (L1R12-EXIT-1).
//!
//! `selka build` writes its report and exits. The kernel reclaims a process's pages in one pass at exit, cheaper than the compiler
//! unmapping its arenas by hand a moment before, so a command that returns straight to process exit can skip its last frees. A Debug or
//! ReleaseSafe compiler (the checking allocator) never skips, so leak checks see every free. A command that continues after the build
//! (`selka run` starts the program, and a test run builds many programs) never declares itself last.
const std = @import("std");
const builtin = @import("builtin");

/// Whether this build of the compiler checks for leaks, and therefore frees everything.
const checks_leaks = switch (builtin.mode) {
    .debug, .safe => true,
    .fast, .small => false,
};

var ends: std.atomic.Value(bool) = .init(false);

/// Declare that the process exits as soon as the current command returns.
pub fn declareLast() void {
    ends.store(true, .release);
}

/// Withdraw `declareLast`: the command returned and the process goes on.
pub fn withdraw() void {
    ends.store(false, .release);
}

/// Whether the memory the build still holds may be left to the kernel: the process ends with the current command, and nothing checks for leaks.
pub fn leavesMemory() bool {
    return !checks_leaks and ends.load(.acquire);
}

test "a command that is not the last frees everything, a last one leaves its memory in a release compiler" {
    withdraw();
    try std.testing.expect(!leavesMemory());
    declareLast();
    try std.testing.expectEqual(!checks_leaks, leavesMemory());
    withdraw();
    try std.testing.expect(!leavesMemory());
}
