//! The op log of lowering (docs/design/incremental-engine.md §17.1, G0b answer 2, part 2 step G3a1).
//!
//! Lowering numbers three program-wide tables in first-use order: functions, compound types and strings. A stored
//! artifact that holds those numbers is wrong after an unrelated edit moves them. The op log is the name-based form of
//! what lowering does to the tables: for each stretch of work (a *segment*: the roots, the lowering of one function,
//! the normalization of one function) the compound types it obtained, the functions it appended and the strings it
//! appended, every type spelled with ids local to the segment and every nominal record by its `RecordName`.
//!
//! Replaying the segments in order against an empty `ir.Module` reproduces the tables of the module lowering built,
//! entry for entry (`verify`). That is this step's contract: the log is complete and its names are enough. The log is
//! write-only here: no key, artifact or pass reads it, so the output of a build does not change. Later steps assemble
//! compounds and strings from it (G3a2), then functions (G3b), and store it instead of the positional delta.
//!
//! A compound type is recorded when lowering *obtains* it, found or appended (`ir.Module.tap`), because an artifact
//! that only found a type another function made must still be able to create it in a program where that function is
//! absent. A structural compound is recorded with its children; a nominal record by its name, with its content in the
//! segment that reserved it (any other segment finds it, and a program that lacks it maps its declaration).
const std = @import("std");
const ir = @import("ir.zig");
const names = @import("stable_names.zig");
const record_names = @import("record_names.zig");

/// Whether every build records its op log and checks it by replay: a debug compiler does, like the other validators
/// (`verify_ir.enabled`). `--verify-names` asks any compiler for it.
pub const enabled = @import("builtin").mode == .debug;

/// What recording and replaying can fail with.
pub const Error = std.mem.Allocator.Error;

/// One effect on the compound table, in the order lowering had it. A type's local id is the number of `nominal` and
/// `structural` operations before it, counted from `ir.Type.first_compound`.
pub const TypeOp = union(enum) {
    /// Find the nominal record or union of this name, or reserve an empty one.
    nominal: names.RecordName,
    /// Give a nominal type its content; applies only when the replay reserved it (a found type has it already).
    fill: Fill,
    /// Find or intern a structural compound whose children are local ids.
    structural: ir.Compound,

    /// The content of a nominal type.
    pub const Fill = struct { id: ir.Type, compound: ir.Compound };
};

/// One function appended to the function table. `name` is the exact name lowering gave it (until G3a3 some families
/// spell a position in it); `key` is its stable identity.
pub const FunctionOp = struct { key: names.FunctionName, name: []const u8, signature: ir.Signature };

/// The stretch of lowering a segment covers.
pub const Phase = enum {
    /// The declaration of the roots, before any body is built.
    roots,
    /// The lowering of one function's body.
    lower,
    /// The normalization of one function after every body is built (`lowering_finish`).
    finish,
};

/// Everything one stretch of lowering did to the three tables.
pub const Segment = struct {
    phase: Phase,
    /// The checked name of the function the segment belongs to; empty for the roots.
    owner: []const u8,
    types: []const TypeOp,
    functions: []const FunctionOp,
    strings: []const []const u8,
};

/// Where a replay differs from the module lowering built.
pub const Mismatch = struct {
    /// The table that differs: `compounds`, `functions` or `strings`.
    table: []const u8,
    /// The first differing index, or the shorter length when one table is a prefix of the other.
    index: usize,
};

/// What a build's replay check did, for `--verify-names` to report.
pub const Summary = struct {
    segments: u32 = 0,
    types: u32 = 0,
    functions: u32 = 0,
    strings: u32 = 0,
    /// Whether the replay ran and matched; false when the log did not describe every effect (a restored artifact).
    checked: bool = false,
    /// Records and checked functions whose name is not unique (the stable name then needs an ordinal).
    ambiguous_records: u32 = 0,
    ambiguous_functions: u32 = 0,
};

/// The deepest nesting of types the recorder follows. Every cycle of types passes through a nominal record or union,
/// which the recorder stops at, so nesting this deep means the log lost track of a type.
const max_depth = 256;

/// An open segment: the operations so far, the memo of types already localized, and the table lengths at its start.
const Open = struct {
    phase: Phase,
    owner: []const u8,
    types: std.ArrayList(TypeOp) = .empty,
    memo: std.AutoHashMapUnmanaged(ir.Type, ir.Type) = .empty,
    functions: usize,
    strings: usize,
    /// The operation that defined each local compound id, by index into `types`.
    defs: std.ArrayList(u32) = .empty,
    /// The functions lowering obtained (declared, found or made), in the order it first did.
    touched: std.ArrayList(u32) = .empty,
    touched_seen: std.AutoHashMapUnmanaged(u32, void) = .empty,

    fn nextId(self: *const Open) ir.Type {
        return @fromBackingInt(@intCast(ir.Type.first_compound + self.defs.items.len));
    }
};

