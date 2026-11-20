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
const cache_miss = @import("selka").cache_miss;
const typed = @import("selka").typed;
const return_borrow = @import("selka").return_borrow;
const Rule = @import("selka").ownership_rules.Rule;
const Source = @import("selka").source.Source;
const Field = @FieldType(@FieldType(typed.Node, "data"), "field");
const BufferOperation = @FieldType(@FieldType(typed.Node, "data"), "buffer_operation");
const ir = @import("ir.zig");
const fuse = @import("fuse.zig");
const slices = @import("slices.zig");
const flags = @import("flags.zig");
const copy_sites = @import("copy_sites.zig");
const field_moves = @import("field_moves.zig");
const fuse_dict = @import("fuse_dict.zig");
const build_dict = @import("build_dict.zig");
const build_text = @import("build_text.zig");
const build_enum_names = @import("build_enum_names.zig");
const span_forms = @import("span_forms.zig");
const build_view = @import("build_borrowed_view.zig");
const build_list_methods = @import("build_list_methods.zig");
const fuse_text = @import("fuse_text.zig");
const build_cap = @import("build_cap.zig");
const build_chain = @import("build_chain.zig");
const build_task = @import("build_task.zig");
const build_bytes = @import("build_bytes.zig");
const build_fn = @import("build_fn.zig");
const build_values = @import("build_values.zig");
const build_format = @import("build_format.zig");
const single_owner_copy = @import("single_owner_copy.zig");
const alias_places = @import("alias_places.zig");
const build_capture = @import("build_capture.zig");
const lowering_cache = @import("lowering_cache.zig");
const borrow_selection = @import("borrow_selection.zig");
const op_log = @import("op_log.zig");
const lowering_assembly = @import("lowering_assembly.zig");
const lowering_finish = @import("lowering_finish.zig");
const record_names = @import("record_names.zig");
const stable_names = @import("stable_names.zig");

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

/// The first unsupported construct, with a rule only for an ownership limit. `reason` is a noun phrase naming the
/// construct, because the report writes "the new core does not support {reason} yet"; `hint`, when there is one, is
/// a clause saying what the author can do instead, which the report appends after a colon.
pub const Refusal = struct { reason: []const u8 = "", span: u32 = 0, rule: ?Rule = null, hint: []const u8 = "" };

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
/// `debug(...)` lines drop their output, as a `build --release` executable does: such a line still evaluates its arguments
/// in order, and only the formatting and the write to standard error are left out, so a program means the same in every
/// build; `run`, `build --run` and `test` keep the output in every mode.
/// `names` asks any compiler to record the op log of lowering and check it by replay (`op_log.zig`), and receives what
/// it replayed; a debug compiler always does.
/// `callee_roots` lowers every root as an ordinary callee does, with borrowed view parameters: the
/// allocation contract judges the body a build emits for a promised function, and a build calls every
/// function but its entry wrapper (`entry_adapter`, which calls the source `main`) and a test root, whose
/// parameters are capabilities (F19).
/// `compared_returns` names the test functions of a test executable: a `bool` one that ends in `return LEFT op RIGHT`
/// keeps the two values for the runner's report when it returns false (`returnsCompared`, `traceCompared`).
pub const Input = struct {
    program: typed.Program,
    source: ?Source = null,
    drop_debug: bool = false,
    names: ?*op_log.Summary = null,
    callee_roots: bool = false,
    compared_returns: []const typed.FunctionId = &.{},
    /// The build target's pointer width (`Target.pointerBytes`), which every size and offset lowering writes follows.
    pointer_bytes: u32 = 8,
    /// The functions a device's `hooks` bind (MCU-NOC4A): roots beside `main`, at the function indices after it, in this order.
    hooks: []const typed.FunctionId = &.{},
};

/// Build an executable's module from `input`, rooted at the program's `main`.
pub fn buildExecutable(allocator: std.mem.Allocator, input: Input, refusal: *Refusal) Error!ir.Module {
    return buildRootsInput(allocator, try rootsOf(allocator, input), input, refusal);
}

/// `main` and then the functions of the device's hooks: the roots of an executable, in memory from `allocator` (a build's
/// arena). Never `&.{input.program.main}`: `main` is not known at compile time, so that is a pointer into this function's
/// own stack frame, and a compiler built ReleaseFast reads the slot again after the next calls have reused it (GH-7.3).
pub fn rootsOf(allocator: std.mem.Allocator, input: Input) std.mem.Allocator.Error![]const typed.FunctionId {
    const roots = try allocator.alloc(typed.FunctionId, 1 + input.hooks.len);
    roots[0] = input.program.main;
    @memcpy(roots[1..], input.hooks);
    return roots;
}

/// Reuse validated function lowering artifacts, preserving the uncached oracle.
pub fn buildExecutableCached(allocator: std.mem.Allocator, input: Input, refusal: *Refusal, cache: *lowering_cache.Cache) CachedError!ir.Module {
    return buildRootsCached(allocator, try rootsOf(allocator, input), input, refusal, cache);
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
    var handoff: lowering_cache.Handoff = undefined;
    // A record that is declined has already keyed the functions and indexed the program's declarations: the replay is handed both.
    defer if (cache) |stored| {
        stored.engine.handed = null;
    };
    if (cache) |stored| if (try assembled(allocator, roots, input, refusal, stored, &handoff)) |module| return module;
    return replayRoots(allocator, roots, input, refusal, cache);
}

/// Lower selected roots by restoring or building every function in the order the builder discovers them.
fn replayRoots(allocator: std.mem.Allocator, roots: []const typed.FunctionId, input: Input, refusal: *Refusal, cache: ?*lowering_cache.Cache) CachedError!ir.Module {
    const program = input.program;
    // A build keys its receipts by the source it lowers, bound here rather than only when the frontend plans demand: a
    // build with no previous summaries never plans demand, and it still publishes receipts.
    if (cache) |lowering| if (lowering.demand) |queries| queries.bindSource(input.source);
    var mb: ModuleBuilder = .{ .allocator = allocator, .input = input, .refusal = refusal, .module = .{ .lowering = .{ .pointer_bytes = input.pointer_bytes } } };
    defer mb.discovery.ids.deinit(allocator);
    defer mb.types.deinit(allocator);
    defer mb.discovery.pending.deinit(allocator);
    // The log is recorded when it is checked (a debug compiler, `--verify-names`) and when a lowering cache stores or
    // restores artifacts, which are the log's segments. It is kept only to be checked.
    const checking = op_log.enabled or input.names != null;
    var recorder = op_log.Recorder.init(allocator, scratchMemory(allocator, cache), checking);
    defer recorder.deinit();
    recorder.state.segments = checking or cache != null;
    var records: record_names.RecordIndex = undefined;
    try mb.startRecording(&recorder, &records);
    try mb.beginSegment(.roots, "");
    for (roots, 0..) |root, position| {
        const index = if (input.callee_roots) try mb.functionIndex(root) else try mb.rootIndex(root);
        if (position == 0) mb.module.entry = index;
    }
    try mb.endSegment();
    var reuse: ?lowering_cache.Session = if (cache) |store| lowering_cache.Session.prepare(store, mb.lowering()) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidSnapshot => null,
    } else null;
    // Headers held for bodies whose finish never came (an error ended the build first) are written without it.
    defer if (reuse) |*session| session.flush();
    if (reuse == null) if (cache) |stored| if (stored.demand) |queries| if (queries.count() != 0) return cache_miss.at(@src());
    // Freshly lowered bodies and their lowering keys, for the normalization records below.
    var fresh: std.ArrayList(FreshBody) = .empty;
    defer fresh.deinit(allocator);
    var next: usize = 0;
    while (next < mb.discovery.pending.items.len) : (next += 1) {
        const id = mb.discovery.pending.items[next];
        const index = mb.discovery.ids.get(@backingInt(id)).?;
        const function = program.functions[@backingInt(id)];
        if (mb.module.functions.items[index].signature.linkage == .internal) {
            try mb.beginSegment(.lower, function.name);
            // Building may declare callees and grow the table, so store afterwards.
            const built = if (reuse) |*session| blk: {
                var scratch = std.heap.ArenaAllocator.init(session.cache.store.backing);
                defer scratch.deinit();
                const a = scratch.allocator();
                const before = lowering_cache.Before.init(mb.lowering());
                const keyed = try keyFor(session, mb.lowering(), function);
                if (keyed) |known| if (try session.restore(a, known.key, mb.lowering(), function, mb.module.functions.items[index])) |cached| break :blk cached;
                if (session.cache.demand) |queries| if (queries.omitted(id)) return cache_miss.at(@src());
                const built_fresh = try buildFunction(&mb, function, mb.module.functions.items[index]);
                session.cache.counts.lowered += 1;
                if (keyed) |known| _ = try session.remember(a, mb.lowering(), .{ .key = known.key, .body = known.body, .refs = known.refs, .before = before, .checked = function }, built_fresh);
                if (keyed) |known| try fresh.append(allocator, .{ .index = index, .key = known.key });
                break :blk built_fresh;
            } else try buildFunction(&mb, function, mb.module.functions.items[index]);
            try mb.endSegment();
            mb.module.functions.items[index] = built;
        }
    }
    try finishLowered(allocator, &mb.module, input.source, cache, .{ .fresh = fresh.items, .log = mb.log, .session = if (reuse) |*session| session else null });
    // Owner lifetime and direct destruction are handled by `own.zig` after optimization.
    if (cache) |stored| if (stored.demand) |queries| try queries.recordReachable(mb.discovery.pending.items);
    try mb.assignModules();
    try mb.assignPrivacy();
    try mb.assignFreestanding();
    try mb.checkLog(input.names);
    // The optimizer's records find a nominal record again by its name (`optimizer_names.zig`).
    mb.module.nominal = try recorder.nominalDigests(allocator, mb.module.compounds.items.len);
    try keepAssembly(allocator, roots, input, cache, &mb);
    return mb.module;
}

/// The lowering key of `function`, or null when it cannot be keyed (the build then lowers it and stores nothing). A refusal
/// is noted: an omitted body that cannot be keyed is why the build starts again (`cache_miss.zig`).
fn keyFor(session: *lowering_cache.Session, mb: lowering_cache.Context, function: typed.Function) std.mem.Allocator.Error!?lowering_cache.Keyed {
    cache_miss.clear();
    if (session.cache.engine.handed) |handed| if (handed.keyed[@backingInt(function.id)]) |known| {
        // The key a declined attempt made for this function: what the session would make, and the receipt it would note.
        if (session.cache.demand) |queries| try queries.record(function.id, known.key);
        return known;
    };
    return session.key(mb, function) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidSnapshot => {
            cache_miss.note(@src());
            return null;
        },
    };
}

/// Where lowering's scratch memory comes from: the cache's backing allocator when there is a cache, else `fallback`.
fn scratchMemory(fallback: std.mem.Allocator, cache: ?*lowering_cache.Cache) std.mem.Allocator {
    return if (cache) |stored| stored.store.backing else fallback;
}

/// A freshly lowered body and the lowering key its artifact was stored under.
const FreshBody = struct { index: u32, key: [32]u8 };

/// What `finishLowered` knows about the bodies lowering built: the fresh ones, and the op log to extend.
const Finish = struct { fresh: []const FreshBody, log: ?*op_log.Recorder, session: ?*lowering_cache.Session };

/// Normalize every lowered body (`lowering_finish`). Unmaterialized functions receive the same
/// normalization on demand, except that a deferred body whose normalization declares a runtime
/// helper (or is not known not to) is restored here instead, in index order, so the demand table
/// declares the eager table's helpers in its order. Freshly lowered bodies record which they are.
fn finishLowered(allocator: std.mem.Allocator, module: *ir.Module, source: ?Source, cache: ?*lowering_cache.Cache, bodies: Finish) CachedError!void {
    const fresh_keys = try allocator.alloc(?[32]u8, module.functions.items.len);
    defer allocator.free(fresh_keys);
    @memset(fresh_keys, null);
    for (bodies.fresh) |entry| fresh_keys[entry.index] = entry.key;
    const lazy = if (cache) |stored| stored.lazy else null;
    for (0..module.functions.items.len) |index| {
        if (lazy) |state| if (index < state.tables.loaded.items.len and !state.tables.loaded.items[index]) {
            // A deferred body is restored, or left alone, without the log hearing of it.
            if (bodies.log) |log| log.abandon();
            if (!state.finishesPlain(index)) try state.materializeAt(module, source, index);
            continue;
        };
        if (bodies.log) |log| try log.begin(module, .finish, module.functions.items[index].name);
        const helpers = try @import("lowering_finish.zig").functionTracked(allocator, module, index);
        if (bodies.log) |log| try log.end(module);
        if (bodies.session) |session| if (fresh_keys[index]) |key| try lowering_cache.rememberFinish(session, key, helpers);
        if (lazy) |state| if (fresh_keys[index] != null and index < state.tables.finish.items.len) {
            state.tables.finish.items[index].plain = !helpers;
        };
    }
}

/// Whether `cache` may assemble this lowering from a record, or keep one: the engine decides the build, it restores deferred headers
/// rather than complete trees, nothing watches or checks the lowering function by function, and the build is an executable's.
fn assemblable(roots: []const typed.FunctionId, input: Input, cache: *const lowering_cache.Cache) bool {
    if (!cache.engine.assembly or cache.engine.observed != null) return false;
    if (input.names != null or input.callee_roots or input.source == null) return false;
    const lazy = cache.lazy orelse return false;
    return !lazy.force_eager and roots.len == 1 and roots[0] == input.program.main;
}

/// The file of the assembly record of this build: named by the program's entry source, its mode and the compiler.
fn assemblyPath(allocator: std.mem.Allocator, input: Input, cache: *const lowering_cache.Cache) std.mem.Allocator.Error!?[]const u8 {
    const source = input.source orelse return null;
    const main = input.program.functions[@backingInt(input.program.main)].name;
    const identity = cache.store.key("lowering-assembly-v1", &.{ source.keyPath(), &.{@intFromBool(input.drop_debug)}, main, "zero-rc" });
    return lowering_assembly.pathOf(allocator, cache.store, identity);
}

/// Keep the tables this lowering ended with for the next build (`lowering_assembly.zig`), when every function was restored from a
/// header. A record that cannot be made or written costs the next build its warmth and nothing else.
fn keepAssembly(allocator: std.mem.Allocator, roots: []const typed.FunctionId, input: Input, cache: ?*lowering_cache.Cache, mb: *ModuleBuilder) std.mem.Allocator.Error!void {
    const stored = cache orelse return;
    if (!assemblable(roots, input, stored)) return;
    const path = try assemblyPath(allocator, input, stored) orelse return;
    const record = try lowering_assembly.capture(allocator, &mb.module, stored.lazy.?, &mb.discovery.ids) orelse return;
    lowering_assembly.write(allocator, stored.store.io, path, record);
}

/// What lowering one function alone found: its effects on the tables, the strings and the proofs of its artifact, and whether
/// finishing its body declares a runtime helper.
pub const Lowered = struct { effects: [32]u8, string_start: u64, string_count: u64, source_max: ?u32, proofs: []const @import("demand_sources.zig").Proof, helpers: bool };

/// A module of its own in which functions are lowered one by one for their artifacts alone (`lowering_assembly.zig`): each is
/// declared, built, captured and stored as it would be in the program, and nothing of the program is built around it.
pub const Standalone = struct {
    mb: ModuleBuilder,
    recorder: op_log.Recorder,
    records: record_names.RecordIndex,

    /// A standalone module for `input`; `allocator` is the lowering's arena and `backing` the store's allocator.
    pub fn create(allocator: std.mem.Allocator, backing: std.mem.Allocator, input: Input, refusal: *Refusal) Error!*Standalone {
        const self = try allocator.create(Standalone);
        errdefer allocator.destroy(self);
        self.* = .{ .mb = .{ .allocator = allocator, .input = input, .refusal = refusal }, .recorder = op_log.Recorder.init(allocator, backing, false), .records = undefined };
        errdefer self.recorder.deinit();
        self.recorder.state.segments = true;
        try self.mb.startRecording(&self.recorder, &self.records);
        return self;
    }

    /// Lower `function` (keyed `keyed`) and store its artifact through `session`. Null when its artifact cannot be captured or it is not
    /// an internal function; an unsupported construct refuses as the program's lowering would.
    pub fn lower(self: *Standalone, session: *lowering_cache.Session, function: typed.Function, keyed: lowering_cache.Keyed) Error!?Lowered {
        const mb = &self.mb;
        try mb.beginSegment(.roots, "");
        const index = if (function.id == mb.input.program.main) try mb.rootIndex(function.id) else try mb.functionIndex(function.id);
        try mb.endSegment();
        if (mb.module.functions.items[index].signature.linkage != .internal) return null;
        try mb.beginSegment(.lower, function.name);
        const before = lowering_cache.Before.init(mb.lowering());
        const built = try buildFunction(mb, function, mb.module.functions.items[index]);
        const remembered = try session.remember(mb.allocator, mb.lowering(), .{ .key = keyed.key, .body = keyed.body, .refs = keyed.refs, .before = before, .checked = function }, built);
        try mb.endSegment();
        mb.module.functions.items[index] = built;
        const helpers = try lowering_finish.functionTracked(mb.allocator, &mb.module, index);
        const done = remembered orelse return null;
        try lowering_cache.rememberFinish(session, keyed.key, helpers);
        return .{ .effects = done.effects, .string_start = done.string_start, .string_count = done.string_count, .source_max = done.source_max, .proofs = done.sources, .helpers = helpers };
    }
};

/// The state function keys are made in while a record is held against the program: a copy of the cache that has neither the receipts nor
/// the deferred tables (nothing is noted until the record holds), a module nothing is lowered into, and the session that keys.
const Keying = struct {
    cache: lowering_cache.Cache,
    module: ir.Module = .{},
    discovery: lowering_cache.Discovery = .{},
    types: std.AutoHashMapUnmanaged(typed.Type, ir.Type) = .empty,
    context: lowering_cache.Context = undefined,
    session: lowering_cache.Session = undefined,

    /// Start keying `input`'s functions in place; false when no session can be made.
    fn open(self: *Keying, allocator: std.mem.Allocator, input: Input, cache: *const lowering_cache.Cache) std.mem.Allocator.Error!bool {
        self.* = .{ .cache = cache.* };
        self.cache.demand = null;
        self.cache.lazy = null;
        self.context = .{
            .arena = allocator,
            .input = .{ .program = input.program, .source = input.source, .drop_debug = input.drop_debug },
            .module = &self.module,
            .discovery = &self.discovery,
            .types = &self.types,
        };
        const made = if (cache.engine.parts != null) lowering_cache.Session.prepareKeys(&self.cache, self.context) else lowering_cache.Session.prepare(&self.cache, self.context);
        self.session = made catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidSnapshot => return false,
        };
        return true;
    }
};

/// One attempt to assemble a lowering from a record: the build, the keys, and what the functions whose key moved turned out to be.
const Attempt = struct {
    allocator: std.mem.Allocator,
    input: Input,
    refusal: *Refusal,
    cache: *lowering_cache.Cache,
    keying: *Keying,
    path: []const u8,
    work: Work = .{},

    const Work = struct { standalone: ?*Standalone = null, updates: std.ArrayList(lowering_assembly.Update) = .empty, stored: usize = 0 };

    /// What lowering the function at `index` of the record alone found, from its stored header or by lowering it; null when the record
    /// cannot stand for it (the function was omitted from the checked program, or its finish declares a helper).
    fn lowerChanged(self: *Attempt, found: lowering_assembly.Plan, index: u32) CachedError!?Lowered {
        const function = self.input.program.functions[@backingInt(found.ids[index])];
        if (self.cache.demand) |queries| if (queries.omitted(function.id)) return null;
        const keyed = found.keyed[index];
        if (try lowering_cache.storedHeader(self.cache.store, self.allocator, keyed.key)) |header| {
            self.work.stored += 1;
            if (header.helpers != false) return null;
            return .{
                .effects = header.effects,
                .string_start = header.string_start,
                .string_count = header.string_count,
                .source_max = header.source_max,
                .proofs = header.proofs,
                .helpers = false,
            };
        }
        if (self.work.standalone == null) self.work.standalone = Standalone.create(self.allocator, self.cache.store.backing, self.input, self.refusal) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => return null,
        };
        return self.work.standalone.?.lower(&self.keying.session, function, keyed) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => return null,
        };
    }

    /// Lower the functions whose key moved and require each one to have left the tables as the record has them.
    fn settle(self: *Attempt, found: lowering_assembly.Plan) CachedError!bool {
        for (found.changed) |index| {
            const placed = found.head.entries[index].placed.?;
            if (placed.plain != true) return false;
            const lowered = try self.lowerChanged(found, index) orelse return false;
            if (lowered.helpers or !std.mem.eql(u8, &lowered.effects, &placed.effects) or lowered.string_count != placed.slot.string_count) return false;
            try self.work.updates.append(self.allocator, .{
                .entry = index,
                .effects = lowered.effects,
                .string_start = lowered.string_start,
                .string_count = lowered.string_count,
                .source_max = lowered.source_max,
                .proofs = lowered.proofs,
            });
        }
        return true;
    }

    /// Note the program in the deferred tables from the record, place the bodies that are loaded in any build, and give the receipts and
    /// the counters what a replay would have. Null when the module does not come out as the record's (the deferred tables are reset).
    fn adopt(self: *Attempt, found: lowering_assembly.Plan, tail: lowering_assembly.Tail) CachedError!?ir.Module {
        const lazy = self.cache.lazy.?;
        const record = found.head;
        const module = try lowering_assembly.assemble(self.allocator, found, tail, self.input.program, lazy, self.work.updates.items);
        var mb: ModuleBuilder = .{ .allocator = self.allocator, .input = self.input, .refusal = self.refusal, .module = module };
        const before = mb.module.functions.items.len;
        var next: usize = 0;
        for (record.entries, 0..) |entry, index| {
            const placed = entry.placed orelse continue;
            try mb.discovery.ids.put(self.allocator, @backingInt(found.ids[index]), @intCast(index));
            const changed = next < found.changed.len and found.changed[next] == index;
            if (changed) next += 1;
            if (placed.defines) lazy.fillDefined(&mb.module, self.input.source, index) catch |err| return abandoned(lazy, err);
            if (changed or placed.plain != true) lazy.materializeAt(&mb.module, self.input.source, index) catch |err| return abandoned(lazy, err);
        }
        if (mb.module.functions.items.len != before) return abandoned(lazy, error.CacheMiss);
        try self.note(found, lazy);
        try mb.assignModules();
        try mb.assignPrivacy();
        try mb.assignFreestanding();
        if (found.changed.len != 0) if (try lowering_assembly.capture(self.allocator, &mb.module, lazy, &mb.discovery.ids)) |kept| lowering_assembly.write(self.allocator, self.cache.store.io, self.path, kept);
        return mb.module;
    }

    /// What a replay leaves besides the module: the receipts, the headers this build needs without having read them (compaction drops
    /// what no build needed while receipts still say a body may be omitted), the counters and the record for the next build.
    fn note(self: *Attempt, found: lowering_assembly.Plan, lazy: *lowering_cache.Deferred) std.mem.Allocator.Error!void {
        const record = found.head;
        const headers = try self.allocator.alloc([32]u8, record.entries.len);
        var wanted: usize = 0;
        var reached: std.ArrayList(typed.FunctionId) = .empty;
        for (record.entries, 0..) |entry, index| {
            if (entry.placed == null) continue;
            headers[wanted] = lowering_cache.headerKey(self.cache.store, lazy.tables.keys.items[index].?);
            wanted += 1;
            try reached.append(self.allocator, found.ids[index]);
            if (self.cache.demand) |queries| {
                try queries.record(found.ids[index], lazy.tables.keys.items[index].?);
                try queries.addSources(found.ids[index], lazy.tables.sources.items[index]);
            }
        }
        self.cache.store.need(headers[0..wanted]);
        if (self.cache.demand) |queries| try queries.recordReachable(reached.items);
        self.cache.counts.reused += wanted - found.changed.len + self.work.stored;
        self.cache.counts.lowered += found.changed.len - self.work.stored;
    }
};

/// The lowering of the program assembled from the record the last one left, when that record still describes it (`lowering_assembly.zig`):
/// every function keyed, those whose key moved lowered alone, and the tables taken from the record if those left them as they were. Null
/// (nothing changed, nothing recorded) when the build must replay.
fn assembled(allocator: std.mem.Allocator, roots: []const typed.FunctionId, input: Input, refusal: *Refusal, cache: *lowering_cache.Cache, handoff: *lowering_cache.Handoff) CachedError!?ir.Module {
    if (!assemblable(roots, input, cache)) return null;
    const path = try assemblyPath(allocator, input, cache) orelse return null;
    var held = try lowering_assembly.read(allocator, cache.store.io, path) orelse return null;
    var keying: Keying = undefined;
    if (!try keying.open(allocator, input, cache)) return null;
    defer keying.session.flush();
    const keyed = try allocator.alloc(?lowering_cache.Keyed, input.program.functions.len);
    @memset(keyed, null);
    handoff.* = .{ .declarations = keying.session.declarations, .keyed = keyed };
    // Whatever way the attempt ends short of an assembly, the replay finds the keys it made. A key made without the engine's parts is made
    // from the complete checked trees, which a body the front end left out does not have: only part keys are handed over.
    var adopted = false;
    defer if (!adopted and cache.engine.parts != null) {
        cache.engine.handed = handoff;
    };
    const found = try lowering_assembly.plan(allocator, held.head, &keying.session, keying.context, keyed) orelse return null;
    var attempt: Attempt = .{ .allocator = allocator, .input = input, .refusal = refusal, .cache = cache, .keying = &keying, .path = path };
    defer if (attempt.work.standalone) |lone| lone.recorder.deinit();
    if (!try attempt.settle(found)) return null;
    // The record holds, so its tables are wanted: they are decoded only now, a build that replays instead never reads them.
    const tail = try held.tail() orelse return null;
    // From here a failure resets what was noted and returns to the replay.
    const module = try attempt.adopt(found, tail) orelse return null;
    adopted = true;
    cache.engine.assembled = true;
    return module;
}

/// Give an assembly up after it began to note the program in the deferred tables: reset them and replay, unless memory ran out.
const AssemblyError = std.mem.Allocator.Error || error{CacheMiss};

fn abandoned(lazy: *lowering_cache.Deferred, err: AssemblyError) std.mem.Allocator.Error!?ir.Module {
    lazy.tables = .{};
    cache_miss.clear();
    if (err == error.OutOfMemory) return error.OutOfMemory;
    return null;
}

/// How one checked function fared: built (its Core IR), or the reason it was refused.
pub const Outcome = struct {
    name: []const u8,
    refusal: ?[]const u8,
    rule: ?Rule = null,
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
        const index = mb.functionIndex(function.id) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => {
                outcome.refusal = refusal.reason;
                outcome.rule = refusal.rule;
                continue;
            },
        };
        outcome.function = buildFunction(&mb, function, mb.module.functions.items[index]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Unsupported => blk: {
                outcome.refusal = refusal.reason;
                outcome.rule = refusal.rule;
                break :blk null;
            },
        };
        outcome.module = mb.module;
    }
    return outcomes;
}

/// The `ir.Signature.owned` bits of a function whose parameters (`unit` ones included)
/// are `all` and whose `mut` or `own` parameters sit at `mutated`/`own`: a `mut`
/// parameter is passed by value and returned, so the call hands it over, and an
/// `own` parameter takes its argument outright (bits count passed parameters only).
fn ownedParameters(a: std.mem.Allocator, all: []const ir.Type, function: typed.Function, program: typed.Program) std.mem.Allocator.Error!ir.ParameterPassing {
    var passing: ir.ParameterPassing = .{};
    for (all, function.scope.locals[0..all.len], 0..) |_, local_info, position| {
        const mutated = std.mem.indexOfScalar(u16, function.signature.declared_mutates, @intCast(position)) != null;
        const affine = @import("single_owner_resource.zig").affine(program, local_info.ty);
        if (!takenParameter(mutated, affine, ownParameter(function, position))) continue;
        var passed: usize = 0;
        for (all[0..position]) |param| passed += @intFromBool(param != .void);
        if (position < all.len and all[position] != .void) try passing.setOwned(a, passed);
    }
    return passing;
}

/// Whether a source `extern func` result has a C ABI: nothing, a scalar, or `bytes` the runtime copies (D-FFI-3).
fn externResult(declared: ir.Type) bool {
    return declared == .void or declared.integer() != null or declared == .bool or declared == .f64 or declared == .bytes;
}

/// Whether a source `extern func` parameter has a C ABI: a capability (dropped), a scalar, or a lent text or byte span.
fn externParameter(param: ir.Type) bool {
    return param == .cap or param.integer() != null or param == .bool or param == .f64 or param == .str or param == .bytes;
}

/// Whether a parameter is handed over by the call: a written `mut` position, an
/// affine (move-only) value, or an `own` declaration.
fn takenParameter(mutated: bool, affine: bool, own: bool) bool {
    return mutated or affine or own;
}

/// Whether parameter `position` of `function` takes its argument (`own`).
fn ownParameter(function: typed.Function, position: usize) bool {
    if (position >= function.scope.own_parameters.len) return false;
    return function.scope.own_parameters[position];
}

