//! Independent LLVM modules with deterministic source ownership and dependencies.
const std = @import("std");
const builtin = @import("builtin");
const cache_miss = @import("selka").cache_miss;
const fast_blake3 = @import("fast_blake3.zig");
const ir = @import("ir.zig");
const llvm = @import("emit_llvm.zig");
const values = @import("emit_values.zig");
const constants = @import("emit_constants.zig");
const number_runtime = @import("number_runtime.zig");
const effects = @import("effects.zig");
const cache = @import("emission_cache.zig");
const key_policy = @import("emission_key.zig");
const deferred_facts = @import("deferred_facts.zig");
const facts = @import("facts.zig");
const helper_format = "myl.helper.{s}";
const module_format = "module-{s}";
const content_format = "{s}-{s}";
pub const Error = llvm.Error || error{CacheMiss};

/// Native input suffix shared by the driver and ordered test-program identity.
pub const native_extension = @import("native_artifact.zig").extension;

/// What a unit's emission was made of, for the engine's shadow (`emit_shadow.zig`): the digest of the compact key the unit was looked
/// up under (what the program supplied to it), the digest of its text, and the functions it holds.
pub const Identity = struct { input: key_policy.Digest, text: key_policy.Digest, functions: []const u32 };

/// One object input and its link dependencies, independent of other units' contents.
pub const Unit = struct {
    name: []const u8,
    source_path: []const u8,
    kind: Kind,
    llvm: []const u8,
    dependencies: cache.Dependencies,
    artifact: ?cache.NativeArtifact = null,
    /// Set when the unit was keyed by a compact receipt, which is how a build that reuses emission looks it up.
    identity: ?Identity = null,
};

/// Source modules, instantiated functions, compiler adapters, the C entry, and the
/// one whole-program unit of a release build (S4-1a).
pub const Kind = enum { module, generic, helper, entry, program };

const Group = struct {
    path: []const u8,
    kind: Kind,
    functions: std.ArrayList(u32) = .empty,
};

/// A release build's single unit: the whole program, so LLVM optimizes across every
/// module boundary. Like any unit it is keyed by its exact text.
/// The returned slice, names, paths and LLVM text belong to `a`.
/// Scratch uses `a`; arena callers retain its backing pages.
pub fn whole(a: std.mem.Allocator, module: *const ir.Module, options: llvm.Options) llvm.Error![]Unit {
    return wholeWithScratch(a, a, module, options);
}

/// Emit one whole-program unit, releasing temporary storage to `backing`.
pub fn wholeWithScratch(a: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, options: llvm.Options) llvm.Error![]Unit {
    const text = try llvm.emitModuleWithScratch(a, backing, module, options);
    errdefer a.free(text);
    const units = try a.alloc(Unit, 1);
    errdefer a.free(units);
    const name = try a.dupe(u8, "program");
    errdefer a.free(name);
    const path = try a.dupe(u8, options.source_path);
    units[0] = unit(name, path, .program, text);
    return units;
}

const Partition = struct {
    module: *const ir.Module,
    options: llvm.Options,
    groups: std.ArrayList(Group),
    exported: []const bool,
    symbols: []?[]const u8,
    program: Program = .{},

    fn selection(self: *const Partition, group: Group, entry: bool) llvm.Selection {
        return .{ .functions = group.functions.items, .exported = self.exported, .symbols = self.symbols, .source_path = group.path, .entry = entry, .constants = &self.program.catalog, .survey = &self.program.survey };
    }

    /// Render the program's descriptor catalog and survey the module if this partition has not yet. It runs on the coordinator
    /// before any job that reads them exists, so the jobs, which read them from several threads, see them complete.
    fn ensureCatalog(self: *Partition, a: std.mem.Allocator, counts: ?*cache.Counts) Error!void {
        if (!self.program.pending) return;
        self.program.catalog = try constants.Catalog.init(a, self.module);
        self.program.survey = llvm.survey(a, self.module, self.options) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.UnsupportedInstruction,
        };
        self.program.pending = false;
        if (counts) |tally| tally.work.catalogs_built += 1;
    }
};

/// What a partition's units read of the whole program: the descriptor catalog and the survey of the module
/// (`emit_survey.zig`). `pending` is true while both are still empty: a demand partition makes them (`ensureCatalog`)
/// only when a unit misses its receipt, because a unit served by its receipt reads neither.
const Program = struct {
    catalog: constants.Catalog = .{},
    survey: @import("emit_survey.zig").Survey = .{ .equality = false, .test_counts = false, .functions = 0, .compounds = 0, .preludes = &.{} },
    pending: bool = true,
};