/// The compound types lowering has obtained, for finding them without a scan of the module's table.
const CompoundContext = struct {
    /// A hash of a compound's structure that agrees with `ir.sameCompound`.
    pub fn hash(_: CompoundContext, compound: ir.Compound) u64 {
        var h = std.hash.Wyhash.init(2);
        h.update(&.{@backingInt(std.meta.activeTag(compound))});
        switch (compound) {
            .list, .list_view, .box, .borrowed => |inner| h.update(std.mem.asBytes(&inner)),
            .record, .@"union" => |parts| h.update(std.mem.sliceAsBytes(parts)),
            .dict => |dict| h.update(std.mem.asBytes(&dict)),
            .array => |array| {
                h.update(std.mem.asBytes(&array.elem));
                h.update(std.mem.asBytes(&array.n));
            },
            .@"fn" => |signature| {
                h.update(std.mem.sliceAsBytes(signature.params));
                h.update(std.mem.asBytes(&signature.ret));
                h.update(&.{@backingInt(signature.linkage)});
            },
        }
        return h.final();
    }

    /// Whether two compounds are the same type, as `Module.intern` judges it.
    pub fn eql(_: CompoundContext, a: ir.Compound, b: ir.Compound) bool {
        return ir.sameCompound(a, b);
    }
};

/// The functions of the module being built, by name. Several runtime helpers share a name and differ in signature.
const FunctionIndex = struct {
    /// How many functions of the table are in `by_name`.
    scanned: usize = 0,
    by_name: std.StringHashMapUnmanaged(std.ArrayList(u32)) = .empty,
    /// The render shape declarations among them, by render id.
    shapes: std.StringHashMapUnmanaged(u32) = .empty,
};

/// What lowering has made, by name and by structure: nominal records, and every other compound type.
const Registry = struct {
    /// The functions of the module, by name, as far as lookups have looked.
    functions: FunctionIndex = .{},
    /// The name of every nominal compound lowering reserved, by its type.
    nominals: std.AutoHashMapUnmanaged(ir.Type, names.RecordName) = .empty,
    /// The reverse of `nominals`.
    by_name: std.HashMapUnmanaged(names.RecordName, ir.Type, names.RecordNameContext, std.hash_map.default_max_load_percentage) = .empty,
    /// Every structural compound type, by its structure. A nominal type is never in it.
    structural: std.HashMapUnmanaged(ir.Compound, ir.Type, CompoundContext, std.hash_map.default_max_load_percentage) = .empty,
    /// The function table indices `ModuleBuilder.declare` created: the checked source functions.
    sources: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// The names of the program's records, which outlive any artifact a replay decodes.
    records: ?*const record_names.RecordIndex = null,
};

/// The nominal type lowering reserved, or replay reserved, for a record.
pub const Created = struct { name: names.RecordName, ty: ir.Type };

/// What replaying an artifact's type operations into the live module produced.
pub const Replayed = struct {
    /// The type in the module of each local compound id, by local compound index.
    map: []const ir.Type,
    /// The nominal types the replay reserved, in order; the caller binds each to its checked type.
    created: []const Created,
};

