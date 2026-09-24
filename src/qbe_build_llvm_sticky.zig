//! Checked loops with no branch per check (LLVM-STICKY-REDUCTION-1), ported
//! from the adapter's `sticky_loops.py` for the Zig translator (LLVM-ZIG-1).
//!
//! A qualifying innermost loop is versioned on the IL before translation: its
//! entry edges go to a fast copy in which an ordinary overflow check is
//! sticky (OR-ed into one word) and a reduction's check is dropped while the
//! loop sums the magnitudes it adds. Every normal exit of the fast copy
//! verifies that no dropped check could have fired; otherwise, and on every
//! would-be trap, the fallback restores every frame cell the loop writes and
//! runs the original, untouched loop, which traps exactly as before.
const std = @import("std");
const il = @import("qbe_build_llvm_il.zig");
const classes = @import("qbe_build_llvm_classes.zig");

const Allocator = std.mem.Allocator;
const Error = il.Error;
const Instruction = il.Instruction;
const Operand = il.Operand;
const Block = il.Block;
const Labels = std.array_hash_map.String(void);
/// `%A =l add %B, %C`.
const add_line = "{s} =l add {s}, {s}";
/// `%A =l copy 0`.
const zero_line = "{s} =l copy 0";
/// `%A =l culel %B, N`: whether B is at most N, unsigned.
const at_most_line = "{s} =l culel {s}, {d}";

/// The helper an overflow check traps through.
const overflow_helper = "myl_qbe_fail_overflow_op";
/// The largest signed 64-bit value.
const max_signed: u64 = (1 << 63) - 1;

/// Why a loop is left alone.
const Verdict = error{Declined};
const AnalysisError = Error || Verdict;

/// The 64-bit integer a literal operand denotes, or null.
fn constantValue(value: Operand) ?u64 {
    const literal = switch (value) {
        .constant => |known| known,
        else => return null,
    };
    if (literal.qbe_type != null and std.mem.eql(u8, literal.qbe_type.?, "extern")) return null;
    return il.pythonInt(literal.text);
}

fn signed(value: u64) i64 {
    return @bitCast(value);
}

/// Blocks, explicit successors (fall-through included) and predecessors.
const Cfg = struct {
    blocks: []const *Block,
    by_label: std.StringHashMapUnmanaged(*Block) = .empty,
    following: std.StringHashMapUnmanaged(?[]const u8) = .empty,
    successors: std.StringHashMapUnmanaged([]const []const u8) = .empty,
    predecessors: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty,

    fn of(arena: Allocator, function: *const il.Function) Error!Cfg {
        var self: Cfg = .{ .blocks = try arena.dupe(*Block, function.blocks.items) };
        for (self.blocks, 0..) |block, index| {
            const next = if (index + 1 < self.blocks.len) self.blocks[index + 1].label else null;
            try self.by_label.put(arena, block.label, block);
            try self.following.put(arena, block.label, next);
            try self.successors.put(arena, block.label, try successorsOf(arena, block, next));
            try self.predecessors.put(arena, block.label, .empty);
        }
        for (self.blocks) |block| for (self.successors.get(block.label).?) |successor| {
            const list = self.predecessors.getPtr(successor) orelse continue;
            try list.append(arena, block.label);
        };
        return self;
    }

    fn successorsOf(arena: Allocator, block: *const Block, next: ?[]const u8) Error![]const []const u8 {
        var out: std.ArrayList([]const u8) = .empty;
        const terminator = block.terminator();
        const opcode: ?il.Opcode = if (terminator) |last| last.opcode else null;
        if (opcode == .jmp) {
            try out.append(arena, terminator.?.extra.label);
        } else if (opcode == .jnz) {
            const targets = terminator.?.extra.branch;
            try out.append(arena, targets[0]);
            if (!std.mem.eql(u8, targets[0], targets[1])) try out.append(arena, targets[1]);
        } else if (opcode != .ret and opcode != .hlt) {
            if (next) |label| try out.append(arena, label);
        }
        return out.items;
    }
};

/// The fail-helper call a trap block makes: only `dbgloc` lines, one
/// `call $myl_qbe_fail_*` and `hlt`.
fn trapCall(block: *const Block) ?*Instruction {
    var body: [2]*Instruction = undefined;
    var count: usize = 0;
    for (block.instructions.items) |instruction| {
        if (instruction.opcode == .dbgloc) continue;
        if (count == 2) return null;
        body[count] = instruction;
        count += 1;
    }
    if (count != 2 or body[1].opcode != .hlt or body[0].opcode != .call) return null;
    const name = body[0].directTarget() orelse return null;
    if (!std.mem.startsWith(u8, name, il.fail_prefix)) return null;
    return body[0];
}

/// One innermost natural loop: its header and its body labels in block order.
const Loop = struct { header: []const u8, body: []const []const u8 };

/// The innermost natural loops, in the order of their headers.
fn naturalLoops(arena: Allocator, cfg: *const Cfg) Error![]Loop {
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    for (cfg.blocks, 0..) |block, position| {
        const entry = try index.getOrPut(arena, block.label);
        if (!entry.found_existing) entry.value_ptr.* = position;
    }
    const edges = try arena.alloc([]const usize, cfg.blocks.len);
    for (cfg.blocks, edges) |block, *list| {
        var targets: std.ArrayList(usize) = .empty;
        for (cfg.successors.get(block.label).?) |successor| if (index.get(successor)) |position| try targets.append(arena, position);
        list.* = targets.items;
    }
    const dominators = try classes.Dominators.of(arena, edges);
    var loops: std.array_hash_map.String(Labels) = .empty;
    for (cfg.blocks, 0..) |block, position| for (edges[position]) |successor| {
        if (!dominators.dominates(successor, position)) continue;
        const header = cfg.blocks[successor].label;
        const entry = try loops.getOrPut(arena, header);
        if (!entry.found_existing) entry.value_ptr.* = .empty;
        try loopBody(arena, cfg, header, block.label, entry.value_ptr);
    };
    var innermost: std.ArrayList(Loop) = .empty;
    for (loops.keys(), loops.values()) |header, body| {
        var nested = false;
        for (loops.keys()) |other| nested = nested or (!std.mem.eql(u8, other, header) and body.contains(other));
        if (nested) continue;
        var ordered: std.ArrayList([]const u8) = .empty;
        for (cfg.blocks) |block| if (body.contains(block.label)) try ordered.append(arena, block.label);
        try innermost.append(arena, .{ .header = header, .body = ordered.items });
    }
    std.mem.sort(Loop, innermost.items, &index, struct {
        fn less(positions: *const std.StringHashMapUnmanaged(usize), left: Loop, right: Loop) bool {
            return positions.get(left.header).? < positions.get(right.header).?;
        }
    }.less);
    return innermost.items;
}

/// Add the natural loop of the back edge `latch -> header` to `body`.
fn loopBody(arena: Allocator, cfg: *const Cfg, header: []const u8, latch: []const u8, body: *Labels) Error!void {
    var local: Labels = .empty;
    try local.put(arena, header, {});
    try local.put(arena, latch, {});
    var work: std.ArrayList([]const u8) = .empty;
    try work.append(arena, latch);
    while (work.pop()) |current| {
        if (std.mem.eql(u8, current, header)) continue;
        for (cfg.predecessors.get(current).?.items) |predecessor| {
            if (local.contains(predecessor)) continue;
            try local.put(arena, predecessor, {});
            try work.append(arena, predecessor);
        }
    }
    for (local.keys()) |label| try body.put(arena, label, {});
}

/// A frame cell: storage at a fixed offset of an `alloc` defined once in the entry block.
const Cell = struct {
    alloc: []const u8,
    offset: i64,

    fn eql(self: Cell, other: Cell) bool {
        return self.offset == other.offset and std.mem.eql(u8, self.alloc, other.alloc);
    }
    fn less(self: Cell, other: Cell) bool {
        const order = std.mem.order(u8, self.alloc, other.alloc);
        if (order != .eq) return order == .lt;
        return self.offset < other.offset;
    }
};

