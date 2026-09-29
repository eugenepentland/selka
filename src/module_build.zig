//! MODULE-SCHEDULE-1..3: `mylang build` of a project, one module at a time.
//!
//! The build discovers the project's modules from their headers (a module
//! whose source digest is unchanged keeps the imports its last build read),
//! and compiles each one that is stale with `compile-module --ready` in a
//! child process, over the import graph, as many at once as the cores and
//! free memory allow. A module is stale when it has no record, its source or
//! the program's arena switch changed, or an interface its last compile read
//! (by interface, emission and positions hash) is not the one there now. A
//! compile signals as soon as its interface is written, so its dependents start
//! while its units and objects are still being built, and a dependent whose
//! inputs all held stays as it is: a body edit compiles one module, and an
//! interface edit only the modules that read what changed (early cutoff).
//!
//! The link reads one record per module (its objects in link order, the
//! digest of its share of the program-wide metadata unit, its warnings) from
//! one state file, never a unit: the objects are ordered as a whole-program
//! build orders them, the metadata unit is found by a key over the modules'
//! shares and rendered only on a miss, and a specialization several modules
//! emitted is linked once. The executable is the whole-program build's, byte
//! for byte. Anything this path does not handle — a library, the LLVM
//! backend, a provider, a `mylang.json`, a header or check error — goes to the
//! whole-program build, which reports it exactly as before.
const std = @import("std");
// The compiler reaches the language through its `mylang` module and a test
// root holds every source file in one module, so the application or test root
// hands it over, as it hands `native_test_snapshot` its project loader.
const language = @import("native_test_root").compiler_language;
const native_build = @import("qbe_build.zig");
const options = @import("qbe_build_options.zig");
const fs = @import("qbe_build_io.zig");
const spawn = @import("qbe_build_spawn.zig");
const outputs = @import("qbe_build_outputs.zig");
const budget = @import("memory_budget");
const interface_command = @import("module_interface_command.zig");
const compile_command = @import("module_compile_command.zig");
const project_config = @import("project_config.zig");
const module_syntax = @import("module_syntax.zig");

const native_test_contracts = @import("native_test_contracts.zig");
const Blake = std.crypto.hash.Blake3;
const Map = std.array_hash_map.String;
const json_value = @import("qbe_build_value.zig");
const field = json_value.get;
const items = json_value.array;
const stringOf = json_value.text;
const state_version = "module-build-state-v2";
/// The file in a variant's directory that holds its modules' records.
const state_file = "state.json";
/// Resident memory one module compile (and the tools it starts) is budgeted
/// for when the pool is sized from `MemAvailable`.
const child_ceiling: u64 = 256 << 20;

/// What a per-module build can fail with: the driver's errors, and a module
/// header or source the build could not read.
pub const Error = native_build.Error || error{ ReadFailed, InternalError, SourceError };

/// Why a project build went to the whole-program path instead.
pub const Fallback = enum { options, entry, project, config, compile, conflict, cold, busy };

/// What a per-module build did: finished with an exit status, or handed the
/// build to the whole-program path for `Fallback`.
pub const Outcome = union(enum) { status: u8, fallback: Fallback };

/// A module's interface, emission and positions hashes.
const Hashes = struct { interface: []const u8, emission: []const u8, positions: []const u8 };

/// One interface a compile read, and its hashes then.
const Input = struct { module: []const u8, interface: []const u8, emission: []const u8, positions: []const u8 };

/// Whether a module's units open an arena scope or need the text runtime.
const Marks = struct { arena: bool = false, text: bool = false };

/// What the state file keeps about one module.
const ModuleState = struct {
    name: []const u8,
    digest: []const u8,
    imports: []const []const u8,
    arenas: bool,
    hashes: Hashes,
    inputs: []const Input = &.{},
    marks: Marks = .{},
    text_format: bool = false,
    warnings: []const u8 = "",
    placed: []const native_build.Placed = &.{},
    shared: []const u8 = "",
    entry: ?[]const u8 = null,
    objects: ?[]const u8 = null,
    /// Warnings its compile reported in other modules' text.
    foreign: []const Foreign = &.{},
};

/// A test run's merged test documents.
const MergedTests = struct { graph: []const u8, library: LibraryParts, contracts: std.json.Value };

/// The last merge of a test variant, behind the key of the records it was
/// merged from.
const MergedFile = struct {
    key: []const u8,
    graph: []const u8,
    library: struct { roots: std.json.Value, schema: []const u8, wire: std.json.Value, codecs: std.json.Value },
    contracts: std.json.Value,
};

/// The schema of every module's tests and benchmarks, as one document: the
/// union of their functions, types and exported names, each sorted as the
/// schema renderer sorts them.
fn mergedSchema(allocator: std.mem.Allocator, entry: []const u8, schemas: []const std.json.Value) ![]const u8 {
    var functions: Map(std.json.Value) = .empty;
    var types: Map(std.json.Value) = .empty;
    var exported: Map(std.json.Value) = .empty;
    for (schemas) |schema| {
        for (items(field(schema, native_test_contracts.functions_key))) |item| _ = try putFirst(std.json.Value, allocator, &functions, stringOf(field(item, "name")), item);
        for (items(field(schema, "types"))) |item| _ = try putFirst(std.json.Value, allocator, &types, stringOf(field(item, "name")), item);
        for (items(field(schema, "exports"))) |item| _ = try putFirst(std.json.Value, allocator, &exported, stringOf(item), item);
    }
    var document: std.json.ObjectMap = .empty;
    try document.put(allocator, "version", .{ .string = "language-schema-v1" });
    try document.put(allocator, "scope", .{ .string = "reachable-module-exports" });
    try document.put(allocator, "representation", .{ .string = "language-contracts-no-wire-format-or-abi" });
    try document.put(allocator, "entry", .{ .string = entry });
    try document.put(allocator, "exports", .{ .array = try arrayOf(allocator, try sortedValues(allocator, exported)) });
    try document.put(allocator, native_test_contracts.functions_key, .{ .array = try arrayOf(allocator, try sortedValues(allocator, functions)) });
    try document.put(allocator, "types", .{ .array = try arrayOf(allocator, try sortedValues(allocator, types)) });
    return std.json.Stringify.valueAlloc(allocator, std.json.Value{ .object = document }, .{});
}

/// MODULE-TEST-2: the codec metadata of every module merged the way
/// `qbe_codecs.canonical` orders one program's: types by name with their
/// descriptors, codecs by domain, callbacks by symbol, and every method
/// numbered by its callback's position.
fn mergedCodecs(allocator: std.mem.Allocator, types: Map(std.json.Value), codecs: Map(std.json.Value), callbacks: Map(std.json.Value), validations: Map(std.json.Value)) !std.json.Value {
    const sorted_types = try sortedValues(allocator, types);
    var type_items = std.json.Array.init(allocator);
    var descriptor_items = std.json.Array.init(allocator);
    for (sorted_types) |pair| {
        try type_items.append(pair.array.items[0]);
        try descriptor_items.append(pair.array.items[1]);
    }
    const sorted_callbacks = try sortedValues(allocator, callbacks);
    var callback_items = std.json.Array.init(allocator);
    var positions: Map(usize) = .empty;
    for (sorted_callbacks, 0..) |callback, index| {
        var numbered = callback;
        numbered.object = try callback.object.clone(allocator);
        try numbered.object.put(allocator, "index", .{ .integer = @intCast(index) });
        try callback_items.append(numbered);
        try positions.put(allocator, stringOf(field(callback, "symbol")), index);
    }
    var codec_items = std.json.Array.init(allocator);
    for (try sortedValues(allocator, codecs)) |codec| {
        var numbered = codec;
        numbered.object = try codec.object.clone(allocator);
        for ([_][]const u8{ "decode", "encode" }) |key| {
            const at = positions.get(stringOf(field(codec, key))) orelse return error.InvalidNativeManifest;
            try numbered.object.put(allocator, key, .{ .integer = @intCast(at) });
        }
        try codec_items.append(numbered);
    }
    var table: std.json.ObjectMap = .empty;
    try table.put(allocator, "types", .{ .array = type_items });
    try table.put(allocator, "descriptors", .{ .array = descriptor_items });
    try table.put(allocator, "codecs", .{ .array = codec_items });
    try table.put(allocator, "callbacks", .{ .array = callback_items });
    var validation_items = std.json.Array.init(allocator);
    for (try sortedValues(allocator, validations), 0..) |validation, index| {
        var numbered = validation;
        numbered.object = try validation.object.clone(allocator);
        try numbered.object.put(allocator, "index", .{ .integer = @intCast(index) });
        try validation_items.append(numbered);
    }
    try table.put(allocator, "validations", .{ .array = validation_items });
    return .{ .object = table };
}

