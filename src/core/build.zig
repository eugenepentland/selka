//! Build Core IR from the checked tree (docs/design/new-core-ir.md §3).
//!
//! SSA comes from the on-the-fly construction of Braun et al. (2013): each
//! checked local is a variable, `read`/`write` look definitions up per block,
//! phis appear on demand and are completed when a block is sealed, and a
//! trivial phi becomes a forwarding `copy`. The checked tree is structured, so
//! a block is sealed as soon as the walk has created all its predecessors.
//! Only functions reachable from `main` are built; a node the builder does not
//! support stops the build with `error.Unsupported` and a `Refusal`.
const std = @import("std");
const typed = @import("mylang").typed;
const Source = @import("mylang").source.Source;
const Field = @FieldType(@FieldType(typed.Node, "data"), "field");
const BufferOperation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");
const ir = @import("ir.zig");
const fuse = @import("fuse.zig");
const slices = @import("slices.zig");
const flags = @import("flags.zig");
const fuse_dict = @import("fuse_dict.zig");
const build_dict = @import("build_dict.zig");
const build_text = @import("build_text.zig");
const build_view = @import("build_borrowed_view.zig");
const build_list_methods = @import("build_list_methods.zig");
const fuse_text = @import("fuse_text.zig");
const build_cap = @import("build_cap.zig");
const build_bytes = @import("build_bytes.zig");
const build_fn = @import("build_fn.zig");
const build_values = @import("build_values.zig");
const single_owner_copy = @import("single_owner_copy.zig");
const build_capture = @import("build_capture.zig");
const lowering_cache = @import("lowering_cache.zig");
const aggregate_provider = @import("aggregate_provider.zig");

/// Refusal reasons several constructs share.
const refuse_payload = "match payload";
const refuse_field_index = "field index";
const refuse_non_record = "field of a non-record value";
const refuse_equality = "aggregate equality";
const view_value_marker: u32 = 1 << 31;

/// Why building stopped.
pub const Error = error{ OutOfMemory, Unsupported };
/// An omitted checked body whose lowering artifact is absent requires a fresh
/// frontend check; it must never be lowered as an empty function.
pub const CachedError = Error || error{CacheMiss};

/// The first unsupported construct: a short reason and its source offset.
pub const Refusal = struct { reason: []const u8 = "", span: u32 = 0 };

/// Build the module for `program`, reachable from its `main`. On
/// `error.Unsupported`, `refusal` names the construct.
pub fn buildModule(allocator: std.mem.Allocator, program: typed.Program, refusal: *Refusal) Error!ir.Module {
    return buildRootsSource(allocator, program, &.{program.main}, null, refusal);
}

/// Build the module reachable from several `roots` (the test runner's one executable
/// holds every test of a file). The roots take the first function indices in order
/// and `entry` is the first one; the caller replaces `entry` with its own dispatcher.
pub fn buildRoots(allocator: std.mem.Allocator, program: typed.Program, roots: []const typed.FunctionId, refusal: *Refusal) Error!ir.Module {
    return buildRootsSource(allocator, program, roots, null, refusal);
}

/// Build a checked program with its resolved compile-time embedded assets.
pub fn buildModuleSource(allocator: std.mem.Allocator, program: typed.Program, source: Source, refusal: *Refusal) Error!ir.Module {
    return buildRootsSource(allocator, program, &.{program.main}, source, refusal);
}

/// What a module is built from: the checked program, its loaded source, and whether
/// `debug(...)` lines are dropped, as a `build --release` executable drops them
/// (DEBUG-LINE-1); `run`, `build --run` and `test` keep them in every mode.
pub const Input = struct { program: typed.Program, source: ?Source = null, drop_debug: bool = false, single_owner: bool = false, zero_rc: bool = false };

/// Build an executable's module from `input`, rooted at the program's `main`.
pub fn buildExecutable(allocator: std.mem.Allocator, input: Input, refusal: *Refusal) Error!ir.Module {
    return buildRootsInput(allocator, &.{input.program.main}, input, refusal);
}

/// Reuse validated function lowering artifacts, preserving the uncached oracle.
pub fn buildExecutableCached(allocator: std.mem.Allocator, input: Input, refusal: *Refusal, cache: *lowering_cache.Cache) CachedError!ir.Module {
    return buildRootsCached(allocator, &.{input.program.main}, input, refusal, cache);
}

/// Build selected roots with optional loaded source; digest-only inputs refuse blobs precisely.
pub fn buildRootsSource(allocator: std.mem.Allocator, program: typed.Program, roots: []const typed.FunctionId, source: ?Source, refusal: *Refusal) Error!ir.Module {
    return buildRootsInput(allocator, roots, .{ .program = program, .source = source }, refusal);
}

fn buildRootsInput(allocator: std.mem.Allocator, roots: []const typed.FunctionId, input: Input, refusal: *Refusal) Error!ir.Module {
    return buildRootsCached(allocator, roots, input, refusal, null) catch |err| switch (err) {
        error.CacheMiss => unreachable,
        else => |other| return other,
    };
}

/// Lower selected roots with optional validated artifact and discovery reuse.
pub fn buildRootsCached(allocator: std.mem.Allocator, roots: []const typed.FunctionId, input: Input, refusal: *Refusal, cache: ?*lowering_cache.Cache) CachedError!ir.Module {
    const program = input.program;
    var mb: ModuleBuilder = .{ .allocator = allocator, .input = input, .refusal = refusal, .discovery = .{ .enabled = cache != null } };
    defer if (mb.provider_types) |facts| allocator.free(facts);
    mb.module.single_owner = input.single_owner or input.zero_rc;
    mb.module.zero_rc = input.zero_rc;
    defer mb.discovery.ids.deinit(allocator);
    defer mb.types.deinit(allocator);
    defer mb.discovery.pending.deinit(allocator);
    defer mb.discovery.types.deinit(allocator);
    for (roots, 0..) |root, position| {
        const index = try mb.functionIndex(root);
        if (position == 0) mb.module.entry = index;
    }
    var reuse: ?lowering_cache.Session = if (cache) |store| lowering_cache.Session.prepare(store, mb.lowering()) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidSnapshot => null,
    } else null;
    if (reuse == null) if (cache) |stored| if (stored.demand) |queries| if (queries.count() != 0) return error.CacheMiss;
    if (reuse) |*session| {
        var scratch = std.heap.ArenaAllocator.init(session.cache.store.backing);
        defer scratch.deinit();
        try session.advance(scratch.allocator(), .{ .functions = 0, .compounds = 0, .strings = 0, .pending = 0, .types = 0 }, mb.lowering());
    }
    var next: usize = 0;
    while (next < mb.discovery.pending.items.len) : (next += 1) {
        const id = mb.discovery.pending.items[next];
        const index = mb.discovery.ids.get(@backingInt(id)).?;
        const function = program.functions[@backingInt(id)];
        if (mb.module.functions.items[index].signature.linkage == .internal) {
            // Building may declare callees and grow the table, so store afterwards.
            const built = if (reuse) |*session| blk: {
                var scratch = std.heap.ArenaAllocator.init(session.cache.store.backing);
                defer scratch.deinit();
                const a = scratch.allocator();
                const before = lowering_cache.Before.init(mb.lowering());
                const key: ?[32]u8 = session.key(mb.lowering(), function) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidSnapshot => null,
                };
                if (key) |digest| if (try session.restore(a, digest, mb.lowering(), function, mb.module.functions.items[index])) |cached| {
                    try session.advance(a, before, mb.lowering());
                    break :blk cached;
                };
                if (session.cache.demand) |queries| if (queries.omitted(id)) return error.CacheMiss;
                const fresh = try buildFunction(&mb, function, mb.module.functions.items[index]);
                session.cache.lowered += 1;
                if (key) |digest| try session.remember(a, mb.lowering(), .{ .key = digest, .before = before, .checked = function }, fresh);
                try session.advance(a, before, mb.lowering());
                break :blk fresh;
            } else try buildFunction(&mb, function, mb.module.functions.items[index]);
            mb.module.functions.items[index] = built;
        }
    }
    // Unmaterialized functions receive the same local normalization on demand.
    for (0..mb.module.functions.items.len) |index| {
        if (cache) |stored| if (stored.lazy) |lazy| {
            if (index < lazy.tables.loaded.items.len and !lazy.tables.loaded.items[index]) continue;
        };
        try @import("lowering_finish.zig").function(allocator, &mb.module, index);
    }
    // Ownership (copies before shared updates, counting) is `own.zig`'s, after the release passes.
    if (cache) |stored| if (stored.demand) |queries| try queries.recordReachable(mb.discovery.pending.items);
    return mb.module;
}

/// How one checked function fared: built (its Core IR), or the reason it was refused.
pub const Outcome = struct {
    name: []const u8,
    refusal: ?[]const u8,
    function: ?ir.Function = null,
    /// The types the built function uses (its own module's interned compounds).
    module: ?ir.Module = null,
};

/// Try to build every function of `program` on its own (the coverage sweep).
pub fn coverage(allocator: std.mem.Allocator, program: typed.Program) Error![]Outcome {
    return coverageSource(allocator, program, null);
}

/// Coverage checks with optional resolved embedded-asset content.
pub fn coverageSource(allocator: std.mem.Allocator, program: typed.Program, source: ?Source) Error![]Outcome {
    return coverageInput(allocator, .{ .program = program, .source = source });
}

/// Coverage checks under the caller's selected source ownership and runtime ABI.
pub fn coverageInput(allocator: std.mem.Allocator, input: Input) Error![]Outcome {
    const program = input.program;
    const outcomes = try allocator.alloc(Outcome, program.functions.len);
    for (program.functions, outcomes) |function, *outcome| {
        outcome.* = .{ .name = function.name, .refusal = null };
        if (function.policy.c_abi or function.policy.host != null) {
            outcome.refusal = if (function.policy.c_abi) "extern" else "host function";
            continue;
        }
        var refusal: Refusal = .{};
        var mb: ModuleBuilder = .{ .allocator = allocator, .input = input, .refusal = &refusal };
        defer if (mb.provider_types) |facts| allocator.free(facts);
        mb.module.single_owner = input.single_owner or input.zero_rc;
        mb.module.zero_rc = input.zero_rc;
        const index = mb.functionIndex(function.id) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => {
                outcome.refusal = refusal.reason;
                continue;
            },
        };
        outcome.function = buildFunction(&mb, function, mb.module.functions.items[index]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => blk: {
                outcome.refusal = refusal.reason;
                break :blk null;
            },
        };
        outcome.module = mb.module;
    }
    return outcomes;
}

/// The `ir.Signature.owned` bits of a function whose parameters (`unit` ones included)
/// are `all` and whose `mut` parameters sit at `mutated`: a `mut` parameter is passed
/// by value and returned, so the call hands it over (bits count passed parameters only).
fn ownedParameters(all: []const ir.Type, function: typed.Function, program: typed.Program, zero_rc: bool) u64 {
    var bits: u64 = 0;
    for (all, function.scope.locals[0..all.len], 0..) |_, local_info, position| {
        const mutated = std.mem.indexOfScalar(u16, function.signature.declared_mutates, @intCast(position)) != null;
        const affine = zero_rc and @import("single_owner_resource.zig").affine(program, local_info.ty);
        if (!mutated and !affine) continue;
        var passed: u6 = 0;
        for (all[0..position]) |param| passed += @intFromBool(param != .void);
        if (position < all.len and all[position] != .void) bits |= @as(u64, 1) << passed;
    }
    return bits;
}

const ModuleBuilder = struct {
    allocator: std.mem.Allocator,
    input: Input,
    refusal: *Refusal,
    module: ir.Module = .{},
    discovery: lowering_cache.Discovery = .{},
    /// Checked record and union type → IR type. An entry is made before the type's fields
    /// are mapped, so a recursive type (through a boxed field) finds itself.
    types: std.AutoHashMapUnmanaged(typed.Type, ir.Type) = .empty,
    provider_types: ?[]bool = null,

    fn hasProvider(self: *ModuleBuilder, ty: typed.Type) Error!bool {
        if (self.provider_types == null) self.provider_types = try aggregate_provider.classify(self.allocator, self.input.program);
        return aggregate_provider.contains(self.provider_types.?, ty);
    }

    fn lowering(self: *ModuleBuilder) lowering_cache.Context {
        return .{ .arena = self.allocator, .input = .{ .program = self.input.program, .source = self.input.source, .drop_debug = self.input.drop_debug }, .module = &self.module, .discovery = &self.discovery, .types = &self.types };
    }

    /// Record an unsupported feature at its source position.
    pub fn refuse(self: *ModuleBuilder, reason: []const u8, span: u32) Error {
        self.refusal.* = .{ .reason = reason, .span = span };
        return error.Unsupported;
    }

    /// The IR index of a checked function, declaring it on first use.
    fn functionIndex(self: *ModuleBuilder, id: typed.FunctionId) Error!u32 {
        if (self.discovery.ids.get(@backingInt(id))) |index| return index;
        const function = self.input.program.functions[@backingInt(id)];
        if (self.viewType(function.signature.return_type)) return self.refuse("escaping live dictionary view", @intCast(function.declaration.start));
        const all = try self.allocator.alloc(ir.Type, function.signature.parameter_count);
        for (all, function.scope.locals[0..all.len]) |*param, local| param.* = try self.mapType(local.ty, @intCast(local.declaration.start));
        // A `unit` parameter carries nothing, so it is not passed.
        var passed: std.ArrayList(ir.Type) = .empty;
        for (all) |param| if (param != .void) try passed.append(self.allocator, param);
        const params = passed.items;
        const span: u32 = @intCast(function.declaration.start);
        const linkage: ir.Linkage = if (function.policy.c_abi) .extern_c else if (function.policy.host != null) return self.refuse("host function", span) else .internal;
        const declared = try self.mapType(function.signature.return_type, span);
        if (linkage == .extern_c) {
            for (params) |param| if (param != .cap and param.integer() == null and param != .bool and param != .f64) return self.refuse("source extern aggregate ABI", span);
            if (declared != .void and declared.integer() == null and declared != .bool and declared != .f64) return self.refuse("source extern aggregate ABI", span);
        }
        if (linkage == .extern_c and function.signature.declared_mutates.len != 0) return self.refuse("mut parameter of an extern function", span);
        const ret = try self.returnType(function, declared, all, span);
        const index: u32 = @intCast(self.module.functions.items.len);
        const owned = ownedParameters(all, function, self.input.program, self.module.zero_rc);
        try self.module.functions.append(self.allocator, .{ .name = function.name, .signature = .{ .params = params, .ret = ret, .linkage = linkage, .owned = owned }, .span = span });
        try self.discovery.ids.put(self.allocator, @backingInt(id), index);
        try self.discovery.pending.append(self.allocator, id);
        return index;
    }

    /// The IR return type of `function`: its declared type, or, when it has `mut` parameters,
    /// a record of that value (unless it is `unit`) followed by each `mut` parameter's final
    /// value in parameter order. The caller writes those values back into its places, which
    /// is the `inout` of a `mut` parameter done by value (docs/design/new-core-s1.md §7).
    fn returnType(self: *ModuleBuilder, function: typed.Function, declared: ir.Type, params: []const ir.Type, _: u32) Error!ir.Type {
        const mutated = function.signature.declared_mutates;
        if (mutated.len == 0) return declared;
        // Declared permissions define inout even when a branch performs no write.
        var parts: std.ArrayList(ir.Type) = .empty;
        defer parts.deinit(self.allocator);
        if (declared != .void) try parts.append(self.allocator, declared);
        for (mutated) |position| try parts.append(self.allocator, params[position]);
        if (parts.items.len == 1) return parts.items[0];
        return self.module.intern(self.allocator, .{ .record = parts.items });
    }

    /// The Core IR type of a checked type, or a refusal.
    pub fn mapType(self: *ModuleBuilder, ty: typed.Type, span: u32) Error!ir.Type {
        return switch (ty) {
            .i64 => .i64,
            .bool => .bool,
            .i8 => .i8,
            .i16 => .i16,
            .i32 => .i32,
            .u8 => .u8,
            .u16 => .u16,
            .u32 => .u32,
            .u64 => .u64,
            .unit => .void,
            .host_cap, .stream_cap => .cap,
            .clock_cap, .random_cap, .filesystem_cap, .network_cap, .environment_cap => .capability,
            .file, .text_file => .resource,
            else => self.mapAggregate(ty, span),
        };
    }

    fn mapAggregate(self: *ModuleBuilder, ty: typed.Type, span: u32) Error!ir.Type {
        const records = self.input.program.records;
        if (!ty.isAggregate()) return self.refuse(if (ty.isFile()) "file handle type" else "capability type", span);
        if (ty.recordIndex() >= records.len) return self.refuse("type", span);
        const record = records[ty.recordIndex()];
        if (record.shape.builtin == .borrowed_view) {
            if (!self.module.zero_rc) return self.refuse("borrowed views require --experimental-zero-rc", span);
            return .str_view;
        }
        if (record.isCollection()) switch (record.collection.kind) {
            .string => return .str,
            .list => {
                if (self.viewType(record.shape.buffer.?)) return self.refuse("list storage of live dictionary views", span);
                const element = try self.mapType(record.shape.buffer.?, span);
                if (element == .cap) return self.refuse("list element type", span);
                // A list of `None` holds nothing but its length: a list of `false`, whose elements read as unit.
                return self.module.intern(self.allocator, .{ .list = if (element == .void) .bool else element });
            },
            .dictionary => {
                const source_key = try self.mapType(record.collection.key.?, span);
                const key: ir.Type = if (source_key == .void) .bool else source_key;
                if (!build_dict.keySupported(self.module, key)) return self.refuse("dictionary key type", span);
                if (!record.collection.set and self.viewType(record.shape.buffer.?)) return self.refuse("dictionary storage of live dictionary views", span);
                const value = if (record.collection.set) .void else try self.mapType(record.shape.buffer.?, span);
                return self.module.intern(self.allocator, .{ .dict = .{ .key = key, .value = value } });
            },
            .bytes => return if (std.mem.eql(u8, record.name, "byte_buffer")) build_bytes.bufferType(self, span) else .bytes,
        };
        if (record.shape.domain != null and std.mem.eql(u8, record.name, "float")) return .f64;
        if (record.shape.variants) |variants| return self.mapUnion(ty, variants, span);
        if (record.contract.callback) |callback| return build_fn.mapCallable(self, callback, span);
        if (record.shape.array) |array| {
            if (self.viewType(array.element)) return self.refuse("fixed array storage of live dictionary views", span);
            const elem = try self.mapType(array.element, span);
            const n = std.math.cast(u32, array.length) orelse return self.refuse("fixed array length", span);
            return self.module.intern(self.allocator, .{ .array = .{ .elem = if (elem == .void) .bool else elem, .n = n } });
        }
        if (record.shape.resource != null) return .resource;
        // A domain is its wire type: `wrap` and `unwrap` change nothing at run time.
        if (record.shape.domain) |wire| {
            const underlying = try self.mapType(wire, span);
            if (underlying == .void or underlying == .cap) return self.refuse("domain type", span);
            return underlying;
        }
        if (record.isManagedRecord()) return self.refuse("class type", span);
        return self.mapRecord(ty, record, span);
    }

    /// The IR index of runtime `symbol`, declared with this linkage and signature on first use.
    pub fn runtimeFunction(self: *ModuleBuilder, symbol: []const u8, params: []const ir.Type, ret: ir.Type, linkage: ir.Linkage) Error!u32 {
        var owned: u64 = 0;
        var views: u64 = 0;
        if (self.module.zero_rc) {
            const boundary = @import("zero_rc.zig").contract(symbol) orelse
                return self.refuse(try std.fmt.allocPrint(self.allocator, "unaudited zero-RC runtime helper {s}", .{symbol}), 0);
            const owning_result = boundary.result == .fresh or boundary.result == .transferred;
            const nullable_owner = self.module.kind(ret) == .@"union" and self.module.unionLayout(ret).form == .niche;
            if (owning_result != (self.module.isBlock(ret) or nullable_owner)) return self.refuse("zero-RC runtime result contract mismatch", 0);
            if ((boundary.result == .borrowed) != (ret == .str_view)) return self.refuse("zero-RC runtime borrow contract mismatch", 0);
            owned = boundary.owned;
            views = boundary.views;
            if (owned != 0) {
                const valid_result = boundary.result == .transferred or boundary.result == .scalar;
                if (params.len == 0) return self.refuse("zero-RC runtime transfer contract mismatch", 0);
                if (!self.module.isBlock(params[0]) or !valid_result) return self.refuse("zero-RC runtime transfer contract mismatch", 0);
            }
        }
        // One declaration per symbol and signature: a runtime function over lists of several element
        // types has a Core IR signature for each, which are one `ptr` function to LLVM.
        for (self.module.functions.items, 0..) |function, index| {
            if (function.signature.linkage != linkage or !std.mem.eql(u8, function.name, symbol)) continue;
            if (function.signature.ret == ret and std.mem.eql(ir.Type, function.signature.params, params)) return @intCast(index);
        }
        const index: u32 = @intCast(self.module.functions.items.len);
        try self.module.functions.append(self.allocator, .{ .name = symbol, .signature = .{ .params = try self.allocator.dupe(ir.Type, params), .ret = ret, .linkage = linkage, .owned = owned, .views = views } });
        return index;
    }

    /// Reserve the IR type of a checked record or union before its parts are mapped.
    fn reserve(self: *ModuleBuilder, ty: typed.Type) Error!ir.Type {
        const reserved: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + self.module.compounds.items.len));
        try self.module.compounds.append(self.allocator, .{ .record = &.{} });
        try self.types.put(self.allocator, ty, reserved);
        if (self.discovery.enabled) try self.discovery.types.append(self.allocator, .{ .checked = ty, .physical = reserved });
        return reserved;
    }

    fn viewType(self: *ModuleBuilder, ty: typed.Type) bool {
        return ty.isAggregate() and ty.recordIndex() < self.input.program.records.len and self.input.program.records[ty.recordIndex()].shape.builtin == .live_view;
    }

    /// The type a field or payload is stored as: its own type, or a `box` of it when it closes a recursive type.
    fn stored(self: *ModuleBuilder, ty: typed.Type, boxed: bool, span: u32) Error!ir.Type {
        if (self.viewType(ty)) return self.refuse("aggregate storage of live dictionary views", span);
        const mapped = try self.mapType(ty, span);
        if (!boxed or mapped == .void) return mapped;
        return self.module.intern(self.allocator, .{ .box = mapped });
    }

    fn mapRecord(self: *ModuleBuilder, ty: typed.Type, record: typed.Record, span: u32) Error!ir.Type {
        if (self.types.get(ty)) |known| return known;
        const reserved = try self.reserve(ty);
        const fields = try self.allocator.alloc(ir.Type, record.fields.len);
        for (record.fields, fields) |field, *out| {
            out.* = self.stored(field.ty, field.boxed, span) catch |err| return self.unreserve(ty, err);
            if (out.* == .void) out.* = .bool;
        }
        self.module.compounds.items[@backingInt(reserved) - ir.Type.first_compound] = .{ .record = fields };
        return reserved;
    }

    /// Mapping `ty` failed: forget its reservation, so a later use is refused again instead of finding an empty type.
    fn unreserve(self: *ModuleBuilder, ty: typed.Type, err: Error) Error {
        _ = self.types.remove(ty);
        return err;
    }

    /// A union, `Option`, `Result` or payload-free enum: one IR case per checked case, in the checker's order.
    fn mapUnion(self: *ModuleBuilder, ty: typed.Type, variants: typed.Variants, span: u32) Error!ir.Type {
        if (self.types.get(ty)) |known| return known;
        const reserved = try self.reserve(ty);
        const cases = try self.allocator.alloc(ir.Type, variants.cases.len);
        for (variants.cases, cases) |case, *out| {
            out.* = if (case.payload) |payload| self.stored(payload, case.boxed, span) catch |err| return self.unreserve(ty, err) else .void;
        }
        self.module.compounds.items[@backingInt(reserved) - ir.Type.first_compound] = .{ .@"union" = cases };
        return reserved;
    }
};

