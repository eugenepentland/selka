//! `mylang interfaces`: emit, inspect and verify module interface artifacts
//! (MODULE-INTERFACE-1). This stage changes no build: `emit` writes each
//! module's interface from today's whole-program check, `check` checks one
//! module against those files instead of its imports' sources, and `oracle`
//! asserts, module by module, that such a check equals the whole program's.
const std = @import("std");
const language = @import("mylang");
const project_config = @import("mylang").project_config;
const iface = language.module_interface;
const builder = language.module_interface_build;
const oracle = language.module_interface_oracle;
const diagnostic_output = language.diagnostic_output;
const project_module = language.project;

/// The command's usage text.
pub const usage =
    \\usage: mylang interfaces emit <entry.my> [--out=DIR] [--cache-dir=DIR]
    \\       mylang interfaces show <module.myi>
    \\       mylang interfaces check <entry.my> --module=NAME --from=DIR
    \\       mylang interfaces oracle <entry.my> [--module=NAME] [--from=DIR]
    \\  emit    check the project as one program and write <module>.myi and index.json
    \\          for every module (default DIR: <cache-dir>/interfaces, cache-dir .mylang-cache)
    \\  show    print one interface artifact as canonical text
    \\  check   check one module against the interfaces in DIR, not its imports' sources
    \\  oracle  check each module against its imports' interfaces and compare with the
    \\          whole-program check; exits 1 on any difference
    \\
;

/// Failures the command reports as a host failure.
pub const Error = oracle.Error || error{ WriteFailed, ReadFailed };

const Options = struct {
    action: []const u8 = "",
    path: []const u8 = "",
    out: ?[]const u8 = null,
    cache: []const u8 = ".mylang-cache",
    module: ?[]const u8 = null,
    from: ?[]const u8 = null,
};

fn parse(args: []const []const u8) ?Options {
    if (args.len < 2) return null;
    var options: Options = .{ .action = args[0], .path = args[1] };
    for (args[2..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--out=")) {
            options.out = arg["--out=".len..];
        } else if (std.mem.startsWith(u8, arg, "--cache-dir=")) {
            options.cache = arg["--cache-dir=".len..];
        } else if (std.mem.startsWith(u8, arg, "--module=")) {
            options.module = arg["--module=".len..];
        } else if (std.mem.startsWith(u8, arg, "--from=")) {
            options.from = arg["--from=".len..];
        } else return null;
    }
    return options;
}

/// Run `mylang interfaces ARGS`; returns the process exit status.
pub fn run(process: std.process.Init, args: []const []const u8) Error!u8 {
    const options = parse(args) orelse return usageError(process);
    const context: Context = .{ .gpa = process.gpa, .io = process.io, .arena = process.arena.allocator() };
    if (std.mem.eql(u8, options.action, "emit")) return emit(context, options);
    if (std.mem.eql(u8, options.action, "show")) return show(context, options);
    if (std.mem.eql(u8, options.action, "check")) return checkOne(context, options);
    if (std.mem.eql(u8, options.action, "oracle")) return verify(context, options);
    return usageError(process);
}

fn usageError(process: std.process.Init) Error!u8 {
    std.Io.File.stderr().writeStreamingAll(process.io, usage) catch return error.WriteFailed;
    return 2;
}

const Context = struct { gpa: std.mem.Allocator, io: std.Io, arena: std.mem.Allocator };

fn stdout(context: Context, bytes: []const u8) Error!void {
    std.Io.File.stdout().writeStreamingAll(context.io, bytes) catch return error.WriteFailed;
}

fn stderr(context: Context, bytes: []const u8) Error!void {
    std.Io.File.stderr().writeStreamingAll(context.io, bytes) catch return error.WriteFailed;
}

/// Report why a whole program did not load or check, like `mylang check`.
fn reportWhole(context: Context, whole: *oracle.Whole) Error!void {
    if (whole.project.problem != null) {
        const text = diagnostic_output.renderProject(context.gpa, &whole.project, .text) catch return error.OutOfMemory;
        defer context.gpa.free(text);
        return stderr(context, text);
    }
    for (whole.compilation.diagnostics.items.items) |item| {
        const text = try diagnostic_output.render(context.gpa, item, whole.compilation.src, .text);
        defer context.gpa.free(text);
        try stderr(context, text);
    }
}