/// Records the op log of one lowering. It is the `ir.Module.tap` of the module being built, and the builder tells it
/// about the rest: where a segment starts and ends, which records are reserved and filled, which functions are checked
/// source declarations. It also finds what lowering made by name and by structure, which is how an artifact's type
/// operations are replayed into the live module.
pub const Recorder = struct {
    /// Holds what outlives a segment: the registry and, when the log is kept, the segments.
    arena: std.mem.Allocator,
    /// Holds a segment's operations when the log is not kept; reset when the next segment begins.
    scratch: std.heap.ArenaAllocator,
    tap: ir.Module.Tap = .{ .on_intern = onIntern },
    segments: std.ArrayList(Segment) = .empty,
    open: ?Open = null,
    registry: Registry = .{},
    state: State = .{},

    /// What the recorder knows about its own completeness.
    pub const State = struct {
        /// False once an effect happened that the log does not describe (a deferred body, or memory ran out): the log
        /// is then not checked, and no more is recorded.
        complete: bool = true,
        /// Whether finished segments are kept, for `verify` and `--verify-names`. An artifact needs only the open one.
        keep: bool = true,
        /// Whether segments are opened at all: a build with no lowering cache and no check only needs the registry.
        segments: bool = true,
        /// Checked functions whose name another checked function already carries.
        ambiguous_functions: u32 = 0,
        /// How deep the type being localized nests.
        depth: u32 = 0,
        /// The names of the checked functions declared so far.
        function_names: std.StringHashMapUnmanaged(void) = .empty,
    };

    /// A recorder whose registry is allocated in `arena`, which must outlive it, and whose segment scratch memory comes
    /// from `backing`. With `keep`, the finished segments are kept in `arena` too.
    pub fn init(arena: std.mem.Allocator, backing: std.mem.Allocator, keep: bool) Recorder {
        return .{ .arena = arena, .scratch = std.heap.ArenaAllocator.init(backing), .state = .{ .keep = keep } };
    }

    /// Release the segment scratch memory.
    pub fn deinit(self: *Recorder) void {
        self.scratch.deinit();
    }

    /// Start observing `module`, naming its records by `records`. The module must not be copied out while attached:
    /// `detach` first.
    pub fn attach(self: *Recorder, module: *ir.Module, records: ?*const record_names.RecordIndex) void {
        module.lowering.tap = &self.tap;
        self.registry.records = records;
    }

    /// Stop observing `module`.
    pub fn detach(_: *Recorder, module: *ir.Module) void {
        module.lowering.tap = null;
    }

    /// Say the log no longer describes every effect.
    pub fn abandon(self: *Recorder) void {
        self.state.complete = false;
        self.open = null;
    }

    /// Whether the function at `index` was declared by `ModuleBuilder.declare`: a checked source function.
    pub fn isSource(self: *const Recorder, index: u32) bool {
        return self.registry.sources.contains(index);
    }

    /// The names of the nominal types lowering reserved, which types are keyed by.
    pub fn nominalNames(self: *const Recorder) *const std.AutoHashMapUnmanaged(ir.Type, names.RecordName) {
        return &self.registry.nominals;
    }

    /// The digest of the stable name of each nominal compound among the first `count`, by compound index, in `a`.
    pub fn nominalDigests(self: *const Recorder, a: std.mem.Allocator, count: usize) Error![]const ?[32]u8 {
        const out = try a.alloc(?[32]u8, count);
        @memset(out, null);
        var each = self.registry.nominals.iterator();
        while (each.next()) |entry| {
            const at = @backingInt(entry.key_ptr.*) - ir.Type.first_compound;
            if (at < count) out[at] = entry.value_ptr.digest();
        }
        return out;
    }

    /// The indices, in table order, of the functions among the first `limit` of `module` named `name`. The index reads the
    /// table as far as `limit` the first time it is asked, and again after the table has grown.
    pub fn functionsNamed(self: *Recorder, module: *const ir.Module, name: []const u8, limit: usize) Error![]const u32 {
        const index = &self.registry.functions;
        while (index.scanned < limit) : (index.scanned += 1) {
            const each = module.functions.items[index.scanned].name;
            const found = try index.by_name.getOrPut(self.arena, each);
            if (!found.found_existing) {
                found.key_ptr.* = try self.arena.dupe(u8, each);
                found.value_ptr.* = .empty;
            }
            try found.value_ptr.append(self.arena, @intCast(index.scanned));
            if (shapeId(each)) |id| _ = try index.shapes.getOrPutValue(self.arena, try self.arena.dupe(u8, id), @intCast(index.scanned));
        }
        const list = (index.by_name.get(name) orelse return &.{}).items;
        var count = list.len;
        while (count != 0 and list[count - 1] >= limit) count -= 1;
        return list[0..count];
    }

    /// The render shape declaration for render id `id` among the first `limit` functions of `module`, if there is one.
    pub fn shapeDeclared(self: *Recorder, module: *const ir.Module, id: []const u8, limit: usize) Error!?u32 {
        _ = try self.functionsNamed(module, "", limit);
        const found = self.registry.functions.shapes.get(id) orelse return null;
        return if (found < limit) found else null;
    }

    /// `signature` on the types local to the open segment, adding the operations that create the types it uses.
    pub fn localizeSignature(self: *Recorder, a: std.mem.Allocator, module: *const ir.Module, signature: ir.Signature) Error!ir.Signature {
        var out = try signature.clone(a);
        out.params = try a.alloc(ir.Type, signature.params.len);
        const local = try self.localSignature(module, signature);
        @memcpy(@constCast(out.params), local.params);
        out.ret = local.ret;
        return out;
    }

    /// Whether a segment is open and the log is complete, so that types can be localized.
    pub fn recording(self: *const Recorder) bool {
        return self.open != null and self.state.complete;
    }

    /// The operations of the open segment so far: the type operations an artifact stores.
    pub fn operations(self: *const Recorder) []const TypeOp {
        const open = self.open orelse return &.{};
        return open.types.items;
    }

    /// The module type behind each local compound id of the open segment, in the order of the ids: where an artifact captured now finds
    /// its types in this module.
    pub fn typePlaces(self: *const Recorder, a: std.mem.Allocator) Error![]const ir.Type {
        const open = self.open orelse return &.{};
        const out = try a.alloc(ir.Type, open.defs.items.len);
        @memset(out, @fromBackingInt(0));
        var found = open.memo.iterator();
        while (found.next()) |entry| {
            const at = @backingInt(entry.value_ptr.*) - ir.Type.first_compound;
            if (at < out.len) out[at] = entry.key_ptr.*;
        }
        return out;
    }

    fn memory(self: *Recorder) std.mem.Allocator {
        return if (self.state.keep) self.arena else self.scratch.allocator();
    }

    /// Open a segment at the current table lengths. A segment still open is closed first.
    pub fn begin(self: *Recorder, module: *const ir.Module, phase: Phase, owner: []const u8) Error!void {
        if (self.open != null) try self.end(module);
        if (!self.state.complete or !self.state.segments) return;
        if (!self.state.keep) _ = self.scratch.reset(.retain_capacity);
        self.open = .{ .phase = phase, .owner = owner, .functions = module.functions.items.len, .strings = module.strings.items.len };
    }

    /// Close the open segment: the functions and strings appended since it began join the types it recorded.
    pub fn end(self: *Recorder, module: *const ir.Module) Error!void {
        const open = &(self.open orelse return);
        if (!self.state.keep) {
            self.open = null;
            return;
        }
        var functions: std.ArrayList(FunctionOp) = .empty;
        var counts: [std.enums.values(names.GeneratedRole).len]u32 = @splat(0);
        for (module.functions.items[open.functions..], open.functions..) |function, index| {
            const signature = try self.localSignature(module, function.signature);
            const key: names.FunctionName = key: {
                if (function.signature.linkage != .internal) break :key .{ .runtime = .{ .symbol = function.name, .signature = signatureHash(open, signature) } };
                if (self.registry.sources.contains(@intCast(index))) break :key .{ .source = function.name };
                const role = names.generatedRole(function.name) orelse break :key .{ .source = function.name };
                counts[@backingInt(role)] += 1;
                break :key .{ .generated = .{ .creator = open.owner, .role = role, .ordinal = counts[@backingInt(role)] - 1 } };
            };
            try functions.append(self.arena, .{ .key = key, .name = function.name, .signature = signature });
        }
        // The strings are copied now, not when they were appended: a render shape fills its string in place.
        const strings = try self.arena.dupe([]const u8, module.strings.items[open.strings..]);
        try self.segments.append(self.arena, .{ .phase = open.phase, .owner = open.owner, .types = open.types.items, .functions = functions.items, .strings = strings });
        self.open = null;
    }

    /// Lowering reserved the empty nominal compound `ty` for the record `record`.
    pub fn reserved(self: *Recorder, ty: ir.Type, record: names.RecordName) Error!void {
        try self.registry.nominals.put(self.arena, ty, record);
        try self.registry.by_name.put(self.arena, record, ty);
        const open = &(self.open orelse return);
        if (!self.state.complete) return;
        const id = open.nextId();
        try open.defs.append(self.memory(), @intCast(open.types.items.len));
        try open.types.append(self.memory(), .{ .nominal = record });
        try open.memo.put(self.memory(), ty, id);
    }

    /// Lowering gave the reserved nominal compound `ty` its content.
    pub fn filled(self: *Recorder, module: *const ir.Module, ty: ir.Type) Error!void {
        const open = &(self.open orelse return);
        const id = open.memo.get(ty) orelse return;
        const content = try self.localCompound(module, module.compound(ty));
        try open.types.append(self.memory(), .{ .fill = .{ .id = id, .compound = content } });
    }

    /// Lowering obtained `ty` without going through `intern` (a nominal type it had already mapped).
    pub fn touched(self: *Recorder, module: *const ir.Module, ty: ir.Type) Error!void {
        if (!self.recording()) return;
        _ = try self.localType(module, ty);
    }

    /// Lowering obtained the function at `index`: declared, found or made. The segment's function requests are these, in the
    /// order they first happened, which is the order a replay has to repeat them in.
    pub fn touchedFunction(self: *Recorder, index: u32) Error!void {
        const open = &(self.open orelse return);
        if (!self.state.complete) return;
        if ((try open.touched_seen.getOrPut(self.memory(), index)).found_existing) return;
        try open.touched.append(self.memory(), index);
    }

    /// The functions the open segment has obtained, in order.
    pub fn functionTouches(self: *const Recorder) []const u32 {
        const open = self.open orelse return &.{};
        return open.touched.items;
    }

    /// `ModuleBuilder.declare` appended the checked source function `name` at `index`.
    pub fn declared(self: *Recorder, index: u32, name: []const u8) Error!void {
        try self.registry.sources.put(self.arena, index, {});
        if ((try self.state.function_names.getOrPut(self.arena, name)).found_existing) self.state.ambiguous_functions += 1;
    }

    /// How much the log holds, and whether it was checked. `ambiguous_records` comes from the program's `RecordIndex`.
    pub fn summary(self: *const Recorder, checked: bool, ambiguous_records: u32) Summary {
        var out: Summary = .{ .segments = @intCast(self.segments.items.len), .checked = checked, .ambiguous_records = ambiguous_records, .ambiguous_functions = self.state.ambiguous_functions };
        for (self.segments.items) |segment| {
            out.types += @intCast(segment.types.len);
            out.functions += @intCast(segment.functions.len);
            out.strings += @intCast(segment.strings.len);
        }
        return out;
    }

    /// Replay the log into an empty module and say where it differs from `module`; null when it does not.
    pub fn verify(self: *const Recorder, scratch: std.mem.Allocator, module: *const ir.Module) Error!?Mismatch {
        var fresh: ir.Module = .{};
        try replay(scratch, self.segments.items, &fresh);
        return compare(&fresh, module);
    }

    /// A copy of `function` whose types are ids local to the open segment (the instructions are copied; blocks, extra
    /// operands and loops are shared). The operations that create a type the segment had not yet obtained join it.
    pub fn localizeFunction(self: *Recorder, a: std.mem.Allocator, module: *const ir.Module, function: ir.Function) Error!ir.Function {
        var out = function;
        out.signature = try self.localSignature(module, function.signature);
        const insts = try a.dupe(ir.Inst, function.insts.items);
        for (insts) |*inst| inst.ty = try self.localType(module, inst.ty);
        out.insts = .fromOwnedSlice(insts);
        return out;
    }

    /// Whether `ops` can be replayed into `module` now: every local id they use is defined, and every nominal type is
    /// found in the module or filled by the operations themselves. A nominal type that is neither would be an empty
    /// record, so the artifact is refused instead.
    pub fn replayable(self: *Recorder, module: *const ir.Module, scratch: std.mem.Allocator, ops: []const TypeOp) Error!bool {
        var count: u32 = 0;
        var absent: std.ArrayList(bool) = .empty;
        for (ops) |op| switch (op) {
            .nominal => |record| {
                try absent.append(scratch, self.nominalType(module, record) == null);
                count += 1;
            },
            .structural => |compound| {
                if (!definedAll(compound, count)) return false;
                try absent.append(scratch, false);
                count += 1;
            },
            .fill => |content| {
                const at = @backingInt(content.id) -% ir.Type.first_compound;
                if (!content.id.isCompound() or at >= count) return false;
                if (!definedAll(content.compound, count)) return false;
                absent.items[at] = false;
            },
        };
        for (absent.items) |missing| if (missing) return false;
        return true;
    }

    /// The nominal type of `record` in `module`, when lowering made it and it is still the module's.
    pub fn nominalType(self: *const Recorder, module: *const ir.Module, record: names.RecordName) ?ir.Type {
        const found = self.registry.by_name.get(record) orelse return null;
        if (!module.valid(found)) return null;
        const registered = self.registry.nominals.get(found) orelse return null;
        return if (registered.eql(record)) found else null;
    }

    /// Replay `ops`, which `replayable` accepted, into `module`: find what exists, create what does not, and record
    /// each type in the open segment as lowering would have. `a` is the module's allocator.
    pub fn replayInto(self: *Recorder, module: *ir.Module, a: std.mem.Allocator, ops: []const TypeOp) Error!Replayed {
        // A restored function is never stored again, so unless the log is kept to be checked its segment is not recorded;
        // the registry of what the module holds is still kept.
        const quiet = !self.state.keep;
        const saved = self.open;
        if (quiet) self.open = null;
        defer if (quiet) {
            self.open = saved;
        };
        var local: std.ArrayList(ir.Type) = .empty;
        var made: std.ArrayList(bool) = .empty;
        var created: std.ArrayList(Created) = .empty;
        for (ops) |op| switch (op) {
            .nominal => |record| {
                if (self.nominalType(module, record)) |found| {
                    try self.touched(module, found);
                    try local.append(a, found);
                    try made.append(a, false);
                } else {
                    const reserved_type: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + module.compounds.items.len));
                    try module.compounds.append(a, .{ .record = &.{} });
                    // The decoded name dies with the artifact; the index's copy lives as long as the program.
                    const own = if (self.registry.records) |index| index.canonical(record) orelse record else record;
                    try self.reserved(reserved_type, own);
                    try local.append(a, reserved_type);
                    try made.append(a, true);
                    try created.append(a, .{ .name = own, .ty = reserved_type });
                }
            },
            .fill => |content| {
                const at = @backingInt(content.id) - ir.Type.first_compound;
                if (!made.items[at]) continue;
                module.compounds.items[@backingInt(local.items[at]) - ir.Type.first_compound] = try mapCompound(a, local.items, content.compound);
                try self.filled(module, local.items[at]);
            },
            .structural => |compound| {
                const wanted = try mapCompound(a, local.items, compound);
                const found = self.registry.structural.get(wanted);
                if (found) |known| try self.touched(module, known);
                try local.append(a, found orelse try module.intern(a, wanted));
                try made.append(a, false);
            },
        };
        return .{ .map = local.items, .created = created.items };
    }

    fn onIntern(tap: *ir.Module.Tap, module: *const ir.Module, ty: ir.Type) void {
        const self: *Recorder = @fieldParentPtr("tap", tap);
        self.registerStructural(module, ty) catch {
            self.state.complete = false;
        };
        if (!self.recording()) return;
        _ = self.localType(module, ty) catch {
            self.state.complete = false;
        };
    }

    /// Remember a compound type `intern` returned, unless it is a nominal one.
    fn registerStructural(self: *Recorder, module: *const ir.Module, ty: ir.Type) Error!void {
        if (self.registry.nominals.contains(ty)) return;
        const found = try self.registry.structural.getOrPut(self.arena, module.compound(ty));
        if (!found.found_existing) found.value_ptr.* = ty;
    }

    /// The segment-local id of global type `ty`, appending the operations that create it on first use. Children come
    /// before parents; a nominal type is appended before its content, so a recursive type finds itself.
    fn localType(self: *Recorder, module: *const ir.Module, ty: ir.Type) Error!ir.Type {
        if (!ty.isCompound()) return ty;
        const open = &(self.open orelse return ty);
        if (open.memo.get(ty)) |known| return known;
        if (!module.valid(ty)) {
            self.state.complete = false;
            return ty;
        }
        // A cycle that passes through no reserved nominal type means a type reached the module without the log
        // hearing of it: the log is then incomplete, and recording stops.
        self.state.depth += 1;
        defer self.state.depth -= 1;
        if (self.state.depth > max_depth) {
            self.state.complete = false;
            return ty;
        }
        if (self.registry.nominals.get(ty)) |record| {
            // A nominal type this segment did not reserve is named, not described: its content is a function of the
            // record's declaration, and the segment that reserved it holds it.
            const id = open.nextId();
            try open.defs.append(self.memory(), @intCast(open.types.items.len));
            try open.types.append(self.memory(), .{ .nominal = record });
            try open.memo.put(self.memory(), ty, id);
            return id;
        }
        const content = try self.localCompound(module, module.compound(ty));
        const id = open.nextId();
        try open.defs.append(self.memory(), @intCast(open.types.items.len));
        try open.types.append(self.memory(), .{ .structural = content });
        try open.memo.put(self.memory(), ty, id);
        return id;
    }

    fn localCompound(self: *Recorder, module: *const ir.Module, compound: ir.Compound) Error!ir.Compound {
        return switch (compound) {
            .list => |element| .{ .list = try self.localType(module, element) },
            .list_view => |element| .{ .list_view = try self.localType(module, element) },
            .box => |inner| .{ .box = try self.localType(module, inner) },
            .borrowed => |inner| .{ .borrowed = try self.localType(module, inner) },
            .record => |fields| .{ .record = try self.localTypes(module, fields) },
            .@"union" => |cases| .{ .@"union" = try self.localTypes(module, cases) },
            .dict => |dict| .{ .dict = .{ .key = try self.localType(module, dict.key), .value = try self.localType(module, dict.value) } },
            .array => |array| .{ .array = .{ .elem = try self.localType(module, array.elem), .n = array.n, .vector = array.vector } },
            .@"fn" => |signature| .{ .@"fn" = try self.localSignature(module, signature) },
        };
    }

    fn localTypes(self: *Recorder, module: *const ir.Module, types: []const ir.Type) Error![]const ir.Type {
        const out = try self.memory().alloc(ir.Type, types.len);
        for (types, out) |ty, *slot| slot.* = try self.localType(module, ty);
        return out;
    }

    fn localSignature(self: *Recorder, module: *const ir.Module, signature: ir.Signature) Error!ir.Signature {
        var out = try signature.clone(self.memory());
        out.params = try self.localTypes(module, signature.params);
        out.ret = try self.localType(module, signature.ret);
        return out;
    }
};

