//! Per-function checked-to-Core artifacts. Replay preserves discovery order,
//! including private string allocations, before the normal module transforms.
const std = @import("std");
const cache_miss = @import("selka").cache_miss;
const fast_blake3 = @import("fast_blake3.zig");
const language = @import("selka");
const typed = language.typed;
const codec = language.persist_codec;
const ir = @import("ir.zig");
const snapshot = @import("ir_snapshot.zig");
const stage = @import("stage_store.zig");
const flags = @import("flags.zig");
const render = @import("build_render.zig");
const demand = @import("lowering_demand.zig");
const demand_ir = @import("demand_ir.zig");
const demand_sources = @import("demand_sources.zig");
const op_log = @import("op_log.zig");
const record_names = @import("record_names.zig");

const Error = snapshot.Error;
/// Ordered checked declarations owned by the builder.
pub const Discovery = struct {
    ids: std.AutoHashMapUnmanaged(usize, u32) = .empty,
    pending: std.ArrayList(typed.FunctionId) = .empty,
};
/// Borrowed builder state; keeping it explicit avoids a build/cache import cycle.
pub const Context = struct {
    arena: std.mem.Allocator,
    input: struct { program: typed.Program, source: ?language.source.Source, drop_debug: bool },
    module: *ir.Module,
    discovery: *Discovery,
    types: *std.AutoHashMapUnmanaged(typed.Type, ir.Type),
    /// What an artifact is stored and restored by: set whenever a lowering cache is in use.
    names: ?Names = null,
};

/// What the lowering builder offers a restore: declaring a checked function the way its own lowering would (which finds
/// it when it is declared already), and refusing the build.
pub const Builder = struct {
    context: *anyopaque,
    declare: *const fn (context: *anyopaque, id: typed.FunctionId) error{ OutOfMemory, Unsupported }!u32,
    refuse: *const fn (context: *anyopaque, reason: []const u8) error{Unsupported},
};

/// The op log of a lowering, the names of the program's records and the builder. An artifact stores the type operations
/// of its segment and the requests it made of the function table; a restore replays the types and repeats the requests.
pub const Names = struct { log: *op_log.Recorder, records: *const record_names.RecordIndex, builder: Builder };

/// Where an instruction came from, as an artifact stores it: nowhere, at an offset inside the function's own declaration, or at
/// a line and column of a file named by its key path (never by its place among the program's sources).
const Position = union(enum) { zero, local: u32, external: demand_sources.Site };
const Function = struct { value: snapshot.Function, positions: []Position };

/// One request a lowering made of the function table, in the order it made them. A request's position in the artifact's
/// list is the local id its bodies call or take it by; no function id of any program is stored.
const Request = union(enum) {
    /// A checked source function, by its checked name: found when the module declared it already, else declared by the
    /// builder, which maps its signature and queues it for lowering as its own lowering would.
    declare: []const u8,
    /// A runtime or extern declaration: found by name and signature (types local to the artifact), else appended.
    helper: Named,
    /// An internal function made by the compiler that the module must hold already, found by name and signature.
    found: Named,
    /// An internal function this lowering made, with its body: found by its name, else appended.
    define: Function,
    /// A render shape declaration: found by render id, else, when this lowering made it, appended over its string.
    shape: Shape,

    const Named = struct { name: []const u8, signature: ir.Signature };
    const Shape = struct { id: []const u8, string: ?u32 };
};

/// What one function's lowering did to the program's tables: the type operations of its segment (ids local to the artifact,
/// records by name), the requests it made of the function table, and the strings it appended.
const Delta = struct {
    requests: []const Request,
    types: []const op_log.TypeOp,
    strings: []const []const u8,
    string_start: usize,
};
const Wire = struct { function: Function, delta: Delta, sources: []const demand_sources.Proof = &.{} };
/// A function's header record: the wire without its body, what is known about its positions, and the digest of the whole
/// artifact in canonical form (`canonicalDigest`), so a restore that defers the body can still say what it restored.
/// `helpers` says whether finishing the body (`lowering_finish`) declared a runtime helper, which decides whether a build that defers
/// the body can leave it alone; null while that is not known (the finish of a freshly lowered body comes after its header is made).
/// `effects` is the digest of what the lowering did to the program's tables (`effectsDigest`): a restore that finds it unchanged
/// after an edit to the function's body knows the tables its program was assembled with still hold (`lowering_assembly.zig`).
const Header = struct { wire: Wire, local_positions: bool, helpers: ?bool = null, source_max: ?u32, digest: stage.Digest, effects: stage.Digest };
/// Inputs needed to publish one successful function without repeating arguments.
pub const Publication = struct { key: stage.Digest, body: stage.Digest, refs: RefsDto, before: Before, checked: typed.Function };

/// A function's lowering key, with the body digest and the references the key was
/// built from. `remember` stores the references under the body digest, so a later
/// build whose frontend omits the body can rebuild the same key without the tree.
pub const Keyed = struct { key: stage.Digest, body: stage.Digest, refs: RefsDto };

/// Declaration references of one body, as stored under its body digest.
/// A function with a unique name is stored by that name, so an index shift
/// between builds still finds it; any other function keeps its index.
pub const RefsDto = struct { functions: []const FunctionRef = &.{}, types: []const record_names.RecordKeys.Digest = &.{} };

/// One stored function reference: a unique stable name, or a positional index.
pub const FunctionRef = union(enum) { index: u64, name: []const u8 };

fn bodyRefsKey(store: *const stage.Store, body: stage.Digest) stage.Digest {
    return store.key("lowered-body-refs-v4", &.{&body});
}

