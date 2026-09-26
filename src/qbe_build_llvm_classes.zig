//! The facts the LLVM translator proves about one unit before emitting it
//! (LLVM-ZIG-1): which memory class each address names, which frontend
//! overflow formulas are exactly an intrinsic's overflow bit, the frame-map
//! call positions, and the dominance relation the loop versioning needs.
//!
//! Every analysis is deliberately partial. An address the unit does not place
//! beyond doubt carries no alias metadata, a flag that is not exactly a known
//! formula stays the frontend's own code, and a contradiction discards the
//! whole classification rather than emitting a fact it just disproved.
const std = @import("std");
const il = @import("qbe_build_llvm_il.zig");

const Allocator = std.mem.Allocator;
const Error = il.Error;
const Instruction = il.Instruction;
const Operand = il.Operand;

// ---------------------------------------------------------------------------
// Memory classes
// ---------------------------------------------------------------------------

/// One memory class: this activation's own stack storage (`frame`), storage
/// some other allocation owns (`foreign`), and the two refinements of a
/// foreign address the frontend marked: an object, or a container's element
/// storage of one element kind (LLVM-ELEMENT-CLASS-1).
pub const Class = union(enum) {
    frame,
    foreign,
    object,
    element: []const u8,

    /// Whether two classes are the same (an element class by its kind).
    pub fn eql(self: Class, other: Class) bool {
        return switch (self) {
            .element => |kind| other == .element and std.mem.eql(u8, kind, other.element),
            else => @backingInt(self) == @backingInt(other),
        };
    }
};

/// The runtime helpers whose C definition fixes the class of their result.
fn helperClass(name: []const u8) ?Class {
    if (std.mem.eql(u8, name, "myl_qbe_frame_allocate") or std.mem.eql(u8, name, "myl_qbe_frame_try_allocate")) return .frame;
    if (std.mem.eql(u8, name, "myl_qbe_heap")) return .foreign;
    return null;
}

const Names = std.StringHashMapUnmanaged(void);
const ClassMap = std.StringHashMapUnmanaged(Class);

/// How many times each temporary of a function is defined (parameters once).
pub fn definitionCounts(arena: Allocator, function: *const il.Function) Error!std.StringHashMapUnmanaged(u32) {
    var counts: std.StringHashMapUnmanaged(u32) = .empty;
    for (function.parameters) |parameter| try counts.put(arena, parameter.name, 1);
    for (function.blocks.items) |block| for (block.instructions.items) |instruction| {
        const dest = instruction.dest orelse continue;
        const entry = try counts.getOrPut(arena, dest);
        entry.value_ptr.* = if (entry.found_existing) entry.value_ptr.* + 1 else 1;
    };
    return counts;
}

