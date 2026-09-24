//! Native builds invoke the compiler, QBE and Zig directly; no Python is needed.
const std = @import("std");
const builtin = @import("builtin");
const bundled = @import("qbe_build_assets");
const fs = @import("qbe_build_io.zig");
const options = @import("qbe_build_options.zig");
const backend = @import("qbe_build_backend.zig");
const cache_api = @import("qbe_build_cache.zig");
const outputs = @import("qbe_build_outputs.zig");
const v = @import("qbe_build_value.zig");
const frame_map = @import("qbe_frame_map.zig");
const native_link = @import("native_link.zig");
const lean = @import("qbe_build_units.zig");
const receipts = @import("qbe_build_receipt.zig");
const batch = @import("qbe_build_batch.zig");
const tool_spawn = @import("qbe_build_spawn.zig");
const direct_link = @import("qbe_build_link.zig");
const llvm_compile = @import("qbe_build_llvm_compile.zig");
const llvm_thin = @import("qbe_build_llvm_thin.zig");
/// The linker flag that drops every section a program never references.
const gc_sections = "-Wl,--gc-sections";
/// The manifest array that lists every emitted unit.
const manifest_functions = "functions";
/// Zig's bundled LLVM libunwind, linked statically into an LLVM frame-map
/// executable so a trap can unwind guest frames that keep no frame pointer.
/// The runtime names `_Unwind_Backtrace` and `_Unwind_GetIP` weakly, so a
/// program without libunwind still links; a weak reference pulls nothing out of
/// an archive, so the link asks for both symbols outright.
const unwind_link = [_][]const u8{ "-lunwind", "-Wl,-u,_Unwind_Backtrace", "-Wl,-u,_Unwind_GetIP" };
const module_syntax = @import("module_syntax.zig");
/// Build errors include frontend transport, native tools and manifest validation.
pub const Error = fs.Error || std.json.ParseError(std.json.Scanner) || outputs.Error ||
    @import("qbe_build_embed.zig").Error || cache_api.Error ||
    @import("memory_budget").Error ||
    error{ UnsupportedNativeHost, ZigVersionMismatch, InvalidNativeManifest };
/// The native ABI tag every manifest must carry, and the tag this driver's
/// generation identity is keyed by. The compiler core owns the same tag as
/// `native_test_dependencies.abi`; the two are one value that Zig's module
/// boundary will not let one file spell — a file belongs to one module, and
/// this driver is compiled both inside the compiler executable and as its own
/// `qbe_build` module. `src/aggref_abi_test.zig` is the join: a bump on either
/// side alone fails there rather than letting the driver accept a manifest the
/// core would not emit.
pub const native_abi = "mylang-qbe-native-v8";
const Record = struct { name: []const u8, symbol: []const u8, key: []const u8, object: []const u8, reused: bool };
/// Fixed runtime translation units archived together once per build environment.
const runtime_units = [_][]const u8{
    "qbe_runtime.c",    "native_heap.c",         "native_arena.c",  "native_collections.c", "native_text.c",   "native_dictionary.c",
    "qbe_stack.c",      "qbe_providers.c",       "qbe_resources.c", "native_equal.c",       "native_bytes.c",  "qbe_bytes.c",
    "native_regions.c", "qbe_arena.c",           "native_print.c",  "qbe_io.c",             "native_scoped.c", "qbe_grants.c",
    "qbe_files.c",      "native_text_methods.c", "qbe_stand_ins.c",
};
/// Execute a native build using process-owned allocation and I/O policy.
pub fn run(process: std.process.Init, args: []const []const u8) Error!u8 {
    return runMeasured(process, args, null);
}
/// Execute a native build and, when `phases` is non-null, hand its measured
/// phase durations to the caller instead of writing any timing record. The
/// caller owns the `phase-timings-v1` shape, so `--timings=json` cannot drift
/// from the records `run` and `run-project` write.
pub fn runMeasured(process: std.process.Init, args: []const []const u8, phases: ?*PhaseTimings) Error!u8 {
    if (args.len == 1 and std.mem.eql(u8, args[0], "--help")) {
        try std.Io.File.stdout().writeStreamingAll(process.io, options.usage);
        return 0;
    }
    // RELEASE-CHECKED-1: name the removed policy instead of dumping usage.
    if (options.uncheckedRequested(args)) {
        try std.Io.File.stderr().writeStreamingAll(process.io, "mylang build: " ++ options.unchecked_removed);
        return 2;
    }
    const parsed = options.parse(args) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, options.usage);
        return 2;
    };
    try checkHost(builtin.os.tag, builtin.cpu.arch);
    // Build scratch is freed here, not at process exit: a long-lived host that
    // rebuilds its guest on every reload must reclaim each build, so the context
    // owns a reclaiming arena over `gpa` rather than the process's own arena.
    var context = try fs.Context.init(process.gpa, process.io, process.environ_map);
    defer context.deinit();
    const controls = try runtimeControls(context.allocator, args);
    return build(context, parsed, controls, phases);
}
/// The four phase durations a build measures for `--report`, in seconds. A
/// command that asked for `phase-timings-v1` records receives them here instead
/// of the driver writing them, so one module owns the JSON Lines shape. A field
/// stays null when its phase never ran, and `complete` says whether every phase
/// did: a build refused by the frontend names only `frontend`, while a linked
/// artifact names all four.
pub const PhaseTimings = struct {
    frontend: ?f64 = null,
    codegen: ?f64 = null,
    link: ?f64 = null,
    native: ?f64 = null,
    complete: bool = false,
};
/// Collect runtime/authority controls from a `build --run` command line. They
/// travel to the temporary executable in `MYLANG_OPTIONS` and are revalidated by
/// the native runtime; the values after `--` are the program's own arguments.
fn runtimeControls(allocator: std.mem.Allocator, args: []const []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    for (args) |argument| {
        if (std.mem.eql(u8, argument, "--")) break;
        if (options.runtimeControl(argument)) try list.append(allocator, argument);
    }
    return list.toOwnedSlice(allocator);
}
/// A resolved toolchain and object cache, reusable across many native builds, and
/// the cache root whose generation families (`objects`, `run`, `exe`) hold its output.
pub const Prepared = struct { cache: cache_api.Cache, zig_version: []const u8, root: []const u8 };
/// Resolve the native tools, publish the bundled runtime tree, and open the object cache.
/// The returned cache owns a private staging directory; release it with `context.remove`.
pub fn prepare(context: fs.Context, parsed: options.Options) Error!Prepared {
    const a = context.allocator;
    const zig = try context.executable(parsed.zig);
    const selected = try backend.resolve(context, parsed, zig);
    const version = try context.capture(&.{ zig, "version" });
    if (fs.exitCode(version.term) != 0) return error.NativeToolFailed;
    const zig_version = std.mem.trim(u8, version.stdout, "\r\n ");
    try checkVersion(zig_version);
    const directory = try cacheRoot(context, parsed);
    try context.mkdir(directory);
    const assets = try materializeRuntime(context, parsed, directory);
    const temporary = try context.temporary(directory);
    const environment = try environmentJson(a, .{
        .zig = try context.stamp(zig),
        .backend = selected.name,
        .backend_tool = selected.tool_identity,
        .optimization = selected.optimization,
        .lto = selected.lto,
        .zig_version = zig_version,
        .mode = parsed.mode,
        .target = parsed.target,
        .target_cpu = selected.target_cpu,
        .target_features = selected.target_features,
    });
    // Objects live in this driver's generation; opening it evicts every other
    // one no process still leases.
    const objects = try generation(context, directory, "objects", generation_identity);
    return .{
        .cache = .{
            .context = context,
            .directory = objects,
            .temporary = temporary,
            .assets = assets,
            .environment = environment,
            .zig = zig,
            .mode = parsed.mode,
            .codegen = .{ .tool = selected.tool, .llvm = std.mem.eql(u8, selected.name, "llvm"), .optimization = selected.optimization, .lto = selected.lto, .target_cpu = selected.target_cpu, .target_features = selected.target_features },
        },
        .zig_version = zig_version,
        .root = directory,
    };
}
/// The per-invocation half of an object's build environment: the resolved tool
/// stamps and the requested build mode and target.
const Environment = struct {
    zig: []const u8,
    backend: []const u8,
    backend_tool: []const u8,
    optimization: []const u8,
    lto: options.Lto,
    zig_version: []const u8,
    mode: []const u8,
    target: []const u8,
    target_cpu: []const u8 = "",
    target_features: []const u8 = "",
};
/// Encode everything besides a unit's own IL that decides the object bytes. It
/// names the *native driver* identity rather than the whole compiler: objects are
/// already content addressed by the IL the frontend emitted, the runtime sources
/// are covered by `runtime`, the tools by their stamps and the link flags by the
/// cache contract, so an edit to a compiler source that cannot change how IL
/// becomes an object must not evict every cached object and executable.
fn environmentJson(allocator: std.mem.Allocator, per_build: Environment) Error![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "zig-native-build-v3",
        .abi = native_abi,
        .driver = bundled.driver_identity,
        .runtime = bundled.content_hash,
        .zig = per_build.zig,
        .backend = per_build.backend,
        .backend_tool = per_build.backend_tool,
        .optimization = per_build.optimization,
        .lto = per_build.lto,
        .zig_version = per_build.zig_version,
        .mode = per_build.mode,
        .target = per_build.target,
        .target_cpu = per_build.target_cpu,
        .target_features = per_build.target_features,
    }, .{});
}
/// Validate one emitted manifest and link it into `output`, reporting whether the file changed.
pub fn assemble(cache: cache_api.Cache, parsed: options.Options, manifest: std.json.Value, output: []const u8) Error!bool {
    try validate(cache.context.allocator, manifest);
    var state = State{ .context = cache.context, .cache = cache, .manifest = manifest };
    try state.compile(parsed);
    return state.link(parsed, output);
}
/// The frontend that emits a guest's QBE units. A host application is its own
/// frontend, so `/proc/self/exe emit-project-qbe` emits them; `MYLANG_HOST_COMPILER`
/// overrides that with an explicit compiler, which a host running from a binary
/// that is not itself a compiler — a Zig test binary — must supply.
fn frontendCompiler(context: fs.Context) fs.Error![]const u8 {
    if (context.environ.get("MYLANG_HOST_COMPILER")) |path| return context.allocator.dupe(u8, path);
    return std.Io.Dir.cwd().realPathFileAlloc(context.io, "/proc/self/exe", context.allocator);
}
fn build(context: fs.Context, parsed: options.Options, controls: []const []const u8, phases: ?*PhaseTimings) !u8 {
    const a = context.allocator;
    const prepared = prepare(context, parsed) catch |err| switch (err) {
        error.NativeToolFailed => return 2,
        else => return err,
    };
    const cache = prepared.cache;
    const temporary = cache.temporary;
    defer context.remove(temporary);
    const start = std.Io.Timestamp.now(context.io, .awake);
    // An internal `--manifest-file` names an already checked frontend manifest,
    // so the frontend is not spawned again and its check is consumed directly.
    const checked_manifest = manifestFile(parsed.link_arguments);
    const manifest_bytes = if (checked_manifest) |path| try context.read(path) else frontend: {
        // The frontend child reuses its persistent content-addressed cache by default.
        // An explicit `--cache-dir` keeps the frontend under that same root; the
        // `no_cache` sentinel disables reuse for this build.
        // `build` follows `run`'s project detection: a source that opens as a
        // module loads its imports rather than being treated as one unit, so the
        // entry needs no `--project` spelling.
        var project = parsed.project;
        if (!project) project = module_syntax.usesModuleSyntax(try context.read(try context.absolute(parsed.source)));
        const compiler = try frontendCompiler(context);
        var arguments: std.ArrayList([]const u8) = .empty;
        try arguments.appendSlice(a, &.{ compiler, if (project) "emit-project-qbe" else "emit-qbe", try context.absolute(parsed.source) });
        // A project's units stay in the compiler's fragment store; the manifest
        // names each text and its metadata by digest (`QBE-FRAGMENT-REUSE-1`,
        // `EMIT-META-1`), and an executable's leaves out library-only facts.
        if (project) try arguments.append(a, leanManifestFlag(parsed));
        if (std.mem.eql(u8, parsed.cache, options.no_cache)) {
            try arguments.append(a, "--no-cache");
        } else if (!std.mem.eql(u8, parsed.cache, options.default_cache)) {
            try arguments.append(a, try std.fmt.allocPrint(a, "--cache-dir={s}", .{parsed.cache}));
        }
        // A ReleaseFast `build` drops `debug` lines in lowering; `run` keeps them.
        if (!parsed.run and std.mem.eql(u8, parsed.mode, release_fast)) try arguments.append(a, "--drop-debug");
        // A ReleaseFast executable was not asked for an instruction ceiling, so it
        // drops step-budget accounting. A library always keeps it: the embed API
        // and the guest-test runner always run under a finite budget.
        const fast_executable = !parsed.library and !stepAccounting(parsed.link_arguments) and std.mem.eql(u8, parsed.mode, release_fast);
        if (fast_executable) try arguments.append(a, "--drop-step-checks");
        // The same reasoning for call depth: a ReleaseFast executable that was not
        // asked for a frame ceiling carries no depth accounting, and its entry
        // refuses one at run time. A library always keeps it.
        const frame_accounted = frameAccounting(parsed.link_arguments);
        if (fast_executable and !frame_accounted) try arguments.append(a, "--drop-frame-checks");
        if (selectFile(parsed.link_arguments)) |path| {
            try arguments.append(a, try std.fmt.allocPrint(a, "--select-file={s}", .{path}));
            // Forward the work-report request for selective test builds so native-test
            // parents observe the frontend's real lowering/emission counts.
            if (parsed.report) try arguments.append(a, "--report");
        }
        const generated = try context.capture(arguments.items);
        const code = fs.exitCode(generated.term);
        if (code != 0) {
            // A refused source still reports the phase that refused it.
            if (phases) |measured| measured.frontend = seconds(context, start);
            return code;
        }
        break :frontend generated.stdout;
    };
    // A consumed manifest reports no frontend time because no frontend ran.
    const frontend = if (checked_manifest != null) 0 else seconds(context, start);
    const native_start = std.Io.Timestamp.now(context.io, .awake);
    const output = if (parsed.run) try std.fs.path.join(a, &.{ temporary, "program" }) else try context.absolute(parsed.output);
    // BUILD-NOOP-1: the same manifest under the same environment, flags and
    // untouched output is already built; nothing below would change a byte.
    const receipt = receipts.Receipt.init(context, parsed, try receiptIdentity(a, cache), manifest_bytes, output);
    if (unchanged(receipt, phases, frontend)) return 0;
    const manifest = (try std.json.parseFromSlice(std.json.Value, a, manifest_bytes, .{ .allocate = .alloc_always })).value;
    try validate(a, manifest);
    var state = State{ .context = context, .cache = cache, .manifest = manifest };
    const codegen_start = std.Io.Timestamp.now(context.io, .awake);
    try state.compile(parsed);
    const codegen = seconds(context, codegen_start);
    const link_start = std.Io.Timestamp.now(context.io, .awake);
    const changed = try state.link(parsed, output);
    if (receipt) |built| built.record();
    const link = seconds(context, link_start);
    if (parsed.report) {
        const objects = try functionObjects(a, state.records.items);
        const report = try std.json.Stringify.valueAlloc(a, .{
            .version = "qbe-build-v1",
            .output = output,
            .output_changed = changed,
            .compiled_functions = state.records.items.len - state.reused,
            .reused_functions = state.reused,
            .function_objects = objects.total,
            .compiled_function_objects = objects.compiled,
            .runtime_reused = state.runtime.reused,
            .runtime_installed = state.runtime_installed,
            .metadata_reused = state.metadata_reused,
            .link_route = routeName(state.link_route),
            .functions = state.records.items,
            .frontend_seconds = frontend,
            .codegen_seconds = codegen,
            .link_seconds = link,
            .native_seconds = seconds(context, native_start),
            .target = parsed.target,
            .mode = parsed.mode,
            .zig_version = prepared.zig_version,
            .artifact_kind = if (parsed.library) "shared-library" else "executable",
            .backend = if (cache.codegen.llvm) "llvm" else "qbe",
            .optimization = cache.codegen.optimization,
            .lto = cache.codegen.lto.on(),
            .thin_lto = cache.codegen.lto == .thin,
        }, .{});
        const stream = if (parsed.run) std.Io.File.stderr() else std.Io.File.stdout();
        try stream.writeStreamingAll(context.io, try std.fmt.allocPrint(a, "{s}\n", .{report}));
    }
    // The four phases `--report` already measures, handed to a caller that asked
    // for `phase-timings-v1` records.
    if (phases) |measured| {
        measured.frontend = frontend;
        measured.codegen = codegen;
        measured.link = link;
        measured.native = seconds(context, native_start);
        measured.complete = true;
    }
    if (parsed.run) return spawnParts(context, output, controls, parsed);
    return 0;
}
/// Whether this build's receipt says its output is already exactly what it
/// would produce (`BUILD-NOOP-1`). A skipped build still reports its frontend
/// phase, and codegen, link and native phases that did no work.
fn unchanged(receipt: ?receipts.Receipt, phases: ?*PhaseTimings, frontend: f64) bool {
    const recorded = receipt orelse return false;
    switch (recorded.state()) {
        .fresh => {
            if (phases) |measured| measured.* = .{ .frontend = frontend, .codegen = 0, .link = 0, .native = 0, .complete = true };
            return true;
        },
        // Something replaced the output this manifest built: the link's own
        // reuse check trusts the sidecar, so the stranger must go first.
        .replaced => recorded.discard(),
        .unknown => {},
    }
    return false;
}
/// Everything besides the manifest and the build flags that decides a build's
/// output: this driver's generation (driver, runtime and native ABI) and the
/// resolved tool, mode, target and backend environment of every object.
fn receiptIdentity(a: std.mem.Allocator, cache: cache_api.Cache) Error![]const u8 {
    return std.mem.concat(a, u8, &.{ generation_identity, "\x00", cache.environment });
}
/// How many distinct objects hold the guest functions, and how many of them
/// this build compiled: one per function on the LLVM arm, one per batch on QBE.
const ObjectCounts = struct { total: usize, compiled: usize };
fn functionObjects(allocator: std.mem.Allocator, records: []const Record) !ObjectCounts {
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var counts: ObjectCounts = .{ .total = 0, .compiled = 0 };
    for (records) |record| {
        if ((try seen.getOrPut(allocator, record.object)).found_existing) continue;
        counts.total += 1;
        counts.compiled += @intFromBool(!record.reused);
    }
    return counts;
}
/// Find an internal `--select-file=PATH` in the original build arguments. The
/// selective frontend input is intentionally not stored in `Options`, whose
/// field count is frozen by the repository's type-size ratchet.
fn selectFile(args: []const []const u8) ?[]const u8 {
    for (args) |argument| if (std.mem.startsWith(u8, argument, "--select-file=")) return argument["--select-file=".len..];
    return null;
}

