//! The LLVM translator's emitter state (LLVM-ZIG-1): every temporary's
//! private entry-block slot, operand rendering, the AMD64 SysV aggregate ABI,
//! call lowering and the alias metadata one unit's accesses name.
//!
//! The IL is not SSA: each temporary is a mutable cell, so each gets one slot
//! that its definitions store to and its uses load from, and LLVM's own
//! promotion recovers SSA. An aggregate value is the address of its storage,
//! an `i64` like any pointer-width value, turned into a pointer only by the
//! instruction that touches memory. No `nsw`/`nuw`/`exact`/fast-math flag and
//! no `inbounds` is ever emitted: the frontend emits its own checks.
const std = @import("std");
const il = @import("qbe_build_llvm_il.zig");
const classes = @import("qbe_build_llvm_classes.zig");
const runtime = @import("qbe_build_llvm_runtime.zig");

const Allocator = std.mem.Allocator;
const Error = il.Error;
const Instruction = il.Instruction;
const Operand = il.Operand;
/// The LLVM lines one instruction or block renders to.
pub const Lines = std.ArrayList([]const u8);
/// `%NAME = alloca TYPE, align N`: one stack allocation.
pub const alloca_line = "  %{s} = alloca {s}, align {d}";
/// `%NAME = ptrtoint ptr %POINTER to i64`: an address as the IL's integer.
pub const address_line = "  %{s} = ptrtoint ptr %{s} to i64";
const StringSet = std.StringHashMapUnmanaged(void);

/// How an aggregate crosses a call under AMD64 SysV: its storage, the
/// register value it is coerced to, or memory (`byval`/`sret`).
pub const Abi = struct {
    size: u64,
    alignment: u64,
    storage: []const u8,
    value: ?[]const u8,
    indirect: bool,

    /// Whether two classifications are the same shape.
    pub fn eql(self: Abi, other: Abi) bool {
        const values = if (self.value) |left| (other.value != null and std.mem.eql(u8, left, other.value.?)) else other.value == null;
        return self.size == other.size and self.alignment == other.alignment and values and self.indirect == other.indirect;
    }
};

/// The LLVM storage and coerced SysV value shape of an aggregate of `size` bytes.
pub fn aggregateAbi(arena: Allocator, size: u64, alignment: u64, force_memory: bool) Error!Abi {
    const storage = try std.fmt.allocPrint(arena, "[{d} x i8]", .{size});
    var value: ?[]const u8 = null;
    if (size <= 8) {
        value = try std.fmt.allocPrint(arena, "i{d}", .{size * 8});
    } else if (size <= 16) {
        const tail = (size - 8) * 8;
        value = if (tail == 64) "{ i64, i64 }" else try std.fmt.allocPrint(arena, "{{ i64, i{d} }}", .{tail});
    }
    return .{ .size = size, .alignment = alignment, .storage = storage, .value = value, .indirect = force_memory or value == null };
}

/// A parameter or result shape: a scalar LLVM type, or an aggregate ABI.
pub const Shape = union(enum) {
    scalar: []const u8,
    aggregate: Abi,

    /// Whether two shapes are the same.
    pub fn eql(self: Shape, other: Shape) bool {
        return switch (self) {
            .scalar => |name| other == .scalar and std.mem.eql(u8, name, other.scalar),
            .aggregate => |abi| other == .aggregate and abi.eql(other.aggregate),
        };
    }
};

/// One unit of this build as a caller sees it: its parameter letters and
/// result letter (null for none).
pub const CallSignature = struct { parameters: []const []const u8, result: ?[]const u8 };
/// Every unit of the build's closure, by symbol.
pub const Signatures = std.StringHashMapUnmanaged(CallSignature);

/// Where a declaration came from.
pub const Origin = enum { external, intrinsic, undefined };
/// One declared symbol: its parameters, its result and its origin.
pub const Declaration = struct { parameters: []const Shape, result: Shape, origin: Origin };

/// What a translation reads besides the unit: the closure's signatures, the
/// runtime helper registry, the target policy and the A/B switches.
pub const Options = struct {
    signatures: *const Signatures,
    runtime: *const runtime.Table,
    target_cpu: []const u8 = "",
    target_features: []const u8 = "",
    alias: bool = true,
    element_gep: bool = true,
    sticky: bool = true,
};

/// One temporary's slot: its entry-block pointer, the LLVM type it holds and its size.
pub const Slot = struct { pointer: []const u8, llvm: []const u8, size: u64 };
/// The buffer reserved in the entry block for one call's aggregate result.
pub const CallBuffer = struct { pointer: []const u8, abi: Abi };
/// A phi input stored on the edge out of its predecessor.
pub const PhiStore = struct { instruction: *const Instruction, value: Operand };
/// An overflow bit one checked arithmetic instruction computed.
pub const BitKey = struct { producer: *const Instruction, stem: classes.Stem };

/// What the unit's analyses established before emission.
pub const Facts = struct {
    types: il.Types = .{},
    pointers: StringSet = .empty,
    stack_guard: ?*const Instruction = null,
    overflow: classes.OverflowChecks = .{},
    memory: ?classes.MemoryClasses = null,
    single: StringSet = .empty,
    rewrites: Rewrites = .{},
};

/// What emission renders differently from the instruction it reads: the
/// stores a phi needs on each incoming edge, and every marked RC prefix
/// address by the payload and constant offset it was computed from
/// (LLVM-RC-PREFIX-1).
pub const Rewrites = struct {
    phi_stores: std.StringHashMapUnmanaged(std.ArrayList(PhiStore)) = .empty,
    prefix_bases: std.StringHashMapUnmanaged(PrefixBase) = .empty,
};

/// A singly-defined `sub`/`add` of a singly-defined payload and a constant.
pub const PrefixBase = struct { payload: Operand, offset: i64 };

/// The block being emitted: where each temporary it defined so far was
/// defined, and the position of the instruction being emitted.
pub const BlockState = struct {
    positions: std.StringHashMapUnmanaged(usize) = .empty,
    definitions: std.StringHashMapUnmanaged(*const Instruction) = .empty,
    position: usize = 0,
};

