//! MODULE-COMPILE-1: compile one module of a program from its own source and
//! its imports' interfaces alone, to the units, interface and runtime data a
//! whole-program build produces for that module.
//!
//! The module is checked against the interfaces of the modules it imports
//! (`module_interface_oracle.Single`): a declared function of another module
//! stands in with the facts its interface carries and is lowered signature
//! only, so the inliner never splices its `pass` body. Every other function the
//! check produced — the module's own, the bodies interfaces keep (inlined,
//! evaluated, conversion and host declarations), the standard library, which
//! is read from the compiler, and every specialization — is lowered and
//! analysed exactly as the whole program analyses it. What a unit reads about
//! a stood-in function comes from that function's interface: whether a call to
//! it may allocate, transitively, and which parameters its body writes.
//!
//! The module emits its own functions, its lambdas, and every specialization
//! its units reach; a specialization another module also reaches is emitted
//! there too, content-addressed under one symbol, and a link keeps one copy.
//! The emission's facts about the module's declared functions become the
//! `emission` section of the module's own interface, which its dependents'
//! compiles read.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const lower = @import("lower.zig");
const bytecode_inline = @import("bytecode_inline.zig");
const qbe = @import("qbe.zig");
const native_interface = @import("native_interface.zig");
const fragments = @import("qbe_fragments.zig");
const iface = @import("module_interface.zig");
const builder = @import("module_interface_build.zig");
const oracle = @import("module_interface_oracle.zig");
const entry_adapter = @import("entry_adapter.zig");
const project = @import("project.zig");
const native_types = @import("native_types.zig");
const project_compile = @import("project_compile.zig");
const test_facts = @import("native_test_facts.zig");

/// Failures of one module compile. `SourceError` means the module did not
/// check (its diagnostics are on the returned compilation); `MissingEmission`
/// means an import's interface carries no emission facts for this build's
/// configuration, so that module has to be compiled first.
pub const Error = oracle.Error || error{ WriteFailed, MissingEmission };

/// The source of a standard module, which a compile reads from the compiler
/// rather than the project, or null for a project module path.
pub fn standardSource(path: []const u8) ?[]const u8 {
    return @import("standard_library.zig").source(path);
}

/// What one module compile needs.
pub const Request = struct {
    /// The module, its source bytes and whether it is the program's entry.
    module: oracle.ModuleRequest,
    /// The lowering and emission switches, and the program's arena switch.
    config: iface.EmissionConfig,
    /// The fragment store the module's units are kept in; unused by a
    /// check-only compile.
    reuse: ?fragments.Reuse,
    /// MODULE-SCHEDULE-5: called as soon as the module's interface and
    /// hashes are final, before its units are emitted.
    ready: ?Ready = null,
    /// MODULE-CHECK-1: check the module and build its interface (with no
    /// emission section) without reading its imports' emission facts or
    /// emitting a unit.
    check_only: bool = false,
    /// MODULE-TEST-1: also describe what a test run reads of the module
    /// (`Units.tests`).
    tests: bool = false,
};

/// A callback for a compile whose interface is final.
pub const Ready = struct { context: *anyopaque, run: *const fn (context: *anyopaque, compiled: *const Compiled) anyerror!void };

/// One compiled module. `single` owns the checked program everything else
/// points into; `deinit` releases it.
pub const Compiled = struct {
    /// Null only when allocation failed before the check began.
    single: ?*oracle.Single = null,
    interface: iface.Interface,
    hashes: Hashes,
    units: Units,
    /// The emission's facts and keys, one entry per program function.
    report: fragments.Report,
    counts: Counts,
    /// Why a compile that failed with `MissingEmission` failed.
    problem: []const u8 = "",

    /// Release the module's checked program.
    pub fn deinit(self: *Compiled) void {
        if (self.single) |single| single.deinit();
        self.single = null;
    }
};

/// The module's units: the lean executable manifest (`qbe-units-v1`) of the
/// functions it emits, and its share of the program's runtime data.
pub const Units = struct {
    manifest: []const u8 = "",
    parts: native_interface.Parts = .{},
    /// MODULE-TEST-1: the `module-tests-v1` document of a compile asked for
    /// tests, else empty.
    tests: []const u8 = "",
};

