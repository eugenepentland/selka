//! Turn emitted LLVM units into an executable with the bundled clang (`zig cc`),
//! through the core's own content-keyed stores (docs/design/new-core-s4.md §6):
//! - the runtime (-O2, whatever the program's level) and the number-text object,
//!   once per content, in the per-user directory `runtimeDirectory` names;
//! - one object per unit in that directory's `units-v1` store (`unit_cache.zig`),
//!   keyed by the unit's text, level, target, toolchain and runtime ABI. Misses
//!   compile in parallel with `zig cc -c`; hits start no process;
//! - each `--link` C source in the work directory's `foreign-v1` store, keyed by
//!   its bytes and the bytes of every header its compiler depfile listed;
//! - the linked program in the work directory's `programs-v1` store, keyed by
//!   every object it links, so a build whose objects all match links nothing.
//! Every `zig` process gets a fresh local cache inside this build's private
//! staging directory, removed when the build ends: these stores are the cache,
//! and Zig's own would only keep a second copy of every object and program.
//! A minimal driver rather than the old core's `qbe_build_llvm_compile.zig`:
//! that one is bound to the QBE manifest, fragment store and object cache.
const std = @import("std");
const build_mode = @import("build_mode.zig");
const target_policy = @import("target.zig");
const target = target_policy.current;
const number_runtime = @import("number_runtime.zig");
const tool_identity = @import("tool_identity.zig");
const emit_units = @import("emit_units.zig");
const unit_cache = @import("unit_cache.zig");
const native_receipt = @import("native_receipt.zig");
const count_runtime = @import("count_runtime.zig");
const sanitize_llvm = @import("sanitize_llvm.zig");
const Digest = unit_cache.Digest;
const query_store = @import("stage_store.zig");
const stage_metrics = @import("stage_metrics.zig");
const language = @import("mylang");
const shared_artifacts = language.shared_artifact_store;
const work_claim = language.native_cache_work;

/// The runtime C source, compiled into every program.
pub const runtime_source = @embedFile("runtime/core_rt.c") ++ "\n" ++
    @embedFile("runtime/core_dict.c") ++ "\n" ++
    @embedFile("runtime/core_unicode_data.h") ++ "\n" ++
    @embedFile("runtime/core_text.c") ++ "\n" ++
    @embedFile("runtime/core_sort.c") ++ "\n" ++ @embedFile("runtime/core_number.c") ++ "\n" ++
    @embedFile("runtime/core_io.c") ++ "\n" ++ @embedFile("runtime/core_durable.c") ++ "\n" ++ @embedFile("runtime/core_host.c") ++ "\n" ++
    @embedFile("runtime/core_bytes.c") ++ "\n" ++ @embedFile("runtime/core_values.c") ++ "\n" ++ @embedFile("runtime/core_owned_copy.c") ++ "\n" ++ @embedFile("runtime/core_test.c") ++ "\n" ++ @embedFile("runtime/core_tasks.c");

/// One build: tools, directories, the program and how to optimize it.
pub const Request = struct {
    /// The `zig` executable whose `cc` compiles and links.
    zig: []const u8,
    /// The build's cache directory: foreign objects, linked programs and staging.
    work: []const u8,
    output: []const u8,
    mode: build_mode.Mode = .optimized_debug,
    /// Extra C sources to compile and link (`--link`).
    links: []const []const u8,
    /// Independent LLVM inputs, in link order (`emit_units`, or `wholeUnit`).
    units: []const emit_units.Unit = &.{},
    /// `--verify-cache`: also recompile every unit the store served and require
    /// the same object bytes.
    verify: bool = false,
};

/// Why a native build failed; the tool's output was written to `log`.
pub const Error = error{ ToolFailed, OutOfMemory, WriteFailed, CacheMiss };

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
    /// Wall time inside the native linker process, zero on program cache hits.
    link_ns: u64 = 0,
};

/// The result of a successful `link`.
pub const Outcome = struct {
    counts: Counts = .{},
    /// The program came from the program store: no tool linked it.
    program_reused: bool = false,
    /// A verified shared artifact supplied the local program store entry.
    program_shared: bool = false,
    /// The program store entry the output was copied from (proved toolchains only).
    program: ?unit_cache.Found = null,
    /// The `--link` sources and the headers their depfiles listed, with the bytes
    /// the compiles read; null when a file changed while it was compiled, so no
    /// later build may trust these digests.
    foreign: ?[]const unit_cache.Dependency = &.{},
    /// The toolchain identity the build ran under.
    tool: tool_identity.Identity,
    /// The linked program's exact key (`programKey`): toolchain, target, every object
    /// and the linker environment, with no path and no compiler identity. Set on
    /// every successful link, whether the program was linked, reused or restored;
    /// test execution receipts bind it (EXEC-RECEIPT-1).
    program_key: ?Digest = null,
};

/// A whole-program LLVM text as the one unit of a build.
pub fn wholeUnit(llvm: []const u8) emit_units.Unit {
    return emit_units.unit("whole", "", .program, llvm);
}

const Guard = struct {
    resources: tool_identity.Request,
    identity: tool_identity.Identity,

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

    fn resources(self: Native) unit_cache.Resources {
        return .{ .arena = self.arena, .io = self.io, .environment = self.environment, .backing = self.backing, .memory_budget_bytes = stage_metrics.workerBudget(self.io) };
    }
};

/// Where one build keeps what it caches: `shared` (per-user, content keys only)
/// and `local` (the work directory), or both inside `staging` for an unproved tool.
const Places = struct { shared: []const u8, local: []const u8, staging: []const u8, cacheable: bool };

/// One object to link and the digest of its bytes (or of its store key, for the
/// runtime objects, whose key covers their whole input).
const Object = struct { path: []const u8, digest: Digest };

/// Compile and link `request.units` into `request.output`; failures append the tool's stderr to `log`.
pub fn link(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, request: Request, log: *std.ArrayList(u8)) Error!Outcome {
    return linkWithScratch(allocator, null, io, environ, request, log);
}