fn arrayOf(allocator: std.mem.Allocator, values: []const std.json.Value) !std.json.Array {
    var out = std.json.Array.init(allocator);
    try out.appendSlice(values);
    return out;
}

fn unnumbered(a: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    if (value != .object) return error.InvalidNativeManifest;
    var out = value;
    out.object = try value.object.clone(a);
    _ = out.object.orderedRemove("index");
    return out;
}

fn putFirst(comptime T: type, a: std.mem.Allocator, map: *Map(T), name: []const u8, value: T) !bool {
    if (name.len == 0) return error.InvalidNativeManifest;
    const slot = try map.getOrPut(a, name);
    if (!slot.found_existing) {
        slot.value_ptr.* = value;
        return true;
    }
    const previous = try std.json.Stringify.valueAlloc(a, slot.value_ptr.*, .{});
    const next = try std.json.Stringify.valueAlloc(a, value, .{});
    if (!std.mem.eql(u8, previous, next)) return error.InvalidNativeManifest;
    return false;
}

fn sortedValues(a: std.mem.Allocator, map: Map(std.json.Value)) ![]const std.json.Value {
    const keys = try a.dupe([]const u8, map.keys());
    std.mem.sort([]const u8, keys, {}, struct {
        fn before(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.before);
    const out = try a.alloc(std.json.Value, keys.len);
    for (keys, out) |key, *value| value.* = map.get(key).?;
    return out;
}

/// A warning a compile reported in another module's text, rendered.
const Foreign = struct { module: []const u8, text: []const u8 };

/// The state file of one build variant.
const StateFile = struct { version: []const u8 = state_version, arenas: bool = false, modules: []const ModuleState = &.{} };

const Status = enum { waiting, running, ready, done, failed };

/// One module of the program as this build found it.
const Node = struct {
    name: []const u8,
    digest: []const u8,
    imports: []const []const u8,
    /// Whether its source mentions an arena scope (the switch's first guess).
    arena_text: bool,
    /// Its source's length, for the project's byte budgets.
    bytes: usize,
    /// Indices of the modules it imports.
    deps: []const usize = &.{},
    status: Status = .waiting,
    /// Its interface, emission and positions hashes once they are final.
    current: ?Hashes = null,
    /// Its record once this build has one: its last compile's, or this build's.
    record: ?ModuleState = null,
    /// Whether this build compiled it, and whether that compiled any object.
    compiled: bool = false,
    objects_compiled: bool = false,
};

/// A running compile and what it wrote to standard error so far.
const Running = struct { node: usize, started: spawn.Started, stderr: std.ArrayList(u8) = .empty };

/// What a build variant is keyed by; the standard modules' shared variant
/// has no entry.
const VariantKey = struct { switches: native_build.Switches, place: VariantPlace, identity: []const u8, source: ?[]const u8 };

/// Where a session's variants live (the cache root) and the build
/// environment their objects are built in; a check's is a fixed marker.
const VariantPlace = struct { root: []const u8, environment: []const u8 };

/// The entry of a per-module build: the I/O and environment it
/// runs with, the build arguments, where its phases go, and the compiler
/// identity its outputs are keyed by.
pub const Request = struct {
    io: std.Io,
    environ: *const std.process.Environ.Map,
    args: []const []const u8,
    phases: ?*native_build.PhaseTimings = null,
    identity: []const u8,
};

/// Build the project `request.args` names module by module, or say why it
/// must go to the whole-program path.
pub fn build(gpa: std.mem.Allocator, request: Request) Error!Outcome {
    const parsed = options.parse(request.args) catch return .{ .fallback = .options };
    var context = try fs.Context.init(gpa, request.io, request.environ);
    defer context.deinit();
    const a = context.allocator;
    var session: Session = undefined;
    switch (try Session.open(&session, context, .{ .parsed = parsed, .switches = native_build.emissionSwitches(parsed), .identity = request.identity })) {
        .ready => {},
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    }
    defer session.close();
    const program = switch (try session.compile()) {
        .ready => |ready| ready,
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    };
    return .{ .status = try native_build.linkModules(session.prepared.?, parsed, program, .{
        .frontend = seconds(context, session.start),
        .phases = request.phases,
        .controls = try native_build.runtimeControls(a, request.args),
        .report = try session.report(),
    }) };
}

/// What `mylang run` of a project hands the per-module build: the build
/// settings it runs with (mode, tools, cache), the emission switches its
/// policy asks for, and the compiler identity.
pub const RunRequest = struct {
    io: std.Io,
    environ: *const std.process.Environ.Map,
    settings: options.Options,
    switches: native_build.Switches,
    identity: []const u8,
};

/// What a per-module build for `run` did: the executable to run, an exit
/// status to stop with, or a reason to take the whole-program path.
pub const RunOutcome = union(enum) { executable: []const u8, status: u8, fallback: Fallback };

/// MODULE-SCHEDULE-3: build the project `mylang run` names module by module
/// into the run cache, named by the program's identity, so an unchanged
/// program runs the executable it already has; `gpa` owns the path.
pub fn buildForRun(gpa: std.mem.Allocator, request: RunRequest) Error!RunOutcome {
    var context = try fs.Context.init(gpa, request.io, request.environ);
    defer context.deinit();
    var session: Session = undefined;
    switch (try Session.open(&session, context, .{ .parsed = request.settings, .switches = request.switches, .identity = request.identity })) {
        .ready => {},
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    }
    defer session.close();
    const program = switch (try session.compile()) {
        .ready => |ready| ready,
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    };
    // MODULE-PROJECT-1: a project whose `mylang.json` denies warnings runs no
    // program that has one; the warnings are already printed.
    if (session.state.configured.deny_warnings and session.state.warned()) return .{ .status = 1 };
    const home = try native_build.generation(context, session.prepared.?.root, "run", native_build.generation_identity);
    const path = try std.fs.path.join(context.allocator, &.{ home, try std.fmt.allocPrint(context.allocator, "modules-{s}", .{program.identity}) });
    if (!context.runnable(path)) {
        var settings = request.settings;
        settings.run = false;
        settings.report = false;
        settings.output = path;
        const status = try native_build.linkModules(session.prepared.?, settings, program, .{ .frontend = seconds(context, session.start), .phases = null, .controls = &.{} });
        if (status != 0) return .{ .status = status };
    }
    return .{ .executable = try gpa.dupe(u8, path) };
}

/// MODULE-TEST-1: what a test run hands the per-module build: the settings
/// of its test library (entry, object cache, mode, tools), the emission
/// switches a library in that mode is built with, and the compiler identity.
pub const TestRequest = struct {
    settings: options.Options,
    switches: native_build.Switches,
    identity: []const u8,
    /// MODULE-TEST-5: from how many modules a first run leaves the answer to
    /// the whole-program path (`Fallback.cold`); null always compiles.
    cold: ?usize = null,
};

/// MODULE-TEST-1: a project a test run compiled module by module, its merged
/// test facts, and what a test library of its tests links from.
pub const Tests = struct {
    session: Session,
    program: native_build.ModuleProgram,
    /// The `native-test-graph-v3` facts of the tests' dependency closure.
    graph: []const u8,
    library: LibraryParts,
    /// The modules this run compiled, in the order they finished.
    compiled: []const []const u8,
    /// MODULE-TEST-4: the declaration contracts of every module
    /// (`interface-contracts-v2`), which the run discovers its tests from.
    contracts: std.json.Value,

    /// Link the test executable `target.output` from the modules' objects,
    /// the harness object and a wrapper exporting the tests and benchmarks
    /// `target.names` (MODULE-TEST-3); the link's exit status.
    pub fn link(self: *Tests, target: TestTarget) Error!u8 {
        const context = self.session.state.context;
        const a = context.allocator;
        var functions = std.json.Array.init(a);
        for (target.names) |name| {
            const root = self.library.roots.get(name) orelse return error.InvalidNativeManifest;
            try functions.append(root);
        }
        var manifest: std.json.ObjectMap = .empty;
        try manifest.put(a, "entry", .{ .string = "" });
        try manifest.put(a, "entry_parameters", .{ .array = std.json.Array.init(a) });
        try manifest.put(a, "schema", .{ .string = self.library.schema });
        try manifest.put(a, native_test_contracts.functions_key, .{ .array = functions });
        try manifest.put(a, "wire_types", self.library.wire);
        try manifest.put(a, "codecs", self.library.codecs);
        const wrapper = @import("qbe_build_embed.zig").libraryWrapper(a, .{ .object = manifest }) catch |err| return invalidBlocks(err);
        var program = self.program;
        program.library = wrapper;
        var identity = Blake.init(.{});
        frame(&identity, self.program.identity);
        frame(&identity, wrapper);
        frame(&identity, target.harness);
        var digest: [32]u8 = undefined;
        identity.final(&digest);
        program.identity = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
        var settings = self.session.state.parsed;
        settings.output = target.output;
        settings.report = false;
        settings.run = false;
        settings.link_arguments = try a.dupe([]const u8, &.{ "--link", target.harness });
        return native_build.linkModules(self.session.prepared.?, settings, program, .{ .frontend = 0, .phases = null, .controls = &.{} });
    }

    /// Release the variants' locks and the build's staging directory.
    pub fn close(self: *Tests) void {
        self.session.close();
    }
};

/// What a test executable links: the tests and benchmarks it exports, its
/// path and the harness object it runs them with.
pub const TestTarget = struct { names: []const []const u8, output: []const u8, harness: []const u8 };

/// What a test library's wrapper is written from, merged over the modules:
/// each root's symbol and export description by name, the schema, the wire
/// table and the codec metadata (MODULE-TEST-2).
pub const LibraryParts = struct { roots: Map(std.json.Value), schema: []const u8, wire: std.json.Value, codecs: std.json.Value };

/// What opening a test run's per-module build did.
pub const TestsOutcome = union(enum) { ready: *Tests, status: u8, fallback: Fallback };

/// MODULE-TEST-1: compile the project a test run names module by module,
/// with each module's test document, and merge those into the facts of the
/// tests' closure; or say why the whole-program test path must run it.
pub fn openTests(context: fs.Context, request: TestRequest) Error!TestsOutcome {
    const tests = try context.allocator.create(Tests);
    // MODULE-TEST-6: a run waits for nobody: while a seeder or another run
    // holds its program's variant or the standard modules' shared one, the
    // whole-program run answers (`Fallback.busy`). Only the seeder waits.
    const settings: Settings = .{ .parsed = request.settings, .switches = request.switches, .identity = request.identity, .mode = .tests, .wait = request.cold == null };
    switch (try Session.open(&tests.session, context, settings)) {
        .ready => {},
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    }
    // The session stays open only for a caller handed the tests.
    var kept = false;
    defer if (!kept) tests.session.close();
    tests.program = switch (try tests.session.compileWithin(request.cold)) {
        .ready => |ready| ready,
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    };
    const state = &tests.session.state;
    var compiled: std.ArrayList([]const u8) = .empty;
    for (state.nodes.items) |node| if (node.compiled) try compiled.append(context.allocator, node.name);
    tests.compiled = compiled.items;
    const merged = (try state.mergeTests()) orelse return .{ .fallback = .conflict };
    tests.graph = merged.graph;
    tests.library = merged.library;
    tests.contracts = merged.contracts;
    kept = true;
    return .{ .ready = tests };
}

/// The switches a check's variant is keyed by: a check emits nothing, so
/// one fixed set.
const check_switches: native_build.Switches = .{ .drop_debug = false, .step_checks = true, .frame_checks = true };

/// What `mylang check` of a project hands the per-module check: the entry,
/// the cache root its variants live under, and the compiler identity.
pub const CheckRequest = struct {
    io: std.Io,
    environ: *const std.process.Environ.Map,
    source: []const u8,
    cache: []const u8,
    identity: []const u8,
    /// MODULE-CHECK-2: build the module records a later check reads, waiting
    /// for the variant and printing nothing (the detached seeder).
    seed: bool = false,
};

/// MODULE-CHECK-2, MODULE-TEST-5: how many modules make a first check or
/// test run take the whole-program path and seed the module records in the
/// background, unless an environment variable says otherwise.
pub const seed_threshold: usize = 64;

/// MODULE-CHECK-1: check the project `request.source` names module by
/// module, re-checking only the modules whose source or read interfaces
/// changed; or say why the whole-program check must.
pub fn check(gpa: std.mem.Allocator, request: CheckRequest) Error!Outcome {
    var context = try fs.Context.init(gpa, request.io, request.environ);
    defer context.deinit();
    var session: Session = undefined;
    // A check waits for nobody: while a seeder or another check holds the
    // variant, the whole-program check answers.
    const settings: Settings = .{ .parsed = .{ .source = request.source, .cache = request.cache }, .switches = check_switches, .identity = request.identity, .mode = .check, .wait = request.seed };
    // MODULE-TEST-6: the seeder yields the cores to every foreground run.
    if (request.seed) compile_command.lowerPriority(compile_command.seeder_priority);
    switch (try Session.open(&session, context, settings)) {
        .ready => {},
        .status => |status| return .{ .status = status },
        .fallback => |why| return .{ .fallback = why },
    }
    const threshold = if (request.environ.get("MYLANG_CHECK_SEED_MODULES")) |text| std.fmt.parseInt(usize, text, 10) catch seed_threshold else seed_threshold;
    const outcome: Outcome = switch (try session.check(.{ .seed = request.seed, .threshold = threshold })) {
        .ready, .status => |status| .{ .status = status },
        .fallback => |why| .{ .fallback = why },
    };
    session.close();
    if (outcome == .fallback and outcome.fallback == .cold) spawnSeeder(context, request);
    return outcome;
}

/// MODULE-CHECK-2: start `mylang check` of the same entry as a detached
/// seeder (`MYLANG_CHECK_SEED=1`, no standard streams, never waited for),
/// unless `MYLANG_CHECK_SEED` is `off`. A failure to start it only means the
/// next check seeds.
fn spawnSeeder(context: fs.Context, request: CheckRequest) void {
    if (request.environ.get("MYLANG_CHECK_SEED")) |value| if (std.mem.eql(u8, value, "off")) return;
    const a = context.allocator;
    var environ = request.environ.clone(a) catch return;
    environ.put("MYLANG_CHECK_SEED", "1") catch return;
    const self_exe = std.Io.Dir.cwd().realPathFileAlloc(context.io, "/proc/self/exe", a) catch return;
    const cache = std.fmt.allocPrint(a, "--cache-dir={s}", .{request.cache}) catch return;
    _ = std.process.spawn(context.io, .{
        .argv = &.{ self_exe, "check", request.source, cache },
        .environ_map = &environ,
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
        .pgid = 0,
    }) catch return;
}

/// What one step of a session did: done (with its value), an exit status to
/// stop with, or a reason to take the whole-program path.
fn Step(comptime T: type) type {
    return union(enum) { ready: T, status: u8, fallback: Fallback };
}

/// What a session works toward: an executable from its modules' objects, a
/// check of its modules alone (MODULE-CHECK-1), or a test library from its
/// modules' objects and test documents (MODULE-TEST-1).
const Mode = enum { build, check, tests };

/// What a session is opened with; `wait` false leaves a held variant to the
/// whole-program path (`Fallback.busy`) instead of waiting for it.
const Settings = struct { parsed: options.Options, switches: native_build.Switches, identity: []const u8, mode: Mode = .build, wait: bool = true };

/// How a check session runs: as the detached seeder, and from how many
/// modules a first check leaves the answer to the whole-program check.
const CheckRun = struct { seed: bool, threshold: usize };

/// One per-module build from its entry to the program it links: the build
/// state, the prepared toolchain and cache, and the locks it holds on the
/// program's variant and on the standard modules' shared one.
const Session = struct {
    state: Build,
    /// The toolchain and object cache; a check needs neither.
    prepared: ?native_build.Prepared,
    locks: [2]std.Io.File,
    start: std.Io.Timestamp,

    /// Check the build can go this way, prepare the toolchain and take the
    /// variant.
    fn open(self: *Session, context: fs.Context, settings: Settings) !Step(void) {
        const parsed = settings.parsed;
        if (!eligible(parsed)) return .{ .fallback = .options };
        const a = context.allocator;
        const source = try context.absolute(parsed.source);
        const raw = context.read(source) catch return .{ .fallback = .entry };
        if (!parsed.project and !module_syntax.usesModuleSyntax(raw)) return .{ .fallback = .entry };
        if (!project_config.declaresMain(raw)) return .{ .fallback = .entry };
        // MODULE-PROJECT-1: a `mylang.json` that does not load, or whose
        // import policy does not parse, is the whole-program path's to report.
        const configured = (try configuredProject(context, source)) orelse return .{ .fallback = .config };
        const entry = (try interface_command.entryOf(a, context.io, source)) orelse return .{ .fallback = .entry };
        const prepared: ?native_build.Prepared = if (settings.mode == .check) null else native_build.prepare(context, parsed) catch |err| switch (err) {
            error.NativeToolFailed => return .{ .status = 2 },
            else => return err,
        };
        const place: VariantPlace = if (prepared) |ready| .{
            .root = ready.root,
            // A test run's compiles write test documents too.
            .environment = if (settings.mode == .tests) try std.mem.concat(a, u8, &.{ ready.cache.environment, "\x00tests" }) else ready.cache.environment,
        } else .{ .root = try native_build.cacheRoot(context, parsed), .environment = "\x00check" };
        const key: VariantKey = .{ .switches = settings.switches, .place = place, .identity = settings.identity, .source = source };
        self.* = .{
            .prepared = prepared,
            .start = std.Io.Timestamp.now(context.io, .awake),
            .locks = undefined,
            .state = .{
                .context = context,
                .parsed = parsed,
                .entry = .{ .root = entry.root, .name = entry.name, .bytes = entry.bytes, .path = source },
                .variant = try variantDirectory(context, key),
                .standard = try variantDirectory(context, .{ .switches = key.switches, .place = place, .identity = key.identity, .source = null }),
                .switches = settings.switches,
                .configured = configured,
                .mode = settings.mode,
            },
        };
        errdefer if (prepared) |ready| context.remove(ready.cache.temporary);
        try context.mkdir(self.state.variant);
        try context.mkdir(self.state.standard);
        // Always the program's variant first: two builds never wait on each other in turn.
        self.locks[0] = (try lockVariant(context, self.state.variant, settings.wait)) orelse {
            if (prepared) |ready| context.remove(ready.cache.temporary);
            return .{ .fallback = .busy };
        };
        self.locks[1] = (try lockVariant(context, self.state.standard, settings.wait)) orelse {
            self.locks[0].close(context.io);
            if (prepared) |ready| context.remove(ready.cache.temporary);
            return .{ .fallback = .busy };
        };
        return .{ .ready = {} };
    }

    fn close(self: *Session) void {
        for (self.locks) |lock| lock.close(self.state.context.io);
        if (self.prepared) |ready| self.state.context.remove(ready.cache.temporary);
    }

    /// MODULE-CHECK-1: check every stale module against its imports'
    /// interfaces and replay every module's warnings; the check's exit
    /// status. A module that does not check, or a warning a module reported
    /// in another's text that the other's own check did not, is the
    /// whole-program check's to report.
    fn check(self: *Session, run: CheckRun) !Step(u8) {
        const state = &self.state;
        try state.loadState();
        if (!try state.discover()) return .{ .fallback = .project };
        if (!state.withinBudgets() or state.policyDenies()) return .{ .fallback = .config };
        // MODULE-CHECK-2: a large project checked for the first time is one
        // whole-program pass, cheaper than a chain of module checks; the
        // detached seeder then builds the records the next check reads.
        if (!run.seed and state.firstLarge(run.threshold)) return .{ .fallback = .cold };
        const checked = try state.schedule();
        try state.saveState();
        if (!checked) return .{ .fallback = .compile };
        if (!state.foreignReported()) return .{ .fallback = .conflict };
        if (run.seed) return .{ .ready = 0 };
        try state.printWarnings();
        // A project whose `mylang.json` denies warnings fails a check that has one.
        return .{ .ready = if (state.configured.deny_warnings and state.warned()) 1 else 0 };
    }

    /// Compile every stale module and assemble the program to link.
    fn compile(self: *Session) !Step(native_build.ModuleProgram) {
        return self.compileWithin(null);
    }

    /// `compile`, leaving a first build of at least `cold` modules to the
    /// whole-program path (MODULE-TEST-5).
    fn compileWithin(self: *Session, cold: ?usize) !Step(native_build.ModuleProgram) {
        const state = &self.state;
        try state.loadState();
        if (!try state.discover()) return .{ .fallback = .project };
        if (cold) |threshold| if (state.firstLarge(threshold)) return .{ .fallback = .cold };
        // MODULE-PROJECT-1: a graph over its source budgets, or with an import
        // the policy denies, is reported by the whole-program path.
        if (!state.withinBudgets() or state.policyDenies()) return .{ .fallback = .config };
        state.arenas = state.guessArenas();
        if (!try state.scheduleSaved()) return .{ .fallback = .compile };
        // The arena switch is the program's: when the compiles say it is other
        // than the one they were compiled under, every module compiles again.
        if (state.programArenas() != state.arenas) {
            state.arenas = !state.arenas;
            try state.restart();
            if (!try state.scheduleSaved()) return .{ .fallback = .compile };
        }
        // An object a sweep removed since its module's last compile is rebuilt
        // with that module.
        if (try state.markMissingObjects()) if (!try state.scheduleSaved()) return .{ .fallback = .compile };
        try state.saveState();
        if (!state.foreignReported()) return .{ .fallback = .conflict };
        if (state.mode != .tests) try state.printWarnings();
        const program = (try state.program()) orelse return .{ .fallback = .conflict };
        return .{ .ready = program };
    }

    /// The scheduler's own `--report` fields.
    fn report(self: *Session) !std.json.Value {
        const state = &self.state;
        const a = state.context.allocator;
        return std.json.parseFromSliceLeaky(std.json.Value, a, try std.json.Stringify.valueAlloc(a, .{
            .modules = state.nodes.items.len,
            .compiled = state.compiled,
            .reused = state.nodes.items.len - state.compiled,
            .arenas = state.arenas,
        }, .{}), .{});
    }
};

/// Whether these build options can go through the per-module path: an
/// executable of the QBE backend with a cache, and no provider, selection,
/// checked manifest or `--whole-program`.
fn eligible(parsed: options.Options) bool {
    if (parsed.library or parsed.provider != null) return false;
    if (options.noCache(parsed)) return false;
    if (parsed.codegen == .llvm) return false;
    for (parsed.link_arguments) |argument| {
        if (std.mem.eql(u8, argument, "--")) break;
        if (std.mem.eql(u8, argument, options.whole_program_flag) or std.mem.eql(u8, argument, "--module-objects")) return false;
        if (std.mem.startsWith(u8, argument, "--select-file") or std.mem.startsWith(u8, argument, "--manifest-file")) return false;
        if (std.mem.startsWith(u8, argument, "--diagnostics=")) return false;
    }
    return true;
}

/// The directory of one build variant under the cache: the compiler identity,
/// the entry, the emission switches and the objects' build environment.
fn variantDirectory(context: fs.Context, key: VariantKey) ![]const u8 {
    var hash = Blake.init(.{});
    frame(&hash, state_version);
    frame(&hash, key.identity);
    frame(&hash, key.source orelse "\x00standard");
    frame(&hash, language.runtime_mode.identity());
    hash.update(&.{ @intFromBool(language.value_semantics.enabled()), @intFromBool(language.value_semantics.counting()) });
    const switches = key.switches;
    hash.update(&.{ @intFromBool(switches.drop_debug), @intFromBool(switches.step_checks), @intFromBool(switches.frame_checks) });
    frame(&hash, key.place.environment);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    const name = if (key.source == null) try std.fmt.allocPrint(context.allocator, "standard-{x}", .{digest}) else try std.fmt.allocPrint(context.allocator, "{x}", .{digest});
    return std.fs.path.join(context.allocator, &.{ key.place.root, "modules", name });
}

/// Hold the variant for this build: a concurrent build of the same program
/// waits rather than interleaving its compiles and state with this one's,
/// unless it may not `wait`, when a held variant answers null.
fn lockVariant(context: fs.Context, variant: []const u8, wait: bool) !?std.Io.File {
    const path = try std.fs.path.join(context.allocator, &.{ variant, ".lock" });
    const file = std.Io.Dir.cwd().createFile(context.io, path, .{ .truncate = false }) catch return error.WriteFailed;
    if (!wait) {
        const held = file.tryLock(context.io, .exclusive) catch {
            file.close(context.io);
            return error.WriteFailed;
        };
        if (held) return file;
        file.close(context.io);
        return null;
    }
    file.lock(context.io, .exclusive) catch {
        file.close(context.io);
        return error.WriteFailed;
    };
    return file;
}

fn frame(hash: *Blake, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

fn seconds(context: fs.Context, start: std.Io.Timestamp) f64 {
    const elapsed = start.durationTo(std.Io.Timestamp.now(context.io, .awake)).nanoseconds;
    return @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s;
}

/// The program's entry: its import root, module name, source (as the compile
/// reads it) and absolute path.
const Entry = struct { root: []const u8, name: []const u8, bytes: []const u8, path: []const u8 };

/// Everything one per-module build works with.
const Build = struct {
    context: fs.Context,
    parsed: options.Options,
    entry: Entry,
    variant: []const u8,
    /// MODULE-SCHEDULE-4: the standard modules' variant, shared by every
    /// program built with this compiler, switches and toolchain.
    standard: []const u8,
    switches: native_build.Switches,
    /// MODULE-PROJECT-1: what the project's `mylang.json` asks of the build.
    configured: Configured = .{},
    /// Whether the compiles build objects or only check (MODULE-CHECK-1).
    mode: Mode = .build,
    nodes: std.ArrayList(Node) = .empty,
    names: std.StringHashMapUnmanaged(usize) = .empty,
    /// Modules in dependency order: each after everything it imports.
    order: std.ArrayList(usize) = .empty,
    previous: std.StringHashMapUnmanaged(ModuleState) = .empty,
    had_state: bool = false,
    previous_arenas: bool = false,
    arenas: bool = false,
    compiled: usize = 0,

    /// The variant a module's outputs live in: the shared standard one for a
    /// standard module, the program's otherwise.
    fn home(self: *Build, module: []const u8) []const u8 {
        return if (standardModule(module)) self.standard else self.variant;
    }

    fn outFile(self: *Build, module: []const u8, suffix: []const u8) ![]const u8 {
        return std.fs.path.join(self.context.allocator, &.{ self.home(module), "out", try std.fmt.allocPrint(self.context.allocator, "{s}{s}", .{ module, suffix }) });
    }

    /// The last successful builds' module records: the program's, and the
    /// standard modules' shared ones.
    fn loadState(self: *Build) !void {
        const a = self.context.allocator;
        for ([_][]const u8{ self.standard, self.variant }, [_]bool{ true, false }) |directory, standard| {
            const bytes = self.context.read(try std.fs.path.join(a, &.{ directory, state_file })) catch continue;
            const file = std.json.parseFromSliceLeaky(StateFile, a, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch continue;
            if (!std.mem.eql(u8, file.version, state_version)) continue;
            if (!standard) {
                self.had_state = true;
                self.previous_arenas = file.arenas;
            }
            for (file.modules) |module| try self.previous.put(a, module.name, module);
        }
    }

    /// Write the program's records, and the standard modules' records into
    /// their shared state (keeping those of standard modules this program
    /// does not import).
    fn saveState(self: *Build) !void {
        const a = self.context.allocator;
        var own: std.ArrayList(ModuleState) = .empty;
        var standard: Map(ModuleState) = .empty;
        if (self.context.read(try std.fs.path.join(a, &.{ self.standard, state_file }))) |bytes| {
            if (std.json.parseFromSliceLeaky(StateFile, a, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always })) |file| {
                if (std.mem.eql(u8, file.version, state_version)) for (file.modules) |module| try standard.put(a, module.name, module);
            } else |_| {}
        } else |_| {}
        for (self.nodes.items) |node| {
            // A module this build did not reach (an import failed) keeps its
            // last record, which staleness still tests against its inputs.
            const record = node.record orelse self.previous.get(node.name) orelse continue;
            if (standardModule(record.name)) try standard.put(a, record.name, record) else try own.append(a, record);
        }
        try self.context.atomic(try std.fs.path.join(a, &.{ self.variant, state_file }), try std.json.Stringify.valueAlloc(a, StateFile{ .arenas = self.arenas, .modules = own.items }, .{}));
        try self.context.atomic(try std.fs.path.join(a, &.{ self.standard, state_file }), try std.json.Stringify.valueAlloc(a, StateFile{ .arenas = self.arenas, .modules = standard.values() }, .{}));
    }

    fn intern(self: *Build, name: []const u8) !?usize {
        return self.names.get(name);
    }

    /// Re-read real source and embeds under loader budgets before any early cutoff.
    fn capture(self: *Build) !bool {
        var loaded: language.project.Project = .init(self.context.parent);
        defer loaded.deinit();
        var files: language.project_files.Files = .{ .io = self.context.io, .root = self.entry.root, .embed_root = self.configured.embed_root };
        loaded.load(files.provider(), self.entry.name, self.configured.limits) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return false,
        };
        const a = self.context.allocator;
        for (loaded.modules.items) |module| {
            var hash = Blake.init(.{});
            hash.update(module.src.bytes);
            language.embed.hashInto(&hash, module.src.embeds);
            var digest: [32]u8 = undefined;
            hash.final(&digest);
            const imports = try a.alloc([]const u8, module.imports.len);
            for (module.imports, imports) |imported, *name| name.* = try a.dupe(u8, imported.name);
            const id = self.nodes.items.len;
            try self.nodes.append(a, .{
                .name = try a.dupe(u8, module.name),
                .digest = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower)),
                .imports = imports,
                .arena_text = std.mem.indexOf(u8, module.src.bytes, "arena(") != null,
                .bytes = module.src.bytes.len,
            });
            try self.names.put(a, self.nodes.items[id].name, id);
        }
        return true;
    }

    /// Find every module from the entry's imports, as the project loader
    /// does, and order them so each follows what it imports. A module that
    /// cannot be read, a header problem or an import cycle is the
    /// whole-program path's to report.
    fn discover(self: *Build) !bool {
        if (!try self.capture()) return false;
        const a = self.context.allocator;
        const Visit = struct { id: usize, next: usize = 0 };
        const root = (try self.intern(self.entry.name)) orelse return false;
        var visiting: std.AutoHashMapUnmanaged(usize, void) = .empty;
        var complete: std.AutoHashMapUnmanaged(usize, void) = .empty;
        var work: std.ArrayList(Visit) = .empty;
        try work.append(a, .{ .id = root });
        try visiting.put(a, root, {});
        while (work.items.len != 0) {
            const top = &work.items[work.items.len - 1];
            const imports = self.nodes.items[top.id].imports;
            if (top.next == imports.len) {
                const deps = try a.alloc(usize, imports.len);
                for (imports, deps) |name, *dep| dep.* = self.names.get(name).?;
                self.nodes.items[top.id].deps = deps;
                try self.order.append(a, top.id);
                try complete.put(a, top.id, {});
                _ = visiting.remove(top.id);
                _ = work.pop();
                continue;
            }
            const name = imports[top.next];
            top.next += 1;
            const target = (try self.intern(name)) orelse return false;
            if (complete.contains(target)) continue;
            if (visiting.contains(target)) return false;
            try visiting.put(a, target, {});
            try work.append(a, .{ .id = target });
        }
        return true;
    }

    /// Whether the program fits the source budgets the whole-program loader
    /// enforces (the project's, or the defaults): its module count, its import
    /// count, each file's bytes and all files' bytes.
    fn withinBudgets(self: *Build) bool {
        const limits = self.configured.limits;
        var imports: usize = 0;
        var total: usize = 0;
        for (self.nodes.items) |node| {
            if (node.bytes > limits.max_file_bytes) return false;
            imports += node.imports.len;
            total += node.bytes;
        }
        return self.nodes.items.len <= limits.max_modules and imports <= limits.max_imports and total <= limits.max_total_bytes;
    }

    /// Whether the project's import policy denies any import of the program.
    fn policyDenies(self: *Build) bool {
        const policy = self.configured.policy orelse return false;
        for (self.nodes.items) |node| {
            for (node.imports) |imported| if (language.import_policy.denies(policy, node.name, imported)) return true;
        }
        return false;
    }

    /// Schedule, and when a compile failed, save what finished first: the
    /// modules the next build need not compile again.
    fn scheduleSaved(self: *Build) !bool {
        if (try self.schedule()) return true;
        try self.saveState();
        return false;
    }

    /// MODULE-CHECK-1: whether every warning a compile reported in another
    /// module's text is one that module's own compile reported too. A body
    /// an interface keeps (a template, an inlined function) is checked again
    /// by each dependent, and the whole program reports its warning once, in
    /// its own module; a warning only a dependent's use raises is the
    /// whole-program path's to place.
    fn foreignReported(self: *Build) bool {
        for (self.nodes.items) |node| {
            const record = node.record orelse continue;
            for (record.foreign) |warning| {
                const owner = self.names.get(warning.module) orelse return false;
                const own = self.nodes.items[owner].record orelse return false;
                if (std.mem.indexOf(u8, own.warnings, warning.text) == null) return false;
            }
        }
        return true;
    }

    /// MODULE-TEST-1: every module's test document merged: the facts of the
    /// tests' closure (`native_test_facts.mergeShares`) and the library parts;
    /// null when a document is missing or malformed.
    fn mergeTests(self: *Build) !?MergedTests {
        const a = self.context.allocator;
        // MODULE-TEST-1: the last merge answers while no module changed: the
        // merged documents are a function of every module's record.
        var key = Blake.init(.{});
        frame(&key, "module-tests-merged-v1");
        for (self.nodes.items) |node| {
            const record = node.record orelse return null;
            frame(&key, record.name);
            frame(&key, record.digest);
            frame(&key, record.hashes.interface);
            frame(&key, record.hashes.emission);
        }
        var digest: [32]u8 = undefined;
        key.final(&digest);
        const stamp = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
        const cached = try std.fs.path.join(a, &.{ self.variant, "tests.merged.json" });
        if (self.context.read(cached)) |bytes| {
            if (std.json.parseFromSliceLeaky(MergedFile, a, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always })) |file| {
                if (std.mem.eql(u8, file.key, stamp) and file.library.roots == .object) {
                    var roots: Map(std.json.Value) = .empty;
                    var entries = file.library.roots.object.iterator();
                    while (entries.next()) |entry| try roots.put(a, entry.key_ptr.*, entry.value_ptr.*);
                    return .{ .graph = file.graph, .library = .{ .roots = roots, .schema = file.library.schema, .wire = file.library.wire, .codecs = file.library.codecs }, .contracts = file.contracts };
                }
            } else |_| {}
        } else |_| {}
        const merged = (try self.mergeDocuments()) orelse return null;
        var roots_object: std.json.ObjectMap = .empty;
        for (merged.library.roots.keys(), merged.library.roots.values()) |name, root| try roots_object.put(a, name, root);
        const library = merged.library;
        const saved: MergedFile = .{
            .key = stamp,
            .graph = merged.graph,
            .library = .{ .roots = .{ .object = roots_object }, .schema = library.schema, .wire = library.wire, .codecs = library.codecs },
            .contracts = merged.contracts,
        };
        // A merge that cannot be kept is done again by the next run.
        self.context.atomic(cached, try std.json.Stringify.valueAlloc(a, saved, .{})) catch return merged;
        return merged;
    }

    /// Every module's test document merged, read from the modules' files.
    fn mergeDocuments(self: *Build) !?MergedTests {
        const a = self.context.allocator;
        const test_facts = language.native_test_facts;
        var shares: std.ArrayList(test_facts.Share) = .empty;
        var roots: Map(std.json.Value) = .empty;
        var schemas: std.ArrayList(std.json.Value) = .empty;
        var wire: Map(std.json.Value) = .empty;
        var codec_types: Map(std.json.Value) = .empty;
        var codecs: Map(std.json.Value) = .empty;
        var callbacks: Map(std.json.Value) = .empty;
        var validations: Map(std.json.Value) = .empty;
        var contracts: Map(std.json.Value) = .empty;
        for (self.nodes.items) |node| {
            const bytes = self.context.read(try self.outFile(node.name, ".tests.json")) catch return null;
            const document = std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{ .allocate = .alloc_always }) catch return null;
            _ = try putFirst(std.json.Value, a, &contracts, node.name, field(document, "contract"));
            const share = std.json.parseFromSliceLeaky(test_facts.Share, a, stringOf(field(document, "facts")), .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch return null;
            try shares.append(a, share);
            for (items(field(document, "roots"))) |root| _ = try putFirst(std.json.Value, a, &roots, stringOf(field(field(root, "export"), "name")), root);
            try schemas.append(a, std.json.parseFromSliceLeaky(std.json.Value, a, stringOf(field(document, "schema")), .{ .allocate = .alloc_always }) catch return null);
            for (items(field(document, "wire_types"))) |item| _ = try putFirst(std.json.Value, a, &wire, stringOf(field(item, "name")), item);
            const table = field(document, "codecs");
            const types = items(field(table, "types"));
            const descriptors = items(field(table, "descriptors"));
            if (types.len != descriptors.len) return null;
            for (types, descriptors) |item, descriptor| {
                var pair = std.json.Array.init(a);
                try pair.appendSlice(&.{ item, descriptor });
                _ = try putFirst(std.json.Value, a, &codec_types, stringOf(field(item, "name")), .{ .array = pair });
            }
            // Method numbers are positions in the module's own callbacks;
            // codecs name their methods by symbol until the merge renumbers.
            const own = items(field(table, "callbacks"));
            for (items(field(table, "codecs"))) |codec| {
                var named = codec;
                named.object = try codec.object.clone(a);
                for ([_][]const u8{ "decode", "encode" }) |key| {
                    const at: usize = @intCast(field(codec, key).integer);
                    if (at >= own.len) return null;
                    try named.object.put(a, key, field(own[at], "symbol"));
                }
                _ = try putFirst(std.json.Value, a, &codecs, stringOf(field(codec, "domain")), named);
            }
            for (own) |callback| _ = try putFirst(std.json.Value, a, &callbacks, stringOf(field(callback, "symbol")), try unnumbered(a, callback));
            for (items(field(table, "validations"))) |validation| _ = try putFirst(std.json.Value, a, &validations, stringOf(field(validation, "symbol")), try unnumbered(a, validation));
        }
        const entry = language.native_test_facts.symbol(a, try std.fmt.allocPrint(a, "{s}::main", .{self.entry.name})) catch return error.OutOfMemory;
        const schema = try mergedSchema(a, self.entry.name, schemas.items);
        const graph = language.native_test_facts.mergeShares(a, shares.items, .{ .schema = schema, .entry = entry, .scope = .closure }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        };
        var manifest: std.json.ObjectMap = .empty;
        try manifest.put(a, "version", .{ .string = "interface-contracts-v2" });
        try manifest.put(a, "modules", .{ .array = try arrayOf(a, try sortedValues(a, contracts)) });
        const table: std.json.Value = .{ .array = try arrayOf(a, try sortedValues(a, wire)) };
        const parts: LibraryParts = .{ .roots = roots, .schema = schema, .wire = table, .codecs = try mergedCodecs(a, codec_types, codecs, callbacks, validations) };
        return .{ .graph = graph, .library = parts, .contracts = .{ .object = manifest } };
    }

    /// Whether this variant has no records yet and the program has at least
    /// `threshold` modules.
    fn firstLarge(self: *Build, threshold: usize) bool {
        return !self.had_state and self.nodes.items.len >= threshold;
    }

    /// Whether any module's check reported a warning.
    fn warned(self: *Build) bool {
        for (self.nodes.items) |node| if (node.record.?.warnings.len != 0) return true;
        return false;
    }

    /// The arena switch to compile under first: the last build's, or, with no
    /// last build, whether any module's source mentions an arena scope.
    fn guessArenas(self: *Build) bool {
        if (self.had_state) return self.previous_arenas;
        for (self.nodes.items) |node| if (node.arena_text) return true;
        return false;
    }

    /// Whether any module's units open an arena: the program's switch.
    fn programArenas(self: *Build) bool {
        for (self.nodes.items) |node| if (node.record.?.marks.arena) return true;
        return false;
    }

    /// Compile every module again under a new arena switch.
    fn restart(self: *Build) !void {
        for (self.nodes.items) |*node| {
            node.status = .waiting;
            node.current = null;
            if (node.record) |record| try self.previous.put(self.context.allocator, record.name, record);
            node.record = null;
        }
    }

    /// Mark every module one of whose objects is gone for another compile;
    /// whether there was one.
    fn markMissingObjects(self: *Build) !bool {
        var any = false;
        for (self.nodes.items) |*node| {
            const record = node.record.?;
            const gone = for (record.placed) |placed| {
                if (!self.context.exists(placed.object)) break true;
            } else false;
            if (!gone) continue;
            any = true;
            _ = self.previous.remove(record.name);
            node.record = null;
            node.status = .waiting;
            node.current = null;
        }
        if (!any) return false;
        // Everything else stands as it is: a recompile keeps its interface.
        for (self.nodes.items) |*node| if (node.record) |record| {
            try self.previous.put(self.context.allocator, record.name, record);
            node.status = .waiting;
            node.current = null;
            node.record = null;
        };
        return true;
    }

    /// Whether module `id` must compile: null while an input it read is not
    /// final yet.
    fn stale(self: *Build, id: usize) bool {
        const node = self.nodes.items[id];
        const known = self.previous.get(node.name) orelse return true;
        if (!std.mem.eql(u8, known.digest, node.digest) or known.arenas != self.arenas) return true;
        for (known.inputs) |input| {
            const at = self.names.get(input.module) orelse return true;
            const now = self.nodes.items[at].current orelse return true;
            if (!std.mem.eql(u8, now.interface, input.interface) or !std.mem.eql(u8, now.emission, input.emission)) return true;
            // Positions matter only to a compile whose units spliced or
            // instantiated a body of that interface's text.
            if (input.positions.len != 0 and !std.mem.eql(u8, now.positions, input.positions)) return true;
        }
        return false;
    }

    /// Whether every module `id` imports has its final interface.
    fn importsReady(self: *Build, id: usize) bool {
        for (self.nodes.items[id].deps) |dep| switch (self.nodes.items[dep].status) {
            .ready, .done => {},
            else => return false,
        };
        return true;
    }

    /// Compile every stale module over the import graph, as many at once as
    /// the cores and free memory allow; whether every module ended with a
    /// record. After a failed compile no new one starts, and the ones running
    /// finish.
    fn schedule(self: *Build) !bool {
        const a = self.context.allocator;
        const width = budget.workers(.{
            .programs = @max(1, self.nodes.items.len),
            .cores = std.Thread.getCpuCount() catch 1,
            .free = budget.available(self.context.io),
            .ceiling = child_ceiling,
            .jobs = if (self.context.environ.get("MYLANG_JOBS")) |text| budget.jobs(text) catch null else null,
        });
        var running: std.ArrayList(Running) = .empty;
        var failed = false;
        while (true) {
            var progress = true;
            while (progress) {
                progress = false;
                for (self.order.items) |id| {
                    if (self.nodes.items[id].status != .waiting or !self.importsReady(id)) continue;
                    if (!self.stale(id)) {
                        const known = self.previous.get(self.nodes.items[id].name).?;
                        self.nodes.items[id].record = known;
                        self.nodes.items[id].current = known.hashes;
                        self.nodes.items[id].status = .done;
                        progress = true;
                        continue;
                    }
                    if (failed or running.items.len >= width) continue;
                    try running.append(a, .{ .node = id, .started = try self.start(id) });
                    self.nodes.items[id].status = .running;
                }
            }
            if (running.items.len == 0) break;
            const started = try a.alloc(spawn.Started, running.items.len);
            for (running.items, started) |one, *slot| slot.* = one.started;
            const index = try spawn.ready(a, started);
            const one = &running.items[index];
            const ended = try spawn.pump(a, one.started, &one.stderr);
            try self.noticeReady(one);
            if (!ended) continue;
            const finished = running.swapRemove(index);
            const term = spawn.reap(finished.started);
            if (fs.exitCode(term) == 0 and try self.finish(finished.node)) continue;
            self.nodes.items[finished.node].status = .failed;
            failed = true;
        }
        for (self.nodes.items) |node| if (node.status != .done) return false;
        return !failed;
    }

    /// Start the compile of module `id`.
    fn start(self: *Build, id: usize) !spawn.Started {
        const a = self.context.allocator;
        const node = self.nodes.items[id];
        var argv: std.ArrayList([]const u8) = .empty;
        const home_directory = self.home(node.name);
        try argv.appendSlice(a, &.{
            try std.Io.Dir.cwd().realPathFileAlloc(self.context.io, "/proc/self/exe", a),
            "compile-module",
            self.entry.path,
            try std.fmt.allocPrint(a, "--module={s}", .{node.name}),
            try std.fmt.allocPrint(a, "--interfaces={s}/if", .{home_directory}),
            try std.fmt.allocPrint(a, "--standard-interfaces={s}/if", .{self.standard}),
            try std.fmt.allocPrint(a, "--out={s}/out", .{home_directory}),
            try std.fmt.allocPrint(a, "--cache-dir={s}", .{self.parsed.cache}),
        });
        if (self.mode == .check) {
            try argv.appendSlice(a, &.{ "--check-only", "--ready" });
            return spawn.start(a, .{ .argv = argv.items });
        }
        try argv.append(a, if (self.arenas) "--arenas=on" else "--arenas=off");
        try argv.appendSlice(a, try native_build.frontendSwitches(a, self.switches));
        if (self.mode == .tests) try argv.append(a, "--tests");
        try argv.appendSlice(a, &.{ "--objects", "--ready", "--", "--mode", self.parsed.mode, "--target", self.parsed.target, try std.fmt.allocPrint(a, "--zig={s}", .{self.parsed.zig}) });
        switch (self.parsed.codegen) {
            .qbe => |tool| try argv.append(a, try std.fmt.allocPrint(a, "--qbe={s}", .{tool})),
            else => {},
        }
        return spawn.start(a, .{ .argv = argv.items });
    }

    /// Take a compile's interface hashes from its ready line, once.
    fn noticeReady(self: *Build, one: *Running) !void {
        const node = &self.nodes.items[one.node];
        if (node.status != .running) return;
        const at = std.mem.indexOf(u8, one.stderr.items, compile_command.ready_marker) orelse return;
        const line_end = std.mem.indexOfScalarPos(u8, one.stderr.items, at, '\n') orelse return;
        var fields = std.mem.tokenizeScalar(u8, one.stderr.items[at + compile_command.ready_marker.len .. line_end], ' ');
        const a = self.context.allocator;
        node.current = .{
            .interface = try a.dupe(u8, fields.next() orelse return),
            .emission = try a.dupe(u8, fields.next() orelse return),
            .positions = try a.dupe(u8, fields.next() orelse return),
        };
        node.status = .ready;
    }

    /// Record a finished compile of module `id` from its result files;
    /// whether they were complete.
    fn finish(self: *Build, id: usize) !bool {
        const a = self.context.allocator;
        const node = &self.nodes.items[id];
        const bytes = self.context.read(try self.outFile(node.name, ".result.json")) catch return false;
        const Result = struct {
            hashes: struct { interface: []const u8, emission: []const u8, positions: []const u8, inputs: []const Input = &.{} },
            warnings: []const u8 = "",
            marks: Marks = .{},
            text_format: bool = false,
            entry: ?[]const u8 = null,
            shared: []const u8 = "",
            objects: ?[]const u8 = null,
            foreign: []const Foreign = &.{},
        };
        const result = std.json.parseFromSliceLeaky(Result, a, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch return false;
        const Objects = struct { compiled: bool = false, placed: []const native_build.Placed = &.{} };
        // A check builds no objects.
        const listed: ?[]const u8 = if (self.mode == .check) null else result.objects orelse return false;
        const objects: Objects = if (listed) |path| std.json.parseFromSliceLeaky(Objects, a, self.context.read(path) catch return false, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch return false else .{};
        node.record = .{
            .name = node.name,
            .digest = node.digest,
            .imports = node.imports,
            .arenas = self.arenas,
            .hashes = .{ .interface = result.hashes.interface, .emission = result.hashes.emission, .positions = result.hashes.positions },
            .inputs = result.hashes.inputs,
            .marks = result.marks,
            .text_format = result.text_format,
            .warnings = result.warnings,
            .placed = objects.placed,
            .shared = result.shared,
            .entry = result.entry,
            .objects = listed,
            .foreign = result.foreign,
        };
        node.current = node.record.?.hashes;
        node.status = .done;
        node.compiled = true;
        node.objects_compiled = objects.compiled;
        self.compiled += 1;
        return true;
    }

    /// Replay every module's warnings, in the order the modules were found.
    fn printWarnings(self: *Build) !void {
        for (self.nodes.items) |node| {
            const warnings = node.record.?.warnings;
            if (warnings.len != 0) std.Io.File.stderr().writeStreamingAll(self.context.io, warnings) catch return error.WriteFailed;
        }
    }

    /// The program to link: every module's objects in whole-program link
    /// order (a specialization several modules emitted once), the metadata
    /// unit's key, the entry's fields, and the report records when asked;
    /// null when two modules emitted one batch with different objects.
    fn program(self: *Build) !?native_build.ModuleProgram {
        const a = self.context.allocator;
        var placed: Map(native_build.Placed) = .empty;
        var compiled = false;
        var text = false;
        var entry: ?[]const u8 = null;
        var shared = Blake.init(.{});
        frame(&shared, "module-metadata-parts-v1");
        const sorted = try a.dupe(usize, self.order.items);
        std.mem.sort(usize, sorted, self, nameBefore);
        for (sorted) |id| {
            const node = self.nodes.items[id];
            const record = node.record.?;
            compiled = compiled or node.objects_compiled;
            text = text or record.text_format;
            if (record.entry) |fields| entry = fields;
            frame(&shared, record.name);
            frame(&shared, record.shared);
            for (record.placed) |one| {
                const slot = try placed.getOrPut(a, try std.fmt.allocPrint(a, "{s}\x00{s}\x00{s}", .{ @tagName(one.kind), one.group, one.first }));
                if (slot.found_existing) {
                    if (!std.mem.eql(u8, slot.value_ptr.key, one.key)) return null;
                } else slot.value_ptr.* = one;
            }
        }
        const ordered = try a.dupe(native_build.Placed, placed.values());
        std.mem.sort(native_build.Placed, ordered, {}, placedBefore);
        const objects = try a.alloc([]const u8, ordered.len);
        var identity = Blake.init(.{});
        frame(&identity, "module-program-v1");
        for (ordered, objects) |one, *object| {
            object.* = one.object;
            frame(&identity, one.key);
        }
        var key: [32]u8 = undefined;
        shared.final(&key);
        const shared_key = try a.dupe(u8, &std.fmt.bytesToHex(key, .lower));
        frame(&identity, shared_key);
        const fields = entry orelse return null;
        frame(&identity, fields);
        identity.update(&.{@intFromBool(text)});
        var manifest = (std.json.parseFromSliceLeaky(std.json.Value, a, fields, .{}) catch return null);
        if (manifest != .object) return null;
        try manifest.object.put(a, "text_format", .{ .bool = text });
        try manifest.object.put(a, native_test_contracts.functions_key, .{ .array = std.json.Array.init(a) });
        var digest: [32]u8 = undefined;
        identity.final(&digest);
        const render = try a.create(SharedRender);
        render.* = .{ .build = self, .order = sorted };
        return .{
            .objects = objects,
            .compiled = compiled,
            .records = if (self.parsed.report) try self.records() else &.{},
            .shared = .{ .key = shared_key, .render = .{ .context = render, .run = SharedRender.run } },
            .manifest = manifest,
            .identity = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower)),
        };
    }

    /// Every function's report record, from each module's object list: a
    /// module this build did not compile reused every object.
    fn records(self: *Build) ![]const native_build.Record {
        const a = self.context.allocator;
        var seen: Map(native_build.Record) = .empty;
        for (self.nodes.items) |node| {
            const listed = node.record.?.objects orelse continue;
            const Objects = struct { functions: []const native_build.Record = &.{} };
            const bytes = self.context.read(listed) catch continue;
            const objects = std.json.parseFromSliceLeaky(Objects, a, bytes, .{ .ignore_unknown_fields = true, .allocate = .alloc_always }) catch continue;
            for (objects.functions) |record| {
                const slot = try seen.getOrPut(a, record.symbol);
                if (slot.found_existing) continue;
                slot.value_ptr.* = record;
                if (!node.compiled) slot.value_ptr.reused = true;
            }
        }
        const out = try a.dupe(native_build.Record, seen.values());
        std.mem.sort(native_build.Record, out, {}, recordBefore);
        return out;
    }
};