/// The four hashes one compile states for its module, lowercase hex, and the
/// hashes of every interface the compile read: a later build may reuse this
/// compile's outputs while its source, configuration and every one of those
/// is unchanged.
pub const Hashes = struct {
    interface: []const u8,
    implementation: []const u8,
    emission: []const u8,
    positions: []const u8,
    inputs: []const Input = &.{},
};

/// One interface a compile read, by module, with its interface, emission and
/// positions hashes (lowercase hex); the positions hash is empty when no
/// emitted unit's positions fell in that interface's text.
pub const Input = struct { module: []const u8, interface: []const u8, emission: []const u8, positions: []const u8 };

/// How much one compile did: the program's functions, how many it lowered
/// with their bodies, how many it stood in from interfaces, its units, and
/// how many diagnostics its check reported (before lowering).
pub const Counts = struct { functions: usize = 0, lowered: usize = 0, stood_in: usize = 0, emitted: usize = 0, diagnostics: usize = 0 };

/// Compile `request.module` into `arena`. On `error.SourceError` the check's
/// diagnostics are on `out.single`, which the caller still deinitializes.
pub fn compile(gpa: std.mem.Allocator, arena: std.mem.Allocator, request: Request, out: *Compiled) Error!void {
    var single: *oracle.Single = undefined;
    out.* = .{ .interface = undefined, .hashes = undefined, .units = .{}, .report = .{}, .counts = .{} };
    oracle.Single.open(gpa, request.module, &single) catch |err| {
        // `open` hands the check back on every failure but allocation.
        if (err != error.OutOfMemory) out.single = single;
        return err;
    };
    out.single = single;
    if (!single.declaredOnly()) {
        out.problem = "module declarations required a whole-program recheck";
        return error.InternalError;
    }
    const compilation = &single.compilation;
    const program = compilation.program orelse return error.InternalError;
    if (single.request.prepared == null) return error.InternalError;
    const modules = compilation.index.project.modules.items;
    const own = moduleIndex(modules, request.module.module) orelse return error.InternalError;
    const stood = try standIns(arena, single, program.functions.len);
    // A check-only compile emits nothing, so it reads no emission facts.
    const facts = if (request.check_only) std.StringHashMapUnmanaged(iface.EmittedFunction).empty else importedFacts(arena, request, modules, own) catch |err| switch (err) {
        error.MissingEmission => {
            out.problem = "an import's interface holds emission facts for another configuration";
            return err;
        },
        else => return err,
    };
    const imported = try arena.alloc(?native_interface.Imported, program.functions.len);
    var counts: Counts = .{ .functions = program.functions.len, .diagnostics = compilation.diagnostics.items.items.len };
    for (program.functions, stood, imported) |function, skipped, *entry| {
        entry.* = null;
        if (!skipped) continue;
        counts.stood_in += 1;
        if (request.check_only) continue;
        const stated = facts.get(function.name) orelse {
            out.problem = try std.fmt.allocPrint(arena, "no emission facts for `{s}`: compile its module first, under the same configuration", .{function.name});
            return error.MissingEmission;
        };
        entry.* = .{ .allocates = stated.allocates, .writes = stated.writes };
    }
    const selected = try arena.alloc(bool, program.functions.len);
    for (selected, stood) |*chosen, skipped| chosen.* = !skipped;
    for (selected) |chosen| counts.lowered += @intFromBool(chosen);
    var lowered: [2]bytecode.Program = undefined;
    for (&lowered, [_]bool{ false, true }) |*code, drop_debug| code.* = try lowerInlined(.{ .output = arena, .scratch = gpa }, program, selected, drop_debug);
    var code = lowered[@intFromBool(request.config.drop_debug)];
    if (request.check_only) {
        out.counts = counts;
        var checked: InterfaceStep = .{ .arena = arena, .request = request, .out = out, .body = .{ .lowered = &lowered, .code = code, .emit = &.{}, .archive = .{}, .dependencies = &.{} }, .own = own };
        return checked.publish(.{ .arena = arena });
    }
    var emit = try emitted(arena, .{ .compilation = compilation, .program = program, .code = code, .own = modules[own].name, .is_entry = request.module.is_entry });
    for (emit) |chosen| counts.emitted += @intFromBool(chosen);
    const physical = try @import("module_physical.zig").archive(arena, code, emit);
    const imported_interfaces = try interfacesOf(arena, request, modules, own);
    const restored = @import("module_physical_inputs.zig").restore(arena, code, emit, imported, imported_interfaces) catch |err| {
        out.problem = "invalid imported physical data";
        return err;
    };
    code = restored.code;
    emit = @constCast(restored.emit);
    var parts: native_interface.Parts = .{};
    const template: native_interface.Module = .{ .emit = emit, .imported = restored.imported, .remap = try remapOf(arena, request.module.library, modules, own), .arenas = request.config.arenas, .parts = &parts };
    var step: InterfaceStep = .{ .arena = arena, .request = request, .out = out, .body = .{ .lowered = &lowered, .code = code, .emit = emit, .archive = physical, .dependencies = imported_interfaces }, .own = own };
    var module = template;
    module.analyzed = .{ .arena = arena, .context = &step, .run = InterfaceStep.announced };
    var report: fragments.Report = .{ .arena = arena };
    const policy: native_interface.Policy = .{
        .drop_debug = request.config.drop_debug,
        .step_checks = request.config.step_checks,
        .frame_checks = request.config.frame_checks,
        .cow = if (@import("value_semantics.zig").counting()) .counting else .off,
    };
    out.counts = counts;
    const reuse = request.reuse orelse return error.InternalError;
    out.units.manifest = qbe.generateWithInterface(arena, code, compilation.src, &compilation.diagnostics, .{ .policy = policy, .reuse = reuse, .module = &module, .report = &report }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.SourceError => return error.SourceError,
        error.WriteFailed => return if (step.failure) |failure| failure else error.WriteFailed,
        else => {
            out.problem = "native module emission failed";
            return error.InternalError;
        },
    };
    out.units.parts = parts;
    out.report = report;
    if (request.tests) out.units.tests = try testDocument(arena, .{ .compilation = compilation, .code = code, .emit = emit, .module = modules[own].name, .compiled = out });
    // An emission that never announced its facts (every unit stood in)
    // publishes the interface once it is done.
    if (!step.done) step.publish(report) catch |err| return step.failure orelse err;
}

