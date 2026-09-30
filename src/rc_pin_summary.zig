//! COW-PIN-ELIDE-1: which `mut` list parameters a function provably never shares.
//!
//! A `mut` call pins each collection argument until the callee returns, so a
//! semantic share of it during the call becomes an eager copy and its backing
//! block stays put (`COW-PIN-1`). That pin is only observable when the callee
//! can share the parameter or change its storage. This module finds the
//! functions and parameters for which neither can happen, whole-program and
//! conservatively, and the caller then skips the scope begin, pin and end.
//!
//! The answer for parameter `p` of function `f` is the greatest fixed point of
//! one local test over every function body. The test walks the instructions
//! that name `p` or a compiler temporary filled from it (its family) and
//! accepts only when each of them is one of:
//!
//! - a buffer `length`, `read` or `write` with a family local as its owner;
//! - a `load_local` of a family local whose value, in straight line code with
//!   no branch target in between, is stored into a compiler temporary (which
//!   joins the family) or passed as argument `q` of a direct call to a
//!   function whose parameter `q` is itself in the summary.
//!
//! Everything else that names a family local rejects it: a growth, shrink,
//! iteration, slice or any other buffer operation, a `move`, `drop` or `ref`,
//! a store into a named local (`copy = xs`), a field, list or dictionary
//! store, a return, an `invoke`, or a pass to a read-only parameter.

const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const sources = @import("ownership_sources.zig");
const ownership = @import("ownership_model.zig");
const cow_plan = @import("cow_plan.zig");
const runtime_mode = @import("runtime_mode.zig");

/// The only failure the analysis can meet.
pub const Error = error{OutOfMemory};

/// Per function and per parameter, whether the callee never shares that `mut`
/// list parameter. Empty (all false) outside the RC runtime.
pub const Summary = struct {
    flags: []const []const bool = &.{},

    /// Whether parameter `position` of function `function` is summarised.
    pub fn parameter(self: Summary, function: usize, position: usize) bool {
        const row = self.of(function);
        return position < row.len and row[position];
    }

    /// The per-parameter flags of one function, or none.
    pub fn of(self: Summary, function: usize) []const bool {
        return if (function < self.flags.len) self.flags[function] else &.{};
    }
};

/// Whether parameter `position` of `function` is a `mut` list of plain
/// elements that the caller's uniqueness contract covers: never counted, never
/// a unique-drop resource, never rebound, moved, dropped or referenced.
pub fn plainMutList(program: bytecode.Program, catalog: *shapes.Catalog, function: bytecode.Function, position: usize) bool {
    if (position >= function.signature.parameter_count or position >= function.scope.locals.len) return false;
    const ty = function.scope.locals[position].ty;
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    if (typed.referenceMut(program.records, ty)) return false;
    const record = program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.kind != .list or record.collection.box) return false;
    const shape = catalog.get(record.shape.buffer orelse return false) catch return false;
    if (shape.counted or shape.unique_drop) return false;
    return ownership.uniqueParameter(function, position);
}

/// Summarise every function of `program`. All allocations come from `a`, an
/// arena that outlives the emission.
pub fn compute(a: std.mem.Allocator, program: bytecode.Program, layouts: *native.Catalog) Error!Summary {
    if (!runtime_mode.enabled()) return .{};
    var catalog = try shapes.Catalog.init(a, layouts);
    const rows = try a.alloc([]bool, program.functions.len);
    var any = false;
    for (program.functions, rows, 0..) |function, *row, index| {
        row.* = try a.alloc(bool, function.signature.parameter_count);
        @memset(row.*, false);
        // Positions the emitter looks up by function id must be the array index.
        if (@backingInt(function.id) != index) return .{};
        if (function.physical) |facts| {
            if (!facts.unknown and facts.stable.len == row.*.len) @memcpy(row.*, facts.stable);
            continue;
        }
        if (function.policy.host != null or function.scope.instructions.len == 0) continue;
        for (row.*, 0..) |*flag, position| {
            flag.* = plainMutList(program, &catalog, function, position);
            any = any or flag.*;
        }
    }
    const result = try a.alloc([]const bool, rows.len);
    for (rows, result) |row, *out| out.* = row;
    if (!any) return .{ .flags = result };
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    var changed = true;
    while (changed) {
        changed = false;
        for (program.functions, rows) |function, row| for (row, 0..) |*flag, position| {
            if (!flag.* or function.physical != null) continue;
            defer _ = scratch.reset(.retain_capacity);
            if (try accepts(scratch.allocator(), program, result, function, position)) continue;
            flag.* = false;
            changed = true;
        };
    }
    return .{ .flags = result };
}