/// Per-block definitions, incomplete phis and sealed flags of the SSA construction.
const Ssa = struct {
    /// (block << 32 | variable) → value.
    defs: std.AutoHashMapUnmanaged(u64, ir.Ref) = .empty,
    /// Phis created in an unsealed block, with the variable each one joins.
    incomplete: std.AutoHashMapUnmanaged(u32, std.ArrayList(struct { variable: u32, phi: ir.Ref })) = .empty,
    sealed: std.ArrayList(bool) = .empty,
    /// The IR type of each variable: checked locals first, then synthetic joins.
    types: std.ArrayList(ir.Type) = .empty,
    resources: std.ArrayList(build_cap.Scope) = .empty,
    /// Parents already detached for a hidden receiver's imminent write-back.
    prepared: std.AutoHashMapUnmanaged(u32, PreparedPath) = .empty,
    /// Exact nested reconstruction reads share their parent's normalized index.
    array_indices: std.AutoHashMapUnmanaged(typed.NodeId, ir.Ref) = .empty,
    dictionary_defaults: std.AutoHashMapUnmanaged(ir.Ref, build_dict.DefaultSelection) = .empty,
};

/// Where `break` and `continue` of one checked loop go.
const PreparedPath = struct { parents: []const ir.Ref, children: []const ir.Ref };

const LoopTargets = struct { id: usize, latch: ir.BlockId, exit: ir.BlockId };

/// One step from a value to a part of it: a record field, a list element by index, or the payload
/// of one case of a union (the narrowing `if x is None: ...` makes of an `Option`).
const Step = union(enum) { field: u32, element: ir.Ref, payload: u32, mapping: ir.Ref };

/// Where a value lives: a local and a path of steps from it, and how many times the local had
/// been written when the place was named. A write to a hidden receiver (`s.items.append(v)`,
/// `xs[i][j] = v`) rebuilds the path and stores the new root back, unless the root was written
/// since (`writableReceiverOf`).
const Place = struct { root: u32, steps: []const Step, root_version: u32 = 0, through_view: bool = false, snapshot: ir.Ref = .none, publish: ir.Ref = .none, live: ?u32 = null };