/// Find an internal `--manifest-file=PATH` in the original build arguments. It
/// names a checked frontend manifest, so the driver skips the frontend child.
fn manifestFile(args: []const []const u8) ?[]const u8 {
    for (args) |argument| if (std.mem.startsWith(u8, argument, "--manifest-file=")) return argument["--manifest-file=".len..];
    return null;
}

/// Whether the build arguments ask for instruction step accounting, either by
/// naming a ceiling directly or with the explicit `--step-accounting` a host
/// application passes because it always runs its guest under `--max-steps=`.
/// Whether the build was asked for a call-depth ceiling, by flag or by `--max-frames`.
fn frameAccounting(args: []const []const u8) bool {
    for (args) |argument| {
        if (std.mem.eql(u8, argument, "--")) break;
        if (std.mem.startsWith(u8, argument, "--max-frames")) return true;
        if (std.mem.eql(u8, argument, "--frame-accounting")) return true;
    }
    return false;
}
fn stepAccounting(args: []const []const u8) bool {
    for (args) |argument| {
        if (std.mem.eql(u8, argument, "--")) break;
        if (std.mem.startsWith(u8, argument, "--max-steps")) return true;
        if (std.mem.eql(u8, argument, "--step-accounting")) return true;
    }
    return false;
}

// spec-case: QBE-STEP-ACCOUNTING-1
test "a build argument naming a step ceiling keeps its accounting" {
    try std.testing.expect(stepAccounting(&.{ "main.my", "--max-steps=100" }));
    try std.testing.expect(stepAccounting(&.{ "main.my", "--step-accounting", "-o", "out" }));
    try std.testing.expect(!stepAccounting(&.{ "main.my", "-o", "out" }));
    // A ceiling after `--` belongs to the guest, not to this build.
    try std.testing.expect(!stepAccounting(&.{ "main.my", "--", "--max-steps=1" }));
}