/// Resolve an entry path the way the project commands do — a `*_test.my`
/// under a project root is named from that root, anything else is its stem
/// beside its directory — and read it, appending the test runner's `main`
/// stub when it declares none.
pub fn entryOf(arena: std.mem.Allocator, io: std.Io, path: []const u8) Error!?oracle.Entry {
    const context: Context = .{ .gpa = arena, .io = io, .arena = arena };
    const located = project_config.testEntryLocation(context.arena, context.io, path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    const basename = std.fs.path.basename(path);
    if (located == null and !std.mem.endsWith(u8, basename, ".my")) return null;
    const root = if (located) |location| location.root else std.fs.path.dirname(path) orelse ".";
    const name = if (located) |location| location.name else basename[0 .. basename.len - 3];
    const relative = project_module.modulePath(context.arena, name) catch return null;
    const file = try std.fs.path.join(context.arena, &.{ root, relative });
    const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, file, context.arena, .limited(64 * 1024 * 1024)) catch return null;
    const files = try context.arena.create(language.project_files.Files);
    const config_path = project_config.discover(context.arena, context.io, path) catch null;
    files.* = .{ .io = context.io, .root = root, .embed_root = if (config_path) |configured| std.fs.path.dirname(configured) orelse root else root };
    return .{ .root = root, .name = name, .bytes = try withMain(context.arena, bytes), .assets = files.provider() };
}

/// A source as a project check reads it: unchanged when it declares `main`,
/// otherwise with the test runner's stub appended.
fn withMain(allocator: std.mem.Allocator, bytes: []const u8) Error![]const u8 {
    if (project_config.declaresMain(bytes)) return bytes;
    const separator: []const u8 = if (bytes.len != 0 and bytes[bytes.len - 1] != '\n') "\n" else "";
    return std.mem.concat(allocator, u8, &.{ bytes, separator, oracle.main_stub });
}

fn openWhole(context: Context, path: []const u8) Error!?*oracle.Whole {
    const entry = (try entryOf(context.arena, context.io, path)) orelse {
        try stderr(context, "mylang interfaces: the entry must be a readable identifier.my file\n");
        return null;
    };
    var whole: *oracle.Whole = undefined;
    oracle.Whole.open(context.gpa, context.io, entry, &whole) catch |err| switch (err) {
        error.SourceError => {
            try reportWhole(context, whole);
            whole.deinit();
            return null;
        },
        else => return err,
    };
    return whole;
}

fn emit(context: Context, options: Options) Error!u8 {
    const whole = (try openWhole(context, options.path)) orelse return 1;
    defer whole.deinit();
    const set = try whole.buildInterfaces();
    const directory = options.out orelse try std.fs.path.join(context.arena, &.{ options.cache, "interfaces" });
    std.Io.Dir.cwd().createDirPath(context.io, directory) catch return error.WriteFailed;
    var rows: std.ArrayList(IndexRow) = .empty;
    for (set.interfaces, 0..) |interface, module| {
        const bytes = try iface.encode(context.arena, interface);
        const name = try iface.fileName(context.arena, interface.module);
        const target = try std.fs.path.join(context.arena, &.{ directory, name });
        std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = target, .data = bytes }) catch return error.WriteFailed;
        try rows.append(context.arena, try indexRow(context.arena, set, module, bytes.len));
    }
    const index = try std.json.Stringify.valueAlloc(context.arena, IndexDocument{ .entry = whole.entry.name, .modules = rows.items }, .{});
    const index_path = try std.fs.path.join(context.arena, &.{ directory, "index.json" });
    std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = index_path, .data = index }) catch return error.WriteFailed;
    try stdout(context, index);
    try stdout(context, "\n");
    return 0;
}

/// `index.json`: one row per module.
const IndexDocument = struct { version: []const u8 = "module-interface-index-v1", entry: []const u8, modules: []const IndexRow };
const IndexRow = struct {
    module: []const u8,
    interface_hash: []const u8,
    implementation_hash: []const u8,
    positions_hash: []const u8,
    bytes: usize,
    counts: Counts,
    imports: []const []const u8,
};
/// Per-interface counts: functions by role, types, re-exports, shapes and text bytes.
const Counts = struct { roles: Roles = .{}, types: usize = 0, reexports: usize = 0, shapes: usize = 0, text_bytes: usize = 0 };
/// Functions of each `module_interface.Role`.
const Roles = struct {
    declared: usize = 0,
    template: usize = 0,
    constant: usize = 0,
    conversion: usize = 0,
    foreign: usize = 0,
    inlined: usize = 0,
    evaluated: usize = 0,
};