/// Which memory class each temporary of one unit addresses.
pub const MemoryClasses = struct {
    arena: Allocator,
    function: *const il.Function,
    counts: std.StringHashMapUnmanaged(u32),
    slots: Names,
    classes: ClassMap = .empty,
    refined: ClassMap = .empty,
    conflict: bool = false,

    /// Classify every temporary of `function`; `sizes` names its aggregates.
    pub fn of(arena: Allocator, function: *const il.Function, sizes: *const std.StringHashMapUnmanaged(u64)) Error!MemoryClasses {
        var self: MemoryClasses = .{ .arena = arena, .function = function, .counts = try definitionCounts(arena, function), .slots = .empty };
        self.slots = try self.simpleSlots();
        try self.classify(sizes);
        if (self.conflict) self.classes = .empty;
        self.refined = try self.refine();
        return self;
    }

    /// The class of one operand, or null when the unit does not place it.
    pub fn operandClass(self: *const MemoryClasses, argument: Operand) ?Class {
        return switch (argument) {
            .global => .foreign,
            .temp => |ref| self.classes.get(ref.name),
            else => null,
        };
    }

    /// The class one access through `argument` is tagged with: a foreign
    /// address the frontend placed in an object or element storage answers
    /// that refinement, everything else its plain class.
    pub fn accessClass(self: *const MemoryClasses, argument: Operand) ?Class {
        const class = self.operandClass(argument) orelse return null;
        if (class == .foreign and argument == .temp) return self.refined.get(argument.temp.name) orelse class;
        return class;
    }

    fn single(self: *const MemoryClasses, name: []const u8) bool {
        return (self.counts.get(name) orelse 0) == 1;
    }

    /// Place one singly-defined temporary, reporting whether that is new.
    fn note(self: *MemoryClasses, name: []const u8, class: ?Class) Error!bool {
        const placed = class orelse return false;
        if (!self.single(name)) return false;
        if (self.classes.get(name)) |previous| {
            if (!previous.eql(placed)) self.conflict = true;
            return false;
        }
        try self.classes.put(self.arena, name, placed);
        return true;
    }

    /// Stack slots whose address is only ever the address of a `loadl` or a
    /// `storel`, allocated once.
    fn simpleSlots(self: *const MemoryClasses) Error!Names {
        var allocated: Names = .empty;
        for (self.function.blocks.items) |block| for (block.instructions.items) |instruction| {
            if (instruction.dest != null and instruction.opcode.isAlloc()) try allocated.put(self.arena, instruction.dest.?, {});
        };
        var escaped: Names = .empty;
        for (self.function.blocks.items) |block| for (block.instructions.items) |instruction| {
            for (instruction.args, 0..) |argument, index| {
                const name = argument.tempName() orelse continue;
                if (!allocated.contains(name)) continue;
                if (instruction.opcode == .loadl and index == 0) continue;
                if (instruction.opcode == .storel and index == 1) continue;
                try escaped.put(self.arena, name, {});
            }
            if (instruction.extra == .phi) for (instruction.extra.phi) |input| {
                const name = input.value.refName() orelse continue;
                if (allocated.contains(name)) try escaped.put(self.arena, name, {});
            };
        };
        var out: Names = .empty;
        var names = allocated.keyIterator();
        while (names.next()) |name| {
            if (!escaped.contains(name.*) and self.single(name.*)) try out.put(self.arena, name.*, {});
        }
        return out;
    }

    fn classify(self: *MemoryClasses, sizes: *const std.StringHashMapUnmanaged(u64)) Error!void {
        for (self.function.parameters) |parameter| {
            const aggregate = il.isAggregateName(parameter.letter) and sizes.contains(parameter.letter);
            _ = try self.note(parameter.name, if (aggregate) .frame else .foreign);
        }
        for (self.function.blocks.items) |block| for (block.instructions.items) |instruction| {
            const dest = instruction.dest orelse continue;
            if (instruction.opcode.isAlloc()) {
                _ = try self.note(dest, .frame);
            } else if (instruction.directTarget()) |target| {
                _ = try self.note(dest, helperClass(target));
            }
        };
        for (self.function.hints.objects.keys()) |name| _ = try self.note(name, .foreign);
        for (0..8) |_| {
            var changed = try self.derive();
            changed = (try self.throughSlots()) or changed;
            if (!changed or self.conflict) break;
        }
    }

    /// Carry a class through `copy` and through offsetting `add`.
    fn derive(self: *MemoryClasses) Error!bool {
        var changed = false;
        for (self.function.blocks.items) |block| for (block.instructions.items) |instruction| {
            const dest = instruction.dest orelse continue;
            if (instruction.opcode != .copy and instruction.opcode != .add) continue;
            if (self.classes.contains(dest)) continue;
            const seen = self.onlyClass(instruction.args, operandClassOf) orelse continue;
            changed = (try self.note(dest, seen)) or changed;
        };
        return changed;
    }

    fn operandClassOf(self: *const MemoryClasses, argument: Operand) ?Class {
        return self.operandClass(argument);
    }

    /// The one class every placed operand shares, or null when none is
    /// placed or two disagree.
    fn onlyClass(self: *const MemoryClasses, args: []const Operand, comptime class_of: fn (*const MemoryClasses, Operand) ?Class) ?Class {
        var found: ?Class = null;
        for (args) |argument| {
            const class = class_of(self, argument) orelse continue;
            if (found) |existing| {
                if (!existing.eql(class)) return null;
            } else found = class;
        }
        return found;
    }

    fn throughSlots(self: *MemoryClasses) Error!bool {
        var flow = try self.slotFlow(.coarse);
        var changed = false;
        var entries = flow.iterator();
        while (entries.next()) |entry| changed = (try self.note(entry.key_ptr.*, entry.value_ptr.*)) or changed;
        flow.deinit(self.arena);
        return changed;
    }

    /// Which view of a stored value `slotFlow` carries: its coarse class, or
    /// its refinement.
    const View = enum { coarse, refined };

    fn valueClass(self: *const MemoryClasses, view: View, value: Operand) ?Class {
        return switch (view) {
            .coarse => self.operandClass(value),
            .refined => if (value.tempName()) |name| self.refined.get(name) else null,
        };
    }

    /// The class of every load of a simple slot into a temporary, by a forward
    /// must-analysis over the blocks in priority order of their position.
    fn slotFlow(self: *const MemoryClasses, view: View) Error!ClassMap {
        const blocks = self.function.blocks.items;
        var index: std.StringHashMapUnmanaged(usize) = .empty;
        for (blocks, 0..) |block, position| try index.put(self.arena, block.label, position);
        const states = try self.arena.alloc(?ClassMap, blocks.len);
        @memset(states, null);
        states[0] = .empty;
        var queued = try std.DynamicBitSetUnmanaged.initEmpty(self.arena, blocks.len);
        queued.set(0);
        var loads: ClassMap = .empty;
        var found: std.array_hash_map.String(?Class) = .empty;
        while (queued.findFirstSet()) |position| {
            queued.unset(position);
            var state = try states[position].?.clone(self.arena);
            for (blocks[position].instructions.items) |instruction| {
                if (self.storeTarget(instruction)) |slot| {
                    if (self.valueClass(view, instruction.args[0])) |class| try state.put(self.arena, slot, class) else _ = state.remove(slot);
                } else if (self.loadSource(instruction)) |slot| {
                    try found.put(self.arena, instruction.dest.?, state.get(slot));
                }
            }
            const following = if (position + 1 < blocks.len) blocks[position + 1].label else null;
            var successors = try successorLabels(self.arena, blocks[position], following);
            for (successors.items) |label| {
                const target = index.get(label) orelse continue;
                if (try mergeInto(self.arena, &states[target], &state)) queued.set(target);
            }
            successors.deinit(self.arena);
        }
        for (found.keys(), found.values()) |name, class| if (class) |placed| try loads.put(self.arena, name, placed);
        return loads;
    }

    fn storeTarget(self: *const MemoryClasses, instruction: *const Instruction) ?[]const u8 {
        if (instruction.opcode != .storel or instruction.args.len != 2) return null;
        const name = instruction.args[1].tempName() orelse return null;
        return if (self.slots.contains(name)) name else null;
    }

    fn loadSource(self: *const MemoryClasses, instruction: *const Instruction) ?[]const u8 {
        if (instruction.opcode != .loadl or instruction.dest == null or instruction.args.len == 0) return null;
        const name = instruction.args[0].tempName() orelse return null;
        return if (self.slots.contains(name)) name else null;
    }

    /// Split the foreign addresses into objects and element storage, carried
    /// through `copy`, `add` and simple slots; any contradiction drops the
    /// whole refinement.
    fn refine(self: *MemoryClasses) Error!ClassMap {
        var refined: ClassMap = .empty;
        const hints = &self.function.hints;
        for (hints.objects.keys()) |name| try self.seed(&refined, name);
        var elements = hints.elements.keyIterator();
        while (elements.next()) |name| try self.seed(&refined, name.*);
        self.refined = refined;
        for (0..8) |_| {
            const changed = (try self.refineRound()) orelse return .empty;
            const through = (try self.refineThroughSlots()) orelse return .empty;
            if (!changed and !through) break;
        }
        return self.refined;
    }

    fn seed(self: *const MemoryClasses, refined: *ClassMap, name: []const u8) Error!void {
        if (!self.single(name) or !self.isForeign(name)) return;
        const class: Class = if (self.function.hints.elements.get(name)) |kind| .{ .element = kind } else .object;
        try refined.put(self.arena, name, class);
    }

    fn isForeign(self: *const MemoryClasses, name: []const u8) bool {
        const class = self.classes.get(name) orelse return false;
        return class == .foreign;
    }

    /// One pass over `copy`/`add`; null on a contradiction, else whether anything changed.
    fn refineRound(self: *MemoryClasses) Error!?bool {
        var changed = false;
        for (self.function.blocks.items) |block| for (block.instructions.items) |instruction| {
            const dest = instruction.dest orelse continue;
            if (instruction.opcode != .copy and instruction.opcode != .add) continue;
            if (!self.single(dest) or !self.isForeign(dest)) continue;
            var seen: ?Class = null;
            for (instruction.args) |argument| {
                const name = argument.tempName() orelse continue;
                const class = self.refined.get(name) orelse continue;
                if (seen) |existing| {
                    if (!existing.eql(class)) return null;
                } else seen = class;
            }
            const class = seen orelse continue;
            const result = (try self.refineOne(dest, class)) orelse return null;
            changed = changed or result;
        };
        return changed;
    }

    fn refineOne(self: *MemoryClasses, name: []const u8, class: Class) Error!?bool {
        if (self.refined.get(name)) |previous| {
            if (!previous.eql(class)) return null;
            return false;
        }
        try self.refined.put(self.arena, name, class);
        return true;
    }

    fn refineThroughSlots(self: *MemoryClasses) Error!?bool {
        var flow = try self.slotFlow(.refined);
        var changed = false;
        var entries = flow.iterator();
        while (entries.next()) |entry| {
            const name = entry.key_ptr.*;
            if (!self.single(name) or !self.isForeign(name)) continue;
            const result = (try self.refineOne(name, entry.value_ptr.*)) orelse return null;
            changed = changed or result;
        }
        return changed;
    }
};