/// MODULE-PROJECT-1: what a project's `mylang.json` asks of a per-module
/// build: the source budgets the loader enforces, the import policy every
/// edge must pass, and whether a warning rejects a `run`. None of it changes
/// a module's compiled output, so none of it keys a compile.
const Configured = struct {
    limits: language.project.Options = .{},
    policy: ?language.import_policy.Policy = null,
    deny_warnings: bool = false,
    embed_root: ?[]const u8 = null,
};

/// The configuration of the project `entry` belongs to (an empty one without
/// a `mylang.json`), or null when it or its policy does not load.
fn configuredProject(context: fs.Context, entry: []const u8) !?Configured {
    const a = context.allocator;
    const path = (project_config.discover(a, context.io, entry) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    }) orelse return .{};
    var failure: project_config.Failure = .{};
    const config = project_config.load(a, context.io, path, &failure) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    // Generated API freshness is still enforced by the whole-program path.
    if (config.document.interface_files) return null;
    var out: Configured = .{ .embed_root = std.fs.path.dirname(path) orelse "." };
    const budgets = config.document.budgets;
    if (budgets.max_modules) |value| out.limits.max_modules = value;
    if (budgets.max_imports) |value| out.limits.max_imports = value;
    if (budgets.max_file_bytes) |value| out.limits.max_file_bytes = value;
    if (budgets.max_total_bytes) |value| out.limits.max_total_bytes = value;
    if (config.policy) |file| out.policy = language.import_policy.Policy.parse(a, file.bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    // A malformed `lint` object leaves warnings reported, as the
    // whole-program path reads it.
    if (config.document.lint) {
        var lint_failure: language.lint_config.Failure = .{};
        if (language.lint_config.parseConfig(a, config.bytes, &lint_failure)) |lint| {
            out.deny_warnings = lint.warnings == .deny;
        } else |err| if (err == error.OutOfMemory) return error.OutOfMemory;
    }
    return out;
}