/// The argument vector for one built program and the options it was given.
pub fn command(context: fs.Context, output: []const u8, arguments: []const []const u8) Error![]const []const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(context.allocator, output);
    try argv.appendSlice(context.allocator, arguments);
    return argv.items;
}
/// Translate a guest program's termination into the status its command reports.
pub fn status(term: std.process.Child.Term) u8 {
    return switch (term) {
        .exited => |code| code,
        .signal => |signal| @intCast(@min(255, 128 + @as(u32, @backingInt(signal)))),
        else => 2,
    };
}
/// The byte ceiling one guest process runs under: `--max-memory` first, then
/// `MYLANG_MEMORY_LIMIT`, then the single-guest default.
pub fn ceiling(context: fs.Context, parsed: options.Options) Error!*const std.process.Environ.Map {
    const budget = @import("memory_budget");
    return context.bounded(try budget.resolve(parsed.max_memory, context.environ, budget.variable, budget.run_default));
}
/// The channel a built program's runtime options travel in.
pub const runtime_options = @import("runtime_options.zig");
/// How one built program is started: the argument vector it receives and the
/// environment that carries its byte ceiling and runtime options.
pub const Launch = struct { argv: []const []const u8, environ: *const std.process.Environ.Map };
/// Start `output` from a launcher's command tail: the runtime options before the
/// tail's first `--` travel in `MYLANG_OPTIONS`, replacing any inherited value,
/// and only the values after it reach the program's argv, so a built program
/// never has to tell its own arguments apart from the runtime's.
pub fn launch(context: fs.Context, output: []const u8, arguments: []const []const u8, parsed: options.Options) Error!Launch {
    const tail = runtime_options.split(arguments);
    const environment = try context.allocator.create(std.process.Environ.Map);
    environment.* = try (try ceiling(context, parsed)).clone(context.allocator);
    try runtime_options.apply(context.allocator, environment, tail.options);
    return .{ .argv = try command(context, output, tail.program), .environ = environment };
}
/// Run a built program with the arguments it was given, under its byte ceiling.
pub fn spawn(context: fs.Context, output: []const u8, parsed: options.Options) Error!u8 {
    return spawnParts(context, output, &.{}, parsed);
}
/// Spawn with runtime controls collected before the guest delimiter.
fn spawnParts(context: fs.Context, output: []const u8, controls: []const []const u8, parsed: options.Options) Error!u8 {
    var arguments: std.ArrayList([]const u8) = .empty;
    try arguments.appendSlice(context.allocator, controls);
    if (parsed.arguments.len == 0 or !std.mem.eql(u8, parsed.arguments[0], "--")) try arguments.append(context.allocator, "--");
    try arguments.appendSlice(context.allocator, parsed.arguments);
    const started = try launch(context, output, arguments.items, parsed);
    var child = try std.process.spawn(context.io, .{ .argv = started.argv, .environ_map = started.environ });
    return status(try child.wait(context.io));
}
/// The native object-cache directory. `--no-cache` is a frontend-reuse sentinel,
/// so the native cache still uses its default directory instead of materializing
/// a directory named after the sentinel while the frontend child is told to
/// disable reuse.
fn nativeCacheDirectory(parsed: options.Options) []const u8 {
    return if (std.mem.eql(u8, parsed.cache, options.no_cache)) options.default_cache else parsed.cache;
}
/// The absolute cache root a build's generations, runtime tree and staging live under.
pub fn cacheRoot(context: fs.Context, parsed: options.Options) fs.Error![]const u8 {
    return context.absolute(nativeCacheDirectory(parsed));
}
/// The generation every cache family is keyed by: the *native driver* identity —
/// the build-driver and link-policy sources, the Zig version and the optimize mode
/// — and the runtime the compiler bundles. An ordinary compiler edit no longer
/// opens a generation, because it cannot change how already-emitted IL becomes an
/// object or an executable; only an edit to the driver itself, a changed runtime
/// or a new native ABI does. Tool stamps, mode and target stay in each entry's key
/// but not here, so every process of one compiler build — whichever path it
/// resolved its tools from, whichever mode it asked for — shares one generation.
pub const generation_identity = "zig-qbe-build-v2\x00" ++ native_abi ++ "\x00" ++ bundled.driver_identity ++ "\x00" ++ bundled.content_hash;
/// One directory under `<root>/<family>` for everything one generation produces,
/// named by the hash of `identity`. Opening a generation leases it for the rest of
/// this process, then evicts every sibling no other process leases: a new driver
/// can no longer hit those entries by their keys, so a cache root holds at most one
/// live generation per family plus whatever concurrent builds still hold. An
/// existing generation is leased and returned without a sweep, so a warm build pays
/// one `stat` and one lock.
pub fn generation(context: fs.Context, root: []const u8, family: []const u8, identity: []const u8) fs.Error![]const u8 {
    const a = context.allocator;
    const parent = try std.fs.path.join(a, &.{ root, family });
    const current = try fs.hash(a, identity);
    const path = try std.fs.path.join(a, &.{ parent, current });
    if (context.exists(path)) {
        context.lease(path);
        return path;
    }
    try context.mkdir(path);
    context.lease(path);
    context.sweep(parent, current);
    return path;
}
/// The directory that holds the materialized runtime source trees. An explicit
/// `--cache-dir` keeps it hermetically under that directory; a default build shares
/// a user-level location (`$XDG_CACHE_HOME/mylang/runtime`, else `$HOME/.cache/...`)
/// so a fresh project reuses the tree another project already derived, and falls
/// back to the per-project cache when neither variable is set.
fn runtimeRoot(context: fs.Context, parsed: options.Options, directory: []const u8) fs.Error![]const u8 {
    const local = try std.fs.path.join(context.allocator, &.{ directory, "runtime" });
    if (!std.mem.eql(u8, nativeCacheDirectory(parsed), options.default_cache)) return local;
    return sharedRuntimeRoot(context) orelse local;
}
/// The user-level shared runtime location, or null when no home directory names it.
fn sharedRuntimeRoot(context: fs.Context) ?[]const u8 {
    const a = context.allocator;
    if (context.environ.get("XDG_CACHE_HOME")) |base| {
        if (base.len != 0 and std.fs.path.isAbsolute(base)) return std.fs.path.join(a, &.{ base, "mylang", "runtime" }) catch null;
    }
    if (context.environ.get("HOME")) |home| {
        if (home.len != 0 and std.fs.path.isAbsolute(home)) return std.fs.path.join(a, &.{ home, ".cache", "mylang", "runtime" }) catch null;
    }
    return null;
}
/// Publish the bundled runtime tree once per content hash and reuse it afterwards.
/// Concurrent builds stage into private directories and rename, so a shared cache
/// never observes a partial tree; a lost race simply reuses the winner's tree.
fn materialize(context: fs.Context, root: []const u8) ![]const u8 {
    const a = context.allocator;
    const directory = try std.fs.path.join(a, &.{ root, bundled.content_hash });
    if (context.exists(directory)) return directory;
    try context.mkdir(root);
    const staging = try context.temporary(root);
    for (bundled.files) |asset| {
        const path = try std.fs.path.join(a, &.{ staging, asset.path });
        try context.mkdir(std.fs.path.dirname(path).?);
        try context.write(path, asset.bytes);
    }
    context.rename(staging, directory) catch |err| {
        context.remove(staging);
        if (!context.exists(directory)) return err;
    };
    // A successful rename moved the whole staging child into place; reclaim the
    // shared `.pending/` folder it came from so it does not outlive the build.
    context.remove(staging);
    return directory;
}
/// Publish the bundled runtime tree, preferring the shared user cache but falling
/// back to the per-project cache when that location cannot be written (for example
/// a read-only home directory). An explicit `--cache-dir` already resolves locally.
fn materializeRuntime(context: fs.Context, parsed: options.Options, directory: []const u8) Error![]const u8 {
    const shared = try runtimeRoot(context, parsed, directory);
    const local = try std.fs.path.join(context.allocator, &.{ directory, "runtime" });
    if (std.mem.eql(u8, shared, local)) return materialize(context, shared);
    const published = materialize(context, shared) catch null;
    return published orelse materialize(context, local);
}
/// The portable identity of a prebuilt runtime artifact: the runtime source content
/// hash, the pinned Zig version, the optimize mode, the backend/flavor tag and the
/// target. It excludes the tool file stamps the object cache keys on, so an archive
/// installed at build time still matches a later build that resolved its tools from a
/// different path. The flavor keeps a QBE archive from ever being linked into an
/// LLVM build (or an LTO archive into a non-LTO one).
fn runtimeInstalledHash(a: std.mem.Allocator, kind: []const u8, mode: []const u8, flavor: []const u8) fs.Error![]const u8 {
    const encoded = try std.json.Stringify.valueAlloc(a, .{ "mylang-runtime-installed-v1", kind, flavor, bundled.content_hash, bundled.zig_version, mode, "amd64_sysv" }, .{});
    return fs.hash(a, encoded);
}
/// The LTO optimization flags `zig cc` passes LLD for one `-O` level, so the
/// frame map's LTO-to-assembly step optimizes exactly as the ordinary link
/// would: Zig maps `-O1`..`-O3` to ReleaseFast (`--lto-O3`), `-Os`/`-Oz` to a
/// size mode (`--lto-O2`), and `-O0` to LLD's default.
fn ltoLevel(optimization: []const u8) []const []const u8 {
    if (std.mem.eql(u8, optimization, "0")) return &.{};
    if (std.mem.eql(u8, optimization, "s") or std.mem.eql(u8, optimization, "z")) return &.{ "--lto-O2", "-O2" };
    return &.{ "--lto-O3", "-O3" };
}
/// The backend/flavor tag an archive is keyed by: QBE, LLVM without LTO, or LLVM
/// with full or thin LTO. The text-formatter object is backend-independent and uses none.
fn runtimeFlavor(lo: bool, lto: options.Lto) []const u8 {
    if (!lo) return "qbe";
    return switch (lto) {
        .off => "llvm",
        .full => "llvm-lto",
        .thin => "llvm-thinlto",
    };
}
/// Resolve a prebuilt runtime artifact installed under `<compiler>/../lib/mylang-runtime`.
/// Returns it only when the file exists and its stored fingerprint still matches, so a
/// removed, cross-target or corrupted install falls back to compiling from source.
fn installedRuntime(context: fs.Context, mode: []const u8, kind: []const u8, flavor: []const u8, extension: []const u8) fs.Error!?cache_api.Object {
    const a = context.allocator;
    if (context.self_directory.len == 0) return null;
    const parent = std.fs.path.dirname(context.self_directory) orelse return null;
    const hash = try runtimeInstalledHash(a, kind, mode, flavor);
    const path = try std.fmt.allocPrint(a, "{s}/lib/mylang-runtime/{s}{s}", .{ parent, hash, extension });
    if (!validInstalled(context, path)) return null;
    return .{ .key = hash, .path = path, .reused = true };
}
/// A prebuilt artifact is trusted only when a fingerprint over its length and contents
/// matches the `.digest` published beside it, mirroring the object cache's own check.
fn validInstalled(context: fs.Context, path: []const u8) bool {
    const bytes = context.read(path) catch return false;
    if (bytes.len == 0) return false;
    const checksum = std.fmt.allocPrint(context.allocator, "{s}.digest", .{path}) catch return false;
    const stored = context.read(checksum) catch return false;
    const actual = fs.digest(context.allocator, bytes) catch return false;
    return std.mem.eql(u8, stored, actual);
}
/// One prebuilt runtime archive flavor: the optimize mode, the cache-key tag that
/// keeps QBE, LLVM and LLVM+LTO archives apart, and the codegen that builds it.
const RuntimeFlavor = struct { mode: []const u8, flavor: []const u8, llvm: bool, lto: options.Lto };
/// Every runtime archive `zig build` publishes: QBE for the Debug and explicit-QBE
/// arms, and both LLVM arms for ReleaseFast, so the release path links a bitcode
/// runtime archive instead of compiling one on its first build.
const runtime_flavors = [_]RuntimeFlavor{
    .{ .mode = "Debug", .flavor = "qbe", .llvm = false, .lto = .off },
    .{ .mode = release_fast, .flavor = "qbe", .llvm = false, .lto = .off },
    .{ .mode = release_fast, .flavor = "llvm", .llvm = true, .lto = .off },
    .{ .mode = release_fast, .flavor = "llvm-lto", .llvm = true, .lto = .full },
    .{ .mode = release_fast, .flavor = "llvm-thinlto", .llvm = true, .lto = .thin },
};
/// Build the runtime archive and text-formatter object for each optimize mode and
/// backend flavor and publish them, hashed by their portable identity, into `--out`
/// so `zig build` can install them beside the compiler. `--work` names a scratch
/// cache the step discards. A later `mylang build` links a matching install directly
/// instead of compiling it. Every flavor is published: the LLVM ones need nothing
/// beyond Zig, because the translator is part of this compiler (LLVM-ZIG-1).
pub fn emitRuntime(process: std.process.Init, args: []const []const u8) Error!u8 {
    var context = try fs.Context.init(process.gpa, process.io, process.environ_map);
    defer context.deinit();
    const a = context.allocator;
    var zig_path: []const u8 = "zig";
    var qbe_path: []const u8 = "qbe";
    var out: []const u8 = "";
    var work: []const u8 = "";
    var index: usize = 0;
    while (index + 1 < args.len) : (index += 2) {
        const flag = args[index];
        const value = args[index + 1];
        if (std.mem.eql(u8, flag, "--zig")) {
            zig_path = value;
        } else if (std.mem.eql(u8, flag, "--qbe")) {
            qbe_path = value;
        } else if (std.mem.eql(u8, flag, "--out")) {
            out = value;
        } else if (std.mem.eql(u8, flag, "--work")) {
            work = value;
        } else return 2;
    }
    if (out.len == 0 or work.len == 0) return 2;
    out = try context.absolute(out);
    try checkHost(builtin.os.tag, builtin.cpu.arch);
    for (runtime_flavors) |flavor| {
        const parsed: options.Options = .{
            .source = "runtime",
            .output = "runtime",
            .zig = zig_path,
            .codegen = if (flavor.llvm) .{ .llvm = .{ .optimization = "3", .lto = flavor.lto } } else .{ .qbe = qbe_path },
            .cache = try std.fs.path.join(a, &.{ work, flavor.mode, flavor.flavor }),
            .mode = flavor.mode,
        };
        const prepared = prepare(context, parsed) catch |err| switch (err) {
            error.NativeToolFailed => return 2,
            else => return err,
        };
        defer context.remove(prepared.cache.temporary);
        const archive = try prepared.cache.library("runtime", &runtime_units);
        try publishInstalled(context, archive.path, out, try runtimeInstalledHash(a, "archive", flavor.mode, flavor.flavor), ".a");
        const format = try prepared.cache.object("format", "native_format.zig", .zig_file);
        try publishInstalled(context, format.path, out, try runtimeInstalledHash(a, "format", flavor.mode, ""), ".o");
    }
    return 0;
}
/// Copy one built artifact into the install-staging directory under its portable hash
/// and publish a fingerprint beside it, so a later build can trust the installed file.
fn publishInstalled(context: fs.Context, source: []const u8, out: []const u8, hash: []const u8, extension: []const u8) Error!void {
    const a = context.allocator;
    const bytes = try context.read(source);
    const dest = try std.fmt.allocPrint(a, "{s}/{s}{s}", .{ out, hash, extension });
    try context.write(dest, bytes);
    try context.atomic(try std.fmt.allocPrint(a, "{s}.digest", .{dest}), try fs.digest(a, bytes));
}
fn seconds(context: fs.Context, start: std.Io.Timestamp) f64 {
    return @as(f64, @floatFromInt(start.durationTo(std.Io.Timestamp.now(context.io, .awake)).nanoseconds)) / 1e9;
}
/// Refuse a manifest with the wrong version or ABI, a malformed or repeated
/// unit symbol, or an executable entry no unit defines. Repeats are found with
/// a set, so a manifest of thousands of units costs one pass, not a quadratic scan.
fn validate(allocator: std.mem.Allocator, manifest: std.json.Value) !void {
    if (!std.mem.eql(u8, v.text(v.get(manifest, "version")), "qbe-units-v1")) return error.InvalidNativeManifest;
    if (!std.mem.eql(u8, v.text(v.get(manifest, "abi")), native_abi)) return error.InvalidNativeManifest;
    const units = v.array(v.get(manifest, manifest_functions));
    const entry = v.text(v.get(manifest, "entry"));
    // A selective library manifest has no executable entry; `build --library`
    // emits a stub entry_run instead. Executable manifests still require one.
    var entry_found = entry.len == 0;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(allocator);
    for (units) |unit| {
        const symbol = v.text(v.get(unit, "symbol"));
        if (symbol.len == 0 or !lean.wellFormed(unit)) return error.InvalidNativeManifest;
        if (!std.ascii.isAlphabetic(symbol[0]) and symbol[0] != '_') return error.InvalidNativeManifest;
        for (symbol) |character| if (!std.ascii.isAlphanumeric(character) and character != '_') return error.InvalidNativeManifest;
        if ((try seen.getOrPut(allocator, symbol)).found_existing) return error.InvalidNativeManifest;
        if (std.mem.eql(u8, symbol, entry)) entry_found = true;
    }
    if (!entry_found) return error.InvalidNativeManifest;
}
/// One function's QBE footprint: its blocks, its temporaries, and the bytes
/// QBE is estimated to need for them.
const QbeFootprint = struct { blocks: u64, temporaries: u64, bytes: u64 };
/// QBE-SIZE-LIMIT-1: QBE's liveness and register allocation keep one bit set of
/// every temporary per block, so its memory grows as blocks x temporaries —
/// measured at about 1.6 bytes per pair (0.97 GB at 8k x 76k, 3.7 GB at
/// 16k x 152k). The footprint of one function's IL when that estimate exceeds
/// three quarters of `address_space` bytes, or null when it fits. Blocks are the
/// labels; temporaries are the highest `%v`, `%s` and `%l` numbers, which the
/// emitter hands out densely.
fn qbeRefusal(il: []const u8, address_space: u64) ?QbeFootprint {
    var blocks: u64 = 0;
    var highest = [_]u64{ 0, 0, 0 };
    for (il, 0..) |byte, at| {
        if (byte == '@' and (at == 0 or il[at - 1] == '\n')) blocks += 1;
        if (byte != '%' or at + 2 >= il.len) continue;
        const class: usize = switch (il[at + 1]) {
            'v' => 0,
            's' => 1,
            'l' => 2,
            else => continue,
        };
        var end = at + 2;
        var number: u64 = 0;
        while (end < il.len and std.ascii.isDigit(il[end])) : (end += 1) number = number *| 10 +| (il[end] - '0');
        if (end > at + 2) highest[class] = @max(highest[class], number + 1);
    }
    const temporaries = highest[0] + highest[1] + highest[2];
    const bytes = blocks *| temporaries / 5 *| 8;
    if (bytes <= address_space / 4 * 3) return null;
    return .{ .blocks = blocks, .temporaries = temporaries, .bytes = bytes };
}