fn partition(a: std.mem.Allocator, module: *const ir.Module, given: llvm.Options) llvm.Error!Partition {
    var plan = partitionDemand(a, module, given, null) catch |err| switch (err) {
        error.CacheMiss => return error.UnsupportedInstruction,
        else => |other| return other,
    };
    plan.ensureCatalog(a, null) catch |err| switch (err) {
        error.CacheMiss => return error.UnsupportedInstruction,
        else => |other| return other,
    };
    return plan;
}

/// The groups, linkage and symbol slots of `module`, with the descriptor catalog still to render (`Partition.ensureCatalog`).
fn partitionDemand(a: std.mem.Allocator, module: *const ir.Module, given: llvm.Options, context: ?cache.Context) Error!Partition {
    var options = given;
    if (options.analysis.effects == null) {
        const summaries = try a.create(effects.Summaries);
        summaries.* = try effects.analyze(a, module);
        options.analysis.effects = summaries;
    }
    var groups: std.ArrayList(Group) = .empty;
    const owner = try a.alloc(?u32, module.functions.items.len);
    const exported = try a.alloc(bool, owner.len);
    const symbols = try a.alloc(?[]const u8, owner.len);
    @memset(owner, null);
    @memset(exported, false);
    @memset(symbols, null);
    try assignGroups(a, module, options, &groups, owner);
    // The linkage of a function follows from its own module's source (spec section 17.5): it is `internal` when the check found it
    // private, `hidden` otherwise. No caller in another unit is consulted, so a module's text does not change when another module does.
    for (module.functions.items, exported) |*function, *flag| flag.* = !module.isPrivate(function);
    exported[module.entry] = true;
    if (builtin.mode == .debug) try checkLinkage(module, owner, exported, context);
    return .{ .module = module, .options = options, .groups = groups, .exported = exported, .symbols = symbols };
}

/// A Debug compiler checks the rule of spec section 17.5 against the calls: every function a unit calls in another unit must be
/// `hidden` there, or the link would fail. A violation is an internal error, so the corpus and the language suites test the rule.
fn checkLinkage(module: *const ir.Module, owner: []const ?u32, exported: []const bool, context: ?cache.Context) Error!void {
    for (module.functions.items, 0..) |_, index| {
        if (context) |ctx| {
            if (ctx.receipts) |receipt| if (index < receipt.finals.len) if (receipt.finals[index]) |final| {
                for (final.outgoing) |target| try checkCall(owner, exported, index, target);
                continue;
            };
            try ctx.ensure(@intCast(index));
        }
        for (module.functions.items[index].insts.items) |inst| {
            const target: usize = switch (inst.op) {
                .call => inst.a.index(),
                .func_ref => @intCast(inst.data),
                else => continue,
            };
            try checkCall(owner, exported, index, target);
        }
    }
}

fn checkCall(owner: []const ?u32, exported: []const bool, caller: usize, target: usize) Error!void {
    if (target >= owner.len) return error.UnsupportedInstruction;
    if (owner[target] == null or owner[target] == owner[caller] or exported[target]) return;
    cache_miss.note(@src());
    return error.UnsupportedInstruction;
}

/// Put every function that has a body into the group of its unit: a source module's functions together, every
/// generic instance and every compiler adapter on its own. `owner` receives each function's group.
fn assignGroups(a: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, groups: *std.ArrayList(Group), owner: []?u32) llvm.Error!void {
    // The module group of each path, found by hash and not by a scan of the groups so far (a program has one group per module).
    var module_groups: std.StringHashMapUnmanaged(u32) = .empty;
    for (module.functions.items, 0..) |*function, index| {
        const adapter = values.generated(function);
        const synthetic = function.signature.linkage == .internal and
            (std.mem.startsWith(u8, function.name, "lambda@") or std.mem.startsWith(u8, function.name, "__test_") or std.mem.eql(u8, function.name, "<entry>"));
        const helper = adapter or synthetic;
        if (function.signature.linkage != .internal and !helper) continue;
        const location = options.locator.locate(options.locator.context, function.span);
        const path = if (location.path.len != 0) location.path else options.source_path;
        const kind: Kind = if (helper) .helper else if (std.mem.indexOfScalar(u8, function.name, '[') != null) .generic else .module;
        const group = if (kind == .module) module_groups.get(path) else null;
        const target = group orelse blk: {
            try groups.append(a, .{ .path = try a.dupe(u8, if (adapter) "myl.helper" else path), .kind = kind });
            const created: u32 = @intCast(groups.items.len - 1);
            if (kind == .module) try module_groups.put(a, groups.items[created].path, created);
            break :blk created;
        };
        owner[index] = target;
        try groups.items[target].functions.append(a, @intCast(index));
    }
    for (groups.items) |group| std.mem.sort(u32, group.functions.items, module, functionLess);
}

