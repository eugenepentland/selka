//! Allocation-free dictionary lookup keys (`DICT-RANGE-KEY-1`).
//!
//! `counts[seq[i:i + k]]`, `counts.get(key, 0)` with `key = seq[i:i + k]`, and
//! `key in counts` used to build a fresh `str` per slice only to hash it, compare
//! it and — for most lookups — drop it. A slice whose value is never anything
//! but the key of a `str`-keyed dictionary operation is now *described* instead
//! of built: its operand slot holds the text it ranges over, and a 16-byte span
//! beside the slot holds the octet offset and length `myl_native_text_range`
//! computed with the slice's own clamping. The dictionary hashes and compares
//! those octets in place, and a `write` of a key that turns out to be new builds
//! the one owned key it stores.
//!
//! The value is a range value only where the proof below holds, so no other
//! instruction ever sees the difference:
//!
//!  1. A *producer* is a `str` slice, or a read of a range local. Its value is
//!     consumed, falling through with no branch into the window, by the next
//!     instruction — a `store_local` into a range local — or by a dictionary
//!     read, `get`, `contains`, `write` or index whose key operand is exactly
//!     the producer's slot, with at most two plain pushes (a constant or a
//!     local read) in between, which cannot touch that slot.
//!  2. A *range local* is a non-parameter `str` local that nothing names but a
//!     `store_local` fed by a producer, a `load_local` that is a producer, and a
//!     clearing `drop_local`. The set is the greatest fixpoint: a local whose
//!     read feeds a local that drops out drops out too.
//!
//! The slot keeps a real managed text — the receiver — so every root, frame
//! map, liveness answer and clearing store treats it exactly as it treated the
//! slice, and the receiver stays alive for as long as the key could be read. A
//! program that opens an arena is left alone: a slice built inside one is an
//! arena object the store barrier refuses to put in an outer dictionary, and a
//! described slice would not be.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");

const Op = @FieldType(bytecode.Instruction, "op");

/// What one instruction does with a range value.
pub const Role = enum(u8) {
    /// Nothing: lowered as before.
    none,
    /// A slice that describes itself instead of building a text.
    slice,
    /// A read of a range local, which copies its span beside the operand.
    load,
    /// A store into a range local, which copies the operand's span with it.
    store,
    /// A dictionary operation whose key operand is a range value.
    key,
};

/// The roles of one function's instructions and the spans its frame declares.
pub const Plan = struct {
    /// Per instruction, its role; empty when the function has no range value.
    roles: []const Role = &.{},
    /// Per local, whether it is a range local and so declares `%rl{i}`.
    locals: []const bool = &.{},
    /// Per operand stack height, whether a range value lives there and so the
    /// frame declares `%rs{h}`.
    heights: []const bool = &.{},

    /// The role of the instruction at `pc`.
    pub fn role(self: Plan, pc: usize) Role {
        return if (pc < self.roles.len) self.roles[pc] else .none;
    }
    /// Bytes of span storage the frame declares: 16 per range local and per
    /// range height.
    pub fn frameBytes(self: Plan) u64 {
        var count: u64 = 0;
        for (self.locals) |used| count += @intFromBool(used);
        for (self.heights) |used| count += @intFromBool(used);
        return count * 16;
    }
};

/// What the analysis reads about the function being lowered.
pub const Input = struct {
    program: bytecode.Program,
    function: bytecode.Function,
    /// The validator's operand stack before each instruction; null where
    /// unreachable.
    states: []const ?[]const typed.Type,
    /// Per instruction, whether a branch reaches it directly.
    branch_targets: []const bool,
    /// Per local, whether its slot holds an address rather than its value.
    by_reference: []const bool,
};

/// Where one producer's value goes.
const Use = union(enum) { store: usize, key: usize };