// spec: QBE-SIZE-LIMIT-1
test "qbeRefusal estimates a function's QBE memory and refuses only past the ceiling" {
    const il = "function $f() {\n@start\n %v0 =l add 1, 2\n %v9 =l add %v0, %s3\n@next\n storel %v9, %l4\n ret\n}\n";
    // Two blocks; temporaries %v0..%v9, %s0..%s3 and %l0..%l4: 19; 2 x 19 x 1.6 rounds to 56 bytes.
    const refused = qbeRefusal(il, 64).?;
    try std.testing.expectEqual(@as(u64, 2), refused.blocks);
    try std.testing.expectEqual(@as(u64, 19), refused.temporaries);
    try std.testing.expectEqual(@as(u64, 56), refused.bytes);
    try std.testing.expectEqual(@as(?QbeFootprint, null), qbeRefusal(il, 1 << 20));
    // 4 000 checked statements (16k x 152k, 3.7 GB measured) fit the default
    // 8 GiB ceiling; 8 000 (32k x 304k, which ran QBE out of memory) do not.
    const default_ceiling: u64 = (8 << 30) + (256 << 20);
    const fits = try syntheticIl(std.testing.allocator, 16006, 152015);
    defer std.testing.allocator.free(fits);
    try std.testing.expectEqual(@as(?QbeFootprint, null), qbeRefusal(fits, default_ceiling));
    const large = try syntheticIl(std.testing.allocator, 32006, 304015);
    defer std.testing.allocator.free(large);
    try std.testing.expectEqual(@as(u64, 304016), qbeRefusal(large, default_ceiling).?.temporaries);
}
/// IL with `blocks` labels whose highest temporary is `%v<highest>`.
fn syntheticIl(allocator: std.mem.Allocator, blocks: usize, highest: u64) ![]u8 {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);
    for (0..blocks) |_| try text.appendSlice(allocator, "@a\n");
    try text.print(allocator, "%v{d}\n", .{highest});
    return text.toOwnedSlice(allocator);
}
const State = struct {
    context: fs.Context,
    cache: cache_api.Cache,
    manifest: std.json.Value,
    objects: std.ArrayList([]const u8) = .empty,
    records: std.ArrayList(Record) = .empty,
    reused: usize = 0,
    runtime: cache_api.Object = undefined,
    metadata_reused: bool = false,
    runtime_installed: bool = false,
    /// Whether this build compiled any object it links rather than reusing
    /// it: the link then produces a new program, so the byte comparison that
    /// keeps an identical one in place is not worth reading both files for.
    compiled: bool = false,
    /// How the final link ran (BUILD-LINK-1), or null when it was skipped.
    link_route: ?direct_link.Route = null,
    /// The directory a lean manifest's stored texts and metadata live in.
    fn textStore(self: *const State) []const u8 {
        return v.text(v.get(self.manifest, "store"));
    }
    /// EMIT-META-1: `units` as the function tables read them, a lean unit's
    /// stored metadata read in place of the positions it does not carry.
    fn metaTables(self: *State, units: []const std.json.Value) ![]const std.json.Value {
        const out = try self.context.allocator.alloc(std.json.Value, units.len);
        for (units, out) |unit, *table| table.* = try lean.tables(self.context, self.textStore(), unit);
        return out;
    }
    /// The manifest with every unit's metadata in place, for the LLVM arm's
    /// single metadata C unit, which spells every function's tables.
    fn tableManifest(self: *State) !std.json.Value {
        var copy = try self.manifest.object.clone(self.context.allocator);
        var functions = std.json.Array.init(self.context.allocator);
        try functions.appendSlice(try self.metaTables(v.array(v.get(self.manifest, manifest_functions))));
        try copy.put(self.context.allocator, manifest_functions, .{ .array = functions });
        return .{ .object = copy };
    }
    fn add(self: *State, object: cache_api.Object) !void {
        if (!object.reused) self.compiled = true;
        try self.objects.append(self.context.allocator, object.path);
    }
    fn compile(self: *State, parsed: options.Options) !void {
        const a = self.context.allocator;
        const functions = try a.dupe(std.json.Value, v.array(v.get(self.manifest, manifest_functions)));
        std.mem.sort(std.json.Value, functions, {}, less);
        const wrapper = if (parsed.library) try @import("qbe_build_embed.zig").libraryWrapper(a, self.manifest) else try outputs.entry(a, self.manifest, parsed.provider != null, std.mem.eql(u8, parsed.mode, release_fast));
        const units: [2]cache_api.Object = if (self.cache.codegen.llvm) llvm: {
            try self.compileUnits(functions);
            break :llvm .{ try self.cache.object("metadata", try outputs.metadata(a, try self.tableManifest()), .c_text), try self.cache.object("entry", wrapper, .c_text) };
        } else try self.compileBatches(functions, wrapper);
        self.metadata_reused = units[0].reused;
        try self.add(units[0]);
        try self.add(units[1]);
        if (v.boolean(v.get(self.manifest, "text_format"))) try self.add(try self.resolveFormat());
        // Linked last, so every object above can still pull the members it needs.
        self.runtime = try self.resolveRuntime();
    }
    /// The LLVM arm (LLVM-ZIG-1): one content-addressed object per unit. An
    /// object is named by its unit text's digest, so a hit never reads the
    /// text; the misses are translated in process and compiled concurrently
    /// (`qbe_build_llvm_compile.zig`), reading a lean unit's text from the
    /// fragment store only then (`QBE-FRAGMENT-REUSE-1`).
    fn compileUnits(self: *State, functions: []const std.json.Value) !void {
        const a = self.context.allocator;
        const objects = try a.alloc(cache_api.Object, functions.len);
        var misses: std.ArrayList(llvm_compile.Miss) = .empty;
        for (functions, objects, 0..) |function, *object, index| {
            const key = try self.cache.digestKey(try lean.digest(a, function));
            if (try self.cache.cached(key)) |hit| object.* = hit else try misses.append(a, .{ .unit = index, .key = key });
        }
        if (misses.items.len != 0) {
            const built = try llvm_compile.build(.{ .cache = self.cache, .units = functions, .store = self.textStore(), .misses = misses.items });
            for (misses.items, built) |miss, object| objects[miss.unit] = object;
        }
        for (functions, objects) |function, object| {
            try self.add(object);
            self.reused += @intFromBool(object.reused);
            try self.records.append(a, .{ .name = v.text(v.get(function, "name")), .symbol = v.text(v.get(function, "symbol")), .key = object.key, .object = object.path, .reused = object.reused });
        }
    }
    /// QBE-BATCH-1: the QBE arm plans its units into module batches, reuses
    /// every batch whose object is cached, and builds the rest concurrently,
    /// one QBE run and one assembler run per batch (`qbe_build_batch.zig`).
    /// Each function's report record names its own key and its batch's object.
    /// QBE-BATCH-3: each batch's function metadata is its own assembled object
    /// keyed by its text, and the program-wide metadata and entry C units
    /// compile in the same pool, so none of them waits for the others. Returns
    /// the shared metadata and entry objects, which link after every batch.
    fn compileBatches(self: *State, functions: []const std.json.Value, wrapper: []const u8) ![2]cache_api.Object {
        const a = self.context.allocator;
        const order = try a.alloc(usize, functions.len);
        for (order, 0..) |*slot, index| slot.* = index;
        std.mem.sort(usize, order, functions, planLess);
        const units = try a.alloc(batch.Unit, functions.len);
        const keys = try a.alloc([]const u8, functions.len);
        // A unit is keyed by its IL's digest and planned from the lines the
        // driver reads without compiling it, so a lean unit's text is never read
        // here (`QBE-FRAGMENT-REUSE-1`).
        for (order, units, keys) |index, *unit, *key| {
            const function = functions[index];
            unit.* = .{ .module = batch.moduleOf(v.text(v.get(function, "name"))), .symbol = v.text(v.get(function, "symbol")), .alone = batch.definesData(lean.facts(function)) };
            key.* = try self.cache.digestKey(try lean.digest(a, function));
        }
        const batches = try batch.plan(a, units, batch.policy(self.context.environ));
        // QBE-BATCH-6: function metadata is assembled in coarser groups than
        // code, since assembling it is little work next to starting a tool.
        const groups = try batch.plan(a, units, batch.metadata_policy);
        // Objects: each batch's code, each group's metadata, then the shared metadata and the entry.
        const objects = try a.alloc(cache_api.Object, batches.len + groups.len + 2);
        var misses: std.ArrayList(batch.Miss) = .empty;
        const owner = try a.alloc(usize, functions.len);
        for (batches, 0..) |group, index| {
            const positions = order[group.first .. group.first + group.count];
            for (positions) |position| owner[position] = index;
            const code = try batch.key(self.cache, keys[group.first .. group.first + group.count]);
            if (try self.cache.cached(code)) |hit| objects[index] = hit else {
                // BUILD-MEMORY-1: each member's text is read, checked and written
                // out one at a time, so no miss holds its text until QBE runs.
                var texts: MemberTexts = .{ .state = self, .members = try planned(a, functions, positions) };
                const files = try batch.stage(self.cache, group.count, &texts);
                try misses.append(a, .{ .key = code, .object = &objects[index], .input = .{ .files = files } });
            }
        }
        for (groups, batches.len..) |group, slot| {
            const members = try planned(a, functions, order[group.first .. group.first + group.count]);
            // BUILD-METADATA-KEY-1: the tables are keyed by what they are
            // rendered from, and rendered only for a group that must build them.
            const tables = try self.cache.derived(batch.metadata_version, &std.fmt.bytesToHex(outputs.metadataDigest(members), .lower));
            if (try self.cache.cached(tables)) |hit| objects[slot] = hit else {
                try misses.append(a, .{ .key = tables, .object = &objects[slot], .input = .{ .assembly = try outputs.metadataAssembly(a, try self.metaTables(members)) } });
            }
        }
        const shared = batches.len + groups.len;
        // The C units start first: the shared metadata is the largest single compile.
        var work: std.ArrayList(batch.Miss) = .empty;
        try self.stageC(&work, "metadata", try outputs.sharedMetadata(a, self.manifest), &objects[shared]);
        try self.stageC(&work, "entry", wrapper, &objects[shared + 1]);
        try work.appendSlice(a, misses.items);
        try batch.build(self.cache, work.items, batch.width(self.context.io, work.items.len));
        for (objects[0..shared]) |object| try self.add(object);
        const unit_keys = try a.alloc([]const u8, functions.len);
        for (order, keys) |position, key| unit_keys[position] = key;
        for (functions, owner, unit_keys) |function, index, key| {
            const object = objects[index];
            self.reused += @intFromBool(object.reused);
            try self.records.append(a, .{ .name = v.text(v.get(function, "name")), .symbol = v.text(v.get(function, "symbol")), .key = key, .object = object.path, .reused = object.reused });
        }
        return .{ objects[shared], objects[shared + 1] };
    }
    /// The manifest units at `positions`, in that (plan) order.
    fn planned(allocator: std.mem.Allocator, functions: []const std.json.Value, positions: []const usize) ![]const std.json.Value {
        const members = try allocator.alloc(std.json.Value, positions.len);
        for (positions, members) |position, *member| member.* = functions[position];
        return members;
    }
    /// One missed batch's member texts, read in plan order into the scratch
    /// arena `batch.stage` hands each one, and each checked against the QBE
    /// size limit before it is written.
    const MemberTexts = struct {
        state: *State,
        members: []const std.json.Value,
        at: usize = 0,
        /// The next member's text, read into `scratch` and checked against the QBE size limit.
        pub fn next(self: *MemberTexts, scratch: std.mem.Allocator) lean.Error![]const u8 {
            var reader = self.state.context;
            reader.allocator = scratch;
            const member = self.members[self.at];
            self.at += 1;
            const text = try lean.text(reader, self.state.textStore(), member);
            try self.state.fitsQbe(member, text);
            return text;
        }
    };
    /// Record one generated C unit's object, or stage its compile as a miss
    /// for the batch pool.
    fn stageC(self: *State, misses: *std.ArrayList(batch.Miss), kind: []const u8, text: []const u8, object: *cache_api.Object) !void {
        switch (try self.cache.stage(kind, text, .c_text, null)) {
            .hit => |hit| object.* = hit,
            .miss => |job| try misses.append(self.context.allocator, .{ .key = job.key, .object = object, .input = .{ .staged = job } }),
        }
    }
    /// QBE-SIZE-LIMIT-1: refuse, before QBE starts, a function whose QBE memory
    /// estimate (`qbeRefusal`) exceeds the address-space ceiling QBE inherits
    /// from this process, naming the function and the two ways out, instead of
    /// letting QBE die in `emalloc` minutes later. No ceiling, no refusal.
    fn fitsQbe(self: *State, unit: std.json.Value, text: []const u8) fs.Error!void {
        const address_space = std.posix.getrlimit(.AS) catch return;
        if (address_space.cur == std.math.maxInt(u64)) return;
        const refusal = qbeRefusal(text, address_space.cur) orelse return;
        const gib: f64 = 1024.0 * 1024.0 * 1024.0;
        const message = try std.fmt.allocPrint(
            self.context.allocator,
            "mylang: function `{s}` is too large for the QBE backend: {d} blocks x {d} temporaries need about {d:.1} GiB in QBE, " ++
                "over the {d:.1} GiB address-space ceiling it inherits (MYLANG_HOST_MEMORY_LIMIT); split the function, or build with `--backend llvm`\n",
            .{ v.text(v.get(unit, "name")), refusal.blocks, refusal.temporaries, @as(f64, @floatFromInt(refusal.bytes)) / gib, @as(f64, @floatFromInt(address_space.cur)) / gib },
        );
        std.Io.File.stderr().writeStreamingAll(self.context.io, message) catch return error.NativeToolFailed;
        return error.NativeToolFailed;
    }
    /// Link the prebuilt runtime archive installed beside the compiler when its
    /// hash matches this build's runtime, backend flavor, mode and target; otherwise
    /// compile the archive from source. A matching install skips the whole runtime
    /// compile on a cold build, which for the LTO release path is the largest one.
    fn resolveRuntime(self: *State) !cache_api.Object {
        const flavor = runtimeFlavor(self.cache.codegen.llvm, self.cache.codegen.lto);
        if (try installedRuntime(self.context, self.cache.mode, "archive", flavor, ".a")) |found| {
            self.runtime_installed = true;
            return found;
        }
        return self.cache.library("runtime", &runtime_units);
    }
    /// Use the prebuilt text-formatter object installed beside the compiler when it
    /// matches, else compile `native_format.zig` from the bundled runtime source.
    fn resolveFormat(self: *State) !cache_api.Object {
        if (try installedRuntime(self.context, self.cache.mode, "format", "", ".o")) |found| return found;
        return self.cache.object("format", "native_format.zig", .zig_file);
    }
    /// The full link command for one candidate executable or shared library.
    fn linkCommand(self: *State, parsed: options.Options, candidate: []const u8) ![]const []const u8 {
        const a = self.context.allocator;
        var args: std.ArrayList([]const u8) = .empty;
        try args.appendSlice(a, try self.cache.flags());
        if (parsed.library) try args.appendSlice(a, &library_link_arguments);
        try args.appendSlice(a, self.objects.items);
        try native_link.append(self.context, parsed.link_arguments, &args, false);
        if (self.unwinds(parsed)) try args.appendSlice(a, &unwind_link);
        // Unreferenced runtime sections leave with the archive members nothing pulled.
        // `-s` drops the symbol table and any DWARF an object or an installed archive
        // still carries: traps and their frames read the runtime's own tables. A
        // profile build keeps it so `perf report` can name guest functions.
        if (options.keepSymbols(parsed.link_arguments)) {
            try args.appendSlice(a, &.{ self.runtime.path, "-lm", gc_sections, "-o", candidate });
        } else {
            try args.appendSlice(a, &.{ self.runtime.path, "-lm", gc_sections, "-s", "-o", candidate });
        }
        return args.items;
    }
    /// Whether every object this link names is still on disk. A concurrent sweep
    /// that evicted this generation leaves cache hits pointing at removed files,
    /// which the linker reports only as `cannot open ...: No such file or directory`.
    fn inputsPresent(self: *State) bool {
        for (self.objects.items) |path| if (!self.context.exists(path)) return false;
        return self.context.exists(self.runtime.path);
    }
    /// Recreate this generation and rebuild every object it lost, discarding the
    /// records of the removed ones so the report counts what was really compiled.
    fn recompile(self: *State, parsed: options.Options) !void {
        try self.context.restore(self.cache.directory);
        self.objects.clearRetainingCapacity();
        self.records.clearRetainingCapacity();
        self.reused = 0;
        try self.compile(parsed);
        if (parsed.provider) |provider_source| try self.provider(provider_source);
    }
    /// Link, rebuilding a cached input a concurrent sweep removed and retrying
    /// once. A failure with every input present is the program's own link error
    /// and is reported unchanged.
    fn linkOnce(self: *State, parsed: options.Options, candidate: []const u8) !void {
        if (!self.inputsPresent()) try self.recompile(parsed);
        self.linkAttempt(parsed, candidate) catch |err| {
            if (self.inputsPresent()) return err;
            try self.recompile(parsed);
            try self.linkAttempt(parsed, candidate);
        };
    }
    /// One link: the ordinary single command, or, for an LTO executable whose
    /// units carry frame-map positions, LTO to assembly first.
    fn linkAttempt(self: *State, parsed: options.Options, candidate: []const u8) !void {
        if (self.cache.codegen.lto.on() and !parsed.library and self.usesFrameMap()) return self.linkAssembled(parsed, candidate);
        // BUILD-LINK-1: the command `zig cc` would run, without its host probe.
        const place: direct_link.Place = .{ .directory = self.cache.directory, .environment = self.cache.environment };
        self.link_route = try direct_link.run(self.context, place, .{ .argv = try self.linkCommand(parsed, candidate), .objects = self.objects.items, .output = candidate, .scratch = self.cache.temporary });
    }
    /// Whether this link is an LLVM frame-map executable, whose guest code keeps
    /// no frame pointer: its traps unwind by call-frame information, so it
    /// links libunwind for `_Unwind_Backtrace` (QBE-FRAMEMAP-1).
    fn unwinds(self: *State, parsed: options.Options) bool {
        return self.cache.codegen.llvm and !parsed.library and self.usesFrameMap();
    }
    /// Whether any unit was lowered for the frame map (QBE-FRAMEMAP-1).
    fn usesFrameMap(self: *State) bool {
        for (v.array(v.get(self.manifest, manifest_functions))) |unit| {
            if (frame_map.usesFrameMap(lean.facts(unit))) return true;
        }
        return false;
    }
    /// QBE-FRAMEMAP-1 under LTO. The frame-map table is keyed by each call's
    /// return address, which only the final code has, and LTO produces that
    /// code inside the link. So the bitcode is optimized and compiled to
    /// assembly by LLD itself, with the same optimization level and entry root
    /// the ordinary link gives it: one file under full LTO, one per module
    /// under ThinLTO (LLVM-THINLTO-1). The table is added to each file, which
    /// is assembled and linked natively with the objects that were never
    /// bitcode. The bitcode inputs are not linked again: everything they
    /// contribute is in the assembly.
    fn linkAssembled(self: *State, parsed: options.Options, candidate: []const u8) !void {
        const a = self.context.allocator;
        const directory = std.fs.path.dirname(candidate) orelse ".";
        // The LTO link reads the native objects too: what they reference is
        // what keeps a bitcode definition alive.
        var inputs: std.ArrayList([]const u8) = .empty;
        try inputs.appendSlice(a, self.objects.items);
        try inputs.append(a, self.runtime.path);
        // LLVM-THINLTO-1: every module optimized and compiled on its own thread.
        const compiled = if (self.cache.codegen.lto == .thin)
            try llvm_thin.link(.{ .cache = self.cache, .level = ltoLevel(self.cache.codegen.optimization), .inputs = inputs.items, .directory = directory, .known = try self.probeNames() })
        else
            try self.fullLto(inputs.items, directory);
        var args: std.ArrayList([]const u8) = .empty;
        const bitcode_flag = self.cache.codegen.lto.flag() orelse "";
        for (try self.cache.flags()) |flag| if (!std.mem.eql(u8, flag, bitcode_flag)) try args.append(a, flag);
        for (self.objects.items) |path| if (try self.nativeObject(path)) try args.append(a, path);
        try args.appendSlice(a, compiled);
        try native_link.append(self.context, parsed.link_arguments, &args, false);
        try args.appendSlice(a, &unwind_link);
        try args.appendSlice(a, &.{ "-lm", gc_sections });
        if (!options.keepSymbols(parsed.link_arguments)) try args.append(a, "-s");
        try args.appendSlice(a, &.{ "-o", candidate });
        try self.context.command(try direct_link.responseArgv(self.context, try std.fs.path.join(a, &.{ directory, "link.rsp" }), args.items, 2), null);
    }
    /// Every guest unit's symbol by the GUID its pseudo probes carry, for the
    /// ThinLTO modules a callee was inlined into from another module.
    fn probeNames(self: *State) !*const frame_map.Names {
        const a = self.context.allocator;
        const names = try a.create(frame_map.Names);
        names.* = .empty;
        for (v.array(v.get(self.manifest, manifest_functions))) |unit| {
            const symbol = v.text(v.get(unit, "symbol"));
            try names.put(a, frame_map.probeGuid(symbol), symbol);
        }
        return names;
    }
    /// Full LTO to one assembly file, annotated and assembled into the one
    /// object that stands for every bitcode input.
    fn fullLto(self: *State, inputs: []const []const u8, directory: []const u8) ![]const []const u8 {
        const a = self.context.allocator;
        const base = try std.fs.path.join(a, &.{ directory, "program-lto" });
        var lto: std.ArrayList([]const u8) = .empty;
        try lto.appendSlice(a, &.{ self.cache.zig, "ld.lld", "--error-limit=0", "-mllvm", "-float-abi=hard" });
        try lto.appendSlice(a, ltoLevel(self.cache.codegen.optimization));
        try lto.appendSlice(a, &.{ "--lto-emit-asm", "--lto-partitions=1", "-m", "elf_x86_64", "--entry", "main", "-o", base });
        try lto.appendSlice(a, inputs);
        // BUILD-LINK-RSP-1: the command names every object.
        try self.context.command(try direct_link.responseArgv(self.context, try std.fs.path.join(a, &.{ directory, "lto.rsp" }), lto.items, 2), null);
        const assembly = try std.fs.path.join(a, &.{ directory, "program.s" });
        try self.context.write(assembly, try cache_api.annotateText(self.context, try self.context.read(try std.fmt.allocPrint(a, "{s}.lto.s", .{base})), null));
        const object = try std.fs.path.join(a, &.{ directory, "program.o" });
        try self.context.command(&.{ self.cache.zig, "cc", "-g0", "-c", assembly, "-o", object }, null);
        return a.dupe([]const u8, &.{object});
    }
    /// Whether an input is already machine code rather than LTO bitcode.
    fn nativeObject(self: *State, path: []const u8) !bool {
        const bytes = try self.context.read(path);
        return std.mem.startsWith(u8, bytes, "\x7fELF");
    }
    fn link(self: *State, parsed: options.Options, output: []const u8) !bool {
        const a = self.context.allocator;
        // An unchanged build whose published executable still matches every input
        // keeps it as it is: relinking the LTO object set costs about a second,
        // and the per-function cache has already made codegen a hit. A provider
        // or any explicit native link input disables reuse, because those can
        // change without changing a guest object.
        if (!parsed.run and parsed.provider == null and try self.reusable(parsed, output)) return false;
        const temporary = try self.context.temporary(std.fs.path.dirname(output).?);
        defer self.context.remove(temporary);
        const candidate = try std.fs.path.join(a, &.{ temporary, "program" });
        if (parsed.provider) |provider_source| try self.provider(provider_source);
        try self.linkOnce(parsed, candidate);
        if (parsed.run) return self.context.publish(candidate, output);
        // The link identity leads the sidecar so the next build's `reusable`
        // finds it without parsing every function record after it.
        const report = try std.json.Stringify.valueAlloc(a, .{
            .link_identity = try self.linkIdentity(parsed),
            .version = "qbe-manifest-v1",
            .abi = native_abi,
            .entry = v.text(v.get(self.manifest, "entry")),
            .backend = if (self.cache.codegen.llvm) "llvm" else "qbe",
            .optimization = self.cache.codegen.optimization,
            .lto = self.cache.codegen.lto.on(),
            .thin_lto = self.cache.codegen.lto == .thin,
            .functions = self.records.items,
            .runtime_object = self.runtime.path,
        }, .{});
        const sidecar = try std.fmt.allocPrint(a, "{s}.qbe-manifest.json", .{output});
        const staged = try std.fs.path.join(a, &.{ temporary, "manifest.json" });
        try self.context.write(staged, report);
        // BUILD-PUBLISH-1: a link over an object this build compiled is a new
        // program; only a relink of objects that were all reused can reproduce
        // the published bytes, so only that one is compared before replacing.
        const changed = if (self.compiled or !self.runtime.reused) replaced: {
            try self.context.republish(candidate, output);
            break :replaced true;
        } else try self.context.publish(candidate, output);
        // The sidecar is descriptive, not an atomic transaction with the executable.
        try self.context.rename(staged, sidecar);
        return changed;
    }
    /// Report whether the published executable is still exactly what this build
    /// would produce, so unchanged work keeps it instead of relinking. It is
    /// conservative in both directions: an explicit native link input disables
    /// it, and the executable, every cached object and the runtime archive must
    /// all still be on disk.
    fn reusable(self: *State, parsed: options.Options, output: []const u8) !bool {
        if (!self.context.runnable(output)) return false;
        if (!self.inputsPresent()) return false;
        if (native_link.hasInputs(parsed.link_arguments)) return false;
        const sidecar = try std.fmt.allocPrint(self.context.allocator, "{s}.qbe-manifest.json", .{output});
        const bytes = self.context.read(sidecar) catch return false;
        const published = sidecarIdentity(bytes) orelse return false;
        return std.mem.eql(u8, published, try self.linkIdentity(parsed));
    }
    /// Hash everything a link's output depends on besides its link-input files:
    /// the object set, the runtime archive, the artifact kind, the mode, the
    /// target and the symbol policy. A build with external link inputs refuses
    /// reuse before this is consulted.
    fn linkIdentity(self: *State, parsed: options.Options) ![]const u8 {
        const encoded = try std.json.Stringify.valueAlloc(self.context.allocator, .{
            .objects = self.objects.items,
            .runtime = self.runtime.path,
            .library = parsed.library,
            .mode = parsed.mode,
            .target = parsed.target,
            .symbols = options.keepSymbols(parsed.link_arguments),
        }, .{});
        // BLAKE3 (BUILD-KEYS-1): the object list of a large program is hundreds
        // of kilobytes, which the toolchain's SHA-256 hashes at about 14 MB/s.
        var digest: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(encoded, &digest, .{});
        return self.context.allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
    }
    fn provider(self: *State, source: []const u8) !void {
        const a = self.context.allocator;
        var environment = try self.context.environ.clone(a);
        const temporary = self.cache.temporary;
        try environment.put("ZIG_GLOBAL_CACHE_DIR", try std.fs.path.join(a, &.{ temporary, "provider-cache" }));
        try environment.put("ZIG_LOCAL_CACHE_DIR", try std.fs.path.join(a, &.{ temporary, "provider-local-cache" }));
        const object = try std.fs.path.join(a, &.{ temporary, "provider.o" });
        try self.cache.compileC(try self.context.absolute(source), object, &environment);
        try self.objects.append(a, object);
    }
};
/// The frontend switch that asks for a project's lean manifest: an
/// executable's leaves out the facts only a library build reads (`EMIT-META-1`).
fn leanManifestFlag(parsed: options.Options) []const u8 {
    return if (parsed.library) "--lean-manifest" else "--lean-manifest=executable";
}
/// The report's name for how the link ran, or null when it was skipped.
fn routeName(route: ?direct_link.Route) ?[]const u8 {
    return if (route) |ran| @tagName(ran) else null;
}
/// The `link_identity` a published sidecar records, found by its key rather
/// than by parsing the whole document: the sidecar lists every function, and
/// a key and its quotes cannot occur unescaped inside any JSON string value.
fn sidecarIdentity(bytes: []const u8) ?[]const u8 {
    const key = "\"link_identity\":\"";
    const start = (std.mem.indexOf(u8, bytes, key) orelse return null) + key.len;
    const end = std.mem.indexOfScalarPos(u8, bytes, start, '"') orelse return null;
    return bytes[start..end];
}
/// Shared-library link controls: bind the library's own descriptor references
/// internally so a guest object's non-PIC relocations resolve without symbol
/// interposition.
const library_link_arguments = [_][]const u8{ "-shared", "-Wl,-Bsymbolic" };
/// The default optimize mode; only non-Debug builds can drop accounting.
const release_fast = "ReleaseFast";
fn less(_: void, left: std.json.Value, right: std.json.Value) bool {
    return std.mem.lessThan(u8, v.text(v.get(left, "symbol")), v.text(v.get(right, "symbol")));
}
/// A manifest unit as the batch planner orders it.
fn planUnit(value: std.json.Value) batch.Unit {
    return .{ .module = batch.moduleOf(v.text(v.get(value, "name"))), .symbol = v.text(v.get(value, "symbol")) };
}
/// Batch plan order over manifest units, by index: module, then symbol.
fn planLess(functions: []const std.json.Value, left: usize, right: usize) bool {
    return batch.less({}, planUnit(functions[left]), planUnit(functions[right]));
}

