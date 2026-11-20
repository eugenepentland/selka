//! Where a build lost a stored record (process wiring: the note is shared by the lanes of one process).
//!
//! A lost record (an artifact the front end counted on, a manifest that no longer fits the program, a missing object) makes the
//! build discard its partial work and start again with complete trees. The retry is correct and costs a whole-tree lowering, and
//! the error that causes it is the same one from sixty places. A site that loses a record returns `at(@src())` instead, which
//! remembers the first place anyone gave up since the last `take`, so the build's report can name it.
const std = @import("std");

/// A set of notes about lost records: the first site that gave up, the latest refusal, and the refusal that preceded the first
/// give-up. The process keeps one instance (`process`); a test keeps its own, because the unit root runs other tests that
/// build programs in the same process and a shared one would hand a test the notes of a build running beside it.
pub const Notes = struct {
    /// The first site that gave up since the last `take`. A build's lanes may lose records at once; the first one wins.
    first: std.atomic.Value(?*const std.lang.SourceLocation) = .init(null),
    /// The latest refusal noted by `note`.
    cause: std.atomic.Value(?*const std.lang.SourceLocation) = .init(null),
    /// The refusal `cause` held when `first` was set: why the site that gave up did.
    first_cause: std.atomic.Value(?*const std.lang.SourceLocation) = .init(null),

    /// Remember that a restore refused here. A refusal is not a loss: the function is lowered afresh. It becomes the reason of a
    /// loss when the next site to give up does so for want of the restore (an omitted body that cannot be restored).
    pub inline fn note(self: *Notes, comptime here: std.lang.SourceLocation) void {
        self.cause.store(&here, .monotonic);
    }

    /// Forget the noted refusal: the next restore starts without one.
    pub fn clear(self: *Notes) void {
        self.cause.store(null, .monotonic);
    }

    /// The error of a lost record, noting the place that lost it unless an earlier place is noted.
    pub inline fn at(self: *Notes, comptime here: std.lang.SourceLocation) error{CacheMiss} {
        if (self.first.cmpxchgStrong(null, &here, .monotonic, .monotonic) == null) self.first_cause.store(self.cause.load(.monotonic), .monotonic);
        return error.CacheMiss;
    }

    /// The place noted by the first `at` since the last `take` as `file:line function`, then the refusal it followed
    /// (`after file:line function`) when one was noted; forget both. Empty when none was noted.
    pub fn take(self: *Notes, a: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        const noted = self.first.swap(null, .monotonic) orelse return "";
        const because = self.first_cause.swap(null, .monotonic);
        if (because) |reason| return std.fmt.allocPrint(a, "{s}:{d} {s} after {s}:{d} {s}", .{ noted.file, noted.line, noted.fn_name, reason.file, reason.line, reason.fn_name });
        return std.fmt.allocPrint(a, "{s}:{d} {s}", .{ noted.file, noted.line, noted.fn_name });
    }
};

/// The notes of this process's builds (one build runs at a time in a command; a test uses a local `Notes` instead).
var process: Notes = .{};

/// Remember that a restore refused here (`Notes.note` on the process's notes).
pub inline fn note(comptime here: std.lang.SourceLocation) void {
    process.note(here);
}

/// `note`, and null: for a restore that answers "nothing to restore".
pub inline fn absent(comptime here: std.lang.SourceLocation) @TypeOf(null) {
    note(here);
    return null;
}

/// Forget the noted refusal: the next restore starts without one.
pub fn clear() void {
    process.clear();
}

/// The error of a lost record, noting the place that lost it unless an earlier place is noted. Call as `cache_miss.at(@src())`.
pub inline fn at(comptime here: std.lang.SourceLocation) error{CacheMiss} {
    return process.at(here);
}

/// The place noted by the first `at` since the last `take`, then the refusal it followed; forget both (`Notes.take`).
pub fn take(a: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
    return process.take(a);
}

fn lose(notes: *Notes) error{CacheMiss}!void {
    return notes.at(@src());
}

fn refuse(notes: *Notes) ?u8 {
    notes.note(@src());
    return null;
}

fn loseAgain(notes: *Notes) error{CacheMiss}!void {
    return notes.at(@src());
}

test "the first place that loses a record is the one a build reports, once" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var notes: Notes = .{};
    try std.testing.expectEqualStrings("", try notes.take(a));
    try std.testing.expectError(error.CacheMiss, lose(&notes));
    try std.testing.expectError(error.CacheMiss, loseAgain(&notes));
    const said = try notes.take(a);
    try std.testing.expect(std.mem.indexOf(u8, said, "cache_miss.zig") != null);
    try std.testing.expect(std.mem.endsWith(u8, said, "lose"));
    try std.testing.expectEqualStrings("", try notes.take(a));
    // A refusal noted before the loss is named with it.
    _ = refuse(&notes);
    try std.testing.expectError(error.CacheMiss, lose(&notes));
    const because = try notes.take(a);
    // The file is named from the test root (`wiring/cache_miss.zig` in the unit root), so look for the refusal after the word.
    const refusal = because[(std.mem.indexOf(u8, because, " after ") orelse return error.TestUnexpectedResult) + " after ".len ..];
    try std.testing.expect(std.mem.indexOf(u8, refusal, "cache_miss.zig:") != null);
    try std.testing.expect(std.mem.endsWith(u8, refusal, "refuse"));
    try std.testing.expect(std.mem.endsWith(u8, because[0 .. because.len - refusal.len], "lose after "));
}

test "a cleared refusal is not named with the next loss, and two sets of notes do not share" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var notes: Notes = .{};
    var other: Notes = .{};
    _ = refuse(&notes);
    notes.clear();
    try std.testing.expectError(error.CacheMiss, lose(&notes));
    const alone = try notes.take(a);
    try std.testing.expect(std.mem.indexOf(u8, alone, " after ") == null);
    try std.testing.expectEqualStrings("", try other.take(a));
}