/// Stable function identities of one checked program. A function whose
/// normalized name no other function shares is named by it in lowering keys,
/// stored references and replayed discovery, so inserting a declaration or
/// numbering generic instances in another order changes no key. A shared name
/// keeps the positional index, exactly as before.
pub const Identities = struct {
    by_name: std.StringHashMapUnmanaged(u32) = .empty,

    const ambiguous = std.math.maxInt(u32);

    /// Index every checked function's normalized name once per program.
    pub fn init(a: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error!Identities {
        var self: Identities = .{};
        try self.by_name.ensureTotalCapacity(a, @intCast(program.functions.len));
        for (program.functions, 0..) |function, index| {
            const found = self.by_name.getOrPutAssumeCapacity(normalizedName(function.name));
            found.value_ptr.* = if (found.found_existing) ambiguous else @intCast(index);
        }
        return self;
    }

    /// The stable name of function `index`, or null when it is out of range or shared.
    pub fn name(self: *const Identities, program: typed.Program, index: usize) ?[]const u8 {
        if (index >= program.functions.len) return null;
        const normalized = normalizedName(program.functions[index].name);
        const found = self.by_name.get(normalized) orelse return null;
        return if (found == index) normalized else null;
    }

    /// The current index of the function uniquely named `value`.
    pub fn find(self: *const Identities, value: []const u8) ?u32 {
        const found = self.by_name.get(value) orelse return null;
        return if (found == ambiguous) null else found;
    }
};

/// A catalog of the declarations a build may reuse (`Catalog`) and whether this build did: the cache keeps the two together.
pub const CatalogUse = struct {
    /// The catalog a previous build hashed, offered to this one; null when there is none.
    known: ?*const Catalog = null,
    /// Whether `prepare` reused `known` (its declarations matched the program) rather than hashing them again.
    reused: bool = false,
};

/// Where the engine's `module-check` parts are read for a function's lowering key (G3g): the digest of the function's checked
/// body part, which covers its region of source and the declarations it names, or null when the engine holds none for it.
pub const PartSource = struct {
    context: *anyopaque,
    digest: *const fn (context: *anyopaque, src: ?language.source.Source, function: typed.Function) ?stage.Digest,
};

/// The engine's side of a lowering cache: `observed` notes what the build lowered or restored for the engine's shadow, and `parts`,
/// when the engine decides lowering, lets a function be keyed by its checked-body part instead of by hashing its tree and the
/// declarations it reaches.
pub const EngineHooks = struct {
    observed: ?*Observed = null,
    parts: ?PartSource = null,
    /// Whether a build may assemble its lowering from the last one's record (`lowering_assembly.zig`) and keep one for the next.
    assembly: bool = false,
    /// Whether this build did assemble its lowering from a record.
    assembled: bool = false,
    /// What an attempt to assemble from a record left behind when it was declined: the replay that follows uses it instead of keying again.
    handed: ?*const Handoff = null,
    /// Test only (`--sabotage-instance-keys`): key a generic instance by the records its type arguments reach through fields alone
    /// (`reachRecordsByFields`), the key every build used before an enum's case payloads and the other types a record holds joined it.
    field_reach_arguments: bool = false,
};

/// What a declined attempt to assemble a lowering leaves for the replay after it: the declaration digests of the program and, for each
/// checked function the attempt keyed, its key (null for the others), indexed like `Program.functions`. Both are pure functions of the
/// program, the source and the settings, which the replay shares with the attempt, so using them changes nothing the replay computes.
pub const Handoff = struct { declarations: DeclarationDigests, keyed: []const ?Keyed };

/// A durable store and counters for one build, with optional shared checked input.
/// What a build's lowering did with each function: lowered it, restored it, or found a stored lowering under its key that did
/// not fit the module (`fits`; it was lowered instead and logged in the serving store's `mismatches.log`: a wrong key, or a
/// declaration the IR verifier refuses).
/// `by_part` counts the functions keyed by the engine's checked-body part rather than by hashing their trees.
pub const Counts = struct { lowered: usize = 0, reused: usize = 0, unfit: usize = 0, by_part: usize = 0 };

/// Counters report actual fresh lowering and accepted artifact replay.
pub const Cache = struct {
    store: *const stage.Store,
    /// What this build's lowering did with each function.
    counts: Counts = .{},
    /// Refuse the build on an unfit record instead of lowering the function (the stage-served pass of `--verify-cache`),
    /// so a key that serves a record where it does not fit fails a check rather than passing as a miss.
    strict_fit: bool = false,
    demand: ?*demand.Context = null,
    lazy: ?*Deferred = null,
    catalog: CatalogUse = .{},
    /// What the engine gives and takes: where each function lowered or restored is noted, and the parts that key it.
    engine: EngineHooks = .{},

    /// Bind immutable durable storage; counters start empty for this build.
    pub fn init(store: *const stage.Store) Cache {
        return .{ .store = store };
    }
};

/// What a build's lowering did, function by function: the checked function, the key its artifact is stored under, the digest of
/// the artifact in canonical form (`canonicalDigest`) and whether it was restored. The engine's shadow (`lowering_shadow.zig`)
/// groups them by unit and compares them with the engine's answers.
pub const Observed = struct {
    arena: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,

    /// One function lowered or restored by this build.
    /// `made` names the functions the artifact defines besides the checked one (adapters, thunks, helpers): they belong to it.
    pub const Entry = struct { id: typed.FunctionId, key: stage.Digest, artifact: stage.Digest, reused: bool, sources: []const demand_sources.Proof = &.{}, made: []const []const u8 = &.{} };

    /// Note a function. The proofs are copied: the caller's are scratch.
    pub fn add(self: *Observed, entry: Entry) std.mem.Allocator.Error!void {
        var kept = entry;
        kept.sources = try clone(self.arena, []const demand_sources.Proof, entry.sources);
        kept.made = try clone(self.arena, []const []const u8, entry.made);
        try self.entries.append(self.arena, kept);
    }
};

/// Declaration hashing shared only by roots of the same immutable checked snapshot.
/// The snapshot's tables must remain unchanged until every borrower has finished;
/// a newly checked or copied catalog falls back to hashing its own declarations.
/// Source, locator, asset and physical discovery guards remain per-root inputs.
pub const Catalog = struct {
    program: typed.Program,
    prefix: fast_blake3.Blake3,

    /// Hash exactly the declaration prefix used by ordinary lowering sessions.
    pub fn prepare(program: typed.Program) Error!Catalog {
        // Catalog hashing ignores spans and never reads Core types or locations.
        var module: ir.Module = .{};
        var hash = TreeHash.init(program, .{ .module = &module }, null);
        try hashDeclarations(&hash);
        return .{ .program = program, .prefix = hash.hash };
    }

    /// Ownership checks depend on checked declarations and one typed body, but
    /// never source positions or physical Core discovery. Preserve the lowering
    /// tree encoding while bounding host-stack use independently of body depth.
    pub fn ownershipDigest(self: *const Catalog, a: std.mem.Allocator, function: typed.Function) Error!stage.Digest {
        var module: ir.Module = .{};
        var hash = TreeHash.init(self.program, .{ .module = &module }, null);
        hash.hash = self.prefix;
        try TreeWalk.run(a, &hash, typed.Function, function);
        return hash.finish();
    }

    /// Accept only the same immutable tables, never another snapshot's contents.
    pub fn matches(self: *const Catalog, program: typed.Program) bool {
        return sameTable(self.program.functions, program.functions) and
            sameTable(self.program.records, program.records) and
            sameTable(self.program.nodes, program.nodes) and
            sameTable(self.program.statements, program.statements) and
            sameTable(self.program.aliases, program.aliases) and self.program.main == program.main;
    }
};

fn sameTable(left: anytype, right: @TypeOf(left)) bool {
    return left.ptr == right.ptr and left.len == right.len;
}

fn hashDeclarations(hash: *TreeHash) Error!void {
    try hash.value(hash.program.records);
    try hash.value(hash.program.functions.len);
    for (hash.program.functions) |function| try hashFunctionDeclaration(hash, function);
}

/// One function's declaration as the catalog hashes it: identity, name, type
/// arguments, policy, signature, parameter labels and parameter types. Its body
/// is not part of it.
fn hashFunctionDeclaration(hash: *TreeHash, function: typed.Function) Error!void {
    try hash.value(function.id);
    try hashFunctionFields(hash, function);
}

/// A declaration without its identity: the reach key hashes a callee's index beside
/// this, and a function's own index is not part of its artifact.
fn hashFunctionFields(hash: *TreeHash, function: typed.Function) Error!void {
    try hash.value(normalizedName(function.name));
    try hash.value(function.type_arguments);
    try hash.value(function.policy);
    try hashSignature(hash, function.signature);
    try hash.value(function.scope.parameter_labels);
    // Which parameters the declaration spelled `own`: a caller lowers an argument for an owned parameter otherwise than for a
    // borrowed one, so a callee edited to take `own` must change the reach key of the callers whose text did not change.
    try hash.value(function.scope.own_parameters);
    for (function.scope.locals[0..function.signature.parameter_count]) |local| try hash.value(local.ty);
}

/// A function's signature as a declaration is hashed: every field but `inferred`. What the origin analysis concluded about the
/// function's own body is not part of what a caller, or the typed ownership prefix, depends on: no stage reads a callee's inferred
/// write facts (G-D5), and the function's own key still holds them, since its tree hash covers its whole signature. So an edit
/// that flips one fact relowers the function and not its callers.
fn hashSignature(hash: *TreeHash, signature: typed.FunctionSignature) Error!void {
    inline for (@typeInfo(typed.FunctionSignature).@"struct".field_names) |name| {
        if (comptime std.mem.eql(u8, name, "inferred")) continue;
        try hash.value(@field(signature, name));
    }
}

/// Declarations a checked body or a declaration names: functions by index, and
/// types (a nominal record is a type at or above `typed.Type.record_base`).
const Refs = struct {
    arena: std.mem.Allocator,
    functions: std.ArrayList(usize) = .empty,
    types: std.ArrayList(typed.Type) = .empty,
};

/// Collect every function index and type a declaration value holds, through its
/// fields. Bodies are never reached this way: a declaration references nodes only
/// by identity, and a body's own references are collected while it is hashed.
fn collectRefs(refs: *Refs, comptime T: type, value: T) Error!void {
    if (T == typed.FunctionId) return refs.functions.append(refs.arena, @backingInt(value));
    if (T == typed.Type) return refs.types.append(refs.arena, value);
    switch (@typeInfo(T)) {
        .int, .float, .bool, .void, .@"enum" => {},
        .optional => |optional| if (value) |present| try collectRefs(refs, optional.child, present),
        .pointer => |ptr| {
            if (ptr.size != .slice) @compileError("declaration references must be slices: " ++ @typeName(T));
            if (ptr.child == u8) return;
            for (value) |item| try collectRefs(refs, ptr.child, item);
        },
        .array => |array| for (value) |item| try collectRefs(refs, array.child, item),
        .@"struct" => |s| inline for (s.field_names) |name| try collectRefs(refs, @TypeOf(@field(value, name)), @field(value, name)),
        .@"union" => |u| {
            const tag = std.meta.activeTag(value);
            inline for (u.field_names) |name| if (tag == @field(std.meta.Tag(T), name)) try collectRefs(refs, @TypeOf(@field(value, name)), @field(value, name));
        },
        else => @compileError("declaration needs explicit reference collection: " ++ @typeName(T)),
    }
}

/// Declaration digests of one program, computed on first use and shared by
/// every lowering key of the build. Indexed like `Program.functions` and `records`.
pub const DeclarationDigests = struct {
    functions: []?stage.Digest,
    records: []?stage.Digest,
    names: Identities = .{},
    /// The digest of each record's name: a key holds a record type by it, never by the record's position.
    keys: record_names.RecordKeys = .{ .digests = &.{}, .by_digest = .empty },

    fn init(a: std.mem.Allocator, program: typed.Program, source: ?language.source.Source) std.mem.Allocator.Error!DeclarationDigests {
        const functions = try a.alloc(?stage.Digest, program.functions.len);
        errdefer a.free(functions);
        @memset(functions, null);
        const records = try a.alloc(?stage.Digest, program.records.len);
        @memset(records, null);
        return .{ .functions = functions, .records = records, .names = try Identities.init(a, program), .keys = try record_names.RecordKeys.init(a, program, source) };
    }
};

/// Reach order of records: by the digest of the record's name.
const RecordOrder = struct {
    keys: *const record_names.RecordKeys,

    fn less(self: RecordOrder, a: usize, b: usize) bool {
        return std.mem.lessThan(u8, &self.keys.digests[a], &self.keys.digests[b]);
    }
};

/// Reach order: uniquely named functions by name, then the others by index.
const ReachOrder = struct {
    names: *const Identities,
    program: typed.Program,

    fn less(self: ReachOrder, a: usize, b: usize) bool {
        const left = self.names.name(self.program, a);
        const right = self.names.name(self.program, b);
        if (left != null and right != null) return std.mem.lessThan(u8, left.?, right.?);
        if (left != null or right != null) return left != null;
        return a < b;
    }
};

fn wordFrame(hash: *fast_blake3.Blake3, word: u64) void {
    var little = std.mem.nativeToLittle(u64, word);
    hash.update(std.mem.asBytes(&little));
}

/// Stands in for a body's own function index, which is kept out of the body digest.
const own_sentinel: usize = std.math.maxInt(usize);

/// The key of a function's header record.
/// The key of the header record of the artifact stored under lowering key `lowered`.
pub fn headerKey(store: *const stage.Store, lowered: stage.Digest) stage.Digest {
    return store.key("lowered-header-source-v10", &.{&lowered});
}

/// Record whether the normalization of the body lowered under `lowered` declared a runtime helper, for later builds that defer that
/// body: the flag is written into the function's header, which the restore of the body reads anyway, so a build that defers it reads
/// nothing more to learn it. The header was held back when the body was lowered (`Session.remember`) because a stored record is
/// never replaced by one with other bytes: it is written once, here, with the flag.
pub fn rememberFinish(session: *Session, lowered: stage.Digest, helpers: bool) std.mem.Allocator.Error!void {
    const held = session.pending.fetchRemove(lowered) orelse return;
    var header = held.value;
    header.helpers = helpers;
    try session.cache.store.storeValue(headerKey(session.cache.store, lowered), Header, header);
}

/// What a lowering or a restore knows of a function beside its handle: the largest source position its body holds, the source
/// proofs it rests on, and whether finishing it declares no runtime helper (null when its header does not say).
pub const Known = struct { source_max: ?u32, proofs: []const demand_sources.Proof, plain: ?bool, effects: ?stage.Digest = null, defines: bool = false, fresh: ?Handle = null };

/// What a deferred body's header says besides where it is: whether finishing it declares no runtime helper (null when the header does
/// not say), the digest of its effects on the program's tables (`effectsDigest`) and whether its artifact defines functions of its own
/// (`Request.define`), and for a body built in place where its artifact would land, were it restored (`fresh`): what
/// `lowering_assembly.zig` keeps of a lowering so that a later build can assemble from it.
pub const Finish = struct { plain: ?bool = null, effects: ?stage.Digest = null, defines: bool = false, fresh: ?Handle = null };

/// Where a deferred body's artifact is stored and where it landed in the module: its key, the start of its declaration, the strings it
/// appended (where they were stored from, where they are now, and how many) and where its local types and callees are.
pub const Handle = struct { key: stage.Digest, start: usize, old_strings: usize, new_strings: usize, string_count: usize, places: Places };

/// The module's type for each of the artifact's local compound ids, and its function for each local callee id.
pub const Places = struct { types: []const ir.Type, functions: []const u32 };

/// Where a stored function lands in the live module: its declaration's start, the strings it appended (where they were and
/// where they are now), and where its local types and callees are.
const Placement = struct { start: usize, old: usize, new: usize, places: Places };

/// Compact discovery survives without decoding unchanged instruction arrays.
/// The owning pipeline updates module/source after moving and retaining them.
pub const Deferred = struct {
    arena: std.mem.Allocator,
    store: *const stage.Store,
    /// `catalog` is the whole declaration catalog of the session that prepared this
    /// table: test facts key on it, because their edge registry is a whole-module property.
    input: struct { module: *ir.Module = undefined, source: ?language.source.Source = null, catalog: stage.Digest = @splat(0) } = .{},
    tables: struct {
        handles: std.ArrayList(?Handle) = .empty,
        keys: std.ArrayList(?stage.Digest) = .empty,
        /// `keys` as lowering recorded them, before `prepare` mixed in the source proof (`demand_ir.Context.unmixed`).
        unmixed: std.ArrayList(?stage.Digest) = .empty,
        source_max: std.ArrayList(?u32) = .empty,
        sources: std.ArrayList([]const demand_sources.Proof) = .empty,
        loaded: std.ArrayList(bool) = .empty,
        /// What finishing each body is known to do (`Finish`).
        finish: std.ArrayList(Finish) = .empty,
    } = .{},
    context: demand_ir.Context = undefined,
    restored: usize = 0,
    force_eager: bool = false,

    fn extend(self: *Deferred, count: usize) std.mem.Allocator.Error!void {
        while (self.tables.sources.items.len < count) try self.tables.sources.append(self.arena, &.{});
        while (self.tables.keys.items.len < count) {
            try self.tables.keys.append(self.arena, null);
            try self.tables.unmixed.append(self.arena, null);
            try self.tables.source_max.append(self.arena, null);

            try self.tables.handles.append(self.arena, null);
            try self.tables.loaded.append(self.arena, true);
            try self.tables.finish.append(self.arena, .{});
        }
    }

    /// Whether a deferred body's local normalization is known to declare no runtime helper: its header said so when it was restored.
    /// Unknown counts as declaring one.
    pub fn finishesPlain(self: *const Deferred, index: usize) bool {
        if (index >= self.tables.finish.items.len) return false;
        return self.tables.finish.items[index].plain orelse false;
    }

    /// Restore and normalize one deferred body now, while lowering still
    /// owns `module`, so the helpers it declares take the eager positions.
    pub fn materializeAt(self: *Deferred, module: *ir.Module, source: ?language.source.Source, index: usize) demand_ir.Error!void {
        self.input.module = module;
        self.input.source = source;
        try self.restoreAt(@intCast(index));
        self.tables.loaded.items[index] = true;
    }

    /// Place the bodies of the functions that the artifact of the function at `index` defines (thunks, adapters, workers) in `module`,
    /// where a restore of that function would have placed them: those the module holds without a body, found by name. The artifact's
    /// header holds them, and the function's handle says where its strings and callees are. Each is normalized as the eager lowering
    /// normalizes every body (`lowering_finish`), because the artifact keeps it as the builder made it: a worker of `parallel.map`
    /// that reads a union element has its projections fused only then, and the optimizer's keys name the fused body.
    pub fn fillDefined(self: *Deferred, module: *ir.Module, source: ?language.source.Source, index: usize) demand_ir.Error!void {
        const handle = self.tables.handles.items[index] orelse return cache_miss.at(@src());
        var scratch = std.heap.ArenaAllocator.init(self.store.backing);
        defer scratch.deinit();
        const header = try self.store.loadValue(scratch.allocator(), headerKey(self.store, handle.key), Header) orelse return cache_miss.at(@src());
        const live: snapshot.Context = .{ .module = module, .source = source };
        const place: Placement = .{ .start = handle.start, .old = handle.old_strings, .new = handle.new_strings, .places = handle.places };
        if (header.wire.delta.requests.len != handle.places.functions.len) return cache_miss.at(@src());
        for (header.wire.delta.requests, handle.places.functions) |request, target| {
            if (request != .define) continue;
            if (target >= module.functions.items.len) return cache_miss.at(@src());
            const slot = &module.functions.items[target];
            if (slot.blocks.items.len != 0) continue;
            slot.* = restoreFunction(self.arena, live, place, request.define) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidSnapshot => return cache_miss.at(@src()),
            };
            try @import("lowering_finish.zig").function(self.arena, module, target);
        }
    }

    /// Note the function at `index`: the key its artifact is stored under, where the artifact landed (null for a body built in place,
    /// which is loaded) and what is known of it.
    pub fn record(self: *Deferred, index: usize, key: stage.Digest, handle: ?Handle, known: Known) std.mem.Allocator.Error!void {
        try self.extend(index + 1);
        self.tables.finish.items[index] = .{ .plain = known.plain, .effects = known.effects, .defines = known.defines, .fresh = known.fresh };
        self.tables.keys.items[index] = key;
        self.tables.unmixed.items[index] = key;
        self.tables.source_max.items[index] = known.source_max;
        self.tables.sources.items[index] = try clone(self.arena, []const demand_sources.Proof, known.proofs);
        self.tables.handles.items[index] = handle;
        self.tables.loaded.items[index] = handle == null;
    }

    /// Bind the exact source prefix governing every local site. Nonlocal replay retains conservative original-file
    /// authority. A key holds no layout of the module: where a body's types and callees sit is the optimizer manifest's
    /// own gate (`optimizer_shortcut.Candidates.load`), not part of what lowering the body was.
    pub fn prepare(self: *Deferred, module: *ir.Module, source: ?language.source.Source) std.mem.Allocator.Error!void {
        self.input.module = module;
        self.input.source = source;
        try self.extend(module.functions.items.len);
        var scratch = std.heap.ArenaAllocator.init(self.store.backing);
        defer scratch.deinit();
        const count = if (source) |s| @max(1, s.origins.len) else 1;
        const digests = try scratch.allocator().alloc(stage.Digest, count);
        const ready = try scratch.allocator().alloc(bool, count);
        @memset(ready, false);
        @memset(digests, @splat(0));
        for (self.tables.keys.items, module.functions.items, 0..) |*key, function, index| {
            if (source) |current| if (self.tables.source_max.items[index]) |maximum| {
                const proof = sourceProof(current, function.span, maximum) catch {
                    key.* = null;
                    self.tables.unmixed.items[index] = null;
                    continue;
                };
                if (key.*) |raw| key.* = self.store.key("demand-raw-source-v3", &.{ &raw, &proof });
                continue;
            };
            const raw = key.* orelse continue;
            var origin: usize = 0;
            if (source) |s| if (s.origins.len != 0) {
                const at = s.originalSpan(.{ .start = function.span, .end = function.span }) catch {
                    key.* = null;
                    self.tables.unmixed.items[index] = null;
                    continue;
                };
                origin = at.input;
            };
            if (!ready[origin]) if (source) |s| {
                const original = if (s.origins.len == 0) s else s.origins[origin].original;
                fast_blake3.hash(original.bytes, &digests[origin]);
                ready[origin] = true;
            };
            key.* = self.store.key("demand-raw-v2", &.{ &raw, &digests[origin] });
        }
        // External debug authority survives independently of the owning file.
        for (self.tables.sources.items, self.tables.keys.items) |proofs, *key| {
            if (proofs.len == 0 or key.* == null) continue;
            var writer = codec.Writer.init(scratch.allocator());
            try writer.write([]const demand_sources.Proof, proofs);
            key.* = self.store.key("demand-raw-external-v2", &.{ &key.*.?, writer.bytes.items });
        }
        try self.needHandles(scratch.allocator());
        self.context = .{ .pointer = self, .ensure_fn = ensure, .keys = self.tables.keys.items, .unmixed = self.tables.unmixed.items, .loaded = self.tables.loaded.items, .force_eager = self.force_eager };
    }

    /// Say that this build needs the full artifact of every function it restored from a header alone: it loaded the header, not
    /// the artifact, and compaction keeps only the records a recent build needed, so the artifact would be gone by the time a
    /// later build materializes the body.
    fn needHandles(self: *const Deferred, a: std.mem.Allocator) std.mem.Allocator.Error!void {
        var keys: std.ArrayList(stage.Digest) = .empty;
        for (self.tables.handles.items) |maybe| if (maybe) |handle| try keys.append(a, handle.key);
        self.store.need(keys.items);
    }

    fn ensure(pointer: *anyopaque, index: u32) demand_ir.Error!void {
        const self: *Deferred = @ptrCast(@alignCast(pointer));
        return self.restoreAt(index);
    }

    fn restoreAt(self: *Deferred, index: u32) demand_ir.Error!void {
        const handle = self.tables.handles.items[index] orelse return cache_miss.at(@src());
        var scratch = std.heap.ArenaAllocator.init(self.store.backing);
        defer scratch.deinit();
        const a = scratch.allocator();
        const wire = try self.store.loadValue(a, handle.key, Wire) orelse return cache_miss.at(@src());
        var sources: demand_sources.Cache = .{ .arena = a };
        if (self.input.source) |source| sources.bind(source);
        if (!sameSourceProofs(wire.sources, self.tables.sources.items[index])) return cache_miss.at(@src());
        if (!try validWireSources(&sources, wire)) return cache_miss.at(@src());
        var prefix = self.input.module.*;
        if (handle.new_strings > prefix.strings.items.len or handle.string_count > prefix.strings.items.len - handle.new_strings) return cache_miss.at(@src());
        prefix.strings.items = prefix.strings.items[0 .. handle.new_strings + handle.string_count];
        const source: snapshot.Context = .{ .module = &prefix, .source = self.input.source };
        var candidate = restoreFunction(self.arena, source, .{ .start = handle.start, .old = handle.old_strings, .new = handle.new_strings, .places = handle.places }, wire.function) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return cache_miss.at(@src()),
        };
        const declared = self.input.module.functions.items[index];
        if (!std.mem.eql(u8, candidate.name, declared.name)) return cache_miss.at(@src());
        candidate.module = declared.module;
        if (!sameSignature(candidate.signature, declared.signature)) return cache_miss.at(@src());
        if (!try safeFunction(a, self.input.module, candidate)) return cache_miss.at(@src());
        self.input.module.functions.items[index] = candidate;
        // Whether finishing declared a helper was recorded in the header when the body was first lowered, so nothing is learned here.
        try @import("lowering_finish.zig").function(self.arena, self.input.module, index);
        self.restored += 1;
    }
};
/// What a stored header says about a function without its artifact: the digest of its effects on the program's tables, whether
/// finishing its body declares a runtime helper (null when the header does not say), the largest source position in it, the files its
/// positions are in, and where its strings began in the module it was lowered in and how many there are.
pub const Stored = struct { effects: stage.Digest, helpers: ?bool, source_max: ?u32, proofs: []const demand_sources.Proof, string_start: usize, string_count: usize };

/// The header stored under lowering key `key`, decoded into `a`; null when there is none.
pub fn storedHeader(store: *const stage.Store, a: std.mem.Allocator, key: stage.Digest) stage.Error!?Stored {
    const header = try store.loadValue(a, headerKey(store, key), Header) orelse return null;
    return .{
        .effects = header.effects,
        .helpers = header.helpers,
        .source_max = header.source_max,
        .proofs = header.wire.sources,
        .string_start = header.wire.delta.string_start,
        .string_count = header.wire.delta.strings.len,
    };
}

/// Table lengths before lowering one function.
pub const Before = struct {
    functions: usize,
    compounds: usize,
    strings: usize,

    /// No scans of a growing module are needed to capture its discovery delta.
    pub fn init(mb: Context) Before {
        return .{ .functions = mb.module.functions.items.len, .compounds = mb.module.compounds.items.len, .strings = mb.module.strings.items.len };
    }
};