/// What a module's test document is built from: its checked compilation,
/// its lowered program and the functions it emits.
const TestSource = struct { compilation: *project_compile.Compilation, code: bytecode.Program, emit: []const bool, module: []const u8, compiled: *Compiled };

/// One test or benchmark the module emits, by symbol, with its export
/// description.
const TestRoot = struct { symbol: []const u8, @"export": @import("qbe_exports.zig").Export };

/// MODULE-TEST-1: the `module-tests-v1` document of one module compile: its
/// share of the test facts (as JSON text), the schema of its tests and
/// benchmarks and their export descriptions, and the module's wire and codec
/// tables (MODULE-TEST-2), everything a test run merges and links a test
/// library from.
fn testDocument(arena: std.mem.Allocator, from: TestSource) Error![]const u8 {
    const share = from.compilation.testShare(arena, from.emit[0..from.compilation.program.?.functions.len]) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return testFailure(arena, from.compiled, "test facts", err),
    };
    var roots: std.ArrayList(TestRoot) = .empty;
    for (share.roots, 0..) |root, index| {
        if (!root) continue;
        const described = (@import("qbe_exports.zig").describeMarked(arena, from.code, index, share.roots) catch |err| return testFailure(arena, from.compiled, "test export", err)) orelse continue;
        try roots.append(arena, .{ .symbol = test_facts.symbol(arena, from.code.functions[index].name) catch return error.OutOfMemory, .@"export" = described });
    }
    // MODULE-TEST-4: the module's own entry of the declaration contracts a
    // test run discovers its tests from.
    const modules = from.compilation.index.project.modules.items;
    const own = moduleIndex(modules, from.module) orelse return error.InternalError;
    const contract = from.compilation.index.contractModule(own) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return testFailure(arena, from.compiled, "test contracts", err),
    };
    // MODULE-TEST-5: rendered as `list-interfaces --contracts` renders it
    // (no null field), so a receipt's contract identity is the same on both
    // paths and a verdict recorded by one replays on the other.
    const contract_text = try std.json.Stringify.valueAlloc(arena, contract, .{ .emit_null_optional_fields = false });
    const contract_value = std.json.parseFromSliceLeaky(std.json.Value, arena, contract_text, .{}) catch return error.InternalError;
    var layouts = native_types.Catalog.initRecords(arena, from.code.records) catch |err| return testFailure(arena, from.compiled, "test layouts", err);
    const wire = (@import("qbe_wire.zig").describe(arena, &layouts) catch |err| return testFailure(arena, from.compiled, "test wire types", err)).types;
    const codecs = @import("qbe_codecs.zig").describe(arena, from.code, &layouts) catch |err| return testFailure(arena, from.compiled, "test codecs", err);
    return std.json.Stringify.valueAlloc(arena, .{
        .version = "module-tests-v1",
        .contract = contract_value,
        .facts = share.facts,
        .schema = share.schema,
        .roots = roots.items,
        .wire_types = wire,
        .codecs = codecs,
    }, .{});
}