/// This unit's frame cells: `alloc*` storage defined once in the entry block.
const Frame = struct {
    counts: std.StringHashMapUnmanaged(u32),
    definitions: std.StringHashMapUnmanaged(*Instruction) = .empty,
    sizes: std.array_hash_map.String(u64) = .empty,
    escaped: std.StringHashMapUnmanaged(void) = .empty,

    fn of(arena: Allocator, function: *const il.Function) Error!Frame {
        var self: Frame = .{ .counts = try classes.definitionCounts(arena, function) };
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| {
            if (instruction.dest) |dest| try self.definitions.put(arena, dest, instruction);
        };
        for (function.blocks.items[0].instructions.items) |instruction| {
            const dest = instruction.dest orelse continue;
            if (!instruction.opcode.isAlloc() or !self.single(dest)) continue;
            const size = constantValue(instruction.args[0]) orelse continue;
            try self.sizes.put(arena, dest, size);
        }
        try self.findEscaped(arena, function);
        return self;
    }

    fn single(self: *const Frame, name: []const u8) bool {
        return (self.counts.get(name) orelse 0) == 1;
    }

    /// Frame cells whose address leaves the address position somewhere.
    fn findEscaped(self: *Frame, arena: Allocator, function: *const il.Function) Error!void {
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| {
            for (instruction.args, 0..) |argument, index| {
                if (argument == .call) for (argument.call.args) |nested| {
                    if (self.cell(nested)) |found| try self.escaped.put(arena, found.alloc, {});
                };
                const found = self.cell(argument) orelse continue;
                if (self.addressUse(instruction, index)) continue;
                try self.escaped.put(arena, found.alloc, {});
            }
            if (instruction.extra == .phi) for (instruction.extra.phi) |input| {
                if (self.cell(input.value)) |found| try self.escaped.put(arena, found.alloc, {});
            };
        };
    }

    /// Whether operand `index` of `instruction` is only used as an address.
    fn addressUse(self: *const Frame, instruction: *const Instruction, index: usize) bool {
        const opcode = instruction.opcode;
        if (opcode.isLoad() and index == 0) return true;
        if (opcode.isStore() and index == 1) return true;
        if (opcode == .blit and index <= 1) return true;
        const derived = (opcode == .copy or opcode == .add) and instruction.dest != null;
        return derived and self.cellOf(instruction.dest.?) != null;
    }

    /// `(alloc, offset)` when `address` is frame storage at a fixed offset.
    fn cell(self: *const Frame, address: Operand) ?Cell {
        const name = address.tempName() orelse return null;
        return self.cellOf(name);
    }

    fn cellOf(self: *const Frame, start: []const u8) ?Cell {
        var offset: i64 = 0;
        var name = start;
        for (0..8) |_| {
            if (self.sizes.contains(name)) return .{ .alloc = name, .offset = offset };
            if (!self.single(name)) return null;
            const definition = self.definitions.get(name) orelse return null;
            var next: Operand = undefined;
            if (definition.opcode == .copy) {
                next = definition.args[0];
            } else if (definition.opcode == .add and definition.args.len == 2) {
                const left = definition.args[0];
                const right = definition.args[1];
                if (constantValue(right)) |value| {
                    offset +%= signed(value);
                    next = left;
                } else if (constantValue(left)) |value| {
                    offset +%= signed(value);
                    next = right;
                } else return null;
            } else return null;
            name = next.tempName() orelse return null;
        }
        return null;
    }
};

/// One `jnz` whose one target is a trap block.
const Check = struct {
    block: *Block,
    jnz: *Instruction,
    trap_label: []const u8,
    ok_label: []const u8,
    call: *Instruction,
    operation: ?*Instruction = null,
    update: bool = false,

    fn overflow(self: *const Check) bool {
        return std.mem.eql(u8, self.call.directTarget().?, overflow_helper);
    }
    fn trapOnTrue(self: *const Check) bool {
        return std.mem.eql(u8, self.jnz.extra.branch[0], self.trap_label);
    }
};

/// A reduction update `cell = cell +/- x` whose check is dropped.
const Site = struct { check: *Check, cell: Cell, operand: ?Operand, constant: ?u64, operation: *Instruction };

/// The checks of one plan, by what the fast copy does with them.
const Checks = struct {
    sticky: std.ArrayList(*Check) = .empty,
    sites: std.ArrayList(*Site) = .empty,
    traps: std.ArrayList(*Check) = .empty,
};

/// Everything the rewrite of one loop needs.
const Plan = struct {
    header: []const u8,
    body: []const []const u8,
    checks: Checks = .{},
    cells: Labels = .empty,
    exits: std.ArrayList([]const u8) = .empty,
    defined: Labels = .empty,
};

// ---------------------------------------------------------------------------
// Fact and taint sets
// ---------------------------------------------------------------------------

/// A must-fact about a value: it is one some frame cell held, the result of a
/// checked operation, or a constant.
const Fact = union(enum) {
    of: Cell,
    result: *const Instruction,
    constant: u64,

    fn eql(self: Fact, other: Fact) bool {
        if (@backingInt(self) != @backingInt(other)) return false;
        return switch (self) {
            .of => |cell| cell.eql(other.of),
            .result => |instruction| instruction == other.result,
            .constant => |value| value == other.constant,
        };
    }
    fn less(_: void, self: Fact, other: Fact) bool {
        if (@backingInt(self) != @backingInt(other)) return @backingInt(self) < @backingInt(other);
        return switch (self) {
            .of => |cell| cell.less(other.of),
            .result => |instruction| @intFromPtr(instruction) < @intFromPtr(other.result),
            .constant => |value| value < other.constant,
        };
    }
};

/// A set of facts, kept sorted.
const Facts = []const Fact;

fn factsContain(set: Facts, fact: Fact) bool {
    for (set) |known| if (known.eql(fact)) return true;
    return false;
}

fn factsIntersect(arena: Allocator, left: Facts, right: Facts) Error!Facts {
    var out: std.ArrayList(Fact) = .empty;
    for (left) |fact| if (factsContain(right, fact)) try out.append(arena, fact);
    return out.items;
}

fn factsEqual(left: Facts, right: Facts) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!a.eql(b)) return false;
    return true;
}

fn factsWith(arena: Allocator, set: Facts, fact: Fact) Error!Facts {
    if (factsContain(set, fact)) return set;
    const out = try arena.alloc(Fact, set.len + 1);
    @memcpy(out[0..set.len], set);
    out[set.len] = fact;
    std.mem.sort(Fact, out, {}, Fact.less);
    return out;
}

/// A set of checked operations whose wrapped result may reach a value.
const Origins = []const *const Instruction;

/// The union of two origin sets, always in memory of its own (`right` may be a
/// caller's temporary).
fn originsUnion(arena: Allocator, left: Origins, right: Origins) Error!Origins {
    if (right.len == 0) return left;
    var out: std.ArrayList(*const Instruction) = .empty;
    try out.appendSlice(arena, left);
    for (right) |origin| if (std.mem.indexOfScalar(*const Instruction, out.items, origin) == null) try out.append(arena, origin);
    std.mem.sort(*const Instruction, out.items, {}, lessPointer);
    return out.items;
}

fn lessPointer(_: void, left: *const Instruction, right: *const Instruction) bool {
    return @intFromPtr(left) < @intFromPtr(right);
}

fn originsEqual(left: Origins, right: Origins) bool {
    return std.mem.eql(*const Instruction, left, right);
}

/// A state key: a temporary, or a frame cell (`c`, by allocation and offset,
/// for facts; by allocation alone for taint).
fn temporaryKey(arena: Allocator, name: []const u8) Error![]const u8 {
    return std.fmt.allocPrint(arena, "t:{s}", .{name});
}
fn cellKey(arena: Allocator, cell: Cell) Error![]const u8 {
    return std.fmt.allocPrint(arena, "c:{s}:{d}", .{ cell.alloc, cell.offset });
}
fn allocationKey(arena: Allocator, alloc: []const u8) Error![]const u8 {
    return std.fmt.allocPrint(arena, "c:{s}", .{alloc});
}