/// Fresh names, slots and per-instruction results.
pub const Names = struct {
    counter: usize = 0,
    slots: std.StringHashMapUnmanaged(Slot) = .empty,
    slot_lines: Lines = .empty,
    call_buffers: std.AutoHashMapUnmanaged(*const Instruction, CallBuffer) = .empty,
    overflow_bits: std.AutoHashMapUnmanaged(BitKey, []const u8) = .empty,
    block: BlockState = .{},
};

/// Which alias metadata the module must define: any memory class at all, and
/// the RC prefix scope (LLVM-RC-PREFIX-1).
pub const MetadataUse = struct { alias: bool = false, prefix: bool = false, rc_state: bool = false };

/// A scope list a two-class copy names, by its sorted members.
pub const ScopeList = struct { members: []const u64, number: u64 };

/// What the module around the function declares.
pub const Module = struct {
    globals: std.array_hash_map.String(void) = .empty,
    declarations: std.array_hash_map.String(Declaration) = .empty,
    attributes: std.array_hash_map.String(void) = .empty,
    metadata: MetadataUse = .{},
    element_kinds: std.ArrayList([]const u8) = .empty,
    scope_lists: std.ArrayList(ScopeList) = .empty,
    frame_map: classes.FrameMap = .{ .file = null, .active = false, .unprobed = false },
};

/// The element scopes are `!(element_base + 3j)` for element kind j.
pub const element_base: u64 = 11;
/// The object scope.
pub const object_scope: u64 = 5;
/// The RC prefix scope (LLVM-RC-PREFIX-1): `!8`, its list `!9`, and `!10`
/// listing every scope a prefix word never aliases.
pub const prefix_scope: u64 = 8;
/// RC-SCOPE-IL-1 bookkeeping scope, outside element and copy-list numbering.
pub const rc_state_scope: u64 = 9999997;
/// Element kinds beyond this many stay plainly foreign.
const max_element_kinds = 29;
/// Scope lists a copy between two classes names are numbered from here.
const scope_list_base: u64 = 10000000;

/// One call as the emitter renders it.
pub const Call = struct {
    target: il.Target,
    args: []const Operand,
    wanted: ?[]const u8,
    annotated: ?[]const u8 = null,
    result_pointer: ?[]const u8 = null,
};
/// A rendered call's value and the aggregate ABI of its result, if any.
pub const Rendered = struct { value: []const u8, aggregate: ?Abi };