/// Digest of the declarations `checked` reaches: its own, the functions its body
/// names, and the functions and records their declarations name, followed through
/// declarations only. Null when a reference is out of range; the caller then keys
/// on the whole catalog.
fn reachDigestOf(arena: std.mem.Allocator, program: typed.Program, declarations: *DeclarationDigests, checked: typed.Function, refs: *Refs) Error!?stage.Digest {
    var functions: std.AutoHashMapUnmanaged(usize, void) = .empty;
    var records: std.AutoHashMapUnmanaged(usize, void) = .empty;
    var pending: Refs = .{ .arena = arena };
    try pending.functions.append(arena, @backingInt(checked.id));
    try pending.functions.appendSlice(arena, refs.functions.items);
    try pending.types.appendSlice(arena, refs.types.items);
    while (true) {
        if (pending.functions.pop()) |index| {
            if (index == own_sentinel) continue;
            if ((try functions.getOrPut(arena, index)).found_existing) continue;
            if (index >= program.functions.len) return null;
            const function = program.functions[index];
            var found: Refs = .{ .arena = arena };
            try collectRefs(&found, @TypeOf(function.type_arguments), function.type_arguments);
            try collectRefs(&found, typed.FunctionSignature, function.signature);
            try collectRefs(&found, typed.FunctionPolicy, function.policy);
            for (function.scope.locals[0..function.signature.parameter_count]) |local| try found.types.append(arena, local.ty);
            try pending.functions.appendSlice(arena, found.functions.items);
            try pending.types.appendSlice(arena, found.types.items);
            continue;
        }
        if (pending.types.pop()) |ty| {
            if (!ty.isAggregate()) continue;
            const index = ty.recordIndex();
            if (index >= program.records.len) return null;
            if ((try records.getOrPut(arena, index)).found_existing) continue;
            var found: Refs = .{ .arena = arena };
            try collectRefs(&found, typed.Record, program.records[index]);
            try pending.functions.appendSlice(arena, found.functions.items);
            try pending.types.appendSlice(arena, found.types.items);
            continue;
        }
        break;
    }
    const function_list = try arena.alloc(usize, functions.count());
    var function_keys = functions.keyIterator();
    for (function_list) |*slot| slot.* = function_keys.next().?.*;
    // Named functions sort by name, so their order is independent of position too.
    std.mem.sort(usize, function_list, ReachOrder{ .names = &declarations.names, .program = program }, ReachOrder.less);
    const record_list = try arena.alloc(usize, records.count());
    var record_keys = records.keyIterator();
    for (record_list) |*slot| slot.* = record_keys.next().?.*;
    // Records sort by the digest of their names, so their order is independent of position as well.
    std.mem.sort(usize, record_list, RecordOrder{ .keys = &declarations.keys }, RecordOrder.less);
    var hash = fast_blake3.Blake3.init(.{});
    // A callee with a unique name is named by it, and replay rebinds it by that name; any other
    // callee is named by its index in the artifact, so that index is part of the key. A function's
    // own index is not.
    const own = @backingInt(checked.id);
    for (function_list) |index| {
        const declared = try functionDigestOf(declarations, program, index);
        if (index == own) {
            wordFrame(&hash, 2);
        } else if (declarations.names.name(program, index)) |value| {
            wordFrame(&hash, 3);
            frame(&hash, value);
        } else {
            wordFrame(&hash, 0);
            wordFrame(&hash, index);
        }
        hash.update(&declared);
    }
    for (record_list) |index| {
        const declared = try recordDigestOf(declarations, program, index);
        wordFrame(&hash, 1);
        hash.update(&declarations.keys.digests[index]);
        hash.update(&declared);
    }
    var digest: stage.Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// The records type `ty` is made of, each once: through every type a record's digest hashes (`recordDigestOf` hashes the whole
/// `typed.Record`, and `collectRefs` follows the same value), so the fields, the payloads of an enum's or union's cases, the
/// elements and keys of arrays, tables, dictionaries and sets, a domain's backing type, a buffer's element and a callback's slots
/// are all reached. A record is hashed beside its neighbours by the digest of its name alone, so a record this walk misses is
/// a definition the key does not cover.
pub fn reachRecordsOf(arena: std.mem.Allocator, program: typed.Program, ty: typed.Type, seen: *std.AutoHashMapUnmanaged(usize, void), out: *std.ArrayList(usize)) Error!void {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return;
    const index = ty.recordIndex();
    if ((try seen.getOrPut(arena, index)).found_existing) return;
    try out.append(arena, index);
    var held: Refs = .{ .arena = arena };
    try collectRefs(&held, typed.Record, program.records[index]);
    for (held.types.items) |inner| try reachRecordsOf(arena, program, inner, seen, out);
}

/// The records type `ty` is made of through the fields of its records alone, each once: the reach that keyed generic instances until
/// an enum's case payloads and the other types a record holds joined it (`reachRecordsOf`). Only the test-only sabotage uses it.
fn reachRecordsByFields(arena: std.mem.Allocator, program: typed.Program, ty: typed.Type, seen: *std.AutoHashMapUnmanaged(usize, void), out: *std.ArrayList(usize)) Error!void {
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return;
    const index = ty.recordIndex();
    if ((try seen.getOrPut(arena, index)).found_existing) return;
    try out.append(arena, index);
    for (program.records[index].fields) |field| try reachRecordsByFields(arena, program, field.ty, seen, out);
}

fn functionDigestOf(declarations: *DeclarationDigests, program: typed.Program, index: usize) Error!stage.Digest {
    if (declarations.functions[index]) |known| return known;
    var module: ir.Module = .{};
    var h = TreeHash.init(program, .{ .module = &module }, null);
    h.identities = &declarations.names;
    h.record_keys = &declarations.keys;
    try hashFunctionFields(&h, program.functions[index]);
    const digest = h.finish();
    declarations.functions[index] = digest;
    return digest;
}

fn recordDigestOf(declarations: *DeclarationDigests, program: typed.Program, index: usize) Error!stage.Digest {
    if (declarations.records[index]) |known| return known;
    var module: ir.Module = .{};
    var h = TreeHash.init(program, .{ .module = &module }, null);
    h.identities = &declarations.names;
    h.record_keys = &declarations.keys;
    // A record's own position is not part of what it holds.
    var record = program.records[index];
    record.id = @fromBackingInt(own_sentinel);
    try h.value(record);
    const digest = h.finish();
    declarations.records[index] = digest;
    return digest;
}

/// The declarations a declaration names, as a graph: node `i` below the function count is function `i`, node
/// `functions + r` is record `r`, and a node's edges are the functions and aggregate types its declaration holds (a body is
/// never followed, as in `reachDigestOf`). The closure digest of a node is the digest of its strongly connected component
/// (Tarjan, with an explicit stack): the component's members, each by its stable name or index and its declared digest, and the
/// closure digests of the components it names. Each component is hashed once for the whole program, so what a function's
/// reach costs is the number of declarations it names directly and not the size of everything they name in turn.
const ClosureDigests = struct {
    arena: std.mem.Allocator,
    edges: []Edges,
    walk: Walk,
    /// The digest of each component found so far, by component id; null when a reference in its closure is out of range.
    components: std.ArrayList(?stage.Digest) = .empty,
    scratch: Scratch,

    const Edges = struct { targets: []const u32 = &.{}, known: bool = false, bad: bool = false };
    const Frame = struct { node: u32, cursor: u32 };
    const Walk = struct {
        order: []u32,
        low: []u32,
        component: []u32,
        stack: std.ArrayList(u32) = .empty,
        frames: std.ArrayList(Frame) = .empty,
        next: u32 = 1,
    };
    /// Kept between questions: the entries and closures of the component being digested, and a stamp per node and per component,
    /// so that a function's reach names each closure once however often its body names a declaration.
    const Scratch = struct {
        leaves: std.ArrayList(stage.Digest) = .empty,
        named: std.ArrayList(stage.Digest) = .empty,
        node_stamps: []u32,
        component_stamps: []u32,
        stamp: u32 = 0,
    };
    const unvisited: u32 = 0;
    const unassigned: u32 = std.math.maxInt(u32);

    fn init(a: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error!ClosureDigests {
        const count = program.functions.len + program.records.len;
        const order = try a.alloc(u32, count);
        errdefer a.free(order);
        @memset(order, unvisited);
        const low = try a.alloc(u32, count);
        errdefer a.free(low);
        const component = try a.alloc(u32, count);
        errdefer a.free(component);
        @memset(component, unassigned);
        const edges = try a.alloc(Edges, count);
        errdefer a.free(edges);
        @memset(edges, .{});
        const node_stamps = try a.alloc(u32, count);
        errdefer a.free(node_stamps);
        @memset(node_stamps, 0);
        const component_stamps = try a.alloc(u32, count);
        @memset(component_stamps, 0);
        return .{ .arena = a, .edges = edges, .walk = .{ .order = order, .low = low, .component = component }, .scratch = .{ .node_stamps = node_stamps, .component_stamps = component_stamps } };
    }

    /// Free the tables and the lists; the edge lists of the nodes belong to the arena allocator and go with it.
    fn deinit(self: *ClosureDigests) void {
        const a = self.arena;
        a.free(self.walk.order);
        a.free(self.walk.low);
        a.free(self.walk.component);
        a.free(self.edges);
        self.walk.stack.deinit(a);
        self.walk.frames.deinit(a);
        self.components.deinit(a);
        self.scratch.leaves.deinit(a);
        self.scratch.named.deinit(a);
        a.free(self.scratch.node_stamps);
        a.free(self.scratch.component_stamps);
    }

    /// The edges of `node`, computed on first use together with its declared digest: the declaration is hashed once, and the
    /// functions and types the hash passes over are its references. A reference out of range marks the node bad.
    fn load(self: *ClosureDigests, scratch: std.mem.Allocator, program: typed.Program, declarations: *DeclarationDigests, node: u32) Error!void {
        const slot = &self.edges[node];
        if (slot.known) return;
        var refs: Refs = .{ .arena = scratch };
        const functions = program.functions.len;
        var module: ir.Module = .{};
        var h = TreeHash.init(program, .{ .module = &module }, null);
        h.identities = &declarations.names;
        h.record_keys = &declarations.keys;
        h.refs = &refs;
        if (node < functions) {
            try hashFunctionFields(&h, program.functions[node]);
            declarations.functions[node] = h.finish();
        } else {
            // A record's own position is not part of what it holds.
            var record = program.records[node - functions];
            record.id = @fromBackingInt(own_sentinel);
            try h.value(record);
            declarations.records[node - functions] = h.finish();
        }
        var targets: std.ArrayList(u32) = .empty;
        defer targets.deinit(scratch);
        for (refs.functions.items) |index| {
            if (index == own_sentinel) continue;
            if (index >= functions) slot.bad = true else try targets.append(scratch, @intCast(index));
        }
        for (refs.types.items) |ty| {
            if (!ty.isAggregate()) continue;
            // The stand-in for a record's own position (above) is not a reference.
            if (@backingInt(ty) == own_sentinel) continue;
            if (ty.recordIndex() >= program.records.len) slot.bad = true else try targets.append(scratch, @intCast(functions + ty.recordIndex()));
        }
        std.mem.sort(u32, targets.items, {}, std.sort.asc(u32));
        slot.targets = try self.arena.dupe(u32, targets.items[0..uniqueCount(u32, targets.items)]);
        slot.known = true;
    }

    /// The component of `node`, or null when a reference in the closure it heads is out of range.
    fn componentOf(self: *ClosureDigests, scratch: std.mem.Allocator, program: typed.Program, declarations: *DeclarationDigests, node: u32) Error!?u32 {
        if (self.walk.component[node] == unassigned) try self.visit(scratch, program, declarations, node);
        const id = self.walk.component[node];
        return if (self.components.items[id] == null) null else id;
    }

    fn enter(self: *ClosureDigests, scratch: std.mem.Allocator, program: typed.Program, declarations: *DeclarationDigests, node: u32) Error!void {
        const walk = &self.walk;
        walk.order[node] = walk.next;
        walk.low[node] = walk.next;
        walk.next += 1;
        try walk.stack.append(self.arena, node);
        try walk.frames.append(self.arena, .{ .node = node, .cursor = 0 });
        try self.load(scratch, program, declarations, node);
    }

    fn visit(self: *ClosureDigests, scratch: std.mem.Allocator, program: typed.Program, declarations: *DeclarationDigests, root: u32) Error!void {
        const walk = &self.walk;
        errdefer self.abandon();
        try self.enter(scratch, program, declarations, root);
        while (walk.frames.items.len != 0) {
            const top = &walk.frames.items[walk.frames.items.len - 1];
            const node = top.node;
            const targets = self.edges[node].targets;
            if (top.cursor < targets.len) {
                const next = targets[top.cursor];
                top.cursor += 1;
                if (walk.order[next] == unvisited) {
                    try self.enter(scratch, program, declarations, next);
                } else if (walk.component[next] == unassigned) {
                    walk.low[node] = @min(walk.low[node], walk.order[next]);
                }
                continue;
            }
            _ = walk.frames.pop();
            if (walk.low[node] == walk.order[node]) try self.finish(program, declarations, node);
            if (walk.frames.items.len != 0) {
                const parent = walk.frames.items[walk.frames.items.len - 1].node;
                walk.low[parent] = @min(walk.low[parent], walk.low[node]);
            }
        }
    }

    /// A walk that failed leaves its unfinished nodes unvisited, so a later question starts clean; finished components stay.
    fn abandon(self: *ClosureDigests) void {
        for (self.walk.stack.items) |node| self.walk.order[node] = unvisited;
        self.walk.stack.clearRetainingCapacity();
        self.walk.frames.clearRetainingCapacity();
    }

    /// `root` heads a component: take its members off the stack and digest the component.
    fn finish(self: *ClosureDigests, program: typed.Program, declarations: *DeclarationDigests, root: u32) Error!void {
        const walk = &self.walk;
        const id: u32 = @intCast(self.components.items.len);
        try self.components.append(self.arena, null);
        var first = walk.stack.items.len;
        while (true) {
            first -= 1;
            walk.component[walk.stack.items[first]] = id;
            if (walk.stack.items[first] == root) break;
        }
        const members = walk.stack.items[first..];
        defer walk.stack.items.len = first;
        var bad = false;
        self.scratch.leaves.clearRetainingCapacity();
        self.scratch.named.clearRetainingCapacity();
        for (members) |member| {
            const slot = self.edges[member];
            bad = bad or slot.bad;
            try self.scratch.leaves.append(self.arena, try leafDigest(program, declarations, member));
            for (slot.targets) |target| {
                if (walk.component[target] == id) continue;
                try self.scratch.named.append(self.arena, self.components.items[walk.component[target]] orelse {
                    bad = true;
                    continue;
                });
            }
        }
        if (bad) return;
        std.mem.sort(stage.Digest, self.scratch.leaves.items, {}, closureDigestLess);
        std.mem.sort(stage.Digest, self.scratch.named.items, {}, closureDigestLess);
        const kept = self.scratch.named.items[0..uniqueCount(stage.Digest, self.scratch.named.items)];
        var hash = fast_blake3.Blake3.init(.{});
        frame(&hash, "ownership-component-v1");
        wordFrame(&hash, self.scratch.leaves.items.len);
        for (self.scratch.leaves.items) |leaf| hash.update(&leaf);
        wordFrame(&hash, kept.len);
        for (kept) |digest| hash.update(&digest);
        var digest: stage.Digest = undefined;
        hash.final(&digest);
        self.components.items[id] = digest;
    }

    /// Add the closure digest of `node` to `found` unless this reach has named it already. Null when a reference in it is out of range.
    fn name(self: *ClosureDigests, scratch: std.mem.Allocator, program: typed.Program, declarations: *DeclarationDigests, found: *std.ArrayList(stage.Digest), node: u32) Error!?void {
        const marks = &self.scratch;
        if (marks.node_stamps[node] == marks.stamp) return;
        marks.node_stamps[node] = marks.stamp;
        const id = (try self.componentOf(scratch, program, declarations, node)) orelse return null;
        if (marks.component_stamps[id] == marks.stamp) return;
        marks.component_stamps[id] = marks.stamp;
        try found.append(scratch, self.components.items[id].?);
    }

    /// The reach of the function `checked`: its own declaration, the closures its declaration names, and the closures of the
    /// functions and types its body names (`refs`). Null when a reference in any of them is out of range.
    fn reach(self: *ClosureDigests, scratch: std.mem.Allocator, program: typed.Program, declarations: *DeclarationDigests, checked: typed.Function, refs: *const Refs) Error!?stage.Digest {
        const own = @backingInt(checked.id);
        if (own >= program.functions.len) return null;
        try self.load(scratch, program, declarations, @intCast(own));
        if (self.edges[own].bad) return null;
        const marks = &self.scratch;
        marks.stamp +%= 1;
        if (marks.stamp == 0) {
            @memset(marks.node_stamps, 0);
            @memset(marks.component_stamps, 0);
            marks.stamp = 1;
        }
        var found: std.ArrayList(stage.Digest) = .empty;
        for (self.edges[own].targets) |target| try self.name(scratch, program, declarations, &found, target) orelse return null;
        for (refs.functions.items) |index| {
            if (index == own_sentinel or index == own) continue;
            if (index >= program.functions.len) return null;
            try self.name(scratch, program, declarations, &found, @intCast(index)) orelse return null;
        }
        for (refs.types.items) |ty| {
            if (!ty.isAggregate()) continue;
            if (ty.recordIndex() >= program.records.len) return null;
            try self.name(scratch, program, declarations, &found, @intCast(program.functions.len + ty.recordIndex())) orelse return null;
        }
        std.mem.sort(stage.Digest, found.items, {}, closureDigestLess);
        const kept = found.items[0..uniqueCount(stage.Digest, found.items)];
        var hash = fast_blake3.Blake3.init(.{});
        frame(&hash, "ownership-reach-closure-v1");
        // The function's own entry carries neither its name nor its index, as in the body key: the reach covers the function itself.
        wordFrame(&hash, 2);
        const declared = try functionDigestOf(declarations, program, own);
        hash.update(&declared);
        wordFrame(&hash, kept.len);
        for (kept) |digest| hash.update(&digest);
        var digest: stage.Digest = undefined;
        hash.final(&digest);
        return digest;
    }
};

/// A node's own entry in its component: the stable name of a function with one, else its index; a record's name digest; and the
/// declared digest.
fn leafDigest(program: typed.Program, declarations: *DeclarationDigests, node: u32) Error!stage.Digest {
    var hash = fast_blake3.Blake3.init(.{});
    const functions = program.functions.len;
    if (node < functions) {
        if (declarations.names.name(program, node)) |value| {
            wordFrame(&hash, 3);
            frame(&hash, value);
        } else {
            wordFrame(&hash, 0);
            wordFrame(&hash, node);
        }
        const declared = try functionDigestOf(declarations, program, node);
        hash.update(&declared);
    } else {
        wordFrame(&hash, 1);
        hash.update(&declarations.keys.digests[node - functions]);
        const declared = try recordDigestOf(declarations, program, node - functions);
        hash.update(&declared);
    }
    var digest: stage.Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn closureDigestLess(_: void, left: stage.Digest, right: stage.Digest) bool {
    return std.mem.lessThan(u8, &left, &right);
}

/// How many leading items of the sorted `items` remain when neighbours that are equal are dropped, compacting them in place.
fn uniqueCount(comptime T: type, items: []T) usize {
    if (items.len == 0) return 0;
    var kept: usize = 1;
    for (items[1..]) |item| {
        if (std.meta.eql(item, items[kept - 1])) continue;
        items[kept] = item;
        kept += 1;
    }
    return kept;
}

/// What a typed function's ownership proof depends on, without the whole-program prefix of `Catalog.ownershipDigest`: its
/// own body, and the declarations that body reaches, as lowering's reach key hashes them. A function added, removed or edited
/// elsewhere, and a record nothing it names reaches, leave the digest alone. The ownership check reads a body, the declared
/// signatures of its callees and the records its types name, and a table that is a function of each record's field closure
/// (`single_owner.ownedTypes`), so this reach is what a verdict depends on. One reach serves the
/// functions of one program; it keeps the declaration digests and the closure digests it has computed.
pub const OwnershipReach = struct {
    program: typed.Program,
    declarations: DeclarationDigests,
    closures: ClosureDigests,

    /// A reach over `program`, whose caches are allocated in `a`.
    pub fn init(a: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error!OwnershipReach {
        // No source here: records are named without their module, so two same-named records take ordinals by position,
        // which can only make a proof miss, never serve a stale one.
        var closures = try ClosureDigests.init(a, program);
        errdefer closures.deinit();
        return .{ .program = program, .declarations = try DeclarationDigests.init(a, program, null), .closures = closures };
    }

    /// The digest of `function`'s body and reach, or null when a reference of the body is out of range (the caller then
    /// treats the function as having no proof to reuse). `a` is scratch.
    pub fn digest(self: *OwnershipReach, a: std.mem.Allocator, function: typed.Function) Error!?stage.Digest {
        var refs: Refs = .{ .arena = a };
        var module: ir.Module = .{};
        var hash = TreeHash.init(self.program, .{ .module = &module }, null);
        hash.refs = &refs;
        hash.identities = &self.declarations.names;
        hash.record_keys = &self.declarations.keys;
        // As lowering's body key: the function's own index is not part of its body; the reach covers the function itself.
        var anonymous = function;
        anonymous.id = @fromBackingInt(own_sentinel);
        try TreeWalk.run(a, &hash, typed.Function, anonymous);
        const body = hash.finish();
        const reach = (try self.closures.reach(a, self.program, &self.declarations, function, &refs)) orelse return null;
        var out = fast_blake3.Blake3.init(.{});
        frame(&out, "ownership-reach-v2");
        out.update(&body);
        out.update(&reach);
        // The entry point's index moves whenever an earlier declaration is added, so only the flag that this function is it counts.
        out.update(&.{@intFromBool(function.id == self.program.main)});
        var digest_bytes: stage.Digest = undefined;
        out.final(&digest_bytes);
        return digest_bytes;
    }
};

fn recordTypeAt(index: usize) typed.Type {
    return @fromBackingInt(typed.Type.record_base + index);
}

/// `count` mentions of `ty`, as a body that names a record in every node leaves in its references.
fn mentions(refs: *Refs, ty: typed.Type, count: usize) !void {
    for (0..count) |_| try refs.types.append(refs.arena, ty);
}

test "G1c a reach names each closure once however often the body names a declaration, and a record the body does not name is not in it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span: language.source.Span = .{ .start = 0, .end = 1 };
    const records = try a.dupe(typed.Record, &.{
        .{ .id = recordTypeAt(0), .name = "A", .declaration = span, .fields = try a.dupe(typed.Field, &.{.{ .name = "next", .declaration = span, .ty = recordTypeAt(1) }}) },
        .{ .id = recordTypeAt(1), .name = "B", .declaration = span, .fields = try a.dupe(typed.Field, &.{.{ .name = "back", .declaration = span, .ty = recordTypeAt(0) }}) },
        .{ .id = recordTypeAt(2), .name = "C", .declaration = span, .fields = try a.dupe(typed.Field, &.{.{ .name = "y", .declaration = span, .ty = .i64 }}) },
    });
    const functions = try a.dupe(typed.Function, &.{.{ .scope = .{ .body_complete = true, .body = @fromBackingInt(0) }, .id = @fromBackingInt(0), .name = "use", .declaration = span }});
    const program: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = functions, .main = @fromBackingInt(0), .records = records };
    var declarations = try DeclarationDigests.init(a, program, null);
    var closures = try ClosureDigests.init(a, program);
    var many: Refs = .{ .arena = a };
    try mentions(&many, recordTypeAt(0), 500);
    try mentions(&many, recordTypeAt(1), 300);
    var once: Refs = .{ .arena = a };
    try mentions(&once, recordTypeAt(0), 1);
    var with_c: Refs = .{ .arena = a };
    try mentions(&with_c, recordTypeAt(0), 7);
    try mentions(&with_c, recordTypeAt(2), 1);
    const named_many = (try closures.reach(a, program, &declarations, functions[0], &many)).?;
    const named_once = (try closures.reach(a, program, &declarations, functions[0], &once)).?;
    // A and B name each other: they are one component, so naming either, once or a thousand times, is naming that closure.
    try std.testing.expectEqual(named_once, named_many);
    try std.testing.expect(!std.mem.eql(u8, &named_once, &(try closures.reach(a, program, &declarations, functions[0], &with_c)).?));
    // The question is answered from the memo: the same refs in a fresh walk give the same digest.
    var fresh = try ClosureDigests.init(a, program);
    var fresh_declarations = try DeclarationDigests.init(a, program, null);
    try std.testing.expectEqual(named_many, (try fresh.reach(a, program, &fresh_declarations, functions[0], &many)).?);
}

test "COPY-C1c a callee's declared digest tells a borrowed parameter from an owned one, so its callers' keys change" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span: language.source.Span = .{ .start = 0, .end = 1 };
    const locals = try a.dupe(typed.Local, &.{.{ .name = "name", .declaration = span, .ty = .i64, .mutable = false }});
    const scope: typed.FunctionScope = .{ .body_complete = true, .body = @fromBackingInt(0), .locals = locals, .own_parameters = &.{false} };
    const borrowed: typed.Function = .{ .signature = .{ .parameter_count = 1 }, .scope = scope, .id = @fromBackingInt(0), .name = "header", .declaration = span };
    var owned = borrowed;
    owned.scope.own_parameters = &.{true};
    const before: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{borrowed}, .main = @fromBackingInt(0) };
    const after: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{owned}, .main = @fromBackingInt(0) };
    var borrowing = try DeclarationDigests.init(a, before, null);
    var owning = try DeclarationDigests.init(a, after, null);
    try std.testing.expect(!std.mem.eql(u8, &(try functionDigestOf(&borrowing, before, 0)), &(try functionDigestOf(&owning, after, 0))));
}