const FactState = std.array_hash_map.String(Facts);
const TaintState = std.array_hash_map.String(Origins);
/// One operand of one instruction, for the per-operand fact map.
const OperandKey = struct { instruction: *const Instruction, index: usize };
const OperandFacts = std.AutoHashMapUnmanaged(OperandKey, Facts);

// ---------------------------------------------------------------------------
// Analysis
// ---------------------------------------------------------------------------

/// Decide whether one innermost loop can be versioned, and how.
const Analysis = struct {
    arena: Allocator,
    function: *const il.Function,
    cfg: *const Cfg,
    frame: *const Frame,
    plan: *Plan,
    body: Labels,
    plan_checks: []*Check = &.{},

    fn run(self: *Analysis) AnalysisError!void {
        const plan = self.plan;
        if (std.mem.eql(u8, plan.header, self.cfg.blocks[0].label)) return error.Declined;
        var checks: std.array_hash_map.String(*Check) = .empty;
        for (plan.body) |label| try self.scanBlock(label, &checks);
        if (plan.exits.items.len == 0) return error.Declined;
        self.plan_checks = checks.values();
        try self.findSites();
        if (plan.checks.sites.items.len == 0 and plan.checks.sticky.items.len == 0) return error.Declined;
        try self.checkLiveness();
        try self.checkTaint();
        if (plan.checks.sites.items.len == 0 and plan.checks.sticky.items.len == 0) return error.Declined;
        const last = self.function.blocks.items[self.function.blocks.items.len - 1].terminator() orelse return error.Declined;
        const ends = last.opcode == .ret or last.opcode == .jmp or last.opcode == .hlt or last.opcode == .jnz;
        if (!ends) return error.Declined;
    }

    fn scanBlock(self: *Analysis, label: []const u8, checks: *std.array_hash_map.String(*Check)) AnalysisError!void {
        const block = self.cfg.by_label.get(label).?;
        for (block.instructions.items) |instruction| try self.admit(instruction);
        const terminator = block.terminator();
        for (self.cfg.successors.get(label).?) |successor| {
            if (self.body.contains(successor)) continue;
            const target = self.cfg.by_label.get(successor) orelse return error.Declined;
            if (trapCall(target)) |call| {
                const jnz = terminator orelse return error.Declined;
                if (jnz.opcode != .jnz) return error.Declined;
                const ok = okLabel(jnz.extra.branch, successor) orelse return error.Declined;
                const check = try self.arena.create(Check);
                check.* = .{ .block = block, .jnz = jnz, .trap_label = successor, .ok_label = ok, .call = call };
                try checks.put(self.arena, label, check);
                continue;
            }
            for (target.instructions.items) |instruction| if (instruction.opcode == .phi) return error.Declined;
            for (self.plan.exits.items) |exit| {
                if (std.mem.eql(u8, exit, successor)) break;
            } else try self.plan.exits.append(self.arena, successor);
        }
    }

    fn okLabel(targets: [2][]const u8, trap: []const u8) ?[]const u8 {
        var ok: ?[]const u8 = null;
        var count: usize = 0;
        for (targets) |target| if (!std.mem.eql(u8, target, trap)) {
            ok = target;
            count += 1;
        };
        return if (count == 1) ok else null;
    }

    fn admit(self: *Analysis, instruction: *const Instruction) AnalysisError!void {
        const opcode = instruction.opcode;
        if (opcode == .call or opcode == .blit or opcode == .phi or opcode.isAlloc()) return error.Declined;
        if (opcode.isStore()) {
            const cell = self.frame.cell(instruction.args[1]) orelse return error.Declined;
            const size = self.frame.sizes.get(cell.alloc).?;
            if (size % 4 != 0 or size > 256) return error.Declined;
            try self.plan.cells.put(self.arena, cell.alloc, {});
        }
        const dest = instruction.dest orelse return;
        const plain = if (instruction.qbe_type) |letter| il.isBaseType(letter) else false;
        if (!plain and !opcode.isExtension()) return error.Declined;
        try self.plan.defined.put(self.arena, dest, {});
    }

    /// Sort the loop's checks into reductions, sticky checks and kept ones.
    fn findSites(self: *Analysis) AnalysisError!void {
        const checks = &self.plan.checks;
        const operand_facts = try self.facts();
        var candidates: std.ArrayList(*Check) = .empty;
        for (self.plan_checks) |check| {
            if (!check.overflow()) {
                try checks.traps.append(self.arena, check);
                continue;
            }
            const args = check.call.args;
            const operation = if (args.len == 5) constantValue(args[1]) else null;
            const width = if (args.len == 5) constantValue(args[4]) else null;
            const op = findOperation(check, operation) orelse {
                try checks.traps.append(self.arena, check);
                continue;
            };
            check.operation = op;
            check.update = (operation == @as(u64, 0) or operation == @as(u64, 1)) and width == @as(u64, 64);
            try candidates.append(self.arena, check);
        }
        const sites = try self.reductionSites(candidates.items, &operand_facts);
        for (candidates.items) |check| {
            var mine = false;
            for (sites) |site| if (site.check == check) {
                try checks.sites.append(self.arena, site);
                mine = true;
            };
            if (!mine) try checks.sticky.append(self.arena, check);
        }
    }

    /// What each operand of each loop instruction holds on every path, by a
    /// must-analysis from the header (which starts knowing nothing).
    fn facts(self: *Analysis) AnalysisError!OperandFacts {
        var updates: std.AutoHashMapUnmanaged(*const Instruction, void) = .empty;
        for (self.plan_checks) |check| {
            if (!check.overflow()) continue;
            const args = check.call.args;
            if (args.len != 5) continue;
            const operation = constantValue(args[1]) orelse continue;
            if (operation > 1 or constantValue(args[4]) != @as(u64, 64)) continue;
            if (findOperation(check, operation)) |op| try updates.put(self.arena, op, {});
        }
        var states: std.StringHashMapUnmanaged(?FactState) = .empty;
        for (self.plan.body) |label| try states.put(self.arena, label, null);
        try states.put(self.arena, self.plan.header, .empty);
        var operands: OperandFacts = .empty;
        for (0..64) |_| {
            var changed = false;
            for (self.plan.body) |label| {
                const start = states.get(label).? orelse continue;
                var state = try start.clone(self.arena);
                for (self.cfg.by_label.get(label).?.instructions.items) |instruction| try self.factStep(instruction, &state, &updates, &operands);
                for (self.cfg.successors.get(label).?) |successor| {
                    if (!self.body.contains(successor) or std.mem.eql(u8, successor, self.plan.header)) continue;
                    changed = (try self.mergeFacts(states.getPtr(successor).?, &state)) or changed;
                }
            }
            if (!changed) return operands;
        }
        return error.Declined;
    }

    fn mergeFacts(self: *Analysis, target: *?FactState, state: *const FactState) Error!bool {
        const previous = target.* orelse {
            target.* = try state.clone(self.arena);
            return true;
        };
        var merged: FactState = .empty;
        for (previous.keys(), previous.values()) |key, facts_before| {
            const now = state.get(key) orelse continue;
            const both = try factsIntersect(self.arena, facts_before, now);
            if (both.len != 0) try merged.put(self.arena, key, both);
        }
        if (sameFactState(&merged, &previous)) return false;
        target.* = merged;
        return true;
    }

    fn factStep(self: *Analysis, instruction: *const Instruction, state: *FactState, updates: *const std.AutoHashMapUnmanaged(*const Instruction, void), operands: *OperandFacts) Error!void {
        for (instruction.args, 0..) |argument, index| try operands.put(self.arena, .{ .instruction = instruction, .index = index }, try self.factsOf(state, argument));
        const opcode = instruction.opcode;
        if (opcode.isStore()) {
            const cell = self.frame.cell(instruction.args[1]).?;
            const prefix = try std.fmt.allocPrint(self.arena, "c:{s}:", .{cell.alloc});
            var index: usize = 0;
            while (index < state.count()) {
                if (std.mem.startsWith(u8, state.keys()[index], prefix)) state.orderedRemoveAt(index) else index += 1;
            }
            const stored = try self.factsOf(state, instruction.args[0]);
            if (opcode == .storel and stored.len != 0) try state.put(self.arena, try cellKey(self.arena, cell), stored);
            return;
        }
        const dest = instruction.dest orelse return;
        var result: Facts = &.{};
        if (opcode == .loadl) {
            if (self.frame.cell(instruction.args[0])) |cell| {
                result = state.get(try cellKey(self.arena, cell)) orelse &.{};
                if (cell.offset == 0 and self.frame.sizes.get(cell.alloc) == @as(u64, 8)) result = try factsWith(self.arena, result, .{ .of = cell });
            }
        } else if (opcode == .copy) {
            result = try self.factsOf(state, instruction.args[0]);
        } else if (updates.contains(instruction)) {
            result = try factsWith(self.arena, &.{}, .{ .result = instruction });
        }
        const key = try temporaryKey(self.arena, dest);
        if (result.len != 0) try state.put(self.arena, key, result) else _ = state.orderedRemove(key);
    }

    fn factsOf(self: *Analysis, state: *const FactState, argument: Operand) Error!Facts {
        if (argument.tempName()) |name| return state.get(try temporaryKey(self.arena, name)) orelse &.{};
        const literal = constantValue(argument) orelse return &.{};
        return factsWith(self.arena, &.{}, .{ .constant = literal });
    }

    /// The reduction updates among the checked operations: `a + x`, `x + a`
    /// or `a - x` of a 64-bit signed value, where `a` is a value frame cell R
    /// held and every store to R's allocation in the loop is a `storel` to R
    /// of such an operation's result.
    fn reductionSites(self: *Analysis, candidates: []const *Check, operands: *const OperandFacts) Error![]*Site {
        const Pair = struct { check: *Check, position: usize, cell: Cell };
        var pairs: std.ArrayList(Pair) = .empty;
        for (candidates) |check| {
            if (!check.update) continue;
            const op = check.operation.?;
            const positions: []const usize = if (op.opcode == .add) &.{ 0, 1 } else &.{0};
            for (positions) |position| for (operands.get(.{ .instruction = op, .index = position }) orelse &.{}) |fact| {
                if (fact == .of) try pairs.append(self.arena, .{ .check = check, .position = position, .cell = fact.of });
            };
        }
        var stores: std.StringHashMapUnmanaged(std.ArrayList(*const Instruction)) = .empty;
        for (self.plan.body) |label| for (self.cfg.by_label.get(label).?.instructions.items) |instruction| {
            if (!instruction.opcode.isStore()) continue;
            const entry = try stores.getOrPut(self.arena, self.frame.cell(instruction.args[1]).?.alloc);
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(self.arena, instruction);
        };
        var sites: std.ArrayList(*Site) = .empty;
        for (pairs.items) |pair| {
            var repeated = false;
            for (sites.items) |site| repeated = repeated or (site.check == pair.check and site.cell.eql(pair.cell));
            if (repeated) continue;
            var updating: std.ArrayList(*const Instruction) = .empty;
            for (pairs.items) |other| if (other.cell.eql(pair.cell)) try updating.append(self.arena, other.check.operation.?);
            const cell_stores = if (stores.get(pair.cell.alloc)) |list| list.items else &.{};
            if (!self.validStores(cell_stores, pair.cell, updating.items, operands)) continue;
            const op = pair.check.operation.?;
            const other = op.args[1 - pair.position];
            var constant: ?u64 = null;
            for (operands.get(.{ .instruction = op, .index = 1 - pair.position }) orelse &.{}) |fact| {
                if (fact == .constant) constant = @abs(signed(fact.constant));
            }
            if (constant == null and !usableAtCheck(pair.check, other)) continue;
            const site = try self.arena.create(Site);
            site.* = .{ .check = pair.check, .cell = pair.cell, .operand = if (constant == null) other else null, .constant = constant, .operation = op };
            try sites.append(self.arena, site);
        }
        return sites.items;
    }

    fn validStores(self: *const Analysis, cell_stores: []const *const Instruction, cell: Cell, updating: []const *const Instruction, operands: *const OperandFacts) bool {
        if (cell_stores.len == 0) return false;
        for (cell_stores) |store| {
            if (store.opcode != .storel) return false;
            const target = self.frame.cell(store.args[1]) orelse return false;
            if (!target.eql(cell)) return false;
            var produced = false;
            for (operands.get(.{ .instruction = store, .index = 0 }) orelse &.{}) |fact| {
                if (fact == .result and std.mem.indexOfScalar(*const Instruction, updating, fact.result) != null) produced = true;
            }
            if (!produced) return false;
        }
        return true;
    }

    fn checkLiveness(self: *Analysis) Verdict!void {
        const defined = &self.plan.defined;
        for (self.plan.body) |label| {
            var seen: Labels = .empty;
            for (self.cfg.by_label.get(label).?.instructions.items) |instruction| {
                for (instruction.args) |argument| {
                    const name = argument.tempName() orelse continue;
                    if (!defined.contains(name) or seen.contains(name)) continue;
                    if (!(self.definedBefore(label, name) catch return error.Declined)) return error.Declined;
                }
                if (instruction.dest) |dest| seen.put(self.arena, dest, {}) catch return error.Declined;
            }
        }
        for (self.cfg.blocks) |block| {
            if (self.body.contains(block.label) or trapCall(block) != null) continue;
            for (block.instructions.items) |instruction| for (instruction.args) |argument| {
                const name = argument.tempName() orelse continue;
                if (defined.contains(name)) return error.Declined;
            };
        }
    }

    /// Whether every path from the header to `label` defines `name` first.
    fn definedBefore(self: *Analysis, label: []const u8, name: []const u8) Error!bool {
        var work: std.ArrayList([]const u8) = .empty;
        var seen: Labels = .empty;
        try work.append(self.arena, label);
        try seen.put(self.arena, label, {});
        var first = true;
        while (work.pop()) |current| {
            if (!first or !std.mem.eql(u8, current, label)) {
                if (blockDefines(self.cfg.by_label.get(current).?, name)) continue;
            }
            first = false;
            if (std.mem.eql(u8, current, self.plan.header)) return false;
            for (self.cfg.predecessors.get(current).?.items) |predecessor| {
                if (!self.body.contains(predecessor) or seen.contains(predecessor)) continue;
                try seen.put(self.arena, predecessor, {});
                try work.append(self.arena, predecessor);
            }
        }
        return true;
    }

    /// Demote every dropped check whose wrapped value reaches a hazard, until none does.
    fn checkTaint(self: *Analysis) AnalysisError!void {
        for (0..256) |_| {
            var items: std.array_hash_map.Auto(*const Instruction, *Check) = .empty;
            for (self.plan.checks.sticky.items) |check| try items.put(self.arena, check.operation.?, check);
            for (self.plan.checks.sites.items) |site| try items.put(self.arena, site.operation, site.check);
            if (items.count() == 0) return;
            const culprits = (try self.taint(&items)) orelse return;
            for (culprits) |key| try self.demote(items.get(key).?);
        }
        return error.Declined;
    }

    fn demote(self: *Analysis, check: *Check) Error!void {
        const checks = &self.plan.checks;
        var index: usize = 0;
        while (index < checks.sites.items.len) {
            if (checks.sites.items[index].check == check) _ = checks.sites.orderedRemove(index) else index += 1;
        }
        if (std.mem.indexOfScalar(*Check, checks.sticky.items, check)) |at| _ = checks.sticky.orderedRemove(at);
        if (std.mem.indexOfScalar(*Check, checks.traps.items, check) == null) try checks.traps.append(self.arena, check);
    }

    /// Run the taint dataflow once; the origins of the first hazard, or null.
    fn taint(self: *Analysis, items: *const std.array_hash_map.Auto(*const Instruction, *Check)) AnalysisError!?Origins {
        var jumps: Jumps = .{};
        for (self.plan.checks.sticky.items) |check| try jumps.removed.put(self.arena, check.jnz, {});
        for (self.plan.checks.sites.items) |site| try jumps.removed.put(self.arena, site.check.jnz, {});
        for (self.plan.checks.traps.items) |check| try jumps.kept.put(self.arena, check.jnz, {});
        var states: std.StringHashMapUnmanaged(TaintState) = .empty;
        for (self.plan.body) |label| try states.put(self.arena, label, .empty);
        const header = states.getPtr(self.plan.header).?;
        for (self.plan.checks.sites.items) |site| {
            const key = try allocationKey(self.arena, site.cell.alloc);
            const before = header.get(key) orelse &.{};
            try header.put(self.arena, key, try originsUnion(self.arena, before, &.{site.operation}));
        }
        for (0..128) |_| {
            var changed = false;
            for (self.plan.body) |label| {
                var state = try states.get(label).?.clone(self.arena);
                for (self.cfg.by_label.get(label).?.instructions.items) |instruction| {
                    if (try self.transfer(instruction, &state, items, &jumps)) |hazard| return hazard;
                }
                for (self.cfg.successors.get(label).?) |successor| {
                    const target = states.getPtr(successor) orelse continue;
                    changed = (try self.mergeTaint(target, &state)) or changed;
                }
            }
            if (!changed) return null;
        }
        return error.Declined;
    }

    fn mergeTaint(self: *Analysis, target: *TaintState, state: *const TaintState) Error!bool {
        var changed = false;
        for (state.keys(), state.values()) |key, origins| {
            const before = target.get(key);
            const merged = try originsUnion(self.arena, before orelse &.{}, origins);
            if (before != null and originsEqual(merged, before.?)) continue;
            try target.put(self.arena, key, merged);
            changed = true;
        }
        return changed;
    }

    /// Apply one instruction to the taint state; the hazard's origins, or null.
    fn transfer(self: *Analysis, instruction: *const Instruction, state: *TaintState, items: *const std.array_hash_map.Auto(*const Instruction, *Check), jumps: *const Jumps) Error!?Origins {
        const opcode = instruction.opcode;
        switch (opcode) {
            .jnz => {
                if (jumps.removed.contains(instruction) or jumps.kept.contains(instruction)) return null;
                return nonEmpty(try self.originsOf(state, instruction.args[0]));
            },
            .jmp, .hlt, .ret, .dbgloc => return null,
            else => {},
        }
        if (opcode.isStore()) return self.storeTaint(instruction, state);
        const dest = instruction.dest orelse return null;
        var origins: Origins = &.{};
        if (opcode.isLoad()) {
            if (self.frame.cell(instruction.args[0])) |cell| {
                origins = state.get(try allocationKey(self.arena, cell.alloc)) orelse &.{};
            } else if (nonEmpty(try self.originsOf(state, instruction.args[0]))) |hazard| return hazard;
        } else if (opcode == .shl or opcode == .sar or opcode == .shr) {
            if (nonEmpty(try self.originsOf(state, instruction.args[1]))) |hazard| return hazard;
            origins = try self.originsOf(state, instruction.args[0]);
        } else if (opcode == .div or opcode == .rem or opcode == .udiv or opcode == .urem) {
            if (nonEmpty(try self.originsOf(state, instruction.args[1]))) |hazard| return hazard;
            const divisor = constantValue(instruction.args[1]);
            const dividend = try self.originsOf(state, instruction.args[0]);
            if (dividend.len != 0 and (divisor == null or divisor == std.math.maxInt(u64))) return dividend;
            origins = dividend;
        } else if (opcode == .stosi or opcode == .dtosi or opcode == .stoui or opcode == .dtoui) {
            if (nonEmpty(try self.originsOf(state, instruction.args[0]))) |hazard| return hazard;
        } else {
            for (instruction.args) |argument| origins = try originsUnion(self.arena, origins, try self.originsOf(state, argument));
        }
        if (items.contains(instruction)) origins = try originsUnion(self.arena, origins, &.{instruction});
        const key = try temporaryKey(self.arena, dest);
        if (origins.len != 0) try state.put(self.arena, key, origins) else _ = state.orderedRemove(key);
        return null;
    }

    /// A store of a tainted value taints the whole cell; only a store over
    /// all of an 8-byte cell clears it; an escaped cell must stay clean.
    fn storeTaint(self: *Analysis, instruction: *const Instruction, state: *TaintState) Error!?Origins {
        const cell = self.frame.cell(instruction.args[1]).?;
        const key = try allocationKey(self.arena, cell.alloc);
        const origins = try self.originsOf(state, instruction.args[0]);
        if (origins.len != 0 and self.frame.escaped.contains(cell.alloc)) return origins;
        if (origins.len != 0) {
            try state.put(self.arena, key, try originsUnion(self.arena, state.get(key) orelse &.{}, origins));
        } else if (instruction.opcode == .storel and cell.offset == 0 and self.frame.sizes.get(cell.alloc) == @as(u64, 8)) {
            _ = state.orderedRemove(key);
        }
        return null;
    }

    fn originsOf(self: *Analysis, state: *const TaintState, argument: Operand) Error!Origins {
        const name = argument.tempName() orelse return &.{};
        return state.get(try temporaryKey(self.arena, name)) orelse &.{};
    }
};

