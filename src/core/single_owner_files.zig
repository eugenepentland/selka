//! The stored-file rule of the source ownership contract (P4): a file owner lives in a named local scope, so a type that stores
//! one anywhere below its top is refused, whatever generic or callback type carries it. The rule is a property of a type
//! alone. The walk that decides it is paid once per record of the program, not once per local that has the type: a call that
//! returns without a refusal has seen every record below the type it started from, and remembers them all as clear.
const std = @import("std");
const typed = @import("selka").typed;
const Span = @import("selka").source.Span;

/// A walk stops on the first stored file, or when it runs out of memory.
pub const Error = error{ OutOfMemory, StoredFile };

/// What the walks of a program have learned of one of its records.
const Mark = enum(u8) {
    /// Not walked, or reached only by a call that was refused: nothing is known, so the next call walks it again.
    unknown,
    /// Reached by the call in progress. Its subtree is walked or being walked, and no file owner has been found so far.
    reached,
    /// Reached by a call that returned: no file owner is stored anywhere below it, and no later call looks again.
    clear,
};

/// The records of one program, each marked as the walks of the program's functions learn them. One value serves every function of
/// a check; it is not shared between programs (a mark is a statement about one program's records).
pub const Walk = struct {
    gpa: std.mem.Allocator,
    marks: []Mark,
    /// The records the call in progress marked `reached`, so a call that is refused takes its marks back.
    reached: std.ArrayList(u32) = .empty,
    /// How many records the walks have entered: the work done, which a memoized call does not add to.
    entered: usize = 0,

    /// A walk over a program of `records` records, none yet known.
    pub fn init(gpa: std.mem.Allocator, records: usize) error{OutOfMemory}!Walk {
        const marks = try gpa.alloc(Mark, records);
        @memset(marks, .unknown);
        return .{ .gpa = gpa, .marks = marks };
    }

    /// Release the marks.
    pub fn deinit(self: *Walk) void {
        self.reached.deinit(self.gpa);
        self.gpa.free(self.marks);
    }

    /// Whether the type of a local or of a return, `ty`, stores no file owner below its top (the top itself may be one). A refusal is
    /// `error.StoredFile` and teaches the walk nothing: a type that a refused call entered is walked again by the next call, because
    /// its subtree was cut at the records of the path above it and proves nothing until the whole call is over. A call that returns
    /// marks every record it entered as clear, the records that closed a cycle included: the cut only skips a record the call is
    /// already walking, and the call that returned has walked all of them.
    pub fn supported(self: *Walk, records: []const typed.Record, ty: typed.Type) Error!void {
        std.debug.assert(records.len == self.marks.len);
        std.debug.assert(self.reached.items.len == 0);
        self.enter(records, ty, false) catch |err| {
            for (self.reached.items) |index| self.marks[index] = .unknown;
            self.reached.clearRetainingCapacity();
            return err;
        };
        for (self.reached.items) |index| self.marks[index] = .clear;
        self.reached.clearRetainingCapacity();
    }

    fn enter(self: *Walk, records: []const typed.Record, ty: typed.Type, nested: bool) Error!void {
        if (nested and ty.isFile()) return error.StoredFile;
        if (!ty.isAggregate()) return;
        const index = ty.recordIndex();
        // A record that is clear, or that this call has entered already (an ancestor on the way down, or a finished sibling branch), is
        // not walked again: everything below it is, or will be, examined by the walk that entered it.
        if (self.marks[index] != .unknown) return;
        self.marks[index] = .reached;
        try self.reached.append(self.gpa, @intCast(index));
        self.entered += 1;
        try records[index].eachStored(Error, Below{ .walk = self, .records = records }, Below.visit);
    }
};

/// What the walk of one record hands each type that record stores directly (`typed.Record.eachStored`).
const Below = struct {
    walk: *Walk,
    records: []const typed.Record,

    fn visit(self: Below, ty: typed.Type, _: Span) Error!void {
        try self.walk.enter(self.records, ty, true);
    }
};