/// Canonical order of the functions of one unit: by name, then by table position for the names two functions share. A unit's text
/// then does not depend on the order in which lowering discovered its functions.
fn functionLess(module: *const ir.Module, left: u32, right: u32) bool {
    const order = std.mem.order(u8, module.functions.items[left].name, module.functions.items[right].name);
    return if (order == .eq) left < right else order == .lt;
}

/// What orders the units of a build: the kind (source modules, generic instances, compiler adapters), then the module's path or
/// the canonical symbol of the unit's first function (an adapter's symbol is the digest of its text), then its table position.
const GroupOrder = struct {
    module: *const ir.Module,
    symbols: []const ?[]const u8,

    fn key(self: GroupOrder, group: Group) []const u8 {
        if (group.kind == .module) return group.path;
        const first = group.functions.items[0];
        return self.symbols[first] orelse self.module.functions.items[first].name;
    }

    fn less(self: GroupOrder, left: Group, right: Group) bool {
        if (left.kind != right.kind) return @backingInt(left.kind) < @backingInt(right.kind);
        const order = std.mem.order(u8, self.key(left), self.key(right));
        return if (order == .eq) left.functions.items[0] < right.functions.items[0] else order == .lt;
    }
};

/// Put the groups in canonical order (`GroupOrder`), once the compiler adapters have their canonical symbols. Units, and so the
/// objects of a link, then follow from the set of units and not from the order lowering found them in.
fn sortGroups(groups: []Group, module: *const ir.Module, symbols: []const ?[]const u8) void {
    std.mem.sort(Group, groups, GroupOrder{ .module = module, .symbols = symbols }, GroupOrder.less);
}

/// The functions one emitted unit holds, and the name its certificate file carries.
pub const Members = struct {
    name: []const u8,
    functions: []const u32,
};

/// The units a build of `module` emits, with their functions: one `program` unit for a whole-program (release)
/// build, otherwise the groups `emit` makes. A module unit keeps the name its LLVM unit has; a generic instance
/// or a compiler adapter is named by its kind and the digest of its function's name, so the certificate files
/// do not depend on the emitted text. The entry unit holds no function and is left out.
pub fn members(a: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, whole_program: bool) llvm.Error![]Members {
    var found: std.ArrayList(Members) = .empty;
    if (whole_program) {
        var all: std.ArrayList(u32) = .empty;
        for (module.functions.items, 0..) |function, index| if (function.signature.linkage == .internal) try all.append(a, @intCast(index));
        try found.append(a, .{ .name = "program", .functions = all.items });
        return found.items;
    }
    var groups: std.ArrayList(Group) = .empty;
    const owner = try a.alloc(?u32, module.functions.items.len);
    @memset(owner, null);
    try assignGroups(a, module, options, &groups, owner);
    for (groups.items) |group| {
        const name = if (group.kind == .module)
            try std.fmt.allocPrint(a, module_format, .{try digest(a, group.path)})
        else
            try std.fmt.allocPrint(a, content_format, .{ @tagName(group.kind), try digest(a, module.functions.items[group.functions.items[0]].name) });
        try found.append(a, .{ .name = name, .functions = group.functions.items });
    }
    return found.items;
}

/// Partition the frozen IR, then emit each unit with only its reached constants.
/// Debug builds use this: an edit recompiles only the units whose text changed.
/// The returned slice, names, paths and LLVM text belong to `allocator`.
/// Scratch uses `allocator`; arena callers retain its backing pages.
pub fn emit(allocator: std.mem.Allocator, module: *const ir.Module, options: llvm.Options) llvm.Error![]Unit {
    return emitWithScratch(allocator, allocator, module, options);
}