/// Translates one parsed QBE unit into a self-contained LLVM module.
pub const Emitter = struct {
    arena: Allocator,
    unit: *il.Unit,
    options: Options,
    diagnostic: *il.Diagnostic,
    facts: Facts = .{},
    names: Names = .{},
    module: Module = .{},

    /// Run every analysis of `unit` and reserve its slots.
    pub fn prepare(arena: Allocator, unit: *il.Unit, options: Options, diagnostic: *il.Diagnostic) Error!Emitter {
        var self: Emitter = .{ .arena = arena, .unit = unit, .options = options, .diagnostic = diagnostic };
        const function = &unit.function;
        self.facts.types = try il.inferTypes(arena, unit, diagnostic);
        const counts = try classes.definitionCounts(arena, function);
        self.facts.pointers = try self.findPointerValues(&counts);
        self.facts.stack_guard = try self.findStackGuardCompare();
        self.facts.overflow = try classes.OverflowChecks.of(arena, function, &self.facts.pointers);
        try self.assignSlots();
        try self.collectPhiStores();
        if (options.alias) self.facts.memory = try classes.MemoryClasses.of(arena, function, &unit.sizes);
        self.module.frame_map = classes.FrameMap.of(unit);
        var names = counts.iterator();
        while (names.next()) |entry| if (entry.value_ptr.* == 1) try self.facts.single.put(arena, entry.key_ptr.*, {});
        try self.findPrefixBases();
        return self;
    }

    /// LLVM-RC-PREFIX-1: each marked prefix address that is a constant offset
    /// from a payload whose value never changes, so every access through it
    /// can be a `getelementptr` from that payload.
    fn findPrefixBases(self: *Emitter) Error!void {
        const function = &self.unit.function;
        if (function.hints.prefixes.count() == 0) return;
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| {
            const dest = instruction.dest orelse continue;
            if (!function.hints.prefixes.contains(dest) or !self.facts.single.contains(dest)) continue;
            if ((instruction.opcode != .sub and instruction.opcode != .add) or instruction.args.len != 2) continue;
            const payload = instruction.args[0];
            const name = payload.tempName() orelse continue;
            if (!self.facts.single.contains(name)) continue;
            const literal = switch (instruction.args[1]) {
                .constant => |value| value,
                else => continue,
            };
            const magnitude = std.fmt.parseInt(i64, literal.text, 10) catch continue;
            if (magnitude < 0 or magnitude > 64) continue;
            const offset = if (instruction.opcode == .sub) -magnitude else magnitude;
            try self.facts.rewrites.prefix_bases.put(self.arena, dest, .{ .payload = payload, .offset = offset });
        };
    }

    /// Record a refusal and return `TranslationFailed`.
    pub fn fail(self: *Emitter, message: []const u8) Error {
        return self.diagnostic.fail(self.arena, 0, message);
    }

    /// Append one formatted line.
    pub fn line(self: *Emitter, lines: *Lines, comptime format: []const u8, arguments: anytype) Error!void {
        try lines.append(self.arena, try std.fmt.allocPrint(self.arena, format, arguments));
    }

    /// Format a string in the translation's arena.
    pub fn print(self: *Emitter, comptime format: []const u8, arguments: anytype) Error![]const u8 {
        return std.fmt.allocPrint(self.arena, format, arguments);
    }

    // -- facts -------------------------------------------------------------

    /// The byte size of an aggregate type name defined by this unit, or null.
    pub fn aggregateBytes(self: *const Emitter, letter: ?[]const u8) ?u64 {
        const name = letter orelse return null;
        if (!il.isAggregateName(name)) return null;
        return self.unit.sizes.get(name);
    }

    /// The ABI of an aggregate type name, or null when it is not one.
    pub fn abiOf(self: *Emitter, letter: ?[]const u8, force_memory: bool) Error!?Abi {
        const size = self.aggregateBytes(letter) orelse return null;
        const abi = try aggregateAbi(self.arena, size, self.unit.alignments.get(letter.?).?, force_memory);
        return abi;
    }

    /// The type of a temporary, a pointer-width integer when none was inferred.
    pub fn typeOf(self: *const Emitter, name: []const u8) il.Type {
        return self.facts.types.get(name) orelse .{ .kind = .int, .bits = 64 };
    }

    /// The LLVM type of a temporary's slot.
    pub fn llvmOf(self: *const Emitter, name: []const u8) []const u8 {
        return self.typeOf(name).llvm();
    }

    /// Values whose bits retain an object-address origin: allocations,
    /// aggregate parameters, pointer-returning helpers and aggregate call
    /// results, and copies and additions derived from them or from globals.
    fn findPointerValues(self: *Emitter, counts: *const std.StringHashMapUnmanaged(u32)) Error!StringSet {
        var pointers: StringSet = .empty;
        const function = &self.unit.function;
        for (function.parameters) |parameter| {
            if (self.aggregateBytes(parameter.letter) != null and (counts.get(parameter.name) orelse 0) == 1) try pointers.put(self.arena, parameter.name, {});
        }
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| {
            const dest = instruction.dest orelse continue;
            if ((counts.get(dest) orelse 0) != 1) continue;
            if (instruction.opcode.isAlloc() or self.addressResult(instruction)) try pointers.put(self.arena, dest, {});
        };
        var changed = true;
        while (changed) {
            changed = false;
            for (function.blocks.items) |block| for (block.instructions.items) |instruction| {
                const dest = instruction.dest orelse continue;
                if ((counts.get(dest) orelse 0) != 1 or pointers.contains(dest)) continue;
                if (instruction.opcode != .copy and instruction.opcode != .add) continue;
                if (!derivesAddress(instruction, &pointers)) continue;
                try pointers.put(self.arena, dest, {});
                changed = true;
            };
        }
        return pointers;
    }

    /// Whether a call's result is an address: an exact runtime signature
    /// returning `ptr`, or an aggregate result annotation.
    fn addressResult(self: *const Emitter, instruction: *const Instruction) bool {
        if (instruction.opcode != .call) return false;
        if (instruction.directTarget()) |name| {
            if (self.options.runtime.signature(name)) |exact| if (std.mem.eql(u8, exact.result, "ptr")) return true;
        }
        return self.aggregateBytes(instruction.qbe_type) != null;
    }

    fn derivesAddress(instruction: *const Instruction, pointers: *const StringSet) bool {
        for (instruction.args) |argument| switch (argument) {
            .global => return true,
            .temp => |ref| if (pointers.contains(ref.name)) return true,
            else => {},
        };
        return false;
    }

    /// The frontend's physical stack-floor comparison, identified by shape:
    /// an unsigned-less comparison of a fresh allocation against the floor
    /// word loaded from `%ctx + 64`, feeding a branch with one floor-failure
    /// and one stack-admission successor.
    fn findStackGuardCompare(self: *Emitter) Error!?*const Instruction {
        for (self.unit.function.blocks.items) |block| for (block.instructions.items, 0..) |branch, branch_index| {
            if (branch.opcode != .jnz or !guardShaped(branch.extra.branch)) continue;
            const prologue: Prologue = .{ .instructions = block.instructions.items[0..branch_index] };
            if (prologue.guard(branch.args[0], branch_index)) |found| return found;
            return self.fail(try self.print("{s}: stack-floor branch does not match the checked allocation/load/compare shape", .{self.unit.function.name}));
        };
        return null;
    }

    // -- slots -------------------------------------------------------------

    /// A fresh LLVM local name.
    pub fn fresh(self: *Emitter, stem: []const u8) Error![]const u8 {
        self.names.counter += 1;
        return self.print("{s}{d}", .{ stem, self.names.counter });
    }

    /// Give every temporary one slot in the entry block, and every call with
    /// an aggregate result its buffer.
    fn assignSlots(self: *Emitter) Error!void {
        const function = &self.unit.function;
        for (function.parameters) |parameter| {
            if (self.aggregateBytes(parameter.letter) == null) _ = try self.slot(parameter.name);
        }
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| {
            const dest = instruction.dest orelse continue;
            _ = try self.slot(dest);
            const abi = (try self.abiOf(instruction.qbe_type, false)) orelse continue;
            if (instruction.opcode != .call) continue;
            const pointer = try self.fresh("callresult");
            try self.names.call_buffers.put(self.arena, instruction, .{ .pointer = pointer, .abi = abi });
            try self.line(&self.names.slot_lines, alloca_line, .{ pointer, abi.storage, abi.alignment });
        };
    }

    /// The slot of one temporary, created on first use.
    pub fn slot(self: *Emitter, name: []const u8) Error!Slot {
        if (self.names.slots.get(name)) |existing| return existing;
        const kind = self.typeOf(name);
        const size: u64 = if (kind.kind != .float or kind.bits == 64) 8 else 4;
        const pointer = try self.fresh("slot");
        const created: Slot = .{ .pointer = pointer, .llvm = kind.llvm(), .size = size };
        try self.names.slots.put(self.arena, name, created);
        try self.line(&self.names.slot_lines, alloca_line, .{ pointer, created.llvm, @min(size, 8) });
        return created;
    }

    /// Load a temporary's current value.
    pub fn loadSlot(self: *Emitter, lines: *Lines, name: []const u8) Error![]const u8 {
        const held = try self.slot(name);
        const value = try self.fresh("v");
        try self.line(lines, "  %{s} = load {s}, ptr %{s}, align {d}", .{ value, held.llvm, held.pointer, @min(held.size, 8) });
        return self.print("%{s}", .{value});
    }

    /// Store a value into a temporary's slot.
    pub fn storeSlot(self: *Emitter, lines: *Lines, name: []const u8, value: []const u8) Error!void {
        const held = try self.slot(name);
        try self.line(lines, "  store {s} {s}, ptr %{s}, align {d}", .{ held.llvm, value, held.pointer, @min(held.size, 8) });
    }

    /// An `inttoptr` of an integer address.
    pub fn address(self: *Emitter, lines: *Lines, value: []const u8) Error![]const u8 {
        const pointer = try self.fresh("p");
        try self.line(lines, "  %{s} = inttoptr i64 {s} to ptr", .{ pointer, value });
        return self.print("%{s}", .{pointer});
    }

    fn collectPhiStores(self: *Emitter) Error!void {
        const function = &self.unit.function;
        var known: StringSet = .empty;
        for (function.blocks.items) |block| try known.put(self.arena, block.label, {});
        for (function.blocks.items) |block| for (block.instructions.items) |instruction| {
            if (instruction.opcode != .phi) continue;
            for (instruction.extra.phi) |input| {
                if (!known.contains(input.label)) return self.fail(try self.print("phi in {s} names `{s}`, which is not a block of ${s}", .{ block.label, input.label, function.name }));
                const entry = try self.facts.rewrites.phi_stores.getOrPut(self.arena, input.label);
                if (!entry.found_existing) entry.value_ptr.* = .empty;
                try entry.value_ptr.append(self.arena, .{ .instruction = instruction, .value = input.value });
            }
        };
    }

    // -- operands ----------------------------------------------------------

    /// Render an operand as an LLVM value of type `llvm`; `lines` collects
    /// any instruction a widening or a nested call needs.
    pub fn render(self: *Emitter, lines: *Lines, argument: Operand, llvm: []const u8) Error![]const u8 {
        switch (argument) {
            .global => |ref| return self.globalAddress(ref.name),
            .temp => |ref| {
                const value = try self.loadSlot(lines, ref.name);
                return self.widen(lines, value, self.llvmOf(ref.name), llvm);
            },
            .call => |call| {
                const rendered = try self.renderCall(lines, .{ .target = call.target, .args = call.args, .wanted = llvm });
                return rendered.value;
            },
            .constant => |literal| return self.constant(literal, llvm),
        }
    }

    /// Render a literal as an LLVM constant of type `llvm`.
    fn constant(self: *Emitter, literal: il.Literal, llvm: []const u8) Error![]const u8 {
        if (literal.qbe_type != null and std.mem.eql(u8, literal.qbe_type.?, "extern")) {
            try self.module.globals.put(self.arena, literal.text, {});
            return self.print("ptrtoint (ptr @{s} to i64)", .{literal.text});
        }
        if (std.mem.eql(u8, llvm, "double") or std.mem.eql(u8, llvm, "float")) {
            const value = il.pythonFloat(literal.text) orelse return self.fail(try self.print("cannot parse the float constant `{s}`", .{literal.text}));
            return self.floatConstant(value, llvm);
        }
        const bits = il.pythonInt(literal.text) orelse (try self.truncatedFloat(literal.text));
        const width = bitWidth(llvm) orelse return self.print("{d}", .{bits});
        const mask: u64 = if (width >= 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(width)) - 1;
        return self.print("{d}", .{bits & mask});
    }

    /// Python's `int(float(text))` modulo 2^64, for a literal `int` refuses.
    fn truncatedFloat(self: *Emitter, text: []const u8) Error!u64 {
        const refused = try self.print("cannot parse the constant `{s}`", .{text});
        const value = il.pythonFloat(text) orelse return self.fail(refused);
        if (std.math.isNan(value) or std.math.isInf(value) or @abs(value) >= 0x1p127) return self.fail(refused);
        const whole: i128 = @intFromFloat(value);
        return @truncate(@as(u128, @bitCast(whole)));
    }

    fn floatConstant(self: *Emitter, value: f64, llvm: []const u8) Error![]const u8 {
        if (std.math.isNan(value) or std.math.isInf(value)) {
            const bits: u64 = if (std.math.isNan(value)) 0x7FF8000000000000 else if (value > 0) 0x7FF0000000000000 else 0xFFF0000000000000;
            if (std.mem.eql(u8, llvm, "double")) return self.print("bitcast (i64 {d} to double)", .{bits});
            return self.print("bitcast (i32 {d} to float)", .{bits >> 32});
        }
        return pythonRepr(self.arena, value);
    }

    /// Register a `$symbol` global and return its address as an integer.
    pub fn globalAddress(self: *Emitter, name: []const u8) Error![]const u8 {
        try self.module.globals.put(self.arena, name, {});
        return self.print("ptrtoint (ptr @{s} to i64)", .{name});
    }

    /// Convert between two scalar types, appending an instruction if needed.
    /// Only `double`/`i64` is a bit reinterpretation; every other integer and
    /// float pair converts its value, unsigned, exactly as the adapter did.
    pub fn widen(self: *Emitter, lines: *Lines, value: []const u8, source: []const u8, target: []const u8) Error![]const u8 {
        if (std.mem.eql(u8, source, target)) return value;
        const source_bits = bitWidth(source);
        const target_bits = bitWidth(target);
        const name = try self.fresh("cv");
        const source_float = isFloat(source);
        const target_float = isFloat(target);
        const operation: []const u8 = if ((std.mem.eql(u8, source, "double") and std.mem.eql(u8, target, "i64")) or (std.mem.eql(u8, source, "i64") and std.mem.eql(u8, target, "double")))
            "bitcast"
        else if (source_bits != null and target_bits != null)
            (if (source_bits.? > target_bits.?) "trunc" else "zext")
        else if (source_bits != null and target_float)
            "uitofp"
        else if (source_float and target_bits != null)
            "fptoui"
        else if (std.mem.eql(u8, source, "float") and std.mem.eql(u8, target, "double"))
            "fpext"
        else if (std.mem.eql(u8, source, "double") and std.mem.eql(u8, target, "float"))
            "fptrunc"
        else
            return self.fail(try self.print("{s}: cannot convert {s} to {s}", .{ self.unit.function.name, source, target }));
        try self.line(lines, "  %{s} = {s} {s} {s} to {s}", .{ name, operation, source, value, target });
        return self.print("%{s}", .{name});
    }

    // -- memory classes ----------------------------------------------------

    /// The alias metadata one access through `argument` carries.
    pub fn aliasOf(self: *Emitter, argument: Operand) Error![]const u8 {
        const memory = if (self.facts.memory) |*known| known else return "";
        const suffix = try self.classSuffix(memory.accessClass(argument));
        if (suffix.len != 0) self.module.metadata.alias = true;
        return suffix;
    }

    fn classSuffix(self: *Emitter, class: ?classes.Class) Error![]const u8 {
        const placed = class orelse return "";
        return switch (placed) {
            .frame => ", !alias.scope !3, !noalias !4",
            .foreign => ", !alias.scope !4, !noalias !3",
            .object => ", !alias.scope !6, !noalias !7",
            .prefix => {
                self.module.metadata.prefix = true;
                return ", !alias.scope !9, !noalias !10";
            },
            .rc_state => {
                self.module.metadata.rc_state = true;
                return ", !alias.scope !9999998, !noalias !9999999";
            },
            .element => |kind| {
                const index = (try self.elementIndex(kind)) orelse return ", !alias.scope !4, !noalias !3";
                const scope = element_base + 3 * index;
                return self.print(", !alias.scope !{d}, !noalias !{d}", .{ scope + 1, scope + 2 });
            },
        };
    }

    /// The index of an element kind, registering it on first use; null once
    /// the unit has used as many kinds as the numbering leaves room for.
    fn elementIndex(self: *Emitter, kind: []const u8) Error!?u64 {
        for (self.module.element_kinds.items, 0..) |known, index| if (std.mem.eql(u8, known, kind)) return index;
        if (self.module.element_kinds.items.len >= max_element_kinds) return null;
        try self.module.element_kinds.append(self.arena, kind);
        return self.module.element_kinds.items.len - 1;
    }

    /// (own scopes, scopes it cannot alias) of one memory class.
    fn classScopes(self: *Emitter, class: classes.Class) Error![2][]const u64 {
        switch (class) {
            .frame => return .{ &.{1}, &.{2} },
            .foreign => return .{ &.{2}, &.{1} },
            else => {},
        }
        var kinds: std.ArrayList(u64) = .empty;
        for (0..self.module.element_kinds.items.len) |index| try kinds.append(self.arena, element_base + 3 * index);
        if (class == .object) {
            var apart: std.ArrayList(u64) = .empty;
            try apart.append(self.arena, 1);
            try apart.appendSlice(self.arena, kinds.items);
            return .{ try self.arena.dupe(u64, &.{object_scope}), apart.items };
        }
        if (class == .prefix) {
            self.module.metadata.prefix = true;
            var apart: std.ArrayList(u64) = .empty;
            try apart.appendSlice(self.arena, &.{ 1, object_scope });
            try apart.appendSlice(self.arena, kinds.items);
            return .{ try self.arena.dupe(u64, &.{prefix_scope}), apart.items };
        }
        if (class == .rc_state) {
            self.module.metadata.rc_state = true;
            var apart: std.ArrayList(u64) = .empty;
            try apart.appendSlice(self.arena, &.{ 1, object_scope });
            if (self.module.metadata.prefix) try apart.append(self.arena, prefix_scope);
            try apart.appendSlice(self.arena, kinds.items);
            return .{ try self.arena.dupe(u64, &.{rc_state_scope}), apart.items };
        }
        const index = (try self.elementIndex(class.element)) orelse return .{ &.{2}, &.{1} };
        const own = element_base + 3 * index;
        var apart: std.ArrayList(u64) = .empty;
        try apart.appendSlice(self.arena, &.{ 1, object_scope });
        for (kinds.items) |scope| if (scope != own) try apart.append(self.arena, scope);
        return .{ try self.arena.dupe(u64, &.{own}), apart.items };
    }

    fn scopeList(self: *Emitter, members: []const u64) Error!u64 {
        const sorted = try self.arena.dupe(u64, members);
        std.mem.sort(u64, sorted, {}, std.sort.asc(u64));
        for (self.module.scope_lists.items) |known| if (std.mem.eql(u64, known.members, sorted)) return known.number;
        const number = scope_list_base + self.module.scope_lists.items.len;
        try self.module.scope_lists.append(self.arena, .{ .members = sorted, .number = number });
        return number;
    }

    /// The metadata a two-address copy carries: both ends' scopes, and the
    /// scopes neither end can alias.
    pub fn aliasOfBoth(self: *Emitter, first: Operand, second: Operand) Error![]const u8 {
        const memory = if (self.facts.memory) |*known| known else return "";
        const left = memory.accessClass(first) orelse return "";
        const right = memory.accessClass(second) orelse return "";
        if (left.eql(right)) {
            const suffix = try self.classSuffix(left);
            if (suffix.len != 0) self.module.metadata.alias = true;
            return suffix;
        }
        const left_scopes = try self.classScopes(left);
        const right_scopes = try self.classScopes(right);
        self.module.metadata.alias = true;
        const own = try union64(self.arena, left_scopes[0], right_scopes[0]);
        var suffix = try self.print(", !alias.scope !{d}", .{try self.scopeList(own)});
        const apart = try intersection64(self.arena, left_scopes[1], right_scopes[1]);
        if (apart.len != 0) suffix = try self.print("{s}, !noalias !{d}", .{ suffix, try self.scopeList(apart) });
        return suffix;
    }

    // -- ABI ---------------------------------------------------------------

    /// Classify a whole signature, including SysV register rollback.
    pub fn parameterAbis(self: *Emitter, letters: []const []const u8, result_letter: ?[]const u8) Error![]Shape {
        const result = try self.abiOf(result_letter, false);
        var used: u64 = if (result != null and result.?.indirect) 1 else 0;
        const out = try self.arena.alloc(Shape, letters.len);
        for (letters, out) |letter, *shape| {
            if (try self.abiOf(letter, false)) |first| {
                const words = (first.size + 7) / 8;
                const aggregate = (try self.abiOf(letter, first.indirect or used + words > 6)).?;
                if (!aggregate.indirect) used += words;
                shape.* = .{ .aggregate = aggregate };
            } else {
                const llvm = try self.letterType(letter);
                if (!isFloat(llvm)) used += 1;
                shape.* = .{ .scalar = llvm };
            }
        }
        return out;
    }

    /// The LLVM type of a QBE type letter or aggregate name: `l` and every
    /// `:name` are pointer-width integers.
    pub fn letterType(self: *Emitter, letter: ?[]const u8) Error![]const u8 {
        const name = letter orelse return "i64";
        if (std.mem.eql(u8, name, "l") or il.isAggregateName(name)) return "i64";
        if (std.mem.eql(u8, name, "d")) return "double";
        if (std.mem.eql(u8, name, "s")) return "float";
        if (std.mem.eql(u8, name, "w")) return "i32";
        return self.fail(try self.print("unsupported type letter `{s}`", .{name}));
    }

    /// The return shape of a call to a function of this closure.
    fn declaredResult(self: *Emitter, declared: CallSignature) Error!Shape {
        const letter = declared.result orelse return .{ .scalar = "void" };
        if (letter.len == 0) return .{ .scalar = "void" };
        if (try self.abiOf(letter, false)) |abi| return .{ .aggregate = abi };
        return .{ .scalar = try self.letterType(letter) };
    }

    /// The parameters and result a closure or runtime symbol is declared with.
    pub fn knownSignature(self: *Emitter, name: []const u8) Error!?Declaration {
        if (self.options.runtime.signature(name)) |exact| {
            const parameters = try self.arena.alloc(Shape, exact.parameters.len);
            for (exact.parameters, parameters) |parameter, *shape| shape.* = .{ .scalar = parameter };
            return .{ .parameters = parameters, .result = .{ .scalar = exact.result }, .origin = .external };
        }
        const declared = (try self.closureSignature(name)) orelse return null;
        return .{ .parameters = try self.parameterAbis(declared.parameters, declared.result), .result = try self.declaredResult(declared), .origin = .external };
    }

    /// A closure unit's signature; the unit being translated always knows its own.
    fn closureSignature(self: *Emitter, name: []const u8) Error!?CallSignature {
        if (self.options.signatures.get(name)) |declared| return declared;
        const own = &self.unit.function;
        if (!std.mem.eql(u8, name, own.name)) return null;
        const letters = try self.arena.alloc([]const u8, own.parameters.len);
        for (own.parameters, letters) |parameter, *letter| letter.* = parameter.letter;
        return .{ .parameters = letters, .result = own.result };
    }

    /// Declare a symbol once; the first declaration wins.
    pub fn declare(self: *Emitter, name: []const u8, declaration: Declaration) Error!void {
        const entry = try self.module.declarations.getOrPut(self.arena, name);
        if (!entry.found_existing) entry.value_ptr.* = declaration;
    }

    /// Declare an LLVM intrinsic once.
    pub fn declareIntrinsic(self: *Emitter, name: []const u8, parameters: []const []const u8, result: []const u8) Error!void {
        const shapes = try self.arena.alloc(Shape, parameters.len);
        for (parameters, shapes) |parameter, *shape| shape.* = .{ .scalar = parameter };
        try self.declare(name, .{ .parameters = shapes, .result = .{ .scalar = result }, .origin = .intrinsic });
    }

    // -- calls -------------------------------------------------------------

    /// Render a call, returning its value and the aggregate ABI it holds.
    pub fn renderCall(self: *Emitter, lines: *Lines, call: Call) Error!Rendered {
        const name = switch (call.target) {
            .indirect => return self.renderIndirectCall(lines, call),
            .direct => |symbol| runtime.translatedCallee(symbol),
        };
        if (std.mem.eql(u8, name, "memset")) return self.renderMemset(lines, call.args);
        if (std.mem.eql(u8, name, self.unit.function.name)) try self.declare(name, .{ .parameters = &.{}, .result = .{ .scalar = "" }, .origin = .undefined });
        var signature: Declaration = undefined;
        if (try self.knownSignature(name)) |known| {
            signature = known;
            try self.declare(name, known);
        } else signature = try self.inferExternal(name, call);
        if (signature.parameters.len != call.args.len) {
            return self.fail(try self.print("{s}: call to ${s} passes {d} arguments but ${s} takes {d}", .{ self.unit.function.name, name, call.args.len, name, signature.parameters.len }));
        }
        const callee = try self.print("@{s}", .{name});
        return self.finishCall(lines, call, signature, callee, runtime.callingConvention(name));
    }

    /// `memset` lowers to the LLVM intrinsic, typed exactly.
    fn renderMemset(self: *Emitter, lines: *Lines, args: []const Operand) Error!Rendered {
        if (args.len != 3) return self.fail(try self.print("{s}: memset takes three arguments", .{self.unit.function.name}));
        try self.declareIntrinsic("llvm.memset.p0.i64", &.{ "ptr", "i8", "i64", "i1" }, "void");
        const target = try self.render(lines, args[0], "i64");
        const pointer = try self.address(lines, target);
        const fill = try self.render(lines, args[1], "i8");
        const length = try self.render(lines, args[2], "i64");
        try self.line(lines, "  call void @llvm.memset.p0.i64(ptr {s}, i8 {s}, i64 {s}, i1 false){s}", .{ pointer, fill, length, try self.aliasOf(args[0]) });
        return .{ .value = "0", .aggregate = null };
    }

    /// A call through a function value computed at run time, shaped by the
    /// call site's own operand spellings.
    fn renderIndirectCall(self: *Emitter, lines: *Lines, call: Call) Error!Rendered {
        const target = call.target.indirect;
        const loaded = try self.loadSlot(lines, target);
        const callee = try self.widen(lines, loaded, self.llvmOf(target), "i64");
        const pointer = try self.address(lines, callee);
        const signature = try self.callSiteSignature(call);
        return self.finishCall(lines, call, signature, pointer, "");
    }

    /// Render the arguments and the call itself for a known signature, under
    /// the callee's calling convention (`runtime.callingConvention`).
    fn finishCall(self: *Emitter, lines: *Lines, call: Call, signature: Declaration, callee: []const u8, convention: []const u8) Error!Rendered {
        var rendered = try self.renderArguments(lines, call.args, signature.parameters);
        const joined = try std.mem.join(self.arena, ", ", rendered.items);
        switch (signature.result) {
            .aggregate => |abi| if (abi.indirect) {
                const destination = call.result_pointer orelse try self.fresh("aggret");
                if (call.result_pointer == null) try self.line(lines, alloca_line, .{ destination, abi.storage, abi.alignment });
                try rendered.insert(self.arena, 0, try self.print("ptr sret({s}) align {d} %{s}", .{ abi.storage, abi.alignment, destination }));
                try self.line(lines, "  call {s}void {s}({s})", .{ convention, callee, try std.mem.join(self.arena, ", ", rendered.items) });
                return .{ .value = try self.print("%{s}", .{destination}), .aggregate = abi };
            },
            .scalar => |result| if (std.mem.eql(u8, result, "void")) {
                try self.line(lines, "  call {s}void {s}({s})", .{ convention, callee, joined });
                return .{ .value = "0", .aggregate = null };
            },
        }
        const aggregate: ?Abi = if (signature.result == .aggregate) signature.result.aggregate else null;
        const result_type = if (aggregate) |abi| abi.value.? else signature.result.scalar;
        const value = try self.fresh("call");
        try self.line(lines, "  %{s} = call {s}{s} {s}({s})", .{ value, convention, result_type, callee, joined });
        if (std.mem.eql(u8, result_type, "ptr")) {
            const integer = try self.fresh("calladdr");
            try self.line(lines, address_line, .{ integer, value });
            return .{ .value = try self.print("%{s}", .{integer}), .aggregate = aggregate };
        }
        return .{ .value = try self.print("%{s}", .{value}), .aggregate = aggregate };
    }

    /// Render every argument of a call in the shape its ABI classified.
    fn renderArguments(self: *Emitter, lines: *Lines, args: []const Operand, parameters: []const Shape) Error!Lines {
        var rendered: Lines = .empty;
        for (args, parameters) |argument, parameter| {
            switch (parameter) {
                .aggregate => |abi| {
                    const integer = try self.render(lines, argument, "i64");
                    const pointer = try self.address(lines, integer);
                    if (abi.indirect) {
                        try rendered.append(self.arena, try self.print("ptr byval({s}) align {d} {s}", .{ abi.storage, abi.alignment, pointer }));
                    } else {
                        const loaded = try self.fresh("arg");
                        try self.line(lines, "  %{s} = load {s}, ptr {s}, align {d}", .{ loaded, abi.value.?, pointer, abi.alignment });
                        try rendered.append(self.arena, try self.print("{s} %{s}", .{ abi.value.?, loaded }));
                    }
                },
                .scalar => |llvm| if (std.mem.eql(u8, llvm, "ptr")) {
                    const integer = try self.render(lines, argument, "i64");
                    try rendered.append(self.arena, try self.print("ptr {s}", .{try self.address(lines, integer)}));
                } else {
                    try rendered.append(self.arena, try self.print("{s} {s}", .{ llvm, try self.render(lines, argument, llvm) }));
                },
            }
        }
        return rendered;
    }

    /// The signature a call site's own operand spellings imply.
    fn callSiteSignature(self: *Emitter, call: Call) Error!Declaration {
        const letters = try self.arena.alloc([]const u8, call.args.len);
        for (call.args, letters) |argument, *letter| letter.* = switch (argument) {
            .temp => |ref| ref.qbe_type orelse self.typeOf(ref.name).letter(),
            .constant => |literal| if (literal.qbe_type != null and il.isBaseType(literal.qbe_type.?)) literal.qbe_type.? else "l",
            .call => |nested| nested.qbe_type orelse "l",
            .global => "l",
        };
        const parameters = try self.parameterAbis(letters, call.annotated);
        const result: Shape = if (try self.abiOf(call.annotated, false)) |abi| .{ .aggregate = abi } else .{ .scalar = call.wanted orelse "void" };
        return .{ .parameters = parameters, .result = result, .origin = .external };
    }

    /// The signature of a symbol this unit has no entry for, from the call
    /// site; a runtime helper with no checked C signature is refused.
    fn inferExternal(self: *Emitter, name: []const u8, call: Call) Error!Declaration {
        const signature = try self.callSiteSignature(call);
        const helper = runtime.isHelper(name);
        if (helper and self.options.runtime.signature(name) == null) return self.fail(try self.print("{s}: runtime helper ${s} has no checked C signature", .{ self.unit.function.name, name }));
        if (self.module.declarations.get(name)) |previous| {
            if (!sameSignature(previous, signature)) return self.fail(try self.print("{s}: external ${s} is called with conflicting signatures", .{ self.unit.function.name, name }));
        }
        try self.module.declarations.put(self.arena, name, signature);
        return signature;
    }
};