fn testFailure(a: std.mem.Allocator, compiled: *Compiled, phase: []const u8, err: anyerror) Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    compiled.problem = std.fmt.allocPrint(a, "cannot describe {s}: {s}", .{ phase, @errorName(err) }) catch return error.OutOfMemory;
    return error.InternalError;
}

/// MODULE-SCHEDULE-5: what the module's interface is built from once the
/// emission's facts are known, and whether it was.
const InterfaceStep = struct {
    arena: std.mem.Allocator,
    request: Request,
    out: *Compiled,
    body: PhysicalStep,
    own: usize,
    done: bool = false,
    failure: ?Error = null,

    fn announced(context: *anyopaque, facts: fragments.Report) anyerror!void {
        const self: *InterfaceStep = @ptrCast(@alignCast(context));
        return self.publish(facts);
    }

    /// Build the interface and hand it to the request's `ready` callback;
    /// a failure is kept for the compile to return.
    fn publish(self: *InterfaceStep, facts: fragments.Report) Error!void {
        self.finish(facts) catch |err| {
            self.failure = err;
            return err;
        };
        const ready = self.request.ready orelse return;
        ready.run(ready.context, self.out) catch |err| {
            self.failure = if (err == error.OutOfMemory) error.OutOfMemory else error.WriteFailed;
            return self.failure.?;
        };
    }

    /// Build the module's interface, with its emission section from `facts`,
    /// and its hashes.
    fn finish(self: *InterfaceStep, facts: fragments.Report) Error!void {
        const arena = self.arena;
        const single = self.out.single.?;
        const compilation = &single.compilation;
        const program = compilation.program.?;
        const prepared = single.request.prepared.?;
        const modules = compilation.index.project.modules.items;
        const library = self.request.module.library;
        const foreign = try foreignRoles(arena, library, modules, self.own);
        const inputs: builder.Inputs = .{
            .index = &single.index,
            .src = compilation.src,
            .syntax = compilation.syntax,
            .program = program,
            .prepared = prepared,
            .facts = single.request.produced orelse return error.InternalError,
            .lowered = self.body.lowered,
        };
        const imports = try importHashes(arena, inputs, .{ .library = library, .foreign = &foreign }, self.own);
        const built = try builder.buildOne(arena, inputs, self.own, .{ .foreign = &foreign, .import_hashes = imports });
        var interface = built.interface;
        if (!self.request.check_only) {
            interface.emission = try emissionSection(arena, .{ .interface = interface, .prepared = prepared, .program = program, .report = facts, .emit = self.body.emit, .config = self.request.config });
            interface.emission.physical = self.body.archive;
        }
        self.out.interface = interface;
        // A diagnostic's rendering may name places in an import's text (a
        // note, an instantiated body), so a module that reported any reads
        // every import's positions (MODULE-CHECK-1).
        const placed = try placedIn(arena, compilation, self.body.code, self.body.emit);
        if (self.out.counts.diagnostics != 0) @memset(placed, true);
        self.out.hashes = .{
            .interface = try hex(arena, iface.interfaceHash(interface)),
            .implementation = try hex(arena, built.implementation_hash),
            .emission = try hex(arena, iface.emissionHash(interface)),
            .positions = try hex(arena, iface.positionsHash(interface)),
            .inputs = try inputsOf(arena, .{ .library = library, .modules = modules, .own = self.own, .placed = placed, .physical = self.body.dependencies }),
        };
        self.done = true;
    }
};