/// Rolling declaration guard avoids quadratic catalog hashing on large projects.
pub const Session = struct {
    cache: *Cache,
    /// Whole declaration catalog: the key part for a body whose references are unknown. Null in a session made by `prepareKeys`, which keys by
    /// the engine's checked-body parts alone: a function the engine holds no part for cannot be keyed there (`key` fails).
    catalog: ?stage.Digest,
    /// Source identity and type aliases: part of every key.
    base: stage.Digest,
    assets: stage.Digest,
    sources: demand_sources.Cache,
    declarations: DeclarationDigests,
    /// The headers of the bodies this build lowered, by lowering key, held until the finish of each body is known (`rememberFinish`).
    pending: std.AutoHashMapUnmanaged(stage.Digest, Header) = .empty,

    /// Hash the complete checked declaration/type graph once, excluding bodies
    /// and absolute source positions. Numeric IDs are accepted only under this
    /// exact ordered catalog, including generic instances and inferred summaries.
    pub fn prepare(cache: *Cache, mb: Context) Error!Session {
        return prepareWith(cache, mb, false);
    }

    /// A session that keys functions by the engine's checked-body parts alone (`cache.engine.parts`): it hashes no declaration catalog, so
    /// it costs what the assets, the aliases and the identities of the functions cost, and `key` fails for a function without a part.
    pub fn prepareKeys(cache: *Cache, mb: Context) Error!Session {
        return prepareWith(cache, mb, true);
    }

    fn prepareWith(cache: *Cache, mb: Context, parts_only: bool) Error!Session {
        var h = TreeHash.init(mb.input.program, .{ .module = mb.module, .source = mb.input.source }, null);
        cache.catalog.reused = false;
        if (!parts_only) {
            if (cache.catalog.known) |catalog| if (catalog.matches(mb.input.program)) {
                h.hash = catalog.prefix;
                cache.catalog.reused = true;
            };
            if (!cache.catalog.reused) try hashDeclarations(&h);
        }
        if (mb.input.source) |source| {
            try h.value(source.keyPath());
            for (source.origins) |origin| try h.value(origin.original.keyPath());
        }
        var assets = fast_blake3.Blake3.init(.{});
        if (mb.input.source) |source| for (source.embeds) |embed| {
            frame(&assets, @tagName(embed.status));
            frame(&assets, &embed.digest);
            frame(&assets, embed.contents);
        };
        const declarations = if (cache.engine.handed) |handed| handed.declarations else try DeclarationDigests.init(mb.arena, mb.input.program, mb.input.source);
        var base = TreeHash.init(mb.input.program, .{ .module = mb.module, .source = mb.input.source }, null);
        base.record_keys = &declarations.keys;
        try hashAliases(mb.arena, &base);
        // The program's source is named by its own key path alone: a module it merges is named where a position in it is
        // hashed (a position holds its file's key path), so adding, removing or reordering modules moves no key.
        if (mb.input.source) |source| try base.value(source.keyPath());
        var result: Session = .{ .cache = cache, .catalog = if (parts_only) null else h.finish(), .base = base.finish(), .assets = undefined, .sources = .{ .arena = mb.arena }, .declarations = declarations };
        if (mb.input.source) |source| result.sources.bind(source);
        if (result.catalog) |whole| if (cache.lazy) |lazy| {
            lazy.input.catalog = whole;
        };
        assets.final(&result.assets);
        return result;
    }

    /// Hash the type aliases as a set: each by its name and target, in the order of their digests, so that the modules that
    /// declare them may come in any order.
    fn hashAliases(a: std.mem.Allocator, base: *TreeHash) Error!void {
        const aliases = base.program.aliases;
        const digests = try a.alloc(stage.Digest, aliases.len);
        for (aliases, digests) |alias, *slot| {
            var one = TreeHash.init(base.program, base.context, null);
            one.record_keys = base.record_keys;
            try one.value(alias);
            slot.* = one.finish();
        }
        std.mem.sort(stage.Digest, digests, {}, struct {
            fn less(_: void, left: stage.Digest, right: stage.Digest) bool {
                return std.mem.lessThan(u8, &left, &right);
            }
        }.less);
        try base.value(aliases.len);
        for (digests) |digest| base.hash.update(&digest);
    }

    /// Checked nodes/statements are dereferenced, so allocator order and global
    /// node ordinals cannot invalidate unrelated bodies. Local spans relocate.
    /// The key covers the body, the source identity, and only the declarations the
    /// function reaches (`reachDigest`), so a new unrelated declaration rebuilds nothing.
    pub fn key(self: *Session, mb: Context, checked: typed.Function) Error!Keyed {
        if (self.cache.engine.parts) |source| {
            if (source.digest(source.context, mb.input.source, checked)) |part| {
                self.cache.counts.by_part += 1;
                return self.keyedByPart(mb, checked, part);
            }
        }
        const whole = self.catalog orelse {
            cache_miss.note(@src());
            return error.InvalidSnapshot;
        };
        const program = mb.input.program;
        if (self.declarations.functions.len != program.functions.len or self.declarations.records.len != program.records.len) {
            self.declarations = try DeclarationDigests.init(mb.arena, program, mb.input.source);
        }
        var refs: Refs = .{ .arena = mb.arena };
        const queries = self.cache.demand;
        const omitted = if (queries) |demand_queries| demand_queries.omitted(checked.id) else false;
        var body: stage.Digest = undefined;
        var stored: ?RefsDto = null;
        if (omitted) {
            // The frontend did not materialize this body: its digest and its references come from earlier builds.
            body = queries.?.body(checked.id) orelse {
                cache_miss.note(@src());
                return error.InvalidSnapshot;
            };
            try queries.?.record(checked.id, body);
            stored = try self.cache.store.loadValue(mb.arena, bodyRefsKey(self.cache.store, body), RefsDto);
            if (stored) |found| {
                // A stored name no current function carries uniquely leaves the whole catalog in the key.
                if (!try self.resolveRefs(mb.arena, found, &refs)) stored = null;
            }
        } else {
            body = try self.bodyKey(mb, checked, &refs);
            // A later build that omits this body finds its references under this digest. This build keys the body from the
            // checked tree and never loads that record, and compaction keeps only the records a recent build needed: without
            // this, the record is gone two generations on, the omitted body is keyed under the whole catalog, its artifact is
            // not found and the build starts again with complete trees.
            self.cache.store.need(&.{bodyRefsKey(self.cache.store, body)});
        }
        // Without recorded references, an omitted body keeps the whole catalog: a miss, never a stale hit.
        const catalog = if (omitted and stored == null) whole else (try self.reachDigest(mb, checked, &refs)) orelse whole;
        // The entry point's index moves whenever an earlier declaration is added, so only the flag that this function is it enters the key.
        const modes = [_]u8{ @intFromBool(mb.input.drop_debug), @intFromBool(checked.id == mb.input.program.main) };
        const digest = self.cache.store.key("lowered-function-v15", &.{ &self.base, &catalog, &self.assets, &body, &modes, "zero-rc", "zero-rc" });
        return .{ .key = digest, .body = body, .refs = if (stored) |found| found else try self.refsDto(mb, refs) };
    }

    /// The key of a function the engine holds a checked-body part for (G3h `module-check`): the part digest covers the function's
    /// region of source and the dependency context it was checked in (the declarations its body names), which is what the front end's
    /// own cache trusts to keep a checked body, so neither the tree nor the declarations it reaches are hashed, and no reference list
    /// is stored or loaded. The settings lowering reads besides the program are in the key: debug lines, being the entry, and the
    /// embedded assets. The key is the same in every program that checks the body alike. A function whose positions are in
    /// another file is restored only while the proofs of those files hold (`validWireSources`), whatever its key.
    fn keyedByPart(self: *Session, mb: Context, checked: typed.Function, part: stage.Digest) Error!Keyed {
        const modes = [_]u8{ @intFromBool(mb.input.drop_debug), @intFromBool(checked.id == mb.input.program.main) };
        // A generic instance is its template's body at its type arguments: the template's part, the arguments as they are spelled and
        // the records they reach (a layout the part does not hold). Any other function has no arguments.
        const arguments: stage.Digest = if (checked.type_arguments.len != 0) try self.argumentsDigest(mb, checked) else @splat(0);
        const digest = self.cache.store.key("lowered-function-v16", &.{ &part, &arguments, &self.assets, &modes, "zero-rc" });
        if (self.cache.demand) |queries| try queries.record(checked.id, digest);
        return .{ .key = digest, .body = digest, .refs = .{} };
    }

    /// The digest of what a generic instance's type arguments are: its checked name, which spells them, and each record they reach
    /// (through the fields of records, each once, in the order of their name digests) by its name digest and its declared digest.
    fn argumentsDigest(self: *Session, mb: Context, checked: typed.Function) Error!stage.Digest {
        const program = mb.input.program;
        if (self.declarations.functions.len != program.functions.len or self.declarations.records.len != program.records.len) {
            self.declarations = try DeclarationDigests.init(mb.arena, program, mb.input.source);
        }
        var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
        var reached: std.ArrayList(usize) = .empty;
        const reach = if (self.cache.engine.field_reach_arguments) &reachRecordsByFields else &reachRecordsOf;
        for (checked.type_arguments) |argument| try reach(mb.arena, program, argument, &seen, &reached);
        std.mem.sort(usize, reached.items, &self.declarations.keys, struct {
            fn less(keys: *const record_names.RecordKeys, left: usize, right: usize) bool {
                return std.mem.lessThan(u8, &keys.digests[left], &keys.digests[right]);
            }
        }.less);
        var hash = fast_blake3.Blake3.init(.{});
        hash.update("instance-arguments-v1\x00");
        hash.update(checked.name);
        hash.update("\x00");
        for (reached.items) |index| {
            hash.update(&self.declarations.keys.digests[index]);
            const declared = try recordDigestOf(&self.declarations, program, index);
            hash.update(&declared);
        }
        var out: stage.Digest = undefined;
        hash.final(&out);
        return out;
    }

    /// Current indices of stored references; false when a stored name no
    /// longer belongs to exactly one function, or a stored record name belongs to no record.
    fn resolveRefs(self: *const Session, a: std.mem.Allocator, found: RefsDto, refs: *Refs) Error!bool {
        for (found.functions) |reference| {
            const index: usize = switch (reference) {
                .index => |index| @intCast(index),
                .name => |value| self.declarations.names.find(value) orelse {
                    refs.functions.clearRetainingCapacity();
                    return false;
                },
            };
            try refs.functions.append(a, index);
        }
        for (found.types) |digest| {
            const index = self.declarations.keys.find(digest) orelse {
                refs.functions.clearRetainingCapacity();
                refs.types.clearRetainingCapacity();
                return false;
            };
            try refs.types.append(a, @fromBackingInt(typed.Type.record_base + index));
        }
        return true;
    }

    /// The references of one body in stored form: unique functions by name.
    fn refsDto(self: *const Session, mb: Context, refs: Refs) Error!RefsDto {
        const functions = try mb.arena.alloc(FunctionRef, refs.functions.items.len);
        for (functions, refs.functions.items) |*slot, index| {
            slot.* = if (self.declarations.names.name(mb.input.program, index)) |value| .{ .name = value } else .{ .index = index };
        }
        // The records the body names, by the digests of their names, each once and in a fixed order.
        var records: std.ArrayList(record_names.RecordKeys.Digest) = .empty;
        for (refs.types.items) |ty| if (self.declarations.keys.digestOfType(ty)) |digest| try records.append(mb.arena, digest);
        std.mem.sort(record_names.RecordKeys.Digest, records.items, {}, digestLess);
        var unique: usize = 0;
        for (records.items) |digest| {
            if (unique != 0 and std.mem.eql(u8, &records.items[unique - 1], &digest)) continue;
            records.items[unique] = digest;
            unique += 1;
        }
        return .{ .functions = functions, .types = records.items[0..unique] };
    }

    fn digestLess(_: void, a: record_names.RecordKeys.Digest, b: record_names.RecordKeys.Digest) bool {
        return std.mem.lessThan(u8, &a, &b);
    }

    /// Digest of the declarations `checked` reaches (`reachDigestOf`), in this session's declaration digests.
    fn reachDigest(self: *Session, mb: Context, checked: typed.Function, refs: *Refs) Error!?stage.Digest {
        return reachDigestOf(mb.arena, mb.input.program, &self.declarations, checked, refs);
    }

    fn bodyKey(self: *Session, mb: Context, checked: typed.Function, refs: *Refs) Error!stage.Digest {
        var h = TreeHash.init(mb.input.program, .{ .module = mb.module, .source = mb.input.source }, checked);
        var reach: demand_sources.Reach = .{};
        h.sources = &self.sources;
        h.proofs = &reach;
        h.refs = refs;
        h.identities = &self.declarations.names;
        h.record_keys = &self.declarations.keys;
        // The function's own index is not part of its body: the walk names it by a sentinel, and the
        // reach key covers the function itself. A recursive call still names the real index.
        var anonymous = checked;
        anonymous.id = @fromBackingInt(own_sentinel);
        try TreeWalk.run(mb.arena, &h, typed.Function, anonymous);
        const proofs = try self.sources.seal(&reach) orelse blk: {
            h.proven = false;
            break :blk &.{};
        };
        try h.value(proofs);
        const digest = h.finish();
        if (h.proven) if (self.cache.demand) |queries| {
            try queries.record(checked.id, digest);
            try queries.addSources(checked.id, proofs);
        };
        return digest;
    }

    /// Decode and validate with private scratch and temporary discovery deltas.
    /// Every accepted pointer is then copied onto the result arena. The artifact's type operations are replayed into the
    /// live module, which finds the types that exist and creates the others; its bodies are then placed on the module's
    /// types. A refusal before the replay leaves the module untouched.
    pub fn restore(self: *Session, scratch: std.mem.Allocator, key_value: stage.Digest, mb: Context, checked: typed.Function, declared: ir.Function) (std.mem.Allocator.Error || error{Unsupported})!?ir.Function {
        cache_miss.clear();
        const names = mb.names orelse return cache_miss.absent(@src());
        if (!names.log.recording()) return cache_miss.absent(@src());
        const header = if (self.cache.lazy != null and !self.cache.lazy.?.force_eager) try self.cache.store.loadValue(scratch, headerKey(self.cache.store, key_value), Header) else null;
        const wire = if (header) |metadata| metadata.wire else try self.cache.store.loadValue(scratch, key_value, Wire) orelse return cache_miss.absent(@src());
        const before = Before.init(mb);
        if (!try validWireSources(&self.sources, wire)) return cache_miss.absent(@src());
        if (self.cache.demand) |queries| try queries.addSources(checked.id, wire.sources);
        // Everything that can refuse an artifact is checked before the first change to the module, except what needs the
        // artifact's types in the module: those are made first, which is harmless because the lowering the refusal falls
        // back to makes the same types in the same order.
        if (!try replayable(scratch, mb, names, wire.delta.types)) return cache_miss.absent(@src());
        if (!try presentable(mb, &self.declarations.names, wire, before.strings)) return cache_miss.absent(@src());
        const replayed = try names.log.replayInto(mb.module, mb.arena, wire.delta.types);
        try bindRecords(mb, names, replayed.created);
        const own = placedSignature(scratch, wire.function.value.signature, replayed.map) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return cache_miss.absent(@src()),
        };
        if (!std.mem.eql(u8, wire.function.value.name, declared.name) or !sameSignature(own, declared.signature)) return cache_miss.absent(@src());
        if (!try fits(scratch, mb, wire, .{ .types = replayed.map, .own = own, .start = checked.declaration.start, .first_string = before.strings })) {
            self.cache.counts.unfit += 1;
            self.cache.store.noteUnfit(key_value);
            if (self.cache.strict_fit) return names.builder.refuse(names.builder.context, "a stored function that does not fit the module it is restored into");
            return cache_miss.absent(@src());
        }
        const landing: Landing = .{ .wire = wire, .before = before, .types = replayed.map, .identities = &self.declarations.names };
        const functions = try executeRequests(scratch, mb, landing);
        const place: Placement = .{ .start = checked.declaration.start, .old = wire.delta.string_start, .new = before.strings, .places = .{ .types = replayed.map, .functions = functions } };
        const result = try fillBodies(scratch, mb, wire, place, header != null);
        self.cache.counts.reused += 1;
        if (self.cache.engine.observed) |observed| {
            const artifact = if (header) |metadata| metadata.digest else try canonicalDigest(scratch, wire);
            try observed.add(.{ .id = checked.id, .key = key_value, .artifact = artifact, .reused = true, .sources = wire.sources, .made = try madeNames(scratch, wire) });
        }
        if (header == null) if (self.cache.lazy) |lazy| {
            lazy.restored += 1;
        };
        const plain: ?bool = if (header) |metadata| (if (metadata.helpers) |helps| !helps else null) else null;
        const known: Known = .{
            .source_max = if (header) |metadata| metadata.source_max else sourceMaximum(wire),
            .proofs = wire.sources,
            .plain = plain,
            .effects = if (header) |metadata| metadata.effects else null,
            .defines = hasDefines(wire),
        };
        if (self.cache.lazy) |lazy| try lazy.record(mb.discovery.ids.get(@backingInt(checked.id)).?, key_value, if (header != null) .{
            .key = key_value,
            .start = checked.declaration.start,
            .old_strings = wire.delta.string_start,
            .new_strings = before.strings,
            .string_count = wire.delta.strings.len,
            .places = place.places,
        } else null, known);
        return result;
    }

    /// Write the headers still held, without a flag: the build ended before it finished those bodies (an error, or a build that
    /// never finishes them). A later build that defers such a body restores it, as it would one whose finish is not recorded.
    /// Best effort: a failure here costs warmth, never a result.
    pub fn flush(self: *Session) void {
        var held = self.pending.iterator();
        while (held.next()) |entry| self.cache.store.storeValue(headerKey(self.cache.store, entry.key_ptr.*), Header, entry.value_ptr.*) catch return;
        self.pending.clearRetainingCapacity();
    }

    /// Capture exact table deltas while successful lowering is still untransformed. The function and the functions it
    /// made are stored on the segment's local type ids, beside the segment's type operations and its function requests.
    pub fn remember(self: *Session, a: std.mem.Allocator, mb: Context, publication: Publication, built: ir.Function) std.mem.Allocator.Error!?Remembered {
        const names = mb.names orelse return null;
        const log = names.log;
        if (!log.recording()) return null;
        const before = publication.before;
        const checked = publication.checked;
        const context: snapshot.Context = .{ .module = mb.module, .source = mb.input.source };
        const capture: Capture = .{ .mb = mb, .before = before, .checked = checked, .context = context, .identities = &self.declarations.names };
        var requests: Requests = .{};
        for (log.functionTouches()) |index| _ = try requests.add(a, index);
        for (before.functions..mb.module.functions.items.len) |index| _ = try requests.add(a, @intCast(index));
        var body = try log.localizeFunction(a, mb.module, built);
        try localizeIds(a, &requests, &body);
        const function = captureFunction(a, context, mb.input.program, checked, body) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return null;
        };
        var next: usize = 0;
        while (next < requests.order.items.len) : (next += 1) {
            const request = try requestFor(a, capture, &requests, requests.order.items[next]) orelse return null;
            try requests.list.append(a, request);
        }
        // The operations are read last: localizing the bodies may have added the types they use.
        if (!log.recording()) return null;
        var wire: Wire = .{
            .function = function,
            .delta = .{
                .requests = requests.list.items,
                .types = log.operations(),
                .strings = mb.module.strings.items[before.strings..],
                .string_start = before.strings,
            },
        };
        wire.sources = (try wireSources(&self.sources, wire)) orelse {
            if (self.cache.demand) |queries| queries.reject(checked.id);
            return null;
        };
        if (self.cache.demand) |queries| try queries.addSources(checked.id, wire.sources);
        try self.cache.store.storeValue(publication.key, Wire, wire);
        const artifact = try canonicalDigest(a, wire);
        const effects = try effectsDigest(a, wire);
        if (self.cache.engine.observed) |observed| try observed.add(.{ .id = checked.id, .key = publication.key, .artifact = artifact, .reused = false, .sources = wire.sources, .made = try madeNames(a, wire) });
        if (publication.refs.functions.len != 0 or publication.refs.types.len != 0) try self.cache.store.storeValue(bodyRefsKey(self.cache.store, publication.body), RefsDto, publication.refs);
        var header = wire;
        header.function.value.insts = &.{};
        header.function.value.blocks = &.{};
        header.function.value.extra = &.{};
        header.function.value.loops = &.{};
        header.function.positions = function.positions[0..1];
        const stored_header: Header = .{
            .wire = header,
            .local_positions = localPositions(wire),
            .source_max = sourceMaximum(wire),
            .digest = artifact,
            .effects = effects,
        };
        // Held until the body is finished, then written once with the flag (`rememberFinish`, or `flush` when the build ends first).
        try self.pending.put(mb.arena, publication.key, try clone(mb.arena, Header, stored_header));
        const fresh: Handle = .{
            .key = publication.key,
            .start = checked.declaration.start,
            .old_strings = before.strings,
            .new_strings = before.strings,
            .string_count = wire.delta.strings.len,
            .places = .{ .types = try log.typePlaces(mb.arena), .functions = try mb.arena.dupe(u32, requests.order.items) },
        };
        const known: Known = .{ .source_max = sourceMaximum(wire), .proofs = wire.sources, .plain = null, .effects = effects, .defines = hasDefines(wire), .fresh = fresh };
        if (self.cache.lazy) |lazy| try lazy.record(mb.discovery.ids.get(@backingInt(checked.id)).?, publication.key, null, known);
        return .{ .effects = effects, .string_start = wire.delta.string_start, .string_count = wire.delta.strings.len, .sources = wire.sources, .source_max = known.source_max };
    }
};