/// Emit independent units, releasing partition and unit scratch to `backing`.
pub fn emitWithScratch(allocator: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, given: llvm.Options) llvm.Error![]Unit {
    // The partition, descriptor catalog and canonical symbol table are needed
    // only while emitting. Their explicit backing can return pages independently
    // of the caller's build arena, which retains just each finished unit.
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    const a = scratch.allocator();
    const prepared = try partition(a, module, given);
    const options = prepared.options;
    const groups = prepared.groups;
    const exported = prepared.exported;
    const symbols = prepared.symbols;
    const catalog = prepared.program.catalog;
    const survey = &prepared.program.survey;
    // Hash an adapter's complete closed text with a fixed self-name. Neither an IR
    // type ID nor the eventual hash can enter this seed, including recursively.
    for (groups.items) |group| {
        if (group.kind != .helper) continue;
        const index = group.functions.items[0];
        if (!values.generated(&module.functions.items[index])) continue;
        symbols[index] = "myl.helper.self";
        const seed = try llvm.emitUnitWithScratch(backing, backing, module, options, .{
            .functions = group.functions.items,
            .exported = exported,
            .symbols = symbols,
            .source_path = group.path,
            .constants = &catalog,
            .survey = survey,
        });
        defer backing.free(seed);
        symbols[index] = try std.fmt.allocPrint(a, helper_format, .{try digest(a, seed)});
    }
    sortGroups(groups.items, module, symbols);
    var units: std.ArrayList(Unit) = .empty;
    errdefer for (units.items) |emitted| {
        allocator.free(emitted.name);
        allocator.free(emitted.source_path);
        allocator.free(emitted.llvm);
    };
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    defer names.deinit(a);
    for (groups.items) |group| {
        const text = try llvm.emitUnitWithScratch(allocator, backing, module, options, .{
            .functions = group.functions.items,
            .exported = exported,
            .symbols = symbols,
            .source_path = group.path,
            .constants = &catalog,
            .survey = survey,
        });
        errdefer allocator.free(text);
        const name = if (group.kind == .module) try std.fmt.allocPrint(a, module_format, .{try digest(a, group.path)}) else try std.fmt.allocPrint(a, content_format, .{ @tagName(group.kind), try digest(a, text) });
        try append(allocator, a, &units, &names, unit(name, group.path, group.kind, text));
    }
    {
        const entry = try llvm.emitUnitWithScratch(allocator, backing, module, options, .{
            .functions = &.{},
            .exported = exported,
            .symbols = symbols,
            .entry = true,
            .source_path = options.source_path,
            .constants = &catalog,
            .survey = survey,
        });
        errdefer allocator.free(entry);
        try append(allocator, a, &units, &names, unit("entry", options.source_path, .entry, entry));
    }
    return allocator.dupe(Unit, units.items);
}

fn append(allocator: std.mem.Allocator, scratch: std.mem.Allocator, units: *std.ArrayList(Unit), names: *std.StringHashMapUnmanaged(usize), next: Unit) llvm.Error!void {
    const entry = try names.getOrPut(scratch, next.name);
    if (entry.found_existing) {
        const previous = units.items[entry.value_ptr.*];
        // Equal closed adapters may arise from separate nominal source types.
        // Their callers already share the canonical symbol; emit its body once.
        if (previous.kind != next.kind or !std.meta.eql(previous.dependencies, next.dependencies)) return error.UnsupportedInstruction;
        if (previous.llvm.len != 0 and next.llvm.len != 0) {
            if (!std.mem.eql(u8, previous.llvm, next.llvm)) return error.UnsupportedInstruction;
        } else if (previous.artifact == null or next.artifact == null) return error.UnsupportedInstruction;
        allocator.free(next.llvm);
        return;
    }
    var owned = next;
    owned.name = try allocator.dupe(u8, next.name);
    errdefer allocator.free(owned.name);
    owned.source_path = try allocator.dupe(u8, next.source_path);
    errdefer allocator.free(owned.source_path);
    entry.value_ptr.* = units.items.len;
    try units.append(scratch, owned);
}

fn digest(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var hash: [32]u8 = undefined;
    fast_blake3.hash(text, &hash);
    return std.fmt.allocPrint(a, "{x}", .{hash});
}

/// The link dependencies a unit's text names, found in one pass: the math intrinsics (`-lm`), a counter reader and
/// a test-allocation reader. Each is a substring of the text, the same answer as one `indexOf` per name over the text.
const Mentions = struct { math: bool = false, counting: bool = false, test_counts: bool = false };

/// `Mentions` of `text`: one scan of the bytes, testing the names that start with each byte.
fn mentions(text: []const u8) Mentions {
    var found: Mentions = .{};
    for (text, 0..) |byte, at| {
        if (byte == 'l') {
            if (std.mem.startsWith(u8, text[at..], "llvm.sin.f64") or std.mem.startsWith(u8, text[at..], "llvm.cos.f64") or std.mem.startsWith(u8, text[at..], "llvm.fma.f")) found.math = true;
        } else if (byte == '@') {
            if (std.mem.startsWith(u8, text[at..], "@myl_count_current")) found.counting = true;
            if (std.mem.startsWith(u8, text[at..], "@myl_core_test_allocations")) found.test_counts = true;
        }
        if (found.math and found.counting and found.test_counts) break;
    }
    return found;
}

