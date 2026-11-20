//! Turn emitted LLVM units into an executable with the bundled clang (`zig cc`),
//! through the core's own content-keyed stores (docs/design/new-core-s4.md §6):
//! - the runtime (-O2, whatever the program's level) and the number-text object,
//!   once per content, in the per-user directory `runtimeDirectory` names;
//! - one object per unit in that directory's `units-v1` store (`unit_cache.zig`),
//!   keyed by the unit's text, the mode's whole compile argument list, target, toolchain and runtime ABI. Misses
//!   compile in parallel with `zig cc -c`; hits start no process;
//! - each `--link` C source in the work directory's `foreign-v1` store, keyed by
//!   its bytes and the bytes of every header its compiler depfile listed;
//! - the linked program in the work directory's `programs-v2` store, keyed by
//!   every object it links, so a build whose objects all match links nothing.
//! Every `zig` process gets a fresh local cache inside this build's private
//! staging directory, removed when the build ends: these stores are the cache,
//! and Zig's own would only keep a second copy of every object and program.
//! A minimal driver rather than the old core's `qbe_build_llvm_compile.zig`:
//! that one is bound to the QBE manifest, fragment store and object cache.
const std = @import("std");
const product = @import("selka").product;
const cache_miss = @import("selka").cache_miss;
const vectorize_remarks = @import("vectorize_remarks.zig");
const build_mode = @import("build_mode.zig");
const target_policy = @import("target.zig");
const number_runtime = @import("number_runtime.zig");
const platform = @import("core_tool_platform");
const tool_identity = @import("tool_identity.zig");
const zig_lookup = @import("zig_lookup.zig");
const emit_units = @import("emit_units.zig");
const freestanding_emitted = @import("freestanding_emitted.zig");
const unit_cache = @import("unit_cache.zig");
const c_includes = @import("c_includes.zig");
const inputs_handle = @import("inputs.zig");
const native_receipt = @import("native_receipt.zig");
const count_runtime = @import("count_runtime.zig");
const build_identity = @import("build_identity");
const sanitize_llvm = @import("sanitize_llvm.zig");
const fast_blake3 = @import("fast_blake3.zig");
const Digest = unit_cache.Digest;
const query_store = @import("stage_store.zig");
const stage_metrics = @import("stage_metrics.zig");
const language = @import("selka");
const shared_artifacts = language.shared_artifact_store;
const work_claim = language.native_cache_work;
const program_store = @import("program_store.zig");
const tool_recipe = @import("tool_recipe.zig");
const process_spawn = @import("process_spawn.zig");

/// The runtime C source, compiled into every program.
pub const runtime_source = @embedFile("runtime/core_rt.c") ++ "\n" ++
    @embedFile("runtime/core_dict.c") ++ "\n" ++
    @embedFile("runtime/core_unicode_data.h") ++ "\n" ++
    @embedFile("runtime/core_text.c") ++ "\n" ++
    @embedFile("runtime/core_sort.c") ++ "\n" ++ @embedFile("runtime/core_number.c") ++ "\n" ++
    @embedFile("runtime/core_stop.c") ++ "\n" ++ @embedFile("runtime/core_io.c") ++ "\n" ++ @embedFile("runtime/core_poll.c") ++ "\n" ++ @embedFile("runtime/core_durable.c") ++ "\n" ++
    @embedFile("runtime/core_process.c") ++ "\n" ++ @embedFile("runtime/core_input.c") ++ "\n" ++ @embedFile("runtime/core_host.c") ++ "\n" ++ @embedFile("runtime/core_registers.c") ++ "\n" ++
    @embedFile("runtime/core_sha256.c") ++ "\n" ++
    @embedFile("runtime/core_bytes.c") ++ "\n" ++ @embedFile("runtime/core_values.c") ++ "\n" ++ @embedFile("runtime/core_json.c") ++ "\n" ++
    @embedFile("runtime/core_owned_copy.c") ++ "\n" ++ @embedFile("runtime/core_test.c") ++ "\n" ++ @embedFile("runtime/core_tasks.c");

/// What a program is, besides its bytes: the entry it links (a build's entry, or a test program's file and case)
/// and the mode it is built in. `program_store.zig` keys a program's family by the entry and the mode's whole compile argument list.
pub const Family = struct {
    /// The build mode: its compile argument list decides the units' objects and its level the link.
    mode: build_mode.Mode = .optimized_debug,
    /// The entry the program belongs to; empty when the caller has none.
    entry: []const u8 = "",
    /// The target the units compile for (`--target`); a bare one (`Runtime.bare`) links its runtime and lays out its image
    /// with `linker_script`.
    target: *const target_policy.Target = &target_policy.host,
    /// The linker script of a bare target's image (`--linker-script`); null for a hosted target.
    linker_script: ?[]const u8 = null,
    /// The text of a script the compiler wrote from a device's `memory` (`device_layout.generate`): the link uses it as a named
    /// script, keyed by its bytes, and `linker_script` is null.
    linker_text: ?[]const u8 = null,
    /// Folders added to the include path of every `--link` C source (`-I`), in order; part of each source's key.
    include: []const []const u8 = &.{},
    /// A bare image whose symbol table is kept (`-g`, so `zig cc` does not pass `-s`, which `--strip-debug` would also mean
    /// to it): the image check of
    /// `@freestanding(ram)` functions reads it (`ram_image.zig`). Only a program with such a function sets it; it is part
    /// of the program's key (`keptSymbols`).
    symbols: bool = false,
};

/// One build: tools, directories, the program and how to optimize it.
pub const Request = struct {
    /// The `zig` executable whose `cc` compiles and links.
    zig: []const u8,
    /// The build's cache directory: foreign objects, linked programs and staging.
    work: []const u8,
    output: []const u8,
    family: Family = .{},
    /// Extra C sources to compile and link (`--link`).
    links: []const []const u8,
    /// Independent LLVM inputs, in link order (`emit_units`, or `wholeUnit`).
    units: []const emit_units.Unit = &.{},
    /// `--verify-cache`: also recompile every unit the store served and require
    /// the same object bytes.
    /// `check_vectorize`: a release build checks its `@vectorize` loops (the shipped facts mode only; an
    /// instrumented `--verify-facts` build adds calls inside the loops, which LLVM will not vectorize).
    inspection: struct { verify: bool = false, measure_units: bool = false, check_vectorize: bool = true } = .{},
};

/// One distinct native input. A reused unit has no compile interval, not a fake
/// zero-duration compile. Parallel intervals overlap and must never be summed
/// to infer end-to-end latency or attributed to frontend checking.
pub const UnitTiming = struct {
    name: []const u8,
    source_path: []const u8,
    kind: emit_units.Kind,
    key: []const u8,
    action: enum { reused, compiled, verified, failed },
    compile_ns: ?u64 = null,
    scope: []const u8 = "native-compile-process; startup and diagnostic capture included; queue/frontend/cache IO excluded",
};

/// Why a native build failed; the tool's output was written to `log`.
pub const Error = error{ ToolFailed, OutOfMemory, WriteFailed, CacheMiss, VectorizeFailed };

/// What the tool recipes (`tool_recipe.zig`) did in one build.
pub const RecipeCounts = struct {
    /// The link ran as the recipe's `zig ld.lld`, not as `zig cc`.
    link: bool = false,
    /// Units compiled by the recipe's `zig clang`, not by `zig cc -c`.
    units: u32 = 0,
    /// Zig processes that only learned a recipe (a probe compile, a second link to a throwaway output): not counted in `processes`,
    /// which are the ones that made this build's objects and program.
    learned: u32 = 0,
};

/// What the link step of one build did, for `--report` and the tests. Times are wall nanoseconds.
pub const LinkCounts = struct {
    /// Inside the final native linker process, zero on program cache hits.
    ns: u64 = 0,
    /// Putting the program at the output path: a hard link or a copy.
    output_ns: u64 = 0,
    /// Publishing the program to the work directory's store: reading and hashing it, the sidecar, the rename, pruning older programs.
    store_ns: u64 = 0,
    /// Publishing it to the per-user shared store and making the private name a link to the shared record.
    shared_ns: u64 = 0,
    /// How the output was placed; null when nothing was written (a build that failed first).
    placement: ?program_store.Placement = null,
    /// Scans of the guest toolchain's files that ran (each stats every file of its inventory); a check with no tool process since the
    /// last passing scan does not run one.
    tool_scans: u32 = 0,
    /// What the tool recipes (`tool_recipe.zig`) did.
    recipes: RecipeCounts = .{},
};

/// What one build did, for `--cache-report` and the tests.
pub const Counts = struct {
    /// Distinct units linked.
    units: u32 = 0,
    /// Units whose verified object the store served.
    reused: u32 = 0,
    /// Units compiled by this build.
    compiled: u32 = 0,
    /// Served units recompiled by `--verify-cache` and found byte-identical.
    verified: u32 = 0,
    /// Every `zig` process this build started.
    processes: u32 = 0,
    /// The link step: the linker process and the output's placement.
    link: LinkCounts = .{},
    /// Shared program publications that found a verified record with different
    /// bytes under the same key: a miss, logged in the store's `mismatches.log`.
    shared_mismatches: u32 = 0,
};

/// The result of a successful `link`.
pub const Outcome = struct {
    counts: Counts = .{},
    /// Whether a local or verified shared program avoided a new link.
    reuse: struct { local: bool = false, shared: bool = false } = .{},
    /// The program store entry the output was copied from (proved toolchains only).
    program: ?unit_cache.Found = null,
    /// The `--link` sources and the headers their depfiles listed, with the bytes
    /// the compiles read, and the header names they looked for and did not find
    /// (inputs of the handle, `inputs.zig`); null when a file changed while it was
    /// compiled, so no later build may trust these digests.
    foreign: ?[]const inputs_handle.Input = &.{},
    /// The toolchain identity the build ran under.
    tool: tool_identity.Identity,
    /// The linked program's exact key (`programKey`): toolchain, target, every object
    /// and the linker environment, with no path and no compiler identity. Set on
    /// every successful link, whether the program was linked, reused or restored;
    /// test execution receipts bind it (EXEC-RECEIPT-1).
    program_key: ?Digest = null,
    unit_timings: []const UnitTiming = &.{},
};

/// A whole-program LLVM text as the one unit of a build.
pub fn wholeUnit(llvm: []const u8) emit_units.Unit {
    return emit_units.unit("whole", "", .program, llvm);
}

const Guard = struct {
    resources: tool_identity.Request,
    identity: tool_identity.Identity,
    /// Where the last passing scan stood, when the caller keeps one (`Native.checkTool`).
    memo: ?*Memo = null,

    /// The number of tool processes this build had started when its toolchain last passed a scan.
    const Memo = struct { passed: ?u32 = null };

    /// Validate the captured tool before publishing a native object or accepting a link.
    pub fn check(self: Guard, log: *std.ArrayList(u8)) Error!void {
        const stable = tool_identity.unchanged(self.resources, self.identity) catch |err| changed: {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            break :changed false;
        };
        if (!stable) {
            try log.appendSlice(self.resources.arena, "error: guest toolchain changed during native compilation\n");
            return error.ToolFailed;
        }
    }
};

/// The tools and accounting every native step of one build shares.
const Native = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    zig: []const u8,
    log: *std.ArrayList(u8),
    guard: Guard,
    counts: *Counts,
    backing: ?std.mem.Allocator = null,
    /// Where the recipes of the tool's child processes live; null for a tool that is not proved, whose builds share nothing.
    recipes: ?Recipes = null,
    /// The target every compile and link of the build is for.
    target: *const target_policy.Target = &target_policy.host,

    fn resources(self: Native) unit_cache.Resources {
        return .{ .arena = self.arena, .io = self.io, .environment = self.environment, .backing = self.backing, .memory_budget_bytes = stage_metrics.workerBudget(self.io) };
    }

    /// `guard.check`, unless it already passed with no tool process started since: the scan asks whether the toolchain changed while a
    /// process of it was producing something, so a second scan with no process between is the same question and a toolchain edited
    /// after the first scan has produced nothing yet. Counts the scans that ran (`link.tool_scans`).
    fn checkTool(self: Native, log: *std.ArrayList(u8)) Error!void {
        const started = self.counts.processes + self.counts.link.recipes.learned;
        if (self.guard.memo) |memo| if (memo.passed == started) return;
        try self.guard.check(log);
        self.counts.link.tool_scans += 1;
        if (self.guard.memo) |memo| memo.passed = started;
    }
};

/// Where a build keeps the recipes (`tool_recipe.zig`) of the toolchain it runs, and what they are keyed by.
const Recipes = struct {
    /// The directory the recipes are stored in.
    directory: []const u8,
    /// The toolchain's content digest and native target, hashed together.
    identity: Digest,
    /// The Zig global cache directory the build runs under: a link recipe names Zig's stubs in it.
    global_cache: []const u8,
    /// A private directory of the build, for the probe that learns a compile recipe.
    staging: []const u8,
};

/// A recipe this build learned, kept until the toolchain has passed its scan after the processes that produced it, so a toolchain edited
/// while they ran leaves nothing stored.
const Learned = struct { kind: tool_recipe.Kind, digest: Digest, tokens: []const []const u8 };

/// Store `learned`, when there is one.
fn storeLearned(native: Native, learned: ?Learned) std.mem.Allocator.Error!void {
    const recipes = native.recipes orelse return;
    const item = learned orelse return;
    try tool_recipe.store(native.arena, native.io, recipes.directory, item.kind, item.digest, item.tokens);
}

/// Where one build keeps what it caches: `shared` (per-user, content keys only)
/// and `local` (the work directory), or both inside `staging` for an unproved tool.
const Places = struct { shared: []const u8, local: []const u8, staging: []const u8, cacheable: bool };

/// One object to link and the digest of its bytes (or of its store key, for the
/// runtime objects, whose key covers their whole input).
const Object = struct { path: []const u8, digest: Digest };

/// What the runtime must provide for `units`: the union of each unit's dependencies.
fn dependenciesOf(units: []const emit_units.Unit) Dependencies {
    var needs: Dependencies = .{};
    for (units) |unit| needs = .{
        .number = needs.number or unit.dependencies.number,
        .math = needs.math or unit.dependencies.math,
        .counting = needs.counting or unit.dependencies.counting,
        // A unit that links a `testing` counter reader needs the
        // allocation-event runtime variant (`B5`); the emission records it, so a
        // receipt hit keeps the bit even when its LLVM text is not loaded.
        .test_counts = needs.test_counts or unit.dependencies.test_counts,
    };
    return needs;
}

/// Compile and link `request.units` into `request.output`; failures append the tool's stderr to `log`.
pub fn link(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, request: Request, log: *std.ArrayList(u8)) Error!Outcome {
    return linkWithScratch(allocator, null, io, environ, request, log);
}

/// Link with private worker arenas on a reclaiming thread-safe allocator.
pub fn linkWithScratch(allocator: std.mem.Allocator, backing: ?std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, given: Request, log: *std.ArrayList(u8)) Error!Outcome {
    // The runtime's flavour (`bareFlavour`): a program that starts the second core links the two-core runtime, and its
    // units ask for the calling core's free lists; every other program is built as if the second core did not exist.
    const flavour = try bareFlavour(allocator, given.family.target, given.units);
    var request = given;
    if (flavour.cores) request.units = try perCoreUnits(allocator, given.units);
    try validateLayout(allocator, environ, log);
    try validateSanitize(allocator, environ, log);
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, request.work) catch return error.WriteFailed;
    var environment = environ.clone(allocator) catch return error.OutOfMemory;
    defer environment.deinit();
    // The link runs in `link_directory`, so every path it is given must be absolute.
    const here = cwd.realPathFileAlloc(io, ".", allocator) catch return error.WriteFailed;
    const staging = try std.fs.path.resolve(allocator, &.{ here, try privateDirectory(allocator, io, request.work, "native-link") });
    defer removeDirectory(io, staging);
    environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(allocator, &.{ staging, "local" })) catch return error.OutOfMemory;
    const resources: tool_identity.Request = .{ .arena = allocator, .io = io, .environment = &environment, .executable = request.zig, .cache = request.work };
    const guest = tool_identity.capture(resources) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try log.print(allocator, "error: cannot run {s}: cannot identify guest toolchain: {s}\n{s}", .{ request.zig, @errorName(err), zig_lookup.hintFor(err) });
        return error.ToolFailed;
    };
    // Zig's global cache holds its own libc stub and compiler-rt builds, and a program carries
    // them, debug information included: the stubs name the directory they were built in. A
    // fresh cache rebuilds them (about 6 s), so a proved tool shares one cache of selka's own,
    // always filled by links that run in `link_directory`, and the user's `ZIG_GLOBAL_CACHE_DIR`
    // (which other builds fill from other directories) never reaches the program. An unproved
    // tool gets a private one and never writes the shared builds.
    const shared_zig = if (guest.cacheable) try zigGlobalDirectory(allocator, io, environ) else null;
    environment.put("ZIG_GLOBAL_CACHE_DIR", shared_zig orelse try std.fs.path.join(allocator, &.{ staging, "global" })) catch return error.OutOfMemory;
    var outcome: Outcome = .{ .tool = guest };
    const memo = try allocator.create(Guard.Memo);
    memo.* = .{};
    // Content-keyed objects are shared, so a fresh work directory (a new worktree,
    // a test's temporary directory) reuses them; an unproved tool keeps every
    // object private to this build.
    const places: Places = .{
        .shared = if (guest.cacheable) try runtimeDirectory(allocator, io, environ, request.work) else staging,
        .local = if (guest.cacheable) request.work else staging,
        .staging = staging,
        .cacheable = guest.cacheable,
    };
    const native: Native = .{
        .arena = allocator,
        .io = io,
        .environment = &environment,
        .zig = guest.path,
        .log = log,
        .guard = .{ .resources = resources, .identity = guest, .memo = memo },
        .counts = &outcome.counts,
        .backing = backing,
        .recipes = recipesFor(allocator, places, guest, shared_zig) catch return error.OutOfMemory,
        .target = request.family.target,
    };
    // A sweep of the per-user store never holds a build off it for long (`native_cache_work.lease_wait_ms`): past the bound the
    // build goes on without the lease, as `selka test --no-cache` does while it is collecting.
    const shared_lease = if (places.cacheable) try work_claim.leaseWithin(allocator, io, places.shared, work_claim.lease_wait_ms) else null;
    defer if (shared_lease) |file| file.close(io);
    const local_lease = if (places.cacheable and !std.mem.eql(u8, places.shared, places.local)) try work_claim.lease(allocator, io, places.local) else null;
    defer if (local_lease) |file| file.close(io);
    const needs = dependenciesOf(request.units);
    const runtime = try runtimeFor(allocator, io, places.shared, Variant.of(needs.counting, needs.test_counts), environ, log);
    const settings: unit_cache.Settings = .{ .tool = guest.digest, .cpu = guest.native_target, .mode = request.family.mode, .runtime = runtime.abi, .target = request.family.target };
    var objects: std.ArrayList(Object) = .empty;
    // A bare target links its own runtime units, never the host's number-text object (the build refused a program that
    // needs it, `bareNumberUse`), and lays out its image with the build's linker script (`script`, null for a hosted target).
    const script = if (bareOf(request.family.target) == null) null else if (request.family.linker_text) |text|
        try writeLinkerScript(allocator, io, staging, text, log)
    else
        try readLinkerScript(allocator, io, here, request.family.linker_script, log);
    try objects.appendSlice(allocator, try runtimeObjects(native, places, runtime, request.family.mode, flavour));
    outcome.unit_timings = try unitObjects(native, places, settings, request, &objects);
    if (needs.number and script == null) try objects.append(allocator, .{ .path = try number_runtime.object(allocator, io, places.shared), .digest = number_runtime.digest() });
    outcome.foreign = try foreignObjects(native, places, settings, request, &objects);
    const sanitizer = linkSanitizer(request.family.mode == .release, request.links.len);
    const program_key = keptSymbols(programKey(settings, objects.items, needs.math, sanitizer, environ, script), request.family.symbols);
    outcome.program_key = program_key;
    const programs: unit_cache.Store = .{ .directory = try std.fs.path.join(allocator, &.{ places.local, program_store.directory_name }) };
    const family = program_store.family(request.family.entry, request.family.mode.keyed());
    const family_suffix = try program_store.suffix(allocator, family);
    var shared = try SharedProgram.open(native, request, program_key);
    defer if (shared) |*store| store.store.deinit();
    var program_claim: ?work_claim.Claim = if (!places.cacheable or request.inspection.verify) null else try work_claim.Claim.acquire(allocator, io, programs.directory, program_key);
    defer if (program_claim) |*claim| claim.deinit();
    var shared_claim = try SharedProgram.claim(shared, program_claim != null);
    defer if (shared_claim) |*claim| claim.deinit();
    if (program_claim != null) try native.checkTool(log);
    // A stored program is read only through a pin of this build's own: a concurrent build may remove the store's
    // name at any time, and a pin that finds it gone is a miss that links afresh, never an error.
    if (places.cacheable) if (try programs.lookup(allocator, io, program_key, family_suffix)) |found| {
        const pin_path = try std.fs.path.join(allocator, &.{ staging, "pinned" });
        if (try program_store.pin(io, found.path, pin_path)) {
            if (shared) |*store| try publishStored(native, store, pin_path, found);
            try placeOutput(native, &.{ found.path, pin_path }, request.output);
            outcome.reuse.local = true;
            outcome.program = found;
            return outcome;
        }
    };
    const linked = try std.fs.path.join(allocator, &.{ staging, "program" });
    if (shared) |*store| if (try store.restore(native, linked)) {
        try native.checkTool(log);
        const kept = try keepProgram(native, staging, linked);
        const store_start = stage_metrics.now(io);
        const restored = try programs.publish(allocator, io, program_key, family_suffix, linked);
        try program_store.keepNewest(allocator, io, programs.directory, family);
        native.counts.link.store_ns += stage_metrics.elapsed(io, store_start);
        try placeOutput(native, &.{ restored.path, kept }, request.output);
        outcome.reuse.local = true;
        outcome.reuse.shared = true;
        outcome.program = restored;
        return outcome;
    };
    const line = try linkLine(native, request.family, environ, sanitizer, needs.math, script);
    var inputs: std.ArrayList([]const u8) = .empty;
    for (objects.items) |object| try inputs.append(allocator, try std.fs.path.resolve(allocator, &.{ here, object.path }));
    const link_start = stage_metrics.now(io);
    const learned = try runLink(native, .{ .head = line.head, .objects = inputs.items, .tail = line.tail, .output = linked });
    outcome.counts.link.ns = stage_metrics.elapsed(io, link_start);
    try native.checkTool(log);
    try storeLearned(native, learned);
    if (!places.cacheable) {
        try placeOutput(native, &.{linked}, request.output);
        return outcome;
    }
    const kept = try keepProgram(native, staging, linked);
    const store_start = stage_metrics.now(io);
    const published = try programs.publish(allocator, io, program_key, family_suffix, linked);
    try program_store.keepNewest(allocator, io, programs.directory, family);
    native.counts.link.store_ns += stage_metrics.elapsed(io, store_start);
    const shared_start = stage_metrics.now(io);
    try publishShared(allocator, native, &shared, staging, published.path, published.digest);
    native.counts.link.shared_ns += stage_metrics.elapsed(io, shared_start);
    // Last, so the output is a name of the stored file the shared store may have swapped in: a replay then finds it there already.
    try placeOutput(native, &.{ published.path, kept }, request.output);
    outcome.program = published;
    return outcome;
}

