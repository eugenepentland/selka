//! Independent LLVM modules with deterministic source ownership and dependencies.
const std = @import("std");
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

/// One object input and its link dependencies, independent of other units' contents.
pub const Unit = struct {
    name: []const u8,
    source_path: []const u8,
    kind: Kind,
    llvm: []const u8,
    dependencies: cache.Dependencies,
    artifact: ?cache.NativeArtifact = null,
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
    catalog: constants.Catalog,

    fn selection(self: *const Partition, group: Group, entry: bool) llvm.Selection {
        return .{ .functions = group.functions.items, .exported = self.exported, .symbols = self.symbols, .source_path = group.path, .entry = entry, .constants = &self.catalog };
    }
};

fn partition(a: std.mem.Allocator, module: *const ir.Module, given: llvm.Options) llvm.Error!Partition {
    return partitionDemand(a, module, given, null) catch |err| switch (err) {
        error.CacheMiss => return error.UnsupportedInstruction,
        else => |other| return other,
    };
}

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
    for (module.functions.items, 0..) |*function, index| {
        const adapter = values.generated(function);
        const synthetic = function.signature.linkage == .internal and
            (std.mem.startsWith(u8, function.name, "lambda@") or std.mem.startsWith(u8, function.name, "__test_") or std.mem.eql(u8, function.name, "<entry>"));
        const helper = adapter or synthetic;
        if (function.signature.linkage != .internal and !helper) continue;
        const location = options.locator.locate(options.locator.context, function.span);
        const path = if (location.path.len != 0) location.path else options.source_path;
        const kind: Kind = if (helper) .helper else if (std.mem.indexOfScalar(u8, function.name, '[') != null) .generic else .module;
        const group = if (kind == .module) moduleGroup(groups.items, path) else null;
        const target = group orelse blk: {
            try groups.append(a, .{ .path = try a.dupe(u8, if (adapter) "myl.helper" else path), .kind = kind });
            break :blk @as(u32, @intCast(groups.items.len - 1));
        };
        owner[index] = target;
        try groups.items[target].functions.append(a, @intCast(index));
    }
    for (module.functions.items, 0..) |_, index| {
        if (context) |ctx| {
            if (ctx.receipts) |receipt| if (index < receipt.finals.len) if (receipt.finals[index]) |final| {
                for (final.outgoing) |target| {
                    if (target >= owner.len) return error.UnsupportedInstruction;
                    if (owner[target] != null and owner[target] != owner[index]) exported[target] = true;
                }
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
            if (target >= owner.len) return error.UnsupportedInstruction;
            if (owner[target] != null and owner[target] != owner[index]) exported[target] = true;
        }
    }
    exported[module.entry] = true;
    const catalog = try constants.Catalog.init(a, module);
    return .{ .module = module, .options = options, .groups = groups, .exported = exported, .symbols = symbols, .catalog = catalog };
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
    const catalog = prepared.catalog;
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
        });
        defer backing.free(seed);
        symbols[index] = try std.fmt.allocPrint(a, helper_format, .{try digest(a, seed)});
    }
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

fn moduleGroup(groups: []const Group, path: []const u8) ?u32 {
    for (groups, 0..) |group, index| if (group.kind == .module and std.mem.eql(u8, group.path, path)) return @intCast(index);
    return null;
}

fn digest(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(text, &hash, .{});
    return std.fmt.allocPrint(a, "{x}", .{hash});
}

/// A unit of `text` with its link dependencies (number-text helpers, `-lm`) read from it.
pub fn unit(name: []const u8, path: []const u8, kind: Kind, text: []const u8) Unit {
    const math = std.mem.indexOf(u8, text, "llvm.sin.f64") != null or std.mem.indexOf(u8, text, "llvm.cos.f64") != null;
    const counting = std.mem.indexOf(u8, text, "@myl_count_current") != null;
    return .{
        .name = name,
        .source_path = path,
        .kind = kind,
        .llvm = text,
        .dependencies = .{
            .number = number_runtime.needed(text),
            .math = math,
            .counting = counting,
            .zero_rc = std.mem.indexOf(u8, text, "; mylang-zero-rc-v2\n") != null,
        },
    };
}

fn emissionArtifact(text: []const u8) cache.Artifact {
    const dependencies = unit("", "", .program, text);
    return .{ .text = text, .number = dependencies.dependencies.number, .math = dependencies.dependencies.math, .counting = dependencies.dependencies.counting, .zero_rc = dependencies.dependencies.zero_rc };
}