/// Merge a block's outgoing state into a successor's incoming one by
/// intersection; true when the successor's state changed.
fn mergeInto(arena: Allocator, target: *?ClassMap, state: *const ClassMap) Error!bool {
    const previous = target.* orelse {
        target.* = try state.clone(arena);
        return true;
    };
    var merged: ClassMap = .empty;
    var entries = previous.iterator();
    while (entries.next()) |entry| {
        const class = state.get(entry.key_ptr.*) orelse continue;
        if (class.eql(entry.value_ptr.*)) try merged.put(arena, entry.key_ptr.*, class);
    }
    if (merged.count() == previous.count()) return false;
    target.* = merged;
    return true;
}

/// The labels control can reach from one block, fall-through included (a
/// `jnz` names both of its targets, even when they are the same).
pub fn successorLabels(arena: Allocator, block: *const il.Block, following: ?[]const u8) Error!std.ArrayList([]const u8) {
    var out: std.ArrayList([]const u8) = .empty;
    const terminator = block.terminator() orelse {
        if (following) |label| try out.append(arena, label);
        return out;
    };
    switch (terminator.opcode) {
        .jmp => try out.append(arena, terminator.extra.label),
        .jnz => try out.appendSlice(arena, &terminator.extra.branch),
        .ret, .hlt => {},
        else => if (following) |label| try out.append(arena, label),
    }
    return out;
}