/// Whether parameter `position` of `function`, mapped to `mapped`, is a plain `str`, `bytes` or list an internal
/// function reads as a borrowed view: not `mut` (it is never written), not `own` (it is never given away) and not
/// move-only (a move-only value is handed over, `ownedParameters`). Such a parameter is passed as a view, so a
/// caller's slice is not copied (C9 str, bytes and lists).
fn viewParameter(module: *const ir.Module, program: typed.Program, function: typed.Function, position: usize, mapped: ir.Type) bool {
    if (mapped != .str and mapped != .bytes and module.kind(mapped) != .list and return_borrow.step(program.records, function.scope.locals[position].ty) == null) return false;
    if (std.mem.indexOfScalar(u16, function.signature.declared_mutates, @intCast(position)) != null) return false;
    if (@import("single_owner_resource.zig").affine(program, function.scope.locals[position].ty)) return false;
    return !ownParameter(function, position);
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
    /// The owning-type table of the checked program (R3b), built on first use by a match's scrutinee.
    linear_types: ?[]bool = null,
    /// The fielded case payload records of the checked program (1A, `BorrowedRecords.casePayloads`), built on first use.
    case_payloads: ?[]bool = null,
    /// The op log being recorded (`op_log.zig`); null when this build does not record.
    log: ?*op_log.Recorder = null,
    /// The names of the program's records, while recording.
    records: ?*const record_names.RecordIndex = null,
    /// The position-free identities of the types helpers are named by.
    type_keys: stable_names.TypeKeys = .{},
    /// The checked name of the function being lowered, and how many functions of each family it has made.
    creator: []const u8 = "",
    made: [std.enums.values(stable_names.GeneratedRole).len]u32 = @splat(0),

    /// The program's owned record types (`single_owner.ownedTypesOf`), computed once per module.
    pub fn linearTypes(self: *ModuleBuilder) Error![]const bool {
        if (self.linear_types == null) self.linear_types = try @import("single_owner.zig").ownedTypesOf(self.allocator, self.input.program);
        return self.linear_types.?;
    }

    /// The program's fielded case payload records (`BorrowedRecords.casePayloads`), computed once per module.
    pub fn casePayloads(self: *ModuleBuilder) Error![]const bool {
        if (self.case_payloads == null) self.case_payloads = try @import("single_owner.zig").BorrowedRecords.casePayloads(self.allocator, self.input.program);
        return self.case_payloads.?;
    }

    fn lowering(self: *ModuleBuilder) lowering_cache.Context {
        const input = self.input;
        return .{
            .arena = self.allocator,
            .input = .{ .program = input.program, .source = input.source, .drop_debug = input.drop_debug },
            .module = &self.module,
            .discovery = &self.discovery,
            .types = &self.types,
            .names = if (self.log) |log| .{ .log = log, .records = self.records.?, .builder = .{ .context = self, .declare = declareHook, .refuse = refuseHook } } else null,
        };
    }

    /// A restore declares a checked function as this builder would.
    fn declareHook(context: *anyopaque, id: typed.FunctionId) Error!u32 {
        const self: *ModuleBuilder = @ptrCast(@alignCast(context));
        return self.functionIndex(id);
    }

    /// A restore refuses the build: a stored lowering that cannot be placed after the module has changed.
    fn refuseHook(context: *anyopaque, reason: []const u8) error{Unsupported} {
        const self: *ModuleBuilder = @ptrCast(@alignCast(context));
        self.refusal.* = .{ .reason = reason, .span = 0 };
        return error.Unsupported;
    }

    /// Record an unsupported feature at its source position.
    pub fn refuse(self: *ModuleBuilder, reason: []const u8, span: u32) Error {
        self.refusal.* = .{ .reason = reason, .span = span };
        return error.Unsupported;
    }

    /// Record an ownership operation the builder cannot lower safely.
    pub fn refuseOwnership(self: *ModuleBuilder, reason: []const u8, span: u32) Error {
        self.refusal.* = .{ .reason = reason, .span = span, .rule = .Z3 };
        return error.Unsupported;
    }

    /// Record an ownership operation the builder cannot lower safely, with what the author can do instead.
    pub fn refuseOwnershipHint(self: *ModuleBuilder, reason: []const u8, hint: []const u8, span: u32) Error {
        self.refusal.* = .{ .reason = reason, .span = span, .rule = .Z3, .hint = hint };
        return error.Unsupported;
    }

    /// Refuse an `@address` extern whose integer target is wider than the build target's addresses: `u64` where they
    /// are 32 bits (`thumbv6m-none`). A `u32` target is accepted everywhere: where addresses are 64 bits it is
    /// zero-extended into the pointer, so a device library that declares its ROM calls with `u32` still builds, and
    /// tests, on the host. An `extern type` handle carries a C pointer on every target. The checker has already accepted
    /// the type as a handle, `u32` or `u64` (`sema.zig` `addressTarget`).
    fn addressWidth(self: *ModuleBuilder, function: typed.Function) Error!void {
        const target = function.scope.locals[1].ty;
        if (target != .u64 or self.input.pointer_bytes != 4) return;
        return self.refuse("an `@address` extern target of `u64` on a target whose addresses are 32 bits: declare it `u32`", @intCast(function.scope.locals[1].declaration.start));
    }

    /// The IR index of checked function `id`, declared on first use (E1b tasks name their callee by it).
    pub fn functionIndex(self: *ModuleBuilder, id: typed.FunctionId) Error!u32 {
        return self.declare(id, true);
    }

    /// The IR index of a root (the entry point or a test), whose signature keeps the owned
    /// `str` parameters its C caller passes.
    fn rootIndex(self: *ModuleBuilder, id: typed.FunctionId) Error!u32 {
        return self.declare(id, false);
    }

    /// Declare checked function `id`. `view_abi` lets its plain `str` parameters take a
    /// borrowed view (`viewParameter`); a root never does.
    fn declare(self: *ModuleBuilder, id: typed.FunctionId, view_abi: bool) Error!u32 {
        if (self.discovery.ids.get(@backingInt(id))) |index| {
            try self.touch(index);
            return index;
        }
        const function = self.input.program.functions[@backingInt(id)];
        if (self.viewType(function.signature.return_type)) return self.refuse("a live dictionary view as a checked return type", @intCast(function.declaration.start));
        const span: u32 = @intCast(function.declaration.start);
        const linkage: ir.Linkage = if (function.policy.address) .extern_address else if (function.policy.c_abi) .extern_c else if (function.policy.host != null) return self.refuse("host function", span) else .internal;
        if (linkage == .extern_address) try self.addressWidth(function);
        const all = try self.allocator.alloc(ir.Type, function.signature.parameter_count);
        for (all, function.scope.locals[0..all.len], 0..) |*param, local, position| {
            param.* = try self.mapType(local.ty, @intCast(local.declaration.start));
            // `parallel.map` and its family take a text, bytes or list parameter as its view (FR59), which the map's worker
            // reads in place; any other parameter keeps its own type, which the map lends as before.
            const plain = param.* == .str or param.* == .bytes or self.module.kind(param.*) == .list;
            const viewed_function = view_abi and linkage == .internal and (plain or !@import("build_parallel.zig").matches(self.input.source, function));
            if (viewed_function and viewParameter(&self.module, self.input.program, function, position, param.*)) {
                param.* = try self.readOnlyParameter(local.ty, param.*, span);
            }
        }
        // A `unit` parameter carries nothing, so it is not passed.
        var passed: std.ArrayList(ir.Type) = .empty;
        for (all) |param| if (param != .void) try passed.append(self.allocator, param);
        // Each borrowed `str` or list parameter takes its owner as a trailing parameter (C9 S1, C9 lists): the positions
        // of the passed parameters are unchanged, so every index the signature keeps (owned, view source, mut) still holds.
        var with_owners: std.ArrayList(ir.Type) = .empty;
        try with_owners.appendSlice(self.allocator, passed.items);
        if (view_abi and linkage == .internal) for (passed.items) |param| {
            if (try build_fn.ownerOf(&self.module, self.allocator, param)) |owner| try with_owners.append(self.allocator, owner);
        };
        const params = with_owners.items;
        const declared = try self.mapType(function.signature.return_type, span);
        if (linkage.externC()) {
            for (params) |param| if (!externParameter(param)) return self.refuse("source extern aggregate ABI", span);
            if (!externResult(declared)) return self.refuse("source extern aggregate ABI", span);
            // A `mut` out-parameter is a scalar or handle behind a pointer (D-FFI-5); a copied `bytes` result takes none.
            for (function.signature.declared_mutates) |position| {
                const scalar = all[position].integer() != null or all[position] == .bool or all[position] == .f64;
                if (!scalar or declared == .bytes) return self.refuseOwnership("mut parameter of an extern function that is not a scalar or handle out-parameter", span);
            }
        }
        const logical = try self.logicalReturnType(function, span);
        const ret = try self.returnType(function, logical, all, span);
        if (linkage.externC() and self.module.passedInMemory(ret)) return self.refuseOwnership("more out-parameters of an extern function than fit in registers", span);
        const index: u32 = @intCast(self.module.functions.items.len);
        var passing = try ownedParameters(self.allocator, all, function, self.input.program);
        // A source extern's `str` and `bytes` parameters take the borrowed span ABI: `(data, length)`, lent for the call.
        if (linkage.externC()) for (params, 0..) |param, position| {
            if (param == .str or param == .bytes) try passing.setView(self.allocator, position);
        };
        const contract = try self.lendingSources(try self.resultBorrow(function, all), params, ret);
        try self.module.functions.append(self.allocator, .{ .name = function.name, .signature = .{ .params = params, .ret = ret, .linkage = linkage, .passing = passing, .borrow = contract }, .span = span });
        if (self.log) |log| try log.declared(index, function.name);
        try self.discovery.ids.put(self.allocator, @backingInt(id), index);
        try self.discovery.pending.append(self.allocator, id);
        try self.touch(index);
        return index;
    }

    /// The logical result representation is derived only from its declared borrowing clause.
    /// Read-only collection parameters and standard wrapper spines borrow their payloads.
    pub fn readOnlyParameter(self: *ModuleBuilder, ty: typed.Type, mapped: ir.Type, span: u32) Error!ir.Type {
        if (try build_fn.viewOf(&self.module, self.allocator, mapped)) |view| return view;
        if (return_borrow.step(self.input.program.records, ty) == null) return mapped;
        if (try self.spineHoldsBuffer(ty, span)) return mapped;
        return self.readOnlySpine(ty, span);
    }

    /// Whether a payload of the standard wrapper spine `ty`, at any depth, is a byte buffer (FR92). A byte buffer has no
    /// view a caller can lend: a plain one stays owned (`build_fn.viewOf`), and Core makes a bytes view only of `bytes`. A
    /// spine that holds one stays owned too, so its payload binding is the same buffer a plain parameter is.
    fn spineHoldsBuffer(self: *ModuleBuilder, ty: typed.Type, span: u32) Error!bool {
        if (return_borrow.step(self.input.program.records, ty) == null) {
            const leaf = try self.mapType(ty, span);
            return leaf == .byte_buffer;
        }
        const variants = self.input.program.records[ty.recordIndex()].shape.variants.?;
        for (variants.cases) |case| if (case.payload) |payload| {
            if (try self.spineHoldsBuffer(payload, span)) return true;
        };
        return false;
    }

    fn readOnlySpine(self: *ModuleBuilder, ty: typed.Type, span: u32) Error!ir.Type {
        if (return_borrow.step(self.input.program.records, ty) != null) {
            const record = self.input.program.records[ty.recordIndex()];
            const variants = record.shape.variants.?;
            const mapped = try self.mapType(ty, span);
            const cases = try self.allocator.dupe(ir.Type, self.module.compound(mapped).@"union");
            for (variants.cases, 0..) |case, index| if (case.payload) |payload| {
                cases[index] = try self.readOnlySpine(payload, span);
            };
            // A spine whose payloads are all unchanged is the front end's own union, not a structurally equal one.
            if (std.mem.eql(ir.Type, cases, self.module.compound(mapped).@"union")) return mapped;
            return self.module.intern(self.allocator, .{ .@"union" = cases });
        }
        const shape = return_borrow.shape(self.input.program.records, .{ .return_type = ty, .return_origin = .{ .params = &.{0} } });
        return self.borrowedSpine(ty, shape.kind, span);
    }

    fn logicalReturnType(self: *ModuleBuilder, function: typed.Function, span: u32) Error!ir.Type {
        const shape = return_borrow.shape(self.input.program.records, function.signature);
        if (shape.kind == .none) return self.mapType(function.signature.return_type, span);
        return self.borrowedSpine(function.signature.return_type, shape.kind, span);
    }

    fn borrowedSpine(self: *ModuleBuilder, ty: typed.Type, kind: return_borrow.Kind, span: u32) Error!ir.Type {
        if (return_borrow.step(self.input.program.records, ty)) |step| {
            const owned = try self.mapType(ty, span);
            const cases = try self.allocator.dupe(ir.Type, self.module.compound(owned).@"union");
            cases[step.tag] = try self.borrowedSpine(step.payload, kind, span);
            if (std.mem.eql(ir.Type, cases, self.module.compound(owned).@"union")) return owned;
            return self.module.intern(self.allocator, .{ .@"union" = cases });
        }
        return switch (kind) {
            .text => .str_view,
            .bytes => .bytes_view,
            .list => self.listViewType(ty),
            .value => self.module.borrowedType(self.allocator, try self.mapType(ty, span)),
            .none => self.mapType(ty, span),
        };
    }

    /// `contract` without its sources that cannot lend the result: a source that holds no storage of the result's leaf
    /// (`Module.borrowCompatible`), such as a plain text or bytes parameter, which is passed as a view (`viewParameter`) and
    /// lends only a text or bytes view, or a list of another element type (lane HC). The checker lets no data of such a
    /// source reach the result (`E_BORROW_MIXED`, `E_SINGLE_OWNER_BORROW`), so it keeps nothing alive. A contract whose every
    /// source is such a one is kept whole: no source can lend its result, and the checker refuses it (E_BORROW_SOURCE).
    fn lendingSources(self: *ModuleBuilder, contract: ir.BorrowContract, params: []const ir.Type, ret: ir.Type) Error!ir.BorrowContract {
        if (contract.sources.len == 0) return contract;
        const leaf = self.module.projectedType(ret, contract.path) orelse return contract;
        var kept: std.ArrayList(ir.BorrowSource) = .empty;
        for (contract.sources) |source| {
            const lends = switch (source) {
                .argument => |position| position >= params.len or self.module.borrowCompatible(params[position], leaf),
                .result => |path| if (self.module.projectedType(ret, path)) |owner| self.module.borrowCompatible(owner, leaf) else true,
            };
            if (lends) try kept.append(self.allocator, source);
        }
        if (kept.items.len == 0 or kept.items.len == contract.sources.len) return contract;
        return .{ .path = contract.path, .sources = try kept.toOwnedSlice(self.allocator) };
    }

    fn resultBorrow(self: *ModuleBuilder, function: typed.Function, all: []const ir.Type) Error!ir.BorrowContract {
        const positions = return_borrow.effectiveSources(self.input.program.records, function.signature);
        if (positions.len == 0) return .{};
        var path: std.ArrayList(ir.BorrowProjection) = .empty;
        const mutated = function.signature.declared_mutates;
        if (mutated.len != 0) try path.append(self.allocator, .{ .field = 0 });
        var current = function.signature.return_type;
        while (return_borrow.step(self.input.program.records, current)) |step| {
            try path.append(self.allocator, .{ .payload = @intCast(step.tag) });
            current = step.payload;
        }
        var sources: std.ArrayList(ir.BorrowSource) = .empty;
        for (positions) |position| {
            if (position >= all.len) return self.refuse("invalid declared borrow source", @intCast(function.declaration.start));
            if (std.mem.indexOfScalar(u16, mutated, position)) |changed| {
                const owner = try self.allocator.dupe(ir.BorrowProjection, &.{.{ .field = @intCast(changed + 1) }});
                try sources.append(self.allocator, .{ .result = owner });
            } else {
                var passed: u32 = 0;
                for (all[0..position]) |parameter| if (parameter != .void) {
                    passed += 1;
                };
                try sources.append(self.allocator, .{ .argument = passed });
            }
        }
        return .{ .path = try path.toOwnedSlice(self.allocator), .sources = try sources.toOwnedSlice(self.allocator) };
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
            // Every capability is a scalar handle (5C): the provider state lives in the runtime's table until the process or
            // the test trial ends, so copies share it and nothing in the program destroys it.
            .host_cap, .stream_cap, .input_cap, .clock_cap, .random_cap, .filesystem_cap, .network_cap, .environment_cap, .process_cap, .stop_cap, .registers_cap => .cap,
            .file, .text_file => .resource,
            .task_group => try build_task.groupType(&self.module, self.allocator),
            .task_handle => .i64,
            else => self.mapAggregate(ty, span),
        };
    }

    fn mapAggregate(self: *ModuleBuilder, ty: typed.Type, span: u32) Error!ir.Type {
        const records = self.input.program.records;
        if (!ty.isAggregate()) return self.refuse(if (ty.isFile()) "file handle type" else "capability type", span);
        if (ty.recordIndex() >= records.len) return self.refuse("type", span);
        const record = records[ty.recordIndex()];
        if (record.isCollection()) switch (record.collection.kind) {
            .string => return .str,
            .list => {
                if (self.viewType(record.shape.buffer.?)) return self.refuse("a live dictionary view as a checked list element", span);
                const element = try self.mapType(record.shape.buffer.?, span);
                // A list of `None` holds nothing but its length: a list of `false`, whose elements read as unit.
                return self.module.intern(self.allocator, .{ .list = if (element == .void) .bool else element });
            },
            .dictionary => {
                const source_key = try self.mapType(record.collection.key.?, span);
                const key: ir.Type = if (source_key == .void) .bool else source_key;
                if (!build_dict.keySupported(self.module, key)) return self.refuse("dictionary key type", span);
                if (!record.collection.set and self.viewType(record.shape.buffer.?)) return self.refuse("a live dictionary view as a checked dictionary value", span);
                const value = if (record.collection.set) .void else try self.mapType(record.shape.buffer.?, span);
                return self.module.intern(self.allocator, .{ .dict = .{ .key = key, .value = value } });
            },
            .bytes => return if (std.mem.eql(u8, record.name, "byte_buffer")) build_bytes.bufferType(self, span) else .bytes,
        };
        if (record.shape.builtin == .foreign_handle) return .u64;
        if (record.shape.domain != null and std.mem.eql(u8, record.name, "float")) return .f64;
        if (record.shape.domain != null and std.mem.eql(u8, record.name, "f32")) return .f32;
        if (record.shape.variants) |variants| return self.mapUnion(ty, variants, span);
        if (record.contract.callback) |callback| return build_fn.mapCallable(self, callback, span);
        if (record.shape.array) |array| {
            if (self.viewType(array.element)) return self.refuse("a live dictionary view as a checked fixed array element", span);
            const elem = try self.mapType(array.element, span);
            const n = std.math.cast(u32, array.length) orelse return self.refuse("fixed array length", span);
            return self.module.intern(self.allocator, .{ .array = .{ .elem = if (elem == .void) .bool else elem, .n = n, .vector = array.vector } });
        }
        if (record.shape.resource != null) return .resource;
        // User scalar domains are rejected before Core; float and callbacks
        // retain their internal wrapper shapes and were handled above.
        if (record.shape.domain != null) return self.refuse("removed scalar domain", span);
        if (record.isManagedRecord()) return self.refuse("class type", span);
        return self.mapRecord(ty, record, span);
    }

    /// The runtime text helpers that take a span form (`span_forms.redirects`).
    const span_redirects = span_forms.redirects;

    /// Whether a text position of `params` (mask `texts`) is a borrowed view: only such a call takes a span form
    /// of a `views_only` helper.
    fn hasView(params: []const ir.Type, texts: u64) bool {
        for (params, 0..) |param, position| {
            if (position < 64 and (texts >> @intCast(position)) & 1 != 0 and param.isSpan()) return true;
        }
        return false;
    }

    /// The runtime symbol a call to `symbol` with `params` declares: its span form when it has one
    /// (`span_redirects`) and each of its text positions is a text argument, otherwise `symbol` itself.
    fn spanRedirect(symbol: []const u8, params: []const ir.Type) []const u8 {
        for (span_redirects) |form| {
            if (!std.mem.eql(u8, form.text, symbol)) continue;
            var owned_bytes = false;
            for (params, 0..) |param, position| {
                if (position >= 64 or (form.texts >> @intCast(position)) & 1 == 0) continue;
                switch (param) {
                    .str, .str_view, .bytes_view => {},
                    // An owned bytes argument is the block the helper reads: a call with no view keeps its block form.
                    .bytes => owned_bytes = true,
                    else => return symbol,
                }
            }
            if (owned_bytes and !hasView(params, form.texts)) return symbol;
            if (form.views_only and !hasView(params, form.texts)) return symbol;
            return form.span;
        }
        return symbol;
    }

    /// The IR index of runtime `symbol`, declared with this linkage and signature on first use.
    pub fn runtimeFunction(self: *ModuleBuilder, text_symbol: []const u8, params: []const ir.Type, ret: ir.Type, linkage: ir.Linkage) Error!u32 {
        const symbol = spanRedirect(text_symbol, params);
        var owned: u64 = 0;
        var views: u64 = 0;
        {
            const boundary = @import("zero_rc.zig").contract(symbol) orelse
                return self.refuse(try std.fmt.allocPrint(self.allocator, "unaudited zero-RC runtime helper {s}", .{symbol}), 0);
            const owning_result = boundary.result == .fresh or boundary.result == .transferred;
            const nullable_owner = self.module.kind(ret) == .@"union" and self.module.unionLayout(ret).form == .niche;
            if (owning_result != (self.module.isBlock(ret) or nullable_owner)) return self.refuse("zero-RC runtime result contract mismatch", 0);
            if ((boundary.result == .borrowed) != ret.isSpan()) return self.refuse("zero-RC runtime borrow contract mismatch", 0);
            owned = boundary.owned;
            views = boundary.views;
            if (owned != 0) {
                const valid_result = boundary.result == .transferred or boundary.result == .scalar;
                if (params.len == 0) return self.refuse("zero-RC runtime transfer contract mismatch", 0);
                if (!self.module.isBlock(self.module.storageType(params[0])) or !valid_result) return self.refuse("zero-RC runtime transfer contract mismatch", 0);
            }
        }
        // A borrowed text argument is declared as the owned `str` parameter the helper takes: its span
        // form (`views`) reads the same octets, and a helper without one receives a materialized copy
        // (`view_materialize`), so a view argument never changes the declared signature.
        const declared = try self.allocator.dupe(ir.Type, params);
        for (declared) |*param| {
            param.* = self.module.storageType(param.*);
            if (param.* == .str_view) param.* = .str else if (param.* == .bytes_view) param.* = .bytes;
        }
        // One declaration per symbol and signature: a runtime function over lists of several element
        // types has a Core IR signature for each, which are one `ptr` function to LLVM.
        for (self.module.functions.items, 0..) |function, index| {
            if (function.signature.linkage != linkage or !std.mem.eql(u8, function.name, symbol)) continue;
            if (function.signature.ret == ret and std.mem.eql(ir.Type, function.signature.params, declared)) {
                try self.touch(@intCast(index));
                return @intCast(index);
            }
        }
        const index: u32 = @intCast(self.module.functions.items.len);
        var borrowing: ir.BorrowContract = .{};
        if (self.module.isView(ret)) {
            var sources: std.ArrayList(ir.BorrowSource) = .empty;
            for (declared, 0..) |parameter, position| if ((self.module.managed(parameter) or self.module.isView(parameter)) and self.module.borrowCompatible(parameter, ret)) {
                try sources.append(self.allocator, .{ .argument = @intCast(position) });
            };
            borrowing.sources = try sources.toOwnedSlice(self.allocator);
        }
        try self.module.functions.append(self.allocator, .{ .name = symbol, .signature = .{ .params = declared, .ret = ret, .linkage = linkage, .passing = .{ .owned = owned, .views = views }, .borrow = borrowing } });
        try self.touch(index);
        return index;
    }

    /// Reserve the IR type of a checked record or union before its parts are mapped.
    fn reserve(self: *ModuleBuilder, ty: typed.Type) Error!ir.Type {
        const reserved: ir.Type = @fromBackingInt(@intCast(ir.Type.first_compound + self.module.compounds.items.len));
        try self.module.compounds.append(self.allocator, .{ .record = &.{} });
        try self.types.put(self.allocator, ty, reserved);
        if (self.log) |log| try log.reserved(reserved, self.records.?.nameOf(ty).?);
        return reserved;
    }

    /// Start recording into `recorder`, naming the program's records in `records`. The recorder always runs: it knows the
    /// nominal types that helpers are named by (`helperName`); whether it opens segments is its own setting.
    fn startRecording(self: *ModuleBuilder, recorder: *op_log.Recorder, records: *record_names.RecordIndex) Error!void {
        records.* = try record_names.RecordIndex.init(self.allocator, self.input.program, self.input.source);
        self.log = recorder;
        self.records = records;
        self.type_keys.nominals = recorder.nominalNames();
        recorder.attach(&self.module, records);
    }

    /// The id of the render descriptor of source type `source` laid out as `physical`: the text of a key of the two, and
    /// `_v` for a list view. A record is keyed by its name, so the id holds no position of the checked or Core tables.
    pub fn renderId(self: *ModuleBuilder, source: typed.Type, physical: ir.Type, view: bool) Error![]const u8 {
        var hash = std.crypto.hash.Blake3.init(.{});
        if (if (self.records) |index| index.nameOf(source) else null) |record| {
            hash.update("record");
            hash.update(record.module);
            hash.update("\x00");
            hash.update(record.name);
            hash.update(std.mem.asBytes(&record.ordinal));
        } else {
            hash.update("scalar");
            hash.update(std.mem.asBytes(&source));
        }
        hash.update(&try self.type_keys.key(self.allocator, &self.module, physical));
        var digest: stable_names.TypeKey = undefined;
        hash.final(&digest);
        return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ stable_names.keyText(digest), if (view) "_v" else "" });
    }

    /// Say that lowering has just obtained the function at `index` (declared, found or made): a function request of the
    /// segment being recorded.
    pub fn touch(self: *ModuleBuilder, index: u32) Error!void {
        if (self.log) |log| try log.touchedFunction(index);
    }

    /// The name of the next function of family `role` (a task thunk or a `parallel.map` worker) that the function being
    /// lowered makes: the family, an ordinal local to that function and its checked name, so it holds no table position.
    pub fn generatedName(self: *ModuleBuilder, role: stable_names.GeneratedRole, family: []const u8) Error![]const u8 {
        const ordinal = self.made[@backingInt(role)];
        self.made[@backingInt(role)] += 1;
        return std.fmt.allocPrint(self.allocator, "<{s}.{d}@{s}>", .{ family, ordinal, self.creator });
    }

    /// The name of a compiler helper of family `prefix` for `types`, which holds no table position
    /// (`stable_names.helperName`).
    pub fn helperName(self: *ModuleBuilder, prefix: []const u8, types: []const ir.Type) Error![]const u8 {
        return stable_names.helperName(self.allocator, &self.type_keys, &self.module, prefix, types);
    }

    /// Open an op log segment, when recording.
    fn beginSegment(self: *ModuleBuilder, phase: op_log.Phase, owner: []const u8) Error!void {
        if (self.log) |log| try log.begin(&self.module, phase, owner);
    }

    /// Close the open op log segment, when recording.
    fn endSegment(self: *ModuleBuilder) Error!void {
        if (self.log) |log| try log.end(&self.module);
    }

    /// Stop recording. When the log was kept, replay it and require the module to equal what it replays, and say what it
    /// held.
    fn checkLog(self: *ModuleBuilder, summary: ?*op_log.Summary) Error!void {
        const log = self.log orelse return;
        log.detach(&self.module);
        if (!log.state.keep) return;
        const complete = log.state.complete;
        if (complete) if (try log.verify(self.allocator, &self.module)) |mismatch| {
            const reason = try std.fmt.allocPrint(self.allocator, "an op log that does not replay: {s} differ at {d}", .{ mismatch.table, mismatch.index });
            return self.refuse(reason, 0);
        };
        if (summary) |out| out.* = log.summary(complete, if (self.records) |records| records.ambiguous else 0);
    }

    /// The key path of the module whose source holds merged offset `start`; empty without a source or outside it.
    fn moduleOf(self: *const ModuleBuilder, start: usize) []const u8 {
        return record_names.moduleOf(self.input.source, start);
    }

    /// Set `Function.module` of every function lowering made: a checked function by its declaration, a compiler-made
    /// one by the site of the function it was made for. A runtime helper belongs to no module. The text is the module's own copy,
    /// one per module: the key path it names lives in the merged source, which is released before the optimizer starts.
    fn assignModules(self: *ModuleBuilder) std.mem.Allocator.Error!void {
        var owned: std.StringHashMapUnmanaged([]const u8) = .empty;
        defer owned.deinit(self.allocator);
        for (self.module.functions.items) |*function| {
            if (function.signature.linkage != .runtime_c and function.span != 0) function.module = try self.ownedModule(&owned, self.moduleOf(function.span));
        }
        var declared = self.discovery.ids.iterator();
        while (declared.next()) |entry| {
            const function = &self.module.functions.items[entry.value_ptr.*];
            function.module = try self.ownedModule(&owned, self.moduleOf(self.input.program.functions[entry.key_ptr.*].declaration.start));
        }
    }

    /// The copy of module text `text` that lives as long as the lowering's memory, made once for each distinct text in `owned`.
    fn ownedModule(self: *ModuleBuilder, owned: *std.StringHashMapUnmanaged([]const u8), text: []const u8) std.mem.Allocator.Error![]const u8 {
        if (text.len == 0) return "";
        const slot = try owned.getOrPut(self.allocator, text);
        if (!slot.found_existing) slot.value_ptr.* = try self.allocator.dupe(u8, text);
        return slot.value_ptr.*;
    }

    /// Record the names of the functions the check found private to their modules (`typed.Program.private`), so the emitter's linkage
    /// rule (spec section 17.5) can read them without the checked program. A name that a visible function shares is left out.
    fn assignPrivacy(self: *ModuleBuilder) std.mem.Allocator.Error!void {
        const private = self.input.program.private;
        if (private.len == 0) return;
        var visible: std.AutoHashMapUnmanaged(u128, void) = .empty;
        defer visible.deinit(self.allocator);
        var declared = self.discovery.ids.iterator();
        while (declared.next()) |entry| {
            const id = entry.key_ptr.*;
            if (id < private.len and private[id]) continue;
            try visible.put(self.allocator, ir.Module.nameKey(self.module.functions.items[entry.value_ptr.*].name), {});
        }
        declared = self.discovery.ids.iterator();
        while (declared.next()) |entry| {
            const id = entry.key_ptr.*;
            if (id >= private.len or !private[id]) continue;
            // A device's hook is named by the C-ABI function the entry unit writes, from another unit.
            if (std.mem.indexOfScalar(typed.FunctionId, self.input.hooks, @fromBackingInt(@intCast(id))) != null) continue;
            const key = ir.Module.nameKey(self.module.functions.items[entry.value_ptr.*].name);
            if (!visible.contains(key)) try self.module.private.put(self.allocator, key, {});
        }
    }

    /// Record the names of the `@freestanding` functions (`ir.Module.freestanding`), so the emitter lowers their failed
    /// checks to faults and checks their text without the checked program.
    fn assignFreestanding(self: *ModuleBuilder) std.mem.Allocator.Error!void {
        const functions = self.input.program.functions;
        var declared = self.discovery.ids.iterator();
        while (declared.next()) |entry| {
            const id = entry.key_ptr.*;
            if (id >= functions.len or functions[id].policy.freestanding == null) continue;
            const key = ir.Module.nameKey(self.module.functions.items[entry.value_ptr.*].name);
            try self.module.freestanding.put(self.allocator, key, {});
            if (functions[id].policy.ram) try self.module.ram.put(self.allocator, key, {});
        }
    }

    /// The IR type a view binding holds: a borrowed text span, or the borrowed
    /// elements of a list (wave 3: a slice is a view).
    pub fn viewOf(self: *ModuleBuilder, local: typed.Local) Error!ir.Type {
        if (!local.ty.isAggregate() or local.ty.recordIndex() >= self.input.program.records.len) return .str_view;
        const record = self.input.program.records[local.ty.recordIndex()];
        if (record.isCollection() and record.collection.kind == .bytes) return .bytes_view;
        if (!record.isCollection() or record.collection.kind != .list) return .str_view;
        return self.listViewType(local.ty);
    }

    /// The IR view of the elements of checked list type `ty`.
    pub fn listViewType(self: *ModuleBuilder, ty: typed.Type) Error!ir.Type {
        if (!ty.isAggregate() or ty.recordIndex() >= self.input.program.records.len) return .str_view;
        const source = self.input.program.records[ty.recordIndex()].shape.buffer orelse return .str_view;
        const element = try self.mapType(source, 0);
        return self.module.intern(self.allocator, .{ .list_view = if (element == .void) .bool else element });
    }

    fn viewType(self: *ModuleBuilder, ty: typed.Type) bool {
        return ty.isAggregate() and ty.recordIndex() < self.input.program.records.len and self.input.program.records[ty.recordIndex()].shape.builtin == .live_view;
    }

    /// The type a field or payload is stored as: its own type, or a `box` of it when it closes a recursive type.
    fn stored(self: *ModuleBuilder, ty: typed.Type, boxed: bool, span: u32) Error!ir.Type {
        if (self.viewType(ty)) return self.refuse("a live dictionary view as a checked aggregate field", span);
        const mapped = try self.mapType(ty, span);
        if (!boxed or mapped == .void) return mapped;
        return self.module.intern(self.allocator, .{ .box = mapped });
    }

    fn mapRecord(self: *ModuleBuilder, ty: typed.Type, record: typed.Record, span: u32) Error!ir.Type {
        if (self.types.get(ty)) |known| {
            if (self.log) |log| try log.touched(&self.module, known);
            return known;
        }
        const reserved = try self.reserve(ty);
        const fields = try self.allocator.alloc(ir.Type, record.fields.len);
        for (record.fields, fields) |field, *out| {
            out.* = self.stored(field.ty, field.boxed, span) catch |err| return self.unreserve(ty, err);
            if (out.* == .void) out.* = .bool;
        }
        self.module.compounds.items[@backingInt(reserved) - ir.Type.first_compound] = .{ .record = fields };
        if (self.log) |log| try log.filled(&self.module, reserved);
        return reserved;
    }

    /// Mapping `ty` failed: forget its reservation, so a later use is refused again instead of finding an empty type.
    fn unreserve(self: *ModuleBuilder, ty: typed.Type, err: Error) Error {
        _ = self.types.remove(ty);
        return err;
    }

    /// A union, `Option`, `Result` or payload-free enum: one IR case per checked case, in the checker's order.
    fn mapUnion(self: *ModuleBuilder, ty: typed.Type, variants: typed.Variants, span: u32) Error!ir.Type {
        if (self.types.get(ty)) |known| {
            if (self.log) |log| try log.touched(&self.module, known);
            return known;
        }
        const reserved = try self.reserve(ty);
        const cases = try self.allocator.alloc(ir.Type, variants.cases.len);
        for (variants.cases, cases) |case, *out| {
            out.* = if (case.payload) |payload| self.stored(payload, case.boxed, span) catch |err| return self.unreserve(ty, err) else .void;
        }
        self.module.compounds.items[@backingInt(reserved) - ir.Type.first_compound] = .{ .@"union" = cases };
        if (self.log) |log| try log.filled(&self.module, reserved);
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
    /// The `mut` locals that hold a borrow (4f, `build_const_borrow.prepare`): every store adapts to the borrowed slot.
    borrowed_mut: std.AutoHashMapUnmanaged(u32, void) = .empty,
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
/// A `const` binding's place with the root's write count and the loop depth at the binding.
const Projection = struct { place: Place, version: u32, depth: usize };
/// One place a `match mut` assignment writes, with the value expression that gives it (C1).
const ExclusiveLeaf = struct { place: Place, node: typed.NodeId };

/// The two values an `assert`'s comparison compared, kept for its failure path (F-18); `.none` when there are none.
const Compared = struct { left: ir.Ref = .none, right: ir.Ref = .none };

/// FR91: one statement's groups of field moves (`field_moves.zig`) and, for each record a group opened, its field reads.
const FieldMoves = struct {
    groups: field_moves.Groups = .{},
    opened: std.ArrayList(struct { root: usize, fields: []const ir.Ref }) = .empty,
};

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
    /// The cache owner of each borrowed `str` parameter, by its view value: the trailing `str` parameter that
    /// the call passes with the span (C9 S1). A slice or any other view has none and uses the sentinel.
    view_owner: std.AutoHashMapUnmanaged(u32, ir.Ref) = .empty,
    /// The frame header that serves a parameter's scalar lookups, by its view value (C9 S1, `text_frame`), and the frame box of a
    /// read-only record parameter a lent option holds (O4, `box_frame`), by its parameter value.
    frames: std.AutoHashMapUnmanaged(u32, ir.Ref) = .empty,
    /// The entry value of each borrowed `str` parameter, by its variable. A parameter is never assigned, so every
    /// read of it is its entry value: no loop phi stands between a lookup and the parameter's owner (C9 S1).
    view_params: std.AutoHashMapUnmanaged(u32, ir.Ref) = .empty,
    /// The payload bindings of `match mut` arms (C1): an assignment to one writes through its place into the matched value.
    exclusive_locals: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// FR91: the field moves of the statement being lowered that leave one record together, and the records opened so far.
    field_moves: FieldMoves = .{},
    /// The `const` bindings that name a place of a record (R2 disjoint fields): a read after the record was written, or inside a
    /// loop entered after the binding, projects the place again from the record's current value instead of reusing the borrow
    /// the binding took, so no borrow outlives the update of the record it was read from.
    projected: std.AutoHashMapUnmanaged(u32, Projection) = .empty,
    /// What the body does to the record of each such binding after it is made (`alias_places.compute`), by slot; found when the first
    /// binding of a borrowed place asks, so a function with none pays nothing.
    projectable: ?[]const alias_places.Flags = null,
    /// Which record constructors of the function are borrowed values (1A), built on first use.
    borrowed_records: ?@import("single_owner.zig").BorrowedRecords = null,
    /// Which locals of the function are borrowed collections (RB2), built by `build_const_borrow.prepare`.
    borrowed_collections: ?@import("single_owner.zig").BorrowedCollections = null,
    /// Set while a `match mut` binding's assignment writes its place (C1): a union payload on that path is taken out
    /// (`union_take`) and rebuilt, not read through a borrow, so the element is updated without a copy.
    exclusive_write: bool = false,
    /// Set while a `match mut` scrutinee is lowered (C1): its element read is a place read, as an element update's is.
    exclusive_scrutinee: bool = false,
    /// The group local each task handle local was submitted to (E1b): a handle's `result` reads that group.
    task_groups: std.AutoHashMapUnmanaged(u32, u32) = .empty,

    /// The allocation context for feature builders.
    pub fn allocator(self: *FnBuilder) std.mem.Allocator {
        return self.mb.allocator;
    }

    /// The cache owner that scalar lookups of borrowed text `view` use (C9 S1): a plain parameter's frame header
    /// (created on first use and attached to the entry block by `attachFrames`), or the static sentinel.
    pub fn viewOwner(self: *FnBuilder, view: ir.Ref) Error!ir.Ref {
        const at = self.function.resolve(view);
        const owner = self.view_owner.get(@intCast(at.index())) orelse return self.detached(.{ .op = .text_sentinel, .ty = .str });
        if (self.frames.get(@intCast(at.index()))) |frame| return frame;
        const frame = try self.detached(.{ .op = .text_frame, .ty = .str, .a = owner, .b = at });
        try self.frames.put(self.allocator(), @intCast(at.index()), frame);
        return frame;
    }

    /// The owner a call passes with borrowed text `value` (C9 S1): a plain parameter passes its own owner
    /// unchanged; a slice or other view passes the sentinel.
    pub fn passedOwner(self: *FnBuilder, value: ir.Ref) Error!ir.Ref {
        const at = self.function.resolve(value);
        if (self.view_owner.get(@intCast(at.index()))) |owner| return owner;
        // A slice has no owner: a text view passes the text sentinel, a list view the list sentinel (C9 lists).
        const owner_type = (try build_fn.ownerOf(&self.mb.module, self.allocator(), self.typeOfRef(value))) orelse .str;
        return self.detached(.{ .op = .text_sentinel, .ty = owner_type });
    }

    /// The checked node used by feature builders.
    pub fn nodeOf(self: *FnBuilder, id: typed.NodeId) typed.Node {
        return self.mb.input.program.nodes[@backingInt(id)];
    }

    /// The checked statement `id`.
    pub fn nodeOfStatement(self: *FnBuilder, id: typed.StatementId) typed.Statement {
        return self.mb.input.program.statements[@backingInt(id)];
    }

    fn statementOf(self: *FnBuilder, id: typed.StatementId) typed.Statement {
        return self.mb.input.program.statements[@backingInt(id)];
    }

    /// Refuse a source feature with its exact reason.
    pub fn refuse(self: *FnBuilder, reason: []const u8, span: u32) Error {
        return self.mb.refuse(reason, span);
    }

    /// Refuse an ownership operation with its build-time limit rule.
    pub fn refuseOwnership(self: *FnBuilder, reason: []const u8, span: u32) Error {
        return self.mb.refuseOwnership(reason, span);
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
        // A list view written into an owned list local makes that local a view (C9 lists): a loop's source is only read
        // and never reassigned, so the phis that carry it are views too, and no owned phi receives a view.
        if (value != .none and self.mb.module.kind(self.typeOfRef(value)) == .list_view and self.mb.module.kind(self.ssa.types.items[variable]) == .list) {
            self.ssa.types.items[variable] = self.typeOfRef(value);
        }
        try self.ssa.defs.put(self.allocator(), key(block, variable), value);
    }

    /// Read an SSA local in a feature builder block.
    pub fn read(self: *FnBuilder, variable: u32, block: ir.BlockId) Error!ir.Ref {
        if (self.view_params.get(variable)) |value| return value;
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
        _ = self;
        _ = span;
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
            if (self.places.contains(self.local(slot))) return self.mb.refuseOwnership("rebinding a live dictionary view", @intCast(local_info.declaration.start));
            if (place == null) return self.mb.refuseOwnership("live dictionary view with unproved source identity", @intCast(local_info.declaration.start));
            if (place) |source| {
                var aliases = self.places.iterator();
                while (aliases.next()) |entry| {
                    if (entry.key_ptr.* < self.checked.scope.locals.len) continue;
                    if (entry.value_ptr.root == source.root) return self.mb.refuseOwnership("ordinary dictionary snapshot combined with a live view", @intCast(local_info.declaration.start));
                }
                if (source.steps.len != 0) return self.mb.refuseOwnership("live dictionary view of an interior place", @intCast(local_info.declaration.start));
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
                        return self.mb.refuseOwnership("ordinary dictionary snapshot combined with a live view", @intCast(local_info.declaration.start));
                    }
                }
                try self.places.put(self.allocator(), @as(u32, @intCast(self.checked.scope.locals.len)) + self.local(slot), source);
            };
            // Ordinary named bindings are values; a `match mut` payload binding is a place of the matched value (C1).
            if (!self.exclusive_locals.contains(self.local(slot))) return;
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
        // A borrowed text is counted in its scalars by the view helper, without an owned copy (C9 str).
        const raw_length = if (ty == .str_view) try self.viewScalarCount(receiver, span) else if (ty == .str) try self.stringChars(receiver, span) else try self.emit(.{
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
    /// A `match mut` binding's place as its uses see it now: the container's current version (C1).
    fn currentPlace(self: *FnBuilder, place: Place) Error!Place {
        var fresh = place;
        fresh.root_version = self.version(place.root);
        return fresh;
    }

    /// The place a `match mut` initializer names: an exclusive binding, or a field of one. Null for any other value (C1).
    fn exclusiveAliasOf(self: *FnBuilder, id: typed.NodeId) Error!?Place {
        const n = self.nodeOf(id);
        return switch (n.data) {
            .local => |slot| self.places.get(self.local(slot)),
            .field => |field| if (try self.exclusiveAliasOf(field.base)) |base| try self.extendPlace(base, .{ .field = @intCast(field.index) }) else null,
            else => null,
        };
    }

    /// Whether `id` is the binding `slot` or a field of it, so an update over it rebuilds that binding's place (C1).
    fn rootedAtBinding(self: *FnBuilder, id: typed.NodeId, slot: typed.LocalId) bool {
        const n = self.nodeOf(id);
        return switch (n.data) {
            // A compiler temporary that copies the binding names the same place.
            .local => |bound| bound == slot or self.namesSamePlace(self.local(bound), self.local(slot)),
            .field => |field| self.rootedAtBinding(field.base, slot),
            else => false,
        };
    }

    /// Whether two locals alias the same place (C1).
    fn namesSamePlace(self: *FnBuilder, left: u32, right: u32) bool {
        const a = self.places.get(left) orelse return false;
        const b = self.places.get(right) orelse return false;
        if (a.root != b.root or a.steps.len != b.steps.len) return false;
        for (a.steps, b.steps) |x, y| if (!std.meta.eql(x, y)) return false;
        return true;
    }

    /// The initializer of a `match mut` binding names its place: no value is read, the binding aliases it (C1).
    fn exclusiveStore(self: *FnBuilder, store: typed.Store, span: u32, assign: bool) Error!void {
        if (!assign) {
            const place = (try self.exclusiveAliasOf(store.value)) orelse return self.mb.refuse("match mut binding without a place", span);
            return self.noteAlias(store.slot, place);
        }
        const target = self.places.get(self.local(store.slot)) orelse return self.mb.refuse("match mut binding without a place", span);
        var leaves: std.ArrayList(ExclusiveLeaf) = .empty;
        try self.exclusiveLeaves(store.slot, target, store.value, &leaves);
        const values = try self.allocator().alloc(ir.Ref, leaves.items.len);
        for (leaves.items, values) |leaf, *value| value.* = try self.expression(leaf.node);
        self.exclusive_write = true;
        defer self.exclusive_write = false;
        for (leaves.items, values) |leaf, value| _ = try self.storePlace(leaf.place, value, span);
        try self.refreshExclusiveAliases();
    }

    /// Split an assignment to a `match mut` binding into the places it writes: an update over the binding writes each of
    /// its fields, and any other value writes the whole place (C1).
    fn exclusiveLeaves(self: *FnBuilder, slot: typed.LocalId, target: Place, id: typed.NodeId, leaves: *std.ArrayList(ExclusiveLeaf)) Error!void {
        const n = self.nodeOf(id);
        if (n.data == .update and self.rootedAtBinding(n.data.update.base, slot)) {
            for (n.data.update.fields) |field| {
                const child = try self.extendPlace(target, .{ .field = @intCast(field.index) });
                try self.exclusiveLeaves(slot, child, field.value, leaves);
            }
            return;
        }
        try leaves.append(self.allocator(), .{ .place = target, .node = id });
    }

    /// Every `match mut` binding names its place after a write: the container's version moved, so its place is refreshed.
    fn refreshExclusiveAliases(self: *FnBuilder) Error!void {
        var keys = self.exclusive_locals.keyIterator();
        while (keys.next()) |entry| if (self.places.getPtr(entry.*)) |place| {
            place.root_version = self.version(place.root);
        };
    }

    fn storeStatement(self: *FnBuilder, store: typed.Store, span: u32, assign: bool) Error!void {
        if (store.unpack != null) return self.unpackStore(store, span, assign);
        if (self.exclusive_locals.contains(self.local(store.slot))) return self.exclusiveStore(store, span, assign);
        // A `const` handle records the group its submit joins, so its `result` can read that group (E1b).
        switch (self.nodeOf(store.value).data) {
            .task_submit => |submitted| try build_task.bindHandle(self, store.slot, submitted.group),
            else => {},
        }
        try self.refreshEntryReceiver(store, span, assign);
        if (store.element) {
            const kind = self.mb.module.kind(self.ssa.types.items[self.local(store.slot)]);
            if (kind != .array and kind != .record) return self.mb.refuse("element store", span);
        }
        try self.guardViewRebind(self.local(store.slot), span);
        if (assign) try self.prepareOptionalWriteback(store, span);
        if (!assign) if (self.borrowed_collections) |table| {
            if (table.holds(self.local(store.slot))) return self.storeLentCollection(table, store, span);
            // The value an element write into a collection of borrows stages (RB2): `Some(place)` is lent.
            const into = table.staged[self.local(store.slot)];
            if (into != @import("single_owner.zig").no_local) if (try self.lentOptionElement(@fromBackingInt(@intCast(into)), store.value, span)) |lent| {
                self.ssa.types.items[self.local(store.slot)] = self.typeOfRef(lent);
                try self.write(self.local(store.slot), self.current.?, lent);
                try self.assigned(self.local(store.slot));
                return;
            };
            // A bare read-only text, bytes or list parameter (H5) is staged as its frame block, as an appended one is.
            if (into != @import("single_owner.zig").no_local and try self.bareFramed(store.value)) {
                const view = try self.expression(store.value);
                if (self.current == null) return;
                const framed = try self.frameBlock(view, span);
                self.ssa.types.items[self.local(store.slot)] = self.typeOfRef(framed);
                try self.write(self.local(store.slot), self.current.?, framed);
                try self.assigned(self.local(store.slot));
                return;
            }
        };
        // A `const` of a lent option (H2) holds the lent union of its payload, built as a borrowed record's option field is.
        const constant_store = !assign and !self.checked.scope.locals[@backingInt(store.slot)].mutable;
        if (constant_store and try self.lentLocalOption(store.value)) {
            const slot = self.local(store.slot);
            const lent = try @import("build_frame_box.zig").lent(*FnBuilder, self, store.value, self.module().storageType(self.ssa.types.items[slot]), span);
            if (self.current == null) return;
            try self.write(slot, self.current.?, lent);
            try self.assigned(slot);
            return;
        }
        var place: ?Place = null;
        // A list view binding must not build the copy loop at all: the value is the
        // view of the slice's elements, which the block would have copied.
        const slot_type = self.ssa.types.items[self.local(store.slot)];
        const list_view = self.checked.scope.locals[@backingInt(store.slot)].ownership.view and
            self.mb.module.isView(slot_type) and !slot_type.isSpan();
        // A list slice stored into a `mut` local that holds a borrow (H4) is the view of the slice's elements as well.
        const lent_slice = !list_view and self.ssa.borrowed_mut.contains(@intCast(self.local(store.slot))) and
            self.mb.module.isView(slot_type) and !slot_type.isSpan();
        var value = if (list_view)
            try self.listViewSlot(store, slot_type, span)
        else if (lent_slice)
            (try self.listSliceView(store.value, slot_type, span)) orelse try self.expressionPlace(store.value, &place)
        else
            try self.expressionPlace(store.value, &place);
        if (self.checked.scope.locals[@backingInt(store.slot)].ownership.view and !list_view) value = try self.viewSlot(store, value, span);
        // A borrowed view stored into owning storage is materialized at the store:
        // this is where the pre-wave-3 program copied, so no view reaches an owned
        // phi, loop slot or field (REGRESSION-R1, DECISIONS F2).
        // The slice owner of `collection_lower` is initialized once and never assigned, so a view it holds
        // stays borrowed: the slice reads the octets in place (no copy of its base).
        const local_info = self.checked.scope.locals[@backingInt(store.slot)];
        const borrowed_mut = self.ssa.borrowed_mut.contains(@intCast(self.local(store.slot)));
        if (!assign or borrowed_mut) value = try @import("build_const_borrow.zig").adapt(@TypeOf(self), self, store, value, span);
        const slice_owner_store = !assign and std.mem.eql(u8, local_info.name, "<slice>");
        const borrowed_store = !assign and value != .none and self.mb.module.containsBorrow(self.typeOfRef(value)) and (!local_info.mutable or local_info.usage.temporary);
        if (slice_owner_store and value != .none and self.typeOfRef(value).isSpan()) {
            self.ssa.types.items[self.local(store.slot)] = self.typeOfRef(value);
            // A view-keeping owner of a parameter's view is initialized once and never assigned: its reads are that
            // view, so a loop does not hide the parameter's owner behind a phi (C9 S1).
            const at = self.function.resolve(value);
            if (self.view_owner.contains(@intCast(at.index()))) try self.view_params.put(self.allocator(), self.local(store.slot), at);
        } else if (borrowed_store) {
            self.ssa.types.items[self.local(store.slot)] = self.typeOfRef(value);
        } else if (!borrowed_mut and !local_info.ownership.view) {
            if (value != .none and self.typeOfRef(value).isSpan()) value = try self.materializeOwned(store.slot, value, span);
        }
        const block = self.current orelse return;
        try self.write(self.local(store.slot), block, value);
        try self.assigned(self.local(store.slot));
        if (assign) try build_capture.invalidate(@TypeOf(self), self, .{ .root = self.local(store.slot), .steps = &.{} }, span);
        try self.noteAlias(store.slot, place);
        try self.noteProjection(store.slot, place, !assign and value != .none);
    }

    /// `Some(place)` stored into a collection of borrows (RB2), lent as a borrowed record's option field is (RB1): the
    /// payload read in place. Null for any other value or collection.
    fn lentOptionElement(self: *FnBuilder, owner: typed.LocalId, value: typed.NodeId, span: u32) Error!?ir.Ref {
        const table = self.borrowed_collections orelse return null;
        const slot = table.collectionOf(self.local(owner)) orelse return null;
        if (self.nodeOf(value).data != .variant) return null;
        _ = try self.borrowedRecord(value);
        const element = self.module().lentElement(self.ssa.types.items[slot]) orelse return null;
        // `Some(record)` of a borrowed record: the overlay's storage is the option's payload, lent, never consumed.
        if (@import("single_owner.zig").BorrowedCollections.someRecord(self.borrowed_records.?, value)) |payload| {
            const record = try self.borrowStorage(try self.expression(payload), span);
            if (self.current == null) return .none;
            const option = self.module().storageType(element);
            const made = try self.emit(.{ .op = .union_make, .ty = option, .a = record, .data = self.nodeOf(value).data.variant.tag, .span = span });
            return made;
        }
        if (self.borrowed_records.?.lentOption(value) == null) return null;
        const lent = try @import("build_frame_box.zig").lent(*FnBuilder, self, value, self.module().storageType(element), span);
        return lent;
    }

    /// Initialize a borrowed collection (RB2): a new collection of borrows, empty (`[]`, or a literal's buffer of its
    /// capacity), or the literal's own collection when it is initialized with one.
    fn storeLentCollection(self: *FnBuilder, table: @import("single_owner.zig").BorrowedCollections, store: typed.Store, span: u32) Error!void {
        const slot = self.local(store.slot);
        const value = if (table.literal[slot] != @import("single_owner.zig").no_local) made: {
            _ = try self.expression(store.value);
            if (self.current == null) return;
            break :made try self.read(@intCast(table.literal[slot]), self.current.?);
        } else empty: {
            const node = self.nodeOf(store.value);
            const ty = self.ssa.types.items[slot];
            if (self.module().kind(ty) == .dict) break :empty try self.emit(.{ .op = .dict_new, .ty = ty, .a = try self.constant(.u64, 0), .span = span });
            const capacity = if (node.data == .acquire_buffer) try self.expression(node.data.acquire_buffer.capacity) else try self.constant(.i64, 0);
            break :empty try self.emit(.{ .op = .list_new, .ty = ty, .a = capacity, .span = span });
        };
        try self.write(slot, self.current.?, value);
        try self.assigned(slot);
    }

    /// The value a view binding holds: the borrowed octets of the slice its
    /// initializer lowered to, instead of the copy that slice would make. Every
    /// owned use of the binding is materialized later (`view_materialize.zig`),
    /// so the program sees the same value it always did.
    fn viewSlot(self: *FnBuilder, store: typed.Store, value: ir.Ref, span: u32) Error!ir.Ref {
        const target = self.ssa.types.items[self.local(store.slot)];
        if (self.mb.module.isView(target) and !target.isSpan()) return self.listViewSlot(store, target, span);
        const view = (try self.sliceAsView(value)) orelse return self.mb.refuse("a view binding without a slice initializer", span);
        return view;
    }

    /// The value a view-returning function returns: the borrowed octets of its
    /// slice, or a view of the whole borrowed value. The caller's argument keeps
    /// the source alive (`own.zig` links the result to `view_source`).
    fn viewReturn(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        if (self.typeOfRef(value) == .str_view) return value;
        if (try self.sliceAsView(value)) |view| return view;
        return self.wholeView(value, span);
    }

    /// The octets of text `value` as a borrowed view: a free conversion (a length read and a span),
    /// so the owner keeps the text alive and nothing is copied.
    fn wholeView(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        const bytes = self.typeOfRef(value) == .bytes;
        const len = try self.emit(.{ .op = if (bytes) .list_len else .str_len, .ty = .u64, .a = value, .span = span });
        const start: u32 = @intCast(self.function.extra.items.len);
        try self.function.extra.append(self.allocator(), len);
        return self.emit(.{
            .op = .str_view_of,
            .ty = if (bytes) .bytes_view else .str_view,
            .a = value,
            .b = try self.constant(.u64, 0),
            .data = (ir.ExtraSlice{ .start = start, .len = 1 }).pack(),
            .span = span,
        });
    }

    /// `value` as a `str_view` of the slice it stands for, or null when it is not
    /// a slice copy call. A text slice borrows through the byte-offset op, a byte
    /// slice through the byte-family one: both clamp their octet bounds and the
    /// endpoints were already checked non-negative by the lowering.
    fn sliceAsView(self: *FnBuilder, value: ir.Ref) Error!?ir.Ref {
        return self.sliceAsViewOf(value, false);
    }

    /// `sliceAsView`, and with `buffer` a byte buffer's slice too: its borrow is only read before the buffer can change
    /// (a comparison's operand, `borrowComparedSlice`), so it makes no copy. A buffer's slice is a bytes view (C9 bytes).
    fn sliceAsViewOf(self: *FnBuilder, value: ir.Ref, buffer: bool) Error!?ir.Ref {
        const inst = self.function.inst(self.function.resolve(value));
        if (inst.ty.isSpan()) return value;
        // A scalar text slice has the operands of its borrowed form (receiver, start, extra end).
        if (inst.op == .str_slice) {
            const at = self.function.resolve(value).index();
            self.function.insts.items[at].op = .str_slice_view;
            self.function.insts.items[at].ty = .str_view;
            return value;
        }
        if (inst.op != .call) return null;
        // The operands are read out before `extra` can grow: an append may move the list they point into.
        const operands = self.function.operands(inst.data);
        if (operands.len != 3) return null;
        const receiver = operands[0];
        const first = operands[1];
        const last = operands[2];
        const target = self.mb.module.functions.items[inst.a.index()];
        const text = std.mem.eql(u8, target.name, "myl_core_ir_str_slice_bytes");
        // A byte buffer's slice is a new buffer (`myl_core_buffer_slice`); only a comparison's operand borrows its octets.
        const bytes = std.mem.eql(u8, target.name, "myl_core_bytes_slice") or (buffer and std.mem.eql(u8, target.name, "myl_core_buffer_slice"));
        if (!text and !bytes) return null;
        // A borrowed view is a view of text or of bytes; a byte buffer's slice stays an owned call.
        const source = self.function.inst(self.function.resolve(receiver)).ty;
        const buffer_view = buffer and source == .byte_buffer;
        if (source != .str and source != .bytes and !buffer_view) return null;
        const end: u32 = @intCast(self.function.extra.items.len);
        try self.function.extra.append(self.allocator(), last);
        const rewritten: ir.Inst = .{
            .op = if (text) .str_slice_bytes_view else .str_slice_view,
            .ty = if (source == .str) .str_view else .bytes_view,
            .a = receiver,
            .b = first,
            .data = (ir.ExtraSlice{ .start = end, .len = 1 }).pack(),
            .span = inst.span,
        };
        self.function.insts.items[self.function.resolve(value).index()] = rewritten;
        return value;
    }

    /// A checked read-only list binding holds its declared borrowed call result,
    /// alias or slice directly. Slice construction skips the append-loop copy.
    fn listViewSlot(self: *FnBuilder, store: typed.Store, target: ir.Type, span: u32) Error!ir.Ref {
        if (try self.listSliceView(store.value, target, span)) |view| return view;
        const value = try self.expression(store.value);
        if (self.current == null) return .none;
        const actual = self.typeOfRef(value);
        if (actual == target) return value;
        const source = self.module().listElement(self.module().storageType(actual));
        const element = self.module().listElement(target);
        if (source == null or source != element) return self.mb.refuse("invalid checked list view initializer", span);
        return self.readOnlyArgument(value, target, span);
    }

    /// The view of a checked list slice's elements, or null when the value is not
    /// a slice. Borrowed reads answer in place; the copy loop is never built.
    fn listSliceView(self: *FnBuilder, value: typed.NodeId, target: ir.Type, span: u32) Error!?ir.Ref {
        const parts = (try self.listSliceParts(value)) orelse return null;
        const source = try self.expression(parts.base);
        if (self.current == null) return .none;
        // The block's own source temp is what the endpoint guards read, so bind it
        // here instead of lowering the copy loop that named it.
        try self.write(self.local(parts.owner), self.current.?, source);
        const first = try self.expression(parts.start);
        const last = try self.expression(parts.end);
        if (self.current == null) return .none;
        const view = try self.emit(.{ .op = .list_slice_view, .ty = target, .a = source, .b = first, .data = try self.extraSlice(&.{last}), .span = span });
        return view;
    }

    /// The source and clamped endpoints of the append loop a checked list slice
    /// lowers to (`collection_lower.Builder.slice`): the block initializes the
    /// source, the two endpoints, the fresh output, then runs the copy loop.
    fn listSliceParts(self: *FnBuilder, value: typed.NodeId) Error!?struct { owner: typed.LocalId, base: typed.NodeId, start: typed.NodeId, end: typed.NodeId } {
        const node = self.nodeOf(value);
        if (node.data != .block_value) return null;
        const children = switch (self.nodeOfStatement(node.data.block_value.body).data) {
            .block => |children| children,
            else => return null,
        };
        if (children.len < 5) return null;
        if (self.nodeOfStatement(children[4]).data != .loop) return null;
        const output = switch (self.nodeOfStatement(children[3]).data) {
            .initialize => |initialize| initialize,
            else => return null,
        };
        if (self.nodeOf(output.value).data != .acquire_buffer) return null;
        const source = switch (self.nodeOfStatement(children[0]).data) {
            .initialize => |initialize| initialize,
            else => return null,
        };
        const first = switch (self.nodeOfStatement(children[1]).data) {
            .initialize => |initialize| initialize,
            else => return null,
        };
        const last = switch (self.nodeOfStatement(children[2]).data) {
            .initialize => |initialize| initialize,
            else => return null,
        };
        return .{ .owner = source.slot, .base = source.value, .start = first.value, .end = last.value };
    }

    /// The RHS and defensive refresh have completed; transfer only this payload.
    fn prepareOptionalWriteback(self: *FnBuilder, store: typed.Store, span: u32) Error!void {
        const found = @import("optional_writeback.zig").shape(self.mb.input.program, self.checked, store) orelse return;
        const receiver = self.local(found.receiver);
        const place = self.places.get(receiver) orelse return self.mb.refuse("optional writeback without a payload place", span);
        if (place.root != self.local(store.slot) or place.steps.len != 1 or place.steps[0] != .payload or place.steps[0].payload != found.tag)
            return self.mb.refuse("an optional writeback that does not reconstruct its original payload", span);
        if (place.root_version != self.version(place.root)) return self.mb.refuse("an optional writeback with a stale payload", span);
        const root = try self.read(place.root, self.current.?);
        const payload = try self.propagatedPayload(root, found.tag, span);
        try self.write(receiver, self.current.?, payload);
    }

    /// Validate the complete logical shape before evaluating or splitting a tuple.
    fn unpackStore(self: *FnBuilder, store: typed.Store, span: u32, assign: bool) Error!void {
        _ = @import("tuple_unpack.zig").fields(self.allocator(), self.mb.input.program, self.checked, store, !assign) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Invalid => return self.mb.refuse("invalid complete tuple staging", span),
        };
        var place: ?Place = null;
        const value = try self.expressionPlace(store.value, &place);
        const block = self.current orelse return;
        {
            // The moved source's lexical provider pin must no longer name it.
            // Other whole owners are unavailable under the same source contract.
            if (place) |source| if (source.steps.len == 0) {
                const empty = try self.detached(.{ .op = .undef, .ty = self.typeOfRef(value) });
                try self.write(source.root, block, empty);
            };
            return self.unpackPayload(value, store.unpack.?, span);
        }
        // Ordinary RC tuple parameters can remain borrowed after destructuring.
        for (store.unpack.?, 0..) |optional, index| {
            const slot = optional orelse continue;
            const field = try self.fieldGet(value, index, span);
            try self.write(self.local(slot), self.current.?, field);
        }
    }

    /// Lower a checked statement and preserve lexical cleanup on every exit.
    pub fn statement(self: *FnBuilder, id: typed.StatementId) Error!void {
        if (self.current == null) return;
        const s = self.statementOf(id);
        const span: u32 = @intCast(s.span.start);
        const outer_moves = self.field_moves;
        defer self.field_moves = outer_moves;
        self.field_moves = .{ .groups = try field_moves.of(self.allocator(), self.mb.input.program, id, self, takesGroupedField) };
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
                try self.loopStatement(range.plan().loop.id, range.plan().loop.condition, range.plan().loop.body, range.plan().loop.step, range.plan().loop.vectorize);
            },
            .discard => |value| if (!try build_text.discardedRead(@TypeOf(self), self, value, span)) {
                _ = try self.expression(value);
            },
            .ret => |value| {
                var compared: Compared = .{};
                const result = if (self.returnsCompared(value))
                    try self.comparedCondition(value, &compared)
                else if (return_borrow.effectiveSources(self.mb.input.program.records, self.checked.signature).len != 0)
                    try self.borrowedReturnExpression(value, self.checked.signature.return_type, self.declared_ret, span)
                else
                    try self.expression(value);
                if (self.current == null) return;
                try self.traceReturned(value, result, span);
                try self.traceCompared(result, compared, @intCast(self.nodeOf(value).span.start));
                try self.returnValue(result, span);
            },
            .branch => |b| try self.branchStatement(b.condition, b.then_body, b.else_body),
            .loop => |loop| try self.loopStatement(loop.id, loop.condition, loop.body, loop.step, loop.vectorize),
            .loop_exit => |exit| {
                for (self.loops.items, 0..) |targets, depth| if (targets.id == exit.target) {
                    try build_cap.closeScopes(*FnBuilder, self, depth + 1, span);
                    return self.jump(if (exit.continuing) targets.latch else targets.exit);
                };
                return self.mb.refuse("loop exit target", span);
            },
            .match => |m| try self.matchStatement(m.value, m.arms, m.exclusive, span),
            .assertion => |check| try self.assertStatement(check),
            // The interim arena rule (docs/design/new-core-s1.md §11): a `with arena()` block is a plain
            // block, and `n.escape(v)` is `v`; direct destruction frees at last use. The checker has
            // already rejected every program that lets an arena value outlive its block.
            .with_scope => |scope| {
                if (scope.resource) |source| {
                    if (self.nodeOf(source).data == .task_group_open) return build_task.scope(*FnBuilder, self, scope.slot, scope.body, span);
                    const owner = try self.expression(source);
                    const variable = self.local(scope.slot);
                    try self.write(variable, self.current.?, owner);
                    const provider = try self.expression(build_cap.scopeProvider(self.mb.input.program, source).?);
                    const cleanup: build_cap.Scope = .{ .owner = owner, .depth = self.loops.items.len, .provider = provider, .variable = if (self.typeOfRef(owner) == .resource) variable else null };
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
        var compared: Compared = .{};
        const plain = if (compound or literal != null) null else try self.assertCondition(check, &compared);
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
        if (compared.left != .none) try self.assertOperands(compared, condition_span);
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

    /// The condition of an `assert` statement with no computed message. A comparison (`==`, `!=`, `<`, `<=`, `>`, `>=`),
    /// alone or after the temporaries its operands need, is lowered as any comparison is and its two operand values are
    /// kept in `compared`, so the failure path can name them (F-18); any other condition is lowered as it is elsewhere.
    fn assertCondition(self: *FnBuilder, check: typed.Assertion, compared: *Compared) Error!ir.Ref {
        if (check.kind != .statement or check.message_value != null) return self.expression(check.condition);
        // A freestanding function's failed `assert` builds no text, so its operands are not kept to be printed.
        if (self.checked.policy.freestanding != null) return self.expression(check.condition);
        return self.comparedCondition(check.condition, compared);
    }

    /// `condition` lowered as an expression, its two operand values kept in `compared` when it is one comparison.
    fn comparedCondition(self: *FnBuilder, condition: typed.NodeId, compared: *Compared) Error!ir.Ref {
        var node = self.nodeOf(condition);
        var first: ?u32 = null;
        if (node.data == .block_value) {
            const block = node.data.block_value;
            if (self.nodeOf(block.value).data != .binary) return self.expression(condition);
            first = self.firstInitialized(block.body);
            try self.statement(block.body);
            if (self.current == null) return .none;
            node = self.nodeOf(block.value);
        }
        const b = switch (node.data) {
            .binary => |value| value,
            else => return self.expression(condition),
        };
        // A float comparison reads its operands from the temporaries the block initialized in source order, and
        // `a > b` is `b < a`: the operand read from the first temporary is the source's left one.
        const float = switch (b.op) {
            .f64_eq, .f64_lt, .f64_le, .f32_eq, .f32_lt, .f32_le => true,
            else => false,
        };
        const kept: ?*Compared = switch (b.op) {
            .eq, .ne, .lt, .le, .gt, .ge => compared,
            else => if (float and first != null) compared else null,
        };
        const result = try self.binary(b.op, b.left, b.right, @intCast(b.op_span.start), kept);
        if (kept != null and float) {
            const left_slot = self.unwrappedLocal(b.left);
            const right_slot = self.unwrappedLocal(b.right);
            if (right_slot != null and right_slot.? == first.?) {
                const swapped: Compared = .{ .left = compared.right, .right = compared.left };
                compared.* = swapped;
            } else if (left_slot == null or left_slot.? != first.?) compared.* = .{};
        }
        return result;
    }

    /// Whether `return value` is, in a test of a test executable (`Input.compared_returns`), the `bool` result of one
    /// comparison: the failure path then names its operands (`traceCompared`).
    fn returnsCompared(self: *FnBuilder, value: typed.NodeId) bool {
        const listed = std.mem.indexOfScalar(typed.FunctionId, self.mb.input.compared_returns, self.checked.id) != null;
        if (!listed or self.checked.signature.return_type != .bool) return false;
        var node = self.nodeOf(value);
        if (node.data == .block_value) node = self.nodeOf(node.data.block_value.value);
        return switch (node.data) {
            .binary => |b| switch (b.op) {
                .eq, .ne, .lt, .le, .gt, .ge, .f64_eq, .f64_lt, .f64_le, .f32_eq, .f32_lt, .f32_le => true,
                else => false,
            },
            else => false,
        };
    }

    /// A returned comparison that came out false: hand both operands to the runtime (when they are integers, floats or
    /// texts, as for an `assert`) and record where the comparison is, so the trial's report says what was compared and
    /// on which line, instead of only that the test returned false. The passing path is the one branch.
    fn traceCompared(self: *FnBuilder, result: ir.Ref, compared: Compared, span: u32) Error!void {
        const values = [_]ir.Ref{ compared.left, compared.right };
        for (values) |value| if (value == .none or !printableOperand(self.typeOfRef(value))) return;
        // A comparison the lowering already folded says nothing the source does not, and its failure path would carry the
        // constants into an executable that is otherwise the same after an edit of one of them.
        if (self.isConstant(result) or (self.isConstant(compared.left) and self.isConstant(compared.right))) return;
        const failed = try self.newBlock();
        const done = try self.newBlock();
        try self.branch(result, done, failed, span);
        try self.seal(failed);
        self.current = failed;
        try self.assertOperands(compared, span);
        _ = try self.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.returned), .span = span });
        try self.jump(done);
        try self.seal(done);
        self.enter(done);
    }

    /// Whether `ref` is an integer, float or text constant of the function.
    fn isConstant(self: *FnBuilder, ref: ir.Ref) bool {
        return switch (self.function.inst(self.function.resolve(ref)).op) {
            .iconst, .fconst, .str_const => true,
            else => false,
        };
    }

    /// The local the first `initialize` statement of block `id` writes, or null.
    fn firstInitialized(self: *FnBuilder, id: typed.StatementId) ?u32 {
        const body = switch (self.mb.input.program.statements[@backingInt(id)].data) {
            .block => |items| items,
            else => return null,
        };
        if (body.len == 0) return null;
        return switch (self.mb.input.program.statements[@backingInt(body[0])].data) {
            .initialize => |store| @intCast(@backingInt(store.slot)),
            else => null,
        };
    }

    /// The local an operand reads, through one `unwrap` of a float domain value, or null.
    fn unwrappedLocal(self: *FnBuilder, id: typed.NodeId) ?u32 {
        const inner = switch (self.nodeOf(id).data) {
            .unwrap => |value| value,
            else => id,
        };
        return switch (self.nodeOf(inner).data) {
            .local => |slot| @intCast(@backingInt(slot)),
            else => null,
        };
    }

    /// The failure path of `assert LEFT op RIGHT` when both operands are integers, floats or texts: hand their values to
    /// the runtime, whose assertion trap then prints them after the message (F-18). It allocates nothing; for any other
    /// operand type it emits nothing and the trap is as it was.
    fn assertOperands(self: *FnBuilder, compared: Compared, span: u32) Error!void {
        const values = [_]ir.Ref{ compared.left, compared.right };
        for (values) |value| if (value == .none or !printableOperand(self.typeOfRef(value))) return;
        var arguments: [8]ir.Ref = undefined;
        for (values, 0..) |value, side| {
            const operand = try self.assertOperand(value, span);
            @memcpy(arguments[side * 4 ..][0..4], &operand);
        }
        _ = try self.runtimeCall("myl_core_assert_operands", &.{ .i64, .i64, .f64, .str, .i64, .i64, .f64, .str }, .void, &arguments, span);
    }

    /// Whether the runtime prints a compared value of type `ty`: an integer, a float or a text.
    fn printableOperand(ty: ir.Type) bool {
        return ty == .str or ty == .str_view or ty == .f64 or ty == .f32 or ty.integer() != null;
    }

    /// One printable compared value as the runtime's `(kind, whole, real, text)` quadruple (`myl_core_assert_operands`).
    fn assertOperand(self: *FnBuilder, value: ir.Ref, span: u32) Error![4]ir.Ref {
        const ty = self.typeOfRef(value);
        const zero = try self.constant(.i64, 0);
        const none_real = try self.detached(.{ .op = .fconst, .ty = .f64, .data = 0 });
        if (ty == .str or ty == .str_view) return .{ try self.constant(.i64, 4), zero, none_real, value };
        const empty = try self.emptyText();
        if (ty == .f64 or ty == .f32) {
            const real = if (ty == .f64) value else try self.emit(.{ .op = .float_convert, .ty = .f64, .a = value, .span = span });
            return .{ try self.constant(.i64, 3), zero, real, empty };
        }
        const info = ty.integer().?;
        const wide: ir.Type = if (info.signed) .i64 else .u64;
        var whole = if (ty == wide) value else try self.emit(.{ .op = .convert, .ty = wide, .a = value, .span = span });
        if (!info.signed) whole = try self.emit(.{ .op = .convert, .ty = .i64, .a = whole, .span = span });
        return .{ try self.constant(.i64, if (info.signed) 1 else 2), whole, none_real, empty };
    }

    /// An empty text constant.
    fn emptyText(self: *FnBuilder) Error!ir.Ref {
        const index = self.mb.module.strings.items.len;
        try self.mb.module.strings.append(self.allocator(), "");
        return self.detached(.{ .op = .str_const, .ty = .str, .data = index });
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
            // A comparison chain: one branch per link on its own comparison (`build_chain.zig`).
            .block_value => if (build_chain.of(*FnBuilder, self, node)) |chain| {
                return build_chain.branchOn(*FnBuilder, self, chain, .{ .then = then, .otherwise = otherwise, .span = span });
            },
            else => {},
        }
        const condition = try self.expression(node);
        if (self.current == null) return;
        try self.branch(condition, then, otherwise, span);
    }

    /// Whether `node` is an `and`, an `or`, a `not` or a comparison chain of integers, which `branchOn` turns into
    /// control flow; any other condition is evaluated first and branched on (so its blocks keep the numbering they had).
    fn isCompound(self: *FnBuilder, node: typed.NodeId) bool {
        return switch (self.nodeOf(node).data) {
            .binary => |b| b.op == .logical_and or b.op == .logical_or,
            .unary => |u| u.op == .not,
            .block_value => build_chain.of(*FnBuilder, self, node) != null,
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

    fn loopStatement(self: *FnBuilder, id: usize, condition: typed.NodeId, body: typed.StatementId, step: ?typed.StatementId, vectorize: bool) Error!void {
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
        try self.function.loops.append(self.allocator(), .{ .id = id, .header = header, .body = body_block, .latch = latch, .exit = exit, .vectorize = vectorize });
        self.enter(exit);
    }

    fn matchStatement(self: *FnBuilder, value_node: typed.NodeId, arms: []const typed.MatchArm, exclusive: bool, span: u32) Error!void {
        if (exclusive) for (arms) |arm| {
            if (arm.slot) |slot| try self.exclusive_locals.put(self.allocator(), self.local(slot), {});
            if (arm.unpack) |unpack| for (unpack.fields) |field| if (field) |slot| try self.exclusive_locals.put(self.allocator(), self.local(slot), {});
        };
        // A borrowed call result is read in place, as the checker judges it (R3b): its arms borrow the payload.
        const borrowed = @import("single_owner.zig").borrowedCallValue(self.mb.input.program, try self.mb.linearTypes(), value_node);
        const nodes = self.mb.input.program.nodes;
        const consumed = @import("single_owner.zig").matchConsumesNamed(self.mb.input.program, try self.mb.linearTypes(), value_node);
        const owned = !borrowed and (consumed or @import("single_owner.zig").matchOwnsTemporary(nodes, value_node) or @import("single_owner_resource.zig").affine(self.mb.input.program, self.nodeOf(value_node).ty));
        var value_place: ?Place = null;
        self.exclusive_scrutinee = exclusive;
        const value = try self.expressionPlace(value_node, &value_place);
        self.exclusive_scrutinee = false;
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
        if (arm.slot) |slot| if (!owned and self.exclusive_locals.contains(self.local(slot))) {
            const place: ?Place = if (value_place) |found| try self.extendPlace(found, .{ .payload = @intCast(arm.tag) }) else null;
            try self.noteAlias(slot, place);
            return self.statement(arm.body);
        };
        if (arm.slot) |slot| {
            const payload = if (owned) try self.propagatedPayload(value, arm.tag, span) else try self.payloadOf(value, arm.tag, span);
            if (owned) if (arm.unpack) |unpack| {
                try self.unpackPayload(payload, unpack.fields, span);
                return self.statement(unpack.body);
            };
            // A `Unit` payload (`case Ok(v)` of a `Unit fails E` value) is `.none`, with no instruction to type.
            if (payload != .none and self.module().containsBorrow(self.typeOfRef(payload))) self.ssa.types.items[self.local(slot)] = self.typeOfRef(payload);
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
        const fields = self.module().compound(self.module().storageType(self.typeOfRef(payload))).record;
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
        const source = try self.borrowStorage(dictionary, span);
        const marker_name = try self.mb.helperName(borrow_selection.prefix, &.{ self.typeOfRef(source), ty });
        const callee = borrow_selection.declare(self.allocator(), self.module(), self.typeOfRef(source), ty, marker_name) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnsupportedInstruction => return self.mb.refuse("invalid borrowed dictionary selection", span),
        };
        try self.mb.touch(callee);
        return self.emit(.{ .op = .call, .ty = ty, .a = @fromBackingInt(callee), .data = try self.extraSlice(&.{ selected, source, fallback }), .span = span });
    }

    /// Borrow one selected value while both eagerly evaluated inputs stay live.
    pub fn borrowChoice(self: *FnBuilder, kind: borrow_selection.Kind, selected: ir.Ref, first: ir.Ref, second: ir.Ref, span: u32) Error!ir.Ref {
        const ty = self.typeOfRef(selected);
        const marker_name = try self.mb.helperName(try borrow_selection.choiceFamily(self.allocator(), kind), &.{ self.typeOfRef(first), ty });
        const callee = borrow_selection.declareChoice(self.allocator(), self.module(), self.typeOfRef(first), ty, marker_name) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.UnsupportedInstruction => return self.mb.refuse("invalid borrowed value selection", span),
        };
        try self.mb.touch(callee);
        return self.emit(.{ .op = .call, .ty = ty, .a = @fromBackingInt(callee), .data = try self.extraSlice(&.{ selected, first, second }), .span = span });
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
        const union_type = self.module().storageType(self.typeOfRef(value));
        const cases = switch (self.mb.module.kind(union_type) orelse return self.mb.refuse(refuse_payload, span)) {
            .@"union" => self.mb.module.compound(union_type).@"union",
            else => return self.mb.refuse(refuse_payload, span),
        };
        if (tag >= cases.len) return self.mb.refuse(refuse_payload, span);
        if (cases[tag] == .void) return .none;
        const payload = try self.emit(.{ .op = .union_payload, .ty = cases[tag], .a = value, .data = tag, .span = span });
        return self.unbox(payload, span);
    }

    /// Read a borrowed overlay in its underlying layout before an explicit independent copy.
    pub fn borrowStorage(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        const ty = self.typeOfRef(value);
        if (!self.module().isBorrowed(ty)) return value;
        return self.emit(.{ .op = .borrow, .ty = self.module().storageType(ty), .a = value, .span = span });
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
        // A `match mut` binding has no SSA value of its own: it names its place, so a receiver read projects it (FX12).
        if (try self.exclusiveRead(owner, null, @intCast(self.checked.scope.locals[@backingInt(owner)].declaration.start))) |fresh| return fresh;
        if (try self.reprojected(owner, @intCast(self.checked.scope.locals[@backingInt(owner)].declaration.start))) |fresh| return fresh;
        return self.lentWhole(try self.read(self.local(owner), self.current.?), @intCast(self.checked.scope.locals[@backingInt(owner)].declaration.start));
    }

    /// A collection of borrows (RB2) read as a whole: the read-only overlay of the owned collection whose layout it shares,
    /// so every read of it (an element, its length, an iteration, an argument) is a read of a borrowed list. Any other value
    /// is returned as it is.
    pub fn lentWhole(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        if (value == .none) return value;
        const storage = (try self.module().lentStorage(self.allocator(), self.typeOfRef(value))) orelse return value;
        return self.emit(.{ .op = .borrow, .ty = try self.module().borrowedType(self.allocator(), storage), .a = value, .span = span });
    }

    /// `value` as an element of collection `list` when it is a collection of borrows (RB2): the read-only overlay of the
    /// element's storage. Any other value is returned as it is.
    pub fn lentElementOf(self: *FnBuilder, list: ir.Ref, value: ir.Ref, span: u32) Error!ir.Ref {
        const element = self.module().lentElement(self.typeOfRef(list)) orelse return value;
        if (self.typeOfRef(value) == element) return value;
        return self.readOnlyArgument(value, element, span);
    }

    /// H5: a bare read-only text, bytes or list parameter stored into a local collection of borrows (RB2) is held as its frame
    /// block (RB1, `ir.Op.block_frame`): the caller's block for a whole argument, else one copy this call makes the first time
    /// and frees before it returns. `value` is `node` lowered; any other value, or a store into an owning collection, is kept.
    /// An element write stages its value in a temporary, which holds the frame block (`store`).
    pub fn framedElement(self: *FnBuilder, collection: ir.Ref, node: typed.NodeId, value: ir.Ref, span: u32) Error!ir.Ref {
        if (value == .none or self.module().lentElement(self.typeOfRef(collection)) == null) return value;
        if (!try self.bareFramed(node)) return value;
        return self.frameBlock(value, span);
    }

    /// Whether `node` is a bare read of a plain read-only text, bytes or list parameter, which a borrowed record or a
    /// collection of borrows holds as its frame block (RB1, H5).
    fn bareFramed(self: *FnBuilder, node: typed.NodeId) Error!bool {
        _ = try self.borrowedRecord(node);
        return self.borrowed_records.?.framedRead(node);
    }

    /// Remember a `const` binding that borrows a place of a record the body writes later, so a read after the write projects the
    /// place again. Only a binding that borrows its place is read again: a scalar or a record of scalars is a copy and keeps its
    /// value.
    fn noteProjection(self: *FnBuilder, slot: typed.LocalId, place: ?Place, initializing: bool) Error!void {
        var named = place orelse return;
        const variable = self.local(slot);
        // A place under a binding that is itself read again (`net.pins` under the loop variable `net`) is read again from that
        // binding's own place, so it follows the record both lie in.
        if (self.projected.get(named.root)) |base| if (base.place.root != variable) {
            const steps = try self.allocator().alloc(Step, base.place.steps.len + named.steps.len);
            @memcpy(steps[0..base.place.steps.len], base.place.steps);
            @memcpy(steps[base.place.steps.len..], named.steps);
            named = .{ .root = base.place.root, .steps = steps, .root_version = self.version(base.place.root), .through_view = named.through_view or base.place.through_view };
        };
        if (!initializing or named.steps.len == 0 or named.through_view) return;
        if (named.root == variable) return;
        const info = self.checked.scope.locals[variable];
        if (!alias_places.projectedBinding(info)) return;
        // A loop variable is an element read in place, which an owned element type does not show: it is read again when its
        // type holds storage at all.
        const element = info.origin == .iteration or alias_places.iteratedCollection(info);
        const held = if (element) self.mb.module.managed(self.ssa.types.items[variable]) else self.mb.module.containsBorrow(self.ssa.types.items[variable]);
        if (!held) return;
        if (self.projectable == null) self.projectable = try alias_places.compute(self.allocator(), self.mb.input.program, self.checked);
        const written = self.projectable.?[variable];
        if (!written.bound) return;
        try self.projected.put(self.allocator(), variable, .{ .place = named, .version = self.version(named.root), .depth = if (written.carried) self.loops.items.len else std.math.maxInt(usize) });
    }

    /// A `const` binding of a record place, read again from the record's current value when the record was written since the
    /// binding or the read runs in a loop entered after it; null when the binding's own value is still the place's.
    fn reprojected(self: *FnBuilder, slot: typed.LocalId, span: u32) Error!?ir.Ref {
        const bound = self.projected.get(self.local(slot)) orelse return null;
        if (self.version(bound.place.root) == bound.version and self.loops.items.len <= bound.depth) return null;
        const fresh = try self.readPlace(try self.currentPlace(bound.place), span);
        const target = self.ssa.types.items[self.local(slot)];
        return if (self.typeOfRef(fresh) == target) fresh else try self.readOnlyArgument(fresh, target, span);
    }

    /// The checker's second read of a compound assignment's entry (`server.conns[id].sent += e` binds `<collection> =
    /// server.conns`, its key and the entry, evaluates `e`, then initializes the entry again from `<collection>`): when `e`
    /// wrote the receiver's root (`reset8(mut server.conns[8])` stores the dictionary back into `server`), the receiver is
    /// read again from the root as it stands now, as `x = x op e` reads the place after `e` (FR72). The key keeps its
    /// value (its own hidden local, evaluated once before `e`), and a `match mut` binding is left as it was. A list
    /// receiver is read again the same way (`deck.slots[i].n += bump(mut deck.slots[j])`, FR73): its index is the hidden
    /// local, checked once before `e`, and the write then finds the place unwritten since. A receiver that is the root
    /// itself or lies under one of its elements (`rows[i].n += bump(mut rows[j])`, `grid[i][k].n += bump(mut grid[j][k])`,
    /// FR74) is read again the same way: the root's current value, then the element steps with the indices and keys
    /// already evaluated. The first read of the entry is refreshed too when the index itself wrote the root
    /// (`points.left[save(mut points.right)].x = 13`, the single-owner checker's sibling-field receiver loan): the
    /// receiver was bound before the index, so the read and the write go through the list as it stands after it, as
    /// `const k = save(...)` first would.
    fn refreshEntryReceiver(self: *FnBuilder, store: typed.Store, span: u32, assign: bool) Error!void {
        const info = self.checked.scope.locals[@backingInt(store.slot)];
        const hidden = info.usage.temporary and std.mem.startsWith(u8, info.name, "<");
        if (assign or !hidden) return;
        const operation = switch (self.nodeOf(store.value).data) {
            .buffer_operation => |operation| operation,
            else => return,
        };
        const owner = self.local(operation.owner);
        const kind = self.mb.module.kind(self.ssa.types.items[owner]);
        if (operation.kind != .read or (kind != .dict and kind != .list)) return;
        if (self.exclusive_locals.contains(owner)) return;
        const place = self.places.get(owner) orelse return;
        if (self.version(place.root) == place.root_version) return;
        const fresh = try self.currentPlace(place);
        const value = try self.readPlace(fresh, span);
        if (self.current == null) return;
        try self.write(owner, self.current.?, value);
        try self.places.put(self.allocator(), owner, fresh);
    }

    /// The value a write through receiver `owner` applies to. If evaluating the arguments wrote
    /// the receiver's place, the old runtime applies the write to the payload the receiver
    /// captured, which is the place's still (an in-place change of the place) or no longer (the
    /// callee replaced the field, or cleared the parent) reachable from it; a value cannot tell
    /// the two apart, so the write is refused rather than guessed.
    pub fn writableReceiverOf(self: *FnBuilder, owner: typed.LocalId, span: u32) Error!ir.Ref {
        return self.writableReceiverReusing(owner, .fresh, span);
    }

    /// How `writableReceiverReusing` reaches a receiver's place.
    pub const ReceiverReads = enum {
        /// Read the place again from its root.
        fresh,
        /// Take the reads the receiver binding was made of; nothing may read the place between (`rows[i][j].f = v`).
        binding,
        /// A dictionary entry write whose value is the hidden read of the same entry (`d.conns[k].n += m`,
        /// `d.groups[g].conns[k].out = v`, FR66): the binding's reads, which other reads of the place between may borrow
        /// (the ownership pass joins them), when the place was not written since; the place read again otherwise.
        entry,
    };

    /// `mode` when `value`, what an element write stores, is the hidden read of the slot it writes (`rows[i][j].f = v`
    /// reads `rows[i][j]`, sets its field and stores it back); `fresh` otherwise.
    pub fn slotReads(self: *FnBuilder, value: typed.NodeId, mode: ReceiverReads) ReceiverReads {
        return if (@import("single_owner.zig").slotWritebackLocal(self.mb.input.program, self.checked, value) != null) mode else .fresh;
    }

    /// `writableReceiverOf`, taking the elements the receiver binding was read through instead of reading its place
    /// again when `reuse_reads` is `binding` or `entry`. That is for an element write whose value is the hidden read of
    /// the same slot (`rows[i][j].f = v`): the binding's reads then are taken once, from an owner.
    pub fn writableReceiverReusing(self: *FnBuilder, owner: typed.LocalId, reuse_reads: ReceiverReads, span: u32) Error!ir.Ref {
        const variable = self.local(owner);
        const alias = try self.read(variable, self.current.?);
        const found = self.places.get(variable) orelse return alias;
        // A `match mut` binding is a name for its place (C1): it captured nothing before the arguments, so the place is the
        // container as it stands now, as a plain `mut` local's receiver is its current value. Its recorded version moves only
        // with writes made through the binding itself, so a finished write through a receiver temporary staged from it
        // (`recs[0] = v`, `exchange(mut recs[0], v)`) would otherwise read as a write in flight (FX17).
        const place = if (self.exclusive_locals.contains(variable)) try self.currentPlace(found) else found;
        // An argument may write the receiver's owner only in another outer record field than the one the receiver lies
        // under (the single-owner checker's receiver loan, `differentOuterFields`), so such a receiver is read again from
        // the owner as it stands now. A receiver that is the owner itself or lies under one of its elements is refused.
        const stale = self.version(place.root) != place.root_version;
        const field_receiver = place.steps.len != 0 and place.steps[0] == .field;
        if (stale and (reuse_reads == .binding or !field_receiver)) return self.mb.refuseOwnership("write to a receiver's place while its arguments are evaluated", span);
        const root = try self.read(place.root, self.current.?);

        const parents = try self.allocator().alloc(ir.Ref, place.steps.len);
        const children = try self.allocator().alloc(ir.Ref, place.steps.len);
        // The binding's own value was read through the place already (`rows[i]` for `rows[i][j].f = v`), and the hidden
        // element read that follows went through that read. Take each element once, from those reads: elements read
        // through a second read of the same slot would be read from a borrow, and a slot cannot be taken twice.
        const earlier = if (reuse_reads == .binding or (reuse_reads == .entry and !stale)) try self.earlierReads(alias, place, root, reuse_reads) else null;
        var value = root;
        for (place.steps, 0..) |step, index| {
            value = try self.prepareParent(value, span);
            parents[index] = value;
            if (earlier) |reads| {
                value = reads[index];
                if (step == .payload) self.function.insts.items[value.index()].op = .union_take;
            } else {
                if (step == .payload and (payloadBefore(place.steps[0..index]) or self.projectsFromJoin(value))) try self.caseGuard(value, step.payload, span);
                value = if (step == .payload)
                    try self.propagatedPayload(value, step.payload, span)
                else
                    try self.stepGet(value, step, span);
            }
            value = self.takeWritableChild(value);
            children[index] = value;
            const kind = self.mb.module.kind(self.typeOfRef(parents[index]));
            if ((kind == .list or kind == .dict) and self.mb.module.managed(self.typeOfRef(value))) self.function.insts.items[value.index()].data = flags.place_read;
        }
        try self.ssa.prepared.put(self.allocator(), variable, .{ .parents = parents, .children = children });
        return value;
    }

    /// The reads that built a receiver binding's value, one per step of its place, when every step is a plain list
    /// element, dictionary entry, unboxed record field or unboxed union payload and the first read starts at the place's root; null when any
    /// step was read another way. The caller
    /// has checked that nothing wrote the place since.
    fn earlierReads(self: *FnBuilder, binding_value: ir.Ref, place: Place, root: ir.Ref, mode: ReceiverReads) Error!?[]const ir.Ref {
        if (place.steps.len == 0) return null;
        const reads = try self.allocator().alloc(ir.Ref, place.steps.len);
        var current = self.function.resolve(binding_value);
        var index = place.steps.len;
        while (index != 0) {
            index -= 1;
            const inst = self.function.inst(current);
            switch (place.steps[index]) {
                .element => |at| {
                    // A list element read at the same index, or a dictionary entry read at the same probe.
                    if (inst.op != .list_get and inst.op != .dict_entry_value) return null;
                    if (inst.op == .list_get and inst.data != 0 and inst.data != flags.place_read) return null;
                    if (!self.sameConstant(inst.b, at)) return null;
                },
                .mapping => |wanted| {
                    if (inst.op != .dict_entry_value) return null;
                    const probe = self.function.inst(self.function.resolve(inst.b));
                    if (probe.op != .dict_find or self.function.resolve(probe.a) != self.function.resolve(inst.a)) return null;
                    if (!self.sameConstant(probe.b, wanted)) return null;
                },
                .field => |wanted| {
                    if (inst.op != .record_get or inst.data != wanted) return null;
                },
                // The payload of a `match mut` case, read unboxed (FX17: `items[0].text = v` through a binding of a payload
                // field). The write takes it where it was read (`union_payload` becomes `union_take`), as a read of the
                // place again would.
                .payload => |wanted| {
                    if (inst.op != .union_payload or inst.data != wanted) return null;
                    const stored = self.mb.module.compound(self.module().storageType(self.typeOfRef(inst.a))).@"union"[wanted];
                    if (self.mb.module.kind(stored) == .box) return null;
                },
            }
            reads[index] = current;
            current = self.function.resolve(inst.a);
        }
        if (!build_list_methods.sameRecordProjection(&self.function, current, root)) return null;
        if (!self.untouchedSince(reads, root, mode)) return null;
        if (mode == .entry) try self.forwardPlaceReads(reads);
        return reads;
    }

    /// Makes each read that repeats one of `reads` (the receiver binding's reads, one per step of its place) or one of
    /// their probes, run after the first of them in the window `untouchedSince` accepted, a forwarding copy of it (FR70).
    /// An `entry` write takes `reads`; the right side of `server.conns[id].sent += server.conns[8].sent *
    /// len(server.conns[id].out)` reads `server.conns` twice more, and a second read of the place leaves the binding's
    /// read a borrow the write cannot take. Each repeat reads the same SSA value with the same operands, so it is the
    /// same value: the compound form reads the place once, as `x = x op e` reads it once after the right side, and the
    /// right side's reads borrow it until the write.
    fn forwardPlaceReads(self: *FnBuilder, reads: []const ir.Ref) Error!void {
        var blocks: std.ArrayList(ir.BlockId) = .empty;
        var block = self.current orelse return;
        const first_at = for (0..64) |_| {
            try blocks.append(self.allocator(), block);
            const insts = self.function.blocks.items[block.index()].insts.items;
            if (std.mem.indexOfScalar(ir.Ref, insts, reads[0])) |at| break at;
            const preds = self.function.blocks.items[block.index()].preds.items;
            if (preds.len != 1) return;
            block = preds[0];
        } else return;
        var known: std.ArrayList(ir.Ref) = .empty;
        for (reads) |step_read| {
            try known.append(self.allocator(), step_read);
            const inst = self.function.inst(step_read);
            if (inst.op == .dict_entry_value) try known.append(self.allocator(), self.function.resolve(inst.b));
        }
        var index = blocks.items.len;
        while (index != 0) {
            index -= 1;
            const insts = self.function.blocks.items[blocks.items[index].index()].insts.items;
            for (insts[if (index == blocks.items.len - 1) first_at + 1 else 0..]) |ref| {
                if (std.mem.indexOfScalar(ir.Ref, known.items, ref) != null) continue;
                const earlier = for (known.items) |candidate| {
                    if (self.repeatsRead(ref, candidate)) break candidate;
                } else continue;
                const inst = self.function.inst(ref);
                self.function.insts.items[ref.index()] = .{ .op = .copy, .ty = inst.ty, .a = earlier, .span = inst.span };
            }
        }
    }

    /// Whether `ref` reads what `earlier` read: a field, an entry or element read without taking it, or a key probe, of
    /// the same value at the same field, probe, index or key.
    fn repeatsRead(self: *FnBuilder, ref: ir.Ref, earlier: ir.Ref) bool {
        const inst = self.function.inst(ref);
        const known = self.function.inst(earlier);
        if (inst.op != known.op or inst.ty != known.ty) return false;
        if (self.function.resolve(inst.a) != self.function.resolve(known.a)) return false;
        return switch (inst.op) {
            .record_get => inst.data == known.data,
            .dict_find => self.sameConstant(inst.b, known.b),
            .dict_entry_value => inst.data & flags.dict_take_value == 0 and known.data & flags.dict_take_value == 0 and
                self.sameConstant(inst.b, known.b),
            .list_get => (inst.data == 0 or inst.data == flags.place_read) and (known.data == 0 or known.data == flags.place_read) and
                self.sameConstant(inst.b, known.b),
            else => false,
        };
    }

    /// Whether nothing between the first of `reads` and now reads or writes the places they go through other than the
    /// reads themselves, the element reads of the last one and the probes of a dictionary step: taking them where they
    /// were read is then the same as taking them here. Anything else (a second read of the slot, a call, a store) says
    /// no, except that an `entry` write lets other reads borrow the place (FR66) and lets a direct call given none of
    /// `reads` nor the root run (FR71). The window is the current block; a
    /// place read through a dictionary entry, or an `entry` write, continues it through the blocks the entries' presence
    /// tests ended, each the only predecessor of the next.
    fn untouchedSince(self: *FnBuilder, reads: []const ir.Ref, root: ir.Ref, mode: ReceiverReads) bool {
        var block = self.current orelse return false;
        const across = mode == .entry or for (reads) |step_read| {
            if (self.function.inst(step_read).op == .dict_entry_value) break true;
        } else false;
        for (0..64) |_| {
            const insts = self.function.blocks.items[block.index()].insts.items;
            const found = std.mem.indexOfScalar(ir.Ref, insts, reads[0]);
            const start = if (found) |at| at + 1 else 0;
            for (insts[start..]) |ref| if (!self.leavesReads(ref, reads, root, mode)) return false;
            if (found != null) return true;
            const preds = self.function.blocks.items[block.index()].preds.items;
            if (!across or preds.len != 1) return false;
            block = preds[0];
        }
        return false;
    }

    /// Whether `ref`, run between the first of `reads` and the write that takes them, leaves them to be taken where they
    /// were read (`untouchedSince`).
    fn leavesReads(self: *FnBuilder, ref: ir.Ref, reads: []const ir.Ref, root: ir.Ref, mode: ReceiverReads) bool {
        if (std.mem.indexOfScalar(ir.Ref, reads, ref) != null) return true;
        const inst = self.function.inst(ref);
        // A direct call an `entry` write's window holds (`sent += twice(server.conns[8].sent)`) and given neither the
        // place's root nor the binding's reads cannot reach the place (FR71): IR values do not change, and a call given
        // the root or a part of it `mut` names the root or is followed by a store into it, which still says no. A call's
        // `a` is its callee's index, not a value: only its arguments are looked at.
        if (inst.op == .call and mode == .entry) {
            const arguments = self.function.operands(inst.data);
            for (arguments) |argument| {
                if (argument == .none) continue;
                const value = self.function.resolve(argument);
                if (value == self.function.resolve(root) or std.mem.indexOfScalar(ir.Ref, reads, value) != null) return false;
            }
            return true;
        }
        if (inst.op == .call or inst.op == .call_indirect) return false;
        if (inst.op == .list_get and self.function.resolve(inst.a) == reads[reads.len - 1]) return true;
        // A dictionary step's probe reads the keys only; the entry read of the last read is the write's hidden read.
        if (inst.op == .dict_find and std.mem.indexOfScalar(ir.Ref, reads, self.function.resolve(inst.a)) != null) return true;
        if (inst.op == .dict_entry_value and inst.data & flags.dict_take_value == 0 and self.function.resolve(inst.a) == reads[reads.len - 1]) return true;
        if (!self.mentionsAny(inst, reads) and !self.mentionsAny(inst, &.{root})) return true;
        if (mode != .entry) return false;
        return switch (inst.op) {
            .record_get, .dict_find, .list_len, .dict_len => true,
            .dict_entry_value => inst.data & flags.dict_take_value == 0,
            .list_get => inst.data == 0 or inst.data == flags.place_read,
            else => false,
        };
    }

    /// Whether any operand of `inst` is one of `targets`.
    fn mentionsAny(self: *FnBuilder, inst: ir.Inst, targets: []const ir.Ref) bool {
        for ([_]ir.Ref{ inst.a, inst.b }) |operand| {
            if (operand == .none) continue;
            if (std.mem.indexOfScalar(ir.Ref, targets, self.function.resolve(operand)) != null) return true;
        }
        if (inst.op.hasExtra()) for (self.function.operands(inst.data)) |operand| {
            if (operand == .none) continue;
            if (std.mem.indexOfScalar(ir.Ref, targets, self.function.resolve(operand)) != null) return true;
        };
        return false;
    }

    /// Whether two values are one: the same value, or constants of one kind with equal contents.
    fn sameConstant(self: *FnBuilder, left: ir.Ref, right: ir.Ref) bool {
        const x = self.function.resolve(left);
        const y = self.function.resolve(right);
        if (x == y) return true;
        const one = self.function.inst(x);
        const two = self.function.inst(y);
        if (one.op != two.op) return false;
        return switch (one.op) {
            .iconst => one.data == two.data,
            .str_const => std.mem.eql(u8, self.mb.module.strings.items[one.data], self.mb.module.strings.items[two.data]),
            else => false,
        };
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
        const record_type = self.module().storageType(self.typeOfRef(base));
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
        const record_type = self.module().storageType(self.typeOfRef(base));
        if (self.mb.module.kind(record_type) == .array) return self.arraySet(base, try self.constant(.u64, index), value, span);
        const fields = switch (self.mb.module.kind(record_type) orelse return self.mb.refuse(refuse_non_record, span)) {
            .record => self.mb.module.compound(record_type).record,
            else => return self.mb.refuse(refuse_non_record, span),
        };
        if (index >= fields.len) return self.mb.refuse(refuse_field_index, span);
        const stored = try self.boxFor(fields[index], value, span);
        return self.emit(.{ .op = .record_set, .ty = record_type, .a = base, .b = stored, .data = index, .span = span });
    }

    /// Deepest record-field path a `take`/`exchange` place may reach.
    const max_exchange_depth = 8;
    /// Refusal for a type with no empty value to leave behind.
    const refuse_no_empty = "take of a value without an empty form";

    /// `take(mut place)` and `exchange(mut place, value)` (LANG1 item 3). The replacement is built first (the type's
    /// empty value for `take`), then the place's field path is read and rebuilt around it. No step between a read and
    /// its store can trap, so the moved-out value is the owned result and the place keeps a valid value.
    fn placeExchange(self: *FnBuilder, place: typed.NodeId, value: ?typed.NodeId, ty: ir.Type, span: u32) Error!ir.Ref {
        const replacement = if (value) |id| try self.expression(id) else try self.emptyValue(ty, self.nodeOf(place).ty, span);
        if (self.current == null) return .none;
        // A list element or a `match mut` binding is reached through the receiver temporary the checker initialized from
        // it (G3 3A): the element is read once as a place read, and the replacement is stored back along its path, as
        // the list's own `exchange` does with one element.
        if (self.nodeOf(place).data == .local) {
            const slot = self.nodeOf(place).data.local;
            if (self.places.contains(self.local(slot))) {
                const old = try self.writableReceiverOf(slot, span);
                try self.writeOwner(slot, replacement, span);
                return old;
            }
        }
        var path: [max_exchange_depth]usize = undefined;
        const found = try self.exchangePath(place, &path, span);
        const root = try self.read(self.local(found.root), self.current.?);
        if (found.depth == 0) {
            try self.writeOwner(found.root, replacement, span);
            return root;
        }
        const exchanged = try self.exchangeField(root, path[0..found.depth], replacement, span);
        try self.writeOwner(found.root, exchanged.record, span);
        return exchanged.old;
    }

    /// The root local of a `take`/`exchange` place and the number of record fields it reaches; `path` receives them root first.
    fn exchangePath(self: *FnBuilder, place: typed.NodeId, path: *[max_exchange_depth]usize, span: u32) Error!struct { root: typed.LocalId, depth: usize } {
        var depth: usize = 0;
        var current = place;
        while (true) {
            const node = self.nodeOf(current);
            switch (node.data) {
                .local => |slot| {
                    std.mem.reverse(usize, path[0..depth]);
                    return .{ .root = slot, .depth = depth };
                },
                .field => |field| {
                    if (depth == max_exchange_depth) return self.mb.refuse("take of a field nested this deeply", span);
                    path[depth] = field.index;
                    depth += 1;
                    current = field.base;
                },
                else => return self.mb.refuse("take of a place that is not a record field of a local", span),
            }
        }
    }

    /// Read field `path[0]` of `record`, then rebuild `record` with it replaced: by `replacement` at the leaf, or by the
    /// rebuilt inner record otherwise. The old leaf value comes back owned.
    fn exchangeField(self: *FnBuilder, record: ir.Ref, path: []const usize, replacement: ir.Ref, span: u32) Error!struct { old: ir.Ref, record: ir.Ref } {
        const got = try self.fieldGet(record, path[0], span);
        if (path.len == 1) return .{ .old = got, .record = try self.fieldSet(record, path[0], replacement, span) };
        const inner = try self.exchangeField(got, path[1..], replacement, span);
        return .{ .old = inner.old, .record = try self.fieldSet(record, path[0], inner.record, span) };
    }

    /// The empty value `take` leaves behind: no characters, no octets, no elements, no entries, or `None` for an optional.
    fn emptyValue(self: *FnBuilder, ty: ir.Type, checked: typed.Type, span: u32) Error!ir.Ref {
        if (@import("selka").reference_tables.prelude.optionShape(checked, self.mb.input.program.records)) |option|
            return self.emit(.{ .op = .union_make, .ty = ty, .data = option.none, .span = span });
        if (ty == .str or ty == .bytes) {
            const index = self.mb.module.strings.items.len;
            try self.mb.module.strings.append(self.allocator(), "");
            return self.detached(.{ .op = .str_const, .ty = ty, .data = index, .span = span });
        }
        return switch (self.mb.module.kind(ty) orelse return self.mb.refuse(refuse_no_empty, span)) {
            .list => self.emit(.{ .op = .list_new, .ty = ty, .a = try self.constant(.u64, 0), .span = span }),
            .dict => self.emit(.{ .op = .dict_new, .ty = ty, .a = try self.constant(.u64, 0), .span = span }),
            else => self.mb.refuse(refuse_no_empty, span),
        };
    }

    /// The part of `base` that `step` reaches.
    fn stepGet(self: *FnBuilder, base: ir.Ref, step: Step, span: u32) Error!ir.Ref {
        switch (step) {
            .field => |index| return self.fieldGet(base, index, span),
            .element => |index| {
                const list_type = self.module().storageType(self.typeOfRef(base));
                if (self.mb.module.kind(list_type) == .array) return self.emit(.{ .op = .array_get, .ty = self.mb.module.compound(list_type).array.elem, .a = base, .b = index, .check = .exact, .span = span });
                if (self.mb.module.kind(list_type) == .dict) return self.emit(.{ .op = .dict_entry_value, .ty = self.mb.module.compound(list_type).dict.value, .a = base, .b = index, .span = span });
                if (self.mb.module.kind(list_type) != .list) return self.mb.refuse("element of a non-list value", span);
                return self.emit(.{ .op = .list_get, .ty = self.mb.module.compound(list_type).list, .a = base, .b = index, .check = .exact, .span = span });
            },
            .payload => |tag| return self.payloadOf(base, tag, span),
            .mapping => |key_ref| {
                const index = try build_dict.find(@TypeOf(self), self, base, key_ref, span);
                try build_dict.requirePresent(@TypeOf(self), self, index, span);
                return self.emit(.{ .op = .dict_entry_value, .ty = self.mb.module.compound(self.mb.module.storageType(self.typeOfRef(base))).dict.value, .a = base, .b = index, .span = span });
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
    pub fn listSet(self: *FnBuilder, list: ir.Ref, index: ir.Ref, value: ir.Ref, span: u32) Error!ir.Ref {
        const list_type = self.typeOfRef(list);
        if (self.mb.module.kind(list_type) == .dict) return self.emit(.{ .op = .dict_set_value, .ty = list_type, .a = list, .b = index, .data = try self.extraSlice(&.{value}), .span = span });
        if (self.mb.module.kind(list_type) != .list) return self.mb.refuse("element write of a non-list", span);
        const data = try self.extraSlice(&.{value});
        return self.emit(.{ .op = .list_set, .ty = self.typeOfRef(list), .a = list, .b = index, .data = data, .check = .exact, .span = span });
    }

    /// A checked field destination reconstructs its hidden read into the exact
    /// same slot. Preserve that transfer before store narrowing or ownership.
    pub fn transferSlotRead(self: *FnBuilder, value: typed.NodeId, collection: ir.Ref, index: ir.Ref) Error!?ir.Ref {
        const binding = @import("single_owner.zig").slotWritebackLocal(self.mb.input.program, self.checked, value) orelse return null;
        const slot = self.local(binding);
        const ref = self.function.resolve(try self.read(slot, self.current.?));
        const instruction = self.function.inst(ref);
        if (instruction.op != .list_get and instruction.op != .dict_entry_value) return null;
        if (instruction.data != 0 and instruction.data != flags.place_read) return null;
        const owner = self.function.resolve(collection);
        // Two reads of one place name one owner: for `rows[i][j].f = v` the hidden element read went through the
        // list `rows[i]`, and the write refreshes its receiver with a second read of that same element.
        if (!build_list_methods.sameRecordProjection(&self.function, instruction.a, owner)) return null;
        if (instruction.op == .dict_entry_value) {
            const probe = self.function.inst(self.function.resolve(instruction.b));
            if (probe.op != .dict_find or self.function.resolve(probe.a) != owner or self.function.resolve(probe.b) != self.function.resolve(index)) return null;
        } else if (self.function.resolve(instruction.b) != self.function.resolve(index)) return null;
        if (self.module().managed(instruction.ty)) self.function.insts.items[ref.index()].data = flags.place_read;
        return instruction.b;
    }

    fn storeInto(self: *FnBuilder, base: ir.Ref, steps: []const Step, value: ir.Ref, span: u32) Error!ir.Ref {
        return self.storeIntoBelow(base, steps, value, false, span);
    }

    /// `storeInto`, `below_payload` when an earlier step of the place took a union payload: a nested payload is then
    /// taken under a tag test of its own (`caseGuard`).
    fn storeIntoBelow(self: *FnBuilder, base: ir.Ref, steps: []const Step, value: ir.Ref, below_payload: bool, span: u32) Error!ir.Ref {
        if (steps.len == 0) return value;
        if (steps.len == 1) return self.stepSet(base, steps[0], value, span);
        const kind = self.mb.module.kind(self.typeOfRef(base));
        // A `match mut` write (C1) takes the payload out of its union and rebuilds the union around the new payload.
        if (self.exclusive_write and kind == .@"union" and steps[0] == .payload) {
            const tag = steps[0].payload;
            if (below_payload or self.projectsFromJoin(base)) try self.caseGuard(base, tag, span);
            const payload = try self.propagatedPayload(base, tag, span);
            if (payload == .none) return self.mb.refuse("write to an empty union case", span);
            const inner = try self.storeIntoBelow(payload, steps[1..], value, true, span);
            return self.payloadSet(base, tag, inner, span);
        }
        const indexed = kind == .list or kind == .dict;
        // Ownership chooses identity, count-tested detach, or copy before the
        // child read. The child can then take the slot's existing owner.
        const parent = try self.prepareParent(base, span);
        // A write back after a `mut` argument (`bump(mut v)`) reads the payload rather than taking it: tested the same way.
        if (steps[0] == .payload and (below_payload or self.projectsFromJoin(parent))) try self.caseGuard(parent, steps[0].payload, span);
        const child = try self.stepGet(parent, steps[0], span);
        if (indexed and self.mb.module.managed(self.typeOfRef(child))) self.function.insts.items[child.index()].data = flags.place_read;
        const inner = try self.storeIntoBelow(child, steps[1..], value, below_payload or steps[0] == .payload, span);
        if (kind == .dict) return self.listSet(parent, self.function.inst(child).b, inner, span);
        return self.stepSet(parent, steps[0], inner, span);
    }

    /// The value at `place` as its root stands now.
    pub fn readPlace(self: *FnBuilder, place: Place, span: u32) Error!ir.Ref {
        var value = try self.read(place.root, self.current.?);
        for (place.steps, 0..) |step, index| {
            if (step == .payload and (payloadBefore(place.steps[0..index]) or self.projectsFromJoin(value))) try self.caseGuard(value, step.payload, span);
            value = try self.stepGet(value, step, span);
        }
        return value;
    }

    /// Whether a union payload read or taken from `value`, a field of a record (FX7b), is one the union-tag rule cannot
    /// justify from the `match mut`'s own tag test, so it is tested where it is made (`caseGuard`). The rule relates two
    /// reads of one field of one record value (shape R) and a read after a store into that field (shape S). A field read
    /// of another field read (`w.range.high`: each use reads `w.range` again), of a list or dictionary element (each use
    /// reads the element again), or of a `phi` (a container written back in a loop or on one side of an `if`) is none
    /// of those, and neither is a union that is itself such a `phi`.
    fn projectsFromJoin(self: *FnBuilder, value: ir.Ref) bool {
        const inst = self.function.inst(self.function.resolve(value));
        // A union written back in a loop is a header `phi` the loop body makes again, which ends the `phi`'s facts (shape
        // P); a `phi` where two branches join keeps them and is justified by shape P.
        if (inst.op == .phi) return self.loopPhi(self.function.resolve(value));
        if (inst.op != .record_get) return false;
        const base = self.function.inst(self.function.resolve(inst.a));
        return switch (base.op) {
            .record_get, .phi, .list_get, .dict_entry_value, .array_get => true,
            // A store into another field of the record (`h.tag = x` beside `match mut h.shape`, FX9) is a new record value
            // the tested read is no twin of, and shape S covers only a store into the same field.
            .record_set => base.data != inst.data,
            else => false,
        };
    }

    /// Whether `phi` joins a loop's back edge: it is still incomplete (its loop header is not sealed, so the read is in
    /// the loop's body), or it lies in the header of a loop built already.
    fn loopPhi(self: *FnBuilder, phi: ir.Ref) bool {
        var pending = self.ssa.incomplete.valueIterator();
        while (pending.next()) |phis| for (phis.items) |entry| if (entry.phi == phi) return true;
        for (self.function.loops.items) |loop| {
            if (std.mem.indexOfScalar(ir.Ref, self.function.blocks.items[loop.header.index()].insts.items, phi) != null) return true;
        }
        return false;
    }

    /// Whether a step of `steps` takes a union payload.
    fn payloadBefore(steps: []const Step) bool {
        for (steps) |step| if (step == .payload) return true;
        return false;
    }

    /// Test that `value`, a union a place reaches below another union's payload (a nested `match mut`: `match mut o:` then
    /// `match mut sh:` on its binding), is in case `tag` where its payload is read or taken (FX7). A binding's place is
    /// projected again from the held container at each use, and the inner match tested the tag of another projection,
    /// which the union-tag rule (F-VL-10) does not relate to this one; this test is made where the payload is read, so
    /// the rule justifies the read. While the container is held the case cannot change and the test never fails; when
    /// it does, the program traps (`R_CORE_FACT`) instead of reading another case's payload.
    fn caseGuard(self: *FnBuilder, value: ir.Ref, tag: u32, span: u32) Error!void {
        const case = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = value, .span = span });
        const expected = try self.constant(.u32, tag);
        const holds = try self.emit(.{ .op = .cmp, .ty = .bool, .a = case, .b = expected, .data = @backingInt(ir.Predicate.eq), .span = span });
        const passed = try self.newBlock();
        const failed = try self.newBlock();
        try self.branch(holds, passed, failed, span);
        try self.seal(failed);
        self.current = failed;
        _ = try self.emit(.{ .op = .@"unreachable", .ty = .void, .data = flags.case_trap, .span = span });
        try self.seal(passed);
        self.current = passed;
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
        if (try self.exclusiveRead(slot, out, span)) |fresh| return fresh;
        if (self.isView(ty)) if (self.places.get(self.local(slot))) |source| {
            if (out) |place| place.* = source;
            const dict = try self.readPlace(source, span);
            return self.viewValue(self.ssa.types.items[self.local(slot)], dict, span);
        };
        if (try self.reprojected(slot, span)) |fresh| {
            // The binding still names the place it was bound to, so a binding made from it (`for c in r.checks` after a write
            // to the record the loop variable `r` lies in) is projected from that record too, as it is before the write.
            if (out) |place| place.* = try self.placeOfLocal(slot);
            return fresh;
        }
        if (out) |place| {
            place.* = try self.placeOfLocal(slot);
            if (place.*.?.snapshot == .none) place.*.?.snapshot = try self.read(place.*.?.root, self.current.?);
        }
        return self.lentWhole(try self.read(self.local(slot), self.current.?), span);
    }

    /// A `match mut` binding read now (C1): it is a name for its place, so each use projects it from the exclusively held
    /// container, and it never has an SSA value of its own (reading one gives `undef`, the null owner: FX12). Null for any
    /// other local.
    fn exclusiveRead(self: *FnBuilder, slot: typed.LocalId, out: ?*?Place, span: u32) Error!?ir.Ref {
        if (!self.exclusive_locals.contains(self.local(slot))) return null;
        const found = self.places.get(self.local(slot)) orelse return null;
        const fresh = try self.currentPlace(found);
        if (out) |place| place.* = fresh;
        const value = try self.readPlace(fresh, span);
        return value;
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
            if (entry.value_ptr.root == variable) return self.mb.refuseOwnership("rebinding the source place of a live dictionary view", span);
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
                .exposed => return self.mb.refuseOwnership("aggregate or captured dictionary alias combined with a live view", span),
                .unknown => return self.mb.refuseOwnership("live dictionary view with unproved source identity", span),
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

    /// A `todo[T]()` hole checked in trap mode: evaluating it traps `R_TYPED_HOLE` at `span`. The trap is the
    /// only way out, so the continuation carries an undefined value of the declared type, which keeps the
    /// surrounding expression lowering; no run reaches it.
    fn typedHole(self: *FnBuilder, ty: ir.Type, span: u32) Error!ir.Ref {
        const trap = try self.newBlock();
        const after = try self.newBlock();
        try self.branch(try self.constant(.bool, 1), trap, after, span);
        try self.seal(trap);
        self.current = trap;
        _ = try self.emit(.{ .op = .@"unreachable", .ty = .void, .data = flags.typed_hole_trap, .span = span });
        try self.seal(after);
        self.current = after;
        return self.emit(.{ .op = .undef, .ty = ty, .span = span });
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
            .hole => return self.typedHole(try self.typeOf(id), span),
            .place_exchange => |exchange| return self.placeExchange(exchange.place, exchange.value, try self.typeOf(id), span),
            .local => |slot| return self.localExpression(slot, n.ty, out, span),
            .borrow_selection => |choice| return @import("build_borrow_selection.zig").lower(@TypeOf(self), self, choice, n.ty, try self.typeOf(id), span),
            .block_value => |block| {
                try self.statement(block.body);
                return self.expressionPlace(block.value, out);
            },
            .binary => |b| return self.binary(b.op, b.left, b.right, @intCast(b.op_span.start), null),
            .unary => |u| return self.unary(u.op, u.operand, try self.typeOf(id), @intCast(u.op_span.start)),
            .cast => |operand| {
                if (try self.enumCast(id, operand, span)) |lowered| return lowered;
                return self.cast(operand, try self.typeOf(id), span);
            },
            .wrap => |operand| return self.wrap(operand, try self.typeOf(id), span),
            .float_fma => |fused| return self.fusedMultiplyAdd(fused.a, fused.b, fused.c, span),
            .byte_load => |load| return self.byteLoadRead(load, try self.typeOf(id), span),
            .vector_binary => |vector| return self.vectorBinary(vector.op, vector.left, vector.right, try self.typeOf(id), span),
            .vector_neg => |vector| return self.vectorNeg(vector.operand, span),
            .vector_sqrt => |vector| return self.vectorSqrt(vector.operand, span),
            .vector_convert => |vector| return self.vectorConvert(vector.operand, try self.typeOf(id), span),
            .vector_select => |selection| return self.vectorSelect(selection.mask, selection.a, selection.b, try self.typeOf(id), span),
            .unwrap => |operand| {
                const value = try self.expression(operand);
                if (value == .none) return .none;
                // A domain is its wire type, and a `float` unwraps to its bits only as the prelude spells it.
                if (self.function.inst(value).ty == .f64 or self.function.inst(value).ty == .f32 or self.function.inst(value).ty == try self.typeOf(id)) return value;
                return self.mb.refuse("unwrap", span);
            },
            .call => |c| return self.call(c.function, c.arguments, c.evaluation_order, span),
            .buffer_operation => |operation| return self.borrowedTextSlice(try self.bufferOperation(operation, try self.typeOf(id), span, out), id),
            .acquire_buffer => |acquire| {
                var capacity = try self.expression(acquire.capacity);
                const buffer_type = try self.typeOf(id);
                if (buffer_type.isSpan()) return self.mb.refuse("construct a borrowed view with a slice", span);
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
                if (try self.borrowedRecord(id)) return self.borrowedRecordMake(id, fields, span);
                return self.recordMake(id, fields, span);
            },
            .update => |update| return self.recordUpdate(update.base, update.fields, span),
            .field => return self.fieldExpression(id, out, span),
            .function_value => |callee| {
                const declared = try self.mb.functionIndex(callee);
                // A function that takes a borrowed view is reached through its owned-`str` adapter.
                const expected = self.mb.module.compound(try self.typeOf(id)).@"fn".params;
                const index = (try @import("build_value_adapter.zig").valueIndex(self.allocator(), &self.mb.module, declared, expected)) orelse return self.mb.refuseOwnership("function value of a view result", span);
                try self.mb.touch(index);
                return self.detached(.{ .op = .func_ref, .ty = try self.typeOf(id), .data = index, .span = span });
            },
            .invoke => |invocation| return self.invoke(invocation.callee, invocation.arguments, invocation.evaluation_order, span),
            .replace => |replacement| return self.arrayReplace(replacement, span),
            .propagate => |try_value| return self.tryValue(try_value.value, try_value.output, span),
            .print => |print| return self.printNode(print, span),
            .stream_flush => |flush| {
                const stream = try self.expression(flush.stream);
                try @import("build_cap.zig").streamFlush(*FnBuilder, self, stream, span);
                return .none;
            },
            .format => |format| return build_format.string(*FnBuilder, self, format, span),
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
            .accept_resource,
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
            .task_group_open => return self.refuse("invalid checked task group outside its `with` scope", span),
            // A bare submit is a statement: its index is discarded, so it has no value.
            .task_submit => |submitted| {
                const index = try build_task.submit(*FnBuilder, self, submitted.group, submitted.call, span);
                return if (n.ty == .unit) .none else index;
            },
            .task_result => |handle| return build_task.result(*FnBuilder, self, handle, n.ty, span),
        }
    }

    /// Transfer a checked owning field, or read it while preserving its place.
    fn fieldExpression(self: *FnBuilder, id: typed.NodeId, out: ?*?Place, span: u32) Error!ir.Ref {
        if (try self.takesRecordField(id)) {
            if (self.field_moves.groups.find(id)) |move| return self.groupedField(id, move, span);
            return self.takeRecordField(id, span);
        }
        const node = self.nodeOf(id);
        const field = node.data.field;
        var base_place: ?Place = null;
        const base = try self.expressionPlace(field.base, if (out != null) &base_place else null);
        if (self.current == null) return .none;
        const value = try self.fieldGet(base, field.index, span);
        if (out) |place| if (base_place) |found| {
            place.* = try self.fieldPlace(field, found, span);
        };
        return if (node.ty == .unit) .none else value;
    }

    /// A generic scalar instance reads its field despite the template's marker.
    fn takesRecordField(self: *FnBuilder, id: typed.NodeId) Error!bool {
        const node = self.nodeOf(id);
        return node.own and node.data == .field and self.module().managed(try self.typeOf(id));
    }

    /// FR91: a move of a group (`field_moves.zig`), one of several fields a statement moves out of one record: its field
    /// path is taken from the fields the group's first move opened.
    fn groupedField(self: *FnBuilder, id: typed.NodeId, move: field_moves.Move, span: u32) Error!ir.Ref {
        const opened = try self.openedFields(move, span);
        if (self.current == null) return .none;
        return self.takeOpenedField(id, opened, span);
    }

    /// FR91: the fields of the record a group moves out of, opened at the group's first move. The record goes into a
    /// one-field wrapper (`record_make`) whose `record_take` is a fresh owned record in this block, and each field of that is
    /// read once here, so ownership empties it (`own.zig`, `empty`: the dissolution J8 checks, as `match own` does with its
    /// `union_take`) and drops the fields no move names at this point. A parameter is never emptied itself (D-G-1); the
    /// wrapper's take is, with the operations the table has.
    fn openedFields(self: *FnBuilder, move: field_moves.Move, span: u32) Error![]const ir.Ref {
        for (self.field_moves.opened.items) |opened| if (opened.root == move.root) return opened.fields;
        const record = try self.expression(move.local);
        if (self.current == null) return &.{};
        const ty = self.typeOfRef(record);
        const wrapper = try self.module().intern(self.allocator(), .{ .record = &.{ty} });
        const wrapped = try self.emit(.{ .op = .record_make, .ty = wrapper, .data = try self.extraSlice(&.{record}), .span = span });
        const fresh = try self.emit(.{ .op = .record_take, .ty = ty, .a = wrapped, .data = 0, .span = span });
        const stored = self.module().compound(ty).record;
        const fields = try self.allocator().alloc(ir.Ref, stored.len);
        for (stored, fields, 0..) |field, *slot, index| slot.* = try self.emit(.{ .op = .record_get, .ty = field, .a = fresh, .data = index, .span = span });
        try self.field_moves.opened.append(self.allocator(), .{ .root = move.root, .fields = fields });
        return fields;
    }

    /// FR91: the field path `id` of a group's move, from the opened fields of its root: the path's first field is its read,
    /// and each deeper field is taken out of the one above as `takeRecordField` takes it.
    fn takeOpenedField(self: *FnBuilder, id: typed.NodeId, opened: []const ir.Ref, span: u32) Error!ir.Ref {
        const field = self.nodeOf(id).data.field;
        const selected = if (self.nodeOf(field.base).data == .field) taken: {
            const base = try self.takeOpenedField(field.base, opened, span);
            if (self.current == null) return .none;
            const stored = self.module().compound(self.typeOfRef(base)).record[field.index];
            break :taken try self.emit(.{ .op = .record_take, .ty = stored, .a = base, .data = field.index, .span = span });
        } else opened[field.index];
        const stored = self.typeOfRef(selected);
        if (self.module().kind(stored) != .box) return selected;
        return self.emit(.{ .op = .box_take, .ty = self.module().compound(stored).box, .a = selected, .span = span });
    }

    /// Whether a field node moves out of its record: the lowering's test for `field_moves.of`.
    fn takesGroupedField(self: *FnBuilder, id: typed.NodeId) Error!bool {
        return self.takesRecordField(id);
    }

    /// A checked field transfer consumes every enclosing record immediately.
    /// The source checker has already proved the root is an independent owner.
    fn takeRecordField(self: *FnBuilder, id: typed.NodeId, span: u32) Error!ir.Ref {
        const field = self.nodeOf(id).data.field;
        const base_node = self.nodeOf(field.base);
        const base = if (base_node.data == .field)
            try self.takeRecordField(field.base, span)
        else
            try self.expression(field.base);
        if (self.current == null) return .none;
        const record_type = self.typeOfRef(base);
        const stored = self.module().compound(record_type).record[field.index];
        const selected = try self.emit(.{ .op = .record_take, .ty = stored, .a = base, .data = field.index, .span = span });
        if (self.module().kind(stored) != .box) return selected;
        return self.emit(.{ .op = .box_take, .ty = self.module().compound(stored).box, .a = selected, .span = span });
    }

    /// Preserve the written fixed-array index for the ordinary unsigned bounds check.
    fn arrayIndex(self: *FnBuilder, index: ir.Ref, span: u32) Error!ir.Ref {
        if (self.mb.module.kind(self.typeOfRef(index)) == .@"union") return self.emit(.{ .op = .union_tag, .ty = .u32, .a = index, .span = span });
        return index;
    }

    /// Read a dictionary or array element and remember its place for mut write-back.
    fn arrayGet(self: *FnBuilder, id: typed.NodeId, span: u32, out: ?*?Place) Error!ir.Ref {
        const index = self.nodeOf(id).data.index;
        var base_place: ?Place = null;
        const base = try self.expressionPlace(index.base, if (out != null) &base_place else null);
        const captured = self.ssa.array_indices.get(id);
        const raw = if (captured == null) try self.expression(index.index) else ir.Ref.none;
        if (self.current == null) return .none;
        const ty = self.module().storageType(self.typeOfRef(base));
        const dictionary = self.mb.module.kind(ty) == .dict;
        if (!dictionary and self.mb.module.kind(ty) != .array) return self.mb.refuse("index of a non-array", span);
        const at = captured orelse if (dictionary) try build_dict.find(@TypeOf(self), self, base, raw, span) else try self.arrayIndex(raw, span);
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
        const shared = if (self.mb.module.kind(self.typeOfRef(base)) == .array) self.reconstructedIndex(replacement) else null;
        if (shared) |index| {
            const normalized = try self.arrayIndex(raw, span);
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
        return self.arraySet(base, try self.arrayIndex(raw, span), value, span);
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
        if (projection.base != replacement.base or projection.index != replacement.index) return null;
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
        // A borrowed record payload (1A) is lent as its storage type: the union borrows it and is never dropped.
        if (payload != .none and self.module().isBorrowed(self.typeOfRef(payload)) and self.module().storageType(self.typeOfRef(payload)) == cases[tag])
            payload = try self.borrowStorage(payload, span);
        if (payload != .none) payload = try self.boxFor(cases[tag], payload, span);
        const made = try self.emit(.{ .op = .union_make, .ty = ty, .a = payload, .data = tag, .span = span });
        if (typed.resultShape(self.nodeOf(id).ty, self.mb.input.program.records)) |shape| {
            if (shape.error_tag == tag) _ = try self.emit(.{ .op = .err_trace, .ty = .void, .data = @backingInt(ir.TraceMode.origin), .span = span });
        }
        return made;
    }

    /// Whether constructor `id` is a borrowed record (1A, `single_owner.BorrowedRecords`): the checker accepted it only where a
    /// borrow may stand, so it is built as a read-only overlay.
    pub fn borrowedRecord(self: *FnBuilder, id: typed.NodeId) Error!bool {
        if (self.borrowed_records == null) self.borrowed_records = try @import("single_owner.zig").BorrowedRecords.init(
            self.allocator(),
            self.mb.input.program,
            try self.mb.linearTypes(),
            self.checked,
            try self.mb.casePayloads(),
        );
        return self.borrowed_records.?.constructor(id);
    }

    /// Whether `id` initializes a `const` local as a borrowed option (H2, `single_owner.BorrowedRecords.lentLocalOption`): the
    /// checker accepted it only where a borrow may stand, so the local holds the lent union of its payload.
    pub fn lentLocalOption(self: *FnBuilder, id: typed.NodeId) Error!bool {
        _ = try self.borrowedRecord(id);
        return self.borrowed_records.?.lentLocalOption(id);
    }

    /// A borrowed record (1A): each managed field is lent (a `borrow` of its place's storage, never consumed), and the record
    /// is made with the read-only overlay of its type, so the ownership pass gives it the fields as parents and never drops it.
    fn borrowedRecordMake(self: *FnBuilder, id: typed.NodeId, fields: []const typed.FieldInit, span: u32) Error!ir.Ref {
        const ty = try self.typeOf(id);
        if (self.mb.module.kind(ty) != .record) return self.mb.refuse("borrowed record type", span);
        const stored = self.mb.module.compound(ty).record;
        const values = try self.allocator().alloc(ir.Ref, stored.len);
        @memset(values, .none);
        const table = self.borrowed_records.?;
        for (fields) |init| {
            if (init.index >= stored.len) return self.mb.refuse(refuse_field_index, span);
            // `Some(p)` of a read-only record parameter (O4) holds the parameter in place.
            if (table.lentOption(init.value) != null) {
                values[init.index] = try @import("build_frame_box.zig").lent(*FnBuilder, self, init.value, stored[init.index], span);
                if (self.current == null) return .none;
                continue;
            }
            var value = try self.expression(init.value);
            if (self.current == null) return .none;
            const field_type = stored[init.index];
            // A bare read-only text, bytes or list parameter (RB1) is held as its frame block.
            if (table.framedRead(init.value)) value = try self.frameBlock(value, span);
            if (self.mb.module.managed(field_type) and self.nodeOf(init.value).data != .array) {
                const actual = self.typeOfRef(value);
                if (actual.isSpan() or self.isListView(actual)) return self.mb.refuseOwnership("a view as a field of a borrowed record", span);
                value = try self.borrowStorage(try self.readOnlyArgument(value, try self.module().borrowedType(self.allocator(), self.module().storageType(actual)), span), span);
            }
            if (self.typeOfRef(value) != field_type) return self.mb.refuse("borrowed record field type", span);
            values[init.index] = value;
        }
        for (values) |value| if (value == .none) return self.mb.refuse("record field without a value", span);
        const overlay = try self.module().borrowedType(self.allocator(), ty);
        return self.emit(.{ .op = .record_make, .ty = overlay, .data = try self.extraSlice(values), .span = span });
    }

    /// The block a borrowed record holds for parameter view `view` (RB1, `ir.Op.block_frame`): the parameter's C9 owner
    /// when the caller passed a whole value, else this call's frame copy. A parameter that already arrives as a block is
    /// held as it is.
    pub fn frameBlock(self: *FnBuilder, view: ir.Ref, span: u32) Error!ir.Ref {
        const viewed = self.typeOfRef(view);
        const owned: ir.Type = if (viewed == .str_view) .str else if (viewed == .bytes_view) .bytes else if (self.isListView(viewed))
            try self.module().intern(self.allocator(), .{ .list = self.module().compound(viewed).list_view })
        else
            return view;
        const owner: ir.Ref = if (owned == .bytes) .none else self.view_owner.get(@intCast(self.function.resolve(view).index())) orelse
            return self.mb.refuseOwnership("a frame block of a view that is not a parameter", span);
        return self.emit(.{ .op = .block_frame, .ty = owned, .a = view, .b = owner, .span = span });
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
            // The checker refused a conversion that no case or several cases fit; lowering never picks one.
            const case = if (converted) typed.errorCaseFit(records, wanted.error_type, shape.error_type).unique() orelse return self.mb.refuse("error conversion without exactly one fitting case", span) else 0;
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
            const target = self.failureType(result, wanted.error_tag);
            const stored = self.mb.module.compound(target).@"union"[wanted.error_tag];
            const failure = try self.emit(.{ .op = .union_make, .ty = target, .a = try self.boxFor(stored, error_value, span), .data = wanted.error_tag, .span = span });
            try self.returnValue(failure, span);
            self.current = succeeded;
            return self.successPayload(input, shape.ok_tag, span);
        }
        const none_tag = optionNoneTag(records, input_type) orelse return self.mb.refuse("propagation of a non-result", span);
        _ = optionNoneTag(records, output) orelse return self.mb.refuse("propagation into a non-option", span);
        const is_none = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try self.constant(.u32, @intCast(none_tag)), .data = @backingInt(ir.Predicate.eq), .span = span });
        try self.branch(is_none, failed, succeeded, span);
        try self.seal(failed);
        try self.seal(succeeded);
        self.current = failed;
        const none = try self.emit(.{ .op = .union_make, .ty = self.failureType(result, none_tag), .data = none_tag, .span = span });
        try self.returnValue(none, span);
        self.current = succeeded;
        return self.successPayload(input, 1 - none_tag, span);
    }

    /// The union type in which `try` builds its failure. A function that returns a borrow declares a logical result
    /// whose success case is a view; the failure case holds the same payload there as in the owned result, so the
    /// failure is made in the logical type directly. Converting an owned result afterwards would wrap a view of its
    /// dead success case, a loan on a value the return then drops.
    fn failureType(self: *FnBuilder, owned: ir.Type, tag: usize) ir.Type {
        const logical = self.declared_ret;
        if (logical == owned or logical == .void) return owned;
        if (return_borrow.effectiveSources(self.mb.input.program.records, self.checked.signature).len == 0) return owned;
        if (self.module().kind(logical) != .@"union") return owned;
        const made = self.module().compound(owned).@"union";
        const wanted = self.module().compound(logical).@"union";
        if (made.len != wanted.len or made[tag] != wanted[tag]) return owned;
        return logical;
    }

    /// The success payload `try` hands on. An owned payload moves out of the consumed result; a borrowed one (a call's
    /// `from` result) is a view that only a view operation may define, so it is read in place like a matched payload
    /// and the ownership pass drops the rest of the result.
    fn successPayload(self: *FnBuilder, input: ir.Ref, tag: usize, span: u32) Error!ir.Ref {
        const stored = self.module().compound(self.module().storageType(self.typeOfRef(input))).@"union"[tag];
        if (stored != .void and self.module().containsBorrow(stored)) return self.payloadOf(input, tag, span);
        return self.propagatedPayload(input, tag, span);
    }

    // The source contract consumes a propagated or freshly matched union. Preserve that
    // transfer in IR, including the ownership of a recursive boxed payload.
    fn propagatedPayload(self: *FnBuilder, input: ir.Ref, tag: usize, span: u32) Error!ir.Ref {
        const stored = self.module().compound(self.module().storageType(self.typeOfRef(input))).@"union"[tag];
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

    fn borrowedReturnExpression(self: *FnBuilder, id: typed.NodeId, ty: typed.Type, target: ir.Type, span: u32) Error!ir.Ref {
        const node = self.nodeOf(id);
        if (self.module().kind(target) == .list_view) {
            if (try self.listSliceView(id, target, span)) |view| return view;
            // `return []` beside borrows (4e): a view of the runtime's static empty list, an immortal constant, as
            // `return ""` is a view of a constant text. Nothing is allocated, and the result borrows no owner.
            if (try self.staticEmptyList(id, span)) |empty| return self.listWholeView(empty, target, span);
        }
        if (node.data == .block_value) {
            try self.statement(node.data.block_value.body);
            if (self.current == null) return .none;
            return self.borrowedReturnExpression(node.data.block_value.value, ty, target, span);
        }
        if (return_borrow.step(self.mb.input.program.records, ty)) |step| {
            if (node.data == .variant and node.ty == ty) {
                const variant = node.data.variant;
                const cases = self.module().compound(target).@"union";
                var payload: ir.Ref = .none;
                if (variant.value) |value| {
                    payload = if (variant.tag == step.tag)
                        try self.borrowedReturnExpression(value, step.payload, cases[variant.tag], span)
                    else
                        try self.expression(value);
                }
                if (self.current == null) return .none;
                return self.emit(.{ .op = .union_make, .ty = target, .a = payload, .data = variant.tag, .span = span });
            }
        }
        return self.convertBorrowedReturn(try self.expression(id), ty, target, span);
    }

    /// The runtime's static empty list for an empty list literal `[]` in a position that borrows it (4e, 4c): a returned
    /// borrow, or the default of `unwrap_or` or `dicts.get`. It is an immortal constant (`text_sentinel` of the list type),
    /// so the value borrows no owner and nothing is allocated or dropped. Null for any other value.
    pub fn staticEmptyList(self: *FnBuilder, id: typed.NodeId, span: u32) Error!?ir.Ref {
        if (!@import("single_owner.zig").emptyListLiteral(self.mb.input.program, id)) return null;
        const ty = try self.typeOf(id);
        if (self.mb.module.kind(ty) != .list) return null;
        const empty = try self.detached(.{ .op = .text_sentinel, .ty = ty, .span = span });
        return empty;
    }

    fn convertBorrowedReturn(self: *FnBuilder, value: ir.Ref, ty: typed.Type, target: ir.Type, span: u32) Error!ir.Ref {
        if (value == .none or self.current == null) return .none;
        const actual = self.typeOfRef(value);
        if (actual == target) return value;
        if (return_borrow.step(self.mb.input.program.records, ty)) |step| {
            return self.borrowedWrapper(value, target, step.tag, span);
        }
        if (self.module().isBorrowed(target)) {
            try self.refuseHiddenViewCopy(actual, span);
            return self.emit(.{ .op = .borrow, .ty = target, .a = value, .span = span });
        }
        if (target.isSpan()) {
            if (try self.sliceAsView(value)) |view| return view;
            return self.wholeView(value, span);
        }
        if (self.module().kind(target) == .list_view) return self.listWholeView(value, target, span);
        return self.mb.refuse("invalid declared borrowed result representation", span);
    }

    /// Refuse a borrow of a text or bytes view (Z3, `hiddenViewBorrow`), in every build mode.
    fn refuseHiddenViewCopy(self: *FnBuilder, actual: ir.Type, span: u32) Error!void {
        if (hiddenViewBorrow(actual)) |reason| return self.refuseOwnership(reason, span);
    }

    /// Adapt a read-only argument or selected payload without copying its storage.
    pub fn readOnlyArgument(self: *FnBuilder, value: ir.Ref, target: ir.Type, span: u32) Error!ir.Ref {
        const actual = self.typeOfRef(value);
        if (actual == target) return value;
        const stored = self.module().storageType(actual);
        // Recursive wrapper payloads are boxed in owning storage. A nested
        // wrapper's read-only payload layout can differ from its owned layout,
        // so load it before either rebuilding its tags or applying its overlay.
        if (self.module().kind(stored) == .box) {
            const child = self.module().compound(stored).box;
            const wrapper = self.module().kind(child) == .@"union" and self.module().kind(target) == .@"union" and self.module().containsBorrow(target);
            if (child == self.module().storageType(target) or wrapper) {
                const payload = try self.unbox(try self.borrowStorage(value, span), span);
                return self.readOnlyArgument(payload, target, span);
            }
        }
        if (self.module().isBorrowed(target)) {
            try self.refuseHiddenViewCopy(actual, span);
            return self.emit(.{ .op = .borrow, .ty = target, .a = try self.borrowStorage(value, span), .span = span });
        }
        if (target.isSpan()) {
            if (try self.sliceAsView(value)) |view| return view;
            return self.wholeView(value, span);
        }
        if (self.isListView(target)) return self.listWholeView(value, target, span);
        if (self.module().kind(target) == .@"union") return self.borrowedWrapper(value, target, 0, span);
        return self.borrowStorage(value, span);
    }

    fn borrowedWrapper(self: *FnBuilder, value: ir.Ref, target: ir.Type, tag_index: usize, span: u32) Error!ir.Ref {
        const source_cases = self.module().compound(self.module().storageType(self.typeOfRef(value))).@"union";
        const cases = self.module().compound(target).@"union";
        const output = try self.synthetic(target);
        const tag = try self.emit(.{ .op = .union_tag, .ty = .u32, .a = value, .span = span });
        const yes = try self.newBlock();
        const no = try self.newBlock();
        const done = try self.newBlock();
        const some = try self.emit(.{ .op = .cmp, .ty = .bool, .a = tag, .b = try self.constant(.u32, @intCast(tag_index)), .data = @backingInt(ir.Predicate.eq), .span = span });
        try self.branch(some, yes, no, span);
        try self.seal(yes);
        self.current = yes;
        const payload = if (source_cases[tag_index] == .void) ir.Ref.none else try self.emit(.{ .op = .union_payload, .ty = source_cases[tag_index], .a = value, .data = tag_index, .span = span });
        const borrowed = if (payload == .none) payload else try self.readOnlyArgument(payload, cases[tag_index], span);
        const present = try self.emit(.{ .op = .union_make, .ty = target, .a = borrowed, .data = tag_index, .span = span });
        try self.write(output, self.current.?, present);
        try self.jump(done);
        try self.seal(no);
        self.current = no;
        const other = 1 - tag_index;
        const raw = if (source_cases[other] == .void) ir.Ref.none else try self.emit(.{ .op = .union_payload, .ty = source_cases[other], .a = value, .data = other, .span = span });
        const untouched = if (raw == .none) raw else try self.readOnlyArgument(raw, cases[other], span);
        const absent = try self.emit(.{ .op = .union_make, .ty = target, .a = untouched, .data = other, .span = span });
        try self.write(output, self.current.?, absent);
        try self.jump(done);
        try self.seal(done);
        self.current = done;
        return self.read(output, done);
    }

    /// End the function with `result`. A function with `mut` parameters returns a record of its
    /// result (unless `unit`) and the final value of each `mut` parameter.
    fn returnValue(self: *FnBuilder, result: ir.Ref, span: u32) Error!void {
        try build_cap.closeScopes(*FnBuilder, self, 0, span);
        const mutated = self.checked.signature.declared_mutates;
        var value = if (return_borrow.effectiveSources(self.mb.input.program.records, self.checked.signature).len != 0)
            try self.convertBorrowedReturn(result, self.checked.signature.return_type, self.declared_ret, span)
        else
            result;
        if (mutated.len != 0) {
            var parts: std.ArrayList(ir.Ref) = .empty;
            defer parts.deinit(self.allocator());
            if (self.declared_ret != .void) try parts.append(self.allocator(), value);
            for (mutated) |position| {
                try parts.append(self.allocator(), try self.read(position, self.current.?));
            }
            value = if (parts.items.len == 1) parts.items[0] else try self.emit(.{ .op = .record_make, .ty = self.function.signature.ret, .data = try self.extraSlice(parts.items), .span = span });
        }
        _ = try self.emit(.{ .op = .ret, .ty = .void, .a = if (self.function.signature.ret == .void) .none else value, .span = span });
        self.current = null;
    }

    /// `left op right`. `compared`, given for an `assert`'s comparison, receives the two operand values as evaluated.
    fn binary(self: *FnBuilder, op: typed.BinaryOp, left_node: typed.NodeId, right_node: typed.NodeId, span: u32, compared: ?*Compared) Error!ir.Ref {
        if (op == .logical_and or op == .logical_or) return self.shortCircuit(op == .logical_or, left_node, right_node, span);
        var left = try self.expression(left_node);
        var right = try self.expression(right_node);
        if (compared) |into| if (self.current != null) {
            into.* = .{ .left = left, .right = right };
        };
        // An equality reads both octet runs: a borrowed piece compares in place, with no copy.
        // A bytes slice compared for equality is only read: its octets are borrowed, not copied (C9 bytes).
        if ((op == .eq or op == .ne) and self.current != null) {
            // A byte buffer is compared as a buffer: a slice of one beside a buffer that is no slice is a new buffer like it, and
            // only a slice beside octets (or another slice) is read in place (FR27).
            const left_whole = self.wholeBuffer(left);
            const right_whole = self.wholeBuffer(right);
            if (!right_whole) left = try self.borrowComparedSlice(left, left_node);
            if (!left_whole) right = try self.borrowComparedSlice(right, right_node);
        }
        if ((op == .eq or op == .ne) and self.current != null and self.spanComparable(left, right)) return self.spanEquality(op == .eq, left, right, span);
        // An operator reads owned values; a view binding lends its octets to a
        // comparison or a concatenation only through a copy of its own family.
        // A concatenation's operands are read by a new value (`+`), so their copies are written.
        if (op == .add) {
            // A text view on the left is copied once, by the concatenation's own copy of its owner
            // (`aggregateCompare`), so it is not materialized twice.
            const text_view_left = self.typeOfRef(left) == .str_view and self.ownedFamily(left_node) == .text;
            // A bytes view is read in place by the concatenation (C9 bytes): its octets are the new value's source.
            const bytes_view_left = self.typeOfRef(left) == .bytes_view and self.ownedFamily(left_node) == .bytes;
            const bytes_view_right = self.typeOfRef(right) == .bytes_view and self.ownedFamily(right_node) == .bytes;
            if (!text_view_left and !bytes_view_left) left = try self.materializeWritten(left, self.ownedFamily(left_node), span);
            if (!bytes_view_right) right = try self.materializeWritten(right, self.ownedFamily(right_node), span);
        } else {
            // An ordering of two texts (or two bytes) compares their octets in place (`aggregateCompare`'s span form, C9).
            const span_ordering = (op == .lt or op == .le or op == .gt or op == .ge) and self.ownedFamily(left_node) == self.ownedFamily(right_node);
            const text_ordering = span_ordering;
            if (!text_ordering) {
                left = try self.materializeAs(left, self.ownedFamily(left_node), span);
                right = try self.materializeAs(right, self.ownedFamily(right_node), span);
            }
        }
        if (self.current == null) return .none;
        if (self.nodeOf(left_node).ty == .unit and (op == .eq or op == .ne))
            return self.constant(.bool, @intFromBool(op == .eq));
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
        const compare_aggregate = ty == .str or ty.isSpan() or ty == .bytes or ty == .byte_buffer;
        if (compare_aggregate or ty.isCompound()) return self.aggregateCompare(op, left, right, span);
        const is_float = ty == .f64 or ty == .f32;
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
            .f64_eq, .f32_eq => .{ .op = .fcmp, .predicate = .eq },
            .f64_lt, .f32_lt => .{ .op = .fcmp, .predicate = .lt },
            .f64_le, .f32_le => .{ .op = .fcmp, .predicate = .le },
            .f32_add => .{ .op = .fadd },
            .f32_sub => .{ .op = .fsub },
            .f32_mul => .{ .op = .fmul },
            .f32_div => .{ .op = .fdiv },
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

    /// Whether `left` and `right` are text or bytes, and one of them is a borrowed view.
    fn spanComparable(self: *FnBuilder, left: ir.Ref, right: ir.Ref) bool {
        if (left == .none or right == .none) return false;
        const types = [_]ir.Type{ self.typeOfRef(left), self.typeOfRef(right) };
        for (types) |ty| if (ty != .str and ty != .bytes and !ty.isSpan()) return false;
        return types[0].isSpan() or types[1].isSpan();
    }

    /// Whether `value` is a byte buffer that is not the slice of one: a name, a field, a call's result.
    fn wholeBuffer(self: *FnBuilder, value: ir.Ref) bool {
        if (value == .none or self.typeOfRef(value) != .byte_buffer) return false;
        const inst = self.function.inst(self.function.resolve(value));
        if (inst.op != .call) return true;
        return !std.mem.eql(u8, self.mb.module.functions.items[inst.a.index()].name, "myl_core_buffer_slice");
    }

    /// Make the new buffer a `byte_buffer` slice call stands for the new `bytes` of the same range: the call is rewritten in
    /// place to `myl_core_bytes_slice`, whose copy is the one the slice already made. Whether `value` was such a call.
    fn sliceAsBytes(self: *FnBuilder, value: ir.Ref) Error!bool {
        const at = self.function.resolve(value);
        const inst = self.function.inst(at);
        if (inst.op != .call or inst.ty != .byte_buffer) return false;
        const target = self.mb.module.functions.items[inst.a.index()];
        if (!std.mem.eql(u8, target.name, "myl_core_buffer_slice")) return false;
        const callee = try self.mb.runtimeFunction("myl_core_bytes_slice", &.{ .byte_buffer, .i64, .i64 }, .bytes, .extern_c);
        self.function.insts.items[at.index()].a = @fromBackingInt(@intCast(callee));
        self.function.insts.items[at.index()].ty = .bytes;
        return true;
    }

    /// A bytes slice operand of `==` or `!=` (an expression, not a binding) borrows its octets: the comparison only
    /// reads them, so the slice's own copy is not made (C9 bytes).
    fn borrowComparedSlice(self: *FnBuilder, value: ir.Ref, node: typed.NodeId) Error!ir.Ref {
        // A read of a named binding keeps its value: the binding may outlive the comparison.
        if (value == .none or self.ownedFamily(node) != .bytes or self.nodeOf(node).data == .local) return value;
        _ = try self.sliceAsViewOf(value, true);
        return value;
    }

    /// `left == right` (or `!=`) over two spans: `myl_core_span_eq` compares the octets in place. An
    /// owned operand lends its octets to the comparison as a borrowed span of its whole length.
    fn spanEquality(self: *FnBuilder, wanted_equal: bool, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
        const a = try self.spanOperand(left, span);
        const b = try self.spanOperand(right, span);
        // The span form takes `str` parameters that admit views (`zero_rc.zig`, fusion's span forms).
        const same = try self.runtimeCall("myl_core_span_eq", &.{ .str, .str }, .bool, &.{ a, b }, span);
        if (wanted_equal) return same;
        return self.emit(.{ .op = .cmp, .ty = .bool, .a = same, .b = try self.constant(.bool, 0), .data = @backingInt(ir.Predicate.eq), .span = span });
    }

    fn spanOperand(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        if (self.typeOfRef(value).isSpan()) return value;
        const bytes = self.typeOfRef(value) == .bytes;
        const length_op: ir.Op = if (bytes) .list_len else .str_len;
        const length = try self.emit(.{ .op = length_op, .ty = .u64, .a = value, .span = span });
        return self.emit(.{ .op = .str_view_of, .ty = if (bytes) .bytes_view else .str_view, .a = value, .b = try self.constant(.u64, 0), .data = try self.extraSlice(&.{length}), .span = span });
    }

    /// `value` as an owned value of the family its checked owner belongs to.
    pub fn materializeOwned(self: *FnBuilder, owner: typed.LocalId, value: ir.Ref, span: u32) Error!ir.Ref {
        const family: OwnedFamily = if (self.textReceiver(owner)) .text else .bytes;
        return self.materializeAs(value, family, span);
    }

    /// The owned family a checked node's value belongs to: a text slice copies to
    /// `str`, a byte slice to `bytes`.
    pub fn ownedFamily(self: *FnBuilder, id: typed.NodeId) OwnedFamily {
        const ty = self.nodeOf(id).ty;
        if (!ty.isAggregate() or ty.recordIndex() >= self.mb.input.program.records.len) return .text;
        return if (self.mb.input.program.records[ty.recordIndex()].collection.kind == .bytes) .bytes else .text;
    }

    /// Whether the checked local `slot` names text rather than bytes.
    pub fn textReceiver(self: *FnBuilder, slot: typed.LocalId) bool {
        const ty = self.checked.scope.locals[@backingInt(slot)].ty;
        if (!ty.isAggregate() or ty.recordIndex() >= self.mb.input.program.records.len) return false;
        return self.mb.input.program.records[ty.recordIndex()].collection.kind == .string;
    }

    /// `value` as an owned string: a borrowed view is copied, anything else is
    /// returned unchanged. Every consumer that reads a `str` block needs this.
    pub fn materialized(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        return self.materializeAs(value, .text, span);
    }

    /// Which owned family a borrowed view copies to.
    pub const OwnedFamily = enum { text, bytes };

    /// Mark an instruction this builder just emitted as a written copy (`flags.written_copy`),
    /// and return it. A copy site without the mark is a hidden copy (`copy_sites.zig`).
    pub fn markWritten(self: *FnBuilder, ref: ir.Ref) ir.Ref {
        self.function.insts.items[ref.index()].data |= flags.written_copy;
        return ref;
    }

    /// A text slice the checker marks as a view (`text[a:b]`, `strings.char_slice`) borrows its base:
    /// its owned copy is made only by an owned use, and that copy is written (`copy`).
    fn borrowedTextSlice(self: *FnBuilder, ref: ir.Ref, node: typed.NodeId) Error!ir.Ref {
        if (ref == .none or !self.nodeOf(node).view) return ref;
        const at = self.function.resolve(ref);
        if (self.function.inst(at).op == .str_slice) {
            self.function.insts.items[at.index()].op = .str_slice_view;
            self.function.insts.items[at.index()].ty = .str_view;
            return ref;
        }
        // A bytes slice, or a text byte-offset slice, is the same borrowed view when a runtime call makes it.
        _ = try self.sliceAsView(at);
        return ref;
    }

    /// `value` as an owned value of `family`, where the copy is written: a named new value
    /// (`+`) or a `copy(value)` made it. A view is copied (see `materializeAs`), and the copy is marked.
    pub fn materializeWritten(self: *FnBuilder, value: ir.Ref, family: OwnedFamily, span: u32) Error!ir.Ref {
        if (value == .none or !self.typeOfRef(value).isSpan()) return value;
        return self.markWritten(try self.materializeAs(value, family, span));
    }

    /// `value` as an owned value of `family`: a borrowed view is copied (text to
    /// `str`, byte octets to `bytes`), anything else is returned unchanged.
    pub fn materializeAs(self: *FnBuilder, value: ir.Ref, family: OwnedFamily, span: u32) Error!ir.Ref {
        if (value == .none or !self.typeOfRef(value).isSpan()) return value;
        return switch (family) {
            // A bytes view is an owned bytes value by its copy, whatever family the consumer names.
            .text => if (self.typeOfRef(value) == .bytes_view) self.runtimeCall("myl_core_view_copy_bytes", &.{.bytes_view}, .bytes, &.{value}, span) else self.emit(.{ .op = .str_from_view, .ty = .str, .a = value, .span = span }),
            .bytes => self.runtimeCall("myl_core_view_copy_bytes", &.{.bytes_view}, .bytes, &.{value}, span),
        };
    }

    /// The integer literal `node` as a constant of integer type `ty`.
    fn literalAs(self: *FnBuilder, node: typed.NodeId, ty: ir.Type) Error!ir.Ref {
        if (ty.integer() == null) return self.expression(node);
        return self.constant(ty, self.nodeOf(node).data.integer);
    }

    /// `==` and `!=` of two records, unions (enums, `Option`, `Result`) or lists: structural,
    /// never a pointer comparison. Text compares through the runtime; recursive values use a worklist.
    fn aggregateCompare(self: *FnBuilder, op: typed.BinaryOp, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
        if (op == .add and (self.typeOfRef(left) == .str or self.typeOfRef(left) == .str_view)) {
            if (self.function.resolve(left) == self.function.resolve(right)) return self.runtimeCall("myl_core_str_concat", &.{ .str, .str }, .str, &.{ left, right }, span);
            // String addition produces an independent value. Both operands have
            // already been evaluated; only a proved dead owner may donate this copy.
            // Append materializes immutable literal storage without an extra copy.
            const literal = self.function.inst(self.function.resolve(left)).op == .str_const;
            const owned = if (literal) left else try self.copyOwned(left, span);
            return self.emit(.{ .op = .str_append, .ty = .str, .a = owned, .b = right, .span = span });
        }
        if (op == .add and (self.typeOfRef(left) == .bytes or self.typeOfRef(left) == .bytes_view)) return self.runtimeCall("myl_core_bytes_concat", &.{ self.typeOfRef(left), self.typeOfRef(right) }, .bytes, &.{ left, right }, span);
        const ty = self.typeOfRef(left);
        const ordering = switch (op) {
            .lt, .le, .gt, .ge => true,
            else => false,
        };
        if ((ty == .str or ty.isSpan() or ty == .bytes) and ordering) {
            const order = try self.runtimeCall("myl_core_octets_compare", &.{ ty, self.typeOfRef(right) }, .i64, &.{ left, right }, span);
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
        if (m.isBorrowed(ty)) return self.recursive(m.storageType(ty), depth);
        const kind = m.kind(ty) orelse return false;
        if (depth > 6) return true;
        switch (kind) {
            .borrowed => return self.recursive(m.storageType(ty), depth),
            .box => return true,
            .list => return self.recursive(m.compound(ty).list, depth + 1),
            .list_view => return self.recursive(m.compound(ty).list_view, depth + 1),
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
        // Wrapped views compare their octets in place, just like top-level
        // spans. Each union/record payload retains its own physical type.
        if (self.spanComparable(a, b)) return self.spanEquality(true, a, b, span);
        // A list view compares its elements in place (C9 lists); an owned list beside it is lent a view, so nothing is copied.
        if (self.isListView(self.typeOfRef(a)) or self.isListView(self.typeOfRef(b))) return self.listViewsEqual(a, b, span);
        const ty = m.storageType(self.typeOfRef(a));
        if (ty == .str or ty == .bytes or ty == .byte_buffer) {
            return self.effectCall(flags.str_eq_symbol, &.{ ty, self.typeOfRef(b) }, .bool, &.{ a, b }, span);
        }
        // A recursive value would need a function that calls itself, not an expansion in place.
        if (self.recursive(ty, 0)) return build_values.equal(@TypeOf(self), self, a, b, span);
        if (ty == .f64 or ty == .f32) return self.emit(.{ .op = .fcmp, .ty = .bool, .a = a, .b = b, .data = @backingInt(ir.Predicate.eq), .span = span });
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
            .list_view => return self.listViewsEqual(a, b, span),
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
            .borrowed => unreachable,
            .box => return self.mb.refuse(refuse_equality, span),
        }
    }

    /// Two unions are equal when their tags are and the payloads of that case are.
    fn unionEqual(self: *FnBuilder, a: ir.Ref, b: ir.Ref, span: u32) Error!ir.Ref {
        const cases = self.mb.module.compound(self.mb.module.storageType(self.typeOfRef(a))).@"union";
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
    /// Two lists, at least one of them a view, are equal when their elements are, read in place (C9 lists).
    fn listViewsEqual(self: *FnBuilder, a: ir.Ref, b: ir.Ref, span: u32) Error!ir.Ref {
        const view_a = try self.asListView(a, span);
        const view_b = try self.asListView(b, span);
        return self.listEqual(view_a, view_b, span);
    }

    /// `value` as a list view: a view is itself, and an owned list is lent its elements (`list_view_of`, no copy).
    fn asListView(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        const ty = self.typeOfRef(value);
        if (self.isListView(ty)) return value;
        if (self.mb.module.kind(ty) != .list) return self.mb.refuse(refuse_equality, span);
        const view = try self.mb.module.intern(self.allocator(), .{ .list_view = self.mb.module.compound(ty).list });
        return self.emit(.{ .op = .list_view_of, .ty = view, .a = value, .span = span });
    }

    fn listEqual(self: *FnBuilder, a: ir.Ref, b: ir.Ref, span: u32) Error!ir.Ref {
        const element = self.mb.module.listElement(self.typeOfRef(a)) orelse return self.mb.refuse(refuse_equality, span);
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
            .bit_not => blk: {
                // The complement is a xor with every bit of the operand's own
                // width set, so `bit_not` reads as one operation in Core.
                const ones = try self.constant(ty, allOnes(ty));
                break :blk self.emit(.{ .op = .bit_xor, .ty = ty, .a = operand, .b = ones, .span = span });
            },
            // A mask's complement keeps the mask type; a scalar `not` answers a bool.
            .not => self.emit(.{ .op = .not, .ty = ty, .a = operand, .span = span }),
            .f64_neg => self.emit(.{ .op = .fneg, .ty = .f64, .a = operand, .span = span }),
            .f64_from_i64, .f64_from_u64 => self.emit(.{ .op = .int_to_float, .ty = .f64, .a = operand, .span = span }),
            .f64_to_i64, .f64_to_i32, .f64_to_i16, .f64_to_i8, .f64_to_u8, .f64_to_u16, .f64_to_u32, .f64_to_u64 => self.emit(.{ .op = .float_to_int, .ty = ty, .a = operand, .check = .exact, .span = span }),
            .f64_sqrt, .f64_floor, .f64_ceil, .f64_trunc, .f64_abs, .f64_sin, .f64_cos => self.emit(.{ .op = .float_unary, .ty = .f64, .a = operand, .data = @backingInt(floatSelector(op)), .span = span }),
            .f32_neg => self.emit(.{ .op = .fneg, .ty = .f32, .a = operand, .span = span }),
            .f32_from_i64, .f32_from_u64 => self.emit(.{ .op = .int_to_float, .ty = .f32, .a = operand, .span = span }),
            .f32_to_i64, .f32_to_i32, .f32_to_i16, .f32_to_i8, .f32_to_u8, .f32_to_u16, .f32_to_u32, .f32_to_u64 => self.narrowToInteger(operand, ty, span),
            .f32_sqrt, .f32_floor, .f32_ceil, .f32_trunc, .f32_abs => self.emit(.{ .op = .float_unary, .ty = .f32, .a = operand, .data = @backingInt(floatSelector(op)), .span = span }),
            .f64_from_f32 => self.emit(.{ .op = .float_convert, .ty = .f64, .a = operand, .span = span }),
            .f32_from_f64 => self.emit(.{ .op = .float_convert, .ty = .f32, .a = operand, .span = span }),
            .f64_bits => self.emit(.{ .op = .bitcast, .ty = .u64, .a = operand, .span = span }),
            .f32_bits => self.emit(.{ .op = .bitcast, .ty = .u32, .a = operand, .span = span }),
            .f64_from_bits => self.emit(.{ .op = .bitcast, .ty = .f64, .a = operand, .span = span }),
            .f32_from_bits => self.emit(.{ .op = .bitcast, .ty = .f32, .a = operand, .span = span }),
        };
    }

    /// Every bit of an integer type set, the constant a complement xors with.
    /// A signed type names it `-1` so the constant carries its own sign, which is
    /// what every Core pass reads back out of `iconst.data`.
    fn allOnes(ty: ir.Type) i128 {
        const width = ty.integer() orelse return 0;
        if (width.signed) return -1;
        const shift: u7 = @intCast(width.bits);
        const mask: u128 = (@as(u128, 1) << shift) - 1;
        return @intCast(mask);
    }

    fn floatSelector(op: typed.UnaryOp) ir.FloatUnary {
        return switch (op) {
            .f64_sqrt, .f32_sqrt => .sqrt,
            .f64_floor, .f32_floor => .floor,
            .f64_ceil, .f32_ceil => .ceil,
            .f64_trunc, .f32_trunc => .trunc,
            .f64_abs, .f32_abs => .abs,
            .f64_sin => .sin,
            .f64_cos => .cos,
            else => unreachable,
        };
    }

    /// An `f32` checked conversion to an integer: widen exactly to binary64, then truncate under the same range check.
    fn narrowToInteger(self: *FnBuilder, operand: ir.Ref, ty: ir.Type, span: u32) Error!ir.Ref {
        const wide = try self.emit(.{ .op = .float_convert, .ty = .f64, .a = operand, .span = span });
        return self.emit(.{ .op = .float_to_int, .ty = ty, .a = wide, .check = .exact, .span = span });
    }

    /// `case_name(value)` and `Kind.from_name(text)`, which the checker writes as a `cast` between an enum and its name
    /// (`enum_cases.zig`): an enum or tagged union value to `str`, a `str` or `bytes` to an option of an enum. Null for any other cast,
    /// an option's or a result's `str` among them.
    fn enumCast(self: *FnBuilder, id: typed.NodeId, operand_node: typed.NodeId, span: u32) Error!?ir.Ref {
        const records = self.mb.input.program.records;
        const result_type = self.nodeOf(id).ty;
        const operand_type = self.nodeOf(operand_node).ty;
        if (@import("selka").reference_tables.prelude.optionShape(result_type, records)) |option| {
            const enum_type = option.element;
            if (!enum_type.isAggregate()) return null;
            const cases = (records[enum_type.recordIndex()].shape.variants orelse return null).cases;
            const text = try self.expression(operand_node);
            if (self.current == null) return .none;
            const parsed = try build_enum_names.fromName(@TypeOf(self), self, text, try self.typeOf(id), option, cases, span);
            return parsed;
        }
        if (!operand_type.isAggregate() or (try self.typeOf(id)) != .str) return null;
        // An option or a result is not an enum whose case has a name: `str(option)` is its text, as `print` shows it (F-38,
        // F-38b).
        if (@import("selka").reference_tables.prelude.optionShape(operand_type, records) != null) return null;
        const variants = records[operand_type.recordIndex()].shape.variants orelse return null;
        if (variants.fallible) return null;
        const cases = variants.cases;
        const value = try self.expression(operand_node);
        if (self.current == null) return .none;
        const named = try build_enum_names.name(@TypeOf(self), self, value, cases, span);
        return named;
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
        // A spelled `bytes(buffer)` names a new value that shares no storage with the buffer, so its snapshot is
        // a written copy whatever reads it (CX-1). An implicit snapshot the source did not spell has no such mark.
        // `bytes(buffer[a:b])` is the slice's own copy as octets: the slice is made as `bytes` here, not as a buffer snapshotted
        // again (FR27).
        if (target == .bytes and source == .byte_buffer and try self.sliceAsBytes(operand)) return self.markWritten(operand);
        if (target == .bytes and source == .byte_buffer) return self.markWritten(try self.runtimeCall("myl_core_buffer_snapshot", &.{.byte_buffer}, .bytes, &.{operand}, span));
        // A `bytes(...)` of a buffer-typed expression (a buffer slice, `buffer[a:b]`) names the independent value its
        // lowering copies (CX-1): that copy is the written one, whatever reads it.
        if (target == .bytes and source == .bytes and (try self.typeOf(operand_node)) == .byte_buffer and copy_sites.isSite(&self.mb.module, self.function.inst(operand))) return self.markWritten(operand);
        if (target == .bytes and (self.mb.module.kind(source) == .list or self.mb.module.kind(source) == .list_view)) return build_text.fromList(@TypeOf(self), self, source, operand, span);
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

    /// Elementwise arithmetic or comparison of two `Simd` values: `fadd` and friends on float lanes, the
    /// integer forms on integer lanes, or one compare whose result is the mask vector `ty`.
    fn vectorBinary(self: *FnBuilder, op: typed.BinaryOp, left_node: typed.NodeId, right_node: typed.NodeId, ty: ir.Type, span: u32) Error!ir.Ref {
        const left = try self.expression(left_node);
        const right = try self.expression(right_node);
        if (self.current == null) return .none;
        if (left == .none or right == .none) return self.mb.refuse("vector operand", span);
        const operand = self.function.inst(left).ty;
        if (self.mb.module.compound(operand).array.elem == .bool) return self.maskBinary(op, left, right, span);
        if (self.mb.module.compound(operand).array.elem.integer() != null) return self.integerVectorBinary(op, left, right, ty, span);
        if (vectorPredicate(op)) |p| return self.emit(.{ .op = .fcmp, .ty = ty, .a = left, .b = right, .data = @backingInt(p), .span = span });
        const arithmetic: ir.Op = switch (op) {
            .add => .fadd,
            .sub => .fsub,
            .mul => .fmul,
            .div => .fdiv,
            else => return self.mb.refuse("vector operator", span),
        };
        return self.emit(.{ .op = arithmetic, .ty = operand, .a = left, .b = right, .span = span });
    }

    /// A lane-by-lane `and`, `or` or `xor` of two masks: one bit operation on the `i1` vectors. Both operands are
    /// already evaluated when this runs, so no lane short-circuits (MASK-LOGIC-1).
    fn maskBinary(self: *FnBuilder, op: typed.BinaryOp, left: ir.Ref, right: ir.Ref, span: u32) Error!ir.Ref {
        const bit: ir.Op = switch (op) {
            .bit_and => .bit_and,
            .bit_or => .bit_or,
            .bit_xor => .bit_xor,
            else => return self.mb.refuse("mask operator", span),
        };
        return self.emit(.{ .op = bit, .ty = self.function.inst(left).ty, .a = left, .b = right, .span = span });
    }

    /// The comparison a `Simd` comparison operator lowers to, or null for an arithmetic operator.
    fn vectorPredicate(op: typed.BinaryOp) ?ir.Predicate {
        return switch (op) {
            .eq => .eq,
            .ne => .ne,
            .lt => .lt,
            .le => .le,
            .gt => .gt,
            .ge => .ge,
            else => null,
        };
    }

    /// Integer lanes: checked `+ - *` (each lane's overflow traps, as `arithmetic` does for a scalar), their
    /// wrapping forms, the bitwise operators, and comparisons into the mask `ty`.
    fn integerVectorBinary(self: *FnBuilder, op: typed.BinaryOp, left: ir.Ref, right: ir.Ref, ty: ir.Type, span: u32) Error!ir.Ref {
        if (vectorPredicate(op)) |p| return self.emit(.{ .op = .cmp, .ty = ty, .a = left, .b = right, .data = @backingInt(p), .span = span });
        const Shape = struct { op: ir.Op, check: ir.Check = .none };
        const shape: Shape = switch (op) {
            .add => .{ .op = .add, .check = .exact },
            .sub => .{ .op = .sub, .check = .exact },
            .mul => .{ .op = .mul, .check = .exact },
            .wrapping_add => .{ .op = .add },
            .wrapping_sub => .{ .op = .sub },
            .wrapping_mul => .{ .op = .mul },
            .bit_and => .{ .op = .bit_and },
            .bit_or => .{ .op = .bit_or },
            .bit_xor => .{ .op = .bit_xor },
            else => return self.mb.refuse("vector operator", span),
        };
        return self.emit(.{ .op = shape.op, .ty = self.function.inst(left).ty, .a = left, .b = right, .check = shape.check, .span = span });
    }

    /// Elementwise negation of a `Simd` value: `fneg` on float lanes, the checked `neg` on integer lanes.
    fn vectorNeg(self: *FnBuilder, operand_node: typed.NodeId, span: u32) Error!ir.Ref {
        const operand = try self.expression(operand_node);
        if (self.current == null) return .none;
        if (operand == .none) return self.mb.refuse("vector operand", span);
        const ty = self.function.inst(operand).ty;
        if (self.mb.module.compound(ty).array.elem.integer() != null) return self.emit(.{ .op = .neg, .ty = ty, .a = operand, .check = .exact, .span = span });
        return self.emit(.{ .op = .fneg, .ty = ty, .a = operand, .span = span });
    }

    /// Lane-wise conversion between the binary32 and binary64 lanes of a `Simd` value: `fpext` widens each lane, and
    /// `fptrunc` rounds each lane to binary32 exactly as the scalar conversion does (SIMD-LANE-CONVERT-1).
    fn vectorConvert(self: *FnBuilder, operand_node: typed.NodeId, ty: ir.Type, span: u32) Error!ir.Ref {
        const operand = try self.expression(operand_node);
        if (self.current == null) return .none;
        if (operand == .none) return self.mb.refuse("vector operand", span);
        return self.emit(.{ .op = .float_convert, .ty = ty, .a = operand, .span = span });
    }

    /// Elementwise square root of a float or f32 `Simd` value: one `llvm.sqrt` on the vector, correctly rounded per lane.
    fn vectorSqrt(self: *FnBuilder, operand_node: typed.NodeId, span: u32) Error!ir.Ref {
        const operand = try self.expression(operand_node);
        if (self.current == null) return .none;
        if (operand == .none) return self.mb.refuse("vector operand", span);
        return self.emit(.{ .op = .float_unary, .ty = self.function.inst(operand).ty, .a = operand, .data = @backingInt(ir.FloatUnary.sqrt), .span = span });
    }

    /// Lane `i` of the mask `mask` picks `a[i]` where it holds, else `b[i]`: one `select` on the vectors.
    fn vectorSelect(self: *FnBuilder, mask_node: typed.NodeId, a_node: typed.NodeId, b_node: typed.NodeId, ty: ir.Type, span: u32) Error!ir.Ref {
        const mask = try self.expression(mask_node);
        const a = try self.expression(a_node);
        const b = try self.expression(b_node);
        if (self.current == null) return .none;
        if (mask == .none or a == .none or b == .none) return self.mb.refuse("vector operand", span);
        return self.emit(.{ .op = .vector_select, .ty = ty, .a = mask, .b = a, .data = try self.extraSlice(&.{b}), .span = span });
    }

    /// `a * b + c` of one floating width with a single rounding (`llvm.fma`). The third operand travels in `extra`.
    /// One fixed-width read of bytes: the operands in order, then the checked load (build_byte_load.zig).
    fn byteLoadRead(self: *FnBuilder, load: @FieldType(@FieldType(typed.Node, "data"), "byte_load"), ty: ir.Type, span: u32) Error!ir.Ref {
        const source = try self.expression(load.bytes);
        const offset = try self.expression(load.offset);
        if (self.current == null) return .none;
        return @import("build_byte_load.zig").read(*FnBuilder, self, source, offset, ty, load.big_endian, span);
    }
    fn fusedMultiplyAdd(self: *FnBuilder, a_node: typed.NodeId, b_node: typed.NodeId, c_node: typed.NodeId, span: u32) Error!ir.Ref {
        const a = try self.expression(a_node);
        const b = try self.expression(b_node);
        const c = try self.expression(c_node);
        if (self.current == null) return .none;
        if (a == .none or b == .none or c == .none) return self.mb.refuse("fused multiply-add operand", span);
        const ty = self.function.inst(a).ty;
        const lanes = self.mb.module.kind(ty) == .array and self.mb.module.compound(ty).array.vector;
        if (ty != .f64 and ty != .f32 and !lanes) return self.mb.refuse("fused multiply-add type", span);
        return self.emit(.{ .op = .float_fma, .ty = ty, .a = a, .b = b, .data = try self.extraSlice(&.{c}), .span = span });
    }

    /// `wrap` builds a domain value: for `float` from IEEE bits (a constant) or a float operation.
    fn wrap(self: *FnBuilder, operand_node: typed.NodeId, target: ir.Type, span: u32) Error!ir.Ref {
        if (target == .f32) {
            const operand = self.nodeOf(operand_node);
            if (operand.data == .integer) {
                const bits: u64 = @truncate(@as(u128, @bitCast(operand.data.integer)));
                return self.detached(.{ .op = .fconst, .ty = .f32, .data = bits & 0xffffffff });
            }
            const value = try self.expression(operand_node);
            if (value == .none or self.function.inst(value).ty == .f32) return value;
            return self.mb.refuse("float bits", span);
        }
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

    /// The lowerer binds each argument to an SSA value in source order before
    /// assembling parameter order; no separate argument statement block exists.
    fn call(self: *FnBuilder, callee: typed.FunctionId, argument_nodes: []const typed.NodeId, order: []const usize, span: u32) Error!ir.Ref {
        const checked_function = self.mb.input.program.functions[@backingInt(callee)];
        if (checked_function.policy.host != null and !checked_function.policy.c_abi) return @import("build_host.zig").call(self, checked_function, argument_nodes, span);
        const index = try self.mb.functionIndex(callee);
        const declared = self.mb.input.program.functions[@backingInt(callee)].signature;
        const target: ir.Inst = .{ .op = .call, .a = @fromBackingInt(index), .ty = self.mb.module.functions.items[index].signature.ret };
        const contract: CallContract = .{ .order = order, .mutated = declared.declared_mutates, .declared = declared.return_type };
        return self.callTarget(target, argument_nodes, contract, span);
    }

    /// Invoke a top-level function value with the same copy-in/copy-out mut ABI.
    fn invoke(self: *FnBuilder, callee: typed.NodeId, arguments: []const typed.NodeId, order: []const usize, span: u32) Error!ir.Ref {
        const target = try self.expression(callee);
        if (self.current == null) return .none;
        const checked_ty = self.nodeOf(callee).ty;
        const callback = self.mb.input.program.records[checked_ty.recordIndex()].contract.callback orelse return self.mb.refuse("invoke of a non-function", span);
        const signature = self.mb.module.compound(self.typeOfRef(target)).@"fn";
        var inst: ir.Inst = .{ .op = .call_indirect, .a = target, .ty = signature.ret };
        build_fn.directTarget(&self.function, &inst);
        return self.callTarget(inst, arguments, .{ .order = order, .mutated = callback.mutates, .declared = callback.return_type }, span);
    }

    const CallContract = struct { order: []const usize = &.{}, mutated: []const u16, declared: typed.Type };

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

    /// The parameters a call to `target` passes: an internal callee's signature, or an indirect call's callable type.
    /// Empty for an extern callee, which reads its arguments as owned values.
    fn passedParameters(self: *FnBuilder, target: ir.Inst) []const ir.Type {
        if (target.op == .call and self.mb.module.functions.items[target.a.index()].signature.linkage == .internal)
            return self.mb.module.functions.items[target.a.index()].signature.params;
        if (target.op == .call_indirect) return self.mb.module.compound(self.typeOfRef(target.a)).@"fn".params;
        return &.{};
    }

    /// Lower arguments in source order and write mut results back to their captured places.
    /// The passed arguments in parameter order, then the owner of each borrowed `str` parameter (C9 S1): the owned
    /// block itself, a plain parameter's own owner, or the sentinel. A `unit` argument is evaluated, not passed.
    fn passArguments(self: *FnBuilder, values: []const ir.Ref, callee_params: []const ir.Type, arguments: *std.ArrayList(ir.Ref), span: u32) Error!void {
        var passed: usize = 0;
        var owners: std.ArrayList(ir.Ref) = .empty;
        defer owners.deinit(self.allocator());
        for (values) |given| {
            if (given == .none or self.typeOfRef(given) == .void) continue;
            const wanted: ir.Type = if (passed < callee_params.len) callee_params[passed] else .void;
            const borrowed = wanted.isSpan() or self.isListView(wanted);
            // A borrowed list (a collection of borrows read whole, RB2) lends the list it overlays, as an owned list does.
            const overlaid = self.module().isBorrowed(self.typeOfRef(given)) and self.mb.module.kind(self.module().storageType(self.typeOfRef(given))) == .list;
            const value = if (self.isListView(wanted) and overlaid) try self.borrowStorage(given, span) else given;
            if (wanted == .str_view) try owners.append(self.allocator(), if (self.typeOfRef(value) == .str) value else try self.passedOwner(value));
            // A borrowed list passes the owned list it lends, or the owner its view carries (C9 lists).
            if (self.isListView(wanted)) try owners.append(self.allocator(), if (self.mb.module.kind(self.typeOfRef(value)) == .list) value else try self.passedOwner(value));
            const text = borrowed and (self.typeOfRef(value) == .str or self.typeOfRef(value) == .bytes);
            // An owned list handed to a list-view parameter lends its elements (C9 lists); a slice already is a view.
            const list = borrowed and wanted != .void and self.typeOfRef(value) != wanted and self.mb.module.kind(self.typeOfRef(value)) == .list;
            // A list view handed to an owned parameter takes the owned list its owner names (C9 lists): a copy only for a slice.
            // CX2 (lanes/cx2.md B3): unreachable from checked source (a `mut` or view argument is refused), so unwritten.
            const owned_view = wanted != .void and !borrowed and self.mb.module.kind(self.typeOfRef(value)) == .list_view;
            const passed_value = if (text)
                try self.wholeView(value, span)
            else if (list)
                try self.listWholeView(value, wanted, span)
            else if (owned_view)
                try self.copyListViewUnspelled(value, span)
            else if (wanted != .void and self.module().containsBorrow(wanted))
                try self.readOnlyArgument(value, wanted, span)
            else
                try self.borrowStorage(value, span);
            try arguments.append(self.allocator(), passed_value);
            passed += 1;
        }
        try arguments.appendSlice(self.allocator(), owners.items);
    }

    /// An owned list of the elements of list view `value`: a copy (C9 lists).
    pub fn copyListView(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        return single_owner_copy.copyView(*FnBuilder, self, value, span);
    }

    /// A copy of list view `value` that no source spelled (CX2). Its two callers (`passArguments`' owned view and the
    /// owned-view call's slice path) are unreachable from checked source: R-B2, R-B3 and R-B4 refuse their shapes. The
    /// copy is left unwritten, so the verifier refuses it if one ever appears.
    pub fn copyListViewUnspelled(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        const copied = try self.copyListView(value, span);
        const inst = &self.function.insts.items[copied.index()];
        if (inst.op == .list_copy) inst.data &= ~flags.written_copy;
        return copied;
    }

    /// The owner of list view `view` when it is a plain parameter's (C9 lists): the caller's block, or the list sentinel
    /// for a slice. Null for a view this function made (a slice of its own): that view has no owner.
    pub fn listViewOwner(self: *FnBuilder, view: ir.Ref) ?ir.Ref {
        return self.view_owner.get(@intCast(self.function.resolve(view).index()));
    }

    /// Whether `ty` is the list view of an internal parameter (C9 lists).
    fn isListView(self: *FnBuilder, ty: ir.Type) bool {
        return self.mb.module.kind(ty) == .list_view;
    }

    /// The list view of an owned list `value` for a view parameter of type `wanted` (C9 lists): a free conversion, so the
    /// owner keeps the elements alive and nothing is copied.
    fn listWholeView(self: *FnBuilder, value: ir.Ref, wanted: ir.Type, span: u32) Error!ir.Ref {
        return self.emit(.{ .op = .list_view_of, .ty = wanted, .a = value, .span = span });
    }

    /// The list view a slice argument passes to a view parameter (C9 lists), so the call borrows the source's elements
    /// rather than building the copy the slice would otherwise make. Null when the argument is not a list slice or its
    /// parameter is not a list view. `position` is the argument's place in the call; unit arguments are not passed.
    fn sliceArgumentView(self: *FnBuilder, argument: typed.NodeId, argument_nodes: []const typed.NodeId, position: usize, callee_params: []const ir.Type, span: u32) Error!?ir.Ref {
        var index: usize = 0;
        for (argument_nodes[0..position]) |earlier| {
            if (try self.typeOf(earlier) != .void) index += 1;
        }
        if (index >= callee_params.len or !self.isListView(callee_params[index])) return null;
        return self.listSliceView(argument, callee_params[index], span);
    }

    fn callTarget(self: *FnBuilder, target: ir.Inst, argument_nodes: []const typed.NodeId, contract: CallContract, span: u32) Error!ir.Ref {
        const mutated = contract.mutated;
        const first_capture = self.captures.items.len;
        const first_slot = self.capture_slots.items.len;
        defer self.captures.items.len = first_capture;
        defer self.capture_slots.items.len = first_slot;
        for (mutated) |position| if (self.nodeOf(argument_nodes[position]).data == .local) {
            try self.capture_slots.append(self.allocator(), self.local(self.nodeOf(argument_nodes[position]).data.local));
        };
        var arguments: std.ArrayList(ir.Ref) = .empty;
        defer arguments.deinit(self.allocator());
        // A whole `mut` argument names the current caller variable. Interior arguments select
        // a value before later arguments; an ancestor write can orphan that selected value.
        // A later whole-root mutation supersedes publication even if its body preserves the leaf.
        const places = try self.allocator().alloc(Place, mutated.len);
        const prepared = try self.allocator().alloc(?PreparedPath, mutated.len);
        @memset(prepared, null);
        const values = try self.allocator().alloc(ir.Ref, argument_nodes.len);
        // The callee's passed parameters name which arguments are borrowed views (C9 lists).
        const callee_params = self.passedParameters(target);
        for (0..argument_nodes.len) |written_position| {
            const position = if (contract.order.len == 0) written_position else contract.order[written_position];
            const argument = argument_nodes[position];
            const value = &values[position];
            const slot = std.mem.indexOfScalar(u16, mutated, @intCast(position));
            if (slot != null and self.isView(self.nodeOf(argument).ty)) return self.mb.refuse("a live dictionary view as a checked mutable argument", span);
            if (slot == null) if (try self.sliceArgumentView(argument, argument_nodes, position, callee_params, span)) |view| {
                value.* = view;
                continue;
            };
            var place: ?Place = null;
            value.* = try self.expressionPlace(argument, if (slot != null) &place else null);
            if (slot) |at| {
                places[at] = place orelse return self.mb.refuse("mut argument that is not a place", span);
                try build_capture.watch(@TypeOf(self), self, &places[at], @intCast(self.nodeOf(argument).span.start));
                if (places[at].snapshot == .none) places[at].snapshot = try self.read(places[at].root, self.current.?);
            }
        }
        if (self.current == null) return .none;
        if (target.op == .call and self.mb.module.functions.items[target.a.index()].signature.linkage.externC() and values.len != 0 and self.typeOfRef(values[0]) == .cap) {
            _ = try self.effectCall("myl_core_host_check", &.{.cap}, .void, &.{values[0]}, span);
        }
        // A managed leaf transfers its owner through a saved path. Scalar writebacks
        // rebuild from the current root so an earlier sibling write is preserved.
        for (mutated, places, prepared, 0..) |position, *place, *path, at| {
            if (place.steps.len > 0 and self.version(place.root) != place.root_version) {
                values[position] = try build_capture.refresh(@TypeOf(self), self, place, values[position], span);
            } else if (place.steps.len > 0 and self.module().managed(try self.typeOf(argument_nodes[position]))) {
                path.* = try self.prepareMutPlace(place.*, places[0..at], prepared[0..at], span);
                values[position] = path.*.?.children[place.steps.len - 1];
            } else values[position] = try self.readPlace(place.*, span);
        }
        try self.guardMutPlaces(places, span);
        self.captures.items.len = first_capture;
        self.capture_slots.items.len = first_slot;
        // A `unit` argument is evaluated for its effects and not passed. A text argument of a
        // view parameter of an internal callee is passed as its borrowed view (`wholeView`).
        // A direct call of an internal function, or an indirect call of a callable, names its parameters (C9 S1).
        // An owned parameter that takes a list view with an owner (C9 lists) gets the owner on the owner's path and a copy
        // on a slice's path: the call is emitted once per path, so each path owns the list it passes.
        // CX2 (lanes/cx2.md B2): the owned-view call is unreachable from checked source (R-B2 refuses a view given to
        // `parallel.map`), so its slice copy is unwritten (`copyListViewUnspelled`) and the verifier would refuse it.
        if (mutated.len == 0) if (ownedViewArgument(self, values, callee_params)) |at| return self.ownedViewCall(target, values, at, span);
        try self.passArguments(values, callee_params, &arguments, span);
        if (self.mb.module.kind(target.ty) == .dict) for (argument_nodes) |argument| {
            if (self.isView(self.nodeOf(argument).ty)) return self.mb.refuse("a live dictionary view as a checked dictionary call argument", span);
        };
        var inst = target;
        inst.data = try self.extraSlice(arguments.items);
        inst.span = span;
        const result = try self.emit(inst);
        if (mutated.len == 0) return if (inst.ty == .void) .none else result;
        const declared = try self.mb.mapType(contract.declared, span);
        return self.writeBack(result, declared != .void, places, prepared, span);
    }

    /// The index in `values` of the one argument an owned parameter takes from a list view with an owner (C9 lists), or null.
    fn ownedViewArgument(self: *FnBuilder, values: []const ir.Ref, callee_params: []const ir.Type) ?usize {
        var passed: usize = 0;
        for (values, 0..) |value, at| {
            if (value == .none or self.typeOfRef(value) == .void) continue;
            const wanted: ir.Type = if (passed < callee_params.len) callee_params[passed] else .void;
            passed += 1;
            if (self.mb.module.kind(wanted) == .list and self.mb.module.kind(self.typeOfRef(value)) == .list_view and self.listViewOwner(value) != null) return at;
        }
        return null;
    }

    /// Emit call `target` once per path (C9 lists): the owner's path passes the owner of the list view `values[at]`, and a
    /// slice's path passes a copy of it. Each path passes the one list it owns, and the two results merge.
    fn ownedViewCall(self: *FnBuilder, target: ir.Inst, values: []const ir.Ref, at: usize, span: u32) Error!ir.Ref {
        const view = values[at];
        const owner = self.listViewOwner(view) orelse return self.mb.refuse("owned list view without an owner", span);
        const list_type = self.typeOfRef(owner);
        const sentinel = try self.detached(.{ .op = .text_sentinel, .ty = list_type });
        const same = try self.runtimeCall("myl_core_owned_same_block", &.{ list_type, list_type }, .i64, &.{ owner, sentinel }, span);
        const is_slice = try self.emit(.{ .op = .cmp, .ty = .bool, .a = same, .b = try self.constant(.i64, 1), .data = @backingInt(ir.Predicate.eq), .span = span });
        const variable: ?u32 = if (target.ty == .void) null else try self.synthetic(target.ty);
        const slice_block = try self.newBlock();
        const owner_block = try self.newBlock();
        const join = try self.newBlock();
        try self.branch(is_slice, slice_block, owner_block, span);
        try self.seal(slice_block);
        try self.seal(owner_block);
        for ([_]bool{ true, false }) |sliced| {
            self.enter(if (sliced) slice_block else owner_block);
            const passed = if (sliced) try self.copyListViewUnspelled(view, span) else owner;
            const path = try self.allocator().dupe(ir.Ref, values);
            path[at] = passed;
            var arguments: std.ArrayList(ir.Ref) = .empty;
            defer arguments.deinit(self.allocator());
            try self.passArguments(path, self.passedParameters(target), &arguments, span);
            var inst = target;
            inst.data = try self.extraSlice(arguments.items);
            inst.span = span;
            const value = try self.emit(inst);
            if (variable) |slot| try self.write(slot, self.current.?, value);
            try self.jump(join);
        }
        try self.seal(join);
        self.enter(join);
        return if (variable) |slot| self.read(slot, join) else .none;
    }

    /// Transfer a checked interior mut argument through one captured parent path.
    /// Source checking keeps the root exclusively loaned until the call returns.
    /// A payload taken below another payload (a binding of a nested `match mut`, FR77) is tested for its case where it is
    /// taken (`caseGuard`), as `storeIntoBelow` tests it for an assignment: the inner match tested another projection.
    fn prepareMutPlace(self: *FnBuilder, place: Place, previous: []const Place, paths: []const ?PreparedPath, span: u32) Error!PreparedPath {
        const parents = try self.allocator().alloc(ir.Ref, place.steps.len);
        const children = try self.allocator().alloc(ir.Ref, place.steps.len);
        var value = try self.read(place.root, self.current.?);
        var below_payload = false;
        for (place.steps, 0..) |step, index| {
            parents[index] = value;
            const shared = for (previous, paths) |prior, path| {
                const saved = path orelse continue;
                if (index >= prior.steps.len or saved.parents[index] != value) continue;
                if (self.sameMutStep(step, prior.steps[index])) break saved.children[index];
            } else ir.Ref.none;
            if (shared == .none and step == .payload and below_payload) try self.caseGuard(value, step.payload, span);
            if (step == .payload) below_payload = true;
            value = if (shared != .none) shared else if (step == .payload)
                try self.propagatedPayload(value, step.payload, span)
            else
                try self.stepGet(value, step, span);
            value = self.takeWritableChild(value);
            children[index] = value;
            const kind = self.module().kind(self.typeOfRef(parents[index]));
            if ((kind == .list or kind == .dict) and self.module().managed(self.typeOfRef(value))) self.function.insts.items[value.index()].data = flags.place_read;
        }
        return .{ .parents = parents, .children = children };
    }

    /// A writable path transfers the boxed field as well as its surrounding
    /// record. Ownership still rejects a parent whose field cannot be taken.
    fn takeWritableChild(self: *FnBuilder, value: ir.Ref) ir.Ref {
        if (self.function.inst(value).op == .box_get)
            self.function.insts.items[value.index()].op = .box_take;
        return value;
    }

    fn sameMutStep(self: *FnBuilder, left: Step, right: Step) bool {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
        return switch (left) {
            .field => |value| value == right.field,
            .payload => |value| value == right.payload,
            .element, .mapping => |value| sameMutIndex(&self.function, value, if (right == .element) right.element else right.mapping),
        };
    }

    fn sameMutIndex(function: *const ir.Function, left: ir.Ref, right: ir.Ref) bool {
        const a = function.resolve(left);
        const b = function.resolve(right);
        if (a == b) return true;
        const first = function.inst(a);
        const second = function.inst(b);
        return first.op == .iconst and second.op == .iconst and first.ty == second.ty and first.data == second.data;
    }

    const MutReturns = struct { places: []const Place, paths: []const ?PreparedPath, values: []const ir.Ref };

    /// Rebuild a shared ancestor only after all of its changed children are ready.
    /// Every transferred edge is reattached once, including shared nested prefixes.
    /// Every changed child is rebuilt before the first is set into `parent` (FR94): a deeper child stored after a sibling's
    /// set (`f(mut s.state, mut s.xs[i])`) would write into a part of `parent` that the set already consumed, and its
    /// element taken at a run-time index would then be a take from a borrowed list (J8).
    fn rebuildMutParent(self: *FnBuilder, returns: MutReturns, parent: ir.Ref, depth: usize, span: u32) Error!ir.Ref {
        const changes = try self.allocator().alloc(?ir.Ref, returns.places.len);
        for (returns.paths, changes, 0..) |candidate, *change, position| {
            change.* = null;
            const path = candidate orelse continue;
            if (depth >= path.parents.len or path.parents[depth] != parent) continue;
            const child = path.children[depth];
            const visited = for (returns.paths[0..position]) |prior| {
                const saved = prior orelse continue;
                if (depth < saved.parents.len and saved.parents[depth] == parent and saved.children[depth] == child) break true;
            } else false;
            if (visited) continue;
            change.* = if (depth + 1 == path.parents.len) returns.values[position] else try self.rebuildMutParent(returns, child, depth + 1, span);
        }
        var rebuilt = parent;
        for (returns.places, returns.paths, changes) |place, candidate, change| {
            const changed = change orelse continue;
            const child = candidate.?.children[depth];
            rebuilt = if (self.module().kind(self.typeOfRef(parent)) == .dict)
                try self.listSet(rebuilt, self.function.inst(child).b, changed, span)
            else
                try self.stepSet(rebuilt, place.steps[depth], changed, span);
        }
        return rebuilt;
    }

    fn storeMutPlace(self: *FnBuilder, returns: MutReturns, position: usize, span: u32) Error!void {
        const place = returns.places[position];
        const parent = returns.paths[position].?.parents[0];
        const rebuilt = try self.rebuildMutParent(returns, parent, 0, span);
        try self.write(place.root, self.current.?, rebuilt);
        try self.assigned(place.root);
        try build_capture.invalidate(@TypeOf(self), self, place, span);
    }

    /// A call to a function with `mut` parameters returned `result`: its own value (unless
    /// `unit`) and each `mut` parameter's final value. Store those into the caller's places.
    fn writeBack(self: *FnBuilder, result: ir.Ref, has_value: bool, places: []const Place, prepared: []const ?PreparedPath, span: u32) Error!ir.Ref {
        const record_type = self.typeOfRef(result);
        const parts: []const ir.Type = if (self.mb.module.kind(record_type) == .record) self.mb.module.compound(record_type).record else &.{};
        // One part alone is not wrapped in a record.
        const wrapped = has_value or places.len > 1;
        const first: usize = if (has_value) 1 else 0;
        // The call's value may be a view borrowed from a written-back part (`-> T from p`). The part is then read first, so that
        // the view, read after it, has a parent defined before it; any other value is read where it always was.
        const parts_first = wrapped and has_value and self.mb.module.containsBorrow(parts[0]);
        var value: ir.Ref = result;
        if (wrapped and !parts_first) value = if (has_value) try self.emit(.{ .op = .record_get, .ty = parts[0], .a = result, .data = 0, .span = span }) else .none;
        const returned = try self.allocator().alloc(ir.Ref, places.len);
        for (returned, 0..) |*part, k| part.* = if (wrapped) try self.emit(.{ .op = .record_get, .ty = parts[first + k], .a = result, .data = first + k, .span = span }) else result;
        if (parts_first) value = try self.emit(.{ .op = .record_get, .ty = parts[0], .a = result, .data = 0, .span = span });
        const returns: MutReturns = .{ .places = places, .paths = prepared, .values = returned };
        for (places, prepared, returned, 0..) |place, path, part, k| {
            if (path) |captured| {
                const stored = for (prepared[0..k]) |prior| {
                    if (prior) |saved| if (saved.parents[0] == captured.parents[0]) break true;
                } else false;
                if (!stored) try self.storeMutPlace(returns, k, span);
            } else if (!rebuiltLater(places, prepared, k)) try self.storeMutPart(place, part, span);
        }
        // A part stored from the root's current value waits for a later sibling's path, which rebuilds the root it read before
        // the call (`split(mut o.port, mut o.path)` with `o.path` managed): stored first, the part would be lost to that path.
        for (places, prepared, returned, 0..) |place, path, part, k| {
            if (path == null and rebuiltLater(places, prepared, k)) try self.storeMutPart(place, part, span);
        }
        return if (has_value) value else .none;
    }

    /// Whether a `mut` argument after the one at `k` transfers a path from the same root (`prepareMutPlace`).
    fn rebuiltLater(places: []const Place, prepared: []const ?PreparedPath, k: usize) bool {
        for (places[k + 1 ..], prepared[k + 1 ..]) |later, path| {
            if (path != null and later.root == places[k].root) return true;
        }
        return false;
    }

    /// Store a `mut` argument's final value `part` at `place` from its root's current value, under its publish condition.
    /// A place under a `match mut` binding is written as an assignment through that binding is (C1, FR76): the payload is
    /// taken out of its union and the union rebuilt (`exclusive_write`), not read through a borrow that a managed payload's
    /// rebuild would then take.
    fn storeMutPart(self: *FnBuilder, place: Place, part: ir.Ref, span: u32) Error!void {
        const outer = self.exclusive_write;
        defer self.exclusive_write = outer;
        if (self.underExclusiveBinding(place)) self.exclusive_write = true;
        if (place.publish == .none) {
            _ = try self.storePlace(place, part, span);
            return;
        }
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

    /// Whether `place` lies at or under the place of a `match mut` payload binding: its root and its first steps are that
    /// binding's place, which ends in the union payload the binding names (C1).
    fn underExclusiveBinding(self: *FnBuilder, place: Place) bool {
        var keys = self.exclusive_locals.keyIterator();
        while (keys.next()) |entry| {
            const bound = self.places.get(entry.*) orelse continue;
            if (bound.root != place.root or bound.steps.len == 0 or bound.steps.len > place.steps.len) continue;
            const same = for (bound.steps, place.steps[0..bound.steps.len]) |x, y| {
                if (!std.meta.eql(x, y)) break false;
            } else true;
            if (same) return true;
        }
        return false;
    }

    fn collectionOperation(self: *FnBuilder, operation: BufferOperation, ty: ir.Type, span: u32, out: ?*?Place) Error!?ir.Ref {
        const receiver_type = self.module().storageType(self.ssa.types.items[self.local(operation.owner)]);
        if (operation.kind == .copy) {
            const copied = try self.copyList(operation.owner, ty, span);
            return copied;
        }
        const collection = self.mb.module.kind(receiver_type) orelse return null;
        switch (collection) {
            .list => {
                switch (operation.kind) {
                    .extend, .reverse, .index_of, .insert, .exchange, .pop_at, .remove, .slice_step, .clear => {
                        const result = try build_list_methods.operation(@TypeOf(self), self, operation, ty, span);
                        return result;
                    },
                    else => {},
                }
            },
            // A list view is read in place (C9 lists): its position search and its stepped copy (`lists.stride`) read the
            // elements and the length only.
            .list_view => {
                if (operation.kind == .index_of or operation.kind == .slice_step) {
                    const found = try build_list_methods.operation(@TypeOf(self), self, operation, ty, span);
                    return found;
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
        if (base_type.isSpan()) {
            const text = self.mb.input.program.records[self.nodeOf(index.base).ty.recordIndex()].collection.kind == .string;
            const view = try self.expression(index.base);
            // A bytes view has no cache owner: its octets are the whole read (C9 bytes).
            const owner = if (text) try self.viewOwner(view) else view;
            return build_view.indexed(@TypeOf(self), self, owner, view, try self.expression(index.index), .{ .text = text, .result = result }, span);
        }
        if (base_type == .str or base_type == .bytes or base_type == .byte_buffer) return build_text.indexed(@TypeOf(self), self, index.base, index.index, span, result);
        const value = try self.arrayGet(id, span, out);
        return if (node.ty == .unit) .none else value;
    }

    /// A text `strip`, `lstrip` or `rstrip` with no character set: its span form (`myl_core_text_trim_view`)
    /// keeps the borrowed octets, so a view receiver is not copied first.
    fn noArgumentTextTrim(operation: BufferOperation, text: bool) bool {
        return text and operation.arguments.len == 0 and @import("selka").reference_tables.buffer_operations.trim(operation.kind) != null;
    }

    fn bufferOperation(self: *FnBuilder, operation: BufferOperation, ty: ir.Type, span: u32, out: ?*?Place) Error!ir.Ref {
        const receiver_type = self.ssa.types.items[self.local(operation.owner)];
        if (operation.kind == .position_fail) return self.positionFailure(operation, span);
        if (operation.kind == .copy) {
            const source = try self.receiverOf(operation.owner);
            if (self.ssa.dictionary_defaults.contains(self.function.resolve(source))) return self.copyOwned(source, span);
        }
        if (try build_view.dispatch(@TypeOf(self), self, operation, ty, receiver_type, span)) |value| return value;
        // An operation with no span form reads an owned value, so the borrowed
        // octets are copied first and the method runs on that copy.
        const text_owner = self.textReceiver(operation.owner);
        const borrowed_text = receiver_type.isSpan() and operation.kind != .iteration_check;
        const not_spanned = !build_view.spanReceiver(operation.kind, text_owner) and !noArgumentTextTrim(operation, text_owner);
        if (borrowed_text and not_spanned) {
            const family: OwnedFamily = if (self.textReceiver(operation.owner)) .text else .bytes;
            const view = try self.receiverOf(operation.owner);
            const copy = try self.materializeAs(view, family, span);
            try self.write(self.local(operation.owner), self.current.?, copy);
            const result = try self.bufferOperationRaw(operation, ty, span, out);
            // A view-keeping owner (`<slice>`) is never reassigned: the copy serves this operation only, and the
            // owner holds its view again, so a loop that reads the owner keeps one type for it (C9 str).
            if (self.current != null and std.mem.eql(u8, self.checked.scope.locals[@backingInt(operation.owner)].name, "<slice>")) try self.write(self.local(operation.owner), self.current.?, view);
            return result;
        }
        const result = try self.bufferOperationRaw(operation, ty, span, out);
        // A length is `u64` in the IR; a `len()` of a view or buffer typed `int` converts it,
        // as the plain `length` node does.
        if (operation.kind != .length or result == .none or ty == .void or self.typeOfRef(result) == ty) return result;
        return self.emit(.{ .op = .convert, .ty = ty, .a = result, .check = .exact, .span = span });
    }

    fn copyList(self: *FnBuilder, owner: typed.LocalId, target: ir.Type, span: u32) Error!ir.Ref {
        return single_owner_copy.copyAs(@TypeOf(self), self, try self.receiverOf(owner), target, span);
    }

    /// End a negative-position arm with its located, operand-bearing bounds trap.
    fn positionFailure(self: *FnBuilder, operation: BufferOperation, span: u32) Error!ir.Ref {
        const index = try self.expression(operation.arguments[0]);
        const length = try self.expression(operation.arguments[1]);
        if (self.current == null) return .none;
        const source_type = self.checked.scope.locals[@backingInt(operation.owner)].ty;
        const text = self.mb.input.program.records[source_type.recordIndex()].collection.kind == .string;
        _ = try self.emit(.{ .op = .@"unreachable", .ty = .void, .a = index, .b = length, .data = flags.text_trap | @as(u64, if (text) 11 else 2), .span = span });
        self.current = null;
        return .none;
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
            // A view receiver is the borrowed form of text or bytes, and
            // `build_text` takes the family from the checked local.
            .str, .bytes, .str_view, .bytes_view => return build_text.operation(@TypeOf(self), self, operation, ty, span),
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
                const data: u64 = if (self.exclusive_scrutinee) flags.place_read else 0;
                const element = try self.emit(.{ .op = .list_get, .ty = if (ty == .void) .bool else ty, .a = receiver, .b = index, .data = data, .check = .exact, .span = span });
                return if (ty == .void) .none else element;
            },
            .append => {
                var value = (try self.lentOptionElement(owner, argument_nodes[0], span)) orelse try self.expression(argument_nodes[0]);
                if (self.current == null) return .none;
                if (value == .none or self.typeOfRef(value) == .void) value = try self.constant(.bool, 0);
                // The receiver is read after the argument, which may have written its place.
                const list = try self.writableReceiverOf(owner, span);
                value = try self.lentElementOf(list, try self.framedElement(list, argument_nodes[0], value, span), span);
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
                const list = try self.writableReceiverReusing(owner, self.slotReads(argument_nodes[1], .binding), span);
                value = try self.lentElementOf(list, value, span);
                _ = try self.transferSlotRead(argument_nodes[1], list, index);
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
            // Explicit copies duplicate every owned child.
            .copy => return self.copyList(owner, ty, span),
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
        // The sort works on owned copies: a list view of the source is copied first (C9 lists), as an owned source is.
        source = try single_owner_copy.copy(@TypeOf(self), self, source, span);
        keys = try single_owner_copy.copy(@TypeOf(self), self, keys, span);
        const source_type = self.typeOfRef(source);
        const keys_type = self.typeOfRef(keys);
        if (self.mb.module.kind(source_type) != .list or self.mb.module.kind(keys_type) != .list) return self.mb.refuse("keyed sort of a non-list", span);
        const key_type = self.mb.module.compound(keys_type).list;
        const shape = build_fn.keyShape(self.mb.module, key_type);
        const strides = @as(u64, self.mb.module.size(self.mb.module.compound(source_type).list)) | (@as(u64, self.mb.module.size(self.mb.module.compound(keys_type).list)) << 32);
        const sorted = if (shape) |layout| packed_key: {
            const symbol = "myl_core_owned_sort_keyed";
            const sorts: []const ir.Ref = &.{ source, keys, try self.constant(.u64, layout.shape), try self.constant(.u64, layout.offsets), reverse, try self.constant(.u64, strides) };
            // `sorted(xs, key=...)` names a new value: the runtime's copy of the source and keys is written (CX2).
            break :packed_key self.markWritten(try self.runtimeCall(symbol, &.{ source_type, keys_type, .u64, .u64, .bool, .u64 }, source_type, sorts, span));
        } else extended: {
            const descriptor = try build_fn.recordKeyDescriptor(self.allocator(), self.mb.module, key_type) orelse return self.mb.refuse("sort key type", span);
            const index = self.mb.module.strings.items.len;
            try self.mb.module.strings.append(self.allocator(), descriptor);
            const metadata = try self.detached(.{ .op = .str_const, .ty = .bytes, .data = index });
            const symbol = "myl_core_owned_sort_keyed_record";
            break :extended self.markWritten(try self.runtimeCall(symbol, &.{ source_type, keys_type, .bytes, .bool, .u64 }, source_type, &.{ source, keys, metadata, reverse, try self.constant(.u64, strides) }, span));
        };
        try self.writeOwner(owner, sorted, span);
        return .none;
    }

    /// `len(text)` of a string that is not a local (a field, an element, a call result).
    fn stringLength(self: *FnBuilder, operand: typed.NodeId, span: u32) Error!ir.Ref {
        const value = try self.expression(operand);
        if (self.current == null) return .none;
        if (self.mb.module.kind(self.mb.module.storageType(self.typeOfRef(value))) == .dict) {
            const length = try self.emit(.{ .op = .dict_len, .ty = .u64, .a = value, .span = span });
            return self.emit(.{ .op = .convert, .ty = .i64, .a = length, .check = .exact, .span = span });
        }
        if (self.mb.module.kind(self.mb.module.storageType(self.typeOfRef(value))) == .array) return self.constant(.i64, self.mb.module.compound(self.mb.module.storageType(self.typeOfRef(value))).array.n);
        const value_type = self.typeOfRef(value);
        if (value_type.isSpan()) {
            const text = self.mb.input.program.records[self.nodeOf(operand).ty.recordIndex()].collection.kind == .string;
            return build_view.length(@TypeOf(self), self, if (text) try self.viewOwner(value) else value, value, text, span);
        }
        if (value_type != .str and value_type != .bytes and value_type != .byte_buffer) return self.mb.refuse("length of a non-string", span);
        const chars = if (value_type != .str) try self.emit(.{ .op = .list_len, .ty = .u64, .a = value, .span = span }) else try self.stringChars(value, span);
        return self.emit(.{ .op = .convert, .ty = .i64, .a = chars, .check = .exact, .span = span });
    }

    /// A call of the runtime function `symbol` (declared in the module on first use) with `arguments`.
    /// Invoke an extern helper for a feature builder.
    pub fn runtimeCall(self: *FnBuilder, symbol: []const u8, params: []const ir.Type, ret: ir.Type, arguments: []const ir.Ref, span: u32) Error!ir.Ref {
        const callee = try self.mb.runtimeFunction(symbol, params, ret, .extern_c);
        const physical = try self.physicalArguments(arguments, span);
        return self.emit(.{ .op = .call, .ty = ret, .a = @fromBackingInt(@intCast(callee)), .data = try self.extraSlice(physical), .span = span });
    }

    /// Ordered runtime call that passes every capability token to its adapter.
    pub fn effectCall(self: *FnBuilder, name: []const u8, params: []const ir.Type, ret: ir.Type, arguments: []const ir.Ref, span: u32) Error!ir.Ref {
        const callee = try self.mb.runtimeFunction(name, params, ret, .runtime_c);
        const physical = try self.physicalArguments(arguments, span);
        return self.emit(.{ .op = .call, .ty = ret, .a = @fromBackingInt(callee), .data = try self.extraSlice(physical), .span = span });
    }

    fn physicalArguments(self: *FnBuilder, arguments: []const ir.Ref, span: u32) Error![]const ir.Ref {
        var physical: ?[]ir.Ref = null;
        for (arguments, 0..) |argument, index| {
            if (argument == .none or !self.module().isBorrowed(self.typeOfRef(argument))) continue;
            if (physical == null) physical = try self.allocator().dupe(ir.Ref, arguments);
            physical.?[index] = try self.borrowStorage(argument, span);
        }
        return physical orelse arguments;
    }

    /// The text of `value`, as `str(value)` and an f-string part spell it: a string as it is, an
    /// integer in decimal, a boolean as `True` or `False`.
    pub fn textOf(self: *FnBuilder, value: ir.Ref, source_ty: typed.Type, span: u32) Error!ir.Ref {
        if (value == .none or source_ty == .unit) return self.runtimeCall("myl_core_none_text", &.{}, .str, &.{}, span);
        const ty = self.typeOfRef(value);
        if (self.renderDomain(source_ty)) return build_values.render(*FnBuilder, self, value, source_ty, span);
        if (ty == .str or ty == .str_view) return value;
        if (ty == .f64) return self.runtimeCall("myl_core_str_from_f64", &.{.f64}, .str, &.{value}, span);
        if (ty == .f32) return self.runtimeCall("myl_core_str_from_f32", &.{.f32}, .str, &.{value}, span);
        if (ty == .bool) return self.runtimeCall(flags.str_from_bool_symbol, &.{.bool}, .str, &.{value}, span);
        const info = ty.integer() orelse return build_values.render(*FnBuilder, self, value, source_ty, span);
        const wide: ir.Type = if (info.signed) .i64 else .u64;
        const operand = if (ty == wide) value else try self.emit(.{ .op = .convert, .ty = wide, .a = value, .span = span });
        return self.runtimeCall(if (info.signed) flags.str_from_i64_symbol else flags.str_from_u64_symbol, &.{wide}, .str, &.{operand}, span);
    }

    /// Whether an argument of this print is an `f"..."` literal, whose pieces are
    /// written in order rather than built into one text first.
    fn printForms(print: typed.Print, b: *FnBuilder) bool {
        for (print.arguments) |argument| if (b.nodeOf(argument).data == .format) return true;
        return false;
    }

    /// Whether a checked type is a domain value other than `float`, which renders
    /// through its wire type rather than as its own storage.
    pub fn renderDomain(self: *FnBuilder, ty: typed.Type) bool {
        if (!ty.isAggregate()) return false;
        const record = self.mb.input.program.records[ty.recordIndex()];
        return record.shape.domain != null and !std.mem.eql(u8, record.name, "float") and !std.mem.eql(u8, record.name, "f32");
    }

    /// The length of string `value` in Unicode scalars, which is what `len` counts (not bytes):
    /// the runtime counts the bytes that do not continue a scalar.
    /// Builder operation available to the feature dispatch modules.
    pub fn stringChars(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        return self.runtimeCall(flags.str_chars_symbol, &.{.str}, .u64, &.{value}, span);
    }

    /// The scalar count of borrowed text `value`, read in place by the view helper (`myl_core_view_chars`).
    pub fn viewScalarCount(self: *FnBuilder, value: ir.Ref, span: u32) Error!ir.Ref {
        const count = try build_view.chars(*FnBuilder, self, try self.viewOwner(value), value, span);
        return self.emit(.{ .op = .convert, .ty = .u64, .a = count, .check = .exact, .span = span });
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
        // A dropped debug line (`build --release`) evaluates its arguments and formats and writes nothing.
        if (print.debug and self.mb.input.drop_debug) return build_cap.evaluateDroppedDebug(*FnBuilder, self, print);
        // Dynamic separators are ordered writes, and so is an f-string argument,
        // which writes its own pieces. `main`'s reported error is a `str` the
        // entry wrapper prints itself, so there a format string is built once.
        const ordered = print.debug or print.separator != null or print.terminator != null or
            (printForms(print, self) and print.sink != .error_report);
        if (ordered) return build_cap.printOptions(*FnBuilder, self, print, span);
        var operands: std.ArrayList(ir.Ref) = .empty;
        defer operands.deinit(self.allocator());
        const stream = if (print.stream) |stream_node| try self.expression(stream_node) else try self.constant(.cap, switch (print.sink) {
            .stdout => 1,
            .stderr => 2,
            .error_report => flags.error_stream,
        });
        try operands.append(self.allocator(), stream);
        for (print.arguments) |argument| {
            var value = try self.expression(argument);
            if (self.current == null) return .none;
            const source_ty = self.nodeOf(argument).ty;
            // A bytes view renders in place through the span form of its text (C9 bytes), so it is not copied here;
            // a text view prints in place, as before.
            if (self.ownedFamily(argument) == .bytes and (value == .none or self.typeOfRef(value) != .bytes_view)) value = try self.materializeAs(value, .bytes, span);
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

/// Why a value of type `actual` cannot be lent where a borrowed block (`borrowed[T]`) is needed, or null when it can. A text
/// or bytes view cannot: `view_materialize` would copy it into owned storage before the borrow, a copy no `copy(...)` wrote,
/// and the compiler inserts no copy by itself, in any mode. The check refuses every source that would reach this (a slice, a
/// `from` result or a bare parameter is lent only as a frame block or refused), so a shape that does is a gap in lowering:
/// it is refused under Z3 instead of being copied silently, as a view field of a borrowed record already is.
pub fn hiddenViewBorrow(actual: ir.Type) ?[]const u8 {
    if (actual.isSpan()) return "a text or bytes view lent where a borrowed block is needed, which lowering would copy with no copy(...) written";
    return null;
}

/// Attach each frame header that a scalar lookup needs to the entry block (C9 S1). A frame reads only its
/// parameter's owner and span, which the entry block defines, so the first instructions of the entry dominate
/// every use.
fn attachFrames(b: *FnBuilder, entry: ir.BlockId) Error!void {
    var frames = b.frames.valueIterator();
    while (frames.next()) |frame| try b.function.blocks.items[entry.index()].insts.insert(b.allocator(), 0, frame.*);
}

/// Whether a checked `builtin func` kept the empty body its declaration has (a generic one; W10).
fn suppliedWithoutBody(program: typed.Program, checked: typed.Function) bool {
    const body = program.statements[@backingInt(checked.scope.body)];
    return body.data == .block and body.data.block.len == 0;
}

fn buildFunction(mb: *ModuleBuilder, checked: typed.Function, declared: ir.Function) Error!ir.Function {
    mb.creator = checked.name;
    mb.made = @splat(0);
    const parallel = @import("build_parallel.zig");
    if (parallel.matches(mb.input.source, checked)) return parallel.build(mb, declared, checked);
    // The `testing` module's counter readers (`B5`) are runtime calls behind a
    // private declaration, so the module and the checker need no new syntax.
    const testing = @import("build_testing.zig");
    if (testing.matched(mb.input.source, checked)) |name| return testing.build(mb, declared, name);
    // The `registers` operations (MCU-B1): each is one call of the simulated bank's runtime function.
    const registers = @import("build_registers.zig");
    if (registers.matched(mb.input.source, checked)) |operation| return registers.build(mb, declared, operation);
    // `json.encode[T]` and `json.decode[T]`: the derived plain JSON form of `T` (CODEC-1, step 1).
    const json = @import("build_json.zig");
    if (json.matched(mb.input.source, checked)) |which| return json.build(mb, declared, checked, which);
    // A generic `builtin func` has no body: every call of it is checked as its operation, so a build that reaches the
    // function itself is a checker defect, refused here rather than run (W10).
    if (checked.policy.builtin and suppliedWithoutBody(mb.input.program, checked)) return mb.refuse("a builtin function with no supplied body", declared.span);
    var b: FnBuilder = .{ .mb = mb, .function = declared, .checked = checked };
    b.declared_ret = try mb.logicalReturnType(checked, declared.span);
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
    defer b.projected.deinit(mb.allocator);
    defer if (b.projectable) |computed| mb.allocator.free(computed);
    defer b.view_owner.deinit(mb.allocator);
    defer b.frames.deinit(mb.allocator);
    defer b.view_params.deinit(mb.allocator);
    var view_params: std.ArrayList(ir.Ref) = .empty;
    defer view_params.deinit(mb.allocator);
    var view_owner_types: std.ArrayList(ir.Type) = .empty;
    defer view_owner_types.deinit(mb.allocator);
    for (checked.scope.locals) |local| {
        const ty = if (local.ownership.view) try mb.viewOf(local) else mb.mapType(local.ty, @intCast(local.declaration.start)) catch .void;
        try b.ssa.types.append(mb.allocator, ty);
    }
    try @import("build_const_borrow.zig").prepare(@TypeOf(&b), &b);
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
        // The declared signature is the one callers pass to: a view parameter is a `str_view`.
        const passed_ty = declared.signature.params[@intCast(passed)];
        b.ssa.types.items[i] = passed_ty;
        const param = try b.detached(.{ .op = .param, .ty = passed_ty, .data = passed });
        passed += 1;
        try b.write(@intCast(i), entry, param);
        if (try build_fn.ownerOf(&mb.module, mb.allocator, passed_ty)) |owner_type| {
            try view_params.append(mb.allocator, param);
            try view_owner_types.append(mb.allocator, owner_type);
            try b.view_params.put(mb.allocator, @intCast(i), param);
        }
    }
    // The owners follow the passed parameters, one per borrowed `str` or list parameter, in parameter order.
    for (view_params.items, view_owner_types.items, 0..) |view, owner_type, k| {
        const owner = try b.detached(.{ .op = .param, .ty = owner_type, .data = passed + k });
        try b.view_owner.put(mb.allocator, @intCast(b.function.resolve(view).index()), owner);
    }
    try b.statement(checked.scope.body);
    // A `@noalloc` body recovers its inline slices here, where the allocation
    // promise is known and the span helpers it needs are still declarable; the
    // general recovery (`lowering_finish`) covers every other body's reads.
    if (checked.policy.noalloc != null) _ = try @import("fuse_slice_key.zig").rewriteFunction(mb.allocator, &mb.module, &b.function);
    if (b.current != null) {
        if (b.declared_ret != .void) return mb.refuse("missing return", declared.span);
        try b.returnValue(.none, declared.span);
    }
    try b.validateViews();
    try attachFrames(&b, entry);
    // A `@noalloc` body that reads a slice in place must not allocate for it in a
    // debug build either, where the release pipeline's recovery does not run.
    // Only reads are rewritten, so `view_materialize` (which runs later) has
    // nothing left to copy for them.
    return b.function;
}