/// Link with private worker arenas on a reclaiming thread-safe allocator.
pub fn linkWithScratch(allocator: std.mem.Allocator, backing: ?std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, request: Request, log: *std.ArrayList(u8)) Error!Outcome {
    try validateLayout(allocator, environ, log);
    try validateSanitize(allocator, environ, log);
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, request.work) catch return error.WriteFailed;
    var environment = environ.clone(allocator) catch return error.OutOfMemory;
    defer environment.deinit();
    const staging = try privateDirectory(allocator, io, request.work, "native-link");
    defer removeDirectory(io, staging);
    environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(allocator, &.{ staging, "local" })) catch return error.OutOfMemory;
    const resources: tool_identity.Request = .{ .arena = allocator, .io = io, .environment = &environment, .executable = request.zig, .cache = request.work };
    const guest = tool_identity.capture(resources) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try log.print(allocator, "error: cannot run {s}: cannot identify guest toolchain: {s}\n", .{ request.zig, @errorName(err) });
        return error.ToolFailed;
    };
    // Zig's global cache holds only its own libc and compiler-rt builds, which no
    // program input reaches; a fresh one rebuilds them (about 6 s), so only an
    // unproved tool gets one, and it never writes the shared builds.
    if (!guest.cacheable) environment.put("ZIG_GLOBAL_CACHE_DIR", try std.fs.path.join(allocator, &.{ staging, "global" })) catch return error.OutOfMemory;
    var outcome: Outcome = .{ .tool = guest };
    const native: Native = .{ .arena = allocator, .io = io, .environment = &environment, .zig = guest.path, .log = log, .guard = .{ .resources = resources, .identity = guest }, .counts = &outcome.counts, .backing = backing };
    // Content-keyed objects are shared, so a fresh work directory (a new worktree,
    // a test's temporary directory) reuses them; an unproved tool keeps every
    // object private to this build.
    const places: Places = .{
        .shared = if (guest.cacheable) try runtimeDirectory(allocator, io, environ, request.work) else staging,
        .local = if (guest.cacheable) request.work else staging,
        .staging = staging,
        .cacheable = guest.cacheable,
    };
    const shared_lease = if (places.cacheable) try work_claim.lease(allocator, io, places.shared) else null;
    defer if (shared_lease) |file| file.close(io);
    const local_lease = if (places.cacheable and !std.mem.eql(u8, places.shared, places.local)) try work_claim.lease(allocator, io, places.local) else null;
    defer if (local_lease) |file| file.close(io);
    var needs: Dependencies = .{};
    for (request.units) |unit| needs = .{
        .number = needs.number or unit.dependencies.number,
        .math = needs.math or unit.dependencies.math,
        .counting = needs.counting or unit.dependencies.counting,
        .zero_rc = needs.zero_rc or unit.dependencies.zero_rc,
    };
    const runtime = try runtimeForMode(allocator, needs.counting, environ, log, needs.zero_rc);
    const settings: unit_cache.Settings = .{ .tool = guest.digest, .cpu = guest.native_target, .mode = request.mode, .runtime = runtime.abi };
    var objects: std.ArrayList(Object) = .empty;
    try objects.append(allocator, try runtimeObject(native, places.shared, runtime));
    try unitObjects(native, places, settings, request, &objects);
    if (needs.number) try objects.append(allocator, .{ .path = try number_runtime.object(allocator, io, places.shared), .digest = number_runtime.digest() });
    outcome.foreign = try foreignObjects(native, places, settings, request.links, &objects);
    const sanitizer = linkSanitizer(request.mode == .release, request.links.len);
    const program_key = programKey(settings, objects.items, needs.math, sanitizer, environ);
    outcome.program_key = program_key;
    const programs: unit_cache.Store = .{ .directory = try std.fs.path.join(allocator, &.{ places.local, "programs-v1" }) };
    var shared = try SharedProgram.open(native, request, program_key);
    defer if (shared) |*store| store.store.deinit();
    var program_claim: ?work_claim.Claim = if (!places.cacheable or request.verify) null else try work_claim.Claim.acquire(allocator, io, programs.directory, program_key);
    defer if (program_claim) |*claim| claim.deinit();
    var shared_claim = try SharedProgram.claim(shared, program_claim != null);
    defer if (shared_claim) |*claim| claim.deinit();
    if (program_claim != null) try native.guard.check(log);
    if (places.cacheable) if (try programs.lookup(allocator, io, program_key, "")) |found| {
        if (shared) |*store| try store.publish(native, found.path);
        try publishOutput(native, found.path, request.output);
        outcome.program_reused = true;
        outcome.program = found;
        return outcome;
    };
    const linked = try std.fs.path.join(allocator, &.{ staging, "program" });
    if (shared) |*store| if (try store.restore(native, linked)) {
        try native.guard.check(log);
        const restored = try programs.publish(allocator, io, program_key, "", linked);
        try publishOutput(native, restored.path, request.output);
        outcome.program_reused = true;
        outcome.program_shared = true;
        outcome.program = restored;
        return outcome;
    };
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(allocator, &.{ guest.path, "cc", request.mode.level(), "-target", target_policy.native_link_target });
    try argv.appendSlice(allocator, target.cpu_flags);
    if (sanitizer.len != 0) try argv.append(allocator, sanitizer);
    try argv.appendSlice(allocator, sanitizeArguments(environ));
    try argv.append(allocator, "-pthread");
    try argv.appendSlice(allocator, &.{ "-Wno-override-module", "-o", linked });
    for (objects.items) |object| try argv.append(allocator, object.path);
    if (needs.math) try argv.append(allocator, "-lm");
    const link_start = stage_metrics.now(io);
    try run(native, argv.items);
    outcome.counts.link_ns = stage_metrics.elapsed(io, link_start);
    try native.guard.check(log);
    if (!places.cacheable) {
        try publishOutput(native, linked, request.output);
        return outcome;
    }
    const published = try programs.publish(allocator, io, program_key, "", linked);
    if (shared) |*store| try store.publish(native, published.path);
    try publishOutput(native, published.path, request.output);
    outcome.program = published;
    return outcome;
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
        const owned = try present.store.claim(.program, present.key);
        return owned;
    }

    fn open(native: Native, request: Request, exact: Digest) Error!?SharedProgram {
        if (!native.guard.identity.cacheable or request.verify or request.links.len != 0) return null;
        const directory = shared_artifacts.selected(native.environment) orelse return null;
        const store = shared_artifacts.Store.open(native.arena, native.io, directory) catch |err| return failed(native, err);
        return .{ .store = store, .key = sharedProgramKey(exact, native.environment) };
    }

    fn restore(self: *SharedProgram, native: Native, destination: []const u8) Error!bool {
        return self.store.restore(.program, self.key, destination) catch |err| return failed(native, err);
    }

    fn publish(self: *SharedProgram, native: Native, path: []const u8) Error!void {
        try native.guard.check(native.log);
        _ = self.store.publishFile(.program, self.key, path) catch |err| return failed(native, err);
    }

    fn failed(native: Native, err: anyerror) Error {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        native.log.print(native.arena, "error: compiler shared program cache: {s}\n", .{@errorName(err)}) catch return error.OutOfMemory;
        return if (err == error.DeterminismMismatch) error.ToolFailed else error.WriteFailed;
    }
};