/// Find every range value in one function. `arenas` says whether the program
/// opens any arena, in which case nothing is planned.
pub fn plan(allocator: std.mem.Allocator, input: Input, arenas: bool) std.mem.Allocator.Error!Plan {
    if (arenas) return .{};
    const code = input.function.scope.instructions;
    const locals = input.function.scope.locals;
    const candidate = try allocator.alloc(bool, locals.len);
    for (locals, 0..) |local, index| candidate[index] = index >= input.function.signature.parameter_count and
        isText(input.program, local.ty) and !(index < input.by_reference.len and input.by_reference[index]);
    for (code, 0..) |instruction, pc| {
        if (input.states[pc] == null) continue;
        switch (instruction.op) {
            .store_local, .load_local, .drop_local => {},
            else => for (candidate, 0..) |*keep, index| {
                keep.* = keep.* and !mentions(instruction.op, index);
            },
        }
    }
    while (settle(input, candidate)) {}
    var roles = try allocator.alloc(Role, code.len);
    @memset(roles, .none);
    var capacity: usize = 0;
    for (input.states) |state| if (state) |stack| {
        capacity = @max(capacity, stack.len + 1);
    };
    const heights = try allocator.alloc(bool, capacity);
    @memset(heights, false);
    var any = false;
    for (code, 0..) |instruction, pc| {
        const stack = input.states[pc] orelse continue;
        const height: usize = switch (instruction.op) {
            .buffer_operation => |operation| if (isSlice(input, operation)) stack.len - 2 else continue,
            .load_local => |slot| if (candidate[@backingInt(slot)]) stack.len else continue,
            .store_local => |slot| {
                if (candidate[@backingInt(slot)]) roles[pc] = .store;
                continue;
            },
            else => continue,
        };
        const use = consumer(input, pc, height) orelse continue;
        if (!usable(use, candidate)) continue;
        roles[pc] = if (instruction.op == .load_local) .load else .slice;
        heights[height] = true;
        switch (use) {
            .key => |at| roles[at] = .key,
            .store => {},
        }
        any = true;
    }
    if (!any) return .{};
    return .{ .roles = roles, .locals = candidate, .heights = heights };
}

/// Drop every candidate one of whose stores or reads breaks the rule, and say
/// whether any was dropped; repeated until nothing is, it leaves the greatest
/// set of range locals.
fn settle(input: Input, candidate: []bool) bool {
    var changed = false;
    for (input.function.scope.instructions, 0..) |instruction, pc| {
        const stack = input.states[pc] orelse continue;
        const index, const keeps = switch (instruction.op) {
            .store_local => |slot| .{ @backingInt(slot), storedFromProducer(input, candidate, pc, @backingInt(slot)) },
            .load_local => |slot| .{ @backingInt(slot), usable(consumer(input, pc, stack.len), candidate) },
            else => continue,
        };
        if (!candidate[index] or keeps) continue;
        candidate[index] = false;
        changed = true;
    }
    return changed;
}
/// Whether a producer's use keeps its value a range value.
fn usable(use: ?Use, candidate: []const bool) bool {
    const found = use orelse return false;
    return switch (found) {
        .key => true,
        .store => |index| candidate[index],
    };
}

/// Whether the store at `pc` into range-local candidate `index` takes the value
/// a producer pushed immediately before it.
fn storedFromProducer(input: Input, candidate: []const bool, pc: usize, index: usize) bool {
    if (pc == 0 or input.branch_targets[pc]) return false;
    const stack = input.states[pc - 1] orelse return false;
    const producer = input.function.scope.instructions[pc - 1].op;
    switch (producer) {
        .buffer_operation => |operation| if (!isSlice(input, operation)) return false,
        .load_local => |slot| if (!candidate[@backingInt(slot)]) return false,
        else => return false,
    }
    const height = if (producer == .load_local) stack.len else stack.len - 2;
    const use = consumer(input, pc - 1, height) orelse return false;
    return switch (use) {
        .store => |target| target == index,
        .key => false,
    };
}

/// Where the value a producer at `pc` leaves at stack height `height` goes: the
/// store that immediately follows it, or the dictionary operation that reads it
/// as its key after at most two plain pushes, all reached by falling through.
fn consumer(input: Input, pc: usize, height: usize) ?Use {
    const code = input.function.scope.instructions;
    var at = pc + 1;
    var skipped: usize = 0;
    while (at < code.len) : (at += 1) {
        const stack = input.states[at] orelse return null;
        if (input.branch_targets[at]) return null;
        const op = code[at].op;
        if (at == pc + 1) switch (op) {
            .store_local => |slot| return .{ .store = @backingInt(slot) },
            else => {},
        };
        if (keyOperand(input, op, stack.len) == height) return .{ .key = at };
        switch (op) {
            .push_i64, .push_integer, .push_bool, .push_unit, .load_local => {},
            else => return null,
        }
        skipped += 1;
        if (skipped > 2) return null;
    }
    return null;
}

