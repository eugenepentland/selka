//! Settled record-validation facts: the flags validation derives from reachable records, kept per compilation.
const std = @import("std");
const Span = @import("source.zig").Span;

/// The facts validation derives from a record's reachable records, kept for the
/// life of one compilation. A settled record reaches only settled records, so its
/// facts never change, and each later check computes facts only for the records
/// it adds. Every table indexes like `records`.
pub const Facts = struct {
    /// Records `0..len` are settled, and their flags below are final.
    len: usize = 0,
    /// Records validated over every call. A call that adds k records raises it by k.
    checked: usize = 0,
    /// Whether a record carries an open file handle by value.
    file: std.ArrayList(bool) = .empty,
    /// Cell contents policy: whether a Cell may not hold this record (see `cell_types`).
    forbidden: std.ArrayList(bool) = .empty,
    /// Whether a record is, or transitively contains, a Cell.
    cell: std.ArrayList(bool) = .empty,
    /// Where an instance of a generic type was first written (`Box[File]` in a field, a parameter or a local), or an empty span: a
    /// refusal of what the instance stores points at that spelling, not at the field of the template that declares it.
    site: std.ArrayList(Span) = .empty,

    /// Release the tables of facts that do not live in a compilation arena.
    pub fn deinit(self: *Facts, allocator: std.mem.Allocator) void {
        self.file.deinit(allocator);
        self.forbidden.deinit(allocator);
        self.cell.deinit(allocator);
        self.site.deinit(allocator);
    }

    /// Extend every table to `count` records; the new entries start unset.
    pub fn grow(self: *Facts, allocator: std.mem.Allocator, count: usize) std.mem.Allocator.Error!void {
        try self.file.appendNTimes(allocator, false, count - self.file.items.len);
        try self.forbidden.appendNTimes(allocator, false, count - self.forbidden.items.len);
        try self.cell.appendNTimes(allocator, false, count - self.cell.items.len);
        try self.site.appendNTimes(allocator, .{ .start = 0, .end = 0 }, count - self.site.items.len);
    }
};