/// Whether every type `compound` holds is a leaf type or a local id below `count`.
fn definedAll(compound: ir.Compound, count: u32) bool {
    const limit = ir.Type.first_compound + count;
    switch (compound) {
        .list, .list_view, .box, .borrowed => |inner| return defined(inner, limit),
        .record, .@"union" => |parts| {
            for (parts) |part| if (!defined(part, limit)) return false;
            return true;
        },
        .dict => |dict| return defined(dict.key, limit) and defined(dict.value, limit),
        .array => |array| return defined(array.elem, limit),
        .@"fn" => |signature| {
            for (signature.params) |param| if (!defined(param, limit)) return false;
            return defined(signature.ret, limit);
        },
    }
}

fn defined(ty: ir.Type, limit: u32) bool {
    return !ty.isCompound() or @backingInt(ty) < limit;
}

/// The render id of a shape declaration `myl_core_render_shape_<string index>_<id>`: what follows the index, which is a
/// position in the string table; null for any other name.
pub fn shapeId(name: []const u8) ?[]const u8 {
    const prefix = "myl_core_render_shape_";
    if (!std.mem.startsWith(u8, name, prefix)) return null;
    const tail = name[prefix.len..];
    const split = std.mem.indexOfScalar(u8, tail, '_') orelse return null;
    return tail[split + 1 ..];
}