/// The arguments of a link before its objects and after them (`LinkSpec.head`, `LinkSpec.tail`).
const LinkLine = struct { head: []const []const u8, tail: []const []const u8 };

/// The link's arguments for `family`: the mode's level, the target and its CPU flags, the sanitizer controls, then for a hosted
/// target `-pthread` and, after the objects, `-lm` when `math`; for a bare one its whole-image flags in a `--release` build and,
/// after the objects, its link arguments and the linker script `script`.
fn linkLine(native: Native, family: Family, environ: *const std.process.Environ.Map, sanitizer: []const u8, math: bool, script: ?LinkerScript) Error!LinkLine {
    const a = native.arena;
    const bare = bareOf(family.target);
    var head: std.ArrayList([]const u8) = .empty;
    try head.appendSlice(a, &.{ "cc", family.mode.level(), "-target", native.target.cc_target });
    try head.appendSlice(a, native.target.cpu_flags);
    if (bare) |runtime_units| try head.appendSlice(a, wholeImage(runtime_units, family.mode));
    if (sanitizer.len != 0) try head.append(a, sanitizer);
    try head.appendSlice(a, sanitizeArguments(environ));
    if (bare == null) try head.append(a, "-pthread");
    try head.append(a, "-Wno-override-module");
    var tail: std.ArrayList([]const u8) = .empty;
    try tail.appendSlice(a, sanitizeLinkArguments(environ));
    if (bare) |runtime_units| {
        try tail.appendSlice(a, runtime_units.link);
        try tail.append(a, try std.fmt.allocPrint(a, "-Wl,-T,{s}", .{script.?.path}));
        if (family.symbols) try tail.append(a, "-g");
    } else if (math) try tail.append(a, "-lm");
    return .{ .head = head.items, .tail = tail.items };
}

/// The runtime objects a program of this build's target links first: the hosted runtime's one (`runtimeObject`), or a bare
/// runtime's units (`bareRuntimeObjects`) in the flavour the program asks for (`bareFlavour`).
fn runtimeObjects(native: Native, places: Places, runtime: Runtime, mode: build_mode.Mode, flavour: BareFlavour) Error![]const Object {
    if (bareOf(native.target)) |runtime_units| return bareRuntimeObjects(native, places, runtime_units, .{ .mode = mode, .flavour = flavour });
    const hosted = try native.arena.alloc(Object, 1);
    hosted[0] = try runtimeObject(native, places.shared, places.staging, runtime);
    return hosted;
}

/// The identity and places of the recipes of a proved toolchain (`tool_recipe.zig`); null when the build shares nothing (an unproved
/// tool) or has no shared Zig cache to name (`global_cache` null: the link would name stubs of a directory that goes with the build).
fn recipesFor(a: std.mem.Allocator, places: Places, guest: tool_identity.Identity, global_cache: ?[]const u8) std.mem.Allocator.Error!?Recipes {
    const global = global_cache orelse return null;
    if (!places.cacheable) return null;
    var hash = fast_blake3.Blake3.init(.{});
    hash.update(&guest.digest);
    hash.update(&guest.native_target);
    var identity: Digest = undefined;
    hash.final(&identity);
    return .{ .directory = try std.fs.path.join(a, &.{ places.shared, tool_recipe.directory_name }), .identity = identity, .global_cache = global, .staging = places.staging };
}

/// What a link is made of: the driver's arguments before the output, the objects, the arguments after them, and the output.
const LinkSpec = struct { head: []const []const u8, objects: []const []const u8, tail: []const []const u8, output: []const u8 };

/// Link `spec`: through the recipe's `zig ld.lld` when the toolchain's recipe is known and its files exist, else through `zig cc`,
/// which (for a proved toolchain) is followed by a second link that learns the recipe of the next one. A recipe whose linker fails
/// is not trusted: the link runs again as `zig cc`, whose output is what the build reports. The caller stores what was learned once
/// the toolchain has passed its scan (`storeLearned`).
fn runLink(native: Native, spec: LinkSpec) Error!?Learned {
    const a = native.arena;
    var driver_argv: std.ArrayList([]const u8) = .empty;
    try driver_argv.append(a, native.zig);
    try driver_argv.appendSlice(a, spec.head);
    try driver_argv.appendSlice(a, &.{ "-o", spec.output });
    try driver_argv.appendSlice(a, spec.objects);
    try driver_argv.appendSlice(a, spec.tail);
    const recipes = native.recipes orelse {
        try runIn(native, driver_argv.items, link_directory);
        return null;
    };
    var shape: std.ArrayList([]const u8) = .empty;
    try shape.appendSlice(a, spec.head);
    try shape.append(a, "--");
    try shape.appendSlice(a, spec.tail);
    const digest = tool_recipe.key(.link, recipes.identity, shape.items);
    const stored = try tool_recipe.load(a, native.io, recipes.directory, .link, digest);
    if (stored) |tokens| {
        // No tokens: Zig's linker line was found to be no recipe; link as `zig cc`, and learn nothing more.
        if (tokens.len == 0) {
            try runIn(native, driver_argv.items, link_directory);
            return null;
        }
        if (tool_recipe.filesExist(native.io, tokens, recipes.global_cache)) {
            const argv = try tool_recipe.linkArguments(a, native.zig, tokens, spec.objects, spec.output);
            if (try runQuietly(native, argv, link_directory)) {
                native.counts.link.recipes.link = true;
                return null;
            }
        }
    }
    return learnLink(native, recipes, driver_argv.items, spec, digest);
}

/// Start `argv` in `directory` under `environment` and wait for it; null when it could not start. Output goes to the caller, not the log.
fn spawnQuietly(native: Native, argv: []const []const u8, directory: ?[]const u8, environment: *const std.process.Environ.Map) Error!?std.process.RunResult {
    const result = process_spawn.run(native.arena, native.io, .{ .argv = argv, .environment = .{ .map = environment }, .cwd = directory, .die_with_parent = true }) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    return result;
}

/// Whether a child ended with status 0.
fn succeeded(result: std.process.RunResult) bool {
    return switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
}

/// Run `argv` in `directory` (counted); true when it succeeded, its stderr then in the log. A failure leaves the log alone, for a
/// caller that tries another way.
fn runQuietly(native: Native, argv: []const []const u8, directory: ?[]const u8) Error!bool {
    native.counts.processes += 1;
    const result = (try spawnQuietly(native, argv, directory, native.environment)) orelse return false;
    if (!succeeded(result)) return false;
    try native.log.appendSlice(native.arena, result.stderr);
    return true;
}

/// Link as `zig cc` does, and learn the recipe of the next link: the same link again, to a throwaway output under `ZIG_VERBOSE_LINK`,
/// whose printed linker command line (Zig builds its stubs on a first link and prints their commands too) is the recipe. A toolchain
/// whose line cannot be one gets the record that says so, and a probe that fails leaves nothing.
fn learnLink(native: Native, recipes: Recipes, argv: []const []const u8, spec: LinkSpec, digest: Digest) Error!?Learned {
    try runIn(native, argv, link_directory);
    const a = native.arena;
    const output = try std.fs.path.join(a, &.{ recipes.staging, "recipe-program" });
    const probe = try a.dupe([]const u8, argv);
    // The output's place: `runLink` wrote the driver's line as `zig head... -o output objects... tail...`.
    probe[1 + spec.head.len + 1] = output;
    native.counts.link.recipes.learned += 1;
    var environment = native.environment.clone(a) catch return error.OutOfMemory;
    defer environment.deinit();
    environment.put("ZIG_VERBOSE_LINK", "1") catch return error.OutOfMemory;
    const result = (try spawnQuietly(native, probe, link_directory, &environment)) orelse return null;
    if (!succeeded(result)) return null;
    const tokens = try tool_recipe.linkTokens(a, result.stderr, spec.objects, output);
    return .{ .kind = .link, .digest = digest, .tokens = tokens orelse &.{} };
}

/// Publish the program the work directory's store already holds (`found`, held by the build's own `pin`) to the shared store, timing it.
/// A record that already holds this very program has nothing to be published: asking costs two small reads, publishing it again
/// reads and hashes the whole record.
fn publishStored(native: Native, store: *SharedProgram, pin: []const u8, found: unit_cache.Found) Error!void {
    const start = stage_metrics.now(native.io);
    if (!store.holds(found.digest)) try store.publish(native, pin, found.path, found.digest);
    native.counts.link.shared_ns += stage_metrics.elapsed(native.io, start);
}

/// Take the write permission off the linked program and give it a second name inside this build's staging directory, which
/// the caller places at the output if a concurrent sweep removes the store's name first. Returns the second name.
fn keepProgram(native: Native, staging: []const u8, linked: []const u8) Error![]const u8 {
    program_store.protect(native.io, linked);
    const kept = try std.fs.path.join(native.arena, &.{ staging, "kept" });
    if (!try program_store.pin(native.io, linked, kept)) return error.WriteFailed;
    return kept;
}

/// Publish the stored program at `private` to the shared store through a pin of this build's own, so a sweep that
/// removes the stored name cannot break the record (G9). Nothing happens when sharing is off.
fn publishShared(allocator: std.mem.Allocator, native: Native, shared: *?SharedProgram, staging: []const u8, private: []const u8, digest: Digest) Error!void {
    const store = if (shared.*) |*found| found else return;
    const pin_path = try std.fs.path.join(allocator, &.{ staging, "pinned" });
    if (try program_store.pin(native.io, private, pin_path)) try store.publish(native, pin_path, private, digest);
}

// Exact artifact transport preserves every source path and literal in the
// object keys. Module projects already use logical paths; absolute single-file
// provenance differs across roots and therefore cannot hit another root's key.
const SharedProgram = struct {
    store: shared_artifacts.Store,
    key: Digest,

    fn claim(self: ?SharedProgram, enabled: bool) Error!?work_claim.Claim {
        if (!enabled) return null;
        const present = self orelse return null;
        return present.store.claim(.program, present.key);
    }

    fn open(native: Native, request: Request, exact: Digest) Error!?SharedProgram {
        if (!native.guard.identity.cacheable or request.inspection.verify or request.links.len != 0) return null;
        const directory = shared_artifacts.selected(native.environment) orelse return null;
        const store = shared_artifacts.Store.open(native.arena, native.io, directory) catch |err| return failed(native, err);
        return .{ .store = store, .key = sharedProgramKey(exact, native.environment) };
    }

    /// Whether the shared store already holds the program with `digest` under this key (`shared_artifacts.Store.holdsProgram`).
    fn holds(self: *const SharedProgram, digest: Digest) bool {
        return self.store.holdsProgram(self.key, digest);
    }

    fn restore(self: *SharedProgram, native: Native, destination: []const u8) Error!bool {
        return self.store.restore(.program, self.key, destination) catch |err| return failed(native, err);
    }

    // A mismatch keeps the other record, publishes nothing and counts; the build
    // goes on with its own program.
    // `source` is a pin owned by this build; `private` is the stored name it came from.
    fn publish(self: *SharedProgram, native: Native, source: []const u8, private: []const u8, digest: Digest) Error!void {
        try native.checkTool(native.log);
        // `digest` is the one hash of the program's bytes this build made (the work directory's store), handed over rather than made again.
        const published = self.store.publishHashedFile(.program, self.key, source, digest) catch |err| return failed(native, err);
        switch (published) {
            .mismatch => native.counts.shared_mismatches += 1,
            .stored, .present => try self.adopt(native, private),
            .skipped => {},
        }
    }

    // The private program becomes a hardlink to the shared record, so both names share one executable. The
    // bytes are equal (the record was verified or just written), so a refused link (another file system) leaves the private
    // program as it is, which only costs disk; copying the record over it would write the same bytes again.
    fn adopt(self: *SharedProgram, native: Native, path: []const u8) Error!void {
        // A stored name a sweep already removed stays absent: replacing it would store a program without its sidecar.
        _ = std.Io.Dir.cwd().statFile(native.io, path, .{ .follow_symlinks = false }) catch return;
        const record = self.store.artifactPath(.program, self.key) catch |err| return failed(native, err);
        _ = program_store.relink(native.io, record, path, program_store.hardLink);
    }

    fn failed(native: Native, err: anyerror) Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        native.log.print(native.arena, "error: compiler shared program cache: {s}\n", .{@errorName(err)}) catch return error.OutOfMemory;
        return error.WriteFailed;
    }
};

/// The shared store's key for a linked program (SHARED-PROGRAM-3): the exact program
/// key and the linker environment. The objects determine the bytes, so it binds no
/// compiler identity, and the store's byte verification guards the rest. Version 3 names
/// the raw-executable record layout (`shared_artifact_store.zig`), so v2 records are not read.
fn sharedProgramKey(exact: Digest, environment: *const std.process.Environ.Map) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-shared-program-v3");
    unit_cache.field(&hash, &exact);
    linkEnvironmentInto(&hash, environment);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

// spec-case: COMPILER-SHARED-CACHE-1
test "shared program identity retains exact native inputs and linker environment without worktree bookkeeping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(arena.allocator());
    defer environment.deinit();
    const original = sharedProgramKey(@splat(1), &environment);
    try std.testing.expect(!std.mem.eql(u8, &original, &sharedProgramKey(@splat(2), &environment)));
    try environment.put("PWD", "receiving-worktree");
    try environment.put("ZIG_LOCAL_CACHE_DIR", "private-staging");
    try environment.put(shared_artifacts.environment_variable, "another-shared-store");
    try std.testing.expectEqual(original, sharedProgramKey(@splat(1), &environment));
    try environment.put("SOURCE_DATE_EPOCH", "1");
    try std.testing.expect(!std.mem.eql(u8, &original, &sharedProgramKey(@splat(1), &environment)));
    const dated = sharedProgramKey(@splat(1), &environment);
    try environment.put("SOURCE_DATE_EPOCH", "2");
    try std.testing.expect(!std.mem.eql(u8, &dated, &sharedProgramKey(@splat(1), &environment)));
    try environment.put("ZERO_AR_DATE", "");
    const explicit = sharedProgramKey(@splat(1), &environment);
    _ = environment.swapRemove("ZERO_AR_DATE");
    try std.testing.expect(!std.mem.eql(u8, &explicit, &sharedProgramKey(@splat(1), &environment)));
}

// spec: SHARED-PROGRAM-3
test "shared program keys bind the exact program and linker environment, not the compiler identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(arena.allocator());
    defer environment.deinit();
    const exact: Digest = @splat(3);
    const key = sharedProgramKey(exact, &environment);
    var expected_hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&expected_hash, "core-shared-program-v3");
    unit_cache.field(&expected_hash, &exact);
    linkEnvironmentInto(&expected_hash, &environment);
    var expected: Digest = undefined;
    expected_hash.final(&expected);
    try std.testing.expectEqual(expected, key);
    try std.testing.expect(!std.mem.eql(u8, &key, &sharedProgramKey(@splat(4), &environment)));
    try environment.put("SOURCE_DATE_EPOCH", "1");
    try std.testing.expect(!std.mem.eql(u8, &key, &sharedProgramKey(exact, &environment)));
}

const Dependencies = @import("emission_cache.zig").Dependencies;

/// Which runtime text a build compiles. `ordinary` is embedded as it is; `counters`
/// is the `--counters` transformation (`count_runtime.zig`); `test_counts` inserts
/// the `testing` module's one flag-guarded allocation event
/// (`testcount_runtime.zig`), and only a program that imports `testing` selects it,
/// so every other program's allocation path is unchanged.
pub const Variant = enum {
    ordinary,
    counters,
    test_counts,
    /// The variant a build needs: `--counters` outranks a `testing` import.
    fn of(counting: bool, test_counts: bool) Variant {
        if (counting) return .counters;
        return if (test_counts) .test_counts else .ordinary;
    }
    /// The memo file and digest-kind name of this variant.
    fn label(self: Variant) []const u8 {
        return switch (self) {
            .ordinary => "ordinary",
            .counters => "counting",
            .test_counts => "test-counts",
        };
    }
};

/// The runtime a build compiles and its digests. The transformed text is built only
/// where an object has to be compiled (`runtimeText`, `source` empty until then):
/// the digests that key everything else come from a record.
const Runtime = struct { source: []const u8, abi: Digest, implementation: Digest, variant: Variant = .ordinary };