/// The check branches the fast copy removes, and those it keeps as branches.
const Jumps = struct {
    removed: std.AutoHashMapUnmanaged(*const Instruction, void) = .empty,
    kept: std.AutoHashMapUnmanaged(*const Instruction, void) = .empty,
};

fn nonEmpty(origins: Origins) ?Origins {
    return if (origins.len == 0) null else origins;
}

fn sameFactState(left: *const FactState, right: *const FactState) bool {
    if (left.count() != right.count()) return false;
    for (left.keys(), left.values()) |key, value| {
        const other = right.get(key) orelse return false;
        if (!factsEqual(value, other)) return false;
    }
    return true;
}

fn blockDefines(block: *const Block, name: []const u8) bool {
    for (block.instructions.items) |instruction| {
        if (instruction.dest) |dest| if (std.mem.eql(u8, dest, name)) return true;
    }
    return false;
}

/// The `add`/`sub`/`mul` whose overflow a check's call reports.
fn findOperation(check: *const Check, operation: ?u64) ?*Instruction {
    const wanted: il.Opcode = switch (operation orelse return null) {
        0 => .add,
        1 => .sub,
        2 => .mul,
        else => return null,
    };
    const left = check.call.args[2].tempName() orelse return null;
    const right = check.call.args[3].tempName() orelse return null;
    const instructions = check.block.instructions.items;
    var index = instructions.len;
    while (index > 0) {
        index -= 1;
        const instruction = instructions[index];
        if (instruction.opcode != wanted or instruction.dest == null or instruction.args.len != 2) continue;
        const a = instruction.args[0].tempName() orelse continue;
        const b = instruction.args[1].tempName() orelse continue;
        if (std.mem.eql(u8, a, left) and std.mem.eql(u8, b, right)) return instruction;
    }
    return null;
}