/// The shared store's key for a linked program (SHARED-PROGRAM-2): the exact program
/// key and the linker environment. The objects determine the bytes, so it binds no
/// compiler identity, and the store's byte verification guards the rest.
fn sharedProgramKey(exact: Digest, environment: *const std.process.Environ.Map) Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    unit_cache.field(&hash, "core-shared-program-v2");
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

/// `sharedProgramKey` as the version-1 domain computed it, with the compiler identity.
fn compilerBoundProgramKey(exact: Digest, environment: *const std.process.Environ.Map) Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    unit_cache.field(&hash, "core-shared-program-v1");
    unit_cache.field(&hash, @import("build_identity").compiler_identity);
    unit_cache.field(&hash, &exact);
    linkEnvironmentInto(&hash, environment);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

// spec: SHARED-PROGRAM-2
test "shared program keys bind the exact program and linker environment, not the compiler identity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(arena.allocator());
    defer environment.deinit();
    const exact: Digest = @splat(3);
    const key = sharedProgramKey(exact, &environment);
    var expected_hash = std.crypto.hash.Blake3.init(.{});
    unit_cache.field(&expected_hash, "core-shared-program-v2");
    unit_cache.field(&expected_hash, &exact);
    linkEnvironmentInto(&expected_hash, &environment);
    var expected: Digest = undefined;
    expected_hash.final(&expected);
    try std.testing.expectEqual(expected, key);
    try std.testing.expect(!std.mem.eql(u8, &key, &compilerBoundProgramKey(exact, &environment)));
    try std.testing.expect(!std.mem.eql(u8, &key, &sharedProgramKey(@splat(4), &environment)));
    try environment.put("SOURCE_DATE_EPOCH", "1");
    try std.testing.expect(!std.mem.eql(u8, &key, &sharedProgramKey(exact, &environment)));
}

const Dependencies = @import("emission_cache.zig").Dependencies;

/// The runtime source a build compiles and its digest: the ordinary runtime, or for a
/// unit emitted with `--counters` the counting runtime (`count_runtime.zig`).
const Runtime = struct { source: []const u8, abi: Digest };

fn runtimeFor(allocator: std.mem.Allocator, counting: bool, environment: *const std.process.Environ.Map, log: *std.ArrayList(u8)) Error!Runtime {
    return runtimeForMode(allocator, counting, environment, log, false);
}

fn runtimeForMode(allocator: std.mem.Allocator, counting: bool, environment: *const std.process.Environ.Map, log: *std.ArrayList(u8), zero_rc: bool) Error!Runtime {
    const base_source = if (!counting) runtime_source else count_runtime.source(allocator, runtime_source) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.AnchorMissing => {
            try log.appendSlice(allocator, "error: the counting runtime no longer matches the runtime source\n");
            return error.ToolFailed;
        },
    };
    const source = if (zero_rc) try std.mem.concat(allocator, u8, &.{ "#define MYL_ZERO_RC 1\n", base_source }) else base_source;
    var abi: Digest = undefined;
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update(source);
    for (layoutArguments(environment)) |argument| unit_cache.field(&hash, argument);
    for (sanitizeArguments(environment)) |argument| unit_cache.field(&hash, argument);
    hash.final(&abi);
    return .{ .source = source, .abi = abi };
}

// LAYOUT-SWITCH-1: internal paired-measurement control, also salted into the
// runtime ABI so all unit, runtime and program stores distinguish the options.
const layout_variable = "MYLANG_CORE_LAYOUT";

fn layoutArguments(environment: *const std.process.Environ.Map) []const []const u8 {
    const value = environment.get(layout_variable) orelse return &.{};
    if (std.mem.eql(u8, value, "4")) return &.{ "-mllvm", "-align-all-functions=4" };
    if (std.mem.eql(u8, value, "5")) return &.{ "-mllvm", "-align-all-functions=5" };
    if (std.mem.eql(u8, value, "6")) return &.{ "-mllvm", "-align-all-functions=6" };
    return &.{};
}

fn validateLayout(a: std.mem.Allocator, environment: *const std.process.Environ.Map, log: *std.ArrayList(u8)) Error!void {
    if (environment.get(layout_variable) == null or layoutArguments(environment).len != 0) return;
    try log.appendSlice(a, "error: MYLANG_CORE_LAYOUT must be 4, 5 or 6\n");
    return error.ToolFailed;
}

// TSAN-BUILD-1: instrument C and every emitted LLVM definition; the same
// option salts the runtime ABI and foreign settings, separating every cache.
const sanitize_variable = "MYLANG_CORE_SANITIZE";
const thread_sanitizer = "-fsanitize=thread";

fn sanitizeArguments(environment: *const std.process.Environ.Map) []const []const u8 {
    const value = environment.get(sanitize_variable) orelse return &.{};
    return if (std.mem.eql(u8, value, "thread")) &.{thread_sanitizer} else &.{};
}

