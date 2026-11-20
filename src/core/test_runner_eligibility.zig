//! Which `test-exec` records may use the shared tier (C2c1b). The receipts shared a result across worktrees only when the
//! test was provably portable: `test_runner_portable.shareable` for a result under a test's IR key, and `executionRefusal`
//! for one under its linked program's digest, which look for what a key may not see (a source or an asset outside the
//! project root, configuration the key cannot name relative to the root, an extern, a callable digest, an error trace). The
//! engine's tier applies the same two rules to the same two kinds of record, so it shares no more than the receipts did.
//! Local records keep their own eligibility (every test the runner can key).
//!
//! The engine asks a filter with the argument alone, and deciding a rule costs a module build per test, so nothing is
//! decided up front. The runner *declares* an argument when it asks about it (what the record would be a record of: the
//! context, the checked program and the test), and a decision is made the first time the tier is consulted for it (a local
//! miss, a publication) and remembered. An argument nobody declared stays local. A run's declarations are dropped when its
//! entry ends, since they point into that run.
const std = @import("std");
const frontend = @import("frontend.zig");
const receipt = @import("test_runner_receipt.zig");
const discover = @import("test_runner_discover.zig");
const portable = @import("test_runner_portable.zig");

/// Which rule a record answers to.
pub const Which = enum {
    /// A result under a test's IR key: `portable.shareable`.
    ir,
    /// A result under a linked program's digest: `portable.executionRefusal`.
    program,
};

/// What a record is a record of.
pub const Subject = struct {
    context: receipt.Context,
    checked: frontend.Checked,
    case: discover.Case,
    which: Which,
    /// The entry whose run declared it, so the run can drop its declarations.
    owner: []const u8,
    /// For a result under an IR key, whether every function the test reaches is `bare` (`test_runner_facts.bare`) when the
    /// key derivation knew it: the rule then needs no build of the test's program (`portable.shareableKnown`).
    bare: ?bool = null,
    /// The rule's reading of `checked` in the declaring entry's run (`portable.Program`), shared by every test the entry
    /// declares: with it the rule reads the program once for the run and counts what it does (`rule` of the work report).
    program: ?*portable.Program = null,
};

const Declared = struct {
    subject: Subject,
    /// 0: not decided, 1: allowed, 2: kept local.
    state: std.atomic.Value(u8) = .init(0),
};

/// What deciding an argument found.
pub const Decision = struct {
    allowed: bool,
    /// This call made the decision (it is not a remembered one) and it kept the record local.
    newly_local: bool = false,
};

/// The arguments the runs of a process have declared.
pub const Table = struct {
    mutex: std.Io.Mutex = .init,
    arena: std.heap.ArenaAllocator,
    map: std.StringHashMapUnmanaged(*Declared) = .empty,

    /// An empty table over `gpa`.
    pub fn init(gpa: std.mem.Allocator) Table {
        return .{ .arena = .init(gpa) };
    }

    /// Free the table.
    pub fn deinit(self: *Table, gpa: std.mem.Allocator) void {
        self.map.deinit(gpa);
        self.arena.deinit();
    }

    /// Declare that `argument` names a record of `subject`. A later declaration of the same argument replaces the earlier.
    pub fn declare(self: *Table, gpa: std.mem.Allocator, io: std.Io, argument: []const u8, subject: Subject) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const a = self.arena.allocator();
        const entry = a.create(Declared) catch return;
        entry.* = .{ .subject = subject };
        const slot = self.map.getOrPut(gpa, argument) catch return;
        if (!slot.found_existing) slot.key_ptr.* = a.dupe(u8, argument) catch {
            _ = self.map.remove(argument);
            return;
        };
        slot.value_ptr.* = entry;
    }

    /// Drop what the run of `owner` declared: it points into that run.
    pub fn release(self: *Table, gpa: std.mem.Allocator, io: std.Io, owner: []const u8) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        var doomed: std.ArrayList([]const u8) = .empty;
        defer doomed.deinit(gpa);
        var all = self.map.iterator();
        while (all.next()) |found| {
            if (std.mem.eql(u8, found.value_ptr.*.subject.owner, owner)) doomed.append(gpa, found.key_ptr.*) catch continue;
        }
        for (doomed.items) |argument| _ = self.map.remove(argument);
    }

    /// Whether the record of `argument` may use the tier: an argument nobody declared may not; a declared one is decided
    /// by its rule the first time and remembered. A rule that fails to run keeps the record local.
    pub fn decide(self: *Table, gpa: std.mem.Allocator, io: std.Io, argument: []const u8) Decision {
        self.mutex.lockUncancelable(io);
        const found = self.map.get(argument);
        self.mutex.unlock(io);
        const declared = found orelse return .{ .allowed = false };
        switch (declared.state.load(.acquire)) {
            1 => return .{ .allowed = true },
            2 => return .{ .allowed = false },
            else => {},
        }
        const allowed = evaluate(gpa, declared.subject);
        declared.state.store(if (allowed) 1 else 2, .release);
        return .{ .allowed = allowed, .newly_local = !allowed };
    }
};

/// Run the rule of `subject`. Scratch memory is the call's own.
fn evaluate(gpa: std.mem.Allocator, subject: Subject) bool {
    var scratch: std.heap.ArenaAllocator = .init(gpa);
    defer scratch.deinit();
    var context = subject.context;
    context.arena = scratch.allocator();
    const program = subject.program orelse return evaluateAlone(context, subject);
    if (program.counters) |counted| counted.evaluated();
    switch (subject.which) {
        .ir => {
            if (subject.bare) |known| return program.shareableKnown(context, subject.case, known) catch false;
            return program.shareable(context, subject.case) catch false;
        },
        .program => return (program.executionRefusal(context, subject.case) catch return false) == null,
    }
}

/// The rule of a subject declared without its program's reading (a bench), from the program itself.
fn evaluateAlone(context: receipt.Context, subject: Subject) bool {
    switch (subject.which) {
        .ir => {
            if (subject.bare) |known| return portable.shareableKnown(context, subject.checked, subject.case, known, null) catch false;
            return portable.shareable(context, subject.checked, subject.case, null) catch false;
        },
        .program => return (portable.executionRefusal(context, subject.checked, subject.case, null) catch return false) == null,
    }
}