fn indexRow(allocator: std.mem.Allocator, set: builder.Set, module: usize, bytes: usize) Error!IndexRow {
    const interface = set.interfaces[module];
    const declarations = interface.declarations;
    var counts: Counts = .{ .types = declarations.types.len, .reexports = declarations.reexports.len, .shapes = declarations.shapes.len, .text_bytes = interface.text.len };
    for (declarations.functions) |function| switch (function.role) {
        inline else => |role| @field(counts.roles, @tagName(role)) += 1,
    };
    return .{
        .module = interface.module,
        .interface_hash = try hex(allocator, set.interface_hashes[module]),
        .implementation_hash = try hex(allocator, set.implementation_hashes[module]),
        .positions_hash = try hex(allocator, iface.positionsHash(interface)),
        .bytes = bytes,
        .counts = counts,
        .imports = interface.imports,
    };
}

fn hex(allocator: std.mem.Allocator, digest: [32]u8) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{x}", .{digest});
}

fn show(context: Context, options: Options) Error!u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, options.path, context.arena, .limited(256 * 1024 * 1024)) catch return error.ReadFailed;
    const interface = iface.decode(context.arena, bytes) orelse {
        try stderr(context, "mylang interfaces show: not a module-interface-v2 artifact\n");
        return 1;
    };
    try stdout(context, try iface.render(context.arena, interface));
    return 0;
}

/// The artifacts in `directory` as a library that reads each one on first use.
fn readLibrary(context: Context, directory: []const u8) oracle.Library {
    return oracle.Library.stored(.{ .io = context.io, .directory = directory, .arena = context.arena });
}

/// Check one module against the interfaces in `--from`, reading only its own source.
fn checkOne(context: Context, options: Options) Error!u8 {
    const module = options.module orelse return usageMessage(context);
    const from = options.from orelse return usageMessage(context);
    const entry = (try entryOf(context.arena, context.io, options.path)) orelse return usageMessage(context);
    var library = readLibrary(context, from);
    const is_entry = std.mem.eql(u8, module, entry.name);
    const path = try std.fs.path.join(context.arena, &.{ entry.root, project_module.modulePath(context.arena, module) catch return usageMessage(context) });
    const bytes = if (is_entry) entry.bytes else std.Io.Dir.cwd().readFileAlloc(context.io, path, context.arena, .limited(64 * 1024 * 1024)) catch return error.ReadFailed;
    var single: *oracle.Single = undefined;
    const request: oracle.ModuleRequest = .{ .module = module, .bytes = bytes, .is_entry = is_entry, .library = &library, .assets = entry.assets, .limits = entry.limits };
    var status: u8 = 0;
    oracle.Single.open(context.gpa, request, &single) catch |err| switch (err) {
        error.SourceError => status = 1,
        else => return err,
    };
    defer single.deinit();
    const result = try single.result(context.arena, &library, module);
    const text = try std.json.Stringify.valueAlloc(context.arena, .{
        .version = "module-interface-check-v1",
        .module = module,
        .status = status,
        .stood_in = single.request.stood_in,
        .declared_only = single.declaredOnly(),
        .diagnostics = result.diagnostics,
        .functions = result.functions.len,
        .unmapped = result.unmapped,
    }, .{});
    try stdout(context, text);
    try stdout(context, "\n");
    return status;
}

fn usageMessage(context: Context) Error!u8 {
    try stderr(context, usage);
    return 2;
}

/// One module's oracle row.
const Row = struct {
    module: []const u8,
    status: []const u8,
    stood_in: usize,
    compared: Compared,
    mismatches: Mismatches,
};
/// How many checked functions, contexts and lowered bodies one module's check compared.
const Compared = struct { functions: usize, contexts: usize, lowered: usize };
/// Everything that differed for one module.
const Mismatches = struct {
    functions: []const []const u8 = &.{},
    contexts: []const []const u8 = &.{},
    lowered: []const []const u8 = &.{},
    diagnostics: []const []const u8 = &.{},
    unmapped: usize = 0,
    fallback: bool = false,
};