/// Whether `argument` still holds the operation's operand at the check.
fn usableAtCheck(check: *const Check, argument: Operand) bool {
    const name = argument.tempName() orelse return false;
    const instructions = check.block.instructions.items;
    const start = std.mem.indexOfScalar(*Instruction, instructions, check.operation.?).?;
    for (instructions[start..]) |instruction| {
        if (instruction.dest) |dest| if (std.mem.eql(u8, dest, name)) return false;
    }
    return true;
}

// ---------------------------------------------------------------------------
// Rewriting
// ---------------------------------------------------------------------------

/// Version every qualifying innermost loop of `unit` in place. Every loop is
/// analysed on the original function; then each plan is rewritten in turn.
pub fn versionLoops(arena: Allocator, unit: *il.Unit, diagnostic: *il.Diagnostic) Error!void {
    const function = &unit.function;
    if (function.blocks.items.len == 0) return;
    const cfg = try Cfg.of(arena, function);
    const frame = try Frame.of(arena, function);
    var plans: std.ArrayList(*Plan) = .empty;
    for (try naturalLoops(arena, &cfg)) |loop| {
        const plan = try arena.create(Plan);
        plan.* = .{ .header = loop.header, .body = loop.body };
        var body: Labels = .empty;
        for (loop.body) |label| try body.put(arena, label, {});
        var analysis: Analysis = .{ .arena = arena, .function = function, .cfg = &cfg, .frame = &frame, .plan = plan, .body = body };
        analysis.run() catch |err| switch (err) {
            error.Declined => continue,
            else => |other| return other,
        };
        try plans.append(arena, plan);
    }
    for (plans.items, 0..) |plan, number| {
        var rewriter: Rewriter = .{ .arena = arena, .function = function, .plan = plan, .prefix = try std.fmt.allocPrint(arena, "sk{d}", .{number}), .diagnostic = diagnostic };
        try rewriter.run();
    }
}

