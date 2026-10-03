//! Shared conservative overlap gate for complete native ownership moves.
/// Output failures shared with native ownership emission.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// A complete range whose source and destination have the same fixed width.
pub const Range = struct { source: usize, destination: usize, size: u64 };
/// The caller supplies its own slow/fast block names and unique label suffix.
pub const Labels = struct { slow: []const u8, fast: []const u8, number: usize };

/// Admit only ranges whose two unsigned address distances are at least size.
/// The caller defines both target labels; no store precedes this branch.
pub fn branch(comptime E: type, self: *E, range: Range, labels: Labels) Error!void {
    const left = self.temp();
    const right = self.temp();
    const near_left = self.temp();
    const near_right = self.temp();
    const overlapping = self.temp();
    try self.print(" %v{d} =l sub %v{d}, %v{d}\n %v{d} =l sub %v{d}, %v{d}\n", .{ left, range.source, range.destination, right, range.destination, range.source });
    try self.print(" %v{d} =w cultl %v{d}, {d}\n %v{d} =w cultl %v{d}, {d}\n", .{ near_left, left, range.size, near_right, right, range.size });
    try self.print(" %v{d} =w or %v{d}, %v{d}\n jnz %v{d}, @{s}{d}, @{s}{d}\n", .{ overlapping, near_left, near_right, overlapping, labels.slow, labels.number, labels.fast, labels.number });
}