/// The function requests of one lowering, in the order they were first made: the global index of each, the local id each
/// has, and the request descriptions built from them.
const Requests = struct {
    list: std.ArrayList(Request) = .empty,
    order: std.ArrayList(u32) = .empty,
    local: std.AutoHashMapUnmanaged(u32, u32) = .empty,

    /// The local id of the function at `index`, entering it as a request the first time.
    fn add(self: *Requests, a: std.mem.Allocator, index: u32) std.mem.Allocator.Error!u32 {
        const found = try self.local.getOrPut(a, index);
        if (!found.found_existing) {
            found.value_ptr.* = @intCast(self.order.items.len);
            try self.order.append(a, index);
        }
        return found.value_ptr.*;
    }
};

/// What describing a request needs: the lowering, the table lengths before it, its checked function, the source context
/// and the identities of the checked functions.
const Capture = struct { mb: Context, before: Before, checked: typed.Function, context: snapshot.Context, identities: *const Identities };

/// Replace the function ids of `function`'s calls and function values by local ids, entering each function as a request.
fn localizeIds(a: std.mem.Allocator, requests: *Requests, function: *ir.Function) std.mem.Allocator.Error!void {
    for (function.insts.items) |*inst| switch (inst.op) {
        .call => inst.a = @fromBackingInt(try requests.add(a, @intCast(inst.a.index()))),
        .func_ref => inst.data = try requests.add(a, @intCast(inst.data)),
        else => {},
    };
}