/// A unit of `text` with its link dependencies (number-text helpers, `-lm`) read from it.
pub fn unit(name: []const u8, path: []const u8, kind: Kind, text: []const u8) Unit {
    const mentioned = mentions(text);
    const math = mentioned.math;
    const counting = mentioned.counting;
    // Only `@stdlib/testing.selka` declares a counter reader, so a call of one marks
    // the unit (and therefore the program's runtime variant) without scanning IR.
    const test_counts = mentioned.test_counts;
    return .{
        .name = name,
        .source_path = path,
        .kind = kind,
        .llvm = text,
        .dependencies = .{
            .number = number_runtime.needed(text),
            .math = math,
            .counting = counting,
            .test_counts = test_counts,
        },
    };
}

fn emissionArtifact(text: []const u8) cache.Artifact {
    const dependencies = unit("", "", .program, text);
    return .{ .text = text, .number = dependencies.dependencies.number, .math = dependencies.dependencies.math, .counting = dependencies.dependencies.counting, .test_counts = dependencies.dependencies.test_counts };
}

/// Reuse completed LLVM by canonical inputs; changed units render in bounded batches.
/// `backing` must support concurrent allocation; `allocator` is coordinator-only.
pub fn emitCached(allocator: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, context: cache.Context) Error![]Unit {
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    const a = scratch.allocator();
    var plan = try partitionDemand(a, module, options, context);
    var keys = (if (context.receipts != null) key_policy.Prepared.initLazy(a, module, plan.options, &plan.program.catalog) else key_policy.Prepared.init(a, module, plan.options, &plan.program.catalog)) catch |err| switch (err) {
        error.UnknownMetadata => {
            for (module.functions.items, 0..) |_, index| try context.ensure(@intCast(index));
            return emitUncached(allocator, backing, module, options, context.deferred);
        },
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedEntry => return error.UnsupportedEntry,
        error.UnsupportedInstruction => return error.UnsupportedInstruction,
    };
    keys.deferred = context.deferred;
    var compact = try key_policy.Compact.init(a, module, plan.options, &keys.canon, context);
    try helperSymbols(a, backing, &plan, &keys, &compact, context);
    sortGroups(plan.groups.items, module, plan.symbols);
    const jobs = try a.alloc(EmissionJob, plan.groups.items.len + 1);
    var initialized: usize = 0;
    defer for (jobs[0..initialized]) |*job| job.deinit();
    const inputs: JobInputs = .{ .arena = a, .backing = backing, .plan = &plan, .keys = &keys, .compact = &compact, .context = context };
    for (plan.groups.items, jobs[0..plan.groups.items.len]) |group, *job| {
        job.* = try emissionJob(inputs, group, false);
        initialized += 1;
    }
    jobs[jobs.len - 1] = try emissionJob(inputs, .{ .kind = .entry, .path = options.source_path }, true);
    initialized += 1;
    var result: std.ArrayList(Unit) = .empty;
    errdefer for (result.items) |emitted| {
        allocator.free(emitted.name);
        allocator.free(emitted.source_path);
        allocator.free(emitted.llvm);
    };
    // A job the receipt already answers has nothing left to run (`EmissionJob.settle`). It does not wait for a worker thread: a thread
    // costs about 50 us of CPU and a 256 KiB clear of its thread-local area, and a build of 466 units spawned 450 of them to do nothing.
    // The jobs that load or render an artifact run in batches of the lanes the context allows, as before.
    const collected = try a.alloc(?Unit, jobs.len);
    @memset(collected, null);
    errdefer for (collected) |maybe| if (maybe) |emitted| allocator.free(emitted.llvm);
    var waiting: std.ArrayList(usize) = .empty;
    for (jobs, 0..) |*job, at| if (!job.settle()) try waiting.append(a, at);
    var next: usize = 0;
    while (next < waiting.items.len) {
        const widths = try a.alloc(usize, @min(@max(1, context.lanes), waiting.items.len - next));
        for (widths, waiting.items[next..][0..widths.len]) |*weight, at| weight.* = jobs[at].weight;
        const count = cache.batch(widths, context.lanes, context.memory_budget_bytes);
        const batch = waiting.items[next..][0..count];
        try runBatch(a, jobs, batch);
        if (context.counts) |counts| counts.workers = @max(counts.workers, @as(u32, @intCast(count)));
        // Copy each finished job's text out of its scratch now, so a batch's memory is gone before the next batch starts.
        for (batch) |at| collected[at] = try collect(allocator, a, inputs, &jobs[at]);
        next += count;
    }
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    for (jobs, collected) |*job, *slot| {
        const emitted = slot.* orelse try collect(allocator, a, inputs, job);
        slot.* = emitted;
        try append(allocator, a, &result, &names, emitted);
        slot.* = null;
    }
    return allocator.dupe(Unit, result.items);
}

