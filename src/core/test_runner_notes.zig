//! What the runner learns about each test while the engine decides: whether the engine served it and whether a served record
//! is to be checked by running the test, kept by entry and test name until the entry's observation settles them. A leaf of the
//! runner, so the engine's state can hold it and the decision code can fill it without importing one another.
const std = @import("std");

/// What the engine did with a test.
pub const Choice = enum {
    /// The engine was not asked: the test has no key, or the run is one the engine does not decide.
    unasked,
    /// A valid record served the test; the runner reuses its verdict.
    reuse,
    /// No valid record served the test; the runner runs it.
    rerun,
};

/// What is known of one test.
pub const Note = struct {
    /// What the engine did.
    engine: Choice = .unasked,
    /// A record served the test and verify mode chose to check it: the runner runs the test anyway and the observation
    /// compares the fresh verdict with the record.
    check: bool = false,
};

/// The notes of a process, by `entry NUL name`.
pub const Notes = struct {
    mutex: std.Io.Mutex = .init,
    arena: std.heap.ArenaAllocator,
    map: std.StringHashMapUnmanaged(Note) = .empty,

    /// An empty set of notes over `gpa`.
    pub fn init(gpa: std.mem.Allocator) Notes {
        return .{ .arena = .init(gpa) };
    }

    /// Free the notes.
    pub fn deinit(self: *Notes, gpa: std.mem.Allocator) void {
        self.map.deinit(gpa);
        self.arena.deinit();
    }

    /// Fold what a decision site knows into the note of `name` in `entry`: a reuse by the engine outranks a rerun (a test is
    /// reused when any of its arguments is served), and a check mark stays.
    pub fn update(self: *Notes, gpa: std.mem.Allocator, io: std.Io, entry: []const u8, name: []const u8, change: Note) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const a = self.arena.allocator();
        const key = std.mem.concat(a, u8, &.{ entry, "\x00", name }) catch return;
        const slot = self.map.getOrPut(gpa, key) catch return;
        if (!slot.found_existing) slot.value_ptr.* = .{};
        const note = slot.value_ptr;
        switch (change.engine) {
            .unasked => {},
            .reuse => {
                note.engine = .reuse;
                note.check = note.check or change.check;
            },
            .rerun => if (note.engine != .reuse) {
                note.engine = .rerun;
            },
        }
    }

    /// The note of `name` in `entry`, or null when no decision site saw the test.
    pub fn find(self: *Notes, scratch: std.mem.Allocator, io: std.Io, entry: []const u8, name: []const u8) ?Note {
        const key = std.mem.concat(scratch, u8, &.{ entry, "\x00", name }) catch return null;
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.map.get(key);
    }
};

test "a reuse by the engine outranks a rerun and a check mark stays" {
    var notes = Notes.init(std.testing.allocator);
    defer notes.deinit(std.testing.allocator);
    const io = std.testing.io;
    notes.update(std.testing.allocator, io, "a.selka", "t", .{ .engine = .rerun });
    notes.update(std.testing.allocator, io, "a.selka", "t", .{ .engine = .reuse, .check = true });
    notes.update(std.testing.allocator, io, "a.selka", "t", .{ .engine = .rerun });
    var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer scratch.deinit();
    const found = notes.find(scratch.allocator(), io, "a.selka", "t").?;
    try std.testing.expectEqual(Choice.reuse, found.engine);
    try std.testing.expect(found.check);
    try std.testing.expectEqual(@as(?Note, null), notes.find(scratch.allocator(), io, "b.selka", "t"));
}