/// Builds the fast copy, the verification and the fallback of one plan.
const Rewriter = struct {
    arena: Allocator,
    function: *il.Function,
    plan: *Plan,
    prefix: []const u8,
    diagnostic: *il.Diagnostic,
    count: usize = 0,
    rename: std.StringHashMapUnmanaged([]const u8) = .empty,

    fn fresh(self: *Rewriter, stem: []const u8) Error![]const u8 {
        self.count += 1;
        return std.fmt.allocPrint(self.arena, "%{s}.{s}{d}", .{ self.prefix, stem, self.count });
    }

    fn label(self: *Rewriter, name: []const u8) Error![]const u8 {
        return std.fmt.allocPrint(self.arena, "@{s}.{s}", .{ self.prefix, std.mem.trimStart(u8, name, "@") });
    }

    fn parse(self: *Rewriter, comptime format: []const u8, arguments: anytype) Error!*Instruction {
        const text = try std.fmt.allocPrint(self.arena, format, arguments);
        return il.parseInstruction(self.arena, il.strip(text), .{ .number = 0, .raw = text, .diagnostic = self.diagnostic });
    }

    fn cloneOperand(self: *const Rewriter, argument: Operand) Operand {
        const name = argument.tempName() orelse return argument;
        const renamed = self.rename.get(name) orelse return argument;
        return .{ .temp = .{ .name = renamed, .qbe_type = argument.temp.qbe_type } };
    }

    fn clone(self: *Rewriter, instruction: *const Instruction, targets: *Targets) Error!*Instruction {
        const copy = try self.arena.create(Instruction);
        copy.* = instruction.*;
        if (instruction.dest) |dest| copy.dest = self.rename.get(dest) orelse dest;
        const args = try self.arena.alloc(Operand, instruction.args.len);
        for (instruction.args, args) |argument, *slot| slot.* = self.cloneOperand(argument);
        copy.args = args;
        switch (instruction.opcode) {
            .jmp => copy.extra = .{ .label = try targets.of(instruction.extra.label) },
            .jnz => copy.extra = .{ .branch = .{ try targets.of(instruction.extra.branch[0]), try targets.of(instruction.extra.branch[1]) } },
            else => {},
        }
        return copy;
    }

    fn newBlock(self: *Rewriter, name: []const u8) Error!*Block {
        const block = try self.arena.create(Block);
        block.* = .{ .label = name };
        return block;
    }

    fn append(self: *Rewriter, block: *Block, comptime format: []const u8, arguments: anytype) Error!void {
        try block.instructions.append(self.arena, try self.parse(format, arguments));
    }

    fn run(self: *Rewriter) Error!void {
        const plan = self.plan;
        for (plan.defined.keys()) |name| try self.rename.put(self.arena, name, try std.fmt.allocPrint(self.arena, "{s}.{s}", .{ self.prefix, name }));
        const cfg = try Cfg.of(self.arena, self.function);
        var targets: Targets = .{ .rewriter = self, .cfg = &cfg, .fallback = try self.label("@fallback") };
        try targets.collect();
        const hints = &self.function.hints.objects;
        const marked = try self.arena.dupe([]const u8, hints.keys());
        for (marked) |name| if (self.rename.get(name)) |renamed| try hints.put(self.arena, renamed, {});
        var state: Bookkeeping = .{ .sticky = try std.fmt.allocPrint(self.arena, "%{s}.sticky", .{self.prefix}), .count = try std.fmt.allocPrint(self.arena, "%{s}.count", .{self.prefix}) };
        try state.collect(self);
        var blocks: std.ArrayList(*Block) = .empty;
        const entry_label = try self.label("@entry");
        try blocks.append(self.arena, try self.entryBlock(entry_label, &state));
        for (plan.body) |name| try blocks.append(self.arena, try self.fastCopy(&cfg, name, &targets, &state));
        for (targets.exit_targets.items, targets.exit_labels.items) |target, name| {
            const block = try self.newBlock(name);
            const ok = try self.verification(block, &state);
            try self.append(block, "jnz {s}, {s}, {s}", .{ ok, target, targets.fallback });
            try blocks.append(self.arena, block);
        }
        try blocks.append(self.arena, try self.fallbackBlock(targets.fallback, &state));
        try self.enterFastCopy(&cfg, entry_label);
        try self.function.blocks.appendSlice(self.arena, blocks.items);
    }

    /// Entry: snapshot every cell the loop writes, zero the bookkeeping.
    fn entryBlock(self: *Rewriter, name: []const u8, state: *Bookkeeping) Error!*Block {
        const plan = self.plan;
        const entry = try self.newBlock(name);
        for (state.cells_written) |alloc| {
            const frame = try Frame.of(self.arena, self.function);
            const size = frame.sizes.get(alloc).?;
            var pieces: std.ArrayList(Piece) = .empty;
            var offset: u64 = 0;
            while (offset < size) {
                const width: u64 = if (size - offset >= 8) 8 else 4;
                var address: []const u8 = try std.fmt.allocPrint(self.arena, "%{s}", .{alloc});
                if (offset != 0) {
                    address = try self.fresh("at");
                    try self.append(entry, "{s} =l add %{s}, {d}", .{ address, alloc, offset });
                }
                const saved = try self.fresh("save");
                if (width == 8) try self.append(entry, "{s} =l loadl {s}", .{ saved, address }) else try self.append(entry, "{s} =w loaduw {s}", .{ saved, address });
                try pieces.append(self.arena, .{ .offset = offset, .width = width, .saved = saved });
                offset += width;
            }
            try state.snapshots.put(self.arena, alloc, pieces.items);
        }
        if (plan.checks.sticky.items.len != 0) try self.append(entry, zero_line, .{state.sticky});
        if (plan.checks.sites.items.len != 0) {
            try self.append(entry, zero_line, .{state.count});
            for (state.cells) |cell| {
                try self.append(entry, zero_line, .{try state.high(self, cell)});
                try self.append(entry, zero_line, .{try state.low(self, cell)});
            }
        }
        try self.append(entry, "jmp {s}", .{try self.label(plan.header)});
        return entry;
    }

    /// One block of the fast copy: its instructions cloned under the renaming,
    /// a sticky check OR-ed into the sticky word, a reduction's check replaced
    /// by the magnitude sums.
    fn fastCopy(self: *Rewriter, cfg: *const Cfg, name: []const u8, targets: *Targets, state: *Bookkeeping) Error!*Block {
        const plan = self.plan;
        const block = cfg.by_label.get(name).?;
        const copy = try self.newBlock(try self.label(name));
        if (std.mem.eql(u8, name, plan.header) and plan.checks.sites.items.len != 0) try self.append(copy, "{s} =l add {s}, 1", .{ state.count, state.count });
        const terminator = block.terminator();
        const explicit = if (terminator) |last| (last.opcode == .jmp or last.opcode == .jnz or last.opcode == .ret or last.opcode == .hlt) else false;
        const body = if (explicit) block.instructions.items[0 .. block.instructions.items.len - 1] else block.instructions.items;
        for (body) |instruction| try copy.instructions.append(self.arena, try self.clone(instruction, targets));
        if (!explicit) {
            const next = cfg.following.get(name).? orelse return self.diagnostic.fail(self.arena, 0, "sticky loop falls off the function");
            try self.append(copy, "jmp {s}", .{try targets.of(next)});
            return copy;
        }
        const last = terminator.?;
        if (stickyCheck(plan, last)) |check| {
            try self.stickyTest(copy, block, check, state);
            try self.append(copy, "jmp {s}", .{try targets.of(check.ok_label)});
        } else if (firstSite(plan, last)) |check| {
            for (plan.checks.sites.items) |site| if (site.check.jnz == last) try self.magnitudes(copy, site, state);
            try self.append(copy, "jmp {s}", .{try targets.of(check.ok_label)});
        } else try copy.instructions.append(self.arena, try self.clone(last, targets));
        return copy;
    }

    fn stickyTest(self: *Rewriter, copy: *Block, block: *const Block, check: *const Check, state: *Bookkeeping) Error!void {
        const flag = self.cloneOperand(check.jnz.args[0]);
        const word = try self.flagWord(copy, flag, block);
        const bit = try self.fresh("bit");
        const test_name: []const u8 = if (check.trapOnTrue()) "cnel" else "ceql";
        try self.append(copy, "{s} =l {s} {s}, 0", .{ bit, test_name, word });
        try self.append(copy, "{s} =l or {s}, {s}", .{ state.sticky, state.sticky, bit });
    }

    fn magnitudes(self: *Rewriter, copy: *Block, site: *const Site, state: *Bookkeeping) Error!void {
        if (site.constant != null) return;
        const x = self.cloneOperand(site.operand.?).temp.name;
        const sign = try self.fresh("sign");
        const flipped = try self.fresh("flip");
        const magnitude = try self.fresh("abs");
        const top = try self.fresh("top");
        const bottom = try self.fresh("bottom");
        const high = try state.high(self, site.cell);
        const low = try state.low(self, site.cell);
        try self.append(copy, "{s} =l sar %{s}, 63", .{ sign, x });
        try self.append(copy, "{s} =l xor %{s}, {s}", .{ flipped, x, sign });
        try self.append(copy, "{s} =l sub {s}, {s}", .{ magnitude, flipped, sign });
        try self.append(copy, "{s} =l shr {s}, 32", .{ top, magnitude });
        try self.append(copy, "{s} =l and {s}, 4294967295", .{ bottom, magnitude });
        try self.append(copy, add_line, .{ high, high, top });
        try self.append(copy, add_line, .{ low, low, bottom });
    }

    /// The check's flag as an `l` value.
    fn flagWord(self: *Rewriter, copy: *Block, flag: Operand, block: *const Block) Error![]const u8 {
        var definition: ?*const Instruction = null;
        if (flag.tempName()) |name| for (block.instructions.items) |instruction| {
            const dest = instruction.dest orelse continue;
            if (std.mem.eql(u8, self.rename.get(dest) orelse dest, name)) definition = instruction;
        };
        if (definition) |defined| if (defined.qbe_type != null and std.mem.eql(u8, defined.qbe_type.?, "w")) {
            const widened = try self.fresh("wide");
            try self.append(copy, "{s} =l extuw %{s}", .{ widened, flag.tempName().? });
            return widened;
        };
        if (flag.tempName()) |name| return std.fmt.allocPrint(self.arena, "%{s}", .{name});
        return std.fmt.allocPrint(self.arena, "{?d}", .{constantValue(flag)});
    }

    /// Fallback: restore every snapshot, then run the original loop.
    fn fallbackBlock(self: *Rewriter, name: []const u8, state: *Bookkeeping) Error!*Block {
        const fallback = try self.newBlock(name);
        for (state.cells_written) |alloc| for (state.snapshots.get(alloc).?) |piece| {
            var address: []const u8 = try std.fmt.allocPrint(self.arena, "%{s}", .{alloc});
            if (piece.offset != 0) {
                address = try self.fresh("at");
                try self.append(fallback, "{s} =l add %{s}, {d}", .{ address, alloc, piece.offset });
            }
            if (piece.width == 8) try self.append(fallback, "storel {s}, {s}", .{ piece.saved, address }) else try self.append(fallback, "storew {s}, {s}", .{ piece.saved, address });
        };
        try self.append(fallback, "jmp {s}", .{self.plan.header});
        return fallback;
    }

    /// Point every entry edge of the loop at the fast copy.
    fn enterFastCopy(self: *Rewriter, cfg: *const Cfg, entry_label: []const u8) Error!void {
        const plan = self.plan;
        for (cfg.predecessors.get(plan.header).?.items) |predecessor| {
            if (contains(plan.body, predecessor)) continue;
            const block = cfg.by_label.get(predecessor).?;
            const terminator = block.terminator();
            const opcode: ?il.Opcode = if (terminator) |last| last.opcode else null;
            if (opcode == .jmp) {
                terminator.?.extra = .{ .label = entry_label };
            } else if (opcode == .jnz) {
                const old = terminator.?.extra.branch;
                var branch = old;
                for (&branch) |*target| if (std.mem.eql(u8, target.*, plan.header)) {
                    target.* = entry_label;
                };
                terminator.?.extra = .{ .branch = branch };
            } else try self.append(block, "jmp {s}", .{entry_label});
        }
    }

    /// Append the exit test; return the `l` temporary that is 1 when the fast copy is exact.
    fn verification(self: *Rewriter, block: *Block, state: *Bookkeeping) Error![]const u8 {
        const plan = self.plan;
        var parts: std.ArrayList([]const u8) = .empty;
        if (plan.checks.sticky.items.len != 0) {
            const clean = try self.fresh("clean");
            try self.append(block, "{s} =l ceql {s}, 0", .{ clean, state.sticky });
            try parts.append(self.arena, clean);
        }
        for (state.cells) |cell| try self.verifyCell(block, cell, state, &parts);
        if (parts.items.len == 0) {
            const one = try self.fresh("one");
            try self.append(block, "{s} =l copy 1", .{one});
            return one;
        }
        var result = parts.items[0];
        for (parts.items[1..]) |part| {
            const both = try self.fresh("both");
            try self.append(block, "{s} =l and {s}, {s}", .{ both, result, part });
            result = both;
        }
        return result;
    }

    /// `|entry value| + sum of |added values| <= 2^63 - 1` for one reduction cell.
    fn verifyCell(self: *Rewriter, block: *Block, cell: Cell, state: *Bookkeeping, parts: *std.ArrayList([]const u8)) Error!void {
        var variable: u64 = 0;
        var constant: u128 = 0;
        for (self.plan.checks.sites.items) |site| if (site.cell.eql(cell)) {
            if (site.constant) |value| constant += value else variable += 1;
        };
        const entry = state.snapshots.get(cell.alloc).?[0].saved;
        const sign = try self.fresh("sign");
        const flipped = try self.fresh("flip");
        const magnitude = try self.fresh("abs");
        try self.append(block, "{s} =l sar {s}, 63", .{ sign, entry });
        try self.append(block, "{s} =l xor {s}, {s}", .{ flipped, entry, sign });
        try self.append(block, "{s} =l sub {s}, {s}", .{ magnitude, flipped, sign });
        var total = magnitude;
        if (variable != 0) total = try self.verifyVariable(block, .{ .cell = cell, .variable = variable, .total = total, .state = state }, parts);
        if (constant != 0) total = try self.verifyConstant(block, .{ .constant = constant, .variable = variable, .total = total, .count = state.count }, parts);
        const final = try self.fresh("final");
        try self.append(block, at_most_line, .{ final, total, max_signed });
        try parts.append(self.arena, final);
    }

    const VariableSums = struct { cell: Cell, variable: u64, total: []const u8, state: *Bookkeeping };

    fn verifyVariable(self: *Rewriter, block: *Block, sums: VariableSums, parts: *std.ArrayList([]const u8)) Error![]const u8 {
        const high = try sums.state.high(self, sums.cell);
        const low = try sums.state.low(self, sums.cell);
        const limit = (@as(u64, 1) << 32) / sums.variable - 1;
        const fits = try self.fresh("fits");
        try self.append(block, at_most_line, .{ fits, sums.state.count, limit });
        try parts.append(self.arena, fits);
        const small = try self.fresh("small");
        try self.append(block, "{s} =l cultl {s}, 2147483648", .{ small, high });
        try parts.append(self.arena, small);
        const bounded = try self.fresh("bounded");
        try self.append(block, at_most_line, .{ bounded, low, max_signed });
        try parts.append(self.arena, bounded);
        const shifted = try self.fresh("shift");
        const summed = try self.fresh("sum");
        try self.append(block, "{s} =l shl {s}, 32", .{ shifted, high });
        try self.append(block, add_line, .{ summed, shifted, low });
        const inside = try self.fresh("inside");
        try self.append(block, at_most_line, .{ inside, summed, max_signed });
        try parts.append(self.arena, inside);
        const grown = try self.fresh("grown");
        try self.append(block, add_line, .{ grown, sums.total, summed });
        return grown;
    }

    const ConstantSums = struct { constant: u128, variable: u64, total: []const u8, count: []const u8 };

    fn verifyConstant(self: *Rewriter, block: *Block, sums: ConstantSums, parts: *std.ArrayList([]const u8)) Error![]const u8 {
        const limit = max_signed / sums.constant;
        const few = try self.fresh("few");
        try self.append(block, at_most_line, .{ few, sums.count, limit });
        try parts.append(self.arena, few);
        const steps = try self.fresh("steps");
        try self.append(block, "{s} =l mul {s}, {d}", .{ steps, sums.count, sums.constant });
        if (sums.variable != 0) {
            const under = try self.fresh("under");
            try self.append(block, at_most_line, .{ under, sums.total, max_signed });
            try parts.append(self.arena, under);
        }
        const grown = try self.fresh("grown");
        try self.append(block, add_line, .{ grown, sums.total, steps });
        return grown;
    }
};