/// The unit `job` made or served, its text copied into `allocator`, and the counts of the emission updated. A job whose receipt named an
/// artifact the store could not read is rendered afresh here.
fn collect(allocator: std.mem.Allocator, a: std.mem.Allocator, inputs: JobInputs, job: *EmissionJob) Error!Unit {
    const context = inputs.context;
    if (job.failure) |failure| {
        // A receipt whose artifact is catalogued but cannot be read is a miss too: emit the unit afresh on this thread.
        if (failure != error.CacheMiss or job.receipt_hit == null) return failure;
        try renderAfresh(inputs, job);
    }
    const artifact = job.artifact.?;
    const text = try allocator.dupe(u8, artifact.text);
    errdefer allocator.free(text);
    const name = if (context.native_handles and job.receipt_hit != null) try emissionNameDigest(a, job, job.receipt_hit.?.text_digest) else try emissionName(a, job, text);
    if (context.counts) |counts| {
        counts.work.llvm_loaded_bytes += text.len;
        if (context.native_handles and text.len == 0) counts.work.native_handles += 1;
    }
    const emitted: Unit = .{
        .name = name,
        .source_path = job.group.path,
        .kind = job.group.kind,
        .llvm = text,
        .dependencies = .{ .number = artifact.number, .math = artifact.math, .counting = artifact.counting, .test_counts = artifact.test_counts },
        .artifact = if (context.native_handles) .{ .store = context.store, .key = job.key } else null,
        .identity = try identityOf(allocator, job),
    };
    if (context.counts) |counts| {
        counts.units += 1;
        if (job.hit) counts.reused += 1 else counts.rendered += 1;
    }
    job.deinit();
    return emitted;
}

/// The identity of the unit `job` made or served: its compact key, the digest of its text and the functions it holds. Null for a unit
/// that was not looked up by a receipt.
fn identityOf(allocator: std.mem.Allocator, job: *const EmissionJob) std.mem.Allocator.Error!?Identity {
    const input = job.receipt orelse return null;
    var text: key_policy.Digest = undefined;
    if (job.receipt_hit) |record| text = record.text_digest else fast_blake3.hash(job.artifact.?.text, &text);
    return .{ .input = input, .text = text, .functions = try allocator.dupe(u32, job.group.functions.items) };
}

/// Replace `job`, whose receipt named an artifact the store could not read, by a job that ignores receipts, and run it.
fn renderAfresh(inputs: JobInputs, job: *EmissionJob) Error!void {
    const group = job.group;
    const entry = job.entry;
    job.deinit();
    var again = inputs;
    again.trust_receipts = false;
    job.* = try emissionJob(again, group, entry);
    job.run();
    if (job.failure) |failure| return failure;
}

fn emissionName(a: std.mem.Allocator, job: *const EmissionJob, text: []const u8) llvm.Error![]const u8 {
    if (job.entry) return "entry";
    if (job.group.kind == .module) return std.fmt.allocPrint(a, module_format, .{try digest(a, job.group.path)});
    return std.fmt.allocPrint(a, content_format, .{ @tagName(job.group.kind), try digest(a, text) });
}

fn emissionNameDigest(a: std.mem.Allocator, job: *const EmissionJob, text_digest: key_policy.Digest) llvm.Error![]const u8 {
    if (job.entry) return "entry";
    if (job.group.kind == .module) return std.fmt.allocPrint(a, module_format, .{try digest(a, job.group.path)});
    return std.fmt.allocPrint(a, content_format, .{ @tagName(job.group.kind), std.fmt.bytesToHex(text_digest, .lower) });
}

fn receiptArtifact(key: key_policy.Digest, artifact: cache.Artifact) cache.Receipt {
    var text_digest: key_policy.Digest = undefined;
    fast_blake3.hash(artifact.text, &text_digest);
    return .{ .artifact = key, .text_digest = text_digest, .dependencies = .{ .number = artifact.number, .math = artifact.math, .counting = artifact.counting, .test_counts = artifact.test_counts } };
}

fn emitUncached(allocator: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, deferred: ?*const deferred_facts.Table) Error![]Unit {
    if (deferred == null) return emitWithScratch(allocator, backing, module, options);
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    const a = scratch.allocator();
    const functions = try a.alloc(u32, module.functions.items.len);
    for (functions, 0..) |*index, i| index.* = @intCast(i);
    const loaded = try factsOptions(a, options, deferred.?, functions);
    return emitWithScratch(allocator, backing, module, loaded);
}