/// Reuse completed LLVM by canonical inputs; changed units render in bounded batches.
/// `backing` must support concurrent allocation; `allocator` is coordinator-only.
pub fn emitCached(allocator: std.mem.Allocator, backing: std.mem.Allocator, module: *const ir.Module, options: llvm.Options, context: cache.Context) Error![]Unit {
    var scratch = std.heap.ArenaAllocator.init(backing);
    defer scratch.deinit();
    const a = scratch.allocator();
    var plan = try partitionDemand(a, module, options, context);
    var keys = (if (context.receipts != null) key_policy.Prepared.initLazy(a, module, plan.options, &plan.catalog) else key_policy.Prepared.init(a, module, plan.options, &plan.catalog)) catch |err| switch (err) {
        error.UnknownMetadata => {
            for (module.functions.items, 0..) |_, index| try context.ensure(@intCast(index));
            return emitUncached(allocator, backing, module, options, context.deferred);
        },
        error.OutOfMemory => return error.OutOfMemory,
        error.UnsupportedEntry => return error.UnsupportedEntry,
        error.UnsupportedInstruction => return error.UnsupportedInstruction,
    };
    keys.deferred = context.deferred;
    var compact = try key_policy.Compact.init(a, module, plan.options, &plan.catalog, plan.exported, context);
    try helperSymbols(a, backing, &plan, &keys, &compact, context);
    const jobs = try a.alloc(EmissionJob, plan.groups.items.len + 1);
    var initialized: usize = 0;
    defer for (jobs[0..initialized]) |*job| job.deinit();
    for (plan.groups.items, jobs[0..plan.groups.items.len]) |group, *job| {
        job.* = try emissionJob(.{ .arena = a, .backing = backing, .plan = &plan, .keys = &keys, .compact = &compact, .context = context }, group, false);
        initialized += 1;
    }
    jobs[jobs.len - 1] = try emissionJob(.{ .arena = a, .backing = backing, .plan = &plan, .keys = &keys, .compact = &compact, .context = context }, .{ .kind = .entry, .path = options.source_path }, true);
    initialized += 1;
    var result: std.ArrayList(Unit) = .empty;
    errdefer for (result.items) |emitted| {
        allocator.free(emitted.name);
        allocator.free(emitted.source_path);
        allocator.free(emitted.llvm);
    };
    var names: std.StringHashMapUnmanaged(usize) = .empty;
    var next: usize = 0;
    while (next < jobs.len) {
        const widths = try a.alloc(usize, @min(@max(1, context.lanes), jobs.len - next));
        for (widths, jobs[next..][0..widths.len]) |*weight, job| weight.* = job.weight;
        const count = cache.batch(widths, context.lanes, context.memory_budget_bytes);
        const batch = jobs[next..][0..count];
        try runBatch(a, batch);
        if (context.counts) |counts| counts.workers = @max(counts.workers, @as(u32, @intCast(count)));
        for (batch) |*job| {
            if (job.failure) |failure| return failure;
            const artifact = job.artifact.?;
            const text = try allocator.dupe(u8, artifact.text);
            errdefer allocator.free(text);
            const name = if (context.native_handles and job.receipt_hit != null) try emissionNameDigest(a, job, job.receipt_hit.?.text_digest) else try emissionName(a, job, text);
            if (context.counts) |counts| {
                counts.work.llvm_loaded_bytes += text.len;
                if (context.native_handles and text.len == 0) counts.work.native_handles += 1;
            }
            try append(allocator, a, &result, &names, .{
                .name = name,
                .source_path = job.group.path,
                .kind = job.group.kind,
                .llvm = text,
                .dependencies = .{ .number = artifact.number, .math = artifact.math, .counting = artifact.counting, .zero_rc = artifact.zero_rc },
                .artifact = if (context.native_handles) .{ .store = context.store, .key = job.key } else null,
            });
            if (context.counts) |counts| {
                counts.units += 1;
                if (job.hit) counts.reused += 1 else counts.rendered += 1;
            }
            job.deinit();
        }
        next += count;
    }
    return allocator.dupe(Unit, result.items);
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
    std.crypto.hash.Blake3.hash(artifact.text, &text_digest, .{});
    return .{ .artifact = key, .text_digest = text_digest, .dependencies = .{ .number = artifact.number, .math = artifact.math, .counting = artifact.counting, .zero_rc = artifact.zero_rc } };
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

const JobInputs = struct { arena: std.mem.Allocator, backing: std.mem.Allocator, plan: *const Partition, keys: *key_policy.Prepared, compact: *?key_policy.Compact, context: cache.Context };

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
    if (receipt) |receipt_key| {
        if (context.counts) |counts| counts.work.receipts_checked += 1;
        if (try context.store.loadValue(job.scratch.allocator(), receipt_key, cache.Receipt)) |record| {
            job.key = record.artifact;
            job.receipt_hit = record;
            return job;
        }
    }
    for (group.functions.items) |index| try context.ensure(index);
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

    fn execute(self: *EmissionJob) Error!void {
        if (self.artifact != null) return;
        const a = self.scratch.allocator();
        if (self.receipt_hit) |record| {
            if (self.context.native_handles) {
                self.artifact = .{ .text = "", .number = record.dependencies.number, .math = record.dependencies.math, .counting = record.dependencies.counting, .zero_rc = record.dependencies.zero_rc };
                self.hit = true;
                return;
            }
            self.artifact = try self.context.store.loadValue(a, self.key, cache.Artifact) orelse return error.CacheMiss;
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

fn runBatch(a: std.mem.Allocator, jobs: []EmissionJob) Error!void {
    const threads = try a.alloc(std.Thread, jobs.len - 1);
    var started: usize = 0;
    for (threads, jobs[1..]) |*thread, *job| {
        thread.* = std.Thread.spawn(.{}, EmissionJob.run, .{job}) catch break;
        started += 1;
    }
    jobs[0].run();
    for (jobs[1 + started ..]) |*job| job.run();
    for (threads[0..started]) |thread| thread.join();
}