fn runtimeFor(allocator: std.mem.Allocator, io: std.Io, directory: []const u8, variant: Variant, environment: *const std.process.Environ.Map, log: *std.ArrayList(u8)) Error!Runtime {
    const known = try sourceDigests(allocator, io, directory, variant, log);
    const abi = abiFrom(known.surface, variant, environment);
    if (layoutArguments(environment).len != 0 or sanitizeArguments(environment).len != 0)
        return runtimeWithSource(try runtimeSource(allocator, variant, log), abi, environment, variant);
    return .{ .source = if (variant == .ordinary) runtime_source else "", .abi = abi, .implementation = known.source, .variant = variant };
}

/// The text of the ordinary runtime, or of a transformed runtime built from it.
fn runtimeSource(allocator: std.mem.Allocator, variant: Variant, log: *std.ArrayList(u8)) Error![]const u8 {
    return switch (variant) {
        .ordinary => runtime_source,
        .counters => counted: {
            // The counting runtime also carries the `testing` allocation event, so a
            // `--counters` build that measures agrees with its own `allocs` counter.
            const counted_text = count_runtime.source(allocator, runtime_source) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.AnchorMissing => {
                    try log.appendSlice(allocator, "error: the counting runtime no longer matches the runtime source\n");
                    return error.ToolFailed;
                },
            };
            break :counted @import("testcount_runtime.zig").source(allocator, counted_text) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.AnchorMissing => {
                    try log.appendSlice(allocator, "error: the testing runtime no longer matches the runtime source\n");
                    return error.ToolFailed;
                },
            };
        },
        .test_counts => @import("testcount_runtime.zig").source(allocator, runtime_source) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.AnchorMissing => {
                try log.appendSlice(allocator, "error: the testing runtime no longer matches the runtime source\n");
                return error.ToolFailed;
            },
        },
    };
}

/// The text `runtime` compiles from, built now when only its digests were known.
fn runtimeText(native: Native, runtime: Runtime) Error![]const u8 {
    if (runtime.source.len != 0) return runtime.source;
    return runtimeSource(native.arena, runtime.variant, native.log);
}

/// The two digests of a runtime that depend on its source alone: the C declaration
/// surface (`runtime_abi.digest`) and the BLAKE3 of the whole text.
const SourceDigests = struct { surface: Digest, source: Digest };

const ordinary_magic = "selka-runtime-digests-v1\n";
const counted_magic = "selka-counted-digests-v1\n";
const test_counts_magic = "selka-testcnt-digests-v1\n";
const digests_directory = "runtime-digests-v1";

fn digestsMagic(variant: Variant) []const u8 {
    return switch (variant) {
        .ordinary => ordinary_magic,
        .counters => counted_magic,
        .test_counts => test_counts_magic,
    };
}

fn computeSourceDigests(allocator: std.mem.Allocator, variant: Variant, log: *std.ArrayList(u8)) Error!SourceDigests {
    const text = try runtimeSource(allocator, variant, log);
    var result: SourceDigests = .{ .surface = @import("runtime_abi.zig").digest(text), .source = undefined };
    fast_blake3.hash(text, &result.source);
    return result;
}

/// A runtime's `SourceDigests`. They are a function of the embedded source, of the
/// counting transformation and of the scanner, which `compiler_identity` covers, so one record
/// per identity and variant in `directory` stands for them: a Debug compiler spends about 90 ms
/// scanning and hashing the 475 KB of C (and as much again building the counting text), and
/// every command that links would pay it. A missing, damaged or foreign record is recomputed
/// and rewritten; a failed write loses only the saving.
fn sourceDigests(allocator: std.mem.Allocator, io: std.Io, directory: []const u8, variant: Variant, log: *std.ArrayList(u8)) Error!SourceDigests {
    const name = switch (variant) {
        .ordinary => build_identity.compiler_identity ++ ".memo",
        .counters => build_identity.compiler_identity ++ "-counted.memo",
        .test_counts => build_identity.compiler_identity ++ "-testcounts.memo",
    };
    const path = try std.fs.path.join(allocator, &.{ directory, digests_directory, name });
    const cwd = std.Io.Dir.cwd();
    var record: [record_length]u8 = undefined;
    if (cwd.openFile(io, path, .{})) |file| {
        defer file.close(io);
        if ((file.readPositionalAll(io, &record, 0) catch 0) == record.len and recordValid(&record, variant)) {
            return .{ .surface = record[magic_length..][0..32].*, .source = record[magic_length + 32 ..][0..32].* };
        }
    } else |_| {}
    const computed = try computeSourceDigests(allocator, variant, log);
    publishRecord(allocator, io, path, &encodeRecord(computed, variant));
    return computed;
}

const magic_length = ordinary_magic.len;
const record_length = magic_length + 64 + 32;
comptime {
    std.debug.assert(counted_magic.len == magic_length);
    std.debug.assert(test_counts_magic.len == magic_length);
}

fn encodeRecord(known: SourceDigests, variant: Variant) [record_length]u8 {
    var record: [record_length]u8 = undefined;
    @memcpy(record[0..magic_length], digestsMagic(variant));
    @memcpy(record[magic_length..][0..32], &known.surface);
    @memcpy(record[magic_length + 32 ..][0..32], &known.source);
    fast_blake3.hash(record[0 .. magic_length + 64], record[magic_length + 64 ..][0..32]);
    return record;
}

fn recordValid(record: *const [record_length]u8, variant: Variant) bool {
    if (!std.mem.eql(u8, record[0..magic_length], digestsMagic(variant))) return false;
    var expected: Digest = undefined;
    fast_blake3.hash(record[0 .. magic_length + 64], &expected);
    return std.mem.eql(u8, &expected, record[magic_length + 64 ..][0..32]);
}

/// Best effort: stage the record beside its place and rename it in, so a reader sees all of it or none.
fn publishRecord(allocator: std.mem.Allocator, io: std.Io, path: []const u8, record: []const u8) void {
    const cwd = std.Io.Dir.cwd();
    if (std.fs.path.dirname(path)) |parent| cwd.createDirPath(io, parent) catch return;
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const staging = std.fmt.allocPrint(allocator, "{s}.{s}.partial", .{ path, std.fmt.bytesToHex(nonce, .lower) }) catch return;
    cwd.writeFile(io, .{ .sub_path = staging, .data = record }) catch return;
    cwd.rename(staging, cwd, path, io) catch removeFile(io, staging);
}

/// A runtime over `source` with the layout and sanitizer options salted in.
fn runtimeWithSource(source: []const u8, abi: Digest, environment: *const std.process.Environ.Map, variant: Variant) Runtime {
    var implementation: Digest = undefined;
    var hash = fast_blake3.Blake3.init(.{});
    hash.update(source);
    for (layoutArguments(environment)) |argument| unit_cache.field(&hash, argument);
    for (sanitizeArguments(environment)) |argument| unit_cache.field(&hash, argument);
    hash.final(&implementation);
    return .{ .source = source, .abi = abi, .implementation = implementation, .variant = variant };
}

/// Bind emitted LLVM, ownership mode and the independent C declaration surface.
/// Runtime bodies still key runtimeObject and therefore the linked program.
pub fn runtimeAbi(source: []const u8, variant: Variant, environment: *const std.process.Environ.Map) Digest {
    return abiFrom(@import("runtime_abi.zig").digest(source), variant, environment);
}

/// `runtimeAbi` from an already computed declaration-surface digest of the source.
fn abiFrom(surface: [32]u8, variant: Variant, environment: *const std.process.Environ.Map) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-runtime-llvm-abi-v1");
    unit_cache.field(&hash, &surface);
    unit_cache.field(&hash, variant.label());
    unit_cache.field(&hash, "zero-rc");
    for (layoutArguments(environment)) |argument| unit_cache.field(&hash, argument);
    for (sanitizeArguments(environment)) |argument| unit_cache.field(&hash, argument);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

// spec: RUNTIME-DIGEST-MEMO-1
test "the ordinary runtime's digests are recorded once per compiler identity and a damaged record is recomputed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const directory = try temporary.dir.realPathFileAlloc(io, ".", a);
    var log: std.ArrayList(u8) = .empty;
    const live = try computeSourceDigests(a, .ordinary, &log);
    // The first call computes the digests and records them, one file per compiler identity.
    const first = try sourceDigests(a, io, directory, .ordinary, &log);
    try std.testing.expectEqualSlices(u8, &live.surface, &first.surface);
    try std.testing.expectEqualSlices(u8, &live.source, &first.source);
    const path = try std.fs.path.join(a, &.{ directory, digests_directory, build_identity.compiler_identity ++ ".memo" });
    try std.testing.expectEqualSlices(u8, &encodeRecord(live, .ordinary), try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1024)));
    // A later call trusts a valid record: a planted one is returned as it stands.
    const planted: SourceDigests = .{ .surface = @splat(0x11), .source = @splat(0x22) };
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = &encodeRecord(planted, .ordinary) });
    const trusted = try sourceDigests(a, io, directory, .ordinary, &log);
    try std.testing.expectEqualSlices(u8, &planted.surface, &trusted.surface);
    try std.testing.expectEqualSlices(u8, &planted.source, &trusted.source);
    // A record with a flipped byte, a truncated one and a foreign one are recomputed and rewritten.
    var damaged = encodeRecord(planted, .ordinary);
    damaged[magic_length + 5] ^= 1;
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = &damaged });
    const repaired = try sourceDigests(a, io, directory, .ordinary, &log);
    try std.testing.expectEqualSlices(u8, &live.surface, &repaired.surface);
    try std.testing.expectEqualSlices(u8, &encodeRecord(live, .ordinary), try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1024)));
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = encodeRecord(live, .ordinary)[0..40] });
    try std.testing.expectEqualSlices(u8, &live.source, &(try sourceDigests(a, io, directory, .ordinary, &log)).source);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = &encodeRecord(planted, .counters) });
    try std.testing.expectEqualSlices(u8, &live.source, &(try sourceDigests(a, io, directory, .ordinary, &log)).source);
    // The default runtime is what the full computation gives, with and without a layout option.
    var environment: std.process.Environ.Map = .init(a);
    const runtime = try runtimeFor(a, io, directory, .ordinary, &environment, &log);
    try std.testing.expectEqualSlices(u8, &runtimeAbi(runtime_source, .ordinary, &environment), &runtime.abi);
    try std.testing.expectEqualSlices(u8, &runtimeWithSource(runtime_source, runtime.abi, &environment, .ordinary).implementation, &runtime.implementation);
    try environment.put(layout_variable, "5");
    const aligned = try runtimeFor(a, io, directory, .ordinary, &environment, &log);
    try std.testing.expectEqualSlices(u8, &runtimeAbi(runtime_source, .ordinary, &environment), &aligned.abi);
    try std.testing.expect(!std.mem.eql(u8, &runtime.implementation, &aligned.implementation));
}

// spec-case: RUNTIME-DIGEST-MEMO-1
test "the counting runtime's digests are recorded apart, its text is built only when an object needs it, and a record of the other variant is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const directory = try temporary.dir.realPathFileAlloc(io, ".", a);
    var log: std.ArrayList(u8) = .empty;
    var environment: std.process.Environ.Map = .init(a);
    const counting_text = try runtimeSource(a, .counters, &log);
    const live = try computeSourceDigests(a, .counters, &log);
    try std.testing.expectEqualSlices(u8, &@import("runtime_abi.zig").digest(counting_text), &live.surface);
    // The runtime a counting build links knows its digests but not its text.
    const runtime = try runtimeFor(a, io, directory, .counters, &environment, &log);
    try std.testing.expect(runtime.variant == .counters and runtime.source.len == 0);
    try std.testing.expectEqualSlices(u8, &runtimeAbi(counting_text, .counters, &environment), &runtime.abi);
    try std.testing.expectEqualSlices(u8, &runtimeWithSource(counting_text, runtime.abi, &environment, .counters).implementation, &runtime.implementation);
    const path = try std.fs.path.join(a, &.{ directory, digests_directory, build_identity.compiler_identity ++ "-counted.memo" });
    try std.testing.expectEqualSlices(u8, &encodeRecord(live, .counters), try std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1024)));
    // A valid record is trusted, and a record of the ordinary runtime does not stand for it.
    const planted: SourceDigests = .{ .surface = @splat(0x33), .source = @splat(0x44) };
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = &encodeRecord(planted, .counters) });
    try std.testing.expectEqualSlices(u8, &planted.source, &(try sourceDigests(a, io, directory, .counters, &log)).source);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = &encodeRecord(planted, .ordinary) });
    try std.testing.expectEqualSlices(u8, &live.source, &(try sourceDigests(a, io, directory, .counters, &log)).source);
    // Under a layout option the options are salted into the digest of the text, which is built then.
    try environment.put(layout_variable, "5");
    const aligned = try runtimeFor(a, io, directory, .counters, &environment, &log);
    try std.testing.expectEqualSlices(u8, counting_text, aligned.source);
    try std.testing.expect(!std.mem.eql(u8, &runtime.implementation, &aligned.implementation));
}

test "the embedded runtime defines at most half as many macro names as the surface scanner tracks" {
    // Past the scanner's table the runtime's ABI is the whole text, and every body edit rebuilds every guest unit.
    // On 17 November 2026 the runtime reached 131 names against a table of 128 and the body-edit test below failed.
    const runtime_abi = @import("runtime_abi.zig");
    try std.testing.expect(runtime_abi.macroNames(runtime_source) * 2 <= runtime_abi.macro_capacity);
}

// spec-case: NEW-CORE-S4-CACHE-1
test "runtime body edits preserve guest unit keys and declaration edits change them" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const before_source = "int helper(void) { return 1; }";
    const after_source = "int helper(void) { return 2; }";
    const abi = runtimeAbi(before_source, .ordinary, &environment);
    const before = runtimeWithSource(before_source, abi, &environment, .ordinary);
    const after = runtimeWithSource(after_source, runtimeAbi(after_source, .ordinary, &environment), &environment, .ordinary);
    const original: unit_cache.Settings = .{ .tool = @splat(1), .cpu = @splat(2), .runtime = before.abi };
    var changed = original;
    changed.runtime = after.abi;
    try std.testing.expectEqual(unit_cache.key(original, "declare i32 @helper()"), unit_cache.key(changed, "declare i32 @helper()"));
    try std.testing.expect(!std.mem.eql(u8, &before.implementation, &after.implementation));
    try std.testing.expect(!std.mem.eql(u8, &unit_cache.key(original, "declare i32 @helper()"), &unit_cache.key(changed, "declare i64 @helper()")));
    try std.testing.expect(!std.mem.eql(u8, &abi, &runtimeAbi("long helper(void) { return 1; }", .ordinary, &environment)));
    try std.testing.expect(!std.mem.eql(u8, &abi, &runtimeAbi(before_source, .counters, &environment)));
    const edited = try std.mem.replaceOwned(u8, std.testing.allocator, runtime_source, "return atomic_load_explicit(&core_pool_started, memory_order_acquire);", "return !atomic_load_explicit(&core_pool_started, memory_order_acquire);");
    defer std.testing.allocator.free(edited);
    try std.testing.expect(!std.mem.eql(u8, runtime_source, edited));
    try std.testing.expectEqual(runtimeAbi(runtime_source, .ordinary, &environment), runtimeAbi(edited, .ordinary, &environment));
    try environment.put(sanitize_variable, "thread");
    try std.testing.expect(!std.mem.eql(u8, &abi, &runtimeAbi(before_source, .ordinary, &environment)));
}

// LAYOUT-SWITCH-1: internal paired-measurement control, also salted into the
// runtime ABI so all unit, runtime and program stores distinguish the options.
const layout_variable = "SELKA_CORE_LAYOUT";

fn layoutArguments(environment: *const std.process.Environ.Map) []const []const u8 {
    const value = environment.get(layout_variable) orelse return &.{};
    if (std.mem.eql(u8, value, "4")) return &.{ "-mllvm", "-align-all-functions=4" };
    if (std.mem.eql(u8, value, "5")) return &.{ "-mllvm", "-align-all-functions=5" };
    if (std.mem.eql(u8, value, "6")) return &.{ "-mllvm", "-align-all-functions=6" };
    return &.{};
}

fn validateLayout(a: std.mem.Allocator, environment: *const std.process.Environ.Map, log: *std.ArrayList(u8)) Error!void {
    if (environment.get(layout_variable) == null or layoutArguments(environment).len != 0) return;
    try log.appendSlice(a, "error: SELKA_CORE_LAYOUT must be 4, 5 or 6\n");
    return error.ToolFailed;
}

// TSAN-BUILD-1: instrument C and every emitted LLVM definition; the same
// option salts the runtime ABI and foreign settings, separating every cache.
const sanitize_variable = "SELKA_CORE_SANITIZE";
const thread_sanitizer = "-fsanitize=thread";

fn sanitizeArguments(environment: *const std.process.Environ.Map) []const []const u8 {
    const value = environment.get(sanitize_variable) orelse return &.{};
    if (std.mem.eql(u8, value, "thread")) return &.{thread_sanitizer};
    if (std.mem.eql(u8, value, "address")) return &.{"-fsanitize=address"};
    return &.{};
}

fn sanitizeLinkArguments(environment: *const std.process.Environ.Map) []const []const u8 {
    return if (tool_identity.addressSanitizer(environment)) &.{platform.address_runtime.path} else &.{};
}

fn validateSanitize(a: std.mem.Allocator, environment: *const std.process.Environ.Map, log: *std.ArrayList(u8)) Error!void {
    if (environment.get(sanitize_variable) == null or sanitizeArguments(environment).len != 0) return;
    try log.appendSlice(a, "error: SELKA_CORE_SANITIZE must be thread or address\n");
    return error.ToolFailed;
}

fn instrumented(a: std.mem.Allocator, environment: *const std.process.Environ.Map, llvm: []const u8) std.mem.Allocator.Error![]const u8 {
    const kind = environment.get(sanitize_variable) orelse return llvm;
    if (std.mem.eql(u8, kind, "address")) return sanitize_llvm.address(a, llvm);
    return if (sanitizeArguments(environment).len != 0) sanitize_llvm.instrument(a, llvm) else llvm;
}

/// Optional LLVM optimization records from a separate compile of the exact units.
/// Failure or a tool that accepts the flags but writes no YAML leaves it unknown.
/// This never replaces a cached object, changes emitted text, or enters the link.
pub const OptimizationRemarks = struct { yaml: ?[]const u8 = null, processes: u32 = 0, compile_ns: u64 = 0, reused: u32 = 0 };

/// Compile missing exact-unit remark queries; hits still validate tool resources.
/// Failed or absent records remain unknown; verify requests compile every unit.
pub fn optimizationRemarks(a: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, request: Request) std.mem.Allocator.Error!OptimizationRemarks {
    if (environ.get(layout_variable) != null and layoutArguments(environ).len == 0) return .{};
    if (environ.get(sanitize_variable) != null and sanitizeArguments(environ).len == 0) return .{};
    const staging = privateDirectory(a, io, request.work, "llvm-remarks") catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{};
    };
    defer removeDirectory(io, staging);
    var environment = environ.clone(a) catch return error.OutOfMemory;
    defer environment.deinit();
    environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ staging, "local" })) catch return error.OutOfMemory;
    const resources: tool_identity.Request = .{ .arena = a, .io = io, .environment = &environment, .executable = request.zig, .cache = request.work };
    const guest = tool_identity.capture(resources) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return .{};
    };
    if (!guest.cacheable) environment.put("ZIG_GLOBAL_CACHE_DIR", try std.fs.path.join(a, &.{ staging, "global" })) catch return error.OutOfMemory;
    var queries = try query_store.Store.init(a, io, request.work);
    defer queries.deinit();
    var counts: Counts = .{};
    var log: std.ArrayList(u8) = .empty;
    const native: Native = .{ .arena = a, .io = io, .environment = &environment, .zig = guest.path, .log = &log, .guard = .{ .resources = resources, .identity = guest }, .counts = &counts, .target = request.family.target };
    var yaml: std.ArrayList(u8) = .empty;
    var result: OptimizationRemarks = .{};
    const context: RemarkContext = .{ .store = &queries, .staging = staging, .family = request.family, .cacheable = guest.cacheable, .verify = request.inspection.verify };
    for (request.units, 0..) |unit, index| {
        const bytes = try remarkUnit(native, context, unit, index, &result) orelse return result;
        try yaml.appendSlice(a, bytes);
        try yaml.append(a, '\n');
    }
    native.guard.check(&log) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return result;
    };
    _ = try queries.flush();
    result.yaml = try yaml.toOwnedSlice(a);
    return result;
}