/// Check every module (or `--module`) against its imports' interfaces and
/// compare each with the whole-program check. The interfaces are encoded and
/// decoded first (or read from `--from`), so the check sees only artifacts.
fn verify(context: Context, options: Options) Error!u8 {
    const whole = (try openWhole(context, options.path)) orelse return 1;
    defer whole.deinit();
    const reference = try whole.result(context.arena);
    var library = if (options.from) |from| readLibrary(context, from) else try roundTrip(context, try whole.buildInterfaces());
    var rows: std.ArrayList(Row) = .empty;
    var comparisons: std.ArrayList(oracle.Comparison) = .empty;
    var equal = true;
    var totals: Totals = .{};
    for (whole.project.modules.items) |module| {
        if (options.module) |wanted| if (!std.mem.eql(u8, wanted, module.name)) continue;
        if (oracle.standardModule(context.arena, module.name)) continue;
        const request: oracle.ModuleRequest = .{
            .module = module.name,
            .bytes = module.src.bytes,
            .is_entry = std.mem.eql(u8, module.name, whole.entry.name),
            .library = &library,
            .assets = whole.entry.assets,
            .limits = whole.entry.limits,
        };
        const outcome = try checkModule(context, request, reference);
        try comparisons.append(context.arena, outcome.comparison);
        totals.add(outcome);
        if (!outcome.equal()) equal = false;
        try rows.append(context.arena, outcome.row);
    }
    const missing = if (options.module == null) try oracle.missingDiagnostics(context.arena, reference, comparisons.items) else &.{};
    if (missing.len != 0) equal = false;
    const text = try std.json.Stringify.valueAlloc(context.arena, .{
        .version = "module-interface-oracle-v1",
        .entry = whole.entry.name,
        .equal = equal,
        .modules = rows.items.len,
        .functions_compared = totals.functions,
        .contexts_compared = totals.contexts,
        .lowered_compared = totals.lowered,
        .stood_in = totals.stood_in,
        .whole_program_diagnostics = reference.diagnostics.len,
        .missing_diagnostics = missing,
        .results = rows.items,
    }, .{});
    try stdout(context, text);
    try stdout(context, "\n");
    return if (equal) 0 else 1;
}

const Totals = struct {
    functions: usize = 0,
    contexts: usize = 0,
    lowered: usize = 0,
    stood_in: usize = 0,
    fn add(self: *Totals, outcome: Outcome) void {
        self.functions += outcome.row.compared.functions;
        self.contexts += outcome.row.compared.contexts;
        self.lowered += outcome.row.compared.lowered;
        self.stood_in += outcome.row.stood_in;
    }
};

const Outcome = struct {
    row: Row,
    comparison: oracle.Comparison,
    fn equal(self: Outcome) bool {
        const m = self.row.mismatches;
        return std.mem.eql(u8, self.row.status, "checked") and self.comparison.mismatches() == 0 and !m.fallback;
    }
};

fn checkModule(context: Context, request: oracle.ModuleRequest, reference: oracle.Result) Error!Outcome {
    var single: *oracle.Single = undefined;
    var status: []const u8 = "checked";
    oracle.Single.open(context.gpa, request, &single) catch |err| switch (err) {
        error.SourceError => status = if (single.project.problem != null) "did-not-load" else "did-not-check",
        else => return err,
    };
    defer single.deinit();
    const result = try single.result(context.arena, request.library, request.module);
    const comparison = try oracle.compare(context.arena, reference, result, request.module);
    return .{
        .comparison = comparison,
        .row = .{
            .module = request.module,
            .status = status,
            .stood_in = single.request.stood_in,
            .compared = .{ .functions = comparison.functions.compared, .contexts = comparison.contexts.compared, .lowered = comparison.lowered.compared },
            .mismatches = .{
                .functions = comparison.functions.mismatches,
                .contexts = comparison.contexts.mismatches,
                .lowered = comparison.lowered.mismatches,
                .diagnostics = comparison.extra_diagnostics,
                .unmapped = comparison.unmapped,
                .fallback = !single.declaredOnly(),
            },
        },
    };
}

/// Encode and decode every interface, so an in-process oracle reads exactly
/// what a stored artifact holds.
fn roundTrip(context: Context, set: builder.Set) Error!oracle.Library {
    const list = try context.arena.alloc(iface.Interface, set.interfaces.len);
    for (set.interfaces, list) |interface, *decoded| {
        const bytes = try iface.encode(context.arena, interface);
        decoded.* = iface.decode(context.arena, bytes) orelse return error.InternalError;
    }
    return oracle.Library.of(context.arena, list);
}