fn checkHost(os: std.Target.Os.Tag, arch: std.Target.Cpu.Arch) error{UnsupportedNativeHost}!void {
    if (os != .linux or arch != .x86_64) return error.UnsupportedNativeHost;
}
fn checkVersion(version: []const u8) error{ZigVersionMismatch}!void {
    if (!std.mem.eql(u8, version, bundled.zig_version)) return error.ZigVersionMismatch;
}
// spec-case: RUNTIME-TIMEOUT-1
test "build --run forwards a wall-clock timeout and stops at the guest delimiter" {
    const controls = try runtimeControls(std.testing.allocator, &.{ "main.my", "--run", "--timeout=30", "--", "--timeout=9" });
    defer std.testing.allocator.free(controls);
    try std.testing.expectEqual(@as(usize, 1), controls.len);
    try std.testing.expectEqualStrings("--timeout=30", controls[0]);
}
// spec: QBE-2
test "native build rejects incompatible tools targets and malformed manifests" {
    try std.testing.expectError(error.UnsupportedNativeHost, checkHost(.linux, .aarch64));
    try std.testing.expectError(error.ZigVersionMismatch, checkVersion("unrelated-version"));
    try std.testing.expectError(error.InvalidNativeManifest, validate(std.testing.allocator, .null));
    var buffer: [512]u8 = undefined;
    const encoded = try std.fmt.bufPrint(&buffer, "{{\"version\":\"qbe-units-v1\",\"abi\":\"{s}\",\"entry\":\"1bad\",\"functions\":[{{\"symbol\":\"1bad\",\"il\":\"\"}}]}}", .{native_abi});
    const value = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, encoded, .{});
    defer value.deinit();
    try std.testing.expectError(error.InvalidNativeManifest, validate(std.testing.allocator, value.value));
}