fn sameSignature(left: Declaration, right: Declaration) bool {
    if (left.origin == .undefined or right.origin == .undefined) return false;
    if (left.parameters.len != right.parameters.len or !left.result.eql(right.result)) return false;
    for (left.parameters, right.parameters) |a, b| if (!a.eql(b)) return false;
    return true;
}

/// Whether a branch's targets name a floor failure and a stack admission.
fn guardShaped(targets: [2][]const u8) bool {
    var floor = false;
    var admit = false;
    for (targets) |label| {
        if (containsIgnoreCase(label, "floorfail")) floor = true;
        if (containsIgnoreCase(label, "stackadmit")) admit = true;
    }
    return floor and admit;
}

/// Whether `haystack` contains `needle` (lowercase), ignoring ASCII case.
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    for (0..haystack.len - needle.len + 1) |start| {
        if (std.ascii.eqlIgnoreCase(haystack[start .. start + needle.len], needle)) return true;
    }
    return false;
}

/// The straight-line instructions before a stack-guard branch.
const Prologue = struct {
    instructions: []const *Instruction,

    /// The last definition of `name` before position `before`.
    fn reaching(self: Prologue, name: []const u8, before: usize) ?struct { index: usize, instruction: *const Instruction } {
        var index = @min(before, self.instructions.len);
        while (index > 0) {
            index -= 1;
            const dest = self.instructions[index].dest orelse continue;
            if (std.mem.eql(u8, dest, name)) return .{ .index = index, .instruction = self.instructions[index] };
        }
        return null;
    }

    /// Follow the branch condition through copies to the `cultl` that
    /// compares an allocation against the floor loaded from `ctx + 64`.
    fn guard(self: Prologue, condition_start: Operand, branch_index: usize) ?*const Instruction {
        var condition = condition_start;
        var use_index = branch_index;
        var seen: [64][]const u8 = undefined;
        var count: usize = 0;
        while (condition.refName()) |name| {
            for (seen[0..count]) |known| if (std.mem.eql(u8, known, name)) return null;
            if (count == seen.len) return null;
            seen[count] = name;
            count += 1;
            const producer = self.reaching(name, use_index) orelse return null;
            if (producer.instruction.opcode == .copy) {
                condition = producer.instruction.args[0];
                use_index = producer.index;
                continue;
            }
            if (producer.instruction.opcode != .cultl) return null;
            return if (self.floorCompare(producer.instruction, producer.index)) producer.instruction else null;
        }
        return null;
    }

    fn floorCompare(self: Prologue, compare: *const Instruction, index: usize) bool {
        const left = if (compare.args[0].refName()) |name| self.reaching(name, index) else null;
        const right = if (compare.args[1].refName()) |name| self.reaching(name, index) else null;
        const right_load = right != null and right.?.instruction.opcode == .loadl;
        if (!right_load) return false;
        const floor = if (right.?.instruction.args[0].refName()) |name| self.reaching(name, right.?.index) else null;
        const offset = floor != null and floor.?.instruction.opcode == .add and hasSixtyFour(floor.?.instruction.args);
        return left != null and left.?.instruction.opcode.isAlloc() and offset;
    }
};