const FnBuilder = struct {
    /// Source-place provenance shared with feature builders; no runtime view object.
    pub const FeaturePlace = Place;
    mb: *ModuleBuilder,
    function: ir.Function,
    /// The block instructions are appended to; null after a terminator.
    current: ?ir.BlockId = null,
    ssa: Ssa = .{},
    loops: std.ArrayList(LoopTargets) = .empty,
    checked: typed.Function,
    /// The place each checker-hidden receiver local was initialized from.
    places: std.AutoHashMapUnmanaged(u32, Place) = .empty,
    /// How many times each local has been assigned so far (the builder's own count of writes).
    versions: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    /// Interior arguments watched only while their enclosing call evaluates operands.
    captures: std.ArrayList(struct { place: Place, live: u32 }) = .empty,
    /// Source-order keyword temporaries whose mut place must be captured at initialization.
    capture_slots: std.ArrayList(u32) = .empty,
    /// The type the function declares it returns; `function.signature.ret` is a record
    /// of it and the `mut` parameters' final values when there are any.
    declared_ret: ir.Type = .void,

    /// The allocation context for feature builders.
    pub fn allocator(self: *FnBuilder) std.mem.Allocator {
        return self.mb.allocator;
    }

    /// The checked node used by feature builders.
    pub fn nodeOf(self: *FnBuilder, id: typed.NodeId) typed.Node {
        return self.mb.input.program.nodes[@backingInt(id)];
    }

    fn statementOf(self: *FnBuilder, id: typed.StatementId) typed.Statement {
        return self.mb.input.program.statements[@backingInt(id)];
    }

    /// Refuse a source feature with its exact reason.
    pub fn refuse(self: *FnBuilder, reason: []const u8, span: u32) Error {
        return self.mb.refuse(reason, span);
    }

    /// The frozen module shapes available to feature builders.
    pub fn module(self: *FnBuilder) *ir.Module {
        return &self.mb.module;
    }

    // ---- instructions and blocks -------------------------------------------------

    /// Create a block for feature builder control flow.
    pub fn newBlock(self: *FnBuilder) Error!ir.BlockId {
        const id: ir.BlockId = @fromBackingInt(@intCast(self.function.blocks.items.len));
        try self.function.blocks.append(self.allocator(), .{});
        try self.ssa.sealed.append(self.allocator(), false);
        return id;
    }

    /// Add an instruction that belongs to no block (constants, parameters, undef).
    /// Builder operation available to the feature dispatch modules.
    pub fn detached(self: *FnBuilder, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@intCast(self.function.insts.items.len));
        try self.function.insts.append(self.allocator(), inst);
        return ref;
    }

    /// Append an instruction to the current block.
    pub fn emit(self: *FnBuilder, inst: ir.Inst) Error!ir.Ref {
        const block = self.current orelse return self.mb.refuse("unreachable code", inst.span);
        const ref = try self.detached(inst);
        try self.function.blocks.items[block.index()].insts.append(self.allocator(), ref);
        return ref;
    }

    /// A detached scalar constant for feature builders.
    pub fn constant(self: *FnBuilder, ty: ir.Type, value: i128) Error!ir.Ref {
        const bits: u64 = @bitCast(@as(i64, @truncate(value)));
        return self.detached(.{ .op = .iconst, .ty = ty, .data = bits });
    }

    /// Pack extra operands for feature builders.
    pub fn extraSlice(self: *FnBuilder, refs: []const ir.Ref) Error!u64 {
        const start: u32 = @intCast(self.function.extra.items.len);
        try self.function.extra.appendSlice(self.allocator(), refs);
        return (ir.ExtraSlice{ .start = start, .len = @intCast(refs.len) }).pack();
    }

    fn addPred(self: *FnBuilder, block: ir.BlockId, pred: ir.BlockId) Error!void {
        try self.function.blocks.items[block.index()].preds.append(self.allocator(), pred);
    }

    /// End the current feature builder block with a jump.
    pub fn jump(self: *FnBuilder, target: ir.BlockId) Error!void {
        const from = self.current orelse return;
        _ = try self.emit(.{ .op = .jump, .ty = .void, .data = @backingInt(target) });
        try self.addPred(target, from);
        self.current = null;
    }

    /// End the current feature builder block with a condition.
    pub fn branch(self: *FnBuilder, condition: ir.Ref, then: ir.BlockId, otherwise: ir.BlockId, span: u32) Error!void {
        const from = self.current orelse return;
        _ = try self.emit(.{ .op = .branch, .ty = .void, .a = condition, .data = ir.packTargets(then, otherwise), .span = span });
        try self.addPred(then, from);
        try self.addPred(otherwise, from);
        self.current = null;
    }

    fn hasPreds(self: *FnBuilder, block: ir.BlockId) bool {
        return self.function.blocks.items[block.index()].preds.items.len != 0;
    }

    /// Continue in `block` if anything reaches it.
    /// Enter a reachable feature builder block.
    pub fn enter(self: *FnBuilder, block: ir.BlockId) void {
        self.current = if (self.hasPreds(block)) block else null;
    }

    // ---- SSA construction (Braun et al.) ----------------------------------------

    fn key(block: ir.BlockId, variable: u32) u64 {
        return (@as(u64, @backingInt(block)) << 32) | variable;
    }

    /// Bind an SSA local in a feature builder block.
    pub fn write(self: *FnBuilder, variable: u32, block: ir.BlockId, value: ir.Ref) Error!void {
        try self.ssa.defs.put(self.allocator(), key(block, variable), value);
    }

    /// Read an SSA local in a feature builder block.
    pub fn read(self: *FnBuilder, variable: u32, block: ir.BlockId) Error!ir.Ref {
        if (self.ssa.defs.get(key(block, variable))) |value| return self.function.resolve(value);
        return self.readRecursive(variable, block);
    }

    fn readRecursive(self: *FnBuilder, variable: u32, block: ir.BlockId) Error!ir.Ref {
        const preds = self.function.blocks.items[block.index()].preds.items;
        var value: ir.Ref = undefined;
        if (!self.ssa.sealed.items[block.index()]) {
            value = try self.newPhi(block, variable);
            const entry = try self.ssa.incomplete.getOrPut(self.allocator(), @backingInt(block));
            if (!entry.found_existing) entry.value_ptr.* = .empty;
            try entry.value_ptr.append(self.allocator(), .{ .variable = variable, .phi = value });
        } else if (preds.len == 0) {
            value = try self.detached(.{ .op = .undef, .ty = self.ssa.types.items[variable] });
        } else if (preds.len == 1) {
            value = try self.read(variable, preds[0]);
        } else {
            value = try self.newPhi(block, variable);
            try self.write(variable, block, value);
            value = try self.completePhi(variable, value, block);
        }
        try self.write(variable, block, value);
        return value;
    }

    /// Builder control-flow operation available to feature dispatch modules.
    pub fn newPhi(self: *FnBuilder, block: ir.BlockId, variable: u32) Error!ir.Ref {
        const ref = try self.detached(.{ .op = .phi, .ty = self.ssa.types.items[variable] });
        const list = &self.function.blocks.items[block.index()].insts;
        var at: usize = 0;
        while (at < list.items.len and self.function.insts.items[list.items[at].index()].op == .phi) at += 1;
        try list.insert(self.allocator(), at, ref);
        return ref;
    }

    fn completePhi(self: *FnBuilder, variable: u32, phi: ir.Ref, block: ir.BlockId) Error!ir.Ref {
        var operands: std.ArrayList(ir.Ref) = .empty;
        defer operands.deinit(self.allocator());
        const count = self.function.blocks.items[block.index()].preds.items.len;
        for (0..count) |i| {
            const pred = self.function.blocks.items[block.index()].preds.items[i];
            try operands.append(self.allocator(), try self.read(variable, pred));
        }
        self.function.insts.items[phi.index()].data = try self.extraSlice(operands.items);
        return self.removeTrivial(phi);
    }

    fn removeTrivial(self: *FnBuilder, phi: ir.Ref) Error!ir.Ref {
        var same: ir.Ref = .none;
        for (self.function.operands(self.function.insts.items[phi.index()].data)) |raw| {
            const operand = self.function.resolve(raw);
            if (operand == same or operand == phi) continue;
            if (same != .none) return phi;
            same = operand;
        }
        if (same == .none) same = try self.detached(.{ .op = .undef, .ty = self.function.insts.items[phi.index()].ty });
        self.function.insts.items[phi.index()].op = .copy;
        self.function.insts.items[phi.index()].a = same;
        return same;
    }

    /// Complete the predecessor set of a feature builder block.
    pub fn seal(self: *FnBuilder, block: ir.BlockId) Error!void {
        if (self.ssa.incomplete.fetchRemove(@backingInt(block))) |entry| {
            var pending = entry.value;
            defer pending.deinit(self.allocator());
            for (pending.items) |item| _ = try self.completePhi(item.variable, item.phi, block);
        }
        self.ssa.sealed.items[block.index()] = true;
    }

    fn prepareParent(self: *FnBuilder, base: ir.Ref, span: u32) Error!ir.Ref {
        if (self.module().zero_rc) return base;
        const ty = self.typeOfRef(base);
        const kind = self.mb.module.kind(ty);
        if (kind == .list or kind == .dict) return self.emit(.{ .op = if (kind == .dict) .dict_copy else .list_copy, .ty = ty, .a = base, .data = flags.place_copy, .span = span });
        return base;
    }

    /// Feature builders resolve a receiver place without evaluating it twice.
    pub fn local(self: *FnBuilder, slot: typed.LocalId) u32 {
        _ = self;
        return @intCast(@backingInt(slot));
    }

    /// A fresh variable for a value joined across control flow (short-circuit operators).
    /// Reserve an SSA local for a feature builder join.
    pub fn synthetic(self: *FnBuilder, ty: ir.Type) Error!u32 {
        try self.ssa.types.append(self.allocator(), ty);
        return @intCast(self.ssa.types.items.len - 1);
    }

    // ---- live places (D1) -----------------------------------------------------------

    /// Remember a hidden receiver's place for write-back. Checker-generated refreshes
    /// read the current root into a new SSA value; they never retain an entry alias.
    fn noteAlias(self: *FnBuilder, slot: typed.LocalId, place: ?Place) Error!void {
        const local_info = self.checked.scope.locals[@backingInt(slot)];
        const name = local_info.name;
        if (self.isView(local_info.ty)) {
            if (self.places.contains(self.local(slot))) return self.mb.refuse("rebinding a live dictionary view", @intCast(local_info.declaration.start));
            if (place == null) return self.mb.refuse("live dictionary view with unproved source identity", @intCast(local_info.declaration.start));
            if (place) |source| {
                var aliases = self.places.iterator();
                while (aliases.next()) |entry| {
                    if (entry.key_ptr.* < self.checked.scope.locals.len) continue;
                    if (entry.value_ptr.root == source.root) return self.mb.refuse("ordinary dictionary snapshot combined with a live view", @intCast(local_info.declaration.start));
                }
                if (source.steps.len != 0) return self.mb.refuse("live dictionary view of an interior place", @intCast(local_info.declaration.start));
                try self.places.put(self.allocator(), self.local(slot), source);
            }
            return;
        }
        if (name.len == 0 or name[0] != '<') {
            if (self.mb.module.kind(self.ssa.types.items[self.local(slot)]) == .dict) if (place) |source| {
                if (source.root == self.local(slot)) return;
                var views = self.places.iterator();
                while (views.next()) |entry| {
                    const other = entry.key_ptr.*;
                    if (other >= self.checked.scope.locals.len) continue;
                    if (!self.isView(self.checked.scope.locals[other].ty)) continue;
                    if (entry.value_ptr.root == source.root) {
                        return self.mb.refuse("ordinary dictionary snapshot combined with a live view", @intCast(local_info.declaration.start));
                    }
                }
                try self.places.put(self.allocator(), @as(u32, @intCast(self.checked.scope.locals.len)) + self.local(slot), source);
            };
            return;
        }
        const variable = self.local(slot);
        var found = place orelse {
            _ = self.places.remove(variable);
            return;
        };
        if (std.mem.indexOfScalar(u32, self.capture_slots.items, variable) != null) try build_capture.watch(@TypeOf(self), self, &found, @intCast(local_info.declaration.start));
        try self.places.put(self.allocator(), variable, found);
    }

    /// The checker refreshes writable iteration places before each guard. An entry-only
    /// receiver is one immutable SSA value, so its length cannot change under COW.
    fn iterationCheck(self: *FnBuilder, operation: anytype, span: u32) Error!ir.Ref {
        if (self.version(self.local(operation.owner)) <= 1) return .none;
        const receiver = try self.receiverOf(operation.owner);
        const ty = self.typeOfRef(receiver);
        const raw_length = if (ty == .str) try self.stringChars(receiver, span) else try self.emit(.{
            .op = if (self.mb.module.kind(ty) == .dict) .dict_len else .list_len,
            .ty = .u64,
            .a = receiver,
            .span = span,
        });
        const expected = try self.expression(operation.arguments[0]);
        const length = if (self.typeOfRef(expected) == .u64) raw_length else try self.emit(.{ .op = .convert, .ty = self.typeOfRef(expected), .a = raw_length, .span = span });
        const same = try self.emit(.{ .op = .cmp, .ty = .bool, .a = length, .b = expected, .data = @backingInt(ir.Predicate.eq), .span = span });
        const passed = try self.newBlock();
        const failed = try self.newBlock();
        try self.branch(same, passed, failed, span);
        try self.seal(failed);
        self.current = failed;
        _ = try self.emit(.{ .op = .@"unreachable", .ty = .void, .data = flags.iteration_trap, .span = span });
        try self.seal(passed);
        self.current = passed;
        return .none;
    }

    // ---- statements ---------------------------------------------------------------

    /// Lower one binding store and preserve its alias and assignment facts.
    fn storeStatement(self: *FnBuilder, store: typed.Store, span: u32, assign: bool) Error!void {
        if (store.element) {
            const kind = self.mb.module.kind(self.ssa.types.items[self.local(store.slot)]);
            if (kind != .array and kind != .record) return self.mb.refuse("element store", span);
        }
        try self.guardViewRebind(self.local(store.slot), span);
        var place: ?Place = null;
        const value = try self.expressionPlace(store.value, &place);
        const block = self.current orelse return;
        try self.providerStore(store, place, value, assign, span);
        try self.write(self.local(store.slot), block, value);
        try self.assigned(self.local(store.slot));
        if (assign) try build_capture.invalidate(@TypeOf(self), self, .{ .root = self.local(store.slot), .steps = &.{} }, span);
        try self.noteAlias(store.slot, place);
    }

    fn providerStore(self: *FnBuilder, store: typed.Store, place: ?Place, value: ir.Ref, assign: bool, span: u32) Error!void {
        if (!self.module().zero_rc or self.function.resolve(value) == .none) return;
        if (!try self.mb.hasProvider(self.checked.scope.locals[self.local(store.slot)].ty)) return;
        const slot = self.local(store.slot);
        const info = self.checked.scope.locals[slot];
        if (std.mem.startsWith(u8, info.name, "<")) return;
        if (assign) try aggregate_provider.keepalive(@TypeOf(self), self, try self.read(slot, self.current.?), span);
        // Source moves invalidate the old binding. Its lexical pin must read
        // null on this path, not borrow an already-transferred SSA owner.
        if (place) |source| if (source.steps.len == 0 and source.root != slot) {
            const empty = try self.detached(.{ .op = .undef, .ty = self.typeOfRef(value) });
            try self.write(source.root, self.current.?, empty);
        };
        if (!assign) try self.ssa.resources.append(self.allocator(), .{ .owner = .none, .depth = self.loops.items.len, .pin = slot });
    }

    /// Lower a checked statement and preserve lexical cleanup on every exit.
    pub fn statement(self: *FnBuilder, id: typed.StatementId) Error!void {
        if (self.current == null) return;
        const s = self.statementOf(id);
        const span: u32 = @intCast(s.span.start);
        switch (s.data) {
            .block => |items| {
                const first_resource = self.ssa.resources.items.len;
                defer self.ssa.resources.shrinkRetainingCapacity(first_resource);
                for (items) |item| try self.statement(item);
                if (self.current != null) {
                    var index = self.ssa.resources.items.len;
                    while (index > first_resource) {
                        index -= 1;
                        try build_cap.closeScope(@TypeOf(self), self, self.ssa.resources.items[index], span);
                    }
                }
            },
            .initialize, .assign => |store| try self.storeStatement(store, span, s.data == .assign),
            .range_loop => |range| {
                const binding: u32 = @intCast(range.plan().binding.start);
                try self.storeStatement(range.plan().start, binding, false);
                if (self.current == null) return;
                try self.storeStatement(range.plan().end, binding, false);
                for (range.plan().setup) |setup| try self.statement(setup);
                try self.loopStatement(range.plan().loop.id, range.plan().loop.condition, range.plan().loop.body, range.plan().loop.step);
            },
            .discard => |value| _ = try self.expression(value),
            .ret => |value| {
                const result = try self.expression(value);
                if (self.current == null) return;
                try self.traceReturned(value, result, span);
                try self.returnValue(result, span);
            },
            .branch => |b| try self.branchStatement(b.condition, b.then_body, b.else_body),
            .loop => |loop| try self.loopStatement(loop.id, loop.condition, loop.body, loop.step),
            .loop_exit => |exit| {
                for (self.loops.items, 0..) |targets, depth| if (targets.id == exit.target) {
                    try build_cap.closeScopes(*FnBuilder, self, depth + 1, span);
                    return self.jump(if (exit.continuing) targets.latch else targets.exit);
                };
                return self.mb.refuse("loop exit target", span);
            },
            .match => |m| try self.matchStatement(m.value, m.arms, span),
            .assertion => |check| try self.assertStatement(check),
            // The interim arena rule (docs/design/new-core-s1.md §11): a `with arena()` block is a plain
            // block, and `n.escape(v)` is `v`; reference counting frees at last use. The checker has
            // already rejected every program that lets an arena value outlive its block.
            .with_scope => |scope| {
                if (scope.resource) |source| {
                    const owner = try self.expression(source);
                    const variable = self.local(scope.slot);
                    try self.write(variable, self.current.?, owner);
                    const provider = if (self.module().zero_rc) try self.expression(build_cap.scopeProvider(self.mb.input.program, source).?) else .none;
                    const cleanup: build_cap.Scope = .{ .owner = owner, .depth = self.loops.items.len, .provider = provider };
                    try self.ssa.resources.append(self.allocator(), cleanup);
                    try self.statement(scope.body);
                    if (self.current != null) {
                        try build_cap.closeScope(@TypeOf(self), self, cleanup, span);
                    }
                    _ = self.ssa.resources.pop();
                } else try self.statement(scope.body);
            },
        }
    }

    /// `assert condition[, message]` (and the `@requires`, `@ensures` and `@invariant` clauses the
    /// checker places as assertions): a false condition traps with the clause's code and message at
    /// the condition's position, as the old core does. A message computed from values is evaluated
    /// only on failure and written to stderr on its own line before a trap without a message.
    fn assertStatement(self: *FnBuilder, check: typed.Assertion) Error!void {
        const condition_span: u32 = @intCast(self.nodeOf(check.condition).span.start);
        // A condition known at build time (the checker's `assert false` after a narrowing) leaves no
        // branch: a true one is nothing, a false one ends the path.
        const literal: ?bool = switch (self.nodeOf(check.condition).data) {
            .boolean => |value| value,
            else => null,
        };
        if (literal == true) return;
        const compound = self.isCompound(check.condition);
        const plain = if (compound or literal != null) null else try self.expression(check.condition);
        if (literal == null and !compound and self.current == null) return;
        const failed = if (literal != null) self.current orelse return else try self.newBlock();
        const passed: ?ir.BlockId = if (literal != null) null else try self.newBlock();
        if (passed) |next| {
            if (plain) |value| {
                try self.branch(value, next, failed, condition_span);
            } else {
                try self.branchOn(check.condition, next, failed);
                if (!self.hasPreds(next) and !self.hasPreds(failed)) return;
            }
            try self.seal(failed);
            try self.seal(next);
        }
        self.current = failed;
        if (check.message_value) |node| {
            // The old core prints the rendered message and a newline to stderr, then traps with no message.
            const text = try self.expression(node);
            if (self.current == null) {
                self.current = passed;
                return;
            }
            const operands = [_]ir.Ref{ try self.constant(.cap, 2), try self.textOf(text, self.nodeOf(node).ty, condition_span) };
            _ = try self.emit(.{ .op = .print, .ty = .void, .data = try self.extraSlice(&operands), .span = condition_span });
        }
        const message = self.mb.module.strings.items.len;
        try self.mb.module.strings.append(self.allocator(), if (check.message_value != null) "" else check.message);
        const data = flags.assertion_trap | (@as(u64, @backingInt(check.kind)) << 32) | message;
        _ = try self.emit(.{ .op = .@"unreachable", .ty = .void, .data = data, .span = condition_span });
        self.current = passed;
    }

    /// Go to `then` when condition `node` holds and to `otherwise` when it does not, with `and`, `or`
    /// and `not` as control flow instead of a boolean joined by a phi: each comparison then ends
    /// its own block in a branch, so what a failed or passed test says about its operands (the fact
    /// pass refines them along single-predecessor edges) reaches the blocks beyond it, which a
    /// phi of booleans would hide (`if size < 2 or n < 1: return` says `size >= 2` afterwards).
    /// The caller seals `then` and `otherwise` once every edge into them was made.
    fn branchOn(self: *FnBuilder, node: typed.NodeId, then: ir.BlockId, otherwise: ir.BlockId) Error!void {
        const n = self.nodeOf(node);
        const span: u32 = @intCast(n.span.start);
        switch (n.data) {
            .binary => |b| if (b.op == .logical_and or b.op == .logical_or) {
                const is_or = b.op == .logical_or;
                const middle = try self.newBlock();
                try self.branchOn(b.left, if (is_or) then else middle, if (is_or) middle else otherwise);
                if (self.current == null and !self.hasPreds(middle)) return;
                try self.seal(middle);
                self.current = middle;
                return self.branchOn(b.right, then, otherwise);
            },
            .unary => |u| if (u.op == .not) return self.branchOn(u.operand, otherwise, then),
            else => {},
        }
        const condition = try self.expression(node);
        if (self.current == null) return;
        try self.branch(condition, then, otherwise, span);
    }

    /// Whether `node` is an `and`, an `or` or a `not`, which `branchOn` turns into control flow; any other
    /// condition is evaluated first and branched on (so its blocks keep the numbering they had).
    fn isCompound(self: *FnBuilder, node: typed.NodeId) bool {
        return switch (self.nodeOf(node).data) {
            .binary => |b| b.op == .logical_and or b.op == .logical_or,
            .unary => |u| u.op == .not,
            else => false,
        };
    }

    fn branchStatement(self: *FnBuilder, condition: typed.NodeId, then_body: typed.StatementId, else_body: ?typed.StatementId) Error!void {
        // A plain condition is evaluated first, so the blocks it makes keep their numbers.
        const compound = self.isCompound(condition);
        const plain = if (compound) null else try self.expression(condition);
        if (!compound and self.current == null) return;
        const then_block = try self.newBlock();
        const join = try self.newBlock();
        const else_block = if (else_body != null) try self.newBlock() else join;
        if (plain) |value| {
            try self.branch(value, then_block, else_block, @intCast(self.nodeOf(condition).span.start));
        } else try self.branchOn(condition, then_block, else_block);
        // A condition that cannot complete (it returns first) reaches neither side.
        if (!self.hasPreds(then_block) and !self.hasPreds(else_block)) return;
        try self.seal(then_block);
        self.current = then_block;
        try self.statement(then_body);
        try self.jump(join);
        if (else_body) |other| {
            try self.seal(else_block);
            self.current = else_block;
            try self.statement(other);
            try self.jump(join);
        }
        try self.seal(join);
        self.enter(join);
    }

    fn loopStatement(self: *FnBuilder, id: usize, condition: typed.NodeId, body: typed.StatementId, step: ?typed.StatementId) Error!void {
        const header = try self.newBlock();
        try self.jump(header);
        self.current = header;
        const compound = self.isCompound(condition);
        const plain = if (compound) null else try self.expression(condition);
        const body_block = try self.newBlock();
        const latch = try self.newBlock();
        const exit = try self.newBlock();
        // `while True:` has no exit edge: only a `break` (or a return) leaves it.
        const forever = switch (self.nodeOf(condition).data) {
            .boolean => |value| value,
            else => false,
        };
        if (forever) {
            try self.jump(body_block);
        } else if (plain) |value| {
            try self.branch(value, body_block, exit, @intCast(self.nodeOf(condition).span.start));
        } else {
            try self.branchOn(condition, body_block, exit);
            if (!self.hasPreds(body_block) and !self.hasPreds(exit)) return;
        }
        try self.seal(body_block);
        try self.loops.append(self.allocator(), .{ .id = id, .latch = latch, .exit = exit });
        self.current = body_block;
        try self.statement(body);
        try self.jump(latch);
        try self.seal(latch);
        self.enter(latch);
        if (step) |s| try self.statement(s);
        try self.jump(header);
        _ = self.loops.pop();
        try self.seal(header);
        try self.seal(exit);
        try self.function.loops.append(self.allocator(), .{ .id = id, .header = header, .body = body_block, .latch = latch, .exit = exit });
        self.enter(exit);
    }

    fn matchStatement(self: *FnBuilder, value_node: typed.NodeId, arms: []const typed.MatchArm, span: u32) Error!void {
        const owned = self.module().zero_rc and (@import("single_owner.zig").matchOwnsTemporary(self.mb.input.program.nodes, value_node) or @import("single_owner_resource.zig").affine(self.mb.input.program, self.nodeOf(value_node).ty));
        var value_place: ?Place = null;
        const value = try self.expressionPlace(value_node, &value_place);
        if (self.current == null) return;
        if (arms.len == 0) return self.mb.refuse("empty match", span);
        const tag = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = value, .span = span });
        const join = try self.newBlock();
        for (arms, 0..) |arm, i| {
            const arm_block = try self.newBlock();
            if (i + 1 < arms.len) {
                const expected = try self.constant(.u32, @intCast(arm.tag));
                const is_arm = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = expected, .data = @backingInt(ir.Predicate.eq), .span = span });
                const next = try self.newBlock();
                try self.branch(is_arm, arm_block, next, span);
                try self.seal(next);
                try self.seal(arm_block);
                const resume_at = next;
                self.current = arm_block;
                try self.armBody(arm, value, value_place, owned, span);
                try self.jump(join);
                self.current = resume_at;
            } else {
                try self.jump(arm_block);
                try self.seal(arm_block);
                self.current = arm_block;
                try self.armBody(arm, value, value_place, owned, span);
                try self.jump(join);
            }
        }
        try self.seal(join);
        self.enter(join);
    }

    fn armBody(self: *FnBuilder, arm: typed.MatchArm, value: ir.Ref, value_place: ?Place, owned: bool, span: u32) Error!void {
        if (arm.slot) |slot| {
            const payload = if (owned) try self.propagatedPayload(value, arm.tag, span) else try self.payloadOf(value, arm.tag, span);
            if (owned) if (arm.unpack) |unpack| {
                try self.unpackPayload(payload, unpack.fields, span);
                return self.statement(unpack.body);
            };
            try self.write(self.local(slot), self.current.?, payload);
            // A checker-hidden binding (the narrowing of `x is None`) names the payload in place:
            // a write through it must rebuild the union it came from.
            const place: ?Place = if (value_place) |found| try self.extendPlace(found, .{ .payload = @intCast(arm.tag) }) else null;
            try self.noteAlias(slot, place);
        }
        try self.statement(arm.body);
    }

    /// Split every physical field once; ignored owners are dropped by ownership.
    /// Keeping all reads in this block lets `takeFields` empty the whole record.
    fn unpackPayload(self: *FnBuilder, payload: ir.Ref, slots: []const ?typed.LocalId, span: u32) Error!void {
        const fields = self.module().compound(self.typeOfRef(payload)).record;
        for (fields, slots, 0..) |field, slot, index| {
            const value = try self.emit(.{ .op = .record_get, .ty = field, .a = payload, .data = index, .span = span });
            if (slot) |binding| {
                const inner = if (self.module().kind(field) == .box)
                    try self.emit(.{ .op = .box_take, .ty = self.module().compound(field).box, .a = value, .span = span })
                else
                    value;
                try self.write(self.local(binding), self.current.?, inner);
            }
        }
    }

    /// Recursively materialize an independent owner using the selected contract.
    pub fn copyOwned(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        if (self.ssa.dictionary_defaults.get(self.function.resolve(value))) |selection|
            return build_dict.copyDefault(@TypeOf(self), self, selection, span);
        return single_owner_copy.copy(@TypeOf(self), self, value, span);
    }

    /// Pin both evaluated get inputs without allocating or transferring either.
    pub fn borrowSelection(self: *FnBuilder, selected: ir.Ref, dictionary: ir.Ref, fallback: ir.Ref, span: u32) Error!ir.Ref {
        const ty = self.typeOfRef(selected);
        const callee = @import("borrow_selection.zig").declare(self.allocator(), self.module(), self.typeOfRef(dictionary), ty) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnsupportedInstruction => return self.mb.refuse("invalid borrowed dictionary selection", span),
        };
        return self.emit(.{ .op = .call, .ty = ty, .a = @fromBackingInt(callee), .data = try self.extraSlice(&.{ selected, dictionary, fallback }), .span = span });
    }

    /// Preserve one evaluated lookup for an immediately requested independent copy.
    pub fn rememberDefault(self: *FnBuilder, value: ir.Ref, selection: build_dict.DefaultSelection) Error!void {
        try self.ssa.dictionary_defaults.put(self.allocator(), self.function.resolve(value), selection);
    }

    /// The type of the value `ref` stands for.
    pub fn typeOfRef(self: *FnBuilder, ref: ir.Ref) ir.Type {
        return self.function.inst(self.function.resolve(ref)).ty;
    }

    /// The payload of case `tag` of union `value`, read out of its box when the case is boxed.
    fn payloadOf(self: *FnBuilder, value: ir.Ref, tag: usize, span: u32) Error!ir.Ref {
        const union_type = self.typeOfRef(value);
        const cases = switch (self.mb.module.kind(union_type) orelse return self.mb.refuse(refuse_payload, span)) {
            .@"union" => self.mb.module.compound(union_type).@"union",
            else => return self.mb.refuse(refuse_payload, span),
        };
        if (tag >= cases.len) return self.mb.refuse(refuse_payload, span);
        if (cases[tag] == .void) return .none;
        const payload = try self.emit(.{ .op = .union_payload, .ty = cases[tag], .a = value, .data = tag, .span = span });
        return self.unbox(payload, span);
    }

    /// The value inside `value` when it is a `box` (a recursive field or payload), else `value`.
    fn unbox(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        const ty = self.typeOfRef(value);
        if (self.mb.module.kind(ty) != .box) return value;
        return self.emit(.{ .op = .box_get, .ty = self.mb.module.compound(ty).box, .a = value, .span = span });
    }

    /// `value` as stored in a slot of type `stored`: boxed when the slot is a `box`.
    fn boxFor(self: *FnBuilder, stored: ir.Type, value: ir.Ref, span: u32) Error!ir.Ref {
        if (value == .none and stored == .bool) return self.constant(.bool, 0);
        if (self.mb.module.kind(stored) != .box) return value;
        return self.emit(.{ .op = .box_make, .ty = stored, .a = value, .span = span });
    }

    // ---- places ---------------------------------------------------------------------

    /// The place a checked local names: the one its hidden receiver was initialized from, else itself.
    /// Feature builders resolve a receiver place without evaluating it twice.
    pub fn placeOfLocal(self: *FnBuilder, slot: typed.LocalId) Error!Place {
        const variable = self.local(slot);
        if (self.places.get(variable)) |place| return place;
        return .{ .root = variable, .steps = &.{}, .root_version = self.version(variable) };
    }

    fn version(self: *FnBuilder, variable: u32) u32 {
        return self.versions.get(variable) orelse 0;
    }

    /// Note an assignment to `variable`.
    fn assigned(self: *FnBuilder, variable: u32) Error!void {
        try self.versions.put(self.allocator(), variable, self.version(variable) + 1);
    }

    /// The value a read through receiver `owner` sees. A receiver the checker rooted at a place
    /// (`frame.code`, `xs`) was captured before the operation's arguments were evaluated, and
    /// stays that snapshot when an argument writes the place (`xs[poke(mut xs)]` reads the list
    /// as it was, a replaced field included): the hidden local's own value.
    pub fn receiverOf(self: *FnBuilder, owner: typed.LocalId) Error!ir.Ref {
        return self.read(self.local(owner), self.current.?);
    }

    /// The value a write through receiver `owner` applies to. If evaluating the arguments wrote
    /// the receiver's place, the old runtime applies the write to the payload the receiver
    /// captured, which is the place's still (an in-place change of the place) or no longer (the
    /// callee replaced the field, or cleared the parent) reachable from it; a value cannot tell
    /// the two apart, so the write is refused rather than guessed.
    pub fn writableReceiverOf(self: *FnBuilder, owner: typed.LocalId, span: u32) Error!ir.Ref {
        const variable = self.local(owner);
        const alias = try self.read(variable, self.current.?);
        const place = self.places.get(variable) orelse return alias;
        if (self.version(place.root) != place.root_version) return self.mb.refuse("write to a receiver's place while its arguments are evaluated", span);
        const root = try self.read(place.root, self.current.?);
        const root_kind = self.mb.module.kind(self.typeOfRef(root));
        if (root_kind != .list and root_kind != .dict and !self.module().zero_rc) return alias;
        const parents = try self.allocator().alloc(ir.Ref, place.steps.len);
        const children = try self.allocator().alloc(ir.Ref, place.steps.len);
        var value = root;
        for (place.steps, 0..) |step, index| {
            value = try self.prepareParent(value, span);
            parents[index] = value;
            value = if (self.module().zero_rc and step == .payload)
                try self.propagatedPayload(value, step.payload, span)
            else
                try self.stepGet(value, step, span);
            children[index] = value;
            const kind = self.mb.module.kind(self.typeOfRef(parents[index]));
            if ((kind == .list or kind == .dict) and self.mb.module.managed(self.typeOfRef(value))) self.function.insts.items[value.index()].data = flags.place_read;
        }
        try self.ssa.prepared.put(self.allocator(), variable, .{ .parents = parents, .children = children });
        return value;
    }

    /// Feature builders resolve a receiver place without evaluating it twice.
    pub fn extendPlace(self: *FnBuilder, place: Place, step: Step) Error!Place {
        const steps = try self.allocator().alloc(Step, place.steps.len + 1);
        @memcpy(steps[0..place.steps.len], place.steps);
        steps[place.steps.len] = step;
        return .{ .root = place.root, .steps = steps, .root_version = place.root_version, .through_view = place.through_view, .snapshot = place.snapshot };
    }

    /// Field `index` of record `base`, out of its box when the field is boxed.
    fn fieldGet(self: *FnBuilder, base: ir.Ref, index: usize, span: u32) Error!ir.Ref {
        const record_type = self.typeOfRef(base);
        if (self.mb.module.kind(record_type) == .array) {
            const array = self.mb.module.compound(record_type).array;
            if (index >= array.n) return self.mb.refuse(refuse_field_index, span);
            return self.emit(.{ .op = .array_get, .ty = array.elem, .a = base, .b = try self.constant(.u64, index), .check = .exact, .span = span });
        }
        const fields = switch (self.mb.module.kind(record_type) orelse return self.mb.refuse(refuse_non_record, span)) {
            .record => self.mb.module.compound(record_type).record,
            else => return self.mb.refuse(refuse_non_record, span),
        };
        if (index >= fields.len) return self.mb.refuse(refuse_field_index, span);
        const got = try self.emit(.{ .op = .record_get, .ty = fields[index], .a = base, .data = index, .span = span });
        return self.unbox(got, span);
    }

    /// Record `base` with field `index` replaced by `value` (boxed again when the field is boxed).
    fn fieldSet(self: *FnBuilder, base: ir.Ref, index: usize, value: ir.Ref, span: u32) Error!ir.Ref {
        const record_type = self.typeOfRef(base);
        if (self.mb.module.kind(record_type) == .array) return self.arraySet(base, try self.constant(.u64, index), value, span);
        const fields = switch (self.mb.module.kind(record_type) orelse return self.mb.refuse(refuse_non_record, span)) {
            .record => self.mb.module.compound(record_type).record,
            else => return self.mb.refuse(refuse_non_record, span),
        };
        if (index >= fields.len) return self.mb.refuse(refuse_field_index, span);
        const stored = try self.boxFor(fields[index], value, span);
        return self.emit(.{ .op = .record_set, .ty = record_type, .a = base, .b = stored, .data = index, .span = span });
    }

    /// The part of `base` that `step` reaches.
    fn stepGet(self: *FnBuilder, base: ir.Ref, step: Step, span: u32) Error!ir.Ref {
        switch (step) {
            .field => |index| return self.fieldGet(base, index, span),
            .element => |index| {
                const list_type = self.typeOfRef(base);
                if (self.mb.module.kind(list_type) == .array) return self.emit(.{ .op = .array_get, .ty = self.mb.module.compound(list_type).array.elem, .a = base, .b = index, .check = .exact, .span = span });
                if (self.mb.module.kind(list_type) == .dict) return self.emit(.{ .op = .dict_entry_value, .ty = self.mb.module.compound(list_type).dict.value, .a = base, .b = index, .span = span });
                if (self.mb.module.kind(list_type) != .list) return self.mb.refuse("element of a non-list value", span);
                return self.emit(.{ .op = .list_get, .ty = self.mb.module.compound(list_type).list, .a = base, .b = index, .check = .exact, .span = span });
            },
            .payload => |tag| return self.payloadOf(base, tag, span),
            .mapping => |key_ref| {
                const index = try build_dict.find(@TypeOf(self), self, base, key_ref, span);
                try build_dict.requirePresent(@TypeOf(self), self, index, span);
                return self.emit(.{ .op = .dict_entry_value, .ty = self.mb.module.compound(self.typeOfRef(base)).dict.value, .a = base, .b = index, .span = span });
            },
        }
    }

    /// `base` with the part `step` reaches replaced by `value`.
    fn stepSet(self: *FnBuilder, base: ir.Ref, step: Step, value: ir.Ref, span: u32) Error!ir.Ref {
        switch (step) {
            .field => |index| return self.fieldSet(base, index, value, span),
            .element => |index| return if (self.mb.module.kind(self.typeOfRef(base)) == .array) self.arraySet(base, index, value, span) else self.listSet(base, index, value, span),
            .payload => |tag| return self.payloadSet(base, tag, value, span),
            .mapping => |key_ref| return build_dict.put(@TypeOf(self), self, base, key_ref, value, span),
        }
    }

    /// Union `base` rebuilt as case `tag` carrying `value` (boxed again when the payload is boxed).
    fn payloadSet(self: *FnBuilder, base: ir.Ref, tag: u32, value: ir.Ref, span: u32) Error!ir.Ref {
        const union_type = self.typeOfRef(base);
        const cases = switch (self.mb.module.kind(union_type) orelse return self.mb.refuse(refuse_payload, span)) {
            .@"union" => self.mb.module.compound(union_type).@"union",
            else => return self.mb.refuse(refuse_payload, span),
        };
        if (tag >= cases.len or cases[tag] == .void) return self.mb.refuse(refuse_payload, span);
        return self.emit(.{ .op = .union_make, .ty = union_type, .a = try self.boxFor(cases[tag], value, span), .data = tag, .span = span });
    }

    /// `list` with element `index` replaced by `value`; the index is checked, and ownership
    /// releases the element that is replaced.
    fn listSet(self: *FnBuilder, list: ir.Ref, index: ir.Ref, value: ir.Ref, span: u32) Error!ir.Ref {
        const list_type = self.typeOfRef(list);
        if (self.mb.module.kind(list_type) == .dict) return self.emit(.{ .op = .dict_set_value, .ty = list_type, .a = list, .b = index, .data = try self.extraSlice(&.{value}), .span = span });
        if (self.mb.module.kind(list_type) != .list) return self.mb.refuse("element write of a non-list", span);
        const data = try self.extraSlice(&.{value});
        return self.emit(.{ .op = .list_set, .ty = self.typeOfRef(list), .a = list, .b = index, .data = data, .check = .exact, .span = span });
    }

    /// A checked field destination reconstructs its hidden read into the exact
    /// same slot. Preserve that transfer before store narrowing or ownership.
    fn transferSlotRead(self: *FnBuilder, value: typed.NodeId, list: ir.Ref, index: ir.Ref) Error!void {
        if (!self.module().zero_rc) return;
        const base = switch (self.nodeOf(value).data) {
            .update => |update| update.base,
            .replace => |replace| replace.base,
            else => return,
        };
        const slot = switch (self.nodeOf(base).data) {
            .local => |binding| self.local(binding),
            else => return,
        };
        if (!std.mem.startsWith(u8, self.checked.scope.locals[slot].name, "<")) return;
        const ref = self.function.resolve(try self.read(slot, self.current.?));
        const instruction = self.function.inst(ref);
        if (instruction.op != .list_get or !self.module().managed(instruction.ty)) return;
        if (instruction.data != 0 and instruction.data != flags.place_read) return;
        if (self.function.resolve(instruction.a) != self.function.resolve(list) or self.function.resolve(instruction.b) != self.function.resolve(index)) return;
        self.function.insts.items[ref.index()].data = flags.place_read;
    }

    fn storeInto(self: *FnBuilder, base: ir.Ref, steps: []const Step, value: ir.Ref, span: u32) Error!ir.Ref {
        if (steps.len == 0) return value;
        if (steps.len == 1) return self.stepSet(base, steps[0], value, span);
        const kind = self.mb.module.kind(self.typeOfRef(base));
        const indexed = kind == .list or kind == .dict;
        // Ownership chooses identity, count-tested detach, or copy before the
        // child read. The child can then take the slot's existing owner.
        const parent = try self.prepareParent(base, span);
        const child = try self.stepGet(parent, steps[0], span);
        if (indexed and self.mb.module.managed(self.typeOfRef(child))) self.function.insts.items[child.index()].data = flags.place_read;
        const inner = try self.storeInto(child, steps[1..], value, span);
        if (kind == .dict) return self.listSet(parent, self.function.inst(child).b, inner, span);
        return self.stepSet(parent, steps[0], inner, span);
    }

    /// The value at `place` as its root stands now.
    pub fn readPlace(self: *FnBuilder, place: Place, span: u32) Error!ir.Ref {
        var value = try self.read(place.root, self.current.?);
        for (place.steps) |step| value = try self.stepGet(value, step, span);
        return value;
    }

    /// Store `value` at `place`: rebuild the path from the root's current value and write the root.
    fn storePlace(self: *FnBuilder, place: Place, value: ir.Ref, span: u32) Error!ir.Ref {
        const block = self.current orelse return .none;
        const root = try self.read(place.root, block);
        const rebuilt = try self.storeInto(root, place.steps, value, span);
        try self.write(place.root, self.current.?, rebuilt);
        try self.assigned(place.root);
        try build_capture.invalidate(@TypeOf(self), self, place, span);
        return rebuilt;
    }

    /// A write through receiver `owner` produced `value`: bind it, and store it back where the receiver came from.
    pub fn writeOwner(self: *FnBuilder, owner: typed.LocalId, value: ir.Ref, span: u32) Error!void {
        try self.write(self.local(owner), self.current.?, value);
        try self.assigned(self.local(owner));
        if (self.places.getPtr(self.local(owner))) |place| {
            if (self.ssa.prepared.fetchRemove(self.local(owner))) |entry| {
                var rebuilt = value;
                var index = place.steps.len;
                while (index != 0) {
                    index -= 1;
                    const parent = entry.value.parents[index];
                    rebuilt = if (self.mb.module.kind(self.typeOfRef(parent)) == .dict)
                        try self.listSet(parent, self.function.inst(entry.value.children[index]).b, rebuilt, span)
                    else
                        try self.stepSet(parent, place.steps[index], rebuilt, span);
                }
                try self.write(place.root, self.current.?, rebuilt);
                try self.assigned(place.root);
                try build_capture.invalidate(@TypeOf(self), self, place.*, span);
            } else _ = try self.storePlace(place.*, value, span);
            place.root_version = self.version(place.root);
        } else try build_capture.invalidate(@TypeOf(self), self, .{ .root = self.local(owner), .steps = &.{} }, span);
    }

    // ---- expressions --------------------------------------------------------------

    fn localExpression(self: *FnBuilder, slot: typed.LocalId, ty: typed.Type, out: ?*?Place, span: u32) Error!ir.Ref {
        // Unit has no SSA payload; crossing a join must not manufacture a void phi/undef.
        if (ty == .unit) return .none;
        if (self.isView(ty)) if (self.places.get(self.local(slot))) |source| {
            if (out) |place| place.* = source;
            const dict = try self.readPlace(source, span);
            return self.viewValue(self.ssa.types.items[self.local(slot)], dict, span);
        };
        if (out) |place| {
            place.* = try self.placeOfLocal(slot);
            if (place.*.?.snapshot == .none) place.*.?.snapshot = try self.read(place.*.?.root, self.current.?);
        }
        return self.read(self.local(slot), self.current.?);
    }

    fn fieldPlace(self: *FnBuilder, field: Field, found: Place, span: u32) Error!Place {
        if (self.isView(self.nodeOf(field.base).ty) and field.index == 0) {
            if (self.mb.module.kind(self.typeOfRef(try self.readPlace(found, span))) == .dict) {
                var source = found;
                source.through_view = true;
                return source;
            }
        }
        return self.extendPlace(found, .{ .field = @intCast(field.index) });
    }

    fn guardViewRebind(self: *FnBuilder, variable: u32, span: u32) Error!void {
        var iterator = self.places.iterator();
        while (iterator.next()) |entry| {
            const slot = entry.key_ptr.*;
            if (slot >= self.checked.scope.locals.len or !self.isView(self.checked.scope.locals[slot].ty)) continue;
            if (entry.value_ptr.root == variable) return self.mb.refuse("rebinding the source place of a live dictionary view", span);
        }
    }

    fn isView(self: *FnBuilder, ty: typed.Type) bool {
        return ty.isAggregate() and ty.recordIndex() < self.mb.input.program.records.len and self.mb.input.program.records[ty.recordIndex()].shape.builtin == .live_view;
    }

    fn markView(self: *FnBuilder, ref: ir.Ref) Error!ir.Ref {
        try self.places.put(self.allocator(), view_value_marker | @as(u32, @intCast(ref.index())), .{ .root = std.math.maxInt(u32), .steps = &.{} });
        return ref;
    }

    fn viewValue(self: *FnBuilder, ty: ir.Type, dict: ir.Ref, span: u32) Error!ir.Ref {
        return self.markView(try self.emit(.{ .op = .record_make, .ty = ty, .data = try self.extraSlice(&.{dict}), .span = span }));
    }

    fn validateViews(self: *FnBuilder) Error!void {
        var wrappers: std.ArrayList(ir.Ref) = .empty;
        defer wrappers.deinit(self.allocator());
        var markers = self.places.iterator();
        while (markers.next()) |entry| {
            if (entry.key_ptr.* & view_value_marker != 0) try wrappers.append(self.allocator(), @fromBackingInt(entry.key_ptr.* & ~view_value_marker));
        }
        var views = self.places.iterator();
        while (views.next()) |entry| {
            const slot = entry.key_ptr.*;
            if (slot >= self.checked.scope.locals.len or !self.isView(self.checked.scope.locals[slot].ty)) continue;
            var sources: std.ArrayList(ir.Ref) = .empty;
            defer sources.deinit(self.allocator());
            var definitions = self.ssa.defs.iterator();
            while (definitions.next()) |definition| {
                if (@as(u32, @truncate(definition.key_ptr.*)) == entry.value_ptr.root) try sources.append(self.allocator(), definition.value_ptr.*);
            }
            const span: u32 = @intCast(self.checked.scope.locals[slot].declaration.start);
            switch (try fuse_dict.viewIdentity(self.allocator(), &self.function, &self.mb.module, sources.items, wrappers.items)) {
                .safe => {},
                .exposed => return self.mb.refuse("aggregate or captured dictionary alias combined with a live view", span),
                .unknown => return self.mb.refuse("live dictionary view with unproved source identity", span),
            }
        }
    }

    fn typeOf(self: *FnBuilder, id: typed.NodeId) Error!ir.Type {
        const n = self.nodeOf(id);
        return self.mb.mapType(n.ty, @intCast(n.span.start));
    }

    /// Evaluate a checked expression for a feature builder.
    pub fn expression(self: *FnBuilder, id: typed.NodeId) Error!ir.Ref {
        return self.expressionPlace(id, null);
    }

    /// Build expression `id`. When `out` is given and the expression names a place (a local,
    /// a field of a place, an element read of a place), `out` receives that place.
    fn expressionPlace(self: *FnBuilder, id: typed.NodeId, out: ?*?Place) Error!ir.Ref {
        const n = self.nodeOf(id);
        const span: u32 = @intCast(n.span.start);
        if (self.current == null) return .none;
        switch (n.data) {
            .integer => |value| return self.constant(try self.typeOf(id), value),
            .boolean => |value| return self.constant(.bool, @intFromBool(value)),
            .unit => return .none,
            .local => |slot| return self.localExpression(slot, n.ty, out, span),
            .block_value => |block| {
                try self.statement(block.body);
                return self.expressionPlace(block.value, out);
            },
            .binary => |b| return self.binary(b.op, b.left, b.right, @intCast(b.op_span.start)),
            .unary => |u| return self.unary(u.op, u.operand, try self.typeOf(id), @intCast(u.op_span.start)),
            .cast => |operand| return self.cast(operand, try self.typeOf(id), span),
            .wrap => |operand| return self.wrap(operand, try self.typeOf(id), span),
            .unwrap => |operand| {
                const value = try self.expression(operand);
                if (value == .none) return .none;
                // A domain is its wire type, and a `float` unwraps to its bits only as the prelude spells it.
                if (self.function.inst(value).ty == .f64 or self.function.inst(value).ty == try self.typeOf(id)) return value;
                return self.mb.refuse("unwrap", span);
            },
            .call => |c| return self.call(c.function, c.arguments, if (c.evaluation) |e| e.body else null, c.evaluation_order, span),
            .buffer_operation => |operation| return self.bufferOperation(operation, try self.typeOf(id), span, out),
            .acquire_buffer => |acquire| {
                var capacity = try self.expression(acquire.capacity);
                const buffer_type = try self.typeOf(id);
                if (buffer_type == .str_view) return self.mb.refuse("construct borrowed views with .borrow()", span);
                if (buffer_type == .byte_buffer) return build_bytes.acquire(@TypeOf(self), self, capacity, span);
                if (self.mb.module.kind(buffer_type) == .dict and self.typeOfRef(capacity) != .u64) capacity = try self.emit(.{ .op = .convert, .ty = .u64, .a = capacity, .check = .exact, .span = span });
                return self.emit(.{ .op = if (self.mb.module.kind(buffer_type) == .dict) .dict_new else .list_new, .ty = buffer_type, .a = capacity, .span = span });
            },
            .index => return self.indexExpression(id, try self.typeOf(id), span, out),
            .arena_escape => |value| return self.expression(value),
            .length => |operand| return self.stringLength(operand, span),
            .variant => |case| return self.variantMake(id, case.tag, case.value, span),
            .record => |fields| {
                if (self.isView(n.ty) and out != null and fields.len == 1) {
                    const dict = try self.expressionPlace(fields[0].value, out);
                    return self.viewValue(try self.typeOf(id), dict, span);
                }
                return self.recordMake(id, fields, span);
            },
            .update => |update| return self.recordUpdate(update.base, update.fields, span),
            .field => |field| {
                var base_place: ?Place = null;
                const base = try self.expressionPlace(field.base, if (out != null) &base_place else null);
                if (self.current == null) return .none;
                const value = try self.fieldGet(base, field.index, span);
                if (out) |place| if (base_place) |found| {
                    place.* = try self.fieldPlace(field, found, span);
                };
                return if (n.ty == .unit) .none else value;
            },
            .function_value => |callee| {
                const index = try self.mb.functionIndex(callee);
                return self.detached(.{ .op = .func_ref, .ty = try self.typeOf(id), .data = index, .span = span });
            },
            .invoke => |invocation| return self.invoke(invocation.callee, invocation.arguments, if (invocation.evaluation) |evaluation| evaluation.body else null, invocation.evaluation_order, span),
            .replace => |replacement| return self.arrayReplace(replacement, span),
            .propagate => |try_value| return self.tryValue(try_value.value, try_value.output, span),
            .print => |print| return self.printNode(print, span),
            .array => |items| {
                const ty = try self.typeOf(id);
                if (self.mb.module.kind(ty) == .dict) return build_dict.literal(@TypeOf(self), self, ty, items, span);
                if (ty == .bytes) return build_text.literal(@TypeOf(self), self, items, span);
                if (ty == .byte_buffer) return build_bytes.fromValue(@TypeOf(self), self, .bytes, try build_text.literal(@TypeOf(self), self, items, span), span);
                if (ty == .str) return self.stringConstant(items, span);
                if (self.mb.module.kind(ty) == .list) return build_values.literal(@TypeOf(self), self, ty, items, span);
                if (self.mb.module.kind(ty) != .array) return self.mb.refuse("array", span);
                const values = try self.allocator().alloc(ir.Ref, items.len);
                for (items, values) |item, *value| value.* = try self.boxFor(self.mb.module.compound(ty).array.elem, try self.expression(item), span);
                if (self.current == null) return .none;
                return self.emit(.{ .op = .record_make, .ty = ty, .data = try self.extraSlice(values), .span = span });
            },
            .blob => |asset| return build_bytes.blob(self, asset, try self.typeOf(id), span),
            .acquire_resource,
            .complete_resource,
            .resource_io,
            .restrict_resource,
            .dir_resource,
            .host_resource,
            .environment_get,
            .environment_only,
            .environment_names,
            .external_read,
            .stand_in,
            .stream_write,
            .file_access,
            .file_method,
            => return build_cap.Lower(*FnBuilder).expression(self, n, span),
        }
    }

    /// Normalize a signed negative fixed-array index once, before its place is captured.
    fn arrayIndex(self: *FnBuilder, base: ir.Ref, index: ir.Ref, from_end: bool, span: u32) Error!ir.Ref {
        if (self.mb.module.kind(self.typeOfRef(index)) == .@"union") return self.emit(.{ .op = .union_tag, .ty = .u32, .a = index, .span = span });
        if (!from_end) return index;
        const ty = self.typeOfRef(index);
        const info = ty.integer() orelse return self.mb.refuse("array index type", span);
        if (!info.signed) return index;
        const wide = if (ty == .i64) index else try self.emit(.{ .op = .convert, .ty = .i64, .a = index, .span = span });
        const negative = try self.emit(.{ .op = .cmp, .ty = .bool, .a = wide, .b = try self.constant(.i64, 0), .data = @backingInt(ir.Predicate.lt), .span = span });
        const variable = try self.synthetic(.i64);
        try self.write(variable, self.current.?, wide);
        const adjust = try self.newBlock();
        const join = try self.newBlock();
        try self.branch(negative, adjust, join, span);
        try self.seal(adjust);
        self.current = adjust;
        const fixed = try self.emit(.{ .op = .add, .ty = .i64, .a = wide, .b = try self.constant(.i64, self.mb.module.compound(self.typeOfRef(base)).array.n), .span = span });
        try self.write(variable, adjust, fixed);
        try self.jump(join);
        try self.seal(join);
        self.current = join;
        return self.read(variable, join);
    }

    /// Read a dictionary or array element and remember its place for mut write-back.
    fn arrayGet(self: *FnBuilder, id: typed.NodeId, span: u32, out: ?*?Place) Error!ir.Ref {
        const index = self.nodeOf(id).data.index;
        var base_place: ?Place = null;
        const base = try self.expressionPlace(index.base, if (out != null) &base_place else null);
        const captured = self.ssa.array_indices.get(id);
        const raw = if (captured == null) try self.expression(index.index) else ir.Ref.none;
        if (self.current == null) return .none;
        const ty = self.typeOfRef(base);
        const dictionary = self.mb.module.kind(ty) == .dict;
        if (!dictionary and self.mb.module.kind(ty) != .array) return self.mb.refuse("index of a non-array", span);
        const at = captured orelse if (dictionary) try build_dict.find(@TypeOf(self), self, base, raw, span) else try self.arrayIndex(base, raw, index.from_end, span);
        if (dictionary) try build_dict.requirePresent(@TypeOf(self), self, at, span);
        if (out) |place| if (base_place) |found| {
            place.* = try self.extendPlace(found, .{ .element = at });
        };
        const element = if (dictionary) self.mb.module.compound(ty).dict.value else self.mb.module.compound(ty).array.elem;
        return if (element == .void) .none else self.emit(.{ .op = if (dictionary) .dict_entry_value else .array_get, .ty = element, .a = base, .b = at, .check = if (dictionary) .none else .exact, .span = span });
    }

    /// A fixed-array replacement is a value update; whole mut rebinding stays checker-refused.
    fn arrayReplace(self: *FnBuilder, replacement: @FieldType(@FieldType(typed.Node, "data"), "replace"), span: u32) Error!ir.Ref {
        const base = try self.expression(replacement.base);
        const raw = try self.expression(replacement.index);
        if (self.current == null) return .none;
        const shared = if (self.module().zero_rc and self.mb.module.kind(self.typeOfRef(base)) == .array) self.reconstructedIndex(replacement) else null;
        if (shared) |index| {
            const normalized = try self.arrayIndex(base, raw, replacement.from_end, span);
            const previous = self.ssa.array_indices.get(index);
            try self.ssa.array_indices.put(self.allocator(), index, normalized);
            defer {
                if (previous) |old| self.ssa.array_indices.getPtr(index).?.* = old else _ = self.ssa.array_indices.remove(index);
            }
            const value = try self.expression(replacement.value);
            if (self.current == null) return .none;
            return self.arraySet(base, normalized, value, span);
        }
        const value = try self.expression(replacement.value);
        if (self.current == null) return .none;
        if (self.mb.module.kind(self.typeOfRef(base)) == .dict) return build_dict.put(@TypeOf(self), self, base, raw, value, span);
        if (self.mb.module.kind(self.typeOfRef(base)) != .array) return self.mb.refuse("replace of a non-array", span);
        return self.arraySet(base, try self.arrayIndex(base, raw, replacement.from_end, span), value, span);
    }

    /// Only the exact typed projection being rebuilt can reuse this normalization.
    fn reconstructedIndex(self: *FnBuilder, replacement: @FieldType(@FieldType(typed.Node, "data"), "replace")) ?typed.NodeId {
        const base = switch (self.nodeOf(replacement.value).data) {
            .update => |update| update.base,
            .replace => |replace| replace.base,
            else => return null,
        };
        const projection = switch (self.nodeOf(base).data) {
            .index => |index| index,
            else => return null,
        };
        if (projection.base != replacement.base or projection.index != replacement.index or projection.from_end != replacement.from_end) return null;
        return base;
    }

    /// Replace one normalized array element, preserving aggregate ownership semantics.
    fn arraySet(self: *FnBuilder, base: ir.Ref, index: ir.Ref, value: ir.Ref, span: u32) Error!ir.Ref {
        const ty = self.typeOfRef(base);
        const stored = try self.boxFor(self.mb.module.compound(ty).array.elem, value, span);
        return self.emit(.{ .op = .array_set, .ty = ty, .a = base, .b = index, .data = try self.extraSlice(&.{stored}), .check = .exact, .span = span });
    }

    /// `Name(...)` or `Union.case(...)`: a union value, boxing a recursive payload. Building an
    /// `Err` starts an error trace at this site (ERROR-TRACE-1).
    fn variantMake(self: *FnBuilder, id: typed.NodeId, tag: usize, value_node: ?typed.NodeId, span: u32) Error!ir.Ref {
        const ty = try self.typeOf(id);
        var payload: ir.Ref = .none;
        if (value_node) |value| {
            payload = try self.expression(value);
            if (self.current == null) return .none;
        }
        const cases = switch (self.mb.module.kind(ty) orelse return self.mb.refuse("variant type", span)) {
            .@"union" => self.mb.module.compound(ty).@"union",
            else => return self.mb.refuse("variant type", span),
        };
        if (tag >= cases.len) return self.mb.refuse("variant tag", span);
        if (payload != .none) payload = try self.boxFor(cases[tag], payload, span);
        const made = try self.emit(.{ .op = .union_make, .ty = ty, .a = payload, .data = tag, .span = span });
        if (typed.resultShape(self.nodeOf(id).ty, self.mb.input.program.records)) |shape| {
            if (shape.error_tag == tag) _ = try self.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.origin), .span = span });
        }
        return made;
    }

    /// `Name(fields)`: the fields are evaluated in the order written and placed in declaration order.
    fn recordMake(self: *FnBuilder, id: typed.NodeId, fields: []const typed.FieldInit, span: u32) Error!ir.Ref {
        const ty = try self.typeOf(id);
        const stored = switch (self.mb.module.kind(ty) orelse return self.mb.refuse("record type", span)) {
            .record => self.mb.module.compound(ty).record,
            .array => blk: {
                const array = self.mb.module.compound(ty).array;
                const slots = try self.allocator().alloc(ir.Type, array.n);
                @memset(slots, array.elem);
                break :blk slots;
            },
            else => return self.mb.refuse("record type", span),
        };
        const values = try self.allocator().alloc(ir.Ref, stored.len);
        @memset(values, .none);
        for (fields) |init| {
            if (init.index >= stored.len) return self.mb.refuse(refuse_field_index, span);
            const value = try self.expression(init.value);
            if (self.current == null) return .none;
            values[init.index] = try self.boxFor(stored[init.index], value, span);
        }
        for (values) |value| if (value == .none) return self.mb.refuse("record field without a value", span);
        const made = try self.emit(.{ .op = .record_make, .ty = ty, .data = try self.extraSlice(values), .span = span });
        return if (self.isView(self.nodeOf(id).ty)) self.markView(made) else made;
    }

    /// `update`: the base with each listed field replaced.
    fn recordUpdate(self: *FnBuilder, base_node: typed.NodeId, fields: []const typed.FieldInit, span: u32) Error!ir.Ref {
        var base = try self.expression(base_node);
        if (self.current == null) return .none;
        for (fields) |init| {
            const value = try self.expression(init.value);
            if (self.current == null) return .none;
            base = try self.fieldSet(base, init.index, value, span);
        }
        return base;
    }

    /// `value?`: the payload on success; on failure `return` the failure in the function's own
    /// result type, converting the error into the case of the caller's error union that carries it.
    fn tryValue(self: *FnBuilder, value_node: typed.NodeId, output: typed.Type, span: u32) Error!ir.Ref {
        const input = try self.expression(value_node);
        if (self.current == null) return .none;
        const records = self.mb.input.program.records;
        const input_type = self.nodeOf(value_node).ty;
        const result = try self.mb.mapType(output, span);
        const tag = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = input, .span = span });
        const failed = try self.newBlock();
        const succeeded = try self.newBlock();
        if (typed.resultShape(input_type, records)) |shape| {
            const wanted = typed.resultShape(output, records) orelse return self.mb.refuse("propagation into a non-result", span);
            const is_error = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try self.constant(.u32, @intCast(shape.error_tag)), .data = @backingInt(ir.Predicate.eq), .span = span });
            try self.branch(is_error, failed, succeeded, span);
            try self.seal(failed);
            try self.seal(succeeded);
            self.current = failed;
            // An error passed on unchanged appends its site; one wrapped into a case of the caller's
            // error union is `converted`, naming `Union.case` (design note §6.2).
            const converted = shape.error_type != wanted.error_type;
            const case = if (converted) typed.wrappingCase(records, wanted.error_type, shape.error_type) orelse return self.mb.refuse("error conversion", span) else 0;
            const naming: ir.Ref = if (converted) try self.caseName(wanted.error_type, case) else .none;
            _ = try self.emit(.{ .op = .err_trace, .ty = .void, .a = naming, .data = @backingInt(if (converted) ir.TraceMode.converted else ir.TraceMode.append), .span = span });
            var error_value = try self.propagatedPayload(input, shape.error_tag, span);
            if (converted) {
                if (typed.wrappingRecord(records, wanted.error_type, case, shape.error_type)) |record| {
                    const payload_type = try self.mb.mapType(record, span);
                    const field_type = self.mb.module.compound(payload_type).record[0];
                    const field = try self.boxFor(field_type, error_value, span);
                    error_value = try self.emit(.{ .op = .record_make, .ty = payload_type, .data = try self.extraSlice(&.{field}), .span = span });
                }
                const union_type = try self.mb.mapType(wanted.error_type, span);
                const stored = self.mb.module.compound(union_type).@"union"[case];
                error_value = try self.emit(.{ .op = .union_make, .ty = union_type, .a = try self.boxFor(stored, error_value, span), .data = case, .span = span });
            }
            const stored = self.mb.module.compound(result).@"union"[wanted.error_tag];
            const failure = try self.emit(.{ .op = .union_make, .ty = result, .a = try self.boxFor(stored, error_value, span), .data = wanted.error_tag, .span = span });
            try self.returnValue(failure, span);
            self.current = succeeded;
            return self.propagatedPayload(input, shape.ok_tag, span);
        }
        const none_tag = optionNoneTag(records, input_type) orelse return self.mb.refuse("propagation of a non-result", span);
        _ = optionNoneTag(records, output) orelse return self.mb.refuse("propagation into a non-option", span);
        const is_none = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try self.constant(.u32, @intCast(none_tag)), .data = @backingInt(ir.Predicate.eq), .span = span });
        try self.branch(is_none, failed, succeeded, span);
        try self.seal(failed);
        try self.seal(succeeded);
        self.current = failed;
        const none = try self.emit(.{ .op = .union_make, .ty = result, .data = none_tag, .span = span });
        try self.returnValue(none, span);
        self.current = succeeded;
        return self.propagatedPayload(input, 1 - none_tag, span);
    }

    // The source contract consumes a propagated or freshly matched union. Preserve that
    // transfer in IR, including the ownership of a recursive boxed payload.
    fn propagatedPayload(self: *FnBuilder, input: ir.Ref, tag: usize, span: u32) Error!ir.Ref {
        if (!self.module().zero_rc) return self.payloadOf(input, tag, span);
        const stored = self.module().compound(self.typeOfRef(input)).@"union"[tag];
        if (stored == .void) return .none;
        const payload = if (self.module().kind(stored) == .box) self.module().compound(stored).box else stored;
        return self.emit(.{ .op = .union_take, .ty = payload, .a = input, .data = tag, .span = span });
    }

    /// A string constant `Union.case` naming case `case` of the union `ty`, as the old core spells it.
    fn caseName(self: *FnBuilder, ty: typed.Type, case: usize) Error!ir.Ref {
        const record = self.mb.input.program.records[ty.recordIndex()];
        const text = try std.fmt.allocPrint(self.allocator(), "{s}.{s}", .{ record.name, record.shape.variants.?.cases[case].name });
        const index = self.mb.module.strings.items.len;
        try self.mb.module.strings.append(self.allocator(), text);
        return self.detached(.{ .op = .str_const, .ty = .str, .data = index });
    }

    /// `return value` in a function that returns a `Result`: when the statement did not build the
    /// value itself (a variable, a call, a conditional) and it is an `Err`, its site is appended.
    fn traceReturned(self: *FnBuilder, node: typed.NodeId, result: ir.Ref, span: u32) Error!void {
        const shape = typed.resultShape(self.checked.signature.return_type, self.mb.input.program.records) orelse return;
        if (result == .none or self.nodeOf(node).data == .variant) return;
        const tag = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = result, .span = span });
        const is_error = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try self.constant(.u32, @intCast(shape.error_tag)), .data = @backingInt(ir.Predicate.eq), .span = span });
        const failed = try self.newBlock();
        const done = try self.newBlock();
        try self.branch(is_error, failed, done, span);
        try self.seal(failed);
        self.current = failed;
        _ = try self.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.returned), .span = span });
        try self.jump(done);
        try self.seal(done);
        self.enter(done);
    }

    /// End the function with `result`. A function with `mut` parameters returns a record of its
    /// result (unless `unit`) and the final value of each `mut` parameter.
    fn returnValue(self: *FnBuilder, result: ir.Ref, span: u32) Error!void {
        try build_cap.closeScopes(*FnBuilder, self, 0, span);
        const mutated = self.checked.signature.declared_mutates;
        var value = result;
        if (mutated.len != 0) {
            var parts: std.ArrayList(ir.Ref) = .empty;
            defer parts.deinit(self.allocator());
            if (self.declared_ret != .void) try parts.append(self.allocator(), result);
            for (mutated) |position| {
                try parts.append(self.allocator(), try self.read(position, self.current.?));
            }
            value = if (parts.items.len == 1) parts.items[0] else try self.emit(.{ .op = .record_make, .ty = self.function.signature.ret, .data = try self.extraSlice(parts.items), .span = span });
        }
        _ = try self.emit(.{ .op = .ret, .ty = .void, .a = if (self.function.signature.ret == .void) .none else value, .span = span });
        self.current = null;
    }

    fn binary(self: *FnBuilder, op: typed.BinaryOp, left_node: typed.NodeId, right_node: typed.NodeId, span: u32) Error!ir.Ref {
        if (op == .logical_and or op == .logical_or) return self.shortCircuit(op == .logical_or, left_node, right_node, span);
        var left = try self.expression(left_node);
        var right = try self.expression(right_node);
        if (self.current == null) return .none;
        // The checker may type the literal of `i16 + 1` as `i64`: it takes the other operand's type.
        {
            const left_type = self.typeOfRef(left);
            const right_type = self.typeOfRef(right);
            if (left_type != right_type) {
                if (self.nodeOf(right_node).data == .integer and self.nodeOf(left_node).data != .integer) right = try self.literalAs(right_node, left_type);
                if (self.nodeOf(left_node).data == .integer and self.nodeOf(right_node).data != .integer) left = try self.literalAs(left_node, right_type);
            }
        }
        const ty = self.typeOfRef(left);
        if (op == .mul and (repeatable(ty) or repeatable(self.typeOfRef(right)))) return build_values.repeat(@TypeOf(self), self, left, right, span);
        if (ty == .str or ty == .bytes or ty == .byte_buffer or ty.isCompound()) return self.aggregateCompare(op, left, right, span);
        const is_float = ty == .f64;
        if (op == .saturating_sub or op == .saturating_mul) return self.saturatingFallback(op, left, right, span);
        const Shape = struct { op: ir.Op, check: ir.Check = .none, predicate: ?ir.Predicate = null };
        const shape: Shape = switch (op) {
            .add => .{ .op = .add, .check = .exact },
            .sub => .{ .op = .sub, .check = .exact },
            .mul => .{ .op = .mul, .check = .exact },
            .div => .{ .op = .div, .check = .exact },
            .rem => .{ .op = .rem, .check = .exact },
            .floor_div => .{ .op = .floor_div, .check = .exact },
            .floor_rem => .{ .op = .floor_rem, .check = .exact },
            .wrapping_add => .{ .op = .add },
            .wrapping_sub => .{ .op = .sub },
            .wrapping_mul => .{ .op = .mul },
            .bit_and => .{ .op = .bit_and },
            .bit_or => .{ .op = .bit_or },
            .bit_xor => .{ .op = .bit_xor },
            .shift_left => .{ .op = .shift_left, .check = .exact },
            .shift_right => .{ .op = .shift_right, .check = .exact },
            .saturating_add => .{ .op = .saturating_add },
            .eq => .{ .op = if (is_float) .fcmp else .cmp, .predicate = .eq },
            .ne => .{ .op = if (is_float) .fcmp else .cmp, .predicate = .ne },
            .lt => .{ .op = .cmp, .predicate = .lt },
            .le => .{ .op = .cmp, .predicate = .le },
            .gt => .{ .op = .cmp, .predicate = .gt },
            .ge => .{ .op = .cmp, .predicate = .ge },
            .f64_add => .{ .op = .fadd },
            .f64_sub => .{ .op = .fsub },
            .f64_mul => .{ .op = .fmul },
            .f64_div => .{ .op = .fdiv },
            .f64_eq => .{ .op = .fcmp, .predicate = .eq },
            .f64_lt => .{ .op = .fcmp, .predicate = .lt },
            .f64_le => .{ .op = .fcmp, .predicate = .le },
            else => return self.mb.refuse(@tagName(op), span),
        };
        const is_compare = shape.predicate != null;
        const scalar = is_float or ty.integer() != null or ty == .bool;
        if (!is_compare and !scalar) return self.mb.refuse("binary operand type", span);
        return self.emit(.{
            .op = shape.op,
            .ty = if (is_compare) .bool else ty,
            .a = left,
            .b = right,
            .data = if (shape.predicate) |p| @backingInt(p) else 0,
            .check = shape.check,
            .span = span,
        });
    }

    fn saturatingFallback(self: *FnBuilder, op: typed.BinaryOp, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
        const ty = self.typeOfRef(left);
        const info = ty.integer() orelse return self.mb.refuse("saturating operand type", span);
        const wide_left = if (ty == .u64) left else try self.emit(.{ .op = .convert, .ty = .u64, .a = left, .span = span });
        const wide_right = if (ty == .u64) right else try self.emit(.{ .op = .convert, .ty = .u64, .a = right, .span = span });
        const mode: i128 = @as(i128, @intFromBool(info.signed)) | (if (op == .saturating_mul) @as(i128, 2) else 0);
        const result = try self.runtimeCall("myl_core_saturating_integer", &.{ .u64, .u64, .u32, .u32 }, .u64, &.{ wide_left, wide_right, try self.constant(.u32, info.bits), try self.constant(.u32, mode) }, span);
        return if (ty == .u64) result else self.emit(.{ .op = .convert, .ty = ty, .a = result, .span = span });
    }

    fn repeatable(ty: ir.Type) bool {
        return ty == .str or ty == .bytes or ty.isCompound();
    }

    /// The integer literal `node` as a constant of integer type `ty`.
    fn literalAs(self: *FnBuilder, node: typed.NodeId, ty: ir.Type) Error!ir.Ref {
        if (ty.integer() == null) return self.expression(node);
        return self.constant(ty, self.nodeOf(node).data.integer);
    }

    /// `==` and `!=` of two records, unions (enums, `Option`, `Result`) or lists: structural,
    /// never a pointer comparison. Text compares through the runtime; recursive values use a worklist.
    fn aggregateCompare(self: *FnBuilder, op: typed.BinaryOp, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
        if (op == .add and self.typeOfRef(left) == .str) {
            if (self.function.resolve(left) == self.function.resolve(right)) return self.runtimeCall("myl_core_str_concat", &.{ .str, .str }, .str, &.{ left, right }, span);
            return self.emit(.{ .op = .str_append, .ty = .str, .a = left, .b = right, .span = span });
        }
        if (op == .add and self.typeOfRef(left) == .bytes) return self.runtimeCall("myl_core_bytes_concat", &.{ .bytes, .bytes }, .bytes, &.{ left, right }, span);
        const ty = self.typeOfRef(left);
        const ordering = switch (op) {
            .lt, .le, .gt, .ge => true,
            else => false,
        };
        if ((ty == .str or ty == .bytes) and ordering) {
            const order = try self.runtimeCall("myl_core_octets_compare", &.{ ty, ty }, .i64, &.{ left, right }, span);
            const predicate: ir.Predicate = switch (op) {
                .lt => .lt,
                .le => .le,
                .gt => .gt,
                else => .ge,
            };
            return self.emit(.{ .op = .cmp, .ty = .bool, .a = order, .b = try self.constant(.i64, 0), .data = @backingInt(predicate), .span = span });
        }
        if (op == .add and self.mb.module.kind(ty) == .list) return build_values.concat(@TypeOf(self), self, left, right, span);
        if (op != .eq and op != .ne) return self.mb.refuse(if (op == .add) "concatenation" else "operator on an aggregate value", span);
        const same = try self.equal(left, right, span);
        if (self.current == null or op == .eq) return same;
        return self.emit(.{ .op = .not, .ty = .bool, .a = same, .span = span });
    }

    /// Whether `ty` is recursive: it holds a `box`, or nests deeper than equality is expanded
    /// (a record that holds a list of itself).
    fn recursive(self: *FnBuilder, ty: ir.Type, depth: u32) bool {
        const m = self.mb.module;
        const kind = m.kind(ty) orelse return false;
        if (depth > 6) return true;
        switch (kind) {
            .box => return true,
            .list => return self.recursive(m.compound(ty).list, depth + 1),
            .dict, .@"fn" => return false,
            .array => return self.recursive(m.compound(ty).array.elem, depth + 1),
            .record => for (m.compound(ty).record) |field| if (self.recursive(field, depth + 1)) return true,
            .@"union" => for (m.compound(ty).@"union") |case| if (self.recursive(case, depth + 1)) return true,
        }
        return false;
    }

    /// Whether two values of one type are equal: fields and payloads compare with the type's
    /// own equality (floats as IEEE numbers), and a union's payloads only when its tags are equal.
    pub fn equal(self: *FnBuilder, a: ir.Ref, b: ir.Ref, span: u32) Error!ir.Ref {
        const m = self.mb.module;
        const ty = self.typeOfRef(a);
        if (ty == .str or ty == .bytes or ty == .byte_buffer) {
            return self.effectCall(flags.str_eq_symbol, &.{ ty, self.typeOfRef(b) }, .bool, &.{ a, b }, span);
        }
        // A recursive value would need a function that calls itself, not an expansion in place.
        if (self.recursive(ty, 0)) return build_values.equal(@TypeOf(self), self, a, b, span);
        if (ty == .f64) return self.emit(.{ .op = .fcmp, .ty = .bool, .a = a, .b = b, .data = @backingInt(ir.Predicate.eq), .span = span });
        if (ty.integer() != null or ty == .bool) return self.emit(.{ .op = .cmp, .ty = .bool, .a = a, .b = b, .data = @backingInt(ir.Predicate.eq), .span = span });
        switch (m.kind(ty) orelse return self.mb.refuse(refuse_equality, span)) {
            .record => {
                var all = try self.constant(.bool, 1);
                for (m.compound(ty).record, 0..) |_, i| {
                    const here = try self.equal(try self.fieldGet(a, i, span), try self.fieldGet(b, i, span), span);
                    all = try self.emit(.{ .op = .bit_and, .ty = .bool, .a = all, .b = here, .span = span });
                }
                return all;
            },
            .@"union" => return self.unionEqual(a, b, span),
            .list => return self.listEqual(a, b, span),
            .array => {
                var all = try self.constant(.bool, 1);
                for (0..m.compound(ty).array.n) |i| {
                    const here = try self.equal(try self.fieldGet(a, i, span), try self.fieldGet(b, i, span), span);
                    all = try self.emit(.{ .op = .bit_and, .ty = .bool, .a = all, .b = here, .span = span });
                }
                return all;
            },
            .dict => return build_dict.equal(@TypeOf(self), self, a, b, span),
            .@"fn" => return self.emit(.{ .op = .cmp, .ty = .bool, .a = a, .b = b, .data = @backingInt(ir.Predicate.eq), .span = span }),
            .box => return self.mb.refuse(refuse_equality, span),
        }
    }

    /// Two unions are equal when their tags are and the payloads of that case are.
    fn unionEqual(self: *FnBuilder, a: ir.Ref, b: ir.Ref, span: u32) Error!ir.Ref {
        const cases = self.mb.module.compound(self.typeOfRef(a)).@"union";
        const tag_a = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = a, .span = span });
        const tag_b = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = b, .span = span });
        const tags = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag_a, .b = tag_b, .data = @backingInt(ir.Predicate.eq), .span = span });
        var payloads: std.ArrayList(u32) = .empty;
        defer payloads.deinit(self.allocator());
        for (cases, 0..) |case, k| if (case != .void) try payloads.append(self.allocator(), @intCast(k));
        if (payloads.items.len == 0) return tags;
        const result = try self.synthetic(.bool);
        try self.write(result, self.current.?, tags);
        const check = try self.newBlock();
        const join = try self.newBlock();
        try self.branch(tags, check, join, span);
        try self.seal(check);
        self.current = check;
        for (payloads.items) |case| {
            const arm = try self.newBlock();
            const next = try self.newBlock();
            const is_case = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag_a, .b = try self.constant(.u32, case), .data = @backingInt(ir.Predicate.eq), .span = span });
            try self.branch(is_case, arm, next, span);
            try self.seal(arm);
            try self.seal(next);
            self.current = arm;
            const same = try self.equal(try self.payloadOf(a, case, span), try self.payloadOf(b, case, span), span);
            try self.write(result, self.current.?, same);
            try self.jump(join);
            self.current = next;
        }
        // A tag that carries no payload: equal tags are equal values.
        try self.write(result, self.current.?, tags);
        try self.jump(join);
        try self.seal(join);
        self.enter(join);
        return self.read(result, join);
    }

    /// Two lists are equal when their lengths are and every element pair is.
    fn listEqual(self: *FnBuilder, a: ir.Ref, b: ir.Ref, span: u32) Error!ir.Ref {
        const element = self.mb.module.compound(self.typeOfRef(a)).list;
        const length_a = try self.emit(.{ .op = .list_len, .ty = .u64, .a = a, .span = span });
        const length_b = try self.emit(.{ .op = .list_len, .ty = .u64, .a = b, .span = span });
        const lengths = try self.emit(.{ .op = .cmp, .ty = .bool, .a = length_a, .b = length_b, .data = @backingInt(ir.Predicate.eq), .span = span });
        const result = try self.synthetic(.bool);
        const index = try self.synthetic(.u64);
        try self.write(result, self.current.?, lengths);
        try self.write(index, self.current.?, try self.constant(.u64, 0));
        const header = try self.newBlock();
        const join = try self.newBlock();
        const start = try self.newBlock();
        try self.branch(lengths, start, join, span);
        try self.seal(start);
        self.current = start;
        try self.jump(header);
        self.current = header;
        const position = try self.read(index, header);
        const more = try self.emit(.{ .op = .cmp, .ty = .bool, .a = position, .b = length_a, .data = @backingInt(ir.Predicate.lt), .span = span });
        const body = try self.newBlock();
        const finished = try self.newBlock();
        try self.branch(more, body, finished, span);
        try self.seal(body);
        try self.seal(finished);
        self.current = body;
        // The lengths agree, so both reads are in range.
        const x = try self.emit(.{ .op = .list_get, .ty = element, .a = a, .b = position, .span = span });
        const y = try self.emit(.{ .op = .list_get, .ty = element, .a = b, .b = position, .span = span });
        const same = try self.equal(x, y, span);
        const latch = try self.newBlock();
        const differ = try self.newBlock();
        try self.branch(same, latch, differ, span);
        try self.seal(latch);
        try self.seal(differ);
        self.current = latch;
        try self.write(index, latch, try self.emit(.{ .op = .add, .ty = .u64, .a = position, .b = try self.constant(.u64, 1), .span = span }));
        try self.jump(header);
        try self.seal(header);
        self.current = differ;
        try self.write(result, differ, try self.constant(.bool, 0));
        try self.jump(join);
        self.current = finished;
        try self.write(result, finished, try self.constant(.bool, 1));
        try self.jump(join);
        try self.seal(join);
        self.enter(join);
        return self.read(result, join);
    }

    /// `a or b` / `a and b`: the right operand runs only when it decides the result.
    fn shortCircuit(self: *FnBuilder, is_or: bool, left_node: typed.NodeId, right_node: typed.NodeId, span: u32) Error!ir.Ref {
        const variable = try self.synthetic(.bool);
        const left = try self.expression(left_node);
        const from = self.current orelse return .none;
        try self.write(variable, from, left);
        const right_block = try self.newBlock();
        const join = try self.newBlock();
        if (is_or) try self.branch(left, join, right_block, span) else try self.branch(left, right_block, join, span);
        try self.seal(right_block);
        self.current = right_block;
        const right = try self.expression(right_node);
        if (self.current) |end| try self.write(variable, end, right);
        try self.jump(join);
        try self.seal(join);
        self.enter(join);
        if (self.current == null) return .none;
        return self.read(variable, join);
    }

    fn unary(self: *FnBuilder, op: typed.UnaryOp, operand_node: typed.NodeId, ty: ir.Type, span: u32) Error!ir.Ref {
        const operand = try self.expression(operand_node);
        if (self.current == null) return .none;
        return switch (op) {
            .neg => self.emit(.{ .op = .neg, .ty = ty, .a = operand, .check = .exact, .span = span }),
            .not => self.emit(.{ .op = .not, .ty = .bool, .a = operand, .span = span }),
            .f64_neg => self.emit(.{ .op = .fneg, .ty = .f64, .a = operand, .span = span }),
            .f64_from_i64, .f64_from_u64 => self.emit(.{ .op = .int_to_float, .ty = .f64, .a = operand, .span = span }),
            .f64_to_i64, .f64_to_i32, .f64_to_i16, .f64_to_i8, .f64_to_u8, .f64_to_u16, .f64_to_u32, .f64_to_u64 => self.emit(.{ .op = .float_to_int, .ty = ty, .a = operand, .check = .exact, .span = span }),
            .f64_sqrt, .f64_floor, .f64_ceil, .f64_trunc, .f64_abs, .f64_sin, .f64_cos => self.emit(.{ .op = .float_unary, .ty = .f64, .a = operand, .data = @backingInt(floatSelector(op)), .span = span }),
        };
    }

    fn floatSelector(op: typed.UnaryOp) ir.FloatUnary {
        return switch (op) {
            .f64_sqrt => .sqrt,
            .f64_floor => .floor,
            .f64_ceil => .ceil,
            .f64_trunc => .trunc,
            .f64_abs => .abs,
            .f64_sin => .sin,
            .f64_cos => .cos,
            else => unreachable,
        };
    }

    fn cast(self: *FnBuilder, operand_node: typed.NodeId, target: ir.Type, span: u32) Error!ir.Ref {
        const operand = try self.expression(operand_node);
        if (self.current == null) return .none;
        if (operand == .none) {
            // `str(None)`: the text of a `unit` value.
            if (target != .str or self.nodeOf(operand_node).ty != .unit) return self.mb.refuse("cast of a value that has no result", span);
            const index = self.mb.module.strings.items.len;
            try self.mb.module.strings.append(self.allocator(), "None");
            return self.detached(.{ .op = .str_const, .ty = .str, .data = index });
        }
        const source = self.function.inst(operand).ty;
        if (target == .byte_buffer) return build_bytes.fromValue(@TypeOf(self), self, source, operand, span);
        if (target == .bytes and source == .byte_buffer) return self.runtimeCall("myl_core_buffer_snapshot", &.{.byte_buffer}, .bytes, &.{operand}, span);
        if (target == .bytes and self.mb.module.kind(source) == .list) return build_text.fromList(@TypeOf(self), self, source, operand, span);
        if (target == .str and self.mb.module.kind(source) == .@"fn")
            return @import("build_callable_digest.zig").lower(self, operand_node, operand, span);
        if (target == .str) return self.textOf(operand, self.nodeOf(operand_node).ty, span);
        if (source == target) return operand;
        const from = source.integer() orelse return self.mb.refuse("cast source", span);
        const to = target.integer() orelse return self.mb.refuse("cast target", span);
        // A conversion every source value survives carries no check.
        const fits = (from.signed == to.signed and to.bits >= from.bits) or (!from.signed and to.signed and to.bits > from.bits);
        return self.emit(.{ .op = .convert, .ty = target, .a = operand, .check = if (fits) .none else .exact, .span = span });
    }

    /// `wrap` builds a domain value: for `float` from IEEE bits (a constant) or a float operation.
    fn wrap(self: *FnBuilder, operand_node: typed.NodeId, target: ir.Type, span: u32) Error!ir.Ref {
        if (target != .f64) {
            const wire = try self.expression(operand_node);
            if (wire == .none or self.function.inst(wire).ty != target) return self.mb.refuse("domain wrap", span);
            return wire;
        }
        const operand = self.nodeOf(operand_node);
        if (operand.data == .integer) {
            const bits: u64 = @truncate(@as(u128, @bitCast(operand.data.integer)));
            return self.detached(.{ .op = .fconst, .ty = .f64, .data = bits });
        }
        const value = try self.expression(operand_node);
        if (value == .none or self.function.inst(value).ty == .f64) return value;
        return self.mb.refuse("float bits", span);
    }

    /// A call. `evaluation` is the checker's block that binds the arguments of a keyword call
    /// to temporaries in source order; it runs first and the arguments read the temporaries.
    fn call(self: *FnBuilder, callee: typed.FunctionId, argument_nodes: []const typed.NodeId, evaluation: ?typed.StatementId, order: []const usize, span: u32) Error!ir.Ref {
        const checked_function = self.mb.input.program.functions[@backingInt(callee)];
        if (checked_function.policy.host != null and !checked_function.policy.c_abi) return @import("build_host.zig").call(self, checked_function, argument_nodes, evaluation, span);
        const index = try self.mb.functionIndex(callee);
        const declared = self.mb.input.program.functions[@backingInt(callee)].signature;
        const target: ir.Inst = .{ .op = .call, .a = @fromBackingInt(index), .ty = self.mb.module.functions.items[index].signature.ret };
        const contract: CallContract = .{ .evaluation = evaluation, .order = order, .mutated = declared.declared_mutates, .declared = declared.return_type };
        return self.callTarget(target, argument_nodes, contract, span);
    }

    /// Invoke a top-level function value with the same copy-in/copy-out mut ABI.
    fn invoke(self: *FnBuilder, callee: typed.NodeId, arguments: []const typed.NodeId, evaluation: ?typed.StatementId, order: []const usize, span: u32) Error!ir.Ref {
        const target = try self.expression(callee);
        if (self.current == null) return .none;
        const checked_ty = self.nodeOf(callee).ty;
        const callback = self.mb.input.program.records[checked_ty.recordIndex()].contract.callback orelse return self.mb.refuse("invoke of a non-function", span);
        const signature = self.mb.module.compound(self.typeOfRef(target)).@"fn";
        var inst: ir.Inst = .{ .op = .call_indirect, .a = target, .ty = signature.ret };
        build_fn.directTarget(&self.function, &inst);
        return self.callTarget(inst, arguments, .{ .evaluation = evaluation, .order = order, .mutated = callback.mutates, .declared = callback.return_type }, span);
    }

    const CallContract = struct { order: []const usize = &.{}, evaluation: ?typed.StatementId = null, mutated: []const u16, declared: typed.Type };

    /// Guard captured mut paths after argument evaluation, before entering the callee.
    fn guardMutPlaces(self: *FnBuilder, places: []const Place, span: u32) Error!void {
        for (places, 0..) |first, index| {
            for (places[index + 1 ..]) |second| {
                if (first.root != second.root) continue;
                var overlaps = try self.constant(.bool, 1);
                for (first.steps[0..@min(first.steps.len, second.steps.len)], second.steps[0..@min(first.steps.len, second.steps.len)]) |a, b| {
                    const same = switch (a) {
                        .field => |field| if (b == .field) try self.constant(.bool, @intFromBool(field == b.field)) else try self.constant(.bool, 1),
                        .payload => |tag| if (b == .payload) try self.constant(.bool, @intFromBool(tag == b.payload)) else try self.constant(.bool, 1),
                        .element => |element| if (b == .element) try self.equal(element, b.element, span) else try self.constant(.bool, 1),
                        .mapping => |mapping_key| if (b == .mapping) try self.equal(mapping_key, b.mapping, span) else try self.constant(.bool, 1),
                    };
                    overlaps = try self.emit(.{ .op = .bit_and, .ty = .bool, .a = overlaps, .b = same, .span = span });
                }
                const failed = try self.newBlock();
                const passed = try self.newBlock();
                try self.branch(overlaps, failed, passed, span);
                try self.seal(failed);
                try self.seal(passed);
                self.current = failed;
                const message = self.mb.module.strings.items.len;
                try self.mb.module.strings.append(self.allocator(), "overlapping mut arguments");
                _ = try self.emit(.{ .op = .@"unreachable", .ty = .void, .data = flags.assertion_trap | message, .span = span });
                self.current = passed;
            }
        }
    }

    /// Lower arguments in source order and write mut results back to their captured places.
    fn callTarget(self: *FnBuilder, target: ir.Inst, argument_nodes: []const typed.NodeId, contract: CallContract, span: u32) Error!ir.Ref {
        const mutated = contract.mutated;
        const first_capture = self.captures.items.len;
        const first_slot = self.capture_slots.items.len;
        defer self.captures.items.len = first_capture;
        defer self.capture_slots.items.len = first_slot;
        for (mutated) |position| if (self.nodeOf(argument_nodes[position]).data == .local) {
            try self.capture_slots.append(self.allocator(), self.local(self.nodeOf(argument_nodes[position]).data.local));
        };
        if (contract.evaluation) |body| {
            try self.statement(body);
            if (self.current == null) return .none;
        }
        var arguments: std.ArrayList(ir.Ref) = .empty;
        defer arguments.deinit(self.allocator());
        // A whole `mut` argument names the current caller variable. Interior arguments select
        // a value before later arguments; an ancestor write can orphan that selected value.
        // A later whole-root mutation supersedes publication even if its body preserves the leaf.
        const places = try self.allocator().alloc(Place, mutated.len);
        const values = try self.allocator().alloc(ir.Ref, argument_nodes.len);
        for (0..argument_nodes.len) |written_position| {
            const position = if (contract.order.len == 0) written_position else contract.order[written_position];
            const argument = argument_nodes[position];
            const value = &values[position];
            const slot = std.mem.indexOfScalar(u16, mutated, @intCast(position));
            if (slot != null and self.isView(self.nodeOf(argument).ty)) return self.mb.refuse("mut live dictionary view argument", span);
            var place: ?Place = null;
            value.* = try self.expressionPlace(argument, if (slot != null) &place else null);
            if (slot) |at| {
                places[at] = place orelse return self.mb.refuse("mut argument that is not a place", span);
                try build_capture.watch(@TypeOf(self), self, &places[at], @intCast(self.nodeOf(argument).span.start));
                if (places[at].snapshot == .none) places[at].snapshot = try self.read(places[at].root, self.current.?);
            }
        }
        if (self.current == null) return .none;
        if (target.op == .call and self.mb.module.functions.items[target.a.index()].signature.linkage == .extern_c and values.len != 0 and self.typeOfRef(values[0]) == .cap) {
            _ = try self.effectCall("myl_core_host_check", &.{.cap}, .void, &.{values[0]}, span);
        }
        for (mutated, places) |position, *place| {
            if (place.steps.len > 0 and self.version(place.root) != place.root_version) {
                values[position] = try build_capture.refresh(@TypeOf(self), self, place, values[position], span);
            } else values[position] = try self.readPlace(place.*, span);
        }
        try self.guardMutPlaces(places, span);
        self.captures.items.len = first_capture;
        self.capture_slots.items.len = first_slot;
        // A `unit` argument is evaluated for its effects and not passed.
        for (values) |value| if (value != .none and self.typeOfRef(value) != .void) try arguments.append(self.allocator(), value);
        if (self.mb.module.kind(target.ty) == .dict) for (argument_nodes) |argument| {
            if (self.isView(self.nodeOf(argument).ty)) return self.mb.refuse("dictionary snapshot returned from a live view", span);
        };
        var inst = target;
        inst.data = try self.extraSlice(arguments.items);
        inst.span = span;
        const result = try self.emit(inst);
        if (mutated.len == 0) return if (inst.ty == .void) .none else result;
        const declared = try self.mb.mapType(contract.declared, span);
        return self.writeBack(result, declared != .void, places, span);
    }

    /// A call to a function with `mut` parameters returned `result`: its own value (unless
    /// `unit`) and each `mut` parameter's final value. Store those into the caller's places.
    fn writeBack(self: *FnBuilder, result: ir.Ref, has_value: bool, places: []const Place, span: u32) Error!ir.Ref {
        const record_type = self.typeOfRef(result);
        const parts: []const ir.Type = if (self.mb.module.kind(record_type) == .record) self.mb.module.compound(record_type).record else &.{};
        // One part alone is not wrapped in a record.
        const wrapped = has_value or places.len > 1;
        var value: ir.Ref = result;
        if (wrapped) value = if (has_value) try self.emit(.{ .op = .record_get, .ty = parts[0], .a = result, .data = 0, .span = span }) else .none;
        const first: usize = if (has_value) 1 else 0;
        for (places, 0..) |place, k| {
            const part = if (wrapped) try self.emit(.{ .op = .record_get, .ty = parts[first + k], .a = result, .data = first + k, .span = span }) else result;
            if (place.publish == .none) {
                _ = try self.storePlace(place, part, span);
            } else {
                const write_block = try self.newBlock();
                const join = try self.newBlock();
                try self.branch(place.publish, write_block, join, span);
                try self.seal(write_block);
                self.current = write_block;
                _ = try self.storePlace(place, part, span);
                try self.jump(join);
                try self.seal(join);
                self.enter(join);
            }
        }
        return if (has_value) value else .none;
    }

    fn collectionOperation(self: *FnBuilder, operation: BufferOperation, ty: ir.Type, span: u32, out: ?*?Place) Error!?ir.Ref {
        const receiver_type = self.ssa.types.items[self.local(operation.owner)];
        if (operation.kind == .copy) {
            const copied = try self.copyList(operation.owner, receiver_type, span);
            return copied;
        }
        const collection = self.mb.module.kind(receiver_type) orelse return null;
        switch (collection) {
            .list => {
                if (operation.kind == .contains) {
                    const needle = try self.expression(operation.arguments[0]);
                    if (self.current == null) return .none;
                    const result = try build_values.contains(@TypeOf(self), self, try self.receiverOf(operation.owner), needle, span);
                    return result;
                }
                switch (operation.kind) {
                    .extend, .reverse, .index_of, .insert, .pop_at, .remove, .slice_step, .clear => {
                        const result = try build_list_methods.operation(@TypeOf(self), self, operation, ty, span);
                        return result;
                    },
                    else => {},
                }
            },
            .dict => {
                const result = try build_dict.operation(@TypeOf(self), self, operation, ty, span, out);
                return result;
            },
            else => {},
        }
        return null;
    }

    /// Shared readonly text/octet dispatch used by mutable-byte lowering.
    pub fn textOperation(self: *FnBuilder, operation: BufferOperation, ty: ir.Type, span: u32) Error!ir.Ref {
        return build_text.operation(@TypeOf(self), self, operation, ty, span);
    }

    fn indexExpression(self: *FnBuilder, id: typed.NodeId, result: ir.Type, span: u32, out: ?*?Place) Error!ir.Ref {
        const node = self.nodeOf(id);
        const index = node.data.index;
        const base_type = try self.typeOf(index.base);
        if (base_type == .str_view) {
            const text = self.mb.input.program.records[self.nodeOf(index.base).ty.recordIndex()].collection.kind == .string;
            return build_view.indexed(@TypeOf(self), self, try self.expression(index.base), try self.expression(index.index), text, result, span);
        }
        if (base_type == .str or base_type == .bytes or base_type == .byte_buffer) return build_text.indexed(@TypeOf(self), self, index.base, index.index, span, result);
        const value = try self.arrayGet(id, span, out);
        return if (node.ty == .unit) .none else value;
    }

    fn bufferOperation(self: *FnBuilder, operation: BufferOperation, ty: ir.Type, span: u32, out: ?*?Place) Error!ir.Ref {
        const receiver_type = self.ssa.types.items[self.local(operation.owner)];
        if (self.module().zero_rc and operation.kind == .copy) {
            const source = try self.receiverOf(operation.owner);
            if (self.ssa.dictionary_defaults.contains(self.function.resolve(source))) return self.copyOwned(source, span);
        }
        if (try build_view.dispatch(@TypeOf(self), self, operation, ty, receiver_type, span)) |value| return value;
        const result = try self.bufferOperationRaw(operation, ty, span, out);
        // A length is `u64` in the IR; a `len()` of a view or buffer typed `int` converts it,
        // as the plain `length` node does.
        if (operation.kind != .length or result == .none or ty == .void or self.typeOfRef(result) == ty) return result;
        return self.emit(.{ .op = .convert, .ty = ty, .a = result, .check = .exact, .span = span });
    }

    fn copyList(self: *FnBuilder, owner: typed.LocalId, receiver_type: ir.Type, span: u32) Error!ir.Ref {
        _ = receiver_type;
        if (self.mb.input.single_owner) return single_owner_copy.copy(@TypeOf(self), self, try self.receiverOf(owner), span);
        return self.receiverOf(owner);
    }

    fn bufferOperationRaw(self: *FnBuilder, operation: BufferOperation, ty: ir.Type, span: u32, out: ?*?Place) Error!ir.Ref {
        const kind = operation.kind;
        const owner = operation.owner;
        const argument_nodes = operation.arguments;
        const receiver_type = self.ssa.types.items[self.local(owner)];
        if (kind == .float_round) {
            const value = try self.expression(argument_nodes[0]);
            const digits = try self.expression(argument_nodes[1]);
            return self.runtimeCall("myl_core_round_float", &.{ .f64, .i64 }, .f64, &.{ value, digits }, span);
        }
        if (kind == .iteration_check) return self.iterationCheck(operation, span);
        switch (receiver_type) {
            .byte_buffer => return build_bytes.operation(@TypeOf(self), self, operation, ty, span),
            .str, .bytes => return build_text.operation(@TypeOf(self), self, operation, ty, span),
            else => {},
        }
        if (try self.collectionOperation(operation, ty, span, out)) |result| return result;
        switch (kind) {
            .length => {
                const receiver = try self.receiverOf(owner);
                return if (receiver_type == .str) self.stringChars(receiver, span) else self.emit(.{ .op = .list_len, .ty = .u64, .a = receiver, .span = span });
            },
            .read => {
                if (receiver_type == .str) return self.mb.refuse("string index", span);
                const index = try self.expression(argument_nodes[0]);
                if (self.current == null) return .none;
                const receiver = try self.receiverOf(owner);
                if (out) |place| place.* = try self.extendPlace(try self.placeOfLocal(owner), .{ .element = index });
                const element = try self.emit(.{ .op = .list_get, .ty = if (ty == .void) .bool else ty, .a = receiver, .b = index, .check = .exact, .span = span });
                return if (ty == .void) .none else element;
            },
            .append => {
                var value = try self.expression(argument_nodes[0]);
                if (self.current == null) return .none;
                if (value == .none or self.typeOfRef(value) == .void) value = try self.constant(.bool, 0);
                // The receiver is read after the argument, which may have written its place.
                const list = try self.writableReceiverOf(owner, span);
                const pushed = try self.emit(.{ .op = .list_push, .ty = self.function.inst(list).ty, .a = list, .b = value, .span = span });
                try self.writeOwner(owner, pushed, span);
                return .none;
            },
            .write => {
                if (receiver_type == .str) return self.mb.refuse("string element write", span);
                const index = try self.expression(argument_nodes[0]);
                var value = try self.expression(argument_nodes[1]);
                if (self.current == null) return .none;
                if (value == .none or self.typeOfRef(value) == .void) value = try self.constant(.bool, 0);
                const list = try self.writableReceiverOf(owner, span);
                try self.transferSlotRead(argument_nodes[1], list, index);
                try self.writeOwner(owner, try self.listSet(list, index, value, span), span);
                return .none;
            },
            .pop => {
                if (!receiver_type.isCompound() or self.mb.module.kind(receiver_type) != .list) return self.mb.refuse("pop of a non-list", span);
                const list = try self.writableReceiverOf(owner, span);
                // The last element is read first (index `len - 1`, wrapping to a failing index
                // when empty, which the read reports as the empty-list pop), then dropped.
                const length = try self.emit(.{ .op = .list_len, .ty = .u64, .a = list, .span = span });
                const last = try self.emit(.{ .op = .sub, .ty = .u64, .a = length, .b = try self.constant(.u64, 1), .span = span });
                const element = try self.emit(.{ .op = .list_get, .ty = if (ty == .void) .bool else ty, .a = list, .b = last, .data = flags.pop_read, .check = .exact, .span = span });
                const rest = try self.emit(.{ .op = .list_pop, .ty = receiver_type, .a = list, .check = .exact, .span = span });
                try self.writeOwner(owner, rest, span);
                return if (ty == .void) .none else element;
            },
            // `xs.clear()` replaces the list with an empty one; the old value dies by ownership.
            .clear => {
                if (self.mb.module.kind(receiver_type) != .list) return self.mb.refuse("clear of a non-list", span);
                const empty = try self.emit(.{ .op = .list_new, .ty = receiver_type, .a = try self.constant(.i64, 0), .span = span });
                try self.writeOwner(owner, empty, span);
                return .none;
            },
            // A copy of a value is the value: the next write to either copies (copy on write).
            .copy => return self.copyList(owner, receiver_type, span),
            .snapshot => {
                if (self.mb.input.single_owner) try @import("single_owner.zig").enableSnapshots(self.mb.allocator, &self.mb.module, receiver_type);
                return self.receiverOf(owner);
            },
            .iteration_check => return self.iterationCheck(operation, span),
            // `xs.sort()` (and what `sorted(xs)` sorts): the runtime returns the sorted list, which replaces the place.
            .sort => {
                if (self.mb.module.kind(receiver_type) != .list) return self.mb.refuse("sort of a non-list", span);
                const element = self.mb.module.compound(receiver_type).list;
                _ = build_fn.sortKind(self.mb.module, element) orelse return self.mb.refuse("sort of this element type", span);
                const list = try self.writableReceiverOf(owner, span);
                const sorted = try self.emit(.{ .op = .list_sort, .ty = receiver_type, .a = list, .b = try self.constant(.bool, 0), .span = span });
                try self.writeOwner(owner, sorted, span);
                return .none;
            },
            .sort_keyed => return self.sortKeyed(owner, argument_nodes, span),
            // `separator.join(parts)`: the runtime builds one string from a list of strings.
            .join => {
                if (receiver_type != .str) return self.mb.refuse("join on a non-string", span);
                const parts = try self.expression(argument_nodes[0]);
                if (self.current == null) return .none;
                const parts_type = self.typeOfRef(parts);
                if (self.mb.module.kind(parts_type) != .list or self.mb.module.compound(parts_type).list != .str) return self.mb.refuse("join of a list that is not of strings", span);
                return self.runtimeCall(flags.str_join_symbol, &.{ .str, parts_type }, .str, &.{ try self.receiverOf(owner), parts }, span);
            },
            .parse_int => return build_text.number(@TypeOf(self), self, operation, ty, span),
            else => return self.mb.refuse(@tagName(kind), span),
        }
    }

    /// Gather one owning sorted copy from the checker-built keys and exact strides.
    fn sortKeyed(self: *FnBuilder, owner: typed.LocalId, argument_nodes: []const typed.NodeId, span: u32) Error!ir.Ref {
        var source = try self.expression(argument_nodes[0]);
        var keys = try self.expression(argument_nodes[1]);
        const reverse = try self.expression(argument_nodes[2]);
        if (self.current == null) return .none;
        const source_type = self.typeOfRef(source);
        const keys_type = self.typeOfRef(keys);
        if (self.mb.module.kind(source_type) != .list or self.mb.module.kind(keys_type) != .list) return self.mb.refuse("keyed sort of a non-list", span);
        const shape = build_fn.keyShape(self.mb.module, self.mb.module.compound(keys_type).list) orelse return self.mb.refuse("sort key type", span);
        const strides = @as(u64, self.mb.module.size(self.mb.module.compound(source_type).list)) | (@as(u64, self.mb.module.size(self.mb.module.compound(keys_type).list)) << 32);
        if (self.mb.module.zero_rc) {
            source = try single_owner_copy.copy(@TypeOf(self), self, source, span);
            keys = try single_owner_copy.copy(@TypeOf(self), self, keys, span);
        }
        const symbol = if (self.mb.module.zero_rc) "myl_core_owned_sort_keyed" else "myl_core_s2_sort_keyed";
        const sorts: []const ir.Ref = &.{ source, keys, try self.constant(.u64, shape.shape), try self.constant(.u64, shape.offsets), reverse, try self.constant(.u64, strides) };
        const sorted = try self.runtimeCall(symbol, &.{ source_type, keys_type, .u64, .u64, .bool, .u64 }, source_type, sorts, span);
        try self.writeOwner(owner, sorted, span);
        return .none;
    }

    /// `len(text)` of a string that is not a local (a field, an element, a call result).
    fn stringLength(self: *FnBuilder, operand: typed.NodeId, span: u32) Error!ir.Ref {
        const value = try self.expression(operand);
        if (self.current == null) return .none;
        if (self.mb.module.kind(self.typeOfRef(value)) == .dict) {
            const length = try self.emit(.{ .op = .dict_len, .ty = .u64, .a = value, .span = span });
            return self.emit(.{ .op = .convert, .ty = .i64, .a = length, .check = .exact, .span = span });
        }
        if (self.mb.module.kind(self.typeOfRef(value)) == .array) return self.constant(.i64, self.mb.module.compound(self.typeOfRef(value)).array.n);
        const value_type = self.typeOfRef(value);
        if (value_type == .str_view) return build_view.length(@TypeOf(self), self, value, self.mb.input.program.records[self.nodeOf(operand).ty.recordIndex()].collection.kind == .string, span);
        if (value_type != .str and value_type != .bytes and value_type != .byte_buffer) return self.mb.refuse("length of a non-string", span);
        const chars = if (value_type != .str) try self.emit(.{ .op = .list_len, .ty = .u64, .a = value, .span = span }) else try self.stringChars(value, span);
        return self.emit(.{ .op = .convert, .ty = .i64, .a = chars, .check = .exact, .span = span });
    }

    /// A call of the runtime function `symbol` (declared in the module on first use) with `arguments`.
    /// Invoke an extern helper for a feature builder.
    pub fn runtimeCall(self: *FnBuilder, symbol: []const u8, params: []const ir.Type, ret: ir.Type, arguments: []const ir.Ref, span: u32) Error!ir.Ref {
        const callee = try self.mb.runtimeFunction(symbol, params, ret, .extern_c);
        return self.emit(.{ .op = .call, .ty = ret, .a = @fromBackingInt(@intCast(callee)), .data = try self.extraSlice(arguments), .span = span });
    }

    /// Ordered runtime call that passes every capability token to its adapter.
    pub fn effectCall(self: *FnBuilder, name: []const u8, params: []const ir.Type, ret: ir.Type, arguments: []const ir.Ref, span: u32) Error!ir.Ref {
        const callee = try self.mb.runtimeFunction(name, params, ret, .runtime_c);
        return self.emit(.{ .op = .call, .ty = ret, .a = @fromBackingInt(callee), .data = try self.extraSlice(arguments), .span = span });
    }

    /// The text of `value`, as `str(value)` and an f-string part spell it: a string as it is, an
    /// integer in decimal, a boolean as `True` or `False`.
    pub fn textOf(self: *FnBuilder, value: ir.Ref, source_ty: typed.Type, span: u32) Error!ir.Ref {
        if (value == .none or source_ty == .unit) return self.runtimeCall("myl_core_none_text", &.{}, .str, &.{}, span);
        const ty = self.typeOfRef(value);
        if (self.renderDomain(source_ty)) return build_values.render(*FnBuilder, self, value, source_ty, span);
        if (ty == .str) return value;
        if (ty == .f64) return self.runtimeCall("myl_core_str_from_f64", &.{.f64}, .str, &.{value}, span);
        if (ty == .bool) return self.runtimeCall(flags.str_from_bool_symbol, &.{.bool}, .str, &.{value}, span);
        const info = ty.integer() orelse return build_values.render(*FnBuilder, self, value, source_ty, span);
        const wide: ir.Type = if (info.signed) .i64 else .u64;
        const operand = if (ty == wide) value else try self.emit(.{ .op = .convert, .ty = wide, .a = value, .span = span });
        return self.runtimeCall(if (info.signed) flags.str_from_i64_symbol else flags.str_from_u64_symbol, &.{wide}, .str, &.{operand}, span);
    }

    fn renderDomain(self: *FnBuilder, ty: typed.Type) bool {
        if (!ty.isAggregate()) return false;
        const record = self.mb.input.program.records[ty.recordIndex()];
        return record.shape.domain != null and !std.mem.eql(u8, record.name, "float");
    }

    /// The length of string `value` in Unicode scalars, which is what `len` counts (not bytes):
    /// the runtime counts the bytes that do not continue a scalar.
    /// Builder operation available to the feature dispatch modules.
    pub fn stringChars(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        return self.runtimeCall(flags.str_chars_symbol, &.{.str}, .u64, &.{value}, span);
    }

    /// A string literal: the checker spells it as code points, stored here as UTF-8.
    fn stringConstant(self: *FnBuilder, items: []const typed.NodeId, span: u32) Error!ir.Ref {
        var bytes: std.ArrayList(u8) = .empty;
        for (items) |item| {
            const point = switch (self.nodeOf(item).data) {
                .integer => |value| value,
                else => return self.mb.refuse("string element", span),
            };
            var buffer: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(std.math.cast(u21, point) orelse return self.mb.refuse("code point", span), &buffer) catch return self.mb.refuse("code point", span);
            try bytes.appendSlice(self.allocator(), buffer[0..len]);
        }
        const index = self.mb.module.strings.items.len;
        try self.mb.module.strings.append(self.allocator(), try bytes.toOwnedSlice(self.allocator()));
        return self.detached(.{ .op = .str_const, .ty = .str, .data = index });
    }

    fn printNode(self: *FnBuilder, print: typed.Print, span: u32) Error!ir.Ref {
        // A dropped debug line evaluates nothing, as the old core's lowering dropped it.
        if (print.debug and self.mb.input.drop_debug) return .none;
        if (print.debug or print.separator != null or print.terminator != null) return build_cap.printOptions(*FnBuilder, self, print, span);
        var operands: std.ArrayList(ir.Ref) = .empty;
        defer operands.deinit(self.allocator());
        const stream = if (print.stream) |stream_node| try self.expression(stream_node) else try self.constant(.cap, switch (print.sink) {
            .stdout => 1,
            .stderr => 2,
            .error_report => flags.error_stream,
        });
        try operands.append(self.allocator(), stream);
        for (print.arguments) |argument| {
            const value = try self.expression(argument);
            if (self.current == null) return .none;
            const source_ty = self.nodeOf(argument).ty;
            const ty = if (value == .none) .void else self.typeOfRef(value);
            const needs_render = ty.integer() == null and ty != .bool and ty != .str and ty != .str_view;
            const printable = if (value == .none or self.renderDomain(source_ty) or needs_render) try self.textOf(value, source_ty, span) else value;
            try operands.append(self.allocator(), printable);
        }
        if (self.current == null) return .none;
        _ = try self.emit(.{ .op = .print, .ty = .void, .data = try self.extraSlice(operands.items), .span = span });
        return .none;
    }
};