// spec: QBE-AGGREF-6
test "a pre-v7 manifest whose IL already crossed by address is refused, not re-read" {
    // Version 6 was accepted while the managed-object header was still the
    // 96-byte form its generated literal initializers spelled; a v6 manifest and
    // the v7 runtime it would link against disagree about that image layout, so
    // `validate` refuses it before any object is built.
    const value = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"version":"qbe-units-v1","abi":"mylang-qbe-native-v6","entry":"e","functions":[{"symbol":"e","il":""}]}
    , .{});
    defer value.deinit();
    try std.testing.expectError(error.InvalidNativeManifest, validate(std.testing.allocator, value.value));
    const accepted = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"version\":\"qbe-units-v1\",\"abi\":\"" ++ native_abi ++ "\",\"entry\":\"e\",\"functions\":[{\"symbol\":\"e\",\"il\":\"\"}]}", .{});
    defer accepted.deinit();
    try validate(std.testing.allocator, accepted.value);
}

// spec: QBE-AGGREF-8
test "the build generation is keyed by the new ABI so a v6 cache cannot be reused" {
    // The generation every object, archive and executable is keyed by folds in
    // the ABI tag, so an artifact produced for v6 is unreachable by a v7 build.
    // Contrast against the identity this driver produced before the bump rather
    // than against the constant itself.
    const previous = "zig-qbe-build-v2\x00mylang-qbe-native-v6\x00" ++ bundled.driver_identity ++ "\x00" ++ bundled.content_hash;
    try std.testing.expect(!std.mem.eql(u8, generation_identity, previous));
    try std.testing.expect(std.mem.indexOf(u8, generation_identity, native_abi) != null);
    try std.testing.expect(std.mem.indexOf(u8, previous, native_abi) == null);
    var before: [32]u8 = undefined;
    var after: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(previous, &before, .{});
    std.crypto.hash.sha2.Sha256.hash(generation_identity, &after, .{});
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}
// spec: QBE-HOST-COMPILER-1
test "the frontend honours an explicit host compiler over the running executable" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const own = try frontendCompiler(context);
    try std.testing.expect(own.len != 0);
    try environment.put("MYLANG_HOST_COMPILER", "/opt/mylang/bin/mylang");
    try std.testing.expectEqualStrings("/opt/mylang/bin/mylang", try frontendCompiler(context));
}
fn bundles(name: []const u8) bool {
    for (bundled.files) |asset| if (std.mem.eql(u8, asset.path, name)) return true;
    return false;
}
test "bundled build inputs carry only the native runtime, not compiler tests or guest fixtures" {
    try std.testing.expectEqual(@as(usize, 64), bundled.content_hash.len);
    try std.testing.expectEqual(@as(usize, 64), bundled.compiler_identity.len);
    try std.testing.expectEqual(@as(usize, 64), bundled.driver_identity.len);
    for (bundled.files) |asset| {
        try std.testing.expect(!std.mem.endsWith(u8, asset.path, "_test.zig"));
        try std.testing.expect(!std.mem.endsWith(u8, asset.path, ".my") or std.mem.startsWith(u8, asset.path, "stdlib/"));
    }
    try std.testing.expect(bundles("qbe_runtime.c") and bundles("qbe_runtime.h") and bundles("native_heap.c"));
    try std.testing.expect(bundles("native_arena.c") and bundles("native_arena.h"));
    try std.testing.expect(bundles("native_equal.c") and bundles("native_format.zig"));
    try std.testing.expect(!bundles("sema.zig") and !bundles("qbe_build.zig") and !bundles("json_document.zig"));
}
// spec-case: QBE-FRAMEMAP-1
test "every bundled runtime unit that names a trap helper keeps frame pointers" {
    // A unit that calls into the `myl_qbe_*` layer can report a trap from
    // inside itself, so the frame-map walk must be able to cross its frames.
    for (runtime_units) |unit| {
        const source = for (bundled.files) |asset| {
            if (std.mem.eql(u8, asset.path, unit)) break asset.bytes;
        } else return error.TestUnexpectedResult;
        const reaches = std.mem.indexOf(u8, source, "myl_qbe_") != null;
        try std.testing.expect(!reaches or cache_api.keepsFramePointers(unit));
    }
    try std.testing.expect(!cache_api.keepsFramePointers("native_heap.c"));
}
// spec: QBE-3
test "the runtime tree is published once per content hash and reused by later builds" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const cache = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const first = try materialize(context, cache);
    try std.testing.expect(std.mem.endsWith(u8, first, bundled.content_hash));
    try std.testing.expect(context.exists(try std.fs.path.join(context.allocator, &.{ first, "qbe_runtime.c" })));
    try std.testing.expect(!context.exists(try std.fs.path.join(context.allocator, &.{ first, "sema.zig" })));
    const marker = try std.fs.path.join(context.allocator, &.{ first, "reuse-marker" });
    try context.write(marker, "kept");
    try std.testing.expectEqualStrings(first, try materialize(context, cache));
    try std.testing.expectEqualStrings("kept", try context.read(marker));
}
// spec: QBE-GENERATION-1
test "a new build generation evicts its siblings and an existing one is reused untouched" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const first = try generation(context, root, "objects", "toolchain one");
    const marker = try std.fs.path.join(context.allocator, &.{ first, "unit.o" });
    try context.write(marker, "one");
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ root, "objects" }), std.fs.path.dirname(first).?);
    try std.testing.expectEqual(@as(usize, 64), std.fs.path.basename(first).len);
    // The same environment names the same generation and sweeps nothing.
    try std.testing.expectEqualStrings(first, try generation(context, root, "objects", "toolchain one"));
    try std.testing.expectEqualStrings("one", try context.read(marker));
    // Another family is its own namespace with its own generations.
    const executables = try generation(context, root, "exe", "toolchain one");
    try std.testing.expect(context.exists(executables));
    try std.testing.expect(!std.mem.eql(u8, first, executables));
    // Two generations an earlier process abandoned, one per family, hold no lease.
    const abandoned = try std.fs.path.join(context.allocator, &.{ root, "objects", "abandoned" });
    const untouched = try std.fs.path.join(context.allocator, &.{ root, "exe", "abandoned" });
    try context.mkdir(abandoned);
    try context.mkdir(untouched);
    // A changed environment opens a new generation and removes the old one, in its family only.
    const second = try generation(context, root, "objects", "toolchain two");
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.testing.expect(context.exists(second));
    try std.testing.expect(!context.exists(abandoned));
    try std.testing.expect(context.exists(untouched));
    // This process still leases the generation it opened, so the sweep spared it.
    try std.testing.expectEqualStrings("one", try context.read(marker));
    try std.testing.expect(context.exists(executables));
    // The live identity is the native driver and the bundled runtime, nothing per process.
    try std.testing.expect(std.mem.indexOf(u8, generation_identity, bundled.driver_identity) != null);
    try std.testing.expect(std.mem.indexOf(u8, generation_identity, bundled.content_hash) != null);
    try std.testing.expect(std.mem.indexOf(u8, generation_identity, bundled.compiler_identity) == null);
}
// spec-case: NATIVE-PUBLISH-REPAIR-1
test "a link failure with every input still present is reported, never retried" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: cache_api.Cache = .{ .context = context, .directory = "objects", .temporary = "work", .assets = "/assets", .environment = "env", .zig = "/bin/false", .mode = "Debug", .codegen = .{ .tool = "/bin/false" } };
    var state = State{ .context = context, .cache = cache, .manifest = .null };
    state.runtime = .{ .key = "runtime", .path = "/bin/sh", .reused = true };
    // No object went missing, so the linker's own refusal is the answer and the
    // self-healing retry — which would recompile every unit — must not run.
    try std.testing.expect(state.inputsPresent());
    try std.testing.expectError(error.NativeToolFailed, state.linkOnce(.{}, "/dev/null/program"));
}
// spec: QBE-DRIVER-IDENTITY-1
test "the object environment names the native driver, never the whole compiler" {
    const a = std.testing.allocator;
    const text = try environmentJson(a, .{ .zig = "zig-stamp", .backend = "qbe", .backend_tool = "qbe-stamp", .optimization = "default", .lto = .off, .zig_version = bundled.zig_version, .mode = "Debug", .target = "native" });
    defer a.free(text);
    try std.testing.expect(!std.mem.eql(u8, bundled.driver_identity, bundled.compiler_identity));
    try std.testing.expect(std.mem.indexOf(u8, text, bundled.driver_identity) != null);
    try std.testing.expect(std.mem.indexOf(u8, text, bundled.content_hash) != null);
    // An edit to a compiler source that is not a build driver moves only
    // `compiler_identity`, which this environment does not name, so every cached
    // object and executable whose IL is unchanged still keys the same.
    try std.testing.expect(std.mem.indexOf(u8, text, bundled.compiler_identity) == null);
    const same = try environmentJson(a, .{ .zig = "zig-stamp", .backend = "qbe", .backend_tool = "qbe-stamp", .optimization = "default", .lto = .off, .zig_version = bundled.zig_version, .mode = "Debug", .target = "native" });
    defer a.free(same);
    try std.testing.expectEqualStrings(text, same);
}

