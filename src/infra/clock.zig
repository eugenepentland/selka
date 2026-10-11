//! Host clock boundary for disposable cache housekeeping, never reuse admission.
const std = @import("std");

/// Read Unix-epoch nanoseconds through the caller's I/O clock capability.
/// Retention compares this with filesystem timestamps only to choose eviction.
pub fn retentionNow(io: std.Io) i96 {
    return std.Io.Clock.real.now(io).nanoseconds;
}