const RemarkContext = struct { store: *query_store.Store, staging: []const u8, family: Family, cacheable: bool, verify: bool };

fn remarkUnit(native: Native, context: RemarkContext, unit: emit_units.Unit, index: usize, outcome: *OptimizationRemarks) std.mem.Allocator.Error!?[]const u8 {
    const a = native.arena;
    const text = unitText(a, unit) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const actual = try instrumented(a, native.environment, text);
    const key = try remarkKey(a, context.store, native.guard.identity, context.family, native.environment, actual);
    if (context.cacheable and !context.verify) if (try context.store.load(a, key)) |saved| {
        if (saved.len <= 64 << 20) {
            outcome.reused += 1;
            return saved;
        }
    };
    const source = try std.fmt.allocPrint(a, "{s}/{d}.ll", .{ context.staging, index });
    const object = try std.fmt.allocPrint(a, "{s}/{d}.o", .{ context.staging, index });
    const records = try std.fmt.allocPrint(a, "{s}/{d}.opt.yaml", .{ context.staging, index });
    std.Io.Dir.cwd().writeFile(native.io, .{ .sub_path = source, .data = actual }) catch return null;
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(a, try compileArguments(native, try unitFlags(native, context.family.mode, text.len), object, source));
    try args.appendSlice(a, &.{ "-fsave-optimization-record", try std.fmt.allocPrint(a, "-foptimization-record-file={s}", .{records}) });
    const started = std.Io.Timestamp.now(native.io, .awake);
    const ran = run(native, args.items);
    outcome.processes = native.counts.processes;
    outcome.compile_ns += @intCast(@max(0, started.durationTo(std.Io.Timestamp.now(native.io, .awake)).nanoseconds));
    ran catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const bytes = std.Io.Dir.cwd().readFileAlloc(native.io, records, a, .limited(64 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    native.guard.check(native.log) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (context.cacheable and !context.verify) _ = try context.store.save(key, bytes);
    return bytes;
}

fn remarkKey(a: std.mem.Allocator, store: *const query_store.Store, tool: tool_identity.Identity, family: Family, environment: *const std.process.Environ.Map, text: []const u8) std.mem.Allocator.Error!Digest {
    const mode = family.mode;
    var flags: std.ArrayList(u8) = .empty;
    defer flags.deinit(a);
    // Exact semantic arguments; private output/input paths are not compiler inputs.
    for (family.target.cpu_flags) |argument| {
        try flags.appendSlice(a, argument);
        try flags.append(a, 0);
    }
    for (layoutArguments(environment)) |argument| {
        try flags.appendSlice(a, argument);
        try flags.append(a, 0);
    }
    for (sanitizeArguments(environment)) |argument| {
        try flags.appendSlice(a, argument);
        try flags.append(a, 0);
    }
    return store.key("llvm-optimization-record-v1:cc-c-Wno-override-module-fsave-optimization-record", &.{ &tool.digest, &tool.native_target, mode.keyed(), family.target.cc_target, flags.items, text });
}

/// The link flag that keeps Zig from building and linking its UBSan runtime: `zig cc
/// -O0` links it by default (about 10 s to build in a fresh Zig cache), but core units
/// are LLVM text and the runtime is built at -O2, so nothing calls it. A `--link` C
/// source compiled at -O0 may, so those builds keep Zig's default; release links
/// never link it.
fn linkSanitizer(release: bool, foreign: usize) []const u8 {
    return if (release or foreign != 0) "" else "-fno-sanitize=undefined";
}

/// The program store key: the link command's settings and every linked object's
/// bytes, in link order; for a bare image also its link arguments and its linker script's bytes (`script`).
fn programKey(settings: unit_cache.Settings, objects: []const Object, math: bool, sanitizer: []const u8, environment: *const std.process.Environ.Map, script: ?LinkerScript) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-program-v3");
    unit_cache.field(&hash, sanitizer);
    unit_cache.field(&hash, unit_cache.format);
    unit_cache.field(&hash, @tagName(settings.mode));
    unit_cache.field(&hash, settings.mode.keyed());
    unit_cache.field(&hash, settings.target.cc_target);
    for (settings.target.cpu_flags) |flag| unit_cache.field(&hash, flag);
    unit_cache.field(&hash, &settings.cpu);
    unit_cache.field(&hash, &settings.tool);
    for (objects) |object| unit_cache.field(&hash, &object.digest);
    unit_cache.field(&hash, if (math) "-lm" else "");
    linkEnvironmentInto(&hash, environment);
    if (script) |layout| if (bareOf(settings.target)) |runtime_units| {
        unit_cache.field(&hash, "bare-image");
        for (wholeImage(runtime_units, settings.mode)) |flag| unit_cache.field(&hash, flag);
        for (runtime_units.link) |flag| unit_cache.field(&hash, flag);
        unit_cache.field(&hash, &layout.digest);
    };
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// The program key of an image that keeps its symbol table (`Family.symbols`): a link of other arguments, so another key.
fn keptSymbols(key: Digest, symbols: bool) Digest {
    if (!symbols) return key;
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, &key);
    unit_cache.field(&hash, "symbols");
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// A bare image's linker script: its absolute path, for the link that runs in `link_directory`, and the digest of its bytes,
/// for the program key.
const LinkerScript = struct { path: []const u8, digest: Digest };

/// The bare runtime of `target`, or null for a hosted target.
fn bareOf(target: *const target_policy.Target) ?target_policy.Bare {
    return switch (target.system.runtime) {
        .hosted => null,
        .bare => |runtime_units| runtime_units,
    };
}

/// What a bare build adds to every compile and to its link: the target's whole-image flags in a `--release` build, nothing in a plain one.
fn wholeImage(runtime_units: target_policy.Bare, mode: build_mode.Mode) []const []const u8 {
    return if (mode == .release) runtime_units.release else &.{};
}

/// A bare runtime unit's own `--release` arguments, when `whole_image` (`wholeImage`) says the build is one.
fn unitRelease(unit: target_policy.RuntimeUnit, whole_image: []const []const u8) []const []const u8 {
    return if (whole_image.len != 0) unit.release else &.{};
}

/// What the flavours of a bare runtime add to one unit's compile (`RuntimeUnit.cores`, `RuntimeUnit.freestanding`): nothing
/// for a flavour the program does not ask for (`flavour`); for one it does, its flags, and in a `--release` build
/// (`whole_image`, `wholeImage`) its release flags after them.
fn unitFlavour(a: std.mem.Allocator, unit: target_policy.RuntimeUnit, flavour: BareFlavour, whole_image: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    var arguments: std.ArrayList([]const u8) = .empty;
    const release = whole_image.len != 0;
    if (flavour.cores) {
        try arguments.appendSlice(a, unit.cores.flags);
        if (release) try arguments.appendSlice(a, unit.cores.release);
    }
    if (flavour.freestanding) {
        try arguments.appendSlice(a, unit.freestanding.flags);
        if (release) try arguments.appendSlice(a, unit.freestanding.release);
    }
    return arguments.items;
}

/// The runtime function of `registers.start_core1` (`build_registers`), which only the two-core runtime defines.
const start_core1_call = "@" ++ @import("build_registers.zig").runtime_prefix ++ "start_core1(";

/// Which flavours of the bare runtime a build links, each chosen from what the program's units hold (`bareFlavour`).
pub const BareFlavour = struct {
    /// The program starts the second core (`registers.start_core1`): the two-core runtime (`RuntimeUnit.cores`).
    cores: bool = false,
    /// A unit holds a freestanding fault site: the fault decoder (`RuntimeUnit.freestanding`).
    freestanding: bool = false,
};

/// The flavours of the bare runtime a build of `units` links. The second core: a unit names the runtime function of
/// `registers.start_core1` (a built-in, so the call is in the unit's text); such a program links the two-core runtime and
/// its units ask for the calling core's free lists (`perCoreUnits`). The fault decoder: a unit holds a freestanding fault
/// site (`freestanding_emitted.fault_site`, a failed check of a `@freestanding` function), so a program with no
/// freestanding function, which has no such site, links the fault handler it always had. A hosted build, and any program
/// with neither, gets the plain runtime and the emitted text unchanged. The two are independent: a program may have both.
pub fn bareFlavour(a: std.mem.Allocator, target: *const target_policy.Target, units: []const emit_units.Unit) Error!BareFlavour {
    var flavour: BareFlavour = .{};
    if (bareOf(target) == null) return flavour;
    for (units) |unit| {
        const text = try unitText(a, unit);
        if (std.mem.indexOf(u8, text, start_core1_call) != null) flavour.cores = true;
        if (std.mem.indexOf(u8, text, freestanding_emitted.fault_site) != null) flavour.freestanding = true;
        if (flavour.cores and flavour.freestanding) break;
    }
    return flavour;
}

/// Whether a bare build's program starts the second core (`bareFlavour`).
pub fn bareCores(a: std.mem.Allocator, target: *const target_policy.Target, units: []const emit_units.Unit) Error!bool {
    return (try bareFlavour(a, target, units)).cores;
}

/// `units` with each text's free-list accesses asking for the calling core's copy (`emit_llvm.perCoreFreeLists`), for the
/// two-core runtime. The texts are new, so each unit is keyed by its text alone (no receipt of the emitted one).
fn perCoreUnits(a: std.mem.Allocator, units: []const emit_units.Unit) Error![]const emit_units.Unit {
    const rewritten = try a.alloc(emit_units.Unit, units.len);
    for (units, rewritten) |unit, *each| {
        each.* = unit;
        each.llvm = try @import("emit_llvm.zig").perCoreFreeLists(a, try unitText(a, unit));
        each.artifact = null;
        each.identity = null;
    }
    return rewritten;
}

/// The LLVM text `--emit-llvm` writes for a build of `units` whose whole text is `whole`: the text the units compile
/// as, so a program that starts the second core shows its per-core free lists (`bareCores`, `perCoreUnits`).
pub fn emittedText(a: std.mem.Allocator, target: *const target_policy.Target, units: []const emit_units.Unit, whole: []const u8) Error![]const u8 {
    if (!try bareCores(a, target, units)) return whole;
    return @import("emit_llvm.zig").perCoreFreeLists(a, whole);
}

/// Read the linker script `path` names (relative to `here`). The command line refuses a bare build without one
/// (`cli_args.linkerScriptRefusal`); a caller that names none, or a script that cannot be read, fails with one line in `log`.
fn readLinkerScript(a: std.mem.Allocator, io: std.Io, here: []const u8, path: ?[]const u8, log: *std.ArrayList(u8)) Error!LinkerScript {
    const named = path orelse {
        try log.appendSlice(a, "error: a build for a bare target needs a linker script (`--linker-script SCRIPT.ld`)\n");
        return error.ToolFailed;
    };
    const absolute = try std.fs.path.resolve(a, &.{ here, named });
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, absolute, a, .limited(1 << 24)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try log.print(a, "error: cannot read the linker script {s}: {s}\n", .{ named, @errorName(err) });
        return error.ToolFailed;
    };
    var digest: Digest = undefined;
    fast_blake3.hash(bytes, &digest);
    return .{ .path = absolute, .digest = digest };
}

/// The script the compiler wrote from a device's description, `text`, made a file in `staging` for the link and keyed by its bytes, as
/// a named script is.
fn writeLinkerScript(a: std.mem.Allocator, io: std.Io, staging: []const u8, text: []const u8, log: *std.ArrayList(u8)) Error!LinkerScript {
    const absolute = try std.fs.path.join(a, &.{ staging, "device.ld" });
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = absolute, .data = text }) catch |err| {
        try log.print(a, "error: cannot write the linker script of the device's memory: {s}\n", .{@errorName(err)});
        return error.ToolFailed;
    };
    var digest: Digest = undefined;
    fast_blake3.hash(text, &digest);
    return .{ .path = absolute, .digest = digest };
}

test "writeLinkerScript writes the text where the link reads it and keys it by the same digest a named script of those bytes has" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var log: std.ArrayList(u8) = .empty;
    const written = try writeLinkerScript(a, std.testing.io, root, "ENTRY(myl_bare_reset)\n", &log);
    const named = try readLinkerScript(a, std.testing.io, root, "device.ld", &log);
    try std.testing.expectEqual(named.digest, written.digest);
    try std.testing.expectEqualStrings(named.path, written.path);
}

test "readLinkerScript keys a script by its bytes and refuses one that is missing or not named" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "link.ld", .data = "ENTRY(myl_bare_reset)\n" });
    var log: std.ArrayList(u8) = .empty;
    const found = try readLinkerScript(a, std.testing.io, root, "link.ld", &log);
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "link.ld" }), found.path);
    var expected: Digest = undefined;
    fast_blake3.hash("ENTRY(myl_bare_reset)\n", &expected);
    try std.testing.expectEqual(expected, found.digest);
    try std.testing.expectError(error.ToolFailed, readLinkerScript(a, std.testing.io, root, "absent.ld", &log));
    try std.testing.expect(std.mem.indexOf(u8, log.items, "cannot read the linker script absent.ld") != null);
    try std.testing.expectError(error.ToolFailed, readLinkerScript(a, std.testing.io, root, null, &log));
    try std.testing.expect(std.mem.indexOf(u8, log.items, "needs a linker script") != null);
}

/// The text of each unit of a bare runtime and of its headers, embedded in the compiler as the hosted runtime's is: a build
/// never reads the source tree.
const BareText = struct { units: []const []const u8, headers: []const []const u8 };

/// Every file a bare runtime names (`target.Bare`: its units' files and its headers), by its path under `runtime/`,
/// embedded in the compiler as the hosted runtime is. The compiler's identity covers what it embeds, which takes literal paths.
const bare_files = [_]struct { []const u8, []const u8 }{
    .{ "core_rt.c", @embedFile("runtime/core_rt.c") },
    .{ "core_dict.c", @embedFile("runtime/core_dict.c") },
    .{ "core_unicode_data.h", @embedFile("runtime/core_unicode_data.h") },
    .{ "core_text.c", @embedFile("runtime/core_text.c") },
    .{ "core_sort.c", @embedFile("runtime/core_sort.c") },
    .{ "core_number.c", @embedFile("runtime/core_number.c") },
    .{ "core_bytes.c", @embedFile("runtime/core_bytes.c") },
    .{ "core_values.c", @embedFile("runtime/core_values.c") },
    .{ "core_owned_copy.c", @embedFile("runtime/core_owned_copy.c") },
    .{ "core_sha256.c", @embedFile("runtime/core_sha256.c") },
    .{ "bare/core_bare_heap.c", @embedFile("runtime/bare/core_bare_heap.c") },
    .{ "bare/core_bare.c", @embedFile("runtime/bare/core_bare.c") },
    .{ "bare/core_bare_cores.c", @embedFile("runtime/bare/core_bare_cores.c") },
    .{ "bare/core_bare_link.c", @embedFile("runtime/bare/core_bare_link.c") },
    .{ "bare/include/elf.h", @embedFile("runtime/bare/include/elf.h") },
    .{ "bare/include/emmintrin.h", @embedFile("runtime/bare/include/emmintrin.h") },
    .{ "bare/include/errno.h", @embedFile("runtime/bare/include/errno.h") },
    .{ "bare/include/execinfo.h", @embedFile("runtime/bare/include/execinfo.h") },
    .{ "bare/include/fcntl.h", @embedFile("runtime/bare/include/fcntl.h") },
    .{ "bare/include/inttypes.h", @embedFile("runtime/bare/include/inttypes.h") },
    .{ "bare/include/linux/futex.h", @embedFile("runtime/bare/include/linux/futex.h") },
    .{ "bare/include/malloc.h", @embedFile("runtime/bare/include/malloc.h") },
    .{ "bare/include/math.h", @embedFile("runtime/bare/include/math.h") },
    .{ "bare/include/myl_bare_libc.h", @embedFile("runtime/bare/include/myl_bare_libc.h") },
    .{ "bare/include/pthread.h", @embedFile("runtime/bare/include/pthread.h") },
    .{ "bare/include/sched.h", @embedFile("runtime/bare/include/sched.h") },
    .{ "bare/include/signal.h", @embedFile("runtime/bare/include/signal.h") },
    .{ "bare/include/stdio.h", @embedFile("runtime/bare/include/stdio.h") },
    .{ "bare/include/stdlib.h", @embedFile("runtime/bare/include/stdlib.h") },
    .{ "bare/include/string.h", @embedFile("runtime/bare/include/string.h") },
    .{ "bare/include/sys/mman.h", @embedFile("runtime/bare/include/sys/mman.h") },
    .{ "bare/include/sys/stat.h", @embedFile("runtime/bare/include/sys/stat.h") },
    .{ "bare/include/sys/syscall.h", @embedFile("runtime/bare/include/sys/syscall.h") },
    .{ "bare/include/time.h", @embedFile("runtime/bare/include/time.h") },
    .{ "bare/include/unistd.h", @embedFile("runtime/bare/include/unistd.h") },
};

/// The embedded text of the bare runtime file `name` (a path under `runtime/`).
fn bareFile(comptime name: []const u8) []const u8 {
    for (bare_files) |file| if (std.mem.eql(u8, file[0], name)) return file[1];
    @compileError("the bare runtime file " ++ name ++ " is not embedded in driver.zig's bare_files");
}

/// The embedded text of `runtime_units`, built when the compiler is compiled.
fn EmbeddedBare(comptime runtime_units: target_policy.Bare) type {
    return struct {
        const units = texts: {
            @setEvalBranchQuota(100_000);
            var joined: [runtime_units.units.len][]const u8 = undefined;
            for (runtime_units.units, 0..) |unit, index| {
                var together: []const u8 = "";
                for (unit.files) |file| together = together ++ bareFile(file) ++ "\n";
                joined[index] = together;
            }
            break :texts joined;
        };
        const headers = texts: {
            @setEvalBranchQuota(100_000);
            var each: [runtime_units.headers.len][]const u8 = undefined;
            for (runtime_units.headers, 0..) |header, index| each[index] = bareFile(runtime_units.header_root ++ header);
            break :texts each;
        };
        const text: BareText = .{ .units = &units, .headers = &headers };
    };
}

/// The embedded text of `target`'s bare runtime.
fn bareText(target: *const target_policy.Target) BareText {
    inline for (target_policy.all) |known| {
        switch (comptime known.system.runtime) {
            .hosted => {},
            .bare => |runtime_units| if (known == target) return EmbeddedBare(runtime_units).text,
        }
    }
    unreachable;
}

/// Which build of a bare runtime: the build's mode and the flavours it links (`bareFlavour`).
const BareBuild = struct { mode: build_mode.Mode, flavour: BareFlavour };