// ---------------------------------------------------------------------------
// Checked arithmetic (LLVM-OVERFLOW-INTRINSIC-1)
// ---------------------------------------------------------------------------

/// The pure 64-bit opcodes the symbolic evaluation models.
fn pure(opcode: il.Opcode) bool {
    return switch (opcode) {
        .add, .sub, .mul, .@"and", .xor, .shr, .sar, .neg, .csltl, .cultl, .cnel => true,
        else => false,
    };
}

/// A symbolic value, hash-consed so equal computations share one id.
const NodeId = u32;

/// Interns symbolic values by a canonical text key.
const Nodes = struct {
    arena: Allocator,
    ids: std.StringHashMapUnmanaged(NodeId) = .empty,

    fn intern(self: *Nodes, key: []const u8) Error!NodeId {
        const entry = try self.ids.getOrPut(self.arena, key);
        if (!entry.found_existing) entry.value_ptr.* = @intCast(self.ids.count() - 1);
        return entry.value_ptr.*;
    }
    fn constant(self: *Nodes, value: u64) Error!NodeId {
        return self.intern(try std.fmt.allocPrint(self.arena, "c{d}", .{value}));
    }
    fn leaf(self: *Nodes, address: usize) Error!NodeId {
        return self.intern(try std.fmt.allocPrint(self.arena, "x{x}", .{address}));
    }
    fn named(self: *Nodes, tag: u8, name: []const u8) Error!NodeId {
        return self.intern(try std.fmt.allocPrint(self.arena, "{c}{s}", .{ tag, name }));
    }
    fn op(self: *Nodes, opcode: il.Opcode, left: NodeId, right: ?NodeId) Error!NodeId {
        if (right) |second| return self.intern(try std.fmt.allocPrint(self.arena, "o{s}:{d}:{d}", .{ @tagName(opcode), left, second }));
        return self.intern(try std.fmt.allocPrint(self.arena, "o{s}:{d}", .{ @tagName(opcode), left }));
    }
};

/// An overflow intrinsic stem (`llvm.<stem>.with.overflow.i64`).
pub const Stem = enum { sadd, uadd, ssub, usub, umul, smul };
/// A flag that is exactly one arithmetic instruction's overflow bit.
pub const Flag = struct { producer: *const Instruction, stem: Stem };
const Expected = struct { instruction: *const Instruction, stem: Stem };