fn validateSanitize(a: std.mem.Allocator, environment: *const std.process.Environ.Map, log: *std.ArrayList(u8)) Error!void {
    if (environment.get(sanitize_variable) == null or sanitizeArguments(environment).len != 0) return;
    try log.appendSlice(a, "error: MYLANG_CORE_SANITIZE must be thread\n");
    return error.ToolFailed;
}

fn instrumented(a: std.mem.Allocator, environment: *const std.process.Environ.Map, llvm: []const u8) std.mem.Allocator.Error![]const u8 {
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
    const native: Native = .{ .arena = a, .io = io, .environment = &environment, .zig = guest.path, .log = &log, .guard = .{ .resources = resources, .identity = guest }, .counts = &counts };
    var yaml: std.ArrayList(u8) = .empty;
    var result: OptimizationRemarks = .{};
    const context: RemarkContext = .{ .store = &queries, .staging = staging, .mode = request.mode, .cacheable = guest.cacheable, .verify = request.verify };
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

const RemarkContext = struct { store: *query_store.Store, staging: []const u8, mode: build_mode.Mode, cacheable: bool, verify: bool };

fn remarkUnit(native: Native, context: RemarkContext, unit: emit_units.Unit, index: usize, outcome: *OptimizationRemarks) std.mem.Allocator.Error!?[]const u8 {
    const a = native.arena;
    const text = unitText(a, unit) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const actual = try instrumented(a, native.environment, text);
    const key = try remarkKey(a, context.store, native.guard.identity, context.mode, native.environment, actual);
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
    try args.appendSlice(a, try compileArguments(native, context.mode.level(), object, source));
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

fn remarkKey(a: std.mem.Allocator, store: *const query_store.Store, tool: tool_identity.Identity, mode: build_mode.Mode, environment: *const std.process.Environ.Map, text: []const u8) std.mem.Allocator.Error!Digest {
    var flags: std.ArrayList(u8) = .empty;
    defer flags.deinit(a);
    // Exact semantic arguments; private output/input paths are not compiler inputs.
    for (target.cpu_flags) |argument| {
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
    return store.key("llvm-optimization-record-v1:cc-c-Wno-override-module-fsave-optimization-record", &.{ &tool.digest, &tool.native_target, mode.level(), target_policy.native_link_target, flags.items, text });
}

/// Copy `program` to `output` under a temporary name and rename it into place.
/// An existing output is removed first: ext4 flushes a file renamed over another
/// one to disk before the rename returns (`auto_da_alloc`), which cost an unchanged
/// build 50-300 ms for a 10 MB program; a rename to a free name does not.
pub fn copyOutput(io: std.Io, program: []const u8, output: []const u8) std.Io.Dir.CopyFileError!void {
    const cwd = std.Io.Dir.cwd();
    // A missing output is the usual case; any other failure surfaces in the copy.
    removeFile(io, output);
    try cwd.copyFile(program, cwd, output, io, .{});
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
/// bytes, in link order.
fn programKey(settings: unit_cache.Settings, objects: []const Object, math: bool, sanitizer: []const u8, environment: *const std.process.Environ.Map) Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    unit_cache.field(&hash, "core-program-v2");
    unit_cache.field(&hash, sanitizer);
    unit_cache.field(&hash, unit_cache.format);
    unit_cache.field(&hash, settings.mode.level());
    unit_cache.field(&hash, target_policy.native_link_target);
    for (target.cpu_flags) |flag| unit_cache.field(&hash, flag);
    unit_cache.field(&hash, &settings.cpu);
    unit_cache.field(&hash, &settings.tool);
    for (objects) |object| unit_cache.field(&hash, &object.digest);
    unit_cache.field(&hash, if (math) "-lm" else "");
    linkEnvironmentInto(&hash, environment);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn linkEnvironmentInto(hash: *std.crypto.hash.Blake3, environment: *const std.process.Environ.Map) void {
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
    const first = programKey(settings, &objects, false, "", &environment);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "staged", .data = "linked-program" });
    _ = try store.publish(a, std.testing.io, first, "", try std.fs.path.join(a, &.{ root, "staged" }));
    try std.testing.expect((try store.lookup(a, std.testing.io, first, "")) != null);
    try environment.put("SOURCE_DATE_EPOCH", "1");
    const changed = programKey(settings, &objects, false, "", &environment);
    try std.testing.expect(!std.mem.eql(u8, &first, &changed));
    try std.testing.expect((try store.lookup(a, std.testing.io, changed, "")) == null);
    try environment.put("ZERO_AR_DATE", "1");
    try std.testing.expect(!std.mem.eql(u8, &changed, &programKey(settings, &objects, false, "", &environment)));
    _ = environment.swapRemove("SOURCE_DATE_EPOCH");
    _ = environment.swapRemove("ZERO_AR_DATE");
    try std.testing.expect((try store.lookup(a, std.testing.io, programKey(settings, &objects, false, "", &environment), "")) != null);
}

/// Copy a finished program to the requested output path (`copyOutput`).
fn publishOutput(native: Native, program: []const u8, output: []const u8) Error!void {
    copyOutput(native.io, program, output) catch |err| {
        try native.log.print(native.arena, "error: cannot write {s}: {s}\n", .{ output, @errorName(err) });
        return error.WriteFailed;
    };
}

/// One unit this build compiles: a store miss, or a hit `--verify-cache` checks.
const Pending = struct { unit: emit_units.Unit, key: Digest, object: []const u8, slot: usize, served: ?unit_cache.Found };

const UnitInput = struct { unit: emit_units.Unit, key: Digest };

fn digestLess(_: void, left: Digest, right: Digest) bool {
    return std.mem.order(u8, &left, &right) == .lt;
}

fn unitText(a: std.mem.Allocator, unit: emit_units.Unit) Error![]const u8 {
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

/// Serve each distinct unit from the store, compile the rest in parallel, and
/// append every object in unit order.
fn unitObjects(native: Native, places: Places, settings: unit_cache.Settings, request: Request, objects: *std.ArrayList(Object)) Error!void {
    const a = native.arena;
    const store: unit_cache.Store = .{ .directory = try std.fs.path.join(a, &.{ places.shared, "units-v1" }) };
    var seen: std.AutoHashMapUnmanaged(Digest, void) = .empty;
    var pending: std.ArrayList(Pending) = .empty;
    var jobs: std.ArrayList(unit_cache.Job) = .empty;
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
    if (places.cacheable and !request.verify) {
        std.mem.sort(Digest, missing.items, {}, digestLess);
        try claims.ensureTotalCapacity(a, missing.items.len);
        for (missing.items) |key| {
            claims.appendAssumeCapacity(try work_claim.Claim.acquire(a, native.io, store.directory, key));
        }
    }
    for (inputs) |input| {
        var unit = input.unit;
        const key = input.key;
        // Equal text is one object: linking it twice would define its symbols twice.
        if ((try seen.getOrPut(a, key)).found_existing) continue;
        native.counts.units += 1;
        const before_wait = initial.get(key).?;
        const recheck = before_wait == null and places.cacheable and !request.verify;
        const served = if (recheck) try store.lookup(a, native.io, key, ".o") else before_wait;
        if (served != null) native.counts.reused += 1;
        try objects.append(a, if (served) |hit| .{ .path = hit.path, .digest = hit.digest } else .{ .path = "", .digest = key });
        if (served != null and !request.verify) continue;
        unit.llvm = try unitText(a, unit);
        // The exact text key remains authoritative on every compile or verify.
        if (!std.mem.eql(u8, &key, &unit_cache.key(settings, unit.llvm))) return error.CacheMiss;
        const stem = try std.fs.path.join(a, &.{ places.staging, &std.fmt.bytesToHex(key, .lower) });
        // A miss compiles beside its store entry, so publishing is a rename even
        // when the store is on another file system than the work directory.
        const object = if (served != null) try std.fmt.allocPrint(a, "{s}.verify.o", .{stem}) else if (places.cacheable) try store.partial(a, native.io, key, ".o") else try std.fmt.allocPrint(a, "{s}.o", .{stem});
        const source = try std.fmt.allocPrint(a, "{s}.ll", .{stem});
        // Only units that compile are written out; a hit never rewrites its text.
        std.Io.Dir.cwd().writeFile(native.io, .{ .sub_path = source, .data = try instrumented(a, native.environment, unit.llvm) }) catch return error.WriteFailed;
        try pending.append(a, .{ .unit = unit, .key = key, .object = object, .slot = objects.items.len - 1, .served = served });
        try jobs.append(a, .{ .argv = try compileArguments(native, request.mode.level(), object, source), .weight = unit.llvm.len });
    }
    // Cached partials are removed after publication or failure. Uncached
    // objects remain in staging until the caller links and removes that tree.
    defer discardCachedPartials(native, places.cacheable, pending.items);
    try unit_cache.compileAll(native.resources(), jobs.items, unit_cache.width(native.environment, jobs.items.len));
    native.counts.processes += @intCast(jobs.items.len);
    for (jobs.items) |job| try native.log.appendSlice(a, job.log.items);
    for (jobs.items) |job| if (!job.ok) return error.ToolFailed;
    if (jobs.items.len != 0) try native.guard.check(native.log);
    for (pending.items) |item| {
        if (item.served) |hit| {
            try verifyServed(native, item, hit);
            continue;
        }
        native.counts.compiled += 1;
        const stored = if (places.cacheable) try store.publish(a, native.io, item.key, ".o", item.object) else try unit_cache.found(a, native.io, item.object);
        objects.items[item.slot] = .{ .path = stored.path, .digest = stored.digest };
    }
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

fn compileArguments(native: Native, level: []const u8, object: []const u8, source: []const u8) std.mem.Allocator.Error![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(native.arena, &.{ native.zig, "cc", "-c", level, "-target", target_policy.native_link_target });
    try argv.appendSlice(native.arena, target.cpu_flags);
    try argv.appendSlice(native.arena, layoutArguments(native.environment));
    try argv.appendSlice(native.arena, sanitizeArguments(native.environment));
    try argv.appendSlice(native.arena, &.{ "-Wno-override-module", "-o", object, source });
    return argv.items;
}

/// One `--link` source this build compiles, and where its depfile goes.
const Foreign = struct { manifest: []const u8, manifest_key: Digest, object: []const u8, depfile: []const u8, slot: usize };

/// Serve or compile every `--link` C source. A source is served only while its
/// bytes and those of every header its last depfile listed are unchanged.
/// Returns the dependencies a later build must find unchanged, or null when a
/// file changed while it compiled (nothing is then cached).
fn foreignObjects(native: Native, places: Places, settings: unit_cache.Settings, links: []const []const u8, objects: *std.ArrayList(Object)) Error!?[]const unit_cache.Dependency {
    if (links.len == 0) return &.{};
    const a = native.arena;
    const cwd = std.Io.Dir.cwd();
    const store: unit_cache.Store = .{ .directory = try std.fs.path.join(a, &.{ places.local, "foreign-v1" }) };
    cwd.createDirPath(native.io, store.directory) catch return error.WriteFailed;
    var dependencies: std.ArrayList(unit_cache.Dependency) = .empty;
    var compiles: std.ArrayList(Foreign) = .empty;
    var jobs: std.ArrayList(unit_cache.Job) = .empty;
    // A file whose status changes after this marker exists may differ from the
    // bytes its compile read, so its digest is not trusted (see `pinned`).
    const marker = try std.fs.path.join(a, &.{ places.staging, "foreign-marker" });
    cwd.writeFile(native.io, .{ .sub_path = marker, .data = "" }) catch return error.WriteFailed;
    const started = cwd.statFile(native.io, marker, .{}) catch return error.WriteFailed;
    const manifest_keys = try a.alloc(Digest, links.len);
    defer a.free(manifest_keys);
    for (links, manifest_keys) |source, *key| key.* = try foreignKey(native, settings, source);
    var claims: std.ArrayList(work_claim.Claim) = .empty;
    defer {
        for (claims.items) |*claim| claim.deinit();
        claims.deinit(a);
    }
    if (places.cacheable) {
        const ordered = try a.dupe(Digest, manifest_keys);
        defer a.free(ordered);
        std.mem.sort(Digest, ordered, {}, digestLess);
        try claims.ensureTotalCapacity(a, ordered.len);
        for (ordered, 0..) |key, index| {
            if (index != 0 and std.mem.eql(u8, &key, &ordered[index - 1])) continue;
            claims.appendAssumeCapacity(try work_claim.Claim.acquire(a, native.io, store.directory, key));
        }
    }
    for (links, 0..) |source, index| {
        const manifest_key = manifest_keys[index];
        const manifest = try store.path(a, manifest_key, ".deps");
        if (places.cacheable) if (try servedForeign(native, store, manifest_key, manifest)) |served| {
            try objects.append(a, served.object);
            try dependencies.appendSlice(a, served.dependencies);
            continue;
        };
        try objects.append(a, .{ .path = "", .digest = manifest_key });
        const stem = try std.fmt.allocPrint(a, "{s}/foreign-{d}", .{ places.staging, index });
        const object = try std.fmt.allocPrint(a, "{s}.o", .{stem});
        const depfile = try std.fmt.allocPrint(a, "{s}.d", .{stem});
        var argv: std.ArrayList([]const u8) = .empty;
        try argv.appendSlice(a, &.{ native.zig, "cc", "-c", settings.mode.level(), "-target", target_policy.native_link_target });
        try argv.appendSlice(a, target.cpu_flags);
        try argv.appendSlice(a, sanitizeArguments(native.environment));
        try argv.appendSlice(a, &.{ "-MMD", "-MF", depfile, "-o", object, source });
        try jobs.append(a, .{ .argv = argv.items, .weight = links.len - index });
        try compiles.append(a, .{ .manifest = manifest, .manifest_key = manifest_key, .object = object, .depfile = depfile, .slot = objects.items.len - 1 });
    }
    try unit_cache.compileAll(native.resources(), jobs.items, unit_cache.width(native.environment, jobs.items.len));
    native.counts.processes += @intCast(jobs.items.len);
    for (jobs.items) |job| try native.log.appendSlice(a, job.log.items);
    for (jobs.items) |job| if (!job.ok) return error.ToolFailed;
    if (jobs.items.len != 0) try native.guard.check(native.log);
    var stable = true;
    for (compiles.items) |compiled| {
        const fresh = try unit_cache.found(a, native.io, compiled.object);
        objects.items[compiled.slot] = .{ .path = fresh.path, .digest = fresh.digest };
        const inputs = try pinned(native, try readDepfile(native, compiled.depfile), started.ctime.nanoseconds) orelse {
            stable = false;
            continue;
        };
        try dependencies.appendSlice(a, inputs);
        if (!places.cacheable) continue;
        const text = try manifestText(a, inputs);
        const stored = try store.publish(a, native.io, objectKey(compiled.manifest_key, text), ".o", compiled.object);
        objects.items[compiled.slot] = .{ .path = stored.path, .digest = stored.digest };
        try atomicWrite(native, compiled.manifest, text);
    }
    return if (stable) dependencies.items else null;
}

const ServedForeign = struct { object: Object, dependencies: []const unit_cache.Dependency };

fn servedForeign(native: Native, store: unit_cache.Store, manifest_key: Digest, manifest: []const u8) Error!?ServedForeign {
    const a = native.arena;
    const text = std.Io.Dir.cwd().readFileAlloc(native.io, manifest, a, .limited(16 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const dependencies = try parseManifest(a, text) orelse return null;
    if (!try unit_cache.unchanged(a, native.io, dependencies)) return null;
    const found = try store.lookup(a, native.io, objectKey(manifest_key, text), ".o") orelse return null;
    return .{ .object = .{ .path = found.path, .digest = found.digest }, .dependencies = dependencies };
}

/// The manifest slot of one `--link` source: its absolute path and bytes, the
/// compile settings and the toolchain.
fn foreignKey(native: Native, settings: unit_cache.Settings, source: []const u8) Error!Digest {
    const a = native.arena;
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(native.io, source, a) catch source;
    const content = unit_cache.fileDigest(a, native.io, source) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ReadFailed => null,
    };
    var hash = std.crypto.hash.Blake3.init(.{});
    unit_cache.field(&hash, "core-foreign-v1");
    for (sanitizeArguments(native.environment)) |argument| unit_cache.field(&hash, argument);
    unit_cache.field(&hash, absolute);
    // The source's spelling and the working directory reach its debug information.
    unit_cache.field(&hash, source);
    unit_cache.field(&hash, std.Io.Dir.cwd().realPathFileAlloc(native.io, ".", a) catch "");
    unit_cache.field(&hash, if (content) |*digest| digest else "absent");
    unit_cache.field(&hash, settings.mode.level());
    unit_cache.field(&hash, target_policy.native_link_target);
    for (target.cpu_flags) |flag| unit_cache.field(&hash, flag);
    unit_cache.field(&hash, &settings.cpu);
    unit_cache.field(&hash, &settings.tool);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn objectKey(manifest_key: Digest, manifest: []const u8) Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    unit_cache.field(&hash, "core-foreign-object-v1");
    unit_cache.field(&hash, &manifest_key);
    unit_cache.field(&hash, manifest);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

const manifest_magic = "core-foreign-deps-v1\n";

fn manifestText(a: std.mem.Allocator, dependencies: []const unit_cache.Dependency) Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, manifest_magic);
    for (dependencies) |dependency| try text.print(a, "{s}\t{s}\n", .{ std.fmt.bytesToHex(dependency.digest.?, .lower), dependency.path });
    return text.items;
}

fn parseManifest(a: std.mem.Allocator, text: []const u8) Error!?[]const unit_cache.Dependency {
    const framed = std.mem.startsWith(u8, text, manifest_magic) and std.mem.endsWith(u8, text, "\n");
    if (!framed or text.len == manifest_magic.len) return null;
    var dependencies: std.ArrayList(unit_cache.Dependency) = .empty;
    var lines = std.mem.splitScalar(u8, text[manifest_magic.len .. text.len - 1], '\n');
    while (lines.next()) |line| {
        if (line.len < 66 or line[64] != '\t') return null;
        var digest: Digest = undefined;
        _ = std.fmt.hexToBytes(&digest, line[0..64]) catch return null;
        try dependencies.append(a, .{ .path = line[65..], .digest = digest });
    }
    return dependencies.items;
}

fn readDepfile(native: Native, path: []const u8) Error![]const []const u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(native.io, path, native.arena, .limited(16 << 20)) catch {
        try native.log.print(native.arena, "error: the C compiler wrote no dependency file {s}\n", .{path});
        return error.ToolFailed;
    };
    return unit_cache.depfileInputs(native.arena, bytes);
}

/// Digest every listed input by absolute path. A file whose status changed at or
/// after `since` (this build's marker, created before the compile started) may
/// differ from the bytes the compiler read, so the set is not pinned (null).
fn pinned(native: Native, inputs: []const []const u8, since: i96) Error!?[]const unit_cache.Dependency {
    const a = native.arena;
    const cwd = std.Io.Dir.cwd();
    const working = cwd.realPathFileAlloc(native.io, ".", a) catch return null;
    const dependencies = try a.alloc(unit_cache.Dependency, inputs.len);
    for (inputs, dependencies) |input, *dependency| {
        const absolute = try std.fs.path.resolve(a, &.{ working, input });
        const digest = unit_cache.fileDigest(a, native.io, absolute) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ReadFailed => return null,
        } orelse return null;
        const after = cwd.statFile(native.io, absolute, .{}) catch return null;
        if (after.ctime.nanoseconds >= since or after.mtime.nanoseconds >= since) return null;
        dependency.* = .{ .path = absolute, .digest = digest };
    }
    return dependencies;
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

/// The directory for content-keyed runtime and unit objects: `MYLANG_CORE_RUNTIME_CACHE`,
/// else `$XDG_CACHE_HOME/mylang/core-runtime`, else `$HOME/.cache/mylang/core-runtime`,
/// so a new project, a fresh worktree or a test's temporary directory reuses objects
/// another build compiled. Sharing is safe because every key is the object's complete
/// input. An empty `MYLANG_CORE_RUNTIME_CACHE`, no usable variable, or a directory that
/// cannot be created keeps the objects in `work`.
pub fn runtimeDirectory(allocator: std.mem.Allocator, io: std.Io, environ: *const std.process.Environ.Map, work: []const u8) Error![]const u8 {
    const directory = (try sharedRuntimeDirectory(allocator, environ)) orelse return work;
    std.Io.Dir.cwd().createDirPath(io, directory) catch return work;
    return directory;
}

fn sharedRuntimeDirectory(allocator: std.mem.Allocator, environ: *const std.process.Environ.Map) Error!?[]const u8 {
    if (environ.get("MYLANG_CORE_RUNTIME_CACHE")) |explicit| return if (explicit.len == 0) null else explicit;
    const parts: []const []const u8 = if (environ.get("XDG_CACHE_HOME")) |base| (if (std.fs.path.isAbsolute(base)) &.{ base, "mylang", "core-runtime" } else &.{}) else &.{};
    if (parts.len != 0) {
        const directory = try std.fs.path.join(allocator, parts);
        return directory;
    }
    const home = environ.get("HOME") orelse return null;
    if (!std.fs.path.isAbsolute(home)) return null;
    const directory = try std.fs.path.join(allocator, &.{ home, ".cache", "mylang", "core-runtime" });
    return directory;
}

/// A fresh directory `<work>/<prefix>-<nonce>` this build alone owns.
fn privateDirectory(allocator: std.mem.Allocator, io: std.Io, work: []const u8, prefix: []const u8) Error![]const u8 {
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const path = try std.fs.path.join(allocator, &.{ work, try std.fmt.allocPrint(allocator, "{s}-{s}", .{ prefix, std.fmt.bytesToHex(nonce, .lower) }) });
    std.Io.Dir.cwd().createDirPath(io, path) catch return error.WriteFailed;
    return path;
}

/// The runtime object for this runtime source, compiled on first use.
fn runtimeObject(native: Native, directory: []const u8, runtime: Runtime) Error!Object {
    const allocator = native.arena;
    const io = native.io;
    var digest: Digest = undefined;
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("core-runtime-object-v4\x00-O2\x00-g0\x00-falign-functions=64\x00-std=c11\x00");
    hash.update(target_policy.native_link_target);
    hash.update("\x00");
    hash.update(&runtime.abi);
    hash.update(&native.guard.identity.digest);
    hash.final(&digest);
    const stem = try std.fmt.allocPrint(allocator, "core_rt-{x}", .{digest});
    const object = try std.fs.path.join(allocator, &.{ directory, try std.fmt.allocPrint(allocator, "{s}.o", .{stem}) });
    const cwd = std.Io.Dir.cwd();
    var claim = try work_claim.Claim.acquire(allocator, io, directory, digest);
    defer claim.deinit();
    if (cwd.access(io, object, .{})) |_| return .{ .path = object, .digest = digest } else |_| {}
    const source = try std.fs.path.join(allocator, &.{ directory, try std.fmt.allocPrint(allocator, "{s}.c", .{stem}) });
    var nonce: [16]u8 = undefined;
    std.Io.random(io, &nonce);
    const staging = try std.fmt.allocPrint(allocator, "{s}.{x}.partial", .{ source, nonce });
    defer removeFile(io, staging);
    cwd.writeFile(io, .{ .sub_path = staging, .data = runtime.source }) catch return error.WriteFailed;
    cwd.rename(staging, cwd, source, io) catch return error.WriteFailed;
    const partial = try std.fmt.allocPrint(allocator, "{s}.{x}.partial", .{ object, nonce });
    defer removeFile(io, partial);
    var argv: std.ArrayList([]const u8) = .empty;
    // No debug info: the trap walker reads only `mylang-core` compile units, LLVM's
    // machine code does not depend on it, and it cost a cold build 0.46 s.
    try argv.appendSlice(allocator, &.{ native.zig, "cc", "-c", "-O2", "-g0", "-falign-functions=64" });
    try argv.appendSlice(allocator, &.{ "-target", target_policy.native_link_target });
    try argv.appendSlice(allocator, target.cpu_flags);
    try argv.appendSlice(allocator, layoutArguments(native.environment));
    try argv.appendSlice(allocator, sanitizeArguments(native.environment));
    try argv.appendSlice(allocator, &.{ "-std=c11", "-pthread", "-o", partial, source });
    try run(native, argv.items);
    try native.guard.check(native.log);
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
    native.counts.processes += 1;
    const result = @import("process_spawn.zig").run(native.arena, native.io, .{ .argv = argv, .environment = .{ .map = native.environment } }) catch |err| {
        try native.log.print(native.arena, "error: cannot run {s}: {s}\n", .{ argv[0], @errorName(err) });
        return error.ToolFailed;
    };
    try native.log.appendSlice(native.arena, result.stderr);
    const ok = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
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
    const dependencies = [_]unit_cache.Dependency{ .{ .path = "/src/value.c", .digest = @splat(1) }, .{ .path = "/src/with space.h", .digest = @splat(2) } };
    const text = try manifestText(a, &dependencies);
    const parsed = (try parseManifest(a, text)).?;
    try std.testing.expectEqual(@as(usize, 2), parsed.len);
    try std.testing.expectEqualStrings("/src/with space.h", parsed[1].path);
    try std.testing.expectEqual(dependencies[1].digest.?, parsed[1].digest.?);
    try std.testing.expectEqual(@as(?[]const unit_cache.Dependency, null), try parseManifest(a, text[0 .. text.len - 1]));
    try std.testing.expectEqual(@as(?[]const unit_cache.Dependency, null), try parseManifest(a, manifest_magic));
    try std.testing.expectEqual(@as(?[]const unit_cache.Dependency, null), try parseManifest(a, "core-foreign-deps-v0\n"));
    try std.testing.expect(!std.mem.eql(u8, &objectKey(@splat(3), text), &objectKey(@splat(3), try manifestText(a, dependencies[0..1]))));
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

// spec-case: LAYOUT-SWITCH-1
test "layout compile arguments and runtime identity include the internal alignment switch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    var log: std.ArrayList(u8) = .empty;
    var counts: Counts = .{};
    const native = testNative(a, &environment, &log, &counts);
    const default = try runtimeFor(a, false, &environment, &log);
    var expected: Digest = undefined;
    std.crypto.hash.Blake3.hash(runtime_source, &expected, .{});
    try std.testing.expectEqualSlices(u8, &expected, &default.abi);
    try environment.put("MYLANG_CORE_LAYOUT", "5");
    const aligned = try runtimeFor(a, false, &environment, &log);
    try std.testing.expect(!std.mem.eql(u8, &default.abi, &aligned.abi));
    const arguments = try compileArguments(native, "-O3", "out.o", "in.ll");
    try std.testing.expectEqualStrings("-mllvm", arguments[arguments.len - 6]);
    try std.testing.expectEqualStrings("-align-all-functions=5", arguments[arguments.len - 5]);
    try environment.put("MYLANG_CORE_LAYOUT", "7");
    try std.testing.expectError(error.ToolFailed, validateLayout(a, &environment, &log));
    try std.testing.expectEqualStrings("error: MYLANG_CORE_LAYOUT must be 4, 5 or 6\n", log.items);
}

// spec-case: NEW-CORE-S4-CACHE-1
test "publishOutput reports an unwritable output and servedForeign misses on damaged or stale manifests" {
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
    try std.testing.expectError(error.WriteFailed, publishOutput(native, program, try std.fs.path.join(a, &.{ root, "missing", "out" })));
    try std.testing.expect(std.mem.indexOf(u8, log.items, "cannot write") != null);
    try publishOutput(native, program, try std.fs.path.join(a, &.{ root, "out" }));
    try std.testing.expectEqualStrings("binary", try dir.dir.readFileAlloc(std.testing.io, "out", a, .limited(64)));
    const store: unit_cache.Store = .{ .directory = root };
    try std.testing.expectEqual(@as(?ServedForeign, null), try servedForeign(native, store, @splat(1), try std.fs.path.join(a, &.{ root, "absent.deps" })));
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "damaged.deps", .data = "core-foreign-deps-v1\nnot a line\n" });
    try std.testing.expectEqual(@as(?ServedForeign, null), try servedForeign(native, store, @splat(1), try std.fs.path.join(a, &.{ root, "damaged.deps" })));
    const stale = try manifestText(a, &.{.{ .path = program, .digest = @splat(7) }});
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
    var request: Request = .{ .zig = environment.get("MYLANG_ZIG") orelse "zig", .work = root, .output = "", .mode = .release, .links = &.{}, .units = &units };
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
    const original = try remarkKey(a, &store, identity, .release, &environment, "LLVM A");
    try std.testing.expect(!std.mem.eql(u8, &original, &try remarkKey(a, &store, identity, .release, &environment, "LLVM B")));
    try std.testing.expect(!std.mem.eql(u8, &original, &try remarkKey(a, &store, identity, .debug, &environment, "LLVM A")));
    identity.digest = @splat(4);
    try std.testing.expect(!std.mem.eql(u8, &original, &try remarkKey(a, &store, identity, .release, &environment, "LLVM A")));
    identity.digest = @splat(1);
    identity.native_target = @splat(5);
    try std.testing.expect(!std.mem.eql(u8, &original, &try remarkKey(a, &store, identity, .release, &environment, "LLVM A")));
    identity.native_target = @splat(3);
    try environment.put(layout_variable, "4");
    const laid_out = try remarkKey(a, &store, identity, .release, &environment, "LLVM A");
    try std.testing.expect(!std.mem.eql(u8, &original, &laid_out));
    try environment.put(sanitize_variable, "thread");
    try std.testing.expect(!std.mem.eql(u8, &laid_out, &try remarkKey(a, &store, identity, .release, &environment, "LLVM A")));
}