/// The request that finds or makes the function at `index` in another program, or null when the artifact cannot say (a
/// checked name two functions share, or an internal function whose name is not unique).
fn requestFor(a: std.mem.Allocator, capture: Capture, requests: *Requests, index: u32) std.mem.Allocator.Error!?Request {
    const mb = capture.mb;
    const log = mb.names.?.log;
    const target = mb.module.functions.items[index];
    if (log.isSource(index)) {
        if (capture.identities.find(normalizedName(target.name)) == null) return null;
        return .{ .declare = target.name };
    }
    if (op_log.shapeId(target.name)) |id| if (target.signature.linkage == .runtime_c) {
        if (index < capture.before.functions) return .{ .shape = .{ .id = id, .string = null } };
        const string = shapeString(target.name, capture.before.strings, mb.module.strings.items.len) orelse return null;
        return .{ .shape = .{ .id = id, .string = string } };
    };
    if (target.signature.linkage != .internal) return .{ .helper = .{ .name = target.name, .signature = try log.localizeSignature(a, mb.module, target.signature) } };
    if (index < capture.before.functions) {
        if ((try log.functionsNamed(mb.module, target.name, capture.before.functions)).len != 1) return null;
        return .{ .found = .{ .name = target.name, .signature = try log.localizeSignature(a, mb.module, target.signature) } };
    }
    var body = try log.localizeFunction(a, mb.module, target);
    try localizeIds(a, requests, &body);
    const dto = captureFunction(a, capture.context, mb.input.program, capture.checked, body) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    return .{ .define = dto };
}

/// The string, among those a lowering appended from `first`, that the shape declaration `name` over module string
/// `index` authorizes, as a local string index; null when it is outside them.
fn shapeString(name: []const u8, first: usize, count: usize) ?u32 {
    const tail = name[render.declaration_prefix.len..];
    const split = std.mem.indexOfScalar(u8, tail, '_') orelse return null;
    const index = std.fmt.parseInt(usize, tail[0..split], 10) catch return null;
    if (index < first or index >= count) return null;
    return @intCast(index - first);
}

/// Bind the records a restore reserved, the way `ModuleBuilder.reserve` does for the ones a lowering reserves.
fn bindRecords(mb: Context, names: Names, created: []const op_log.Created) std.mem.Allocator.Error!void {
    for (created) |made| {
        const record = names.records.find(mb.input.program, made.name).?;
        try mb.types.put(mb.arena, record, made.ty);
    }
}

/// Whether every request that must find something can: a declared function names one checked function, an internal
/// function or a shape the lowering did not make is in the module. Nothing is changed.
fn presentable(mb: Context, identities: *const Identities, wire: Wire, first_string: usize) std.mem.Allocator.Error!bool {
    const log = mb.names.?.log;
    const count = mb.module.functions.items.len;
    for (wire.delta.requests) |request| switch (request) {
        .declare => |name| if (identities.find(normalizedName(name)) == null) return false,
        .found => |found| if ((try log.functionsNamed(mb.module, found.name, count)).len == 0) return false,
        .shape => |shape| if (shape.string == null and try log.shapeDeclared(mb.module, shape.id, count) == null) return false,
        .helper, .define => {},
    };
    _ = first_string;
    return true;
}

/// Where `fits` places an artifact: the module's type for each of its local types, its own placed signature, the start of the
/// function's declaration and the module's string count before the artifact's strings.
const Fit = struct { types: []const ir.Type, own: ir.Signature, start: usize, first_string: usize };

/// Whether the artifact can be placed in the live module, decided before the first change to it besides the type replay (which
/// the lowering a miss falls back to repeats). Every signature the artifact names is valid on the module's types; a function it
/// finds or defines meets no function of its name with another signature; and its bodies restore against the module's strings
/// and sources, with the functions it names at stand-in places. A record that fits is not refused by `executeRequests` or
/// `fillBodies`; one that does not is a miss, never a refused build (`Session.restore`).
fn fits(scratch: std.mem.Allocator, mb: Context, wire: Wire, fit: Fit) std.mem.Allocator.Error!bool {
    const module = mb.module;
    const log = mb.names.?.log;
    if (!validSignature(module, fit.own)) return false;
    var probe = module.*;
    const strings = try scratch.alloc([]const u8, fit.first_string + wire.delta.strings.len);
    @memcpy(strings[0..fit.first_string], module.strings.items[0..fit.first_string]);
    @memcpy(strings[fit.first_string..], wire.delta.strings);
    probe.strings = .fromOwnedSlice(strings);
    const functions = try scratch.alloc(u32, wire.delta.requests.len);
    @memset(functions, 0);
    const place: Placement = .{ .start = fit.start, .old = wire.delta.string_start, .new = fit.first_string, .places = .{ .types = fit.types, .functions = functions } };
    const live: snapshot.Context = .{ .module = &probe, .source = mb.input.source };
    for (wire.delta.requests) |request| switch (request) {
        .helper, .found => |named| {
            const wanted = placedSignature(scratch, named.signature, fit.types) catch |err| return fitError(err);
            if (!validSignature(module, wanted)) return false;
            var matching: usize = 0;
            for (try log.functionsNamed(module, named.name, module.functions.items.len)) |index| {
                if (module.functions.items[index].signature.eql(wanted)) matching += 1;
            }
            if (matching > 1) return false;
        },
        .define => |defined| {
            const wanted = placedSignature(scratch, defined.value.signature, fit.types) catch |err| return fitError(err);
            if (!validSignature(module, wanted)) return false;
            for (try log.functionsNamed(module, defined.value.name, module.functions.items.len)) |index| {
                if (!module.functions.items[index].signature.eql(wanted)) return false;
            }
            const body = restoreFunction(scratch, live, place, defined) catch |err| return fitError(err);
            if (body.insts.items.len != 0 and !try safeFunction(scratch, &probe, body)) return false;
        },
        .declare, .shape => {},
    };
    const own = restoreFunction(scratch, live, place, wire.function) catch |err| return fitError(err);
    if (own.insts.items.len != 0 and !try safeFunction(scratch, &probe, own)) return false;
    return true;
}

/// A restore error in `fits`: an allocation failure stays one, and an invalid snapshot is a record that does not fit.
fn fitError(err: Error) std.mem.Allocator.Error!bool {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidSnapshot => false,
    };
}

/// An artifact being placed in the live module: its wire, the table lengths before it, the module's type for each local
/// type, and the identities of the checked functions.
const Landing = struct { wire: Wire, before: Before, types: []const ir.Type, identities: *const Identities };

/// Repeat the artifact's function requests on the live module, in order: find what exists, declare or append the rest.
/// Returns the live index of each request. Strings are appended first, so a shape's string has its place. A request that
/// cannot be met after the first change is an internal error, reported as a refusal of the build.
fn executeRequests(scratch: std.mem.Allocator, mb: Context, landing: Landing) (std.mem.Allocator.Error || error{Unsupported})![]const u32 {
    const names = mb.names.?;
    const wire = landing.wire;
    const module = mb.module;
    try module.strings.appendSlice(mb.arena, wire.delta.strings);
    for (module.strings.items[landing.before.strings..], 0..) |*text, at| text.* = try mb.arena.dupe(u8, wire.delta.strings[at]);
    const live = try mb.arena.alloc(u32, wire.delta.requests.len);
    for (wire.delta.requests, live, 0..) |request, *slot, position_in_list| {
        _ = position_in_list;
        slot.* = switch (request) {
            .declare => |name| names.builder.declare(names.builder.context, @fromBackingInt(landing.identities.find(normalizedName(name)).?)) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Unsupported => return error.Unsupported,
            },
            .helper, .found => |named| try placeNamed(scratch, mb, landing, named, request == .helper),
            .define => |defined| try placeDefined(scratch, mb, landing, defined),
            .shape => |shape| try placeShape(mb, landing, shape),
        };
    }
    return live;
}

/// The live index of the function `named` describes (name, and signature on the artifact's local types), appended from that
/// description when `make` and the module lacks it.
fn placeNamed(scratch: std.mem.Allocator, mb: Context, landing: Landing, named: Request.Named, make: bool) (std.mem.Allocator.Error || error{Unsupported})!u32 {
    const names = mb.names.?;
    const wanted = placedSignature(scratch, named.signature, landing.types) catch return names.builder.refuse(names.builder.context, "a stored function that names a type its artifact does not define");
    const module = mb.module;
    var hit: ?u32 = null;
    for (try names.log.functionsNamed(module, named.name, module.functions.items.len)) |index| {
        if (!module.functions.items[index].signature.eql(wanted)) continue;
        if (hit != null) return names.builder.refuse(names.builder.context, "a stored function that names two functions of the module");
        hit = index;
    }
    if (hit) |index| return index;
    if (!make) return names.builder.refuse(names.builder.context, "a stored lowering that lost a function it relies on");
    const index: u32 = @intCast(module.functions.items.len);
    try module.functions.append(mb.arena, .{ .name = try mb.arena.dupe(u8, named.name), .signature = try wanted.clone(mb.arena) });
    return index;
}

/// The live index of the function a lowering made: found by name, else appended; its body is filled in by `fillBodies`.
fn placeDefined(scratch: std.mem.Allocator, mb: Context, landing: Landing, defined: Function) (std.mem.Allocator.Error || error{Unsupported})!u32 {
    const names = mb.names.?;
    const wanted = placedSignature(scratch, defined.value.signature, landing.types) catch return names.builder.refuse(names.builder.context, "a stored function that names a type its artifact does not define");
    const module = mb.module;
    for (try names.log.functionsNamed(module, defined.value.name, module.functions.items.len)) |index| {
        if (module.functions.items[index].signature.eql(wanted)) return index;
        return names.builder.refuse(names.builder.context, "a stored function that meets a function of its name with another signature");
    }
    const index: u32 = @intCast(module.functions.items.len);
    try module.functions.append(mb.arena, .{ .name = try mb.arena.dupe(u8, defined.value.name), .signature = try wanted.clone(mb.arena) });
    return index;
}

/// The live index of a render shape declaration: the one for its id, else a declaration appended over the string the
/// lowering appended for it.
fn placeShape(mb: Context, landing: Landing, shape: Request.Shape) (std.mem.Allocator.Error || error{Unsupported})!u32 {
    const names = mb.names.?;
    const module = mb.module;
    if (try names.log.shapeDeclared(module, shape.id, module.functions.items.len)) |index| return index;
    const string = shape.string orelse return names.builder.refuse(names.builder.context, "a stored lowering that lost a render shape it relies on");
    const index: u32 = @intCast(module.functions.items.len);
    const symbol = try std.fmt.allocPrint(mb.arena, "{s}{d}_{s}", .{ render.declaration_prefix, landing.before.strings + string, shape.id });
    try module.functions.append(mb.arena, .{ .name = symbol, .signature = .{ .params = &.{}, .ret = .void, .linkage = .runtime_c } });
    return index;
}

/// Fill the bodies of the functions the restore appended and restore the artifact's own function, which is returned. A
/// body that cannot be placed after the module has changed is an internal error.
fn fillBodies(scratch: std.mem.Allocator, mb: Context, wire: Wire, place: Placement, is_header: bool) (std.mem.Allocator.Error || error{Unsupported})!ir.Function {
    const names = mb.names.?;
    const live: snapshot.Context = .{ .module = mb.module, .source = mb.input.source };
    for (wire.delta.requests, place.places.functions) |request, index| {
        if (request != .define) continue;
        const module_function = &mb.module.functions.items[index];
        if (module_function.blocks.items.len != 0) continue;
        module_function.* = restoreFunction(mb.arena, live, place, request.define) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return names.builder.refuse(names.builder.context, "a stored function that does not fit the module it is restored into"),
        };
    }
    const result = restoreFunction(mb.arena, live, place, wire.function) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidSnapshot => return names.builder.refuse(names.builder.context, "a stored function that does not fit the module it is restored into"),
    };
    if (!is_header and !try safeFunction(scratch, mb.module, result)) return names.builder.refuse(names.builder.context, "a malformed stored function");
    return result;
}

/// `signature` with its local compound ids replaced by the module's types.
fn placedSignature(a: std.mem.Allocator, signature: ir.Signature, types: []const ir.Type) Error!ir.Signature {
    const place: Places = .{ .types = types, .functions = &.{} };
    var out = signature;
    const params = try a.alloc(ir.Type, signature.params.len);
    for (params, signature.params) |*placed, param| placed.* = try placedType(place, param);
    out.params = params;
    out.ret = try placedType(place, signature.ret);
    return out;
}

/// Whether the artifact's type operations can be replayed: each nominal type names a record of this program, one the
/// builder has not already mapped to another type, and the operations are well formed (`op_log.Recorder.replayable`).
fn replayable(scratch: std.mem.Allocator, mb: Context, names: Names, ops: []const op_log.TypeOp) std.mem.Allocator.Error!bool {
    for (ops) |op| if (op == .nominal) {
        const record = names.records.find(mb.input.program, op.nominal) orelse return false;
        if (names.log.nominalType(mb.module, op.nominal) == null and mb.types.contains(record)) return false;
    };
    return names.log.replayable(mb.module, scratch, ops);
}

/// The artifact in canonical form: what it says about the function and nothing about where the program that stored it put the
/// function. Instruction and function spans (the positions hold them), the absolute index of every string the lowering appended
/// (counted from the first of them instead), and the string slot in the name of a render declaration are replaced by their local
/// forms, exactly the substitutions a restore undoes (`restoreFunction`); the proofs of the files the positions are in are
/// authority for a restore, not content. Two lowerings of one function in programs that differ elsewhere give the same digest.
fn canonicalDigest(a: std.mem.Allocator, wire: Wire) std.mem.Allocator.Error!stage.Digest {
    var canonical = wire;
    const first = wire.delta.string_start;
    canonical.function = try canonicalFunction(a, wire.function, first);
    const requests = try a.alloc(Request, wire.delta.requests.len);
    for (requests, wire.delta.requests) |*slot, request| slot.* = switch (request) {
        .define => |defined| .{ .define = try canonicalFunction(a, defined, first) },
        else => request,
    };
    canonical.delta.requests = requests;
    canonical.delta.string_start = 0;
    canonical.sources = &.{};
    var writer = codec.Writer.init(a);
    try writer.write(Wire, canonical);
    var digest: stage.Digest = undefined;
    fast_blake3.hash(writer.bytes.items, &digest);
    return digest;
}

/// What `Session.remember` kept of a function it captured: the digest of its effects on the program's tables, where its strings began
/// in the module it was lowered in, the proofs of the files its positions are in and the largest of those positions.
pub const Remembered = struct { effects: stage.Digest, string_start: usize, string_count: usize, sources: []const demand_sources.Proof, source_max: ?u32 };

/// Whether the artifact defines functions of its own (`Request.define`: thunks, adapters, workers): a restore places their bodies.
fn hasDefines(wire: Wire) bool {
    for (wire.delta.requests) |request| if (request == .define) return true;
    return false;
}

/// The digest of what a lowering did to the program's tables, and of nothing else: the type operations of its segment, the requests it
/// made of the function table (a function it defines by its name and signature alone, not its body), the strings it appended counted
/// from the first of them, and its own name and signature. Two lowerings of one function whose digests agree leave a program
/// assembled with the first assembled for the second as well, whatever the body they gave the function (`lowering_assembly.zig`).
fn effectsDigest(a: std.mem.Allocator, wire: Wire) std.mem.Allocator.Error!stage.Digest {
    const first = wire.delta.string_start;
    const requests = try a.alloc(Request, wire.delta.requests.len);
    for (requests, wire.delta.requests) |*slot, request| slot.* = switch (request) {
        .define => |defined| blk: {
            var declared = try canonicalFunction(a, defined, first);
            declared.value.insts = &.{};
            declared.value.blocks = &.{};
            declared.value.extra = &.{};
            declared.value.loops = &.{};
            declared.positions = &.{};
            break :blk .{ .define = declared };
        },
        else => request,
    };
    const delta: Delta = .{ .requests = requests, .types = wire.delta.types, .strings = wire.delta.strings, .string_start = 0 };
    var writer = codec.Writer.init(a);
    try writer.write(Delta, delta);
    try writer.write([]const u8, wire.function.value.name);
    try writer.write(ir.Signature, wire.function.value.signature);
    var digest: stage.Digest = undefined;
    fast_blake3.hash(writer.bytes.items, &digest);
    return digest;
}