/// The checked 64-bit operations of one unit, found by value: which
/// arithmetic instructions must also compute which intrinsics, and which
/// flag definitions are exactly one of those intrinsics' overflow bits.
pub const OverflowChecks = struct {
    producers: std.AutoHashMapUnmanaged(*const Instruction, std.ArrayList(Stem)) = .empty,
    flags: std.AutoHashMapUnmanaged(*const Instruction, Flag) = .empty,

    /// Scan every block of `function`; `excluded` names the temporaries that
    /// hold object addresses, whose `add` is lowered as a `getelementptr`.
    pub fn of(arena: Allocator, function: *const il.Function, excluded: *const Names) Error!OverflowChecks {
        var self: OverflowChecks = .{};
        var nodes: Nodes = .{ .arena = arena };
        for (function.blocks.items) |block| try self.scan(arena, &nodes, block, excluded);
        return self;
    }

    fn scan(self: *OverflowChecks, arena: Allocator, nodes: *Nodes, block: *const il.Block, excluded: *const Names) Error!void {
        var values: std.StringHashMapUnmanaged(NodeId) = .empty;
        var expected: std.AutoHashMapUnmanaged(NodeId, Expected) = .empty;
        for (block.instructions.items) |instruction| {
            const dest = instruction.dest orelse continue;
            // The operands' values are taken before the destination is
            // rebound: `%x =l add %x, 1` reads the old `%x`.
            const node = try evaluate(nodes, &values, instruction);
            if (expected.get(node.value)) |match| {
                try self.flags.put(arena, instruction, .{ .producer = match.instruction, .stem = match.stem });
                const entry = try self.producers.getOrPut(arena, match.instruction);
                if (!entry.found_existing) entry.value_ptr.* = .empty;
                if (std.mem.indexOfScalar(Stem, entry.value_ptr.items, match.stem) == null) try entry.value_ptr.append(arena, match.stem);
            }
            try values.put(arena, dest, node.value);
            const opcode = instruction.opcode;
            const checked = opcode == .add or opcode == .sub or opcode == .mul;
            if (checked and isPureNode(instruction) and !addressAdd(instruction, excluded)) {
                const formulas = try overflowFormulas(nodes, opcode, node);
                for (formulas) |formula| try expected.put(arena, formula.flag, .{ .instruction = instruction, .stem = formula.stem });
            }
        }
    }
};

fn isPureNode(instruction: *const Instruction) bool {
    const arity: usize = if (instruction.opcode == .neg) 1 else 2;
    const typed = instruction.qbe_type != null and std.mem.eql(u8, instruction.qbe_type.?, "l");
    return pure(instruction.opcode) and typed and instruction.args.len == arity;
}

/// A symbolic value and, for a pure operation, its operands' values.
const Evaluated = struct { value: NodeId, left: NodeId = 0, right: NodeId = 0 };

fn evaluate(nodes: *Nodes, values: *const std.StringHashMapUnmanaged(NodeId), instruction: *const Instruction) Error!Evaluated {
    if (!isPureNode(instruction)) return .{ .value = try nodes.leaf(@intFromPtr(instruction)) };
    const left = try operandValue(nodes, values, &instruction.args[0]);
    if (instruction.args.len == 1) return .{ .value = try nodes.op(instruction.opcode, left, null), .left = left };
    const right = try operandValue(nodes, values, &instruction.args[1]);
    return .{ .value = try nodes.op(instruction.opcode, left, right), .left = left, .right = right };
}

fn operandValue(nodes: *Nodes, values: *const std.StringHashMapUnmanaged(NodeId), argument: *const Operand) Error!NodeId {
    switch (argument.*) {
        .global => |ref| return nodes.named('g', ref.name),
        .temp => |ref| return values.get(ref.name) orelse nodes.named('e', ref.name),
        .constant => |literal| {
            const external = literal.qbe_type != null and std.mem.eql(u8, literal.qbe_type.?, "extern");
            if (!external) if (il.pythonInt(literal.text)) |value| return nodes.constant(value);
            return nodes.leaf(@intFromPtr(argument));
        },
        .call => return nodes.leaf(@intFromPtr(argument)),
    }
}

/// Whether an `add` has an object-address operand (lowered as a GEP).
fn addressAdd(instruction: *const Instruction, excluded: *const Names) bool {
    if (instruction.opcode != .add) return false;
    for (instruction.args) |argument| switch (argument) {
        .global => return true,
        .temp => |ref| if (excluded.contains(ref.name)) return true,
        else => {},
    };
    return false;
}

const Formula = struct { stem: Stem, flag: NodeId };

/// The (stem, flag) pairs the frontend derives from one `add`, `sub` or `mul`.
fn overflowFormulas(nodes: *Nodes, opcode: il.Opcode, evaluated: Evaluated) Error![2]Formula {
    const a = evaluated.left;
    const b = evaluated.right;
    const result = evaluated.value;
    const zero = try nodes.constant(0);
    switch (opcode) {
        .add => {
            const both = try nodes.op(.@"and", try nodes.op(.xor, a, result), try nodes.op(.xor, b, result));
            return .{ .{ .stem = .sadd, .flag = try nodes.op(.csltl, both, zero) }, .{ .stem = .uadd, .flag = try nodes.op(.cultl, result, a) } };
        },
        .sub => {
            const both = try nodes.op(.@"and", try nodes.op(.xor, a, b), try nodes.op(.xor, a, result));
            return .{ .{ .stem = .ssub, .flag = try nodes.op(.csltl, both, zero) }, .{ .stem = .usub, .flag = try nodes.op(.cultl, a, b) } };
        },
        else => {
            const high = try unsignedHigh(nodes, a, b);
            const a_sign = try nodes.op(.neg, try nodes.op(.csltl, a, zero), null);
            const b_sign = try nodes.op(.neg, try nodes.op(.csltl, b, zero), null);
            const signed_high = try nodes.op(.sub, try nodes.op(.sub, high, try nodes.op(.@"and", b, a_sign)), try nodes.op(.@"and", a, b_sign));
            const sign = try nodes.op(.sar, result, try nodes.constant(63));
            return .{ .{ .stem = .umul, .flag = try nodes.op(.cnel, high, zero) }, .{ .stem = .smul, .flag = try nodes.op(.cnel, signed_high, sign) } };
        },
    }
}