/// The objects of a bare runtime's units for this build's target, mode and flavour, compiled on first use into
/// `places.shared` under a key of the target, the mode's whole-image flags, every compile argument (the flavour's among
/// them), the toolchain and every byte of the units and headers. The host's runtime object and its key are not touched
/// (`runtimeObject`).
fn bareRuntimeObjects(native: Native, places: Places, runtime_units: target_policy.Bare, build: BareBuild) Error![]const Object {
    const a = native.arena;
    const io = native.io;
    const text = bareText(native.target);
    const extra = wholeImage(runtime_units, build.mode);
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-bare-runtime-v1");
    unit_cache.field(&hash, native.target.name);
    unit_cache.field(&hash, native.target.cc_target);
    for (native.target.cpu_flags) |flag| unit_cache.field(&hash, flag);
    for (runtime_units.compile) |flag| unit_cache.field(&hash, flag);
    for (extra) |flag| unit_cache.field(&hash, flag);
    for (runtime_units.c_flags) |flag| unit_cache.field(&hash, flag);
    for (runtime_units.units, text.units) |unit, source| {
        for (unit.flags) |flag| unit_cache.field(&hash, flag);
        for (unitRelease(unit, extra)) |flag| unit_cache.field(&hash, flag);
        for (try unitFlavour(a, unit, build.flavour, extra)) |flag| unit_cache.field(&hash, flag);
        unit_cache.field(&hash, if (unit.headers) "headers" else "");
        unit_cache.field(&hash, source);
    }
    for (runtime_units.headers, text.headers) |name, header| {
        unit_cache.field(&hash, name);
        unit_cache.field(&hash, header);
    }
    unit_cache.field(&hash, &native.guard.identity.digest);
    var key: Digest = undefined;
    hash.final(&key);
    const objects = try a.alloc(Object, text.units.len);
    for (objects, 0..) |*object, index| {
        var unit_hash = fast_blake3.Blake3.init(.{});
        unit_hash.update(&key);
        unit_hash.update(&[_]u8{@intCast(index)});
        unit_hash.final(&object.digest);
        object.path = try std.fs.path.join(a, &.{ places.shared, try std.fmt.allocPrint(a, "core_bare-{x}-{d}.o", .{ key, index }) });
    }
    var claim = try work_claim.Claim.attempt(a, io, places.shared, key);
    defer if (claim) |*held| held.deinit();
    const cwd = std.Io.Dir.cwd();
    var missing = false;
    for (objects) |object| cwd.access(io, object.path, .{}) catch {
        missing = true;
    };
    if (!missing) return objects;
    // The sources and headers go to this build's private staging directory; only the finished objects reach the store.
    const root = try std.fs.path.join(a, &.{ places.staging, "bare-runtime" });
    const include = try std.fs.path.join(a, &.{ root, "include" });
    for (runtime_units.headers, text.headers) |name, header| {
        const path = try std.fs.path.join(a, &.{ include, name });
        cwd.createDirPath(io, std.fs.path.dirname(path).?) catch return error.WriteFailed;
        cwd.writeFile(io, .{ .sub_path = path, .data = header }) catch return error.WriteFailed;
    }
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const jobs = try a.alloc(unit_cache.Job, text.units.len);
    const partials = try a.alloc([]const u8, text.units.len);
    defer for (partials) |partial| removeFile(io, partial);
    for (runtime_units.units, text.units, objects, jobs, partials, 0..) |unit, source_text, object, *job, *partial, index| {
        const source = try std.fmt.allocPrint(a, "{s}/unit-{d}.c", .{ root, index });
        cwd.writeFile(io, .{ .sub_path = source, .data = source_text }) catch return error.WriteFailed;
        partial.* = try std.fmt.allocPrint(a, "{s}.{x}.partial", .{ object.path, nonce });
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ native.zig, "cc", "-c" });
        try argv.appendSlice(a, runtime_units.compile);
        try argv.appendSlice(a, &.{ "-target", native.target.cc_target });
        try argv.appendSlice(a, native.target.cpu_flags);
        try argv.appendSlice(a, extra);
        try argv.appendSlice(a, runtime_units.c_flags);
        try argv.appendSlice(a, unit.flags);
        try argv.appendSlice(a, unitRelease(unit, extra));
        try argv.appendSlice(a, try unitFlavour(a, unit, build.flavour, extra));
        if (unit.headers) try argv.appendSlice(a, &.{ "-I", include });
        try argv.appendSlice(a, &.{ "-o", partial.*, source });
        job.* = .{ .argv = argv.items, .weight = source_text.len };
    }
    try unit_cache.compileAll(native.resources(), jobs, unit_cache.width(native.environment, jobs.len));
    native.counts.processes += @intCast(jobs.len);
    for (jobs) |job| try native.log.appendSlice(a, job.log.items);
    for (jobs) |job| if (!job.ok) return error.ToolFailed;
    try native.checkTool(native.log);
    for (partials, objects) |partial, object| cwd.rename(partial, cwd, object.path, io) catch return error.WriteFailed;
    return objects;
}

/// The `zig cc` arguments that compile one LLVM unit of the program, whose LLVM text is `text_len` bytes, under `mode` for this build's
/// target: the mode's own (`build_mode.unitFlags`: a lean build's small units get LLVM's IR passes) on a hosted target; a bare target's
/// `compile`, and its whole-image flags in a `--release` build, whatever the size.
fn unitFlags(native: Native, mode: build_mode.Mode, text_len: usize) std.mem.Allocator.Error![]const []const u8 {
    const runtime_units = bareOf(native.target) orelse return build_mode.unitFlags(mode, text_len);
    return std.mem.concat(native.arena, []const u8, &.{ runtime_units.compile, wholeImage(runtime_units, mode) });
}

/// The first symbol of the prebuilt number-text object (`number_runtime.zig`) that a unit of a bare build calls, or null
/// when none does. A bare target has no such object (it is built for the host), so the build refuses a program that needs it.
pub fn bareNumberUse(a: std.mem.Allocator, target: *const target_policy.Target, units: []const emit_units.Unit) Error!?[]const u8 {
    if (bareOf(target) == null) return null;
    for (units) |unit| {
        if (!unit.dependencies.number) continue;
        if (number_runtime.firstNeeded(try unitText(a, unit))) |name| return name;
    }
    return null;
}

/// The `registers` function only a simulated bank has (`build_registers.simulatedCall`) that a unit of a bare build calls,
/// as `registers.NAME`, or null when none does: the bare runtime has no simulated bank, and a device's `main` receives its
/// registers instead.
pub fn bareSimulatedRegisters(a: std.mem.Allocator, target: *const target_policy.Target, units: []const emit_units.Unit) Error!?[]const u8 {
    if (bareOf(target) == null) return null;
    for (units) |unit| if (@import("build_registers.zig").simulatedCall(try unitText(a, unit))) |name| return name;
    return null;
}

/// The `registers` function only a device has (`build_registers.deviceCall`: `start_core1`) that a unit of a hosted build
/// calls, as `registers.NAME`, or null when none does: the hosted runtime has no second core to start.
pub fn hostedDeviceRegisters(a: std.mem.Allocator, target: *const target_policy.Target, units: []const emit_units.Unit) Error!?[]const u8 {
    if (bareOf(target) != null) return null;
    for (units) |unit| if (@import("build_registers.zig").deviceCall(try unitText(a, unit))) |name| return name;
    return null;
}

fn linkEnvironmentInto(hash: *fast_blake3.Blake3, environment: *const std.process.Environ.Map) void {
    // These linker controls can affect output bytes without changing an object.
    // Tool injection is already refused by the captured tool's cacheability guard.
    for ([_][]const u8{ "SOURCE_DATE_EPOCH", "ZERO_AR_DATE" }) |name| {
        unit_cache.field(hash, name);
        unit_cache.field(hash, if (environment.get(name) != null) "present" else "absent");
        unit_cache.field(hash, environment.get(name) orelse "");
    }
}

// spec-case: COMPILER-SHARED-CACHE-1
test "local programs cannot relabel a warm executable after a linker environment change" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const store: unit_cache.Store = .{ .directory = root };
    const settings: unit_cache.Settings = .{ .tool = @splat(1), .cpu = @splat(2), .runtime = @splat(3) };
    const objects = [_]Object{.{ .path = "unit.o", .digest = @splat(4) }};
    const first = programKey(settings, &objects, false, "", &environment, null);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "staged", .data = "linked-program" });
    _ = try store.publish(a, std.testing.io, first, "", try std.fs.path.join(a, &.{ root, "staged" }));
    try std.testing.expect((try store.lookup(a, std.testing.io, first, "")) != null);
    try environment.put("SOURCE_DATE_EPOCH", "1");
    const changed = programKey(settings, &objects, false, "", &environment, null);
    try std.testing.expect(!std.mem.eql(u8, &first, &changed));
    try std.testing.expect((try store.lookup(a, std.testing.io, changed, "")) == null);
    try environment.put("ZERO_AR_DATE", "1");
    try std.testing.expect(!std.mem.eql(u8, &changed, &programKey(settings, &objects, false, "", &environment, null)));
    _ = environment.swapRemove("SOURCE_DATE_EPOCH");
    _ = environment.swapRemove("ZERO_AR_DATE");
    try std.testing.expect((try store.lookup(a, std.testing.io, programKey(settings, &objects, false, "", &environment, null), "")) != null);
}

/// Put a finished program at the requested output path (`program_store.place`): a second name for the stored
/// program's file where the file system allows one, else a copy. `sources` are the names of the program's bytes,
/// the stored one first. The time and the way it was placed go to `native.counts.link`.
fn placeOutput(native: Native, sources: []const []const u8, output: []const u8) Error!void {
    const start = stage_metrics.now(native.io);
    const placed = program_store.place(native.io, sources, output, program_store.hardLink) catch |err| {
        try native.log.print(native.arena, "error: cannot write {s}: {s}\n", .{ output, @errorName(err) });
        return error.WriteFailed;
    };
    native.counts.link.output_ns += stage_metrics.elapsed(native.io, start);
    native.counts.link.placement = placed;
}

/// One unit this build compiles: a store miss, or a hit `--verify-cache` checks.
const Pending = struct { unit: emit_units.Unit, key: Digest, object: []const u8, slot: usize, served: ?unit_cache.Found, timing_slot: ?usize };

const UnitInput = struct { unit: emit_units.Unit, key: Digest };

fn digestLess(_: void, left: Digest, right: Digest) bool {
    return std.mem.order(u8, &left, &right) == .lt;
}

/// The LLVM text of `unit`: its own, or the stored artifact's a reused unit names.
pub fn unitText(a: std.mem.Allocator, unit: emit_units.Unit) Error![]const u8 {
    if (unit.llvm.len != 0) return unit.llvm;
    const handle = unit.artifact orelse return unit.llvm;
    const artifact = try native_receipt.materialize(a, handle);
    return artifact.text;
}

fn unitInput(a: std.mem.Allocator, settings: unit_cache.Settings, cacheable: bool, given: emit_units.Unit) Error!UnitInput {
    var unit = given;
    if (cacheable and unit.llvm.len == 0) if (unit.artifact) |handle| {
        if (try native_receipt.lookup(a, handle, settings)) |key| return .{ .unit = unit, .key = key };
    };
    unit.llvm = try unitText(a, unit);
    const key = unit_cache.key(settings, unit.llvm);
    if (cacheable) if (unit.artifact) |handle| try native_receipt.remember(handle, settings, key);
    return .{ .unit = unit, .key = key };
}

/// Claim each of `keys`, which are sorted so that builds take them in one order, skipping a repeat of the key before it. Once a
/// namespace is held by a collection past `native_cache_work.lease_wait_ms` the rest are not claimed and not waited for: the build
/// works them unclaimed, so a hundred units cost one wait and not a hundred.
fn claimAll(a: std.mem.Allocator, io: std.Io, directory: []const u8, keys: []const Digest, claims: *std.ArrayList(work_claim.Claim)) Error!void {
    try claims.ensureTotalCapacity(a, keys.len);
    for (keys, 0..) |key, index| {
        if (index != 0 and std.mem.eql(u8, &key, &keys[index - 1])) continue;
        const claim = (try work_claim.Claim.acquire(a, io, directory, key)) orelse return;
        claims.appendAssumeCapacity(claim);
    }
}

/// Release and forget every claim in `claims`.
fn releaseClaims(claims: *std.ArrayList(work_claim.Claim)) void {
    for (claims.items) |*claim| claim.deinit();
    claims.clearRetainingCapacity();
}

test "a build waits once for a store namespace a collection holds and works the rest of its units unclaimed" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const root = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    const keys = [_]Digest{ @splat(1), @splat(2), @splat(2), @splat(3), @splat(4) };
    var claims: std.ArrayList(work_claim.Claim) = .empty;
    defer claims.deinit(std.testing.allocator);
    try claimAll(std.testing.allocator, io, root, &keys, &claims);
    try std.testing.expectEqual(@as(usize, 4), claims.items.len);
    releaseClaims(&claims);
    const sweep = (try language.native_cache_retention.Context.init(std.testing.allocator, io, root, .compiler).tryExclusive()).?;
    defer sweep.close(io);
    const started = std.Io.Timestamp.now(io, .awake).nanoseconds;
    try claimAll(std.testing.allocator, io, root, &keys, &claims);
    const waited_ms = @divTrunc(std.Io.Timestamp.now(io, .awake).nanoseconds - started, std.time.ns_per_ms);
    try std.testing.expectEqual(@as(usize, 0), claims.items.len);
    try std.testing.expect(waited_ms < 2 * work_claim.lease_wait_ms);
}

/// Serve each distinct unit from the store, compile the rest in parallel, and
/// append every object in unit order.
fn unitObjects(native: Native, places: Places, settings: unit_cache.Settings, request: Request, objects: *std.ArrayList(Object)) Error![]const UnitTiming {
    const a = native.arena;
    const store: unit_cache.Store = .{ .directory = try std.fs.path.join(a, &.{ places.shared, "units-v1" }) };
    var seen: std.AutoHashMapUnmanaged(Digest, void) = .empty;
    var pending: std.ArrayList(Pending) = .empty;
    var jobs: std.ArrayList(unit_cache.Job) = .empty;
    var details: std.ArrayList(UnitTiming) = .empty;
    // The recipe's `zig clang` compile (`tool_recipe.zig`), asked for once and only when a unit has to be compiled; each job of it keeps
    // the `zig cc -c` command it falls back to if the recipe's compile fails.
    var recipe: RecipeJobs = .{};
    const inputs = try a.alloc(UnitInput, request.units.len);
    defer a.free(inputs);
    for (request.units, inputs) |given, *input| input.* = try unitInput(a, settings, places.cacheable, given);
    var initial: std.AutoHashMapUnmanaged(Digest, ?unit_cache.Found) = .empty;
    defer initial.deinit(a);
    var missing: std.ArrayList(Digest) = .empty;
    defer missing.deinit(a);
    for (inputs) |input| {
        const entry = try initial.getOrPut(a, input.key);
        if (entry.found_existing) continue;
        entry.value_ptr.* = if (places.cacheable) try store.lookup(a, native.io, input.key, ".o") else null;
        if (entry.value_ptr.* == null) try missing.append(a, input.key);
    }
    var claims: std.ArrayList(work_claim.Claim) = .empty;
    defer {
        for (claims.items) |*claim| claim.deinit();
        claims.deinit(a);
    }
    if (places.cacheable and !request.inspection.verify) {
        std.mem.sort(Digest, missing.items, {}, digestLess);
        try claimAll(a, native.io, store.directory, missing.items, &claims);
    }
    for (inputs) |input| {
        var unit = input.unit;
        const key = input.key;
        // Equal text is one object: linking it twice would define its symbols twice.
        if ((try seen.getOrPut(a, key)).found_existing) continue;
        native.counts.units += 1;
        const before_wait = initial.get(key).?;
        const recheck = before_wait == null and places.cacheable and !request.inspection.verify;
        const served = if (recheck) try store.lookup(a, native.io, key, ".o") else before_wait;
        if (served != null) native.counts.reused += 1;
        const timing_slot = try recordUnitTiming(a, &details, unit, key, .{ .enabled = request.inspection.measure_units, .reused = served != null });
        try objects.append(a, if (served) |hit| .{ .path = hit.path, .digest = hit.digest } else .{ .path = "", .digest = key });
        if (served != null and !request.inspection.verify) continue;
        unit.llvm = try unitText(a, unit);
        // The exact text key remains authoritative on every compile or verify.
        if (!std.mem.eql(u8, &key, &unit_cache.key(settings, unit.llvm))) return cache_miss.at(@src());
        const stem = try std.fs.path.join(a, &.{ places.staging, &std.fmt.bytesToHex(key, .lower) });
        // A miss compiles beside its store entry, so publishing is a rename even
        // when the store is on another file system than the work directory.
        const object = if (served != null) try std.fmt.allocPrint(a, "{s}.verify.o", .{stem}) else if (places.cacheable) try store.partial(a, native.io, key, ".o") else try std.fmt.allocPrint(a, "{s}.o", .{stem});
        const source = try std.fmt.allocPrint(a, "{s}.ll", .{stem});
        // Only units that compile are written out; a hit never rewrites its text.
        std.Io.Dir.cwd().writeFile(native.io, .{ .sub_path = source, .data = try instrumented(a, native.environment, unit.llvm) }) catch return error.WriteFailed;
        try pending.append(a, .{ .unit = unit, .key = key, .object = object, .slot = objects.items.len - 1, .served = served, .timing_slot = timing_slot });
        const release = request.family.mode == .release and request.inspection.check_vectorize;
        const arguments = try jobArguments(native, try unitFlags(native, request.family.mode, unit.llvm.len), release, unit.llvm, object, source);
        const argv = try recipe.argumentsFor(native, request.family.mode, unit.llvm.len, arguments, .{ .source = source, .object = object });
        try jobs.append(a, .{ .argv = argv, .weight = unit.llvm.len, .measure = request.inspection.measure_units });
    }
    // Cached partials are removed after publication or failure. Uncached
    // objects remain in staging until the caller links and removes that tree.
    defer discardCachedPartials(native, places.cacheable, pending.items);
    try unit_cache.compileAll(native.resources(), jobs.items, unit_cache.width(native.environment, jobs.items.len));
    native.counts.processes += @intCast(jobs.items.len);
    try retryRecipeFailures(native, jobs.items, recipe.fallbacks.items);
    finishUnitTimings(details.items, pending.items, jobs.items);
    for (jobs.items) |job| try native.log.appendSlice(a, try vectorize_remarks.withoutRemarks(a, job.log.items));
    for (jobs.items) |job| if (!job.ok) return error.ToolFailed;
    if (request.inspection.check_vectorize) try checkVectorized(native, pending.items, jobs.items);
    if (jobs.items.len != 0) try native.checkTool(native.log);
    for (recipe.found) |found| try storeLearned(native, found.learned);
    for (pending.items) |item| {
        if (item.served) |hit| {
            try verifyServed(native, item, hit);
            continue;
        }
        native.counts.compiled += 1;
        const stored = if (places.cacheable) try store.publish(a, native.io, item.key, ".o", item.object) else try unit_cache.found(a, native.io, item.object);
        objects.items[item.slot] = .{ .path = stored.path, .digest = stored.digest };
    }
    return details.items;
}

/// The compile recipe of one `unitObjects` and the `zig cc` command each job that uses it falls back to, asked for when the first unit is
/// compiled (a release build's unit compiles as `zig cc` with its remark flags and does not use one).
const RecipeJobs = struct {
    // One recipe for each of the two lists a lean build's units may get: LLVM's passes off (index 0), on (1, `build_mode.passesOn`).
    found: [2]CompileRecipe = @splat(.{}),
    asked: [2]bool = @splat(false),
    fallbacks: std.ArrayList(?[]const []const u8) = .empty,

    const Files = struct { source: []const u8, object: []const u8 };

    /// The command that compiles a unit whose LLVM text is `text_len` bytes: the recipe's `zig clang` when there is one, else `arguments`,
    /// the `zig cc` command.
    fn argumentsFor(self: *RecipeJobs, native: Native, mode: build_mode.Mode, text_len: usize, arguments: []const []const u8, files: Files) Error![]const []const u8 {
        const slot = @intFromBool(build_mode.passesOn(mode, text_len) and bareOf(native.target) == null);
        if (!self.asked[slot] and mode != .release) {
            self.asked[slot] = true;
            self.found[slot] = try compileRecipe(native, try unitFlags(native, mode, text_len));
        }
        const tokens = self.found[slot].tokens orelse {
            try self.fallbacks.append(native.arena, null);
            return arguments;
        };
        try self.fallbacks.append(native.arena, arguments);
        return tool_recipe.compileArguments(native.arena, native.zig, tokens, files.source, files.object);
    }
};

/// What `compileRecipe` found: the recipe to compile with (null: use `zig cc`), and the recipe it learned, for `storeLearned`.
const CompileRecipe = struct { tokens: ?[]const []const u8 = null, learned: ?Learned = null };

