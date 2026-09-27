//! Loop versioning (`QBE-LOOP-VERSION-1`): the native lowering of the facts
//! `qbe_loop_facts.zig` plans for one innermost loop.
//!
//! Every entry to a versioned loop lands on its guard, which evaluates the
//! plan's steps in order. When all of them hold, control enters a copy of the
//! loop lowered under the plan's per-instruction actions: proven index and
//! overflow checks are omitted, a negative-index normalization the guard
//! proved dead is a plain jump, a proven iteration check is nothing, an
//! invariant element read uses the value the guard read, and a stable
//! collection's element storage address is the one the guard loaded. When any
//! step fails, control enters the original loop, lowered exactly as it was
//! before versioning existed, so a trap the original would raise is raised by
//! the original, at the same iteration, with the same message and trace.
//!
//! Labels: the guard takes the header's own label `@i<head>`, so every jump
//! that entered the loop now enters the guard; the copy's instructions are
//! `@fi<pc>`, and the original header becomes `@oi<head>`, which only its own
//! back edge and a failing guard name.
const std = @import("std");
const facts = @import("qbe_loop_facts.zig");
const read_version = @import("qbe_rc_read_version.zig");
const operands = @import("qbe_loop_operands.zig");
const rc_append_loop = @import("qbe_rc_append_loop.zig");

/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Where the element storage address, the capacity and the generation sit in
/// a list header (`native_collections.h`).
const storage_offset = 32;
const capacity_offset = 8;
const generation_offset = 16;

/// The check-free copy being lowered: its loop, and the temporaries holding the
/// guard's values and storage addresses, per plan node.
pub const Active = struct {
    loop: *const facts.Loop,
    values: []?usize,
    storages: []?usize,
    /// For a loop with a presized append, the temporaries carrying its list's
    /// length and generation from one iteration to the next.
    appending: ?Appending = null,
    /// Exact RC read effects admitted only while emitting this guarded copy.
    read: ?read_version.Certificate = null,
};

/// The mutable temporaries a presized append advances.
pub const Appending = struct { length: usize, generation: usize };