/// `qbe_scalar.unsignedHigh`: the high 64 bits of `a * b` over four 32-bit limbs.
fn unsignedHigh(nodes: *Nodes, a: NodeId, b: NodeId) Error!NodeId {
    const mask = try nodes.constant(0xFFFFFFFF);
    const shift = try nodes.constant(32);
    const low_a = try nodes.op(.@"and", a, mask);
    const low_b = try nodes.op(.@"and", b, mask);
    const high_a = try nodes.op(.shr, a, shift);
    const high_b = try nodes.op(.shr, b, shift);
    const base = try nodes.op(.mul, low_a, low_b);
    const middle = try nodes.op(.add, try nodes.op(.mul, high_a, low_b), try nodes.op(.shr, base, shift));
    const total = try nodes.op(.add, try nodes.op(.mul, low_a, high_b), try nodes.op(.@"and", middle, mask));
    const upper = try nodes.op(.add, try nodes.op(.mul, high_a, high_b), try nodes.op(.shr, middle, shift));
    return nodes.op(.add, upper, try nodes.op(.shr, total, shift));
}

// ---------------------------------------------------------------------------
// Frame-map call positions (QBE-FRAMEMAP-1)
// ---------------------------------------------------------------------------

/// First metadata number the frame-map debug nodes use.
pub const frame_map_metadata_base: u64 = 100;
/// The largest pseudo-probe index LLVM can encode in a discriminator.
const max_probe: u64 = 0xFFFF;