/// A hash of a signature's structure that does not depend on any position: leaves by tag, nominal records by name,
/// structural compounds by kind and children. It tells apart runtime helpers that share a symbol.
fn signatureHash(open: *const Open, signature: ir.Signature) u64 {
    var h = std.hash.Wyhash.init(0);
    for (signature.params) |param| h.update(std.mem.asBytes(&typeHash(open, param, 0)));
    h.update(std.mem.asBytes(&typeHash(open, signature.ret, 0)));
    h.update(&.{@backingInt(signature.linkage)});
    h.update(std.mem.asBytes(&signature.passing.owned));
    h.update(std.mem.asBytes(&signature.passing.views));
    return h.final();
}

/// The structural hash of local type `ty`. Cycles pass through a nominal type, which hashes by name; the depth bound
/// only guards a malformed log.
fn typeHash(open: *const Open, ty: ir.Type, depth: u32) u64 {
    if (!ty.isCompound()) return @as(u64, @backingInt(ty)) + 1;
    const id = @backingInt(ty) - ir.Type.first_compound;
    if (depth > 64 or id >= open.defs.items.len) return 0;
    var h = std.hash.Wyhash.init(1);
    switch (open.types.items[open.defs.items[id]]) {
        .nominal => |record| h.update(std.mem.asBytes(&record.hash())),
        .fill => {},
        .structural => |compound| {
            h.update(&.{@backingInt(std.meta.activeTag(compound))});
            switch (compound) {
                .list, .list_view, .box, .borrowed => |inner| h.update(std.mem.asBytes(&typeHash(open, inner, depth + 1))),
                .record, .@"union" => |parts| for (parts) |part| h.update(std.mem.asBytes(&typeHash(open, part, depth + 1))),
                .dict => |dict| {
                    h.update(std.mem.asBytes(&typeHash(open, dict.key, depth + 1)));
                    h.update(std.mem.asBytes(&typeHash(open, dict.value, depth + 1)));
                },
                .array => |array| {
                    h.update(std.mem.asBytes(&typeHash(open, array.elem, depth + 1)));
                    h.update(std.mem.asBytes(&array.n));
                    h.update(&.{@intFromBool(array.vector)});
                },
                .@"fn" => |signature| h.update(std.mem.asBytes(&signatureHash(open, signature))),
            }
        },
    }
    return h.final();
}