/// `function` with its spans zeroed, its string operands counted from `first` and its render name made local.
fn canonicalFunction(a: std.mem.Allocator, function: Function, first: usize) std.mem.Allocator.Error!Function {
    var out = function;
    const insts = try a.dupe(ir.Inst, function.value.insts);
    for (insts) |*inst| {
        inst.span = 0;
        if (inst.op == .str_const) inst.data -%= first;
        if (inst.op == .@"unreachable" and inst.data & flags.assertion_trap != 0) {
            inst.data = (inst.data & 0xffffffff00000000) | (@as(u32, @truncate(inst.data)) -% @as(u32, @intCast(first)));
        }
    }
    out.value.insts = insts;
    out.value.span = 0;
    if (std.mem.startsWith(u8, out.value.name, render.declaration_prefix)) {
        const tail = out.value.name[render.declaration_prefix.len..];
        if (std.mem.indexOfScalar(u8, tail, '_')) |at| {
            const original = std.fmt.parseInt(usize, tail[0..at], 10) catch return out;
            out.value.name = try std.fmt.allocPrint(a, "{s}{d}{s}", .{ render.declaration_prefix, original -% first, tail[at..] });
        }
    }
    return out;
}

/// The names of the functions the artifact defines besides its own: the functions its lowering made.
fn madeNames(a: std.mem.Allocator, wire: Wire) std.mem.Allocator.Error![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (wire.delta.requests) |request| if (request == .define) try names.append(a, request.define.value.name);
    return names.items;
}

fn localPositions(wire: Wire) bool {
    for (wire.function.positions) |at| if (at == .external) return false;
    for (wire.delta.requests) |request| if (request == .define) {
        for (request.define.positions) |at| if (at == .external) return false;
    };
    return true;
}

/// Every external position of the stored functions must carry exact original-file authority: the proof of each file they
/// are in, as far as the last of them reaches. Null when a position cannot be proven.
fn wireSources(sources: *demand_sources.Cache, wire: Wire) std.mem.Allocator.Error!?[]const demand_sources.Proof {
    var reach: demand_sources.Reach = .{};
    for (wire.function.positions) |at| if (at == .external) {
        if (!try sources.collect(&reach, at.external)) return null;
    };
    for (wire.delta.requests) |request| if (request == .define) {
        for (request.define.positions) |at| if (at == .external) {
            if (!try sources.collect(&reach, at.external)) return null;
        };
    };
    return sources.seal(&reach);
}

// Header and payload share one captured wire, so proof ordering is canonical
// for this artifact. Require every proof used by the raw key to match exactly.
fn sameSourceProofs(a: []const demand_sources.Proof, b: []const demand_sources.Proof) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (left.length != right.length) return false;
        if (!std.mem.eql(u8, left.path, right.path) or !std.mem.eql(u8, &left.digest, &right.digest)) return false;
    }
    return true;
}

fn validWireSources(sources: *demand_sources.Cache, wire: Wire) std.mem.Allocator.Error!bool {
    if (!try sources.matches(wire.sources)) return false;
    const required = try wireSources(sources, wire) orelse return false;
    return demand_sources.Cache.covers(wire.sources, required);
}

fn sameSignature(a: ir.Signature, b: ir.Signature) bool {
    return a.eql(b);
}

fn validSignature(module: *const ir.Module, sig: ir.Signature) bool {
    if (!module.valid(sig.ret) or !module.validBorrow(sig)) return false;
    if (!sig.passing.valid(sig.params.len)) return false;
    for (sig.params) |ty| if (!module.valid(ty)) return false;
    return true;
}

fn safeFunction(a: std.mem.Allocator, module: *const ir.Module, f: ir.Function) std.mem.Allocator.Error!bool {
    if (!validSignature(module, f.signature) or f.blocks.items.len == 0) return false;
    for (f.blocks.items) |block| {
        for (block.insts.items) |ref| if (ref.index() >= f.insts.items.len) return false;
        for (block.preds.items) |pred| if (pred.index() >= f.blocks.items.len) return false;
    }
    for (f.insts.items) |inst| {
        if (inst.op.hasExtra()) {
            const slice = ir.ExtraSlice.unpack(inst.data);
            if (slice.start > f.extra.items.len or slice.len > f.extra.items.len - slice.start) return false;
        }
        // A callee's signature is the module's declaration, or one `fits` checked on the artifact's types: only its place is checked here.
        if (inst.op == .call) {
            if (inst.a.index() >= module.functions.items.len) return false;
        } else if (inst.a != .none and inst.a.index() >= f.insts.items.len) return false;
        if (inst.op == .func_ref and inst.data >= module.functions.items.len) return false;
        if (inst.op == .jump and inst.data >= f.blocks.items.len) return false;
        if (inst.op == .branch) {
            const targets = ir.unpackTargets(inst.data);
            if (targets.then.index() >= f.blocks.items.len or targets.otherwise.index() >= f.blocks.items.len) return false;
        }
        if (inst.b != .none and inst.b.index() >= f.insts.items.len) return false;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |i| if (operands.get(i).index() >= f.insts.items.len) return false;
    }
    for (f.loops.items) |loop| {
        const blocks = [_]ir.BlockId{ loop.header, loop.body, loop.latch, loop.exit };
        for (blocks) |block| if (block.index() >= f.blocks.items.len) return false;
    }
    return acyclicCopies(a, f);
}

// Later passes follow forwarding copies. Each instruction is visited at most
// twice here, rejecting malformed cycles before accepting decoded artifacts.
fn acyclicCopies(a: std.mem.Allocator, f: ir.Function) std.mem.Allocator.Error!bool {
    const colors = try a.alloc(u8, f.insts.items.len);
    @memset(colors, 0);
    for (f.insts.items, 0..) |_, start| {
        var current = start;
        while (colors[current] == 0 and f.insts.items[current].op == .copy) {
            colors[current] = 1;
            const next = f.insts.items[current].a;
            if (next == .none) return false;
            current = next.index();
        }
        if (colors[current] == 1) return false;
        current = start;
        while (colors[current] == 1) {
            colors[current] = 2;
            current = f.insts.items[current].a.index();
        }
    }
    return true;
}

/// A function's checked name without the byte offset a lambda carries, which is a relocatable spelling and not an identity.
pub fn normalizedName(name: []const u8) []const u8 {
    // Lambda ordinals and signatures are guarded by the ordered catalog. Their
    // byte-offset suffix is a relocatable symbol spelling, not a declaration ID.
    // Keep actual body keys and final symbols fresh; only catalog/guard names use this.
    if (std.mem.startsWith(u8, name, "lambda@")) {
        const start = if (std.mem.lastIndexOf(u8, name, "::")) |at| at + 2 else "lambda@".len;
        if (start == name.len) return name;
        for (name[start..]) |byte| if (!std.ascii.isDigit(byte)) return name;
        return name[0..start];
    }
    if (std.mem.startsWith(u8, name, render.declaration_prefix)) {
        const tail = name[render.declaration_prefix.len..];
        if (std.mem.indexOfScalar(u8, tail, '_')) |at| return tail[at..];
    }
    return name;
}

fn position(context: snapshot.Context, program: typed.Program, checked: typed.Function, span: u32) Error!Position {
    if (span == 0) return .zero;
    // Declaration spans are headers; local scope/body nodes can extend past them.
    const start = checked.declaration.start;
    const end = @max(checked.declaration.end, program.statements[@backingInt(checked.scope.body)].span.end);
    if (span >= start and span <= end) return .{ .local = @intCast(span - start) };
    return .{ .external = try siteOf(context, span) };
}

/// The position of merged-source offset `span`, named by the file that holds it.
fn siteOf(context: snapshot.Context, span: u32) Error!demand_sources.Site {
    const at = try snapshot.locate(context, span);
    var site: demand_sources.Site = .{ .offset = at.offset };
    if (at.point) |point| site.point = .{ .line = point.line, .column = point.column };
    if (at.origin) |index| {
        const source = context.source orelse return error.InvalidSnapshot;
        if (index >= source.origins.len) return error.InvalidSnapshot;
        site.origin = source.origins[index].original.keyPath();
    }
    return site;
}

/// The last file a restore looked up by name: positions of one function usually sit in one file.
const FileMemo = struct { path: []const u8 = "", index: u32 = 0, known: bool = false };

/// The index in the current source of the one file named `path`; invalid when the source has none or two.
fn originIndex(source: language.source.Source, memo: *FileMemo, path: []const u8) Error!u32 {
    if (memo.known and std.mem.eql(u8, memo.path, path)) return memo.index;
    var found: ?u32 = null;
    for (source.origins, 0..) |origin, index| {
        if (!std.mem.eql(u8, origin.original.keyPath(), path)) continue;
        if (found != null) return error.InvalidSnapshot;
        found = @intCast(index);
    }
    const index = found orelse return error.InvalidSnapshot;
    memo.* = .{ .path = path, .index = index, .known = true };
    return index;
}

/// The offset in the current merged source of a position outside the function.
fn relocateSite(context: snapshot.Context, memo: *FileMemo, site: demand_sources.Site) Error!u32 {
    var location: snapshot.Location = .{ .offset = site.offset };
    if (site.point) |point| location.point = .{ .line = point.line, .column = point.column };
    if (site.origin) |path| location.origin = try originIndex(context.source orelse return error.InvalidSnapshot, memo, path);
    return snapshot.relocate(context, location);
}

fn offset(context: snapshot.Context, memo: *FileMemo, start: usize, value: Position) Error!u32 {
    return switch (value) {
        .zero => 0,
        .local => |delta| std.math.cast(u32, start + delta) orelse error.InvalidSnapshot,
        .external => |site| relocateSite(context, memo, site),
    };
}

fn captureFunction(a: std.mem.Allocator, context: snapshot.Context, program: typed.Program, checked: typed.Function, f: ir.Function) Error!Function {
    const positions = try a.alloc(Position, f.insts.items.len + 1);
    positions[0] = try position(context, program, checked, f.span);
    for (f.insts.items, 0..) |inst, i| positions[i + 1] = try position(context, program, checked, inst.span);
    const blocks = try a.alloc(snapshot.Block, f.blocks.items.len);
    for (blocks, f.blocks.items) |*block, original| block.* = .{ .insts = original.insts.items, .preds = original.preds.items };
    return .{ .value = .{ .name = f.name, .signature = f.signature, .insts = f.insts.items, .blocks = blocks, .extra = f.extra.items, .loops = f.loops.items, .span = f.span }, .positions = positions };
}

fn relocatedString(raw: usize, old: usize, new: usize, count: usize) Error!u32 {
    // Lowering always allocates its literals/private metadata in this function.
    if (raw < old or raw - old >= count) return error.InvalidSnapshot;
    return std.math.cast(u32, new + (raw - old)) orelse error.InvalidSnapshot;
}

/// The type in the live module of the artifact's type `ty`: a leaf type stands for itself, and a compound is a local id.
fn placedType(place: Places, ty: ir.Type) Error!ir.Type {
    if (!ty.isCompound()) return ty;
    const at = @backingInt(ty) - ir.Type.first_compound;
    if (at >= place.types.len) return error.InvalidSnapshot;
    return place.types[at];
}

/// The function in the live module of the artifact's callee `local`.
fn placedFunction(place: Places, local: usize) Error!u32 {
    if (local >= place.functions.len) return error.InvalidSnapshot;
    return place.functions[local];
}

fn restoreFunction(a: std.mem.Allocator, context: snapshot.Context, place: Placement, dto: Function) Error!ir.Function {
    const f = dto.value;
    if (dto.positions.len != f.insts.len + 1 or place.new > context.module.strings.items.len) return error.InvalidSnapshot;
    const count = context.module.strings.items.len - place.new;
    var memo: FileMemo = .{};
    var name = f.name;
    if (std.mem.startsWith(u8, name, render.declaration_prefix)) {
        const tail = name[render.declaration_prefix.len..];
        const at = std.mem.indexOfScalar(u8, tail, '_') orelse return error.InvalidSnapshot;
        const original = std.fmt.parseInt(usize, tail[0..at], 10) catch return error.InvalidSnapshot;
        name = try std.fmt.allocPrint(a, "{s}{d}{s}", .{ render.declaration_prefix, try relocatedString(original, place.old, place.new, count), tail[at..] });
    }
    const insts = try a.dupe(ir.Inst, f.insts);
    for (insts, 0..) |*inst, i| {
        inst.ty = try placedType(place.places, inst.ty);
        if (inst.op == .call) inst.a = @fromBackingInt(try placedFunction(place.places, inst.a.index()));
        if (inst.op == .func_ref) inst.data = try placedFunction(place.places, std.math.cast(usize, inst.data) orelse return error.InvalidSnapshot);
        if (!context.module.valid(inst.ty)) return error.InvalidSnapshot;
        inst.span = try offset(context, &memo, place.start, dto.positions[i + 1]);
        if (inst.op == .str_const) inst.data = try relocatedString(std.math.cast(usize, inst.data) orelse return error.InvalidSnapshot, place.old, place.new, count);
        if (inst.op == .@"unreachable" and inst.data & flags.assertion_trap != 0) inst.data = (inst.data & 0xffffffff00000000) | try relocatedString(@as(u32, @truncate(inst.data)), place.old, place.new, count);
    }
    const blocks = try a.alloc(ir.Block, f.blocks.len);
    for (blocks, f.blocks) |*block, original| block.* = .{
        .insts = .fromOwnedSlice(try a.dupe(ir.Ref, original.insts)),
        .preds = .fromOwnedSlice(try a.dupe(ir.BlockId, original.preds)),
    };
    var sig = try f.signature.clone(a);
    const params = try a.alloc(ir.Type, f.signature.params.len);
    for (params, f.signature.params) |*placed, param| placed.* = try placedType(place.places, param);
    sig.params = params;
    sig.ret = try placedType(place.places, sig.ret);
    if (!validSignature(context.module, sig)) return error.InvalidSnapshot;
    return .{
        .name = try a.dupe(u8, name),
        .signature = sig,
        .span = try offset(context, &memo, place.start, dto.positions[0]),
        .insts = .fromOwnedSlice(insts),
        .blocks = .fromOwnedSlice(blocks),
        .extra = .fromOwnedSlice(try a.dupe(ir.Ref, f.extra)),
        .loops = .fromOwnedSlice(try a.dupe(ir.Loop, f.loops)),
    };
}

fn clone(a: std.mem.Allocator, comptime T: type, value: T) std.mem.Allocator.Error!T {
    return switch (@typeInfo(T)) {
        .pointer => |p| blk: {
            if (p.size != .slice) @compileError("cached tables may only contain slices");
            const out = try a.alloc(p.child, value.len);
            for (out, value) |*copy, original| copy.* = try clone(a, p.child, original);
            break :blk out;
        },
        .@"struct" => |s| blk: {
            var out: T = undefined;
            inline for (s.field_names, s.field_types) |name, F| @field(out, name) = try clone(a, F, @field(value, name));
            break :blk out;
        },
        .@"union" => |u| blk: {
            const tag = std.meta.activeTag(value);
            inline for (u.field_names, u.field_types) |name, F| if (tag == @field(std.meta.Tag(T), name)) break :blk @unionInit(T, name, try clone(a, F, @field(value, name)));
            unreachable;
        },
        else => value,
    };
}

fn frame(hash: *fast_blake3.Blake3, bytes: []const u8) void {
    var len = std.mem.nativeToLittle(u64, bytes.len);
    hash.update(std.mem.asBytes(&len));
    hash.update(bytes);
}