fn factsOptions(a: std.mem.Allocator, given: llvm.Options, table: *const deferred_facts.Table, functions: []const u32) Error!llvm.Options {
    var needed = false;
    for (functions) |index| needed = needed or table.identity(index) != null;
    if (!needed) return given;
    const known = try a.alloc(?facts.Facts, @max(table.entries.len, given.analysis.facts.len));
    @memset(known, null);
    for (functions) |index| {
        if (index >= known.len) continue;
        known[index] = if (index < given.analysis.facts.len) given.analysis.facts[index] else null;
        if (table.identity(index) != null) known[index] = try table.load(a, index);
    }
    var options = given;
    options.analysis.facts = known;
    return options;
}

fn helperSymbols(a: std.mem.Allocator, backing: std.mem.Allocator, plan: *Partition, keys: *key_policy.Prepared, compact: *?key_policy.Compact, context: cache.Context) Error!void {
    for (plan.groups.items) |group| {
        const index = group.functions.items[0];
        if (group.kind != .helper or !values.generated(&plan.module.functions.items[index])) continue;
        plan.symbols[index] = "myl.helper.self";
        var local = std.heap.ArenaAllocator.init(backing);
        defer local.deinit();
        const temp = local.allocator();
        const receipt = if (compact.*) |*policy| try policy.key(a, plan.module, plan.options, plan.selection(group, false)) else null;
        if (receipt) |receipt_key| {
            if (context.counts) |counts| counts.work.receipts_checked += 1;
            if (try context.store.loadValue(temp, receipt_key, cache.Receipt)) |record| {
                if (context.native_handles) {
                    // The symbol needs only the digest, but a root that keeps this receipt keeps the artifact it names (`emissionJob`).
                    _ = try context.store.contains(record.artifact);
                    plan.symbols[index] = try std.fmt.allocPrint(a, helper_format, .{std.fmt.bytesToHex(record.text_digest, .lower)});
                    if (context.counts) |counts| counts.seeds_reused += 1;
                    continue;
                }
                if (try context.store.loadValue(temp, record.artifact, cache.Artifact)) |artifact| {
                    plan.symbols[index] = try std.fmt.allocPrint(a, helper_format, .{try digest(a, artifact.text)});
                    if (context.counts) |counts| counts.seeds_reused += 1;
                    continue;
                }
            }
        }
        try context.ensure(index);
        try plan.ensureCatalog(a, context.counts);
        if (context.counts) |counts| counts.work.keys_built += 1;
        const input = keys.key(temp, plan.selection(group, false)) catch |err| return emissionKeyError(err);
        const key = context.store.key("llvm-helper-seed-v1", &.{&input});
        const served = context.store.loadValue(temp, key, cache.Artifact) catch return error.OutOfMemory;
        const seed = if (served) |artifact| artifact.text else blk: {
            const text = try llvm.emitUnitWithScratch(temp, backing, plan.module, plan.options, plan.selection(group, false));
            try context.store.storeValue(key, cache.Artifact, emissionArtifact(text));
            break :blk text;
        };
        if (receipt) |receipt_key| try context.store.storeValue(receipt_key, cache.Receipt, receiptArtifact(key, emissionArtifact(seed)));
        plan.symbols[index] = try std.fmt.allocPrint(a, helper_format, .{try digest(a, seed)});
        if (context.counts) |counts| {
            if (served != null) counts.seeds_reused += 1 else counts.seeds_rendered += 1;
        }
    }
}

fn emissionKeyError(err: key_policy.Error) llvm.Error {
    return switch (err) {
        error.UnknownMetadata => error.UnsupportedInstruction,
        else => |other| other,
    };
}

/// What `emissionJob` reads. `trust_receipts` is false when a receipt's artifact proved unreadable: the unit is then emitted
/// afresh and its artifact and receipt are stored again.
const JobInputs = struct { arena: std.mem.Allocator, backing: std.mem.Allocator, plan: *Partition, keys: *key_policy.Prepared, compact: *?key_policy.Compact, context: cache.Context, trust_receipts: bool = true };