/// The compile recipe for the `zig cc` argument list `flags`: the stored one, else learned from `zig cc` (`tool_recipe.deriveCompile`); no
/// tokens when the build has no recipes or Zig's command line is no recipe.
fn compileRecipe(native: Native, flags: []const []const u8) Error!CompileRecipe {
    const recipes = native.recipes orelse return .{};
    const a = native.arena;
    // The driver's arguments between `zig cc` and the trailing `-o object source`.
    const full = try compileArguments(native, flags, "object.o", "unit.ll");
    const driver_arguments = full[2 .. full.len - 3];
    const digest = tool_recipe.key(.compile, recipes.identity, driver_arguments);
    if (try tool_recipe.load(a, native.io, recipes.directory, .compile, digest)) |tokens| return .{ .tokens = if (tokens.len == 0) null else tokens };
    native.counts.link.recipes.learned += 1;
    const probe: tool_recipe.Probe = .{ .arena = a, .io = native.io, .environment = native.environment, .zig = native.zig, .staging = recipes.staging };
    const derived = try tool_recipe.deriveCompile(probe, driver_arguments);
    if (!derived.ran) return .{};
    return .{ .tokens = derived.tokens, .learned = .{ .kind = .compile, .digest = digest, .tokens = derived.tokens orelse &.{} } };
}

/// Count the units the recipe's compile built, and compile again as `zig cc -c` each that it failed on, so a failure reaches the log
/// as Zig's driver reports it. `fallbacks[i]` is the `zig cc` command of job `i` when the job ran a recipe, else null.
fn retryRecipeFailures(native: Native, jobs: []unit_cache.Job, fallbacks: []const ?[]const []const u8) Error!void {
    const a = native.arena;
    var retry: std.ArrayList(unit_cache.Job) = .empty;
    var which: std.ArrayList(usize) = .empty;
    for (jobs, fallbacks, 0..) |job, fallback, at| {
        const argv = fallback orelse continue;
        if (job.ok) {
            native.counts.link.recipes.units += 1;
            continue;
        }
        try retry.append(a, .{ .argv = argv, .weight = job.weight, .measure = job.measure });
        try which.append(a, at);
    }
    if (retry.items.len == 0) return;
    try unit_cache.compileAll(native.resources(), retry.items, unit_cache.width(native.environment, retry.items.len));
    native.counts.processes += @intCast(retry.items.len);
    for (retry.items, which.items) |done, at| {
        jobs[at].ok = done.ok;
        jobs[at].log = done.log;
        jobs[at].compile_ns = done.compile_ns;
    }
}

fn recordUnitTiming(a: std.mem.Allocator, details: *std.ArrayList(UnitTiming), unit: emit_units.Unit, key: Digest, observation: struct { enabled: bool, reused: bool }) std.mem.Allocator.Error!?usize {
    if (!observation.enabled) return null;
    const slot = details.items.len;
    try details.append(a, .{
        .name = unit.name,
        .source_path = unit.source_path,
        .kind = unit.kind,
        .key = try a.dupe(u8, &std.fmt.bytesToHex(key, .lower)),
        .action = if (observation.reused) .reused else .compiled,
    });
    return slot;
}

fn finishUnitTimings(details: []UnitTiming, pending: []const Pending, jobs: []const unit_cache.Job) void {
    for (pending, jobs) |item, job| if (item.timing_slot) |slot| {
        details[slot].compile_ns = job.compile_ns;
        details[slot].action = if (!job.ok) .failed else if (item.served != null) .verified else .compiled;
    };
}

fn discardCachedPartials(native: Native, cacheable: bool, pending: []const Pending) void {
    if (!cacheable) return;
    for (pending) |item| removeFile(native.io, item.object);
}

/// `--verify-cache`: a served object must equal a fresh compile of its text.
fn verifyServed(native: Native, item: Pending, served: unit_cache.Found) Error!void {
    const fresh = try unit_cache.found(native.arena, native.io, item.object);
    if (!std.mem.eql(u8, &fresh.digest, &served.digest)) {
        try native.log.print(native.arena, "error: --verify-cache: unit {s} ({s}) compiles to different bytes than its cached object {s}\n", .{ item.unit.name, item.unit.source_path, served.path });
        return error.ToolFailed;
    }
    native.counts.verified += 1;
}

/// The compile arguments of one unit: a release unit that marks loops also reports the vectorizer's remarks.
fn jobArguments(native: Native, flags: []const []const u8, release: bool, llvm: []const u8, object: []const u8, source: []const u8) ![]const []const u8 {
    const argv = try compileArguments(native, flags, object, source);
    if (release and vectorize_remarks.marksLoops(llvm)) return withRemarks(native.arena, argv);
    return argv;
}

/// Fail the build when a freshly compiled unit's marked loop was analysed and not vectorized.
fn checkVectorized(native: Native, pending: []const Pending, jobs: []const unit_cache.Job) Error!void {
    for (pending, 0..) |item, index| {
        if (item.served != null) continue;
        try requireVectorized(native.arena, native.log, item.unit.llvm, jobs[index].log.items);
    }
}

/// Append the vectorizer's report for one unit to `log`, and fail with `VectorizeFailed` when it names a loop.
fn requireVectorized(a: std.mem.Allocator, log: *std.ArrayList(u8), llvm: []const u8, job_log: []const u8) Error!void {
    const report = try vectorize_remarks.failures(a, llvm, job_log);
    if (report.len == 0) return;
    try log.appendSlice(a, report);
    return error.VectorizeFailed;
}

test "a marked loop LLVM could not vectorize fails the build with VectorizeFailed, and its reason is logged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var log: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.VectorizeFailed, requireVectorized(arena.allocator(), &log, "  ; vectorize src.selka:1:1\n", "remark: src.selka:1:1: loop not vectorized: call instruction cannot be vectorized [-Rpass-analysis]\n"));
    try std.testing.expect(std.mem.indexOf(u8, log.items, "E_VECTORIZE_FAILED") != null);
}

// spec: VECTORIZE-REMARKS-ARGV-1
test "a release unit that marks loops compiles with the remark flags and a per-process define" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const argv = try withRemarks(arena.allocator(), &.{ "zig", "cc", "-c", "-O3", "in.ll" });
    const joined = try std.mem.join(arena.allocator(), " ", argv);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-Rpass=loop-vectorize -Rpass-missed=loop-vectorize -Rpass-analysis=loop-vectorize") != null);
    try std.testing.expect(std.mem.indexOf(u8, joined, "-DMYL_VECTORIZE_RUN=") != null);
}

/// `argv` with the vectorizer's remark flags appended, so a release compile of a `@vectorize` unit reports its loops.
/// The per-process define keeps zig's compile cache from replaying the object without its remarks.
fn withRemarks(a: std.mem.Allocator, argv: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    var extended: std.ArrayList([]const u8) = .empty;
    try extended.appendSlice(a, argv);
    try extended.appendSlice(a, &vectorize_remarks.remark_flags);
    try extended.append(a, try std.fmt.allocPrint(a, "-DMYL_VECTORIZE_RUN={d}", .{std.os.linux.getpid()}));
    return extended.items;
}

fn compileArguments(native: Native, flags: []const []const u8, object: []const u8, source: []const u8) std.mem.Allocator.Error![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(native.arena, &.{ native.zig, "cc", "-c" });
    try argv.appendSlice(native.arena, flags);
    try argv.appendSlice(native.arena, &.{ "-target", native.target.cc_target });
    try argv.appendSlice(native.arena, native.target.cpu_flags);
    try argv.appendSlice(native.arena, layoutArguments(native.environment));
    try argv.appendSlice(native.arena, sanitizeArguments(native.environment));
    try argv.appendSlice(native.arena, &.{ "-Wno-override-module", "-o", object, source });
    return argv.items;
}

/// One `--link` source this build compiles, and where its depfile goes.
const Foreign = struct {
    manifest: []const u8,
    manifest_key: Digest,
    object: []const u8,
    depfile: []const u8,
    slot: usize,
    link: usize,
    /// The preprocessed-text key of a source the depfile check cannot cache (`preprocessedKey`), or null.
    preprocessed: ?Digest = null,
};

/// Serve or compile every `--link` C source. A source is served only while its
/// bytes and those of every header its last depfile listed are unchanged.
/// Returns the inputs a later build must find unchanged, or null when a
/// file changed while it compiled (nothing is then cached).
fn foreignObjects(native: Native, places: Places, settings: unit_cache.Settings, request: Request, objects: *std.ArrayList(Object)) Error!?[]const inputs_handle.Input {
    const links = request.links;
    const verify = request.inspection.verify;
    if (links.len == 0) return &.{};
    const include = try includeFlags(native.arena, request.family.include);
    const a = native.arena;
    const cwd = std.Io.Dir.cwd();
    const store: unit_cache.Store = .{ .directory = try std.fs.path.join(a, &.{ places.local, "foreign-v1" }) };
    cwd.createDirPath(native.io, store.directory) catch return error.WriteFailed;
    var dependencies: std.ArrayList(inputs_handle.Input) = .empty;
    var compiles: std.ArrayList(Foreign) = .empty;
    var stable_text = true;
    var jobs: std.ArrayList(unit_cache.Job) = .empty;
    // A file whose status changes after this marker exists may differ from the
    // bytes its compile read, so its digest is not trusted (see `pinned`).
    const marker = try std.fs.path.join(a, &.{ places.staging, "foreign-marker" });
    cwd.writeFile(native.io, .{ .sub_path = marker, .data = "" }) catch return error.WriteFailed;
    const started = cwd.statFile(native.io, marker, .{}) catch return error.WriteFailed;
    const manifest_keys = try a.alloc(Digest, links.len);
    defer a.free(manifest_keys);
    for (links, manifest_keys) |source, *key| key.* = try foreignKey(native, settings, source, include);
    // What the C compiler said about each source, in link order: a served object repeats the record of the
    // compile that made it, so a warm build prints what a clean one does.
    const logs = try a.alloc([]const u8, links.len);
    defer a.free(logs);
    @memset(logs, "");
    var claims: std.ArrayList(work_claim.Claim) = .empty;
    defer {
        for (claims.items) |*claim| claim.deinit();
        claims.deinit(a);
    }
    if (places.cacheable) {
        const ordered = try a.dupe(Digest, manifest_keys);
        defer a.free(ordered);
        std.mem.sort(Digest, ordered, {}, digestLess);
        try claimAll(a, native.io, store.directory, ordered, &claims);
    }
    for (links, 0..) |source, index| {
        const manifest_key = manifest_keys[index];
        const manifest = try store.path(a, manifest_key, ".deps");
        // `--verify-cache` compiles a served source again and requires the object it stored (`publishForeign`).
        if (places.cacheable and !verify) if (try servedForeign(native, store, manifest_key, manifest)) |served| {
            try objects.append(a, served.object);
            try dependencies.appendSlice(a, served.dependencies);
            logs[index] = served.log;
            continue;
        };
        // A source the depfile check cannot cache (it names a header through a macro) is keyed by its preprocessed text.
        const preprocessed = if (places.cacheable and try takesPreprocessed(native, store, manifest_key, source))
            try preprocessedKey(native, settings, .{ .source = source, .staging = places.staging, .index = index, .manifest_key = manifest_key, .include = include })
        else
            null;
        // Its build does not replay: the next build preprocesses again, which is what keeps the key honest.
        if (preprocessed != null) stable_text = false;
        if (preprocessed) |key| if (!verify) if (try servedPreprocessed(native, store, key)) |served| {
            try objects.append(a, served.object);
            logs[index] = served.log;
            continue;
        };
        try objects.append(a, .{ .path = "", .digest = manifest_key });
        const stem = try std.fmt.allocPrint(a, "{s}/foreign-{d}", .{ places.staging, index });
        const object = try std.fmt.allocPrint(a, "{s}.o", .{stem});
        const depfile = try std.fmt.allocPrint(a, "{s}.d", .{stem});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ native.zig, "cc", "-c", settings.mode.level(), "-target", native.target.cc_target });
        try argv.appendSlice(a, native.target.cpu_flags);
        try argv.appendSlice(a, sanitizeArguments(native.environment));
        try argv.appendSlice(a, include);
        // `-MD` lists the system headers too: a `--link` source may include any header of the library,
        // so each one it opened is an input of its object, with its bytes.
        try argv.appendSlice(a, &.{ "-MD", "-MF", depfile, "-o", object, source });
        try jobs.append(a, .{ .argv = argv.items, .weight = links.len - index });
        try compiles.append(a, .{ .manifest = manifest, .manifest_key = manifest_key, .object = object, .depfile = depfile, .slot = objects.items.len - 1, .link = index, .preprocessed = preprocessed });
    }
    try unit_cache.compileAll(native.resources(), jobs.items, unit_cache.width(native.environment, jobs.items.len));
    native.counts.processes += @intCast(jobs.items.len);
    for (compiles.items, jobs.items) |compiled, job| logs[compiled.link] = job.log.items;
    for (logs) |log| try native.log.appendSlice(a, log);
    for (jobs.items) |job| if (!job.ok) return error.ToolFailed;
    if (jobs.items.len != 0) try native.checkTool(native.log);
    var stable = stable_text;
    for (compiles.items) |compiled| {
        const fresh = try unit_cache.found(a, native.io, compiled.object);
        objects.items[compiled.slot] = .{ .path = fresh.path, .digest = fresh.digest };
        // Everything this source's compile read goes through one handle: the files its depfile
        // listed, and the quoted names it asked for beside them, present or not.
        var handle = inputs_handle.Handle.init(a, native.io, native.environment);
        const listed = try pinned(native, &handle, try readDepfile(native, compiled.depfile), started.ctime.nanoseconds) orelse {
            stable = false;
            continue;
        };
        if (compiled.preprocessed) |key| {
            // Nothing the compile read changed since the marker, and the text preprocessed after the compile is the text
            // its key was made from, so the object is the object of that text: a `__TIME__` that ticked or a file that
            // changed while it compiled publishes nothing.
            const after = try preprocessedKey(native, settings, .{ .source = links[compiled.link], .staging = places.staging, .index = compiled.link, .manifest_key = compiled.manifest_key, .include = include });
            if (after == null or !std.mem.eql(u8, &after.?, &key)) {
                stable = false;
                continue;
            }
            try atomicWrite(native, try store.path(a, key, ".log"), logs[compiled.link]);
            const stored = try publishForeign(native, store, .{ .key = key, .object = compiled.object, .verify = verify });
            objects.items[compiled.slot] = .{ .path = stored.path, .digest = stored.digest };
            continue;
        }
        switch (try lookedFor(native, &handle, listed)) {
            .readable => {},
            .macro => {
                // Mark the source so later builds take the preprocessed path (`takesPreprocessed`).
                if (places.cacheable) try atomicWrite(native, try store.path(a, compiled.manifest_key, preprocessed_marker), "");
                stable = false;
                continue;
            },
            .changed => {
                stable = false;
                continue;
            },
        }
        const recorded = handle.inputs();
        try dependencies.appendSlice(a, recorded);
        if (!places.cacheable) continue;
        const text = try manifestText(a, recorded);
        const stored = try publishForeign(native, store, .{ .key = objectKey(compiled.manifest_key, text), .object = compiled.object, .verify = verify });
        objects.items[compiled.slot] = .{ .path = stored.path, .digest = stored.digest };
        // The record of what the compiler said goes first: the manifest is what makes an entry servable.
        try atomicWrite(native, try logPath(a, compiled.manifest), logs[compiled.link]);
        try atomicWrite(native, compiled.manifest, text);
    }
    return if (stable) dependencies.items else null;
}

/// The marker beside a manifest slot whose source named a header through a macro in a header it includes, so later
/// builds key it by its preprocessed text (`takesPreprocessed`).
const preprocessed_marker = ".pp";

/// Whether a `--link` source takes the preprocessed path: its own text names a header through a macro (or across lines),
/// or an earlier build found such a directive in a header it includes and left the marker. These are exactly the sources
/// the depfile check refuses; every other source keeps its key, its depfile check and its cost.
fn takesPreprocessed(native: Native, store: unit_cache.Store, manifest_key: Digest, source: []const u8) Error!bool {
    const a = native.arena;
    const cwd = std.Io.Dir.cwd();
    if (cwd.access(native.io, try store.path(a, manifest_key, preprocessed_marker), .{})) |_| return true else |_| {}
    const text = cwd.readFileAlloc(native.io, source, a, .limited(256 << 20)) catch return false;
    const names = try c_includes.quotedNames(a, text);
    return names == null;
}

/// One source to preprocess for its key.
const Preprocess = struct { source: []const u8, staging: []const u8, index: usize, manifest_key: Digest, include: []const []const u8 = &.{} };

/// The store key of a source the depfile check cannot cache: its manifest slot (which already digests the source's
/// path, spelling, bytes, working directory, the build mode and its optimization level, the target, the CPU, the
/// sanitizer and the toolchain) and the digest of its preprocessed text, made with the same preprocessing flags as its
/// compile. The text holds every header that was included, with line markers naming each by absolute path, every
/// `__has_include` and `#include_next` decision, and every macro, `__DATE__` and `__TIME__` included, so a header that
/// appears and shadows another, a moved checkout or a new date changes the key. Null when the text keeps data the
/// preprocessor does not expand (`#embed`, an `.incbin` directive): such a source stays uncached, as before.
fn preprocessedKey(native: Native, settings: unit_cache.Settings, job: Preprocess) Error!?Digest {
    const a = native.arena;
    const output = try std.fmt.allocPrint(a, "{s}/foreign-{d}.i", .{ job.staging, job.index });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ native.zig, "cc", "-E", settings.mode.level(), "-target", native.target.cc_target });
    try argv.appendSlice(a, native.target.cpu_flags);
    try argv.appendSlice(a, sanitizeArguments(native.environment));
    try argv.appendSlice(a, job.include);
    try argv.appendSlice(a, &.{ "-o", output, job.source });
    var jobs = [_]unit_cache.Job{.{ .argv = argv.items, .weight = 1 }};
    try unit_cache.compileAll(native.resources(), &jobs, 1);
    native.counts.processes += 1;
    if (!jobs[0].ok) return null;
    const text = std.Io.Dir.cwd().readFileAlloc(native.io, output, a, .limited(1 << 30)) catch return null;
    if (unexpandedData(text)) return null;
    var digest: Digest = undefined;
    fast_blake3.hash(text, &digest);
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-foreign-preprocessed-v1");
    unit_cache.field(&hash, &job.manifest_key);
    unit_cache.field(&hash, &digest);
    var key: Digest = undefined;
    hash.final(&key);
    return key;
}

/// Whether preprocessed text still refers to data the preprocessor did not expand into it: an `#embed` directive, or an
/// `.incbin` in inline assembly. Its object would depend on a file the text does not hold.
fn unexpandedData(text: []const u8) bool {
    if (std.mem.indexOf(u8, text, "incbin") != null) return true;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const start = std.mem.trimStart(u8, line, " \t");
        if (start.len == 0 or start[0] != '#') continue;
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, start[1..], " \t"), "embed")) return true;
    }
    return false;
}

