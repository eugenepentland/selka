//! `mylang compile-module` and `mylang link-modules` (MODULE-COMPILE-1): the
//! per-module build path behind its own commands. `compile-module` compiles
//! one module from its source and its imports' interfaces, writes the
//! module's own interface (with the emission facts its dependents read) and
//! its units, and with `--objects` compiles its units' objects through the
//! build's batch cache. `link-modules` merges the units of every module of a
//! program into one manifest and builds it with the ordinary build driver,
//! which finds each module's objects in the cache. Nothing else reads these
//! outputs yet: the default build is still the whole-program one.
const std = @import("std");
const language = @import("mylang");
const interface_command = @import("module_interface_command.zig");
const iface = language.module_interface;
const oracle = language.module_interface_oracle;
const compile_module = language.module_compile;
const fragments = language.qbe_fragments;
const project_module = language.project;
const diagnostic_output = language.diagnostic_output;

/// The commands' usage text.
pub const usage =
    \\usage: mylang compile-module <entry.my> --module=NAME --interfaces=DIR --out=DIR --arenas=on|off
    \\                             [--cache-dir=DIR] [--drop-debug] [--drop-step-checks]
    \\                             [--drop-frame-checks] [--objects [--qbe=PATH] [--zig=PATH]]
    \\                             [--ready] [--standard-interfaces=DIR] [--tests] [-- BUILD-OPTIONS]
    \\       mylang compile-module <entry.my> --module=NAME --interfaces=DIR --out=DIR --check-only
    \\                             [--cache-dir=DIR] [--ready] [--standard-interfaces=DIR]
    \\       mylang link-modules <entry.my> --units=DIR -o OUT [--cache-dir=DIR] [--mode MODE]
    \\  compile-module  check NAME against the interfaces in DIR, write DIR/NAME.myi with its
    \\                  emission facts and OUT/NAME.units.json; --objects also compiles its
    \\                  objects into the build cache. --arenas is the program's arena switch.
    \\                  --ready (the per-module build's scheduler) signals the interface on stderr
    \\                  as soon as it is written, and writes NAME.result.json and NAME.shared.json
    \\                  in place of NAME.units.json; BUILD-OPTIONS go to the build of the objects.
    \\                  --tests also writes OUT/NAME.tests.json, what a test run merges.
    \\                  --check-only checks NAME, writes DIR/NAME.myi (no emission facts) and
    \\                  OUT/NAME.result.json with its warnings, and emits nothing.
    \\  link-modules    merge every OUT/*.units.json into one manifest and build it into OUT
    \\
;

/// Failures reported as a host failure.
pub const Error = compile_module.Error || error{ReadFailed};

const Options = struct {
    path: []const u8 = "",
    module: ?[]const u8 = null,
    interfaces: ?[]const u8 = null,
    out: ?[]const u8 = null,
    cache: []const u8 = ".mylang-cache",
    config: iface.EmissionConfig = .{ .drop_debug = false, .step_checks = true, .frame_checks = true, .arenas = false },
    arenas: bool = false,
    objects: bool = false,
    /// `--qbe=PATH` and `--zig=PATH`, handed to the build of the objects.
    tools: [2]?[]const u8 = .{ null, null },
    /// `--ready`: the scheduler's protocol (MODULE-SCHEDULE-1).
    ready: bool = false,
    /// `--standard-interfaces=DIR`: read the standard modules' interfaces from
    /// DIR instead of checking them from the compiler's source (MODULE-SCHEDULE-4).
    standard: ?[]const u8 = null,
    /// Everything after `--`: the build options the objects are built with.
    build_args: ?[]const []const u8 = null,
    /// `--check-only` (MODULE-CHECK-1): check and publish the interface only.
    check_only: bool = false,
    /// `--tests` (MODULE-TEST-1): also write the module's test document.
    tests: bool = false,
};

fn parse(args: []const []const u8) ?Options {
    if (args.len < 1) return null;
    var options: Options = .{ .path = args[0] };
    for (args[1..], 1..) |arg, at| {
        if (std.mem.eql(u8, arg, "--")) {
            options.build_args = args[at + 1 ..];
            break;
        }
        if (std.mem.eql(u8, arg, "--ready")) {
            options.ready = true;
        } else if (std.mem.eql(u8, arg, "--check-only")) {
            options.check_only = true;
        } else if (std.mem.eql(u8, arg, "--tests")) {
            options.tests = true;
        } else if (std.mem.startsWith(u8, arg, "--standard-interfaces=")) {
            options.standard = arg["--standard-interfaces=".len..];
        } else if (std.mem.startsWith(u8, arg, "--module=")) {
            options.module = arg["--module=".len..];
        } else if (std.mem.startsWith(u8, arg, "--interfaces=")) {
            options.interfaces = arg["--interfaces=".len..];
        } else if (std.mem.startsWith(u8, arg, "--out=")) {
            options.out = arg["--out=".len..];
        } else if (std.mem.startsWith(u8, arg, "--cache-dir=")) {
            options.cache = arg["--cache-dir=".len..];
        } else if (std.mem.eql(u8, arg, "--arenas=on") or std.mem.eql(u8, arg, "--arenas=off")) {
            options.config.arenas = std.mem.eql(u8, arg, "--arenas=on");
            options.arenas = true;
        } else if (std.mem.eql(u8, arg, "--drop-debug")) {
            options.config.drop_debug = true;
        } else if (std.mem.eql(u8, arg, "--drop-step-checks")) {
            options.config.step_checks = false;
        } else if (std.mem.eql(u8, arg, "--drop-frame-checks")) {
            options.config.frame_checks = false;
        } else if (std.mem.eql(u8, arg, "--objects")) {
            options.objects = true;
        } else if (std.mem.startsWith(u8, arg, "--qbe=")) {
            options.tools[0] = arg;
        } else if (std.mem.startsWith(u8, arg, "--zig=")) {
            options.tools[1] = arg;
        } else return null;
    }
    return options;
}

/// The allocators and I/O one command runs with.
const Context = struct { gpa: std.mem.Allocator, io: std.Io, arena: std.mem.Allocator };

fn stdout(io: std.Io, bytes: []const u8) Error!void {
    std.Io.File.stdout().writeStreamingAll(io, bytes) catch return error.WriteFailed;
}

fn stderr(io: std.Io, bytes: []const u8) Error!void {
    std.Io.File.stderr().writeStreamingAll(io, bytes) catch return error.WriteFailed;
}

/// Run `mylang compile-module ARGS`; returns the process exit status.
pub fn compileModule(process: std.process.Init, args: []const []const u8, identity: []const u8) Error!u8 {
    const options = parse(args) orelse return usageError(process.io);
    const module = options.module orelse return usageError(process.io);
    const directory = options.interfaces orelse return usageError(process.io);
    const out = options.out orelse return usageError(process.io);
    if (!options.arenas and !options.check_only) return usageError(process.io);
    const context: Context = .{ .gpa = process.gpa, .io = process.io, .arena = process.arena.allocator() };
    const a = context.arena;
    const entry = (try interface_command.entryOf(context.arena, context.io, options.path)) orelse return usageError(process.io);
    const is_entry = std.mem.eql(u8, module, entry.name);
    const relative = project_module.modulePath(a, module) catch return usageError(process.io);
    const bytes = if (is_entry) entry.bytes else compile_module.standardSource(relative) orelse
        std.Io.Dir.cwd().readFileAlloc(process.io, try std.fs.path.join(a, &.{ entry.root, relative }), a, .limited(64 * 1024 * 1024)) catch return error.ReadFailed;
    var library = oracle.Library.stored(.{ .io = process.io, .directory = directory, .arena = a, .standard = options.standard });
    // A check-only compile emits nothing, so it opens no fragment store.
    var store: fragments.Store = undefined;
    if (!options.check_only) store = try openStore(context, .{ .cache = options.cache, .identity = identity, .entry = entry.name, .module = module });
    var compiled: compile_module.Compiled = undefined;
    var publish: Publish = .{ .context = context, .directory = directory, .module = module };
    const request: compile_module.Request = .{
        .module = .{ .module = module, .bytes = bytes, .is_entry = is_entry, .library = &library, .assets = entry.assets, .limits = entry.limits },
        .config = options.config,
        .reuse = if (options.check_only) null else .{ .store = &store, .lean = true, .executable = true },
        .ready = if (options.ready) .{ .context = &publish, .run = Publish.run } else null,
        .check_only = options.check_only,
        .tests = options.tests and !options.check_only,
    };
    compile_module.compile(process.gpa, a, request, &compiled) catch |err| switch (err) {
        error.SourceError => {
            try reportCheck(context, &compiled);
            compiled.deinit();
            return 1;
        },
        error.MissingEmission => {
            try stderr(process.io, try std.fmt.allocPrint(a, "mylang compile-module: {s}\n", .{compiled.problem}));
            compiled.deinit();
            return 1;
        },
        error.InternalError => {
            if (compiled.problem.len == 0) return error.InternalError;
            try stderr(process.io, try std.fmt.allocPrint(a, "mylang compile-module: {s}\n", .{compiled.problem}));
            compiled.deinit();
            return 1;
        },
        else => return err,
    };
    defer compiled.deinit();
    std.Io.Dir.cwd().createDirPath(process.io, out) catch return error.WriteFailed;
    if (!options.ready) try publish.write(&compiled);
    if (options.check_only) return checked(context, .{ .out = out, .module = module, .is_entry = is_entry, .compiled = &compiled, .objects = null });
    if (compiled.units.tests.len != 0) try writeAtomic(context, try std.fs.path.join(a, &.{ out, try std.fmt.allocPrint(a, "{s}.tests.json", .{module}) }), compiled.units.tests);
    const units_path = try std.fs.path.join(a, &.{ out, try std.fmt.allocPrint(a, "{s}.units.json", .{module}) });
    if (!options.ready) try writeAtomic(context, units_path, try unitsDocument(a, module, is_entry, &compiled));
    const objects: ?[]const u8 = if (options.objects) try moduleObjects(process, .{ .options = options, .entry = options.path, .module = module, .manifest = compiled.units.manifest }) else null;
    if (options.ready) try writeResult(context, .{ .out = out, .module = module, .is_entry = is_entry, .compiled = &compiled, .objects = objects });
    const summary = try std.json.Stringify.valueAlloc(a, .{
        .version = "module-compile-v1",
        .module = module,
        .hashes = compiled.hashes,
        .counts = compiled.counts,
        .units = units_path,
        .objects = objects,
    }, .{});
    try stdout(process.io, summary);
    try stdout(process.io, "\n");
    return 0;
}

/// Where a compile publishes its interface.
const Publish = struct {
    context: Context,
    directory: []const u8,
    module: []const u8,

    /// MODULE-SCHEDULE-5: the interface is final; write it and tell the
    /// scheduler, which may start the module's dependents while its units and
    /// objects are still being built.
    fn run(context: *anyopaque, compiled: *const compile_module.Compiled) anyerror!void {
        const self: *Publish = @ptrCast(@alignCast(context));
        try self.write(compiled);
        const hashes = compiled.hashes;
        try stderr(self.context.io, try std.fmt.allocPrint(self.context.arena, "{s} {s} {s} {s}\n", .{ ready_marker, hashes.interface, hashes.emission, hashes.positions }));
        // MODULE-SCHEDULE-6: what is left (units, QBE, the assembler) is no
        // longer on the build's critical path, which runs through the
        // dependents' compiles; yield the cores to them. A process already
        // nicer than that stays as it is.
        if (niceness() < background_priority) _ = std.os.linux.syscall3(.setpriority, 0, 0, background_priority);
    }

    fn write(self: *Publish, compiled: *const compile_module.Compiled) Error!void {
        const a = self.context.arena;
        std.Io.Dir.cwd().createDirPath(self.context.io, self.directory) catch return error.WriteFailed;
        try writeAtomic(self.context, try std.fs.path.join(a, &.{ self.directory, try iface.fileName(a, self.module) }), try iface.encode(a, compiled.interface));
    }
};

/// What one module's objects are built from.
const ObjectRequest = struct { options: Options, entry: []const u8, module: []const u8, manifest: []const u8 };

/// Compile the module's units into their batch objects in the build cache
/// (`build --module-objects`), in the build mode its configuration implies;
/// returns the path of the object list.
fn moduleObjects(process: std.process.Init, request: ObjectRequest) Error![]const u8 {
    const a = process.arena.allocator();
    const out = request.options.out.?;
    const manifest_path = try std.fs.path.join(a, &.{ out, try std.fmt.allocPrint(a, "{s}.manifest.json", .{request.module}) });
    std.Io.Dir.cwd().writeFile(process.io, .{ .sub_path = manifest_path, .data = request.manifest }) catch return error.WriteFailed;
    const listed = try std.fs.path.join(a, &.{ out, try std.fmt.allocPrint(a, "{s}.objects.json", .{request.module}) });
    var args: std.ArrayList([]const u8) = .empty;
    try args.appendSlice(a, &.{ request.entry, "--project", try std.fmt.allocPrint(a, "--manifest-file={s}", .{manifest_path}), "--module-objects", "-o", listed });
    try args.append(a, try std.fmt.allocPrint(a, "--cache-dir={s}", .{request.options.cache}));
    if (request.options.build_args) |given| {
        try args.appendSlice(a, given);
    } else {
        if (request.options.config.drop_debug) try args.appendSlice(a, &.{ "--mode", "ReleaseFast" });
        for (request.options.tools) |tool| if (tool) |flag| try args.append(a, flag);
    }
    const status = @import("qbe_build.zig").run(process, args.items) catch return error.WriteFailed;
    if (status != 0) return error.WriteFailed;
    return listed;
}

fn usageError(io: std.Io) Error!u8 {
    try stderr(io, usage);
    return 2;
}

/// Which fragment store a module compile opens.
const StoreSite = struct { cache: []const u8, identity: []const u8, entry: []const u8, module: []const u8 };

/// The fragment store every module compile of one program shares, under the
/// cache directory's frontend root, with a pack per program entry and module:
/// concurrent compiles of one program never rewrite each other's pack, and a
/// compile reads and rewrites only its own module's entries.
fn openStore(context: Context, site: StoreSite) Error!fragments.Store {
    const root = try std.fs.path.join(context.arena, &.{ site.cache, "frontend", "fragments" });
    std.Io.Dir.cwd().createDirPath(context.io, root) catch return error.WriteFailed;
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(context.io, root, context.arena) catch return error.WriteFailed;
    const label = try std.fmt.allocPrint(context.arena, "{s}\x00module-compile\x00{s}", .{ site.entry, site.module });
    return fragments.Store.open(context.arena, context.io, absolute, site.identity, label);
}

/// MODULE-SCHEDULE-6: the nice value a `--ready` compile and the tools it
/// starts run at once its interface is published.
pub const background_priority: usize = 10;

/// This process's nice value (the kernel's `getpriority` answers 20 minus it).
fn niceness() usize {
    const raw = std.os.linux.syscall2(.getpriority, 0, 0);
    if (raw > 40) return 0;
    return 20 -| raw;
}

/// The line a `--ready` compile writes to standard error once its interface
/// is final, followed by its interface, emission and positions hashes.
pub const ready_marker = "\x1emylang-module-ready";

/// What a `--ready` compile's result file is written from.
const ResultSite = struct { out: []const u8, module: []const u8, is_entry: bool, compiled: *const compile_module.Compiled, objects: ?[]const u8 };

/// MODULE-SCHEDULE-1: `NAME.shared.json` (the module's share of the program's
/// metadata unit: descriptor and renderer blocks, frozen literals, host
/// bridges) and `NAME.result.json` (hashes, counts, the module's own warnings,
/// marks, the entry's fields, the digest of its shared part, its objects).
fn writeResult(context: Context, site: ResultSite) Error!void {
    const a = context.arena;
    const compiled = site.compiled;
    const manifest = std.json.parseFromSliceLeaky(std.json.Value, a, compiled.units.manifest, .{}) catch return error.InternalError;
    const shared = try std.json.Stringify.valueAlloc(a, .{
        .descriptors = compiled.units.parts.descriptors,
        .renderers = compiled.units.parts.renderers,
        .owners = compiled.units.parts.owners,
        .glue = compiled.units.parts.glue,
        .manifest = .{
            .runtime_contract = field(manifest, "runtime_contract"),
            .functions = try sharedUnits(a, manifest),
            .embeds = field(manifest, "embeds"),
            .host = field(manifest, "host"),
            .entry = if (site.is_entry) field(manifest, "entry") else std.json.Value{ .string = "" },
        },
    }, .{});
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(shared, &digest, .{});
    try writeAtomic(context, try std.fs.path.join(a, &.{ site.out, try std.fmt.allocPrint(a, "{s}.shared.json", .{site.module}) }), shared);
    const entry = if (site.is_entry) try std.json.Stringify.valueAlloc(a, .{
        .entry = field(manifest, "entry"),
        .entry_parameters = field(manifest, "entry_parameters"),
        .entry_parameter_names = field(manifest, "entry_parameter_names"),
        .entry_argv_element = field(manifest, "entry_argv_element"),
    }, .{}) else null;
    const warnings = try warningsOf(context, compiled, site.module, compiled.single.?.compilation.diagnostics.items.items.len);
    const result = try std.json.Stringify.valueAlloc(a, .{
        .version = "module-result-v1",
        .module = site.module,
        .hashes = compiled.hashes,
        .counts = compiled.counts,
        .warnings = warnings.own,
        .foreign = warnings.foreign,
        .marks = compiled.interface.emission.marks,
        .text_format = field(manifest, "text_format") == .bool and field(manifest, "text_format").bool,
        .entry = entry,
        .shared = &std.fmt.bytesToHex(digest, .lower),
        .objects = site.objects,
        // MODULE-SCHEDULE-6: the nice value the units and objects were built at.
        .nice = niceness(),
    }, .{});
    try writeAtomic(context, try std.fs.path.join(a, &.{ site.out, try std.fmt.allocPrint(a, "{s}.result.json", .{site.module}) }), result);
}

/// Retain every shared literal/site marker with its actual physical unit symbol.
fn sharedUnits(a: std.mem.Allocator, manifest: std.json.Value) Error![]const std.json.Value {
    var units: std.ArrayList(std.json.Value) = .empty;
    for (array(field(manifest, "functions"))) |unit| {
        var kept: std.ArrayList([]const u8) = .empty;
        var lines = std.mem.splitScalar(u8, @import("qbe_build_units.zig").facts(unit), '\n');
        while (lines.next()) |line| if (sharedMarker(line)) try kept.append(a, line);
        if (kept.items.len == 0) continue;
        var row: std.json.ObjectMap = .empty;
        try row.put(a, "symbol", field(unit, "symbol"));
        try row.put(a, "il_facts", .{ .string = try std.mem.join(a, "\n", kept.items) });
        try units.append(a, .{ .object = row });
    }
    return units.items;
}

fn sharedMarker(line: []const u8) bool {
    return std.mem.startsWith(u8, line, "# myl-lit ") or
        std.mem.startsWith(u8, line, "# myl-list ") or
        std.mem.startsWith(u8, line, "# myl-rcsite ");
}

/// One warning a compile reported in another module's text, rendered.
const Foreign = struct { module: []const u8, text: []const u8 };

/// A compile's warnings: those located in the module's own source, rendered
/// as a whole-program check renders them (the scheduler replays them on every
/// build, since an unchanged module is not compiled again), and those located
/// in another module's text, which the scheduler requires that module's own
/// compile to have reported too (MODULE-CHECK-1).
const Warnings = struct { own: []const u8, foreign: []const Foreign };

/// The first `count` diagnostics of a compile, split into its own and
/// foreign warnings.
fn warningsOf(context: Context, compiled: *const compile_module.Compiled, module: []const u8, count: usize) Error!Warnings {
    const single = compiled.single orelse return .{ .own = "", .foreign = &.{} };
    const compilation = &single.compilation;
    const modules = compilation.index.project.modules.items;
    var text: std.ArrayList(u8) = .empty;
    var foreign: std.ArrayList(Foreign) = .empty;
    const items = compilation.diagnostics.items.items;
    for (items[0..@min(count, items.len)]) |item| {
        const at = compilation.src.originalSpan(item.span) catch continue;
        if (at.input >= modules.len) continue;
        const rendered = try diagnostic_output.render(context.gpa, item, compilation.src, .text);
        defer context.gpa.free(rendered);
        if (std.mem.eql(u8, modules[at.input].name, module)) {
            try text.appendSlice(context.arena, rendered);
        } else if (std.mem.eql(u8, modules[at.input].name, oracle.root_module) or std.mem.eql(u8, item.code, "W_UNUSED_IMPORT")) {
            // The compile's own synthetic root is no module of the program,
            // and an import an interface's text keeps is used by the body
            // the interface left out.
            continue;
        } else try foreign.append(context.arena, .{ .module = modules[at.input].name, .text = try context.arena.dupe(u8, rendered) });
    }
    return .{ .own = text.items, .foreign = foreign.items };
}

/// MODULE-CHECK-1: finish a `--check-only` compile: write `NAME.result.json`
/// (hashes, counts, the warnings its check reported) and print its summary.
fn checked(context: Context, site: ResultSite) Error!u8 {
    const a = context.arena;
    const compiled = site.compiled;
    const warnings = try warningsOf(context, compiled, site.module, compiled.counts.diagnostics);
    const result = try std.json.Stringify.valueAlloc(a, .{
        .version = "module-check-v1",
        .module = site.module,
        .hashes = compiled.hashes,
        .counts = compiled.counts,
        .warnings = warnings.own,
        .foreign = warnings.foreign,
    }, .{});
    try writeAtomic(context, try std.fs.path.join(a, &.{ site.out, try std.fmt.allocPrint(a, "{s}.result.json", .{site.module}) }), result);
    const summary = try std.json.Stringify.valueAlloc(a, .{ .version = "module-check-v1", .module = site.module, .hashes = compiled.hashes, .counts = compiled.counts }, .{});
    try stdout(context.io, summary);
    try stdout(context.io, "\n");
    return 0;
}

fn field(value: std.json.Value, name: []const u8) std.json.Value {
    if (value != .object) return .null;
    return value.object.get(name) orelse .null;
}

fn array(value: std.json.Value) []const std.json.Value {
    return if (value == .array) value.array.items else &.{};
}

fn string(value: std.json.Value) []const u8 {
    return if (value == .string) value.string else "";
}

/// Report why a module did not check, like `mylang check`.
fn reportCheck(context: Context, compiled: *compile_module.Compiled) Error!void {
    const single = compiled.single orelse return;
    if (single.project.problem != null) {
        const text = diagnostic_output.renderProject(context.gpa, &single.project, .text) catch return error.OutOfMemory;
        defer context.gpa.free(text);
        return stderr(context.io, text);
    }
    for (single.compilation.diagnostics.items.items) |item| {
        const text = try diagnostic_output.render(context.gpa, item, single.compilation.src, .text);
        defer context.gpa.free(text);
        try stderr(context.io, text);
    }
}

/// Write `bytes` to `path` through a sibling temporary, so a reader never
/// sees a partial artifact.
fn writeAtomic(context: Context, path: []const u8, bytes: []const u8) Error!void {
    const temporary = try std.fmt.allocPrint(context.arena, "{s}.tmp", .{path});
    std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = temporary, .data = bytes }) catch return error.WriteFailed;
    std.Io.Dir.cwd().rename(temporary, std.Io.Dir.cwd(), path, context.io) catch return error.WriteFailed;
}

/// One emitted unit's facts and keys, as the per-module units file lists them.
const UnitRow = struct {
    name: []const u8,
    allocates: bool,
    writes: []const bool,
    unit_key: []const u8,
    il: []const u8,
    meta: []const u8,
};

/// `<module>.units.json`: the module's lean manifest, its runtime blocks, the
/// hashes of its interface and each emitted unit's facts and keys.
fn unitsDocument(a: std.mem.Allocator, module: []const u8, is_entry: bool, compiled: *const compile_module.Compiled) Error![]const u8 {
    var rows: std.ArrayList(UnitRow) = .empty;
    for (compiled.report.functions) |entry| {
        if (!entry.emitted) continue;
        try rows.append(a, .{ .name = entry.name, .allocates = entry.allocates, .writes = entry.writes, .unit_key = entry.keys.unit, .il = entry.keys.il, .meta = entry.keys.meta });
    }
    var out: std.Io.Writer.Allocating = .init(a);
    var json: std.json.Stringify = .{ .writer = &out.writer };
    writeUnits(&json, .{ .module = module, .is_entry = is_entry, .compiled = compiled, .rows = rows.items }) catch return error.OutOfMemory;
    return out.toOwnedSlice();
}

const UnitsFile = struct { module: []const u8, is_entry: bool, compiled: *const compile_module.Compiled, rows: []const UnitRow };

fn writeUnits(json: *std.json.Stringify, file: UnitsFile) std.json.Stringify.Error!void {
    const compiled = file.compiled;
    try json.beginObject();
    try json.objectField("version");
    try json.write("module-units-v1");
    try json.objectField("module");
    try json.write(file.module);
    try json.objectField("entry");
    try json.write(file.is_entry);
    try json.objectField("hashes");
    try json.write(compiled.hashes);
    try json.objectField("counts");
    try json.write(compiled.counts);
    try json.objectField("config");
    try json.write(compiled.interface.emission.config);
    try json.objectField("marks");
    try json.write(compiled.interface.emission.marks);
    try json.objectField("values");
    try json.write(compiled.interface.emission.values);
    try json.objectField("descriptors");
    try json.write(compiled.units.parts.descriptors);
    try json.objectField("renderers");
    try json.write(compiled.units.parts.renderers);
    try json.objectField("owners");
    try json.write(compiled.units.parts.owners);
    try json.objectField("glue");
    try json.write(compiled.units.parts.glue);
    try json.objectField("units");
    try json.write(file.rows);
    try json.objectField("manifest");
    try json.beginWriteRaw();
    try json.writer.writeAll(compiled.units.manifest);
    json.endWriteRaw();
    try json.endObject();
}

/// Run `mylang link-modules ARGS`: merge every module's units in `--units`
/// into one executable manifest and build it with the ordinary driver, whose
/// cache holds the objects each module compile made. Returns the build's status.
pub fn linkModules(process: std.process.Init, args: []const []const u8) Error!u8 {
    const a = process.arena.allocator();
    if (args.len < 1) return usageError(process.io);
    var units: ?[]const u8 = null;
    var build_args: std.ArrayList([]const u8) = .empty;
    try build_args.appendSlice(a, &.{ args[0], "--project" });
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--units=")) units = arg["--units=".len..] else try build_args.append(a, arg);
    }
    const directory = units orelse return usageError(process.io);
    const merged = language.module_link.merge(a, try readUnits(a, process.io, directory)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Conflict => {
            try stderr(process.io, "mylang link-modules: two modules emitted one symbol with different units\n");
            return 1;
        },
        error.Incomplete => {
            try stderr(process.io, "mylang link-modules: the units directory has no entry module, or its modules name different unit stores\n");
            return 1;
        },
    };
    const manifest_path = try std.fs.path.join(a, &.{ directory, "program.json" });
    std.Io.Dir.cwd().writeFile(process.io, .{ .sub_path = manifest_path, .data = merged }) catch return error.WriteFailed;
    try build_args.append(a, try std.fmt.allocPrint(a, "--manifest-file={s}", .{manifest_path}));
    return @import("qbe_build.zig").run(process, build_args.items) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => {
            try stderr(process.io, try std.fmt.allocPrint(a, "mylang link-modules: build failed: {s}\n", .{@errorName(err)}));
            return 2;
        },
    };
}

/// Every `*.units.json` in `directory`, in name order, parsed into `a`.
fn readUnits(a: std.mem.Allocator, io: std.Io, directory: []const u8) Error![]const std.json.Value {
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true }) catch return error.ReadFailed;
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var walker = dir.iterate();
    while (walker.next(io) catch return error.ReadFailed) |item| {
        if (item.kind == .file and std.mem.endsWith(u8, item.name, ".units.json")) try names.append(a, try a.dupe(u8, item.name));
    }
    std.mem.sort([]const u8, names.items, {}, lessText);
    const files = try a.alloc(std.json.Value, names.items.len);
    for (names.items, files) |name, *file| {
        const bytes = dir.readFileAlloc(io, name, a, .limited(1 << 30)) catch return error.ReadFailed;
        file.* = std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{}) catch return error.ReadFailed;
    }
    return files;
}

fn lessText(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