/// The tag of `None` when `ty` is an `Option` (a two-case union whose first case has no payload).
fn optionNoneTag(records: []const typed.Record, ty: typed.Type) ?usize {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const record = records[ty.recordIndex()];
    const variants = record.shape.variants orelse return null;
    if (!variants.is_union or variants.fallible or variants.cases.len != 2) return null;
    if (variants.cases[0].payload != null or variants.cases[1].payload == null) return null;
    if (!std.mem.startsWith(u8, record.name, "Option")) return null;
    return 0;
}

fn buildFunction(mb: *ModuleBuilder, checked: typed.Function, declared: ir.Function) Error!ir.Function {
    const parallel = @import("build_parallel.zig");
    if (mb.module.zero_rc and parallel.matches(mb.input.source, checked)) return parallel.build(mb, declared);
    var b: FnBuilder = .{ .mb = mb, .function = declared, .checked = checked };
    b.declared_ret = try mb.mapType(checked.signature.return_type, declared.span);
    defer b.places.deinit(mb.allocator);
    defer b.versions.deinit(mb.allocator);
    defer b.captures.deinit(mb.allocator);
    defer b.capture_slots.deinit(mb.allocator);
    defer b.ssa.defs.deinit(mb.allocator);
    defer b.ssa.incomplete.deinit(mb.allocator);
    defer b.ssa.sealed.deinit(mb.allocator);
    defer b.ssa.types.deinit(mb.allocator);
    defer b.ssa.resources.deinit(mb.allocator);
    defer b.loops.deinit(mb.allocator);
    for (checked.scope.locals) |local| {
        const ty = mb.mapType(local.ty, @intCast(local.declaration.start)) catch .void;
        try b.ssa.types.append(mb.allocator, ty);
    }
    const entry = try b.newBlock();
    try b.seal(entry);
    b.current = entry;
    var passed: u64 = 0;
    for (checked.scope.locals[0..checked.signature.parameter_count], 0..) |local, i| {
        const ty = try mb.mapType(local.ty, @intCast(local.declaration.start));
        if (ty == .void) {
            try b.write(@intCast(i), entry, try b.detached(.{ .op = .undef, .ty = .void }));
            continue;
        }
        const param = try b.detached(.{ .op = .param, .ty = ty, .data = passed });
        passed += 1;
        try b.write(@intCast(i), entry, param);
        if (mb.module.zero_rc and try mb.hasProvider(local.ty)) try b.ssa.resources.append(mb.allocator, .{ .owner = .none, .depth = 0, .pin = @intCast(i) });
    }
    try b.statement(checked.scope.body);
    if (b.current != null) {
        if (b.declared_ret != .void) return mb.refuse("missing return", declared.span);
        try b.returnValue(.none, declared.span);
    }
    try b.validateViews();
    return b.function;
}