/// A local id as an index.
fn li(slot: typed.LocalId) usize {
    return @intCast(@backingInt(slot));
}

/// Whether `slot` names a member of the family.
fn member(family: []const bool, slot: typed.LocalId) bool {
    const index = li(slot);
    return index < family.len and family[index];
}

/// Where a family value went: into a compiler temporary, or into an argument
/// of a call whose callee's parameter is summarised.
const Consumer = union(enum) { store: usize, call };

/// The local test: whether `function` never shares parameter `position`, given
/// `flags` for every function (including this one) taken as true.
fn accepts(a: std.mem.Allocator, program: bytecode.Program, flags: []const []const bool, function: bytecode.Function, position: usize) Error!bool {
    const code = function.scope.instructions;
    const family = try a.alloc(bool, function.scope.locals.len);
    @memset(family, false);
    family[position] = true;
    const targets = try branchTargets(a, code);
    var grew = true;
    while (grew) {
        grew = false;
        for (code, 0..) |instruction, pc| {
            const slot = switch (instruction.op) {
                .load_local => |slot| slot,
                else => continue,
            };
            if (!member(family, slot)) continue;
            const consumer = consume(.{ .program = program, .flags = flags, .function = function, .targets = targets }, pc) orelse return false;
            switch (consumer) {
                .call => {},
                .store => |temp| if (!family[temp]) {
                    family[temp] = true;
                    grew = true;
                },
            }
        }
    }
    for (code) |instruction| switch (instruction.op) {
        .buffer_operation => |operation| if (member(family, operation.owner)) switch (operation.kind) {
            .length, .read, .write => {},
            else => return false,
        },
        .move_local, .drop_local, .ref_local => |slot| if (member(family, slot)) return false,
        .begin_arena, .end_arena => |slot| if (member(family, slot)) return false,
        .resource_io => |io| if (member(family, io.owner)) return false,
        .file_method => |method| if (member(family, method.owner)) return false,
        else => {},
    };
    return true;
}

/// Every instruction some jump, `?` or match arm names.
fn branchTargets(a: std.mem.Allocator, code: []const bytecode.Instruction) Error![]bool {
    const targets = try a.alloc(bool, code.len);
    @memset(targets, false);
    for (code) |instruction| {
        var buffer: [2]usize = undefined;
        for (sources.branchTargets(instruction.op, &buffer)) |target| if (target < code.len) {
            targets[target] = true;
        };
        if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| if (arm.target < code.len) {
            targets[arm.target] = true;
        };
    }
    return targets;
}

/// What one walk needs about the function it reads.
const Walk = struct {
    program: bytecode.Program,
    flags: []const []const bool,
    function: bytecode.Function,
    targets: []const bool,
};

/// Follow the value the `load_local` at `load` pushes through straight line
/// code to the one instruction that pops it, or null when it reaches a branch
/// target, a control transfer or an instruction that may keep it.
fn consume(walk: Walk, load: usize) ?Consumer {
    const code = walk.function.scope.instructions;
    var above: usize = 0;
    var pc = load + 1;
    while (pc < code.len) : (pc += 1) {
        if (walk.targets[pc]) return null;
        const op = code[pc].op;
        const pops = sources.popsOf(walk.program, op);
        if (pops > above) return popper(walk, op, above);
        var buffer: [2]usize = undefined;
        if (!sources.fallsThrough(op) or sources.branchTargets(op, &buffer).len != 0) return null;
        above = above - pops + @intFromBool(sources.pushes(op));
    }
    return null;
}

/// Whether `op`, which pops the tracked value with `above` values over it, is
/// an accepted consumer of it.
fn popper(walk: Walk, op: sources.Op, above: usize) ?Consumer {
    switch (op) {
        .store_local => |slot| {
            const target = li(slot);
            if (target >= walk.function.scope.locals.len) return null;
            if (!cow_plan.temporary(walk.function, @intCast(target))) return null;
            return .{ .store = target };
        },
        .call => |callee| {
            const index: usize = @intCast(@backingInt(callee));
            if (index >= walk.program.functions.len) return null;
            const count = walk.program.functions[index].signature.parameter_count;
            if (above >= count) return null;
            const summarised = index < walk.flags.len and count - 1 - above < walk.flags[index].len and walk.flags[index][count - 1 - above];
            return if (summarised) .call else null;
        },
        else => return null,
    }
}