fn contains(labels: []const []const u8, name: []const u8) bool {
    for (labels) |known| if (std.mem.eql(u8, known, name)) return true;
    return false;
}

fn stickyCheck(plan: *const Plan, terminator: *const Instruction) ?*const Check {
    for (plan.checks.sticky.items) |check| if (check.jnz == terminator) return check;
    return null;
}

fn firstSite(plan: *const Plan, terminator: *const Instruction) ?*const Check {
    for (plan.checks.sites.items) |site| if (site.check.jnz == terminator) return site.check;
    return null;
}

/// One saved piece of a written cell: its offset, width and the temporary holding it.
const Piece = struct { offset: u64, width: u64, saved: []const u8 };

/// The fast copy's bookkeeping names and snapshots.
const Bookkeeping = struct {
    sticky: []const u8,
    count: []const u8,
    cells: []const Cell = &.{},
    cells_written: []const []const u8 = &.{},
    snapshots: std.StringHashMapUnmanaged([]const Piece) = .empty,

    fn collect(self: *Bookkeeping, rewriter: *Rewriter) Error!void {
        var cells: std.ArrayList(Cell) = .empty;
        for (rewriter.plan.checks.sites.items) |site| {
            for (cells.items) |known| {
                if (known.eql(site.cell)) break;
            } else try cells.append(rewriter.arena, site.cell);
        }
        std.mem.sort(Cell, cells.items, {}, struct {
            fn less(_: void, left: Cell, right: Cell) bool {
                return left.less(right);
            }
        }.less);
        self.cells = cells.items;
        const written = try rewriter.arena.dupe([]const u8, rewriter.plan.cells.keys());
        std.mem.sort([]const u8, written, {}, struct {
            fn less(_: void, left: []const u8, right: []const u8) bool {
                return std.mem.lessThan(u8, left, right);
            }
        }.less);
        self.cells_written = written;
    }

    fn high(self: *const Bookkeeping, rewriter: *Rewriter, cell: Cell) Error![]const u8 {
        _ = self;
        return std.fmt.allocPrint(rewriter.arena, "%{s}.hi.{s}", .{ rewriter.prefix, cell.alloc });
    }
    fn low(self: *const Bookkeeping, rewriter: *Rewriter, cell: Cell) Error![]const u8 {
        _ = self;
        return std.fmt.allocPrint(rewriter.arena, "%{s}.lo.{s}", .{ rewriter.prefix, cell.alloc });
    }
};