/// Runtime graph links use an explicit path; reflection descends only through
/// the finite checked schema, never recursively through a NodeId or StatementId.
const TreeWalk = struct {
    allocator: std.mem.Allocator,
    pending: std.ArrayList(Task) = .empty,
    active: std.AutoHashMapUnmanaged(Link, void) = .empty,

    const Link = struct { kind: enum { node, statement }, index: usize };
    const Task = union(enum) {
        value: struct { pointer: *const anyopaque, visit: *const fn (*TreeWalk, *TreeHash, *const anyopaque) Error!void },
        byte: u8,
        leave: Link,
    };

    fn run(a: std.mem.Allocator, hash: *TreeHash, comptime T: type, value: T) Error!void {
        var walk: TreeWalk = .{ .allocator = a };
        defer walk.pending.deinit(a);
        defer walk.active.deinit(a);
        try walk.push(T, &value);
        while (walk.pending.pop()) |task| switch (task) {
            .value => |item| try item.visit(&walk, hash, item.pointer),
            .byte => |byte| try hash.value(byte),
            .leave => |target| _ = walk.active.remove(target),
        };
    }

    fn push(self: *TreeWalk, comptime T: type, pointer: *const T) Error!void {
        const Visitor = struct {
            fn visit(walk: *TreeWalk, hash: *TreeHash, erased: *const anyopaque) Error!void {
                const value: *const T = @ptrCast(@alignCast(erased));
                try walk.visit(hash, T, value);
            }
        };
        try self.pending.append(self.allocator, .{ .value = .{ .pointer = @ptrCast(pointer), .visit = Visitor.visit } });
    }

    fn link(self: *TreeWalk, hash: *TreeHash, target: Link) Error!void {
        const limit = if (target.kind == .node) hash.program.nodes.len else hash.program.statements.len;
        if (target.index >= limit) return error.InvalidSnapshot;
        const found = try self.active.getOrPut(self.allocator, target);
        if (found.found_existing) return error.InvalidSnapshot;
        try self.pending.append(self.allocator, .{ .leave = target });
        if (target.kind == .node) try self.push(typed.Node, &hash.program.nodes[target.index]) else try self.push(typed.Statement, &hash.program.statements[target.index]);
    }

    fn arm(self: *TreeWalk, hash: *TreeHash, value: *const typed.MatchArm) Error!void {
        const selector = try matchSelector(hash.program, value.*);
        if (value.unpack) |*unpack| try self.push(@TypeOf(unpack.fields), &unpack.fields);
        try self.pending.append(self.allocator, .{ .byte = selector });
        try self.push(typed.StatementId, &value.body);
        try self.push(?typed.LocalId, &value.slot);
        try self.push(usize, &value.tag);
    }

    fn visit(self: *TreeWalk, hash: *TreeHash, comptime T: type, value: *const T) Error!void {
        if (T == typed.NodeId) return self.link(hash, .{ .kind = .node, .index = @backingInt(value.*) });
        if (T == typed.StatementId) return self.link(hash, .{ .kind = .statement, .index = @backingInt(value.*) });
        if (T == typed.MatchArm) return self.arm(hash, value);
        // A policy holds no node or statement, and `TreeHash.value` hashes its `address` and `freestanding` only when set.
        if (T == language.source.Span or T == typed.Field or T == typed.FunctionPolicy) return hash.value(value.*);
        switch (@typeInfo(T)) {
            .int, .float, .bool, .void, .@"enum" => try hash.value(value.*),
            .optional => |optional| {
                try hash.value(value.* != null);
                if (value.*) |*present| try self.push(optional.child, present);
            },
            .pointer => |ptr| {
                if (ptr.size != .slice) @compileError("checked cache inputs must own slices");
                try hash.value(@as(u64, value.len));
                if (ptr.child == u8) hash.hash.update(value.*) else try self.items(ptr.child, value.*);
            },
            .array => |array| try self.items(array.child, value),
            .@"struct" => |s| inline for (0..s.field_names.len) |index| {
                const name = s.field_names[s.field_names.len - index - 1];
                try self.push(@TypeOf(@field(value.*, name)), &@field(value.*, name));
            },
            .@"union" => |u| {
                const tag = std.meta.activeTag(value.*);
                try hash.value(tag);
                inline for (u.field_names) |name| if (tag == @field(std.meta.Tag(T), name)) try self.push(@TypeOf(@field(value.*, name)), &@field(value.*, name));
            },
            else => @compileError("checked cache input needs explicit hashing: " ++ @typeName(T)),
        }
    }

    fn items(self: *TreeWalk, comptime T: type, values: []const T) Error!void {
        var index = values.len;
        while (index > 0) {
            index -= 1;
            try self.push(T, &values[index]);
        }
    }
};

fn matchSelector(program: typed.Program, arm: typed.MatchArm) Error!u8 {
    const unpack = arm.unpack orelse return 0;
    if (unpack.body == arm.body) return 1;
    if (@backingInt(arm.body) >= program.statements.len) return error.InvalidSnapshot;
    const statement = program.statements[@backingInt(arm.body)];
    if (statement.data != .block or statement.data.block.len == 0) return error.InvalidSnapshot;
    const children = statement.data.block;
    if (children[children.len - 1] != unpack.body) return error.InvalidSnapshot;
    return 2;
}

const TreeHash = struct {
    hash: fast_blake3.Blake3,
    program: typed.Program,
    context: snapshot.Context,
    checked: ?typed.Function,
    local_positions: bool = true,
    proven: bool = true,
    sources: ?*demand_sources.Cache = null,
    proofs: ?*demand_sources.Reach = null,
    /// Declarations the hashed tree names, collected as its values are hashed.
    refs: ?*Refs = null,
    /// When set, a uniquely named function is hashed by its name, not its index.
    identities: ?*const Identities = null,
    /// When set, a record type is hashed by the digest of its name, not by its position in the record table.
    record_keys: ?*const record_names.RecordKeys = null,

    fn init(program: typed.Program, context: snapshot.Context, checked: ?typed.Function) TreeHash {
        return .{ .hash = fast_blake3.Blake3.init(.{}), .program = program, .context = context, .checked = checked };
    }

    fn finish(self: *TreeHash) stage.Digest {
        var out: stage.Digest = undefined;
        self.hash.final(&out);
        return out;
    }

    /// The unpack body is already present in the ordinary arm. Hash it once,
    /// together with the selected body relationship, instead of revisiting each
    /// nested match twice. Unrelated descriptors must never reuse that digest.
    fn matchArm(self: *TreeHash, arm: typed.MatchArm) Error!void {
        const selector = try matchSelector(self.program, arm);
        try self.value(arm.tag);
        try self.value(arm.slot);
        try self.value(arm.body);
        try self.value(selector);
        if (arm.unpack) |unpack| try self.value(unpack.fields);
    }

    /// Hash a record type by the digest of its name when the hash has record names; false when `ty` was left to the caller
    /// (a scalar is hashed as itself, after a tag that tells it from a record).
    fn hashRecordType(self: *TreeHash, ty: typed.Type) bool {
        const keys = self.record_keys orelse return false;
        if (keys.digestOfType(ty)) |digest| {
            self.hash.update(&.{1});
            self.hash.update(&digest);
            return true;
        }
        self.hash.update(&.{0});
        return false;
    }

    /// Collect the declaration a value names, when the hash collects them.
    fn noteDeclaration(self: *TreeHash, comptime T: type, v: T) Error!void {
        const refs = self.refs orelse return;
        if (T == typed.FunctionId) try refs.functions.append(refs.arena, @backingInt(v));
        if (T == typed.Type) try refs.types.append(refs.arena, v);
    }

    /// Hash a uniquely named function by its name; false when it is left to the caller (tagged 0 as its index).
    fn hashFunctionName(self: *TreeHash, id: typed.FunctionId) Error!bool {
        const names = self.identities orelse return false;
        if (names.name(self.program, @backingInt(id))) |stable| {
            self.hash.update(&.{1});
            try self.value(stable);
            return true;
        }
        self.hash.update(&.{0});
        return false;
    }

    fn value(self: *TreeHash, v: anytype) Error!void {
        const T = @TypeOf(v);
        try self.noteDeclaration(T, v);
        if (T == typed.Type) if (self.hashRecordType(v)) return;
        if (T == typed.FunctionId) if (try self.hashFunctionName(v)) return;
        if (T == typed.NodeId) return self.value(self.program.nodes[@backingInt(v)]);
        if (T == typed.StatementId) return self.value(self.program.statements[@backingInt(v)]);
        if (T == typed.MatchArm) return self.matchArm(v);
        if (T == language.source.Span) {
            if (self.checked) |checked| {
                const at = try position(self.context, self.program, checked, std.math.cast(u32, v.start) orelse return error.InvalidSnapshot);
                if (at == .external) {
                    self.local_positions = false;
                    if (self.sources) |sources| {
                        if (!try sources.collect(self.proofs.?, at.external)) self.proven = false;
                    }
                }
                try self.value(at);
                try self.value(v.end - v.start);
            }
            return;
        }
        if (T == typed.Field) {
            try self.value(v.name);
            try self.value(v.ty);
            try self.value(v.boxed);
            // This is a syntax ordinal, not a checked NodeId. Actual defaults
            // are expanded into the caller's checked tree and hashed there.
            try self.value(v.default_value != null);
            return;
        }
        // `address`, `freestanding` and `ram` are hashed only when set, so a function without them keys exactly as
        // before the fields existed.
        if (T == typed.FunctionPolicy) {
            inline for (@typeInfo(T).@"struct".field_names) |name| if (comptime !typed.FunctionPolicy.keyedWhenSet(name)) try self.value(@field(v, name));
            if (v.address) self.hash.update("address");
            if (v.freestanding) |span| {
                self.hash.update("freestanding");
                try self.value(span);
            }
            if (v.ram) self.hash.update("ram");
            return;
        }
        switch (@typeInfo(T)) {
            .int => {
                var little = std.mem.nativeToLittle(T, v);
                self.hash.update(std.mem.asBytes(&little));
            },
            .float => try self.value(@as(@Int(.unsigned, @bitSizeOf(T)), @bitCast(v))),
            .bool => self.hash.update(&.{@intFromBool(v)}),
            .void => {},
            .@"enum" => try self.value(@backingInt(v)),
            .optional => {
                try self.value(v != null);
                if (v) |present| try self.value(present);
            },
            .pointer => |ptr| {
                if (ptr.size != .slice) @compileError("checked cache inputs must own slices");
                try self.value(@as(u64, v.len));
                if (ptr.child == u8) self.hash.update(v) else for (v) |item| try self.value(item);
            },
            .array => for (v) |item| try self.value(item),
            .@"struct" => |s| inline for (s.field_names) |name| try self.value(@field(v, name)),
            .@"union" => |u| {
                const tag = std.meta.activeTag(v);
                try self.value(tag);
                inline for (u.field_names) |name| if (tag == @field(std.meta.Tag(T), name)) try self.value(@field(v, name));
            },
            else => @compileError("checked cache input needs explicit hashing: " ++ @typeName(T)),
        }
    }
};

/// Exact current source authority for replayed offsets, without retaining a body.
/// Bytes before the maximum site determine every local site's line and column.
pub fn sourceProof(source: language.source.Source, span: u32, maximum: u32) snapshot.Error!stage.Digest {
    const mapped = if (source.origins.len == 0) null else source.originalSpan(.{ .start = span, .end = span }) catch return error.InvalidSnapshot;
    const original = if (mapped) |at| source.origins[at.input].original else source;
    const start = if (mapped) |at| at.span.start else span;
    if (start > original.bytes.len or maximum > original.bytes.len - start) return error.InvalidSnapshot;
    // Do not let a mapped slice's extent exceed the original source it attests.
    const point = original.physicalLocation(start);
    var hash = fast_blake3.Blake3.init(.{});
    // The stream is the prefix, the maximum, the line, the column, the key path, a zero byte and the bytes of the span. Everything before the
    // span goes through one buffer and one update (each update is a call into the hash object), the span through a second; a path longer than
    // the buffer leaves room for takes the pieces one by one. The bytes hashed are the same either way.
    var head: [sourceProofHead]u8 = undefined;
    const path = original.keyPath();
    const prefix = "lowered-local-source-v2\x00";
    const fixed = prefix.len + 4 + 8 + 8;
    if (fixed + path.len + 1 <= head.len) {
        @memcpy(head[0..prefix.len], prefix);
        std.mem.writeInt(u32, head[prefix.len..][0..4], maximum, .little);
        std.mem.writeInt(u64, head[prefix.len + 4 ..][0..8], point.line, .little);
        std.mem.writeInt(u64, head[prefix.len + 12 ..][0..8], point.column, .little);
        @memcpy(head[fixed..][0..path.len], path);
        head[fixed + path.len] = 0;
        hash.update(head[0 .. fixed + path.len + 1]);
    } else {
        var numbers: [20]u8 = undefined;
        std.mem.writeInt(u32, numbers[0..4], maximum, .little);
        std.mem.writeInt(u64, numbers[4..12], point.line, .little);
        std.mem.writeInt(u64, numbers[12..20], point.column, .little);
        hash.update(prefix);
        hash.update(&numbers);
        hash.update(path);
        hash.update("\x00");
    }
    hash.update(original.bytes[start..][0..maximum]);
    var digest: stage.Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// The bytes of a source proof's head (its prefix, numbers and key path) that go through one buffer.
const sourceProofHead = 512;

fn sourceMaximum(wire: Wire) ?u32 {
    if (!localPositions(wire)) return null;
    var maximum: u32 = 0;
    for (wire.function.positions) |at| if (at == .local) {
        maximum = @max(maximum, at.local);
    };
    for (wire.delta.requests) |request| if (request == .define) {
        for (request.define.positions) |at| if (at == .local) {
            maximum = @max(maximum, at.local);
        };
    };
    return maximum;
}

test "requestFor describes each function a lowering touched by how another program finds or makes it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const plain: ir.Signature = .{ .params = &.{}, .ret = .void };
    const runtime: ir.Signature = .{ .params = &.{.str}, .ret = .i64, .linkage = .runtime_c };
    try module.functions.appendSlice(a, &.{
        .{ .name = "app::declared", .signature = plain },
        .{ .name = "app::unknown", .signature = plain },
        .{ .name = "myl_core_x", .signature = runtime },
        .{ .name = "app::adapter#value", .signature = plain },
        .{ .name = "twin", .signature = plain },
        .{ .name = "twin", .signature = plain },
        .{ .name = "myl_core_render_shape_0_" ++ "0123456789abcdef0123456789abcdef", .signature = .{ .params = &.{}, .ret = .void, .linkage = .runtime_c } },
        .{ .name = "app::made#value", .signature = plain },
        .{ .name = "myl_core_render_shape_2_" ++ "fedcba9876543210fedcba9876543210", .signature = .{ .params = &.{}, .ret = .void, .linkage = .runtime_c } },
    });
    try module.strings.appendSlice(a, &.{ "one", "two", "three" });
    var made_body: ir.Function = .{ .name = "app::made#value", .signature = plain };
    try made_body.insts.append(a, .{ .op = .call, .ty = .void, .a = @fromBackingInt(2) });
    try made_body.blocks.append(a, .{});
    module.functions.items[7] = made_body;
    var discovery: Discovery = .{};
    var types: std.AutoHashMapUnmanaged(typed.Type, ir.Type) = .empty;
    const program: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0) };
    var recorder = op_log.Recorder.init(a, std.testing.allocator, false);
    defer recorder.deinit();
    const records = try record_names.RecordIndex.init(a, program, null);
    var identities: Identities = .{};
    try identities.by_name.put(a, "app::declared", 0);
    const mb: Context = .{
        .arena = a,
        .input = .{ .program = program, .source = null, .drop_debug = false },
        .module = &module,
        .discovery = &discovery,
        .types = &types,
        .names = .{ .log = &recorder, .records = &records, .builder = undefined },
    };
    try recorder.declared(0, "app::declared");
    try recorder.declared(1, "app::unknown");
    try recorder.begin(&module, .lower, "app::f");
    const capture: Capture = .{ .mb = mb, .before = .{ .functions = 7, .compounds = 0, .strings = 2 }, .checked = undefined, .context = .{ .module = &module }, .identities = &identities };
    var requests: Requests = .{};
    try std.testing.expectEqualStrings("app::declared", (try requestFor(a, capture, &requests, 0)).?.declare);
    try std.testing.expectEqual(@as(?Request, null), try requestFor(a, capture, &requests, 1));
    try std.testing.expectEqualStrings("myl_core_x", (try requestFor(a, capture, &requests, 2)).?.helper.name);
    try std.testing.expectEqualStrings("app::adapter#value", (try requestFor(a, capture, &requests, 3)).?.found.name);
    try std.testing.expectEqual(@as(?Request, null), try requestFor(a, capture, &requests, 4));
    // A shape declaration from before the lowering is found by its id; one it made carries the local string it authorizes.
    try std.testing.expectEqual(@as(?u32, null), (try requestFor(a, capture, &requests, 6)).?.shape.string);
    try std.testing.expectEqual(@as(?u32, 0), (try requestFor(a, capture, &requests, 8)).?.shape.string);
    // A function it made is defined with its body, and the helper that body calls becomes a request of its own.
    const defined = (try requestFor(a, capture, &requests, 7)).?.define;
    try std.testing.expectEqual(@as(usize, 1), defined.value.insts.len);
    try std.testing.expectEqual(@as(u32, 0), requests.local.get(2).?);
}