/// The object a preprocessed key holds, with what the C compiler said when it made it.
fn servedPreprocessed(native: Native, store: unit_cache.Store, key: Digest) Error!?ServedForeign {
    const a = native.arena;
    const found = try store.lookup(a, native.io, key, ".o") orelse return null;
    const log = std.Io.Dir.cwd().readFileAlloc(native.io, try store.path(a, key, ".log"), a, .limited(16 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    return .{ .object = .{ .path = found.path, .digest = found.digest }, .dependencies = &.{}, .log = log };
}

/// A fresh `--link` object and its store key: under `--verify-cache` an object already stored there must have its bytes.
const Fresh = struct { key: Digest, object: []const u8, verify: bool };

/// Publish a freshly compiled `--link` object under its key, or, under `--verify-cache`, require the object stored there
/// to equal it: a served object is recompiled and compared, under either key.
fn publishForeign(native: Native, store: unit_cache.Store, fresh: Fresh) Error!unit_cache.Found {
    const a = native.arena;
    const compiled = try unit_cache.found(a, native.io, fresh.object);
    if (fresh.verify) if (try store.lookup(a, native.io, fresh.key, ".o")) |stored| {
        if (!std.mem.eql(u8, &stored.digest, &compiled.digest)) {
            try native.log.print(a, "error: --verify-cache: a --link source compiles to different bytes than its cached object {s}\n", .{stored.path});
            return error.ToolFailed;
        }
        native.counts.verified += 1;
        return stored;
    };
    return store.publish(a, native.io, fresh.key, ".o", fresh.object);
}

const ServedForeign = struct { object: Object, dependencies: []const inputs_handle.Input, log: []const u8 };

/// Where the C compiler's output for a manifest is kept.
fn logPath(a: std.mem.Allocator, manifest: []const u8) Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}.log", .{manifest});
}

fn servedForeign(native: Native, store: unit_cache.Store, manifest_key: Digest, manifest: []const u8) Error!?ServedForeign {
    const a = native.arena;
    const text = std.Io.Dir.cwd().readFileAlloc(native.io, manifest, a, .limited(16 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const dependencies = try parseManifest(a, text) orelse return null;
    if (!try inputs_handle.unchanged(.{ .arena = a, .io = native.io, .environment = native.environment }, dependencies)) return null;
    const found = try store.lookup(a, native.io, objectKey(manifest_key, text), ".o") orelse return null;
    // An entry made before compiler output was kept has no record of it: compile again rather than stay silent.
    const log = std.Io.Dir.cwd().readFileAlloc(native.io, try logPath(a, manifest), a, .limited(16 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    return .{ .object = .{ .path = found.path, .digest = found.digest }, .dependencies = dependencies, .log = log };
}

/// The `-I` flags of `folders`, each folder resolved to an absolute path, for every `--link` compile and its key.
fn includeFlags(a: std.mem.Allocator, folders: []const []const u8) error{OutOfMemory}![]const []const u8 {
    const flags = try a.alloc([]const u8, folders.len);
    for (folders, flags) |folder, *flag| flag.* = try std.fmt.allocPrint(a, "-I{s}", .{try std.fs.path.resolve(a, &.{folder})});
    return flags;
}

/// The manifest slot of one `--link` source: its absolute path and bytes, the
/// compile settings, its include folders and the toolchain.
fn foreignKey(native: Native, settings: unit_cache.Settings, source: []const u8, include: []const []const u8) Error!Digest {
    const a = native.arena;
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(native.io, source, a) catch source;
    const content = unit_cache.fileDigest(a, native.io, source) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ReadFailed => null,
    };
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-foreign-v1");
    for (sanitizeArguments(native.environment)) |argument| unit_cache.field(&hash, argument);
    // Only a build with include folders adds them, so a source's key without any is the key it had before they existed.
    for (include) |flag| unit_cache.field(&hash, flag);
    unit_cache.field(&hash, absolute);
    // The source's spelling and the working directory reach its debug information.
    unit_cache.field(&hash, source);
    unit_cache.field(&hash, std.Io.Dir.cwd().realPathFileAlloc(native.io, ".", a) catch "");
    unit_cache.field(&hash, if (content) |*digest| digest else "absent");
    unit_cache.field(&hash, @tagName(settings.mode));
    unit_cache.field(&hash, settings.mode.level());
    unit_cache.field(&hash, native.target.cc_target);
    for (native.target.cpu_flags) |flag| unit_cache.field(&hash, flag);
    unit_cache.field(&hash, &settings.cpu);
    unit_cache.field(&hash, &settings.tool);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn objectKey(manifest_key: Digest, manifest: []const u8) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, "core-foreign-object-v1");
    unit_cache.field(&hash, &manifest_key);
    unit_cache.field(&hash, manifest);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

const manifest_magic = "core-foreign-deps-v3\n";

/// A manifest is the magic line and the handle's record (`inputs.manifest`).
fn manifestText(a: std.mem.Allocator, recorded: []const inputs_handle.Input) Error![]const u8 {
    return std.mem.concat(a, u8, &.{ manifest_magic, try inputs_handle.manifest(a, recorded) });
}

fn parseManifest(a: std.mem.Allocator, text: []const u8) Error!?[]const inputs_handle.Input {
    if (!std.mem.startsWith(u8, text, manifest_magic)) return null;
    const recorded = try inputs_handle.parseManifest(a, text[manifest_magic.len..]) orelse return null;
    return if (recorded.len == 0) null else recorded;
}

fn readDepfile(native: Native, path: []const u8) Error![]const []const u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(native.io, path, native.arena, .limited(16 << 20)) catch {
        try native.log.print(native.arena, "error: the C compiler wrote no dependency file {s}\n", .{path});
        return error.ToolFailed;
    };
    return unit_cache.depfileInputs(native.arena, bytes);
}

/// Digest every listed input by absolute path, through `handle`. A file whose status changed at or
/// after `since` (this build's marker, created before the compile started) may
/// differ from the bytes the compiler read, so the set is not pinned (null).
fn pinned(native: Native, handle: *inputs_handle.Handle, listed: []const []const u8, since: i96) Error!?[]const unit_cache.Dependency {
    const a = native.arena;
    const cwd = std.Io.Dir.cwd();
    const working = handle.workingDirectory();
    const dependencies = try a.alloc(unit_cache.Dependency, listed.len);
    for (listed, dependencies) |input, *dependency| {
        const absolute = try std.fs.path.resolve(a, &.{ working, input });
        const digest = handle.digest(absolute) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ReadFailed => return null,
        } orelse return null;
        const after = cwd.statFile(native.io, absolute, .{}) catch return null;
        if (after.ctime.nanoseconds >= since or after.mtime.nanoseconds >= since) return null;
        dependency.* = .{ .path = absolute, .digest = digest };
    }
    return dependencies;
}

/// What `lookedFor` found: every name readable (the source is cached by its depfile), a directive that names its
/// header through a macro (the source takes the preprocessed path from the next build on), or a file that changed.
const Looked = enum { readable, macro, changed };

/// Record, through `handle`, the files the quoted includes and `__has_include` tests of the listed
/// sources and headers asked for beside the file that names them: with their bytes when there, absent
/// when not. The compiler's dependency file lists only what it opened, so a header that appears later
/// (one that shadows a system header, or one `__has_include` tests for) would not move it. False when a
/// directive names its header through a macro, or a listed file changed after its digest was taken:
/// nothing is then cached for the source.
fn lookedFor(native: Native, handle: *inputs_handle.Handle, listed: []const unit_cache.Dependency) Error!Looked {
    const a = native.arena;
    var known: std.StringHashMapUnmanaged(void) = .empty;
    for (listed) |dependency| try known.put(a, dependency.path, {});
    for (listed) |dependency| {
        // A toolchain header is an input by its bytes; what it asks for beside it is the toolchain's.
        if (inToolchain(native, dependency.path)) continue;
        const text = handle.read(dependency.path, 64 << 20) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ReadFailed => return .changed,
        };
        var digest: Digest = undefined;
        fast_blake3.hash(text, &digest);
        if (!std.mem.eql(u8, &digest, &(dependency.digest orelse return .changed))) return .changed;
        const names = try c_includes.quotedNames(a, text) orelse return .macro;
        const directory = std.fs.path.dirname(dependency.path) orelse ".";
        for (names) |name| {
            const path = try std.fs.path.resolve(a, &.{ directory, name });
            if ((try known.getOrPut(a, path)).found_existing) continue;
            _ = handle.digest(path) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.ReadFailed => return .changed,
            };
        }
    }
    return if (handle.torn) .changed else .readable;
}

/// Whether `path` is inside the toolchain's library: the one beside the `zig` executable, or `ZIG_LIB_DIR`.
fn inToolchain(native: Native, path: []const u8) bool {
    if (native.environment.get("ZIG_LIB_DIR")) |override| {
        if (override.len != 0 and std.mem.startsWith(u8, path, override) and path.len > override.len and path[override.len] == '/') return true;
    }
    const executable = std.fs.path.dirname(native.zig) orelse return false;
    return std.mem.startsWith(u8, path, executable) and std.mem.startsWith(u8, path[executable.len..], "/lib/");
}

fn atomicWrite(native: Native, path: []const u8, bytes: []const u8) Error!void {
    const cwd = std.Io.Dir.cwd();
    var nonce: [16]u8 = undefined;
    std.Io.random(native.io, &nonce);
    const partial = try std.fmt.allocPrint(native.arena, "{s}.{s}.partial", .{ path, std.fmt.bytesToHex(nonce, .lower) });
    defer removeFile(native.io, partial);
    cwd.writeFile(native.io, .{ .sub_path = partial, .data = bytes }) catch return error.WriteFailed;
    cwd.rename(partial, cwd, path, native.io) catch return error.WriteFailed;
}

/// The directory for content-keyed runtime and unit objects: `SELKA_CORE_RUNTIME_CACHE`,
/// else `$XDG_CACHE_HOME/selka/core-runtime`, else `$HOME/.cache/selka/core-runtime`,
/// so a new project, a fresh worktree or a test's temporary directory reuses objects
/// another build compiled. Sharing is safe because every key is the object's complete
/// input. An empty `SELKA_CORE_RUNTIME_CACHE`, no usable variable, or a directory that
/// cannot be created keeps the objects in `work`.
pub fn runtimeDirectory(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, work: []const u8) Error![]const u8 {
    const directory = (try sharedRuntimeDirectory(allocator, environ)) orelse return work;
    std.Io.Dir.cwd().createDirPath(io, directory) catch return work;
    return directory;
}

/// The object store `selka cache where` reports is the one a build uses: one rule (`store_settings.objectStore`).
fn sharedRuntimeDirectory(allocator: std.mem.Allocator, environ: *const std.process.Environ.Map) Error!?[]const u8 {
    return language.store_settings.objectStore(allocator, environ);
}

/// A fresh directory `<work>/<prefix>-<nonce>` this build alone owns.
fn privateDirectory(allocator: std.mem.Allocator, io: std.Io, work: []const u8, prefix: []const u8) Error![]const u8 {
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const path = try std.fs.path.join(allocator, &.{ work, try std.fmt.allocPrint(allocator, "{s}-{s}", .{ prefix, std.fmt.bytesToHex(nonce, .lower) }) });
    std.Io.Dir.cwd().createDirPath(io, path) catch return error.WriteFailed;
    return path;
}

/// The key domain of a hosted runtime object. **Bump it whenever the object's bytes change for the same inputs.** It is
/// v5 since 19 November 2026: GH-3f made the object hold the source name `core_rt.c` where it had held
/// `core_rt-<key>.c`, and kept v4. Compilers from before GH-3f, still running in other worktrees, went on storing the old
/// kind under the same keys in the per-user store, so a component linked with one kind and rebuilt with the other differed
/// by that name, and the component bootstrap test failed at random in every session's gate.
pub const runtime_object_domain = "core-runtime-object-v5";

test "the runtime object's key domain is past v4, whose stored objects hold a hash-named source" {
    try std.testing.expect(!std.mem.eql(u8, runtime_object_domain, "core-runtime-object-v4"));
    try std.testing.expect(std.mem.startsWith(u8, runtime_object_domain, "core-runtime-object-v"));
}

/// The runtime object for this runtime source, compiled on first use. Its source is compiled as `core_rt.c` in a directory
/// named by the object's key below this build's private `staging` directory, never under the key itself: the C compiler writes
/// the source's file name into the object's symbol table, so a name holding the key (which holds the toolchain identity, and
/// so the machine's libraries) landed in every program's and kept two machines from building the same bytes.
fn runtimeObject(native: Native, directory: []const u8, staging: []const u8, runtime: Runtime) Error!Object {
    const allocator = native.arena;
    const io = native.io;
    var digest: Digest = undefined;
    var hash = fast_blake3.Blake3.init(.{});
    hash.update(runtime_object_domain ++ "\x00-O2\x00-g0\x00-falign-functions=64\x00-std=c11\x00");
    hash.update(native.target.cc_target);
    hash.update("\x00");
    hash.update(&runtime.implementation);
    hash.update(&native.guard.identity.digest);
    hash.final(&digest);
    const stem = try std.fmt.allocPrint(allocator, "core_rt-{x}", .{digest});
    const object = try std.fs.path.join(allocator, &.{ directory, try std.fmt.allocPrint(allocator, "{s}.o", .{stem}) });
    const cwd = std.Io.Dir.cwd();
    // The build took the root's lease at its start, or went on without it past the bound: either way this one does not wait again.
    var claim = try work_claim.Claim.attempt(allocator, io, directory, digest);
    defer if (claim) |*held| held.deinit();
    if (cwd.access(io, object, .{})) |_| return .{ .path = object, .digest = digest } else |_| {}
    const source_directory = try std.fs.path.join(allocator, &.{ staging, stem });
    cwd.createDirPath(io, source_directory) catch return error.WriteFailed;
    const source = try std.fs.path.join(allocator, &.{ source_directory, "core_rt.c" });
    cwd.writeFile(io, .{ .sub_path = source, .data = try runtimeText(native, runtime) }) catch return error.WriteFailed;
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const partial = try std.fmt.allocPrint(allocator, "{s}.{x}.partial", .{ object, nonce });
    defer removeFile(io, partial);
    var argv: std.ArrayList([]const u8) = .empty;
    // No debug info: the trap walker reads only the compile units whose producer is the compiler's pre-rename name (the string stays the
    // producer's, GH-D16), LLVM's machine code does not depend on it, and it cost a cold build 0.46 s.
    try argv.appendSlice(allocator, &.{ native.zig, "cc", "-c", "-O2", "-g0", "-falign-functions=64" });
    try argv.appendSlice(allocator, &.{ "-target", native.target.cc_target });
    try argv.appendSlice(allocator, native.target.cpu_flags);
    try argv.appendSlice(allocator, layoutArguments(native.environment));
    try argv.appendSlice(allocator, sanitizeArguments(native.environment));
    try argv.appendSlice(allocator, &.{ "-std=c11", "-pthread", "-o", partial, source });
    try run(native, argv.items);
    try native.checkTool(native.log);
    cwd.rename(partial, cwd, object, io) catch return error.WriteFailed;
    return .{ .path = object, .digest = digest };
}

fn removeFile(io: std.Io, path: []const u8) void {
    // A successfully published file already moved away; cleanup is best effort.
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

fn removeDirectory(io: std.Io, path: []const u8) void {
    // Best-effort cleanup of this build's owned random staging directory.
    std.Io.Dir.cwd().deleteTree(io, path) catch return;
}

/// Run one tool process (counted), appending its stderr to the log.
fn run(native: Native, argv: []const []const u8) Error!void {
    return runIn(native, argv, null);
}

/// The directory every link runs in. Zig builds the C library stubs of a program in the
/// directory it was started in and the stubs name it in their debug information
/// (`DW_AT_comp_dir`), so a fixed one gives the same program bytes wherever the project, the
/// work directory and the command were.
const link_directory = "/";

/// The cache directory Zig's libc stubs and compiler-rt are built into for a proved toolchain:
/// `$XDG_CACHE_HOME/selka/zig-global`, else `$HOME/.cache/selka/zig-global`. Null when there
/// is no usable home or it cannot be created; the link then uses a private one.
fn zigGlobalDirectory(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map) Error!?[]const u8 {
    const parts: []const []const u8 = if (environ.get("XDG_CACHE_HOME")) |base| (if (std.fs.path.isAbsolute(base)) &.{ base, product.user_dir, "zig-global" } else &.{}) else &.{};
    const home = environ.get("HOME") orelse "";
    const directory = if (parts.len != 0)
        try std.fs.path.join(allocator, parts)
    else if (std.fs.path.isAbsolute(home))
        try std.fs.path.join(allocator, &.{ home, ".cache", product.user_dir, "zig-global" })
    else
        return null;
    std.Io.Dir.cwd().createDirPath(io, directory) catch return null;
    return directory;
}

/// `run` in the working directory `directory` (null: this process's own).
fn runIn(native: Native, argv: []const []const u8, directory: ?[]const u8) Error!void {
    native.counts.processes += 1;
    const result = @import("process_spawn.zig").run(native.arena, native.io, .{ .argv = argv, .environment = .{ .map = native.environment }, .cwd = directory, .die_with_parent = true }) catch |err| {
        try native.log.print(native.arena, "error: cannot run {s}: {s}\n", .{ argv[0], @errorName(err) });
        return error.ToolFailed;
    };
    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    // The hint leads: a test verdict keeps only the first line of the log.
    if (!ok) if (@import("memory_budget").toolExhausted(native.environment, result.term, result.stderr)) |hint| try native.log.appendSlice(native.arena, hint);
    try native.log.appendSlice(native.arena, result.stderr);
    if (!ok) return error.ToolFailed;
}

// spec: NEW-CORE-S4-LINK-1
test "a debug link without foreign C objects leaves out Zig's UBSan runtime" {
    try std.testing.expectEqualStrings("-fno-sanitize=undefined", linkSanitizer(false, 0));
    try std.testing.expectEqualStrings("", linkSanitizer(false, 1));
    try std.testing.expectEqualStrings("", linkSanitizer(true, 0));
}

// spec-case: NEW-CORE-S4-TEST-3
test "Guard.check refuses changed and missing tool inputs and propagates allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "zig", .data = "first" });
    try directory.dir.setFilePermissions(std.testing.io, "zig", .executable_file, .{});
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = std.process.Environ.Map.init(a);
    const resources: tool_identity.Request = .{ .arena = a, .io = std.testing.io, .environment = &environment, .executable = try std.fs.path.join(a, &.{ root, "zig" }), .cache = try std.fs.path.join(a, &.{ root, "cache" }) };
    const guard: Guard = .{ .resources = resources, .identity = try tool_identity.capture(resources) };
    var log: std.ArrayList(u8) = .empty;
    try guard.check(&log);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "zig", .data = "other" });
    try std.testing.expectError(error.ToolFailed, guard.check(&log));
    try std.testing.expect(std.mem.indexOf(u8, log.items, "toolchain changed") != null);
    try directory.dir.deleteFile(std.testing.io, "zig");
    try std.testing.expectError(error.ToolFailed, guard.check(&log));
    var failing = guard;
    failing.resources.arena = std.testing.failing_allocator;
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "zig", .data = "other" });
    try directory.dir.setFilePermissions(std.testing.io, "zig", .executable_file, .{});
    try std.testing.expectError(error.OutOfMemory, failing.check(&log));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "foreign manifests round-trip and damaged ones are misses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const recorded = [_]inputs_handle.Input{
        .{ .file = .{ .path = "/src/value.c", .digest = @splat(1) } },
        .{ .file = .{ .path = "/src/with space.h", .digest = @splat(2) } },
        .{ .file = .{ .path = "/src/opt.h", .digest = null } },
    };
    const text = try manifestText(a, &recorded);
    const parsed = (try parseManifest(a, text)).?;
    try std.testing.expectEqual(@as(usize, 3), parsed.len);
    try std.testing.expectEqualStrings("/src/with space.h", parsed[1].file.path);
    try std.testing.expectEqual(recorded[1].file.digest.?, parsed[1].file.digest.?);
    try std.testing.expectEqualStrings("/src/opt.h", parsed[2].file.path);
    try std.testing.expectEqual(@as(?unit_cache.Digest, null), parsed[2].file.digest);
    try std.testing.expectEqual(@as(?[]const inputs_handle.Input, null), try parseManifest(a, text[0 .. text.len - 1]));
    try std.testing.expectEqual(@as(?[]const inputs_handle.Input, null), try parseManifest(a, manifest_magic));
    try std.testing.expectEqual(@as(?[]const inputs_handle.Input, null), try parseManifest(a, "core-foreign-deps-v2\n"));
    try std.testing.expect(!std.mem.eql(u8, &objectKey(@splat(3), text), &objectKey(@splat(3), try manifestText(a, recorded[0..1]))));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "servedPreprocessed serves an object only with its compiler record, and unexpanded data keeps a text out of the cache" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment: std.process.Environ.Map = .init(a);
    var log: std.ArrayList(u8) = .empty;
    var counts: Counts = .{};
    const native = testNative(a, &environment, &log, &counts);
    const store: unit_cache.Store = .{ .directory = root };
    const key: Digest = @splat(7);
    const staged = try std.fs.path.join(a, &.{ root, "staged.o" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "staged.o", .data = "object" });
    _ = try store.publish(a, std.testing.io, key, ".o", staged);
    // An object stored without the record of what the compiler said is compiled again.
    try std.testing.expectEqual(@as(?ServedForeign, null), try servedPreprocessed(native, store, key));
    try atomicWrite(native, try store.path(a, key, ".log"), "warning: careful\n");
    const served = (try servedPreprocessed(native, store, key)).?;
    try std.testing.expectEqualStrings("warning: careful\n", served.log);
    try std.testing.expect(unexpandedData("__asm__(\".incbin \\\"data.bin\\\"\");\n"));
    try std.testing.expect(unexpandedData("int a[] = {\n  #  embed \"data.bin\"\n};\n"));
    try std.testing.expect(!unexpandedData("int a[] = {65, 66 };\n# 1 \"embed.h\" 1\n"));
}