/// Replay `segments` into `out`: for each segment its types in order (finding what exists, creating what does not),
/// then its functions and its strings appended. Local ids resolve to the ids of `out`, so the segments need not have
/// been recorded against the same table positions.
pub fn replay(scratch: std.mem.Allocator, segments: []const Segment, out: *ir.Module) Error!void {
    var nominals: std.HashMapUnmanaged(names.RecordName, ir.Type, names.RecordNameContext, std.hash_map.default_max_load_percentage) = .empty;
    for (segments) |segment| {
        var local: std.ArrayList(ir.Type) = .empty;
        var created: std.ArrayList(bool) = .empty;
        for (segment.types) |op| switch (op) {
            .nominal => |record| {
                const found = nominals.get(record);
                const id = found orelse reserve: {
                    const reserved: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + out.compounds.items.len));
                    try out.compounds.append(scratch, .{ .record = &.{} });
                    try nominals.put(scratch, record, reserved);
                    break :reserve reserved;
                };
                try local.append(scratch, id);
                try created.append(scratch, found == null);
            },
            .fill => |content| {
                const at = @backingInt(content.id) - ir.Type.first_compound;
                if (created.items[at]) out.compounds.items[@backingInt(local.items[at]) - ir.Type.first_compound] = try mapCompound(scratch, local.items, content.compound);
            },
            .structural => |compound| {
                try local.append(scratch, try out.intern(scratch, try mapCompound(scratch, local.items, compound)));
                try created.append(scratch, false);
            },
        };
        for (segment.functions) |function| {
            var signature = function.signature;
            signature.params = try mapTypes(scratch, local.items, function.signature.params);
            signature.ret = mapType(local.items, function.signature.ret);
            try out.functions.append(scratch, .{ .name = function.name, .signature = signature });
        }
        try out.strings.appendSlice(scratch, segment.strings);
    }
}