/// Where each edge out of a fast-copy block goes: into the copy, to an exit
/// verification, or (for a trap) to the fallback.
const Targets = struct {
    rewriter: *Rewriter,
    cfg: *const Cfg,
    fallback: []const u8,
    exit_targets: std.ArrayList([]const u8) = .empty,
    exit_labels: std.ArrayList([]const u8) = .empty,
    traps: Labels = .empty,

    fn collect(self: *Targets) Error!void {
        const rewriter = self.rewriter;
        const plan = rewriter.plan;
        for (plan.exits.items) |target| {
            try self.exit_targets.append(rewriter.arena, target);
            const exit_name = try std.fmt.allocPrint(rewriter.arena, "@exit.{s}", .{std.mem.trimStart(u8, target, "@")});
            try self.exit_labels.append(rewriter.arena, try rewriter.label(exit_name));
        }
        for (plan.checks.traps.items) |check| try self.traps.put(rewriter.arena, check.trap_label, {});
        for (plan.checks.sticky.items) |check| try self.traps.put(rewriter.arena, check.trap_label, {});
        for (plan.checks.sites.items) |site| try self.traps.put(rewriter.arena, site.check.trap_label, {});
    }

    fn of(self: *Targets, name: []const u8) Error![]const u8 {
        const rewriter = self.rewriter;
        if (contains(rewriter.plan.body, name)) return rewriter.label(name);
        for (self.exit_targets.items, self.exit_labels.items) |target, exit| if (std.mem.eql(u8, target, name)) return exit;
        if (self.traps.contains(name)) return self.fallback;
        if (self.cfg.by_label.get(name)) |block| if (trapCall(block) != null) return self.fallback;
        return rewriter.diagnostic.fail(rewriter.arena, 0, "sticky loop edge to an unexpected block");
    }
};

/// Run the analysis of the first innermost loop of `text`.
fn firstLoopVerdict(arena: Allocator, text: []const u8) AnalysisError!void {
    var diagnostic: il.Diagnostic = .{};
    const unit = try il.parse(arena, text, &diagnostic);
    const cfg = try Cfg.of(arena, &unit.function);
    const frame = try Frame.of(arena, &unit.function);
    const loops = try naturalLoops(arena, &cfg);
    const plan = try arena.create(Plan);
    plan.* = .{ .header = loops[0].header, .body = loops[0].body };
    var body: Labels = .empty;
    for (loops[0].body) |label| try body.put(arena, label, {});
    var analysis: Analysis = .{ .arena = arena, .function = &unit.function, .cfg = &cfg, .frame = &frame, .plan = plan, .body = body };
    return analysis.run();
}

const counted_loop =
    \\export function l $f(l %ctx) {
    \\@start
    \\ %i =l alloc8 8
    \\ storel 0, %i
    \\ jmp @head
    \\@head
    \\ %v =l loadl %i
    \\ %c =l csltl %v, 10
    \\ jnz %c, @body, @done
    \\@body
    \\CALL
    \\ %w =l add %v, 1
    \\ storel %w, %i
    \\ jmp @head
    \\@done
    \\ ret 0
    \\}
;

// spec-case: LLVM-STICKY-REDUCTION-1
test "a loop that calls, or has no overflow check to drop, is left alone" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const calling = try std.mem.replaceOwned(u8, a, counted_loop, "CALL", " %x =l call $g(l %ctx)");
    try std.testing.expectError(error.Declined, firstLoopVerdict(a, calling));
    const plain = try std.mem.replaceOwned(u8, a, counted_loop, "CALL\n", "");
    try std.testing.expectError(error.Declined, firstLoopVerdict(a, plain));
}