const PhysicalStep = struct {
    lowered: *const [2]bytecode.Program,
    code: bytecode.Program,
    emit: []const bool,
    archive: @import("module_physical.zig").Archive,
    dependencies: []const iface.Interface,
};

fn interfacesOf(a: std.mem.Allocator, request: Request, modules: []const project.Module, own: usize) Error![]const iface.Interface {
    const library = request.module.library;
    var out: std.ArrayList(iface.Interface) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    try seen.put(a, request.module.module, {});
    try seen.put(a, oracle.root_module, {});
    for (modules, 0..) |module, index| {
        if (index == own) continue;
        if (library.by_name.get(module.name)) |interface| {
            try seen.put(a, module.name, {});
            try out.append(a, interface);
        }
    }
    if (!@import("runtime_mode.zig").enabled()) return out.items;
    const config = try iface.configName(a, request.config);
    var cursor: usize = 0;
    while (cursor < out.items.len) : (cursor += 1) {
        const interface = out.items[cursor];
        if (!iface.physicalInputs(interface)) continue;
        for (interface.emission.physical.dependencies) |dependency| {
            const split = std.mem.indexOf(u8, dependency.name, "::") orelse continue;
            const name = dependency.name[0..split];
            if (seen.contains(name)) continue;
            const path = project.modulePath(a, name) catch return error.InternalError;
            if (standardSource(path) != null) continue;
            if (out.items.len >= request.module.limits.max_modules) return error.InternalError;
            _ = library.text(path) orelse return error.MissingEmission;
            const next = library.by_name.get(name) orelse return error.MissingEmission;
            if (!std.mem.eql(u8, next.emission.config, config)) return error.MissingEmission;
            try seen.put(a, name, {});
            try out.append(a, next);
        }
    }
    return out.items;
}

/// Which merged-source inputs the positions of the emitted units fall in: the
/// interface texts whose positions this compile's metadata read.
fn placedIn(allocator: std.mem.Allocator, compilation: *const project_compile.Compilation, code: bytecode.Program, emit: []const bool) Error![]bool {
    const out = try allocator.alloc(bool, compilation.index.project.modules.items.len);
    @memset(out, false);
    // A check-only compile emitted nothing.
    if (emit.len != code.functions.len) return out;
    for (code.functions, emit) |function, chosen| {
        if (!chosen) continue;
        var last: ?usize = null;
        for (function.scope.instructions) |instruction| {
            const at = compilation.src.originalSpan(instruction.span) catch continue;
            if (last == at.input or at.input >= out.len) continue;
            last = at.input;
            out[at.input] = true;
        }
    }
    return out;
}

/// What the interfaces a compile read are listed from.
const Read = struct { library: *oracle.Library, modules: []const project.Module, own: usize, placed: []const bool, physical: []const iface.Interface };

/// Every interface the compile read, in module order, with its interface and
/// emission hashes, and its positions hash when an emitted unit's positions
/// fell in its text (an inlined or instantiated body): only then does a
/// change of that module's positions change this module's outputs.
fn inputsOf(allocator: std.mem.Allocator, read: Read) Error![]const Input {
    var out: std.ArrayList(Input) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (read.modules, 0..) |module, index| {
        if (index == read.own) continue;
        const interface = read.library.by_name.get(module.name) orelse continue;
        try seen.put(allocator, module.name, {});
        try out.append(allocator, .{
            .module = module.name,
            .interface = try hex(allocator, iface.interfaceHash(interface)),
            .emission = try hex(allocator, iface.emissionHash(interface)),
            .positions = if (index < read.placed.len and read.placed[index]) try hex(allocator, iface.positionsHash(interface)) else "",
        });
    }
    for (read.physical) |interface| {
        if (seen.contains(interface.module)) continue;
        try seen.put(allocator, interface.module, {});
        try out.append(allocator, .{
            .module = interface.module,
            .interface = try hex(allocator, iface.interfaceHash(interface)),
            .emission = try hex(allocator, iface.emissionHash(interface)),
            .positions = "",
        });
    }
    return out.items;
}

fn hex(allocator: std.mem.Allocator, digest: [32]u8) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{x}", .{digest});
}

