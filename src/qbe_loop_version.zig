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

/// Errors reported while emitting native operations.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };

/// Where the element storage address sits in a list or byte string header.
const storage_offset = 32;

/// The check-free copy being lowered: its loop, and the temporaries holding the
/// guard's values and storage addresses, per plan node.
pub const Active = struct {
    loop: *const facts.Loop,
    values: []?usize,
    storages: []?usize,
};

/// Bind versioned-loop lowering to the concrete emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Emit the guard and the check-free copy of `loop` in front of its
        /// header. Returns false, having emitted nothing, when the copy turned
        /// out to allocate after all, so the caller lowers the loop once, as
        /// before.
        pub fn emit(self: *E, loop: *const facts.Loop) Error!bool {
            const nodes = self.loop_plan.nodes;
            const values = try self.allocator.alloc(?usize, nodes.len);
            @memset(values, null);
            const storages = try self.allocator.alloc(?usize, nodes.len);
            @memset(storages, null);
            var active: Active = .{ .loop = loop, .values = values, .storages = storages };
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
            for (loop.guard) |step| try guardStep(self, &active, step);
            // Everything the copy reads from the guard is computed once the
            // whole guard has held, so an element is read only after the step
            // that bounds its index.
            for (loop.actions) |action| {
                if (action.value) |node| _ = try value(self, &active, node);
                if (action.receiver) |node| _ = try storage(self, &active, node);
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
            keep = true;
            var copy = self.output;
            self.output = main;
            try self.print("{s}", .{copy.writer.buffer[0..copy.writer.end]});
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
                .at_most => |pair| try self.print(" %v{d} =l cslel %v{d}, %v{d}\n", .{ flag, try value(self, active, pair.value), try value(self, active, pair.limit) }),
                .below => |pair| try self.print(" %v{d} =l csltl %v{d}, %v{d}\n", .{ flag, try value(self, active, pair.value), try value(self, active, pair.limit) }),
                .within => |pair| try self.print(" %v{d} =l cultl %v{d}, %v{d}\n", .{ flag, try value(self, active, pair.value), try value(self, active, pair.limit) }),
                .equal => |pair| try self.print(" %v{d} =l ceql %v{d}, %v{d}\n", .{ flag, try value(self, active, pair.left), try value(self, active, pair.right) }),
            }
            try self.print(" jnz %v{d}, @guard{d}, @oi{d}\n@guard{d}\n", .{ flag, flag, active.loop.head, flag });
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
            try self.markObject(temp);
            active.storages[id] = temp;
            return temp;
        }
    };
}