fn hasSixtyFour(args: []const Operand) bool {
    for (args) |argument| if (argument == .constant and std.mem.eql(u8, argument.constant.text, "64")) return true;
    return false;
}

/// The bit width of an LLVM integer type, or null for any other type.
pub fn bitWidth(llvm: []const u8) ?u16 {
    if (llvm.len < 2 or llvm[0] != 'i') return null;
    return std.fmt.parseUnsigned(u16, llvm[1..], 10) catch null;
}

/// Whether an LLVM type is `float` or `double`.
pub fn isFloat(llvm: []const u8) bool {
    return std.mem.eql(u8, llvm, "float") or std.mem.eql(u8, llvm, "double");
}

fn union64(arena: Allocator, left: []const u64, right: []const u64) Error![]const u64 {
    var out: std.ArrayList(u64) = .empty;
    for (left) |value| if (std.mem.indexOfScalar(u64, out.items, value) == null) try out.append(arena, value);
    for (right) |value| if (std.mem.indexOfScalar(u64, out.items, value) == null) try out.append(arena, value);
    return out.items;
}

fn intersection64(arena: Allocator, left: []const u64, right: []const u64) Error![]const u64 {
    var out: std.ArrayList(u64) = .empty;
    for (left) |value| {
        if (std.mem.indexOfScalar(u64, right, value) != null and std.mem.indexOfScalar(u64, out.items, value) == null) try out.append(arena, value);
    }
    return out.items;
}