/// The stack height of the key operand a `str`-keyed dictionary lookup or write
/// reads, or null for any other instruction.
fn keyOperand(input: Input, op: Op, depth: usize) ?usize {
    switch (op) {
        .buffer_operation => |operation| {
            const arity: usize = switch (operation.kind) {
                .read, .contains => 1,
                .get, .write => 2,
                else => return null,
            };
            if (!textKeyed(input.program, input.function.scope.locals[@backingInt(operation.owner)].ty)) return null;
            return depth - arity;
        },
        .get_index => |ty| return if (textKeyed(input.program, ty)) depth - 1 else null,
        else => return null,
    }
}

/// Whether a buffer operation is a `str` slice.
fn isSlice(input: Input, operation: @FieldType(Op, "buffer_operation")) bool {
    return operation.kind == .slice and isText(input.program, input.function.scope.locals[@backingInt(operation.owner)].ty);
}

/// Whether a type is `str`.
fn isText(program: bytecode.Program, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = program.records[ty.recordIndex()];
    return record.managed and record.collection.kind == .string;
}

/// Whether a type is a dictionary with `str` keys.
fn textKeyed(program: bytecode.Program, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = program.records[ty.recordIndex()];
    if (!record.managed or record.collection.kind != .dictionary) return false;
    return isText(program, record.collection.key orelse return false);
}

/// Whether an instruction names local `index` in any way.
fn mentions(op: Op, index: usize) bool {
    switch (op) {
        .begin_arena, .end_arena, .move_local, .drop_local, .load_local, .ref_local, .store_local => |other| return @backingInt(other) == index,
        .buffer_operation => |operation| return @backingInt(operation.owner) == index,
        .resource_io => |operation| return @backingInt(operation.owner) == index,
        .file_method => |method| return @backingInt(method.owner) == index,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |bound| if (@backingInt(bound) == index) return true;
        },
        else => {},
    }
    return false;
}

/// Lowering of the four roles, bound to the concrete emitter.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Describe `input[start:end]` into the span at height `base` and leave
        /// the receiver itself as the operand.
        pub fn slice(self: *E, input: usize, base: usize) !void {
            const start = try self.load("s", base);
            const end = try self.load("s", base + 1);
            try self.print(" call $myl_native_text_range(l %v{d}, l %v{d}, l %v{d}, l %rs{d})\n", .{ input, start, end, base });
            try self.store(base, input);
        }
        /// Carry a range local's span onto the operand it was just read into.
        pub fn load(self: *E, index: usize, height: usize) !void {
            try self.print(" blit %rl{d}, %rs{d}, 16\n", .{ index, height });
        }
        /// Carry the stored operand's span into the range local.
        pub fn store(self: *E, index: usize, height: usize) !void {
            try self.print(" blit %rs{d}, %rl{d}, 16\n", .{ height, index });
        }
        /// Look up or write the range value at height `key` in `dictionary`.
        /// `kind` is the dictionary operation; `value` is the written value's
        /// pointer, and `result` receives the runtime's answer.
        pub fn access(self: *E, access_: Access) !void {
            const text = try self.load("s", access_.key);
            switch (access_.kind) {
                .read => try self.print(" %v{d} =w call $myl_native_dictionary_read_range(l %heap, l %v{d}, l %v{d}, l %rs{d}, l %agg{d})\n", .{ access_.result, access_.dictionary, text, access_.key, self.pc }),
                .contains => try self.print(" %v{d} =w call $myl_native_dictionary_contains_range(l %heap, l %v{d}, l %v{d}, l %rs{d})\n", .{ access_.result, access_.dictionary, text, access_.key }),
                .overwrite => try self.print(" %v{d} =w call $myl_native_dictionary_overwrite_range(l %heap, l %v{d}, l %v{d}, l %rs{d}, l %v{d})\n", .{ access_.result, access_.dictionary, text, access_.key, access_.value }),
                .write => try self.print(" %v{d} =w call $myl_native_dictionary_write_range(l %heap, l %v{d}, l %v{d}, l %rs{d}, l %v{d})\n", .{ access_.result, access_.dictionary, text, access_.key, access_.value }),
            }
        }
    };
}

/// One dictionary operation on a range key.
pub const Access = struct {
    /// Which runtime entry point answers it: `overwrite` is the half of a
    /// write that allocates nothing and answers whether the key was present.
    kind: enum { read, contains, overwrite, write },
    /// The temporary holding the dictionary.
    dictionary: usize,
    /// The operand height of the key, whose span is `%rs{key}`.
    key: usize,
    /// The written value's pointer; unused by the lookups.
    value: usize = 0,
    /// The temporary that receives the runtime's answer.
    result: usize,
};