fn moduleIndex(modules: []const project.Module, name: []const u8) ?usize {
    for (modules, 0..) |module, index| if (std.mem.eql(u8, module.name, name)) return index;
    return null;
}

/// Which checked functions an interface's facts stood in for: the ordinary
/// instances whose stable key a declared interface function has.
fn standIns(allocator: std.mem.Allocator, single: *oracle.Single, count: usize) Error![]const bool {
    const marks = try allocator.alloc(bool, count);
    @memset(marks, false);
    const declared = single.request.previous orelse return marks;
    const prepared = single.request.prepared orelse return marks;
    for (prepared.ordinary_ast, 0..) |ast_index, instance| {
        if (instance < count and declared.find(prepared.keys[ast_index]) != null) marks[instance] = true;
    }
    return marks;
}

/// Lower every selected function (the rest signature only) and inline.
fn lowerInlined(allocators: lower.Allocators, program: typed.Program, selected: []const bool, drop_debug: bool) Error!bytecode.Program {
    const plain = lower.lowerSelectedWith(allocators, program, selected, drop_debug) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
    return bytecode_inline.inlineProgram(allocators.output, plain) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InternalError,
    };
}

/// The emission facts of every function the loaded modules' interfaces
/// declare, by checked name, refusing an interface computed under another
/// configuration.
fn importedFacts(allocator: std.mem.Allocator, request: Request, modules: []const project.Module, own: usize) Error!std.StringHashMapUnmanaged(iface.EmittedFunction) {
    const config = try iface.configName(allocator, request.config);
    var out: std.StringHashMapUnmanaged(iface.EmittedFunction) = .empty;
    for (modules, 0..) |module, index| {
        if (index == own) continue;
        const interface = request.module.library.by_name.get(module.name) orelse continue;
        if (interface.emission.config.len == 0) continue;
        if (!std.mem.eql(u8, interface.emission.config, config)) return error.MissingEmission;
        for (interface.emission.functions) |function| try out.put(allocator, function.name, function);
    }
    return out;
}

/// The roles and facts every loaded module's interface states, by stable key.
fn foreignRoles(allocator: std.mem.Allocator, library: *oracle.Library, modules: []const project.Module, own: usize) Error!builder.Foreign {
    var out: builder.Foreign = .empty;
    for (modules, 0..) |module, index| {
        if (index == own) continue;
        const interface = library.by_name.get(module.name) orelse continue;
        for (interface.declarations.functions) |function| try out.put(allocator, function.key, .{ .role = function.role, .fact = function.fact });
    }
    return out;
}

/// Per merged-source input, the stretches of the interface text it was
/// served as, so positions in an instantiated or inlined body are reported
/// in the real source.
fn remapOf(allocator: std.mem.Allocator, library: *oracle.Library, modules: []const project.Module, own: usize) Error![]const ?[]const native_interface.Stretch {
    const out = try allocator.alloc(?[]const native_interface.Stretch, modules.len);
    for (modules, out, 0..) |module, *entry, index| {
        entry.* = null;
        if (index == own) continue;
        const interface = library.by_name.get(module.name) orelse continue;
        const stretches = try allocator.alloc(native_interface.Stretch, interface.positions.origins.len);
        for (interface.positions.origins, stretches) |origin, *stretch| stretch.* = .{ .text = origin.text, .extent = origin.len + origin.gap, .line = origin.line, .column = origin.column };
        entry.* = stretches;
    }
    return out;
}

/// The interfaces a compile read, and the roles and facts they state.
const ReadFacts = struct { library: *oracle.Library, foreign: *const builder.Foreign };

/// The interface hash of each direct import: from its interface, or for a
/// standard module (read from the compiler) from its interface built here.
fn importHashes(allocator: std.mem.Allocator, inputs: builder.Inputs, read: ReadFacts, own: usize) Error![]iface.ImportHash {
    const modules = inputs.index.project.modules.items;
    const imports = modules[own].imports;
    const out = try allocator.alloc(iface.ImportHash, imports.len);
    for (imports, out) |imported, *entry| {
        const name = modules[imported.target].name;
        const interface = read.library.by_name.get(name) orelse (try builder.buildOne(allocator, inputs, imported.target, .{ .foreign = read.foreign, .import_hashes = &.{} })).interface;
        entry.* = .{ .module = name, .hash = iface.interfaceHash(interface) };
    }
    return out;
}