/// Bind versioned-loop lowering to the concrete emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Emit the guard and the check-free copy of `loop` in front of its
        /// header. Returns false, having emitted nothing, when the copy turned
        /// out to allocate after all, so the caller lowers the loop once, as
        /// before.
        pub fn emit(self: *E, loop: *const facts.Loop) Error!bool {
            return atHead(E, self, loop, emitHere);
        }

        fn emitHere(self: *E, loop: *const facts.Loop) Error!bool {
            // Existing hoist/scalar admissions keep their original protocol.
            const previous = !@import("runtime_mode.zig").enabled() or
                @import("qbe_rc_readonly_calls.zig").body(E, self) or
                @import("qbe_rc_hoist.zig").permitsVersion(E, self, loop.head, loop.back) or
                @import("qbe_rc_scalar_version.zig").proven(E, self, loop.head, loop.back);
            const read_proof = if (previous) null else read_version.certify(E, self, loop.head, loop.back);
            if (!previous and read_proof == null) return false;
            const nodes = self.loop_plan.nodes;
            const values = try self.allocator.alloc(?usize, nodes.len);
            @memset(values, null);
            const storages = try self.allocator.alloc(?usize, nodes.len);
            @memset(storages, null);
            var active: Active = .{ .loop = loop, .values = values, .storages = storages, .read = read_proof };
            const main = self.output;
            self.output = .init(self.allocator);
            const fused = self.fused;
            defer self.fused = fused;
            var keep = false;
            defer if (!keep) {
                self.output.deinit();
                self.output = main;
            };
            try self.headerLabel(loop.head, "i");
            if (read_proof) |proof| try read_version.guard(E, self, proof, loop.head);
            for (loop.guard) |step| try guardStep(self, &active, step);
            // Everything the copy reads from the guard is computed once the
            // whole guard has held, so an element is read only after the step
            // that bounds its index.
            for (loop.actions) |action| {
                if (action.value) |node| _ = try value(self, &active, node);
                if (action.receiver) |node| _ = try storage(self, &active, node);
                if (action.effect == .presized) try appendState(self, &active, action.receiver.?);
            }
            try self.print(" jmp @fi{d}\n", .{loop.head});
            const guard_end = self.output.writer.end;
            self.version = &active;
            defer self.version = null;
            var pc = loop.head;
            while (pc <= loop.back) : (pc += 1) {
                if (!loop.actions[pc - loop.head].dead) try self.emitAt(pc);
            }
            const text = self.output.writer.buffer[0..self.output.writer.end];
            if (self.copyAllocates(text[guard_end..])) return false;
            if (read_proof != null and !read_version.quietCopy(text[guard_end..])) return false;
            const isolated = operands.certify(E, self, loop, read_proof, text[guard_end..]);
            keep = true;
            var copy = self.output;
            self.output = main;
            try self.print("{s}", .{copy.writer.buffer[0..guard_end]});
            if (isolated) try operands.begin(E, self, loop);
            try self.print("{s}", .{copy.writer.buffer[guard_end..copy.writer.end]});
            if (isolated) try operands.end(E, self, loop);
            copy.deinit();
            return true;
        }

        fn guardStep(self: *E, active: *Active, step: facts.Step) Error!void {
            const flag = self.temp();
            switch (step) {
                .bounded => |node| {
                    const shifted = self.temp();
                    const bias = @as(u64, 1) << active.loop.bits;
                    try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =l culel %v{d}, {d}\n", .{ shifted, try value(self, active, node), bias, flag, shifted, 2 * bias });
                },
                .at_least => |bound| try self.print(" %v{d} =l csgel %v{d}, {d}\n", .{ flag, try value(self, active, bound.value), bound.minimum }),
                .order => |order| {
                    const comparison: []const u8 = switch (order.relation) {
                        .at_most => "cslel",
                        .below => "csltl",
                        .within => "cultl",
                        .equal => "ceql",
                    };
                    try self.print(" %v{d} =l {s} %v{d}, %v{d}\n", .{ flag, comparison, try value(self, active, order.value), try value(self, active, order.limit) });
                },
                .spans => |span| try spans(self, active, span, flag),
                .room => |room| try spare(self, active, room, flag),
            }
            try self.print(" jnz %v{d}, @guard{d}, @oi{d}\n@guard{d}\n", .{ flag, flag, active.loop.head, flag });
        }

        /// `flag = bound > entry and bound - entry >=u minimum`: with the
        /// signed test first, the unsigned difference is exact.
        fn spans(self: *E, active: *Active, span: @FieldType(facts.Step, "spans"), flag: usize) Error!void {
            const entry = try value(self, active, span.entry);
            const bound = try value(self, active, span.bound);
            const ahead = self.temp();
            const distance = self.temp();
            const long = self.temp();
            try self.print(" %v{d} =l csgtl %v{d}, %v{d}\n %v{d} =l sub %v{d}, %v{d}\n", .{ ahead, bound, entry, distance, bound, entry });
            try self.print(" %v{d} =l cugel %v{d}, {d}\n %v{d} =l and %v{d}, %v{d}\n", .{ long, distance, span.minimum, flag, ahead, long });
        }

        /// `flag = capacity - length >=u bound - entry (+1 when inclusive)`.
        /// It follows the span step, so `bound - entry` is positive and exact,
        /// and a list's length never exceeds its capacity.
        fn spare(self: *E, active: *Active, room: @FieldType(facts.Step, "room"), flag: usize) Error!void {
            const header = try value(self, active, room.list);
            const capacity_field = self.temp();
            const capacity = self.temp();
            const free = self.temp();
            const trips = self.temp();
            try self.markObject(header);
            try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =l loadl %v{d}\n", .{ capacity_field, header, capacity_offset, capacity, capacity_field });
            try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l sub %v{d}, %v{d}\n", .{ free, header, free, capacity, free });
            try self.print(" %v{d} =l sub %v{d}, %v{d}\n", .{ trips, try value(self, active, room.bound), try value(self, active, room.entry) });
            if (room.inclusive) try self.print(" %v{d} =l add %v{d}, 1\n", .{ trips, trips });
            try self.print(" %v{d} =l cugel %v{d}, %v{d}\n", .{ flag, free, trips });
        }

        /// The running length and generation of the list a presized append
        /// extends, read once the guard holds; the copy advances both.
        fn appendState(self: *E, active: *Active, list: facts.NodeId) Error!void {
            const header = try value(self, active, list);
            const generation_field = self.temp();
            const length = self.temp();
            const generation = self.temp();
            try self.markObject(header);
            try self.print(" %v{d} =l loadl %v{d}\n %v{d} =l add %v{d}, {d}\n %v{d} =l loadl %v{d}\n", .{ length, header, generation_field, header, generation_offset, generation, generation_field });
            // RC-PRESIZED-APPEND-1: an RC copy may presize only a certified
            // quiet scalar append loop, after the runtime admits the list once.
            if (!try rc_append_loop.presized(E, self, .{ .head = active.loop.head, .header = header, .generation = generation, .root = self.loop_plan.nodes[list] })) return;
            active.appending = .{ .length = length, .generation = generation };
        }

        /// The temporary holding one plan value, computed on first use.
        fn value(self: *E, active: *Active, id: facts.NodeId) Error!usize {
            if (active.values[id]) |temp| return temp;
            const result = switch (self.loop_plan.nodes[id]) {
                .constant => |number| blk: {
                    const temp = self.temp();
                    try self.print(" %v{d} =l copy {d}\n", .{ temp, number });
                    break :blk temp;
                },
                .leaf => |leaf| switch (leaf.kind) {
                    .local, .entry => try self.load("l", leaf.slot),
                    else => return error.InternalError,
                },
                .length => |object| blk: {
                    const header = try value(self, active, object);
                    const temp = self.temp();
                    try self.markObject(header);
                    try self.print(" %v{d} =l loadl %v{d}\n", .{ temp, header });
                    break :blk temp;
                },
                .element => |element| blk: {
                    const base = try storage(self, active, element.receiver);
                    const index = try value(self, active, element.index);
                    const record = self.program.records[element.collection.recordIndex()];
                    const stride = (try self.layout(record.shape.buffer.?)).size;
                    const offset = self.temp();
                    const address = self.temp();
                    const temp = self.temp();
                    try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n %v{d} =l loadl %v{d}\n", .{ offset, index, stride, address, base, offset, temp, address });
                    try self.markObject(temp);
                    break :blk temp;
                },
                .operation => |operation| blk: {
                    const left = try value(self, active, operation.left);
                    const right = try value(self, active, operation.right);
                    const temp = self.temp();
                    try self.print(" %v{d} =l {s} %v{d}, %v{d}\n", .{ temp, @tagName(operation.operator), left, right });
                    break :blk temp;
                },
                else => return error.InternalError,
            };
            active.values[id] = result;
            return result;
        }

        /// The temporary holding a stable collection's element storage address.
        fn storage(self: *E, active: *Active, id: facts.NodeId) Error!usize {
            if (active.storages[id]) |temp| return temp;
            const header = try value(self, active, id);
            const field = self.temp();
            const temp = self.temp();
            try self.markObject(header);
            try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =l loadl %v{d}\n", .{ field, header, storage_offset, temp, field });
            // The element storage block, with its element layout, as every
            // other storage load names it (LLVM-ELEMENT-CLASS-1).
            try self.markElements(temp, try elementType(self, id));
            active.storages[id] = temp;
            return temp;
        }

        /// The element type of the list or byte string plan node `id` names.
        fn elementType(self: *E, id: facts.NodeId) Error!@import("typed.zig").Type {
            const collection = switch (self.loop_plan.nodes[id]) {
                .leaf => |leaf| self.function.scope.locals[leaf.slot].ty,
                .element => |element| self.program.records[element.collection.recordIndex()].shape.buffer.?,
                else => return error.InternalError,
            };
            return self.program.records[collection.recordIndex()].shape.buffer orelse error.InternalError;
        }
    };
}