fn mapType(local: []const ir.Type, ty: ir.Type) ir.Type {
    return if (ty.isCompound()) local[@backingInt(ty) - ir.Type.first_compound] else ty;
}

fn mapTypes(a: std.mem.Allocator, local: []const ir.Type, types: []const ir.Type) Error![]const ir.Type {
    const out = try a.alloc(ir.Type, types.len);
    for (types, out) |ty, *slot| slot.* = mapType(local, ty);
    return out;
}

fn mapCompound(a: std.mem.Allocator, local: []const ir.Type, compound: ir.Compound) Error!ir.Compound {
    return switch (compound) {
        .list => |element| .{ .list = mapType(local, element) },
        .list_view => |element| .{ .list_view = mapType(local, element) },
        .box => |inner| .{ .box = mapType(local, inner) },
        .borrowed => |inner| .{ .borrowed = mapType(local, inner) },
        .record => |fields| .{ .record = try mapTypes(a, local, fields) },
        .@"union" => |cases| .{ .@"union" = try mapTypes(a, local, cases) },
        .dict => |dict| .{ .dict = .{ .key = mapType(local, dict.key), .value = mapType(local, dict.value) } },
        .array => |array| .{ .array = .{ .elem = mapType(local, array.elem), .n = array.n, .vector = array.vector } },
        .@"fn" => |signature| blk: {
            var out = signature;
            out.params = try mapTypes(a, local, signature.params);
            out.ret = mapType(local, signature.ret);
            break :blk .{ .@"fn" = out };
        },
    };
}

