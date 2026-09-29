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
    /// The fragment store the module's units are kept in.
    reuse: fragments.Reuse,
};

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
pub const Units = struct { manifest: []const u8 = "", parts: native_interface.Parts = .{} };

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
/// positions hashes (lowercase hex).
pub const Input = struct { module: []const u8, interface: []const u8, emission: []const u8, positions: []const u8 };

/// How much one compile did: the program's functions, how many it lowered
/// with their bodies, how many it stood in from interfaces, and its units.
pub const Counts = struct { functions: usize = 0, lowered: usize = 0, stood_in: usize = 0, emitted: usize = 0 };

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
    if (!single.declaredOnly()) return error.InternalError;
    const compilation = &single.compilation;
    const program = compilation.program orelse return error.InternalError;
    const prepared = single.request.prepared orelse return error.InternalError;
    const modules = compilation.index.project.modules.items;
    const own = moduleIndex(modules, request.module.module) orelse return error.InternalError;
    const stood = try standIns(arena, single, program.functions.len);
    const facts = importedFacts(arena, request, modules, own) catch |err| switch (err) {
        error.MissingEmission => {
            out.problem = "an import's interface holds emission facts for another configuration";
            return err;
        },
        else => return err,
    };
    const imported = try arena.alloc(?native_interface.Imported, program.functions.len);
    var counts: Counts = .{ .functions = program.functions.len };
    for (program.functions, stood, imported) |function, skipped, *entry| {
        entry.* = null;
        if (!skipped) continue;
        counts.stood_in += 1;
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
    var emit = try emitted(arena, .{ .compilation = compilation, .program = program, .code = code, .own = modules[own].name, .is_entry = request.module.is_entry });
    for (emit) |chosen| counts.emitted += @intFromBool(chosen);
    const physical = try @import("module_physical.zig").archive(arena, code, emit);
    const imported_interfaces = try interfacesOf(arena, request.module.library, modules, own);
    const restored = try @import("module_physical_inputs.zig").restore(arena, code, emit, imported, imported_interfaces);
    code = restored.code;
    emit = @constCast(restored.emit);
    var parts: native_interface.Parts = .{};
    const module: native_interface.Module = .{ .emit = emit, .imported = restored.imported, .remap = try remapOf(arena, request.module.library, modules, own), .arenas = request.config.arenas, .parts = &parts };
    var report: fragments.Report = .{ .arena = arena };
    const policy: native_interface.Policy = .{ .drop_debug = request.config.drop_debug, .step_checks = request.config.step_checks, .frame_checks = request.config.frame_checks };
    out.units.manifest = qbe.generateWithInterface(arena, code, compilation.src, &compilation.diagnostics, .{ .policy = policy, .reuse = request.reuse, .module = &module, .report = &report }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.SourceError => return error.SourceError,
        error.WriteFailed => return error.WriteFailed,
        else => return error.InternalError,
    };
    out.units.parts = parts;
    out.report = report;
    const foreign = try foreignRoles(arena, request.module.library, modules, own);
    const inputs: builder.Inputs = .{
        .index = &single.index,
        .src = compilation.src,
        .syntax = compilation.syntax,
        .program = program,
        .prepared = prepared,
        .facts = single.request.produced orelse return error.InternalError,
        .lowered = &lowered,
    };
    const imports = try importHashes(arena, inputs, .{ .library = request.module.library, .foreign = &foreign }, own);
    const built = try builder.buildOne(arena, inputs, own, .{ .foreign = &foreign, .import_hashes = imports });
    var interface = built.interface;
    interface.emission = try emissionSection(arena, .{ .interface = interface, .prepared = prepared, .program = program, .report = report, .emit = emit, .config = request.config });
    interface.emission.physical = physical;
    out.interface = interface;
    out.hashes = .{
        .interface = try hex(arena, iface.interfaceHash(interface)),
        .implementation = try hex(arena, built.implementation_hash),
        .emission = try hex(arena, iface.emissionHash(interface)),
        .positions = try hex(arena, iface.positionsHash(interface)),
        .inputs = try inputsOf(arena, request.module.library, modules, own),
    };
    out.counts = counts;
}

fn interfacesOf(a: std.mem.Allocator, library: *oracle.Library, modules: []const project.Module, own: usize) Error![]const iface.Interface {
    var out: std.ArrayList(iface.Interface) = .empty;
    for (modules, 0..) |module, index| {
        if (index == own) continue;
        if (library.by_name.get(module.name)) |interface| try out.append(a, interface);
    }
    return out.items;
}

/// Every interface the compile read, in module order.
fn inputsOf(allocator: std.mem.Allocator, library: *oracle.Library, modules: []const project.Module, own: usize) Error![]const Input {
    var out: std.ArrayList(Input) = .empty;
    for (modules, 0..) |module, index| {
        if (index == own) continue;
        const interface = library.by_name.get(module.name) orelse continue;
        try out.append(allocator, .{
            .module = module.name,
            .interface = try hex(allocator, iface.interfaceHash(interface)),
            .emission = try hex(allocator, iface.emissionHash(interface)),
            .positions = try hex(allocator, iface.positionsHash(interface)),
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
const Read = struct { library: *oracle.Library, foreign: *const builder.Foreign };

/// The interface hash of each direct import: from its interface, or for a
/// standard module (read from the compiler) from its interface built here.
fn importHashes(allocator: std.mem.Allocator, inputs: builder.Inputs, read: Read, own: usize) Error![]iface.ImportHash {
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
    compilation: *const @import("project_compile.zig").Compilation,
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