/// What the emission set is chosen from.
const Scope = struct {
    compilation: *const project_compile.Compilation,
    program: typed.Program,
    code: bytecode.Program,
    own: []const u8,
    is_entry: bool,
};

/// The units this module emits: every non-generic function it declares, its
/// lambdas, the entry adapter when it is the entry, and every specialization
/// those reach through calls, function values and inlined splices,
/// transitively.
fn emitted(allocator: std.mem.Allocator, scope: Scope) Error![]const bool {
    const functions = scope.program.functions;
    const out = try allocator.alloc(bool, functions.len);
    var pending: std.ArrayList(usize) = .empty;
    for (functions, out, 0..) |function, *chosen, index| {
        chosen.* = if (std.mem.eql(u8, function.name, entry_adapter.wrapper_name))
            scope.is_entry
        else
            function.type_arguments.len == 0 and ownedBy(scope, function, scope.own);
        if (chosen.*) try pending.append(allocator, index);
    }
    while (pending.pop()) |index| {
        for (scope.code.functions[index].scope.instructions) |instruction| {
            const target: ?typed.FunctionId = switch (instruction.op) {
                .call => |id| id,
                .function_value => |value| value.function,
                else => null,
            };
            for ([_]?typed.FunctionId{ target, if (instruction.inline_origin) |origin| origin.callee else null }) |candidate| {
                const id = candidate orelse continue;
                const reached = @backingInt(id);
                if (reached >= functions.len or out[reached] or functions[reached].type_arguments.len == 0) continue;
                out[reached] = true;
                try pending.append(allocator, reached);
            }
        }
    }
    return out;
}

/// Whether `function` is declared in module `name`.
fn ownedBy(scope: Scope, function: typed.Function, name: []const u8) bool {
    const at = scope.compilation.src.originalSpan(function.declaration) catch return false;
    const modules = scope.compilation.index.project.modules.items;
    return at.input < modules.len and std.mem.eql(u8, modules[at.input].name, name);
}

/// What the emission section is made of.
const Section = struct {
    interface: iface.Interface,
    prepared: @import("semantic_key.zig").Prepared,
    program: typed.Program,
    report: fragments.Report,
    emit: []const bool,
    config: iface.EmissionConfig,
};

/// The module interface's emission section: the facts of every function its
/// text declares (a template has none), the function values its units take,
/// and its program marks.
fn emissionSection(allocator: std.mem.Allocator, section: Section) Error!iface.Emission {
    var by_key: std.StringHashMapUnmanaged(usize) = .empty;
    for (section.prepared.ordinary_ast, 0..) |ast_index, instance| {
        if (instance < section.program.functions.len) try by_key.put(allocator, section.prepared.keys[ast_index], instance);
    }
    var functions: std.ArrayList(iface.EmittedFunction) = .empty;
    for (section.interface.declarations.functions) |function| {
        const instance = by_key.get(function.key) orelse continue;
        if (instance >= section.report.functions.len) continue;
        const facts = section.report.functions[instance];
        try functions.append(allocator, .{
            .name = facts.name,
            .allocates = facts.allocates,
            .writes = facts.writes,
            .stable = facts.marks.physical.stable,
            .physical = facts.marks.physical.identity,
        });
    }
    std.mem.sort(iface.EmittedFunction, functions.items, {}, emittedBefore);
    var values: std.array_hash_map.String(void) = .empty;
    var marks: iface.Marks = .{};
    for (section.report.functions, section.emit) |facts, chosen| {
        if (!chosen) continue;
        for (facts.values) |name| try values.put(allocator, name, {});
        marks.arena = marks.arena or facts.marks.arena;
        marks.text = marks.text or facts.marks.text;
    }
    const names = try allocator.dupe([]const u8, values.keys());
    std.mem.sort([]const u8, names, {}, lessText);
    return .{ .config = try iface.configName(allocator, section.config), .functions = functions.items, .values = names, .marks = marks };
}

fn emittedBefore(_: void, a: iface.EmittedFunction, b: iface.EmittedFunction) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn lessText(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