/// Call-site positions for a frame-map unit: each call gets a debug location
/// whose discriminator is a pseudo-probe index equal to its position.
pub const FrameMap = struct {
    file: ?[]const u8,
    active: bool,
    unprobed: bool,
    location: [2]u64 = .{ 0, 0 },
    locations: std.ArrayList([2]u64) = .empty,

    /// The frame-map facts of one parsed unit.
    pub fn of(unit: *const il.Unit) FrameMap {
        var any = false;
        var unprobed = false;
        for (unit.function.blocks.items) |block| for (block.instructions.items) |instruction| {
            if (instruction.opcode != .dbgloc) continue;
            any = true;
            const position = instruction.extra.position;
            if (probe(position) == null and position[0] != 0) unprobed = true;
        };
        return .{ .file = unit.debug_file, .active = unit.debug_file != null and any, .unprobed = unprobed };
    }

    /// The probe index one `dbgloc` position gets, or null.
    pub fn probe(position: [2]u64) ?u64 {
        if (position[1] == 1) return 0;
        if (position[0] >= 1 and position[0] <= max_probe) return position[0];
        return null;
    }

    /// LLVM's pseudo-probe discriminator for a direct-call probe `index`.
    pub fn discriminator(index: u64) u64 {
        return (index << 3) | (100 << 19) | (2 << 26) | 0x7;
    }

    /// The GUID LLVM derives from the subprogram's linkage name.
    pub fn guid(self: *const FrameMap) u64 {
        var digest: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(self.file.?, &digest, .{});
        return std.mem.readInt(u64, digest[0..8], .little);
    }

    /// The metadata number of one `(line, column)` debug location.
    pub fn reference(self: *FrameMap, arena: Allocator, location: [2]u64) Error!u64 {
        for (self.locations.items, 0..) |known, index| {
            if (known[0] == location[0] and known[1] == location[1]) return frame_map_metadata_base + 10 + 2 * index;
        }
        try self.locations.append(arena, location);
        return frame_map_metadata_base + 10 + 2 * (self.locations.items.len - 1);
    }

    /// Mark every call line `nomerge` and give it the current location.
    pub fn positionCalls(self: *FrameMap, arena: Allocator, lines: [][]const u8) Error!void {
        if (!self.active) return;
        const number = try self.reference(arena, self.location);
        const unprobed = probe(self.location) == null;
        for (lines) |*line| {
            if (!isCallLine(line.*)) continue;
            const plain = std.mem.indexOf(u8, line.*, "@llvm.") == null and std.mem.endsWith(u8, std.mem.trimEnd(u8, line.*, " \t\n\r\x0b\x0c"), ")");
            const suffix: []const u8 = if (!plain) "" else if (unprobed) " nomerge noinline" else " nomerge";
            line.* = try std.fmt.allocPrint(arena, "{s}{s}, !dbg !{d}", .{ line.*, suffix, number });
        }
    }

    /// The function attributes a frame-map unit's definition carries.
    pub fn attributes(self: *const FrameMap) []const []const u8 {
        if (!self.active) return &.{};
        if (self.unprobed) return &.{ "uwtable", "\"disable-tail-calls\"=\"true\"", "noinline" };
        return &.{ "uwtable", "\"disable-tail-calls\"=\"true\"" };
    }

    /// The named and numbered debug metadata for the module.
    pub fn metadata(self: *const FrameMap, arena: Allocator, out: *std.ArrayList([]const u8)) Error!void {
        if (!self.active) return;
        const base = frame_map_metadata_base;
        const name = try escapeName(arena, self.file.?);
        try out.append(arena, try std.fmt.allocPrint(arena, "!llvm.dbg.cu = !{{!{d}}}", .{base}));
        try out.append(arena, try std.fmt.allocPrint(arena, "!llvm.module.flags = !{{!{d}, !{d}}}", .{ base + 2, base + 3 }));
        try out.append(arena, try std.fmt.allocPrint(arena, "!llvm.pseudo_probe_desc = !{{!{d}}}", .{base + 7}));
        const unit = "!{d} = distinct !DICompileUnit(language: DW_LANG_C99, file: !{d}, producer: \"mylang\", " ++
            "isOptimized: true, runtimeVersion: 0, emissionKind: DebugDirectivesOnly)";
        try out.append(arena, try std.fmt.allocPrint(arena, unit, .{ base, base + 4 }));
        try out.append(arena, try std.fmt.allocPrint(arena, "!{d} = !DIFile(filename: \"{s}\", directory: \"\")", .{ base + 4, name }));
        const subprogram = "!{d} = distinct !DISubprogram(name: \"{s}\", linkageName: \"{s}\", scope: !{d}, file: !{d}, line: 1, " ++
            "type: !{d}, spFlags: DISPFlagDefinition | DISPFlagOptimized, unit: !{d})";
        try out.append(arena, try std.fmt.allocPrint(arena, subprogram, .{ base + 1, name, name, base + 4, base + 4, base + 5, base }));
        try out.append(arena, try std.fmt.allocPrint(arena, "!{d} = !DISubroutineType(types: !{d})", .{ base + 5, base + 6 }));
        try out.append(arena, try std.fmt.allocPrint(arena, "!{d} = !{{}}", .{base + 6}));
        try out.append(arena, try std.fmt.allocPrint(arena, "!{d} = !{{i32 7, !\"Dwarf Version\", i32 4}}", .{base + 2}));
        try out.append(arena, try std.fmt.allocPrint(arena, "!{d} = !{{i32 2, !\"Debug Info Version\", i32 3}}", .{base + 3}));
        try out.append(arena, try std.fmt.allocPrint(arena, "!{d} = !{{i64 {d}, i64 0, !\"{s}\"}}", .{ base + 7, self.guid(), name }));
        for (self.locations.items, 0..) |location, index| {
            const number = base + 10 + 2 * index;
            var scope = try std.fmt.allocPrint(arena, "!{d}", .{base + 1});
            if (probe(location)) |probe_index| {
                try out.append(arena, try std.fmt.allocPrint(arena, "!{d} = !DILexicalBlockFile(scope: !{d}, file: !{d}, discriminator: {d})", .{ number + 1, base + 1, base + 4, discriminator(probe_index) }));
                scope = try std.fmt.allocPrint(arena, "!{d}", .{number + 1});
            }
            try out.append(arena, try std.fmt.allocPrint(arena, "!{d} = !DILocation(line: {d}, column: {d}, scope: {s})", .{ number, location[0], location[1], scope }));
        }
    }
};

/// The file name with backslashes and quotes escaped for LLVM metadata.
fn escapeName(arena: Allocator, name: []const u8) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (name) |c| {
        if (c == '\\') try out.appendSlice(arena, "\\\\") else if (c == '"') try out.appendSlice(arena, "\\\"") else try out.append(arena, c);
    }
    return out.items;
}

/// `^\s*(?:%[\w.]+ = )?call `: a call line in the emitted LLVM.
fn isCallLine(line: []const u8) bool {
    var rest = std.mem.trimStart(u8, line, " \t\n\r\x0b\x0c");
    if (rest.len != 0 and rest[0] == '%') {
        var at: usize = 1;
        while (at < rest.len and (il.isWord(rest[at]) or rest[at] == '.')) at += 1;
        if (at > 1 and std.mem.startsWith(u8, rest[at..], " = ")) rest = rest[at + 3 ..];
    }
    return std.mem.startsWith(u8, rest, "call ");
}

