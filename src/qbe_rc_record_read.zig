//! Retained record homes lend scalar-list fields across a closed checked read.
const std = @import("std");
const frame = @import("qbe_rc_frame.zig");
const model = @import("rc_record_read.zig");
/// Errors shared by ordinary lowering and speculative text buffers.
pub const Error = frame.Error;

/// Lower in isolated state; a refused generated call keeps ordinary lowering.
pub fn emit(comptime E: type, self: *E, pc: usize) Error!?usize {
    const state = frame.get(E, self) orelse return null;
    if (self.version != null or self.original != null or self.fused != null) return null;
    if (self.layouts.states.len > 4096) return null;
    for (state.plan.records.reads, 0..) |proof, index| {
        if (proof.start != pc) continue;
        var trial = self.*;
        trial.output = .init(self.allocator);
        defer trial.output.deinit();
        trial.scratch = .init(self.allocator);
        defer trial.scratch.deinit();
        // Layout/shape lookups are lazy; even their memo writes stay private.
        var layouts = self.layouts.*;
        layouts.layouts = try self.allocator.dupe(@TypeOf(layouts.layouts[0]), layouts.layouts);
        defer self.allocator.free(layouts.layouts);
        layouts.states = try self.allocator.dupe(@TypeOf(layouts.states[0]), layouts.states);
        defer self.allocator.free(layouts.states);
        defer for (self.layouts.states, layouts.states, layouts.layouts) |before, after, value| {
            if (before != .done and after == .done) layouts.releaseLayout(value);
        };
        trial.layouts = &layouts;
        var cow = self.cow.?.*;
        cow.captures = try self.allocator.dupe(@TypeOf(cow.captures[0]), cow.captures);
        defer self.allocator.free(cow.captures);
        trial.cow = &cow;
        var rc = state.*;
        rc.catalog.native = &layouts;
        rc.catalog.shapes = try self.allocator.dupe(@TypeOf(rc.catalog.shapes[0]), rc.catalog.shapes);
        defer self.allocator.free(rc.catalog.shapes);
        cow.rc = &rc;
        rc.plan.records.reads = try self.allocator.dupe(model.Certificate, rc.plan.records.reads);
        defer self.allocator.free(rc.plan.records.reads);
        rc.plan.records.reads[index].active = true;
        trial.by_reference = try self.allocator.dupe(@TypeOf(trial.by_reference[0]), self.by_reference);
        defer self.allocator.free(trial.by_reference);
        const spec = if (proof.home == .incoming) "RC-CALLER-FIELD-READ-1" else "RC-RECORD-FIELD-READ-1";
        try trial.print(" # {s} root {d} capture {d}\n", .{ spec, proof.root, proof.capture });
        for (proof.start..proof.end + 1) |at| try trial.emitAt(at);
        const text = trial.output.written();
        if (!@import("qbe_rc_closed_text.zig").quietCopy(text)) return null;
        // No admitted operation changes frame maps, aggregate storage, plans,
        // version contexts or publication flags. Only SSA IDs escape the trial.
        try self.print("{s}", .{text});
        self.serial = trial.serial;
        return proof.end;
    }
    return null;
}

fn active(comptime E: type, self: *E) ?model.Certificate {
    const state = frame.get(E, self) orelse return null;
    for (state.plan.records.reads) |proof| {
        if (proof.active and self.pc >= proof.start and self.pc <= proof.end) return proof;
    }
    return null;
}

/// Both the list and subsequent scalar field projections consume a raw root.
/// Their operand guard is empty throughout this isolated interval.
pub fn projection(comptime E: type, self: *E) bool {
    return active(E, self) != null;
}

/// The sole capture writer transfers raw bits while its retained slot stays empty.
pub fn store(comptime E: type, self: *E, local: usize, operand: usize) Error!bool {
    const proof = active(E, self) orelse return false;
    if (self.pc != proof.start + 2 or local != proof.capture or operand != 0) return false;
    try self.print(" storel %v{d}, %l{d}\n", .{ try self.load("s", operand), local });
    return true;
}

/// The unchanged frame journal still contains this provably empty capture.
pub fn empty(comptime E: type, self: *E, local: usize) bool {
    const proof = active(E, self) orelse return false;
    return local == proof.capture;
}