/// Whether a module is one of the compiler's standard modules.
fn standardModule(name: []const u8) bool {
    var buffer: [256]u8 = undefined;
    if (name.len + 3 > buffer.len) return false;
    @memcpy(buffer[0..name.len], name);
    @memcpy(buffer[name.len..][0..3], ".my");
    for (buffer[0..name.len]) |*byte| if (byte.* == '.') {
        byte.* = '/';
    };
    return language.module_compile.standardSource(buffer[0 .. name.len + 3]) != null;
}

fn nameBefore(self: *Build, left: usize, right: usize) bool {
    return std.mem.lessThan(u8, self.nodes.items[left].name, self.nodes.items[right].name);
}

/// Whole-program link order: code batches, then metadata groups, each by plan
/// group and first symbol.
fn placedBefore(_: void, left: native_build.Placed, right: native_build.Placed) bool {
    if (left.kind != right.kind) return left.kind == .code;
    const group = std.mem.order(u8, left.group, right.group);
    if (group != .eq) return group == .lt;
    return std.mem.lessThan(u8, left.first, right.first);
}

fn recordBefore(_: void, left: native_build.Record, right: native_build.Record) bool {
    return std.mem.lessThan(u8, left.symbol, right.symbol);
}

/// Renders the program-wide metadata unit from the modules' shares: their
/// descriptor and renderer blocks by name, their frozen literals and their
/// host bridges, as a whole-program emission renders them.
const SharedRender = struct {
    build: *Build,
    order: []const usize,

    fn run(context: *anyopaque, allocator: std.mem.Allocator) native_build.Error![]const u8 {
        const self: *SharedRender = @ptrCast(@alignCast(context));
        const state = self.build;
        var shares: std.ArrayList(std.json.Value) = .empty;
        for (self.order) |id| {
            const name = state.nodes.items[id].name;
            const bytes = try state.context.read(try state.outFile(name, ".shared.json"));
            try shares.append(allocator, try std.json.parseFromSliceLeaky(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always }));
        }
        const encoded = language.module_link.merge(allocator, shares.items) catch |err| return invalidBlocks(err);
        const manifest = try std.json.parseFromSliceLeaky(std.json.Value, allocator, encoded, .{ .allocate = .alloc_always });
        return outputs.sharedMetadata(allocator, manifest);
    }
};

fn invalidBlocks(err: anyerror) native_build.Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidNativeManifest;
}