/// The first place the tables of `replayed` and `built` differ: every compound, every function's name and signature,
/// every string. Function bodies are not compared; the log does not describe them.
pub fn compare(replayed: *const ir.Module, built: *const ir.Module) ?Mismatch {
    const compounds = @min(replayed.compounds.items.len, built.compounds.items.len);
    for (replayed.compounds.items[0..compounds], built.compounds.items[0..compounds], 0..) |x, y, index| {
        if (!exactCompound(x, y)) return .{ .table = "compounds", .index = index };
    }
    if (replayed.compounds.items.len != built.compounds.items.len) return .{ .table = "compounds", .index = compounds };
    const functions = @min(replayed.functions.items.len, built.functions.items.len);
    for (replayed.functions.items[0..functions], built.functions.items[0..functions], 0..) |x, y, index| {
        if (!std.mem.eql(u8, x.name, y.name) or !x.signature.eql(y.signature)) return .{ .table = "functions", .index = index };
    }
    if (replayed.functions.items.len != built.functions.items.len) return .{ .table = "functions", .index = functions };
    const strings = @min(replayed.strings.items.len, built.strings.items.len);
    for (replayed.strings.items[0..strings], built.strings.items[0..strings], 0..) |x, y, index| {
        if (!std.mem.eql(u8, x, y)) return .{ .table = "strings", .index = index };
    }
    if (replayed.strings.items.len != built.strings.items.len) return .{ .table = "strings", .index = strings };
    return null;
}

/// Whether two compounds are equal in every field (`Module.intern`'s own test ignores the `vector` flag of an array).
// twin-drift-ok: the replay check is stricter than `ir.sameCompound` on purpose; it must see a difference intern hides.
fn exactCompound(x: ir.Compound, y: ir.Compound) bool {
    if (std.meta.activeTag(x) != std.meta.activeTag(y)) return false;
    return switch (x) {
        .list => |element| element == y.list,
        .list_view => |element| element == y.list_view,
        .box => |inner| inner == y.box,
        .borrowed => |inner| inner == y.borrowed,
        .record => |fields| std.mem.eql(ir.Type, fields, y.record),
        .@"union" => |cases| std.mem.eql(ir.Type, cases, y.@"union"),
        .dict => |dict| dict.key == y.dict.key and dict.value == y.dict.value,
        .array => |array| array.elem == y.array.elem and array.n == y.array.n and array.vector == y.array.vector,
        .@"fn" => |signature| signature.eql(y.@"fn"),
    };
}