/// Python's `repr` of a finite float: the shortest round-tripping digits,
/// in positional form when the decimal point falls in `(-4, 16]` and in
/// exponent form otherwise.
pub fn pythonRepr(arena: Allocator, value: f64) Error![]const u8 {
    const negative = std.math.signbit(value);
    const sign: []const u8 = if (negative) "-" else "";
    if (value == 0) return std.fmt.allocPrint(arena, "{s}0.0", .{sign});
    const decimal = std.fmt.float.binaryToDecimal(u64, @bitCast(@abs(value)), std.math.floatMantissaBits(f64), std.math.floatExponentBits(f64), false, &std.fmt.float.Backend64_TablesFull);
    const digits = try std.fmt.allocPrint(arena, "{d}", .{decimal.mantissa});
    const point: i64 = @as(i64, @intCast(digits.len)) + decimal.exponent;
    if (point <= -4 or point > 16) {
        const exponent = point - 1;
        const exponent_sign: u8 = if (exponent < 0) '-' else '+';
        const magnitude: u64 = @intCast(@abs(exponent));
        const fraction = if (digits.len > 1) try std.fmt.allocPrint(arena, ".{s}", .{digits[1..]}) else "";
        return std.fmt.allocPrint(arena, "{s}{c}{s}e{c}{d:0>2}", .{ sign, digits[0], fraction, exponent_sign, magnitude });
    }
    if (point <= 0) {
        const zeros = try arena.alloc(u8, @intCast(-point));
        @memset(zeros, '0');
        return std.fmt.allocPrint(arena, "{s}0.{s}{s}", .{ sign, zeros, digits });
    }
    const whole: usize = @intCast(point);
    if (whole >= digits.len) {
        const zeros = try arena.alloc(u8, whole - digits.len);
        @memset(zeros, '0');
        return std.fmt.allocPrint(arena, "{s}{s}{s}.0", .{ sign, digits, zeros });
    }
    return std.fmt.allocPrint(arena, "{s}{s}.{s}", .{ sign, digits[0..whole], digits[whole..] });
}