// ---------------------------------------------------------------------------
// Dominators
// ---------------------------------------------------------------------------

/// The dominance relation of one control-flow graph over block indices,
/// computed by Cooper, Harvey and Kennedy's iterative algorithm over reverse
/// postorder and answered by entry/exit numbers of the dominator tree.
pub const Dominators = struct {
    enter: []?usize,
    leave: []usize,

    /// Build the relation for `edges` (successor indices per block) from block 0.
    pub fn of(arena: Allocator, edges: []const []const usize) Error!Dominators {
        const count = edges.len;
        const postorder = try depthFirstPostorder(arena, edges);
        const rank = try arena.alloc(usize, count);
        for (postorder, 0..) |block, index| rank[block] = index;
        const predecessors = try arena.alloc(std.ArrayList(usize), count);
        for (predecessors) |*list| list.* = .empty;
        const reached = try arena.alloc(bool, count);
        @memset(reached, false);
        for (postorder) |block| reached[block] = true;
        for (postorder) |block| for (edges[block]) |successor| try predecessors[successor].append(arena, block);
        const idom = try arena.alloc(?usize, count);
        @memset(idom, null);
        idom[0] = 0;
        var changed = true;
        while (changed) {
            changed = false;
            var index = postorder.len - 1;
            while (index > 0) {
                index -= 1;
                const block = postorder[index];
                var chosen: ?usize = null;
                for (predecessors[block].items) |predecessor| {
                    if (idom[predecessor] == null) continue;
                    chosen = if (chosen) |current| meet(idom, rank, predecessor, current) else predecessor;
                }
                if (chosen != null and idom[block] != chosen) {
                    idom[block] = chosen;
                    changed = true;
                }
            }
        }
        return numberTree(arena, idom);
    }

    /// Whether every path from the entry to `block` passes `dominator`.
    pub fn dominates(self: *const Dominators, dominator: usize, block: usize) bool {
        const first = self.enter[dominator] orelse return false;
        const second = self.enter[block] orelse return false;
        return first <= second and self.leave[block] <= self.leave[dominator];
    }
};

fn depthFirstPostorder(arena: Allocator, edges: []const []const usize) Error![]usize {
    var postorder: std.ArrayList(usize) = .empty;
    const seen = try arena.alloc(bool, edges.len);
    @memset(seen, false);
    const Frame = struct { block: usize, next: usize };
    var stack: std.ArrayList(Frame) = .empty;
    seen[0] = true;
    try stack.append(arena, .{ .block = 0, .next = 0 });
    while (stack.items.len != 0) {
        const top = &stack.items[stack.items.len - 1];
        var advanced = false;
        while (top.next < edges[top.block].len) {
            const successor = edges[top.block][top.next];
            top.next += 1;
            if (seen[successor]) continue;
            seen[successor] = true;
            try stack.append(arena, .{ .block = successor, .next = 0 });
            advanced = true;
            break;
        }
        if (advanced) continue;
        try postorder.append(arena, top.block);
        _ = stack.pop();
    }
    return postorder.items;
}

fn meet(idom: []const ?usize, rank: []const usize, left_start: usize, right_start: usize) usize {
    var left = left_start;
    var right = right_start;
    while (left != right) {
        while (rank[left] < rank[right]) left = idom[left].?;
        while (rank[right] < rank[left]) right = idom[right].?;
    }
    return left;
}

fn numberTree(arena: Allocator, idom: []const ?usize) Error!Dominators {
    const count = idom.len;
    const children = try arena.alloc(std.ArrayList(usize), count);
    for (children) |*list| list.* = .empty;
    for (idom, 0..) |parent, block| {
        if (parent == null or block == 0) continue;
        try children[parent.?].append(arena, block);
    }
    const enter = try arena.alloc(?usize, count);
    @memset(enter, null);
    const leave = try arena.alloc(usize, count);
    @memset(leave, 0);
    const Step = struct { block: usize, done: bool };
    var walk: std.ArrayList(Step) = .empty;
    try walk.append(arena, .{ .block = 0, .done = false });
    var clock: usize = 0;
    while (walk.pop()) |step| {
        if (step.done) {
            leave[step.block] = clock;
        } else {
            enter[step.block] = clock;
            try walk.append(arena, .{ .block = step.block, .done = true });
            for (children[step.block].items) |child| try walk.append(arena, .{ .block = child, .done = false });
        }
        clock += 1;
    }
    return .{ .enter = enter, .leave = leave };
}