fn emissionJob(inputs: JobInputs, group: Group, entry: bool) Error!EmissionJob {
    const a = inputs.arena;
    const backing = inputs.backing;
    const plan = inputs.plan;
    const keys = inputs.keys;
    const compact = inputs.compact;
    const context = inputs.context;
    const receipt = if (compact.*) |*policy| try policy.key(a, plan.module, plan.options, plan.selection(group, entry)) else null;
    var job: EmissionJob = .{ .plan = plan, .context = context, .group = group, .entry = entry, .key = @splat(0), .receipt = receipt, .weight = 1, .backing = backing, .scratch = .init(backing) };
    errdefer job.deinit();
    if (receipt) |receipt_key| if (inputs.trust_receipts) {
        if (context.counts) |counts| counts.work.receipts_checked += 1;
        if (try context.store.loadValue(job.scratch.allocator(), receipt_key, cache.Receipt)) |record| {
            // A receipt is only as good as the artifact it names. Asking the store for the artifact also names it among
            // this build's roots (`stage_roots.zig`), so compaction, which keeps what the roots name, cannot keep the
            // receipt and drop what it points to; an artifact that is already gone makes the receipt a miss, emitted
            // afresh below, never a failure of the build.
            if (try context.store.contains(record.artifact)) {
                job.key = record.artifact;
                job.receipt_hit = record;
                return job;
            }
        }
    };
    for (group.functions.items) |index| try context.ensure(index);
    try plan.ensureCatalog(a, context.counts);
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    if (context.counts) |counts| counts.work.keys_built += 1;
    const input = keys.key(scratch.allocator(), plan.selection(group, entry)) catch |err| return emissionKeyError(err);
    var instructions: usize = 0;
    for (group.functions.items) |index| instructions += plan.module.functions.items[index].insts.items.len;
    job.key = context.store.key("llvm-unit-v1", &.{&input});
    job.weight = cache.weight(instructions);
    return job;
}

const EmissionJob = struct {
    plan: *const Partition,
    context: cache.Context,
    group: Group,
    entry: bool,
    key: key_policy.Digest,
    receipt: ?key_policy.Digest = null,
    weight: usize,
    backing: std.mem.Allocator,
    scratch: std.heap.ArenaAllocator,
    artifact: ?cache.Artifact = null,
    failure: ?Error = null,
    hit: bool = false,
    receipt_hit: ?cache.Receipt = null,

    fn deinit(self: *EmissionJob) void {
        self.scratch.deinit();
        self.scratch = .init(self.backing);
        self.artifact = null;
    }

    fn run(self: *EmissionJob) void {
        self.execute() catch |err| {
            self.failure = err;
        };
    }

    /// Complete a job that needs no work: its receipt hit and the build hands out native handles, so the artifact is the handle the
    /// receipt names and no text is loaded. True when the job is complete.
    fn settle(self: *EmissionJob) bool {
        const record = self.receipt_hit orelse return false;
        if (!self.context.native_handles) return false;
        self.artifact = .{ .text = "", .number = record.dependencies.number, .math = record.dependencies.math, .counting = record.dependencies.counting, .test_counts = record.dependencies.test_counts };
        self.hit = true;
        return true;
    }

    fn execute(self: *EmissionJob) Error!void {
        if (self.artifact != null) return;
        const a = self.scratch.allocator();
        if (self.receipt_hit != null) {
            if (self.settle()) return;
            self.artifact = try self.context.store.loadValue(a, self.key, cache.Artifact) orelse return cache_miss.at(@src());
            self.hit = true;
            return;
        }
        self.artifact = self.context.store.loadValue(a, self.key, cache.Artifact) catch return error.OutOfMemory;
        if (self.artifact != null) {
            self.hit = true;
            if (self.receipt) |receipt| try self.context.store.storeValue(receipt, cache.Receipt, receiptArtifact(self.key, self.artifact.?));
            return;
        }
        const options = if (self.context.deferred) |table| try factsOptions(a, self.plan.options, table, self.group.functions.items) else self.plan.options;
        const text = try llvm.emitUnitWithScratch(a, self.backing, self.plan.module, options, self.plan.selection(self.group, self.entry));
        self.artifact = emissionArtifact(text);
        self.context.store.storeValue(self.key, cache.Artifact, self.artifact.?) catch return error.OutOfMemory;
        if (self.receipt) |receipt| try self.context.store.storeValue(receipt, cache.Receipt, receiptArtifact(self.key, self.artifact.?));
    }
};

/// Run the jobs `batch` names (indices into `jobs`): the first on this thread, the others on threads of their own when they start.
fn runBatch(a: std.mem.Allocator, jobs: []EmissionJob, batch: []const usize) Error!void {
    const threads = try a.alloc(std.Thread, batch.len - 1);
    var started: usize = 0;
    for (threads, batch[1..]) |*thread, at| {
        thread.* = std.Thread.spawn(.{}, EmissionJob.run, .{&jobs[at]}) catch break;
        started += 1;
    }
    jobs[batch[0]].run();
    for (batch[1 + started ..]) |at| jobs[at].run();
    for (threads[0..started]) |thread| thread.join();
}