test "LLVM optimization LTO and target policy change native object identity" {
    const a = std.testing.allocator;
    const base: Environment = .{ .zig = "zig-stamp", .backend = "llvm", .backend_tool = "mylang-llvm-translator-v1", .optimization = "3", .lto = .off, .zig_version = bundled.zig_version, .mode = "ReleaseFast", .target = "amd64_sysv" };
    const o3 = try environmentJson(a, base);
    defer a.free(o3);
    var changed = base;
    changed.optimization = "2";
    const o2 = try environmentJson(a, changed);
    defer a.free(o2);
    changed = base;
    changed.lto = .full;
    const lto = try environmentJson(a, changed);
    defer a.free(lto);
    changed = base;
    changed.lto = .thin;
    const thin = try environmentJson(a, changed);
    defer a.free(thin);
    changed = base;
    changed.target_cpu = "x86-64-v3";
    const cpu = try environmentJson(a, changed);
    defer a.free(cpu);
    changed = base;
    changed.target_features = "+avx,+avx2,-avx512f";
    const features = try environmentJson(a, changed);
    defer a.free(features);
    try std.testing.expect(!std.mem.eql(u8, o3, o2));
    try std.testing.expect(!std.mem.eql(u8, o3, lto));
    // Thin bitcode never answers for full bitcode (LLVM-THINLTO-1).
    try std.testing.expect(!std.mem.eql(u8, lto, thin));
    try std.testing.expect(!std.mem.eql(u8, o3, cpu));
    try std.testing.expect(!std.mem.eql(u8, o3, features));
}
// spec-case: QBE-3
test "a default build shares the runtime root while an explicit cache-dir keeps it local" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try environment.put("XDG_CACHE_HOME", "/xdg");
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const shared = try runtimeRoot(context, .{ .cache = options.default_cache }, "/project/.mylang-cache/qbe");
    try std.testing.expectEqualStrings("/xdg/mylang/runtime", shared);
    const local = try runtimeRoot(context, .{ .cache = "/tmp/hermetic" }, "/tmp/hermetic");
    try std.testing.expectEqualStrings("/tmp/hermetic/runtime", local);
    try std.testing.expectEqualStrings("/xdg/mylang/runtime", sharedRuntimeRoot(context).?);
    // `--no-cache` disables only the frontend reuse sentinel; the native cache
    // must still resolve to its default directory, not a directory named "none".
    try std.testing.expectEqualStrings(options.default_cache, nativeCacheDirectory(.{ .cache = options.no_cache }));
    try std.testing.expectEqualStrings("/xdg/mylang/runtime", try runtimeRoot(context, .{ .cache = options.no_cache }, "/project/.mylang-cache/qbe"));
}
// spec-case: QBE-3
test "an unwritable shared runtime root falls back to the project cache" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const base = try directory.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(base);
    const blocker = try std.fs.path.join(std.testing.allocator, &.{ base, "not-a-directory" });
    defer std.testing.allocator.free(blocker);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = blocker, .data = "x" });
    try environment.put("XDG_CACHE_HOME", blocker);
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache = try std.fs.path.join(std.testing.allocator, &.{ base, "qbe" });
    defer std.testing.allocator.free(cache);
    const assets = try materializeRuntime(context, .{ .cache = options.default_cache }, cache);
    try std.testing.expect(std.mem.startsWith(u8, assets, cache));
}
// spec: QBE-RUNTIME-INSTALLED-1
test "prebuilt runtime hashes separate kind, mode and backend flavor, and misses fall back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const archive_debug = try runtimeInstalledHash(a, "archive", "Debug", "qbe");
    const archive_release = try runtimeInstalledHash(a, "archive", "ReleaseFast", "qbe");
    const archive_llvm = try runtimeInstalledHash(a, "archive", "ReleaseFast", "llvm");
    const archive_lto = try runtimeInstalledHash(a, "archive", "ReleaseFast", "llvm-lto");
    const format_debug = try runtimeInstalledHash(a, "format", "Debug", "");
    try std.testing.expectEqual(@as(usize, 64), archive_debug.len);
    try std.testing.expect(!std.mem.eql(u8, archive_debug, archive_release));
    try std.testing.expect(!std.mem.eql(u8, archive_release, archive_llvm));
    try std.testing.expect(!std.mem.eql(u8, archive_llvm, archive_lto));
    try std.testing.expect(!std.mem.eql(u8, archive_debug, format_debug));
    try std.testing.expectEqualStrings(archive_debug, try runtimeInstalledHash(a, "archive", "Debug", "qbe"));
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    context.self_directory = "";
    try std.testing.expectEqual(@as(?cache_api.Object, null), try installedRuntime(context, "Debug", "archive", "qbe", ".a"));
    try std.testing.expect(!validInstalled(context, "/no/such/installed/runtime.a"));
    // The archive flavor names the selected backend and LTO policy.
    try std.testing.expectEqualStrings("qbe", runtimeFlavor(false, .off));
    try std.testing.expectEqualStrings("qbe", runtimeFlavor(false, .full));
    try std.testing.expectEqualStrings("llvm", runtimeFlavor(true, .off));
    try std.testing.expectEqualStrings("llvm-lto", runtimeFlavor(true, .full));
    try std.testing.expectEqualStrings("llvm-thinlto", runtimeFlavor(true, .thin));
}
// spec-case: QBE-2
test "shared library links bind their own data descriptor symbols" {
    try std.testing.expectEqual(@as(usize, 2), library_link_arguments.len);
    try std.testing.expectEqualStrings("-shared", library_link_arguments[0]);
    try std.testing.expectEqualStrings("-Wl,-Bsymbolic", library_link_arguments[1]);
}
// spec: BUILD-BACKEND-4
test "an unchanged executable is reused only while its link identity holds" {
    try std.testing.expect(native_link.hasInputs(&.{ "main.my", "--link", "a.c" }));
    try std.testing.expect(native_link.hasInputs(&.{ "main.my", "--link=a.c" }));
    try std.testing.expect(native_link.hasInputs(&.{ "main.my", "--library-path", "lib" }));
    try std.testing.expect(native_link.hasInputs(&.{ "main.my", "--link-library", "m" }));
    try std.testing.expect(!native_link.hasInputs(&.{ "main.my", "-o", "out", "--qbe", "/qbe" }));
    try std.testing.expect(!native_link.hasInputs(&.{ "main.my", "--project", "--mode", "ReleaseFast" }));
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const cache: cache_api.Cache = .{
        .context = context,
        .directory = "objects",
        .temporary = "work",
        .assets = "/assets",
        .environment = "env",
        .zig = "/bin/true",
        .mode = "ReleaseFast",
        .codegen = .{ .tool = "/zig", .llvm = true, .optimization = "3", .lto = .full },
    };
    var state = State{ .context = context, .cache = cache, .manifest = .null };
    state.runtime = .{ .key = "runtime", .path = "/installed/runtime.a", .reused = true };
    try state.objects.append(context.allocator, "/objects/a.o");
    const first = try state.linkIdentity(.{ .mode = "ReleaseFast" });
    try std.testing.expectEqualStrings(first, try state.linkIdentity(.{ .mode = "ReleaseFast" }));
    // A different mode, symbol policy or object set is a different link.
    try std.testing.expect(!std.mem.eql(u8, first, try state.linkIdentity(.{ .mode = "Debug" })));
    try std.testing.expect(!std.mem.eql(u8, first, try state.linkIdentity(.{ .mode = "ReleaseFast", .link_arguments = &.{"--keep-symbols"} })));
    try state.objects.append(context.allocator, "/objects/b.o");
    try std.testing.expect(!std.mem.eql(u8, first, try state.linkIdentity(.{ .mode = "ReleaseFast" })));
}