// Guard queries use the header's physical proof context, never the preceding
// instruction's PC. Trial emission may advance it; restore on every outcome.
fn atHead(comptime E: type, self: *E, loop: *const facts.Loop, comptime body: fn (*E, *const facts.Loop) Error!bool) Error!bool {
    const saved = self.pc;
    self.pc = loop.head;
    defer self.pc = saved;
    return body(self, loop);
}

const PcProbe = struct {
    pc: usize,
    observed: ?usize = null,
    outcome: enum { accepted, refused, failed },

    fn guard(self: *PcProbe, loop: *const facts.Loop) Error!bool {
        self.observed = self.pc;
        // Model a speculative body reaching its final operation before return.
        self.pc = loop.back;
        return switch (self.outcome) {
            .accepted => true,
            .refused => false,
            .failed => error.OutOfMemory,
        };
    }
};

// spec-case: QBE-LOOP-VERSION-1
// spec-case: RC-DICTIONARY-EMPTY-DROPS-1
test "RC loop guard PC observes head and restores after success refusal and error" {
    const t = std.testing;
    const loop: facts.Loop = .{ .head = 40, .back = 60, .bits = 8, .guard = &.{}, .actions = &.{} };
    var probe: PcProbe = .{ .pc = 39, .outcome = .accepted };
    try t.expect(try atHead(PcProbe, &probe, &loop, PcProbe.guard));
    try t.expectEqual(@as(?usize, 40), probe.observed);
    try t.expectEqual(@as(usize, 39), probe.pc);
    probe.outcome = .refused;
    try t.expect(!try atHead(PcProbe, &probe, &loop, PcProbe.guard));
    try t.expectEqual(@as(?usize, 40), probe.observed);
    try t.expectEqual(@as(usize, 39), probe.pc);
    probe.outcome = .failed;
    try t.expectError(error.OutOfMemory, atHead(PcProbe, &probe, &loop, PcProbe.guard));
    try t.expectEqual(@as(?usize, 40), probe.observed);
    try t.expectEqual(@as(usize, 39), probe.pc);
}