// spec-case: NEW-CORE-S4-CACHE-1
test "lookedFor records the quoted headers a listed file asks for beside it and refuses what it cannot read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "foo.c", .data = "#include \"present.h\"\n#include \"absent.h\"\n#include <stdint.h>\n#if __has_include(\"opt.h\")\n#endif\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "present.h", .data = "int x;\n" });
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "macro.c", .data = "#define HEADER \"x.h\"\n#include HEADER\n" });
    var environment: std.process.Environ.Map = .init(a);
    var log: std.ArrayList(u8) = .empty;
    var counts: Counts = .{};
    const native = testNative(a, &environment, &log, &counts);
    const source_path = try std.fs.path.join(a, &.{ root, "foo.c" });
    const header_path = try std.fs.path.join(a, &.{ root, "present.h" });
    const listed = [_]unit_cache.Dependency{
        .{ .path = source_path, .digest = try unit_cache.fileDigest(a, std.testing.io, source_path) },
        .{ .path = header_path, .digest = try unit_cache.fileDigest(a, std.testing.io, header_path) },
    };
    var handle = inputs_handle.Handle.init(a, std.testing.io, &environment);
    // `pinned` has recorded the listed files; `lookedFor` adds the two names asked for that were not there.
    _ = try handle.digest(source_path);
    _ = try handle.digest(header_path);
    try std.testing.expectEqual(Looked.readable, try lookedFor(native, &handle, &listed));
    const recorded = handle.inputs();
    try std.testing.expectEqual(@as(usize, 4), recorded.len);
    try std.testing.expect(std.mem.endsWith(u8, recorded[2].file.path, "/absent.h"));
    try std.testing.expectEqual(@as(?unit_cache.Digest, null), recorded[2].file.digest);
    try std.testing.expect(std.mem.endsWith(u8, recorded[3].file.path, "/opt.h"));
    // The record is what a later build checks: a header that appears moves it.
    try std.testing.expect(try inputs_handle.unchanged(handle.live, recorded));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "absent.h", .data = "int y;\n" });
    try std.testing.expect(!try inputs_handle.unchanged(handle.live, recorded));
    // A header named through a macro cannot be read from the text, and a listed file that changed since it was hashed is not pinned.
    const macro_path = try std.fs.path.join(a, &.{ root, "macro.c" });
    const macro = [_]unit_cache.Dependency{.{ .path = macro_path, .digest = try unit_cache.fileDigest(a, std.testing.io, macro_path) }};
    var macro_handle = inputs_handle.Handle.init(a, std.testing.io, &environment);
    try std.testing.expectEqual(Looked.macro, try lookedFor(native, &macro_handle, &macro));
    const changed = [_]unit_cache.Dependency{.{ .path = header_path, .digest = @splat(9) }};
    var changed_handle = inputs_handle.Handle.init(a, std.testing.io, &environment);
    try std.testing.expectEqual(Looked.changed, try lookedFor(native, &changed_handle, &changed));
    const gone = [_]unit_cache.Dependency{.{ .path = try std.fs.path.join(a, &.{ root, "gone.h" }), .digest = @splat(1) }};
    var gone_handle = inputs_handle.Handle.init(a, std.testing.io, &environment);
    try std.testing.expectEqual(Looked.changed, try lookedFor(native, &gone_handle, &gone));
}

// spec-case: PROVABLE-CACHE-K1-LINK-1
test "the Zig global cache of a proved toolchain is selka's own under the user's cache home" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment: std.process.Environ.Map = .init(a);
    try std.testing.expectEqual(@as(?[]const u8, null), try zigGlobalDirectory(a, std.testing.io, &environment));
    try environment.put("HOME", "relative/home");
    try std.testing.expectEqual(@as(?[]const u8, null), try zigGlobalDirectory(a, std.testing.io, &environment));
    try environment.put("HOME", root);
    const from_home = (try zigGlobalDirectory(a, std.testing.io, &environment)).?;
    try std.testing.expect(std.mem.endsWith(u8, from_home, "/.cache/selka/zig-global"));
    try dir.dir.access(std.testing.io, ".cache/selka/zig-global", .{});
    // The user's own Zig cache variable never decides where the stubs are built.
    try environment.put("ZIG_GLOBAL_CACHE_DIR", "/somewhere/else");
    try environment.put("XDG_CACHE_HOME", try std.fs.path.join(a, &.{ root, "xdg" }));
    const from_xdg = (try zigGlobalDirectory(a, std.testing.io, &environment)).?;
    try std.testing.expectEqualStrings(try std.fs.path.join(a, &.{ root, "xdg", "selka", "zig-global" }), from_xdg);
    try environment.put("XDG_CACHE_HOME", "relative");
    try std.testing.expect(std.mem.endsWith(u8, (try zigGlobalDirectory(a, std.testing.io, &environment)).?, "/.cache/selka/zig-global"));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "blocker", .data = "a file where a directory must go" });
    try environment.put("XDG_CACHE_HOME", try std.fs.path.join(a, &.{ root, "blocker" }));
    try std.testing.expectEqual(@as(?[]const u8, null), try zigGlobalDirectory(a, std.testing.io, &environment));
}

// spec-case: PROVABLE-CACHE-K1-LINK-1
test "a path is in the toolchain when it is below the library beside the executable or ZIG_LIB_DIR" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    var log: std.ArrayList(u8) = .empty;
    var counts: Counts = .{};
    var native = testNative(a, &environment, &log, &counts);
    native.zig = "/opt/zig/zig";
    try std.testing.expect(inToolchain(native, "/opt/zig/lib/libc/include/generic-glibc/stdio.h"));
    try std.testing.expect(!inToolchain(native, "/opt/zig/library/stdio.h"));
    try std.testing.expect(!inToolchain(native, "/home/me/project/lib/stdio.h"));
    try std.testing.expect(!inToolchain(native, "/opt/zig/lib"));
    try environment.put("ZIG_LIB_DIR", "/elsewhere/zig-lib");
    try std.testing.expect(inToolchain(native, "/elsewhere/zig-lib/include/stdint.h"));
    try std.testing.expect(!inToolchain(native, "/elsewhere/zig-lib-copy/include/stdint.h"));
}

// spec-case: PROVABLE-CACHE-K1-LINK-1
test "runIn starts the tool in the directory it is given and reports one that cannot start" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment: std.process.Environ.Map = .init(a);
    var log: std.ArrayList(u8) = .empty;
    var counts: Counts = .{};
    const native = testNative(a, &environment, &log, &counts);
    const at_root = &[_][]const u8{ "/bin/sh", "-c", "test \"$(pwd -P)\" = /" };
    try runIn(native, at_root, link_directory);
    // The same command started where the project is finds another directory.
    try std.testing.expectError(error.ToolFailed, runIn(native, at_root, root));
    try std.testing.expectError(error.ToolFailed, runIn(native, &.{"/no/such/program"}, link_directory));
    try std.testing.expect(std.mem.indexOf(u8, log.items, "cannot run /no/such/program") != null);
    try std.testing.expectEqual(@as(u32, 3), counts.processes);
}

// spec-case: NEW-CORE-DRIVER-1
test "privateDirectory refuses unwritable paths and allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "blocked", .data = "file" });
    try std.testing.expectError(error.WriteFailed, privateDirectory(a, std.testing.io, try std.fs.path.join(a, &.{ root, "blocked" }), "native-link"));
    try std.testing.expectError(error.OutOfMemory, privateDirectory(std.testing.failing_allocator, std.testing.io, root, "native-link"));
    const first = try privateDirectory(a, std.testing.io, root, "native-link");
    const second = try privateDirectory(a, std.testing.io, root, "native-link");
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.testing.expect(std.mem.startsWith(u8, std.fs.path.basename(first), "native-link-"));
}

fn testNative(a: std.mem.Allocator, environment: *const std.process.Environ.Map, log: *std.ArrayList(u8), counts: *Counts) Native {
    const resources: tool_identity.Request = .{ .arena = a, .io = std.testing.io, .environment = environment, .executable = "zig", .cache = "" };
    const identity: tool_identity.Identity = .{ .path = "zig", .digest = @splat(0), .generation = @splat(0), .native_target = @splat(0), .inputs = 0, .memo_hit = false };
    return .{ .arena = a, .io = std.testing.io, .environment = environment, .zig = "zig", .log = log, .guard = .{ .resources = resources, .identity = identity }, .counts = counts };
}

test "spawnQuietly and runQuietly say a tool that cannot start or fails, and keep the log of one that succeeds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try std.testing.environ.createMap(a);
    var log: std.ArrayList(u8) = .empty;
    var counts: Counts = .{};
    const native = testNative(a, &environment, &log, &counts);
    try std.testing.expect((try spawnQuietly(native, &.{"/no/such/program"}, null, &environment)) == null);
    try std.testing.expectError(error.OutOfMemory, spawnQuietly(testNative(std.testing.failing_allocator, &environment, &log, &counts), &.{"/bin/true"}, null, &environment));
    try std.testing.expect(!(try runQuietly(native, &.{"/no/such/program"}, null)));
    try std.testing.expect(!(try runQuietly(native, &.{"/bin/false"}, null)));
    try std.testing.expect(try runQuietly(native, &.{ "/bin/sh", "-c", "echo warned >&2" }, null));
    try std.testing.expectEqualStrings("warned\n", log.items);
    try std.testing.expectEqual(@as(u32, 3), counts.processes);
}

/// Expect two argument lists to hold the same words.
fn expectSameWords(expected: []const []const u8, actual: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "a bare target's unit compiles with the target's own flags whatever its size, and a hosted lean unit's flags follow the cap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    var log: std.ArrayList(u8) = .empty;
    var counts: Counts = .{};
    var native = testNative(a, &environment, &log, &counts);
    // Hosted: a lean unit within the cap has LLVM's IR passes on, a larger one has not; -O0 modes ignore the size.
    const small = try unitFlags(native, .lean_debug, build_mode.lean_passes_cap);
    const large = try unitFlags(native, .lean_debug, build_mode.lean_passes_cap + 1);
    try std.testing.expectEqual(large.len - 2, small.len);
    try std.testing.expectEqualStrings("-Xclang", large[1]);
    try std.testing.expectEqualStrings("-mllvm", small[1]);
    try expectSameWords(try unitFlags(native, .optimized_debug, 1), try unitFlags(native, .optimized_debug, 1 << 30));
    // A bare target: its own `compile` list, for a unit of any size, and none of the lean build's words.
    native.target = &target_policy.thumbv6m_none;
    const bare = native.target.system.runtime.bare;
    try expectSameWords(bare.compile, try unitFlags(native, .lean_debug, 0));
    try expectSameWords(bare.compile, try unitFlags(native, .lean_debug, build_mode.lean_passes_cap));
    try expectSameWords(bare.compile, try unitFlags(native, .lean_debug, build_mode.lean_passes_cap + 1));
    try expectSameWords(try unitFlags(native, .lean_debug, 0), try unitFlags(native, .lean_debug, build_mode.lean_passes_cap + 1));
}

// spec-case: LAYOUT-SWITCH-1
test "layout compile arguments and runtime identity include the internal alignment switch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    var log: std.ArrayList(u8) = .empty;
    var counts: Counts = .{};
    const native = testNative(a, &environment, &log, &counts);
    var runtime_home = std.testing.tmpDir(.{});
    defer runtime_home.cleanup();
    const runtime_directory = try runtime_home.dir.realPathFileAlloc(std.testing.io, ".", a);
    const default = try runtimeFor(a, std.testing.io, runtime_directory, .ordinary, &environment, &log);
    var expected: Digest = undefined;
    fast_blake3.hash(runtime_source, &expected);
    try std.testing.expectEqualSlices(u8, &expected, &default.implementation);
    try std.testing.expectEqual(runtimeAbi(runtime_source, .ordinary, &environment), default.abi);
    try environment.put("SELKA_CORE_LAYOUT", "5");
    const aligned = try runtimeFor(a, std.testing.io, runtime_directory, .ordinary, &environment, &log);
    try std.testing.expect(!std.mem.eql(u8, &default.abi, &aligned.abi));
    const arguments = try compileArguments(native, &.{"-O3"}, "out.o", "in.ll");
    try std.testing.expectEqualStrings("-mllvm", arguments[arguments.len - 6]);
    try std.testing.expectEqualStrings("-align-all-functions=5", arguments[arguments.len - 5]);
    try environment.put("SELKA_CORE_LAYOUT", "7");
    try std.testing.expectError(error.ToolFailed, validateLayout(a, &environment, &log));
    try std.testing.expectEqualStrings("error: SELKA_CORE_LAYOUT must be 4, 5 or 6\n", log.items);
}

// spec: BUILD-OUTPUT-DIR-1
// spec-case: NEW-CORE-S4-CACHE-1
test "placeOutput creates a missing output directory, reports an unwritable output and servedForeign misses on damaged or stale manifests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const root = try dir.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment: std.process.Environ.Map = .init(a);
    var log: std.ArrayList(u8) = .empty;
    var counts: Counts = .{};
    const native = testNative(a, &environment, &log, &counts);
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "program", .data = "binary" });
    const program = try std.fs.path.join(a, &.{ root, "program" });
    // A parent that is a regular file cannot be made a directory: the error names the path and the cause.
    try std.testing.expectError(error.WriteFailed, placeOutput(native, &.{program}, try std.fs.path.join(a, &.{ root, "program", "out" })));
    try std.testing.expect(std.mem.indexOf(u8, log.items, "cannot write") != null);
    try std.testing.expect(std.mem.indexOf(u8, log.items, "NotDir") != null);
    // A missing parent directory, at any depth, is created.
    log.clearRetainingCapacity();
    try placeOutput(native, &.{program}, try std.fs.path.join(a, &.{ root, "build", "deep", "out" }));
    try std.testing.expectEqualStrings("binary", try dir.dir.readFileAlloc(std.testing.io, "build/deep/out", a, .limited(64)));
    try std.testing.expectEqualStrings("", log.items);
    try placeOutput(native, &.{program}, try std.fs.path.join(a, &.{ root, "out" }));
    try std.testing.expectEqualStrings("binary", try dir.dir.readFileAlloc(std.testing.io, "out", a, .limited(64)));
    // The output is a second name for the program's file, and the build counted how it was placed.
    try std.testing.expectEqual(@as(?program_store.Placement, .linked), counts.link.placement);
    try std.testing.expect(program_store.sameFile(program, try std.fs.path.join(a, &.{ root, "out" })));
    const store: unit_cache.Store = .{ .directory = root };
    try std.testing.expectEqual(@as(?ServedForeign, null), try servedForeign(native, store, @splat(1), try std.fs.path.join(a, &.{ root, "absent.deps" })));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "damaged.deps", .data = "core-foreign-deps-v1\nnot a line\n" });
    try std.testing.expectEqual(@as(?ServedForeign, null), try servedForeign(native, store, @splat(1), try std.fs.path.join(a, &.{ root, "damaged.deps" })));
    const stale = try manifestText(a, &.{.{ .file = .{ .path = program, .digest = @splat(7) } }});
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "stale.deps", .data = stale });
    try std.testing.expectEqual(@as(?ServedForeign, null), try servedForeign(native, store, @splat(1), try std.fs.path.join(a, &.{ root, "stale.deps" })));
}

// spec-case: FRONTEND-COST-1
test "cost optimizationRemarks and remarkUnit return unknown for unwritable staging missing tools and failed native compile" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try std.testing.environ.createMap(a);
    defer environment.deinit();
    const units = [_]emit_units.Unit{wholeUnit("invalid LLVM module")};
    var request: Request = .{ .zig = environment.get("SELKA_ZIG") orelse "zig", .work = root, .output = "", .family = .{ .mode = .release }, .links = &.{}, .units = &units };
    try std.testing.expectError(error.OutOfMemory, optimizationRemarks(std.testing.failing_allocator, std.testing.io, &environment, request));
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "blocked", .data = "file" });
    request.work = try std.fs.path.join(a, &.{ root, "blocked" });
    const blocked = try optimizationRemarks(a, std.testing.io, &environment, request);
    try std.testing.expect(blocked.yaml == null);
    try std.testing.expectEqual(@as(u32, 0), blocked.processes);
    request.work = root;
    const original = request.zig;
    request.zig = try std.fs.path.join(a, &.{ root, "missing-zig" });
    const missing = try optimizationRemarks(a, std.testing.io, &environment, request);
    try std.testing.expect(missing.yaml == null);
    try std.testing.expectEqual(@as(u32, 0), missing.processes);
    request.zig = original;
    const failed = try optimizationRemarks(a, std.testing.io, &environment, request);
    try std.testing.expect(failed.yaml == null);
    try std.testing.expectEqual(@as(u32, 1), failed.processes);
    try std.testing.expect(failed.compile_ns > 0);
}

// spec-case: NEW-CORE-COST-QUERY-1
test "cost query LLVM remark keys bind exact text tool CPU mode layout and instrumentation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var store = try query_store.Store.init(a, std.testing.io, root);
    defer store.deinit();
    var environment = std.process.Environ.Map.init(a);
    defer environment.deinit();
    var identity: tool_identity.Identity = .{
        .path = "/qualified/zig",
        .digest = @splat(1),
        .generation = @splat(2),
        .native_target = @splat(3),
        .inputs = 1,
        .memo_hit = false,
        .cacheable = true,
    };
    const original = try remarkKey(a, &store, identity, .{ .mode = .release }, &environment, "LLVM A");
    try std.testing.expect(!std.mem.eql(u8, &original, &try remarkKey(a, &store, identity, .{ .mode = .release }, &environment, "LLVM B")));
    try std.testing.expect(!std.mem.eql(u8, &original, &try remarkKey(a, &store, identity, .{ .mode = .debug }, &environment, "LLVM A")));
    identity.digest = @splat(4);
    try std.testing.expect(!std.mem.eql(u8, &original, &try remarkKey(a, &store, identity, .{ .mode = .release }, &environment, "LLVM A")));
    identity.digest = @splat(1);
    identity.native_target = @splat(5);
    try std.testing.expect(!std.mem.eql(u8, &original, &try remarkKey(a, &store, identity, .{ .mode = .release }, &environment, "LLVM A")));
    identity.native_target = @splat(3);
    try environment.put(layout_variable, "4");
    const laid_out = try remarkKey(a, &store, identity, .{ .mode = .release }, &environment, "LLVM A");
    try std.testing.expect(!std.mem.eql(u8, &original, &laid_out));
    try environment.put(sanitize_variable, "thread");
    try std.testing.expect(!std.mem.eql(u8, &laid_out, &try remarkKey(a, &store, identity, .{ .mode = .release }, &environment, "LLVM A")));
}
