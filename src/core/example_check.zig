//! `selka check FILE --examples`: check every docstring example of the entry's
//! modules the way `selka test` compiles it, and run none of them.
//!
//! The entry is checked as a test run checks it (a file with no `main` gets the
//! runner's stub), then each example block is checked inside the function the
//! runner appends to its module, probe first and the typed display second
//! (`runExample` in `test_runner.zig`). An example that does not compile is
//! reported where it is written, in the docstring, and carries the compiler's
//! structured repair only when that repair maps exactly onto the docstring's text
//! (`docstring_example_diagnostics.zig`); `selka fix` applies those repairs.
//!
//! A graph with no example is not checked at all, and a block that passed once is
//! remembered under a key naming everything its check reads (the compiler, its
//! module, that module's imports and their sources), so later rounds, a sibling
//! entry importing the same module and the final report cost no second check. The
//! entry's own bodies are checked only when some example has to be compiled.
const std = @import("std");
const product = @import("selka").product;
const language = @import("selka");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const runner = @import("test_runner.zig");

const examples = language.docstring_example_source;
const restating = language.docstring_example_diagnostics;

/// What stops a check before it has a status: memory, or an unwritable stream.
pub const Error = runner.Error;

const usage = "usage: selka check <entry.selka> --examples [--diagnostics=text|json] [--cache-dir=DIR] [--no-cache]\n";
/// The success line, which `selka fix` drops with the plain check's.
const passed = language.diagnostic_output.check_passed;

const Options = struct {
    path: []const u8 = "",
    cache: []const u8 = product.core_work_dir,
    format: language.diagnostic_output.Format = .text,
    no_cache: bool = false,
};

/// What every block's check shares.
const Context = struct { init: std.process.Init, options: Options, entry: project_entry.Entry, text: runner.EntryText };

/// Check the docstring examples of `args`' entry and return the process status: 0
/// when the entry and all its examples check, 1 when anything is refused, 2 on a
/// usage or host failure, 3 for a denied import.
pub fn run(given: std.process.Init, args: []const []const u8) Error!u8 {
    const options = parse(args) orelse {
        try write(given.io, usage);
        return 2;
    };
    // The project's `stores`, before any store opens (FR8).
    if (try @import("cli_run.zig").applyStores(given, options.path, options.format == .json)) return 2;
    const init = try @import("compiler_sharing.zig").prepare(given, options.no_cache);
    const allocator = init.arena.allocator();
    // Its frontend stores stay open for the whole check, so the work directory is held for it (`check_command.zig`).
    const retention = @import("work_retention.zig");
    const held: ?retention.Hold = if (options.no_cache) null else try retention.hold(allocator, init.io, options.cache);
    defer if (!options.no_cache) retention.automatic(allocator, init.gpa, init.io, options.cache, init.environ_map);
    defer if (held) |lease| lease.release();
    var report: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(allocator, init.io, options.path, &report) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, report.items);
        return project_entry.status(err);
    };
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, entry.path, allocator, .limited(64 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, try std.fmt.allocPrint(allocator, "selka check: cannot read '{s}': {s}\n", .{ options.path, @errorName(err) }));
        return 2;
    };
    const context: Context = .{
        .init = init,
        .options = options,
        .entry = entry,
        .text = .{ .overlay = try runner.headerlessTest(allocator, entry, bytes), .stub = !runner.definesMain(bytes) },
    };
    var session = frontend.Session.init(init.gpa, init.io, entry.root);
    defer session.deinit();
    entry.configure(&session);
    if (!options.no_cache) {
        try session.enableCache(init.gpa, options.cache);
        try session.enableSharedCache(init.environ_map);
    }
    session.setReportFormat(options.format);
    context.text.apply(&session, context.text.overlay);
    const project_mode = language.project.validName(entry.name);
    if (project_mode) {
        session.declare(allocator, entry.name, &report) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try write(init.io, report.items);
                return 1;
            },
        };
    }
    if (!holdsExamples(&session, bytes)) return finish(context, 0, 0);
    // A project graph lists its examples as soon as it loads, so a graph whose every
    // example passed before is not compiled; a header-less file needs its check first.
    var loaded = try runner.Loaded.of(allocator, &session);
    var blocks: []const examples.Block = if (project_mode) try runner.exampleBlocks(allocator, loaded, entry.name, null) else &.{};
    var pending: std.ArrayList(Pending) = .empty;
    if (project_mode) try pending.appendSlice(allocator, try unremembered(context, loaded, blocks));
    if (project_mode and pending.items.len == 0) return finish(context, 0, countExamples(blocks));
    const checked = (if (project_mode) session.checkDeclared(allocator, &report) else runner.checkEntry(&session, allocator, entry, &report)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try write(init.io, report.items);
            return 1;
        },
    };
    entry.validate(allocator, &session, &report) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        try write(init.io, report.items);
        return project_entry.status(err);
    };
    if (!project_mode) {
        loaded = try runner.Loaded.of(allocator, &session);
        blocks = try runner.exampleBlocks(allocator, loaded, runner.moduleName(checked.program, entry.name), null);
        for (blocks) |block| try pending.append(allocator, .{ .block = block, .key = null });
    }
    var out: std.ArrayList(u8) = .empty;
    var failed: usize = 0;
    for (pending.items) |item| {
        const errors = try refuseBlock(context, item.block, &out);
        failed += errors;
        if (errors == 0) if (item.key) |key| rememberReceipt(context, key);
    }
    try write(init.io, out.items);
    return finish(context, failed, countExamples(blocks));
}

/// An example block and the key its pass is remembered under, when it has one.
const Pending = struct { block: examples.Block, key: ?[32]u8 };

/// The blocks whose pass no receipt vouches for.
fn unremembered(context: Context, loaded: runner.Loaded, blocks: []const examples.Block) Error![]const Pending {
    var pending: std.ArrayList(Pending) = .empty;
    for (blocks) |block| {
        const key = receiptKey(context, loaded, block);
        if (key) |known| if (receiptHeld(context, known)) continue;
        try pending.append(context.init.arena.allocator(), .{ .block = block, .key = key });
    }
    return pending.items;
}

fn countExamples(blocks: []const examples.Block) usize {
    var total: usize = 0;
    for (blocks) |block| total += block.examples.len;
    return total;
}

/// The status and, on success, the line `selka fix` drops with the plain check's.
fn finish(context: Context, failed: usize, total: usize) Error!u8 {
    if (failed != 0) return 1;
    try write(context.init.io, try std.fmt.allocPrint(context.init.arena.allocator(), "{s} ({d} example{s})\n", .{ passed, total, if (total == 1) "" else "s" }));
    return 0;
}

/// Whether the loaded graph has a docstring that could hold an example: a project
/// graph is read from the modules `declare` loaded, a header-less file from its text.
fn holdsExamples(session: *const frontend.Session, entry_bytes: []const u8) bool {
    if (session.project.modules.items.len == 0) return std.mem.indexOf(u8, entry_bytes, ">>> ") != null;
    for (session.project.modules.items) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        if (std.mem.indexOf(u8, module.src.bytes, ">>> ") != null) return true;
    }
    return false;
}

/// Compile one function's examples, probe then display, as `runExample` does, and
/// append the diagnostics of a refusal to `out`. The number of errors found.
fn refuseBlock(context: Context, block: examples.Block, out: *std.ArrayList(u8)) Error!usize {
    const a = context.init.arena.allocator();
    const transcript = try examples.transcriptOf(a, block);
    const probe = try examples.render(a, block, null, transcript);
    var probe_session = frontend.Session.init(context.init.gpa, context.init.io, context.entry.root);
    defer probe_session.deinit();
    var problems: std.ArrayList(u8) = .empty;
    const probed = try overlaySession(context, &probe_session, .{ .block = block, .overlay = probe }, &problems) orelse
        return restated(context, out, .{ .block = block, .overlay = probe }, problems.items);
    const display = try examples.displaysOf(a, probed.program, probed.src, block, probe);
    const overlay = try examples.render(a, block, display, transcript);
    var session = frontend.Session.init(context.init.gpa, context.init.io, context.entry.root);
    defer session.deinit();
    problems.clearRetainingCapacity();
    _ = try overlaySession(context, &session, .{ .block = block, .overlay = overlay }, &problems) orelse
        return restated(context, out, .{ .block = block, .overlay = overlay }, problems.items);
    return 0;
}

const receipt_directory = "example-ok-v1";

/// The key a block's pass is remembered under: the compiler, the project
/// configuration, the block, its module and every module that module imports
/// (directly or not) with the exact bytes of each. Null for a header-less file.
/// The entry and its other modules are absent on purpose: the plain check owns
/// their diagnostics, and a module's examples do not read them.
fn receiptKey(context: Context, loaded: runner.Loaded, block: examples.Block) ?[32]u8 {
    if (context.options.no_cache or loaded.single()) return null;
    var found: ?usize = null;
    for (loaded.modules, 0..) |module, index| {
        if (std.mem.eql(u8, module.src.path, block.src.path)) found = index;
    }
    const first = found orelse return null;
    var closure = std.bit_set.DynamicBitSetUnmanaged.initEmpty(context.init.arena.allocator(), loaded.modules.len) catch return null;
    var pending: std.ArrayList(usize) = .empty;
    pending.append(context.init.arena.allocator(), first) catch return null;
    closure.set(first);
    while (pending.pop()) |index| for (loaded.modules[index].imports) |import| {
        if (import.target >= loaded.modules.len or closure.isSet(import.target)) continue;
        closure.set(import.target);
        pending.append(context.init.arena.allocator(), import.target) catch return null;
    };
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(frontend.compiler_identity);
    if (context.entry.configuration) |configured| hash.update(&configured.digest);
    hash.update(block.function);
    hash.update("\x00");
    var members = closure.iterator(.{});
    while (members.next()) |index| {
        hash.update(loaded.modules[index].src.path);
        hash.update(&loaded.modules[index].digest);
    }
    // The entry's own text also carries the runner's stub `main` when it declares none.
    if (context.text.stub and std.mem.eql(u8, loaded.modules[first].name, context.entry.name)) hash.update("stub");
    return hash.finalResult();
}

fn receiptPath(context: Context, key: [32]u8) ?[]const u8 {
    return std.fmt.allocPrint(context.init.arena.allocator(), "{s}/{s}/{s}", .{ context.options.cache, receipt_directory, std.fmt.bytesToHex(key, .lower) }) catch null;
}

/// Whether the block's check passed before under exactly this key.
fn receiptHeld(context: Context, key: [32]u8) bool {
    const path = receiptPath(context, key) orelse return false;
    std.Io.Dir.cwd().access(context.init.io, path, .{}) catch return false;
    return true;
}

/// Record a pass; a cache that cannot be written only costs a later check.
fn rememberReceipt(context: Context, key: [32]u8) void {
    const path = receiptPath(context, key) orelse return;
    std.Io.Dir.cwd().createDirPath(context.init.io, std.fs.path.dirname(path).?) catch return;
    std.Io.Dir.cwd().writeFile(context.init.io, .{ .sub_path = path, .data = "" }) catch return;
}

/// Check the entry with `at`'s overlay standing in for its module, reporting as
/// `diagnostic-v1` lines in `problems`; null when the check is refused.
fn overlaySession(context: Context, session: *frontend.Session, at: restating.Overlaid, problems: *std.ArrayList(u8)) Error!?frontend.Checked {
    const init = context.init;
    const a = init.arena.allocator();
    context.entry.configure(session);
    if (!context.options.no_cache) {
        try session.enableCache(init.gpa, context.options.cache);
        try session.enableSharedCache(init.environ_map);
    }
    session.setReportFormat(.json);
    const providers = try std.mem.concat(a, frontend.Provider, &.{ &.{.{ .path = at.block.src.path, .text = at.overlay.text }}, context.text.overlay });
    context.text.apply(session, providers);
    return runner.checkEntry(session, a, context.entry, problems) catch |err| { // UNTESTED-ERROR: a refused example is this path; the CLI fix and check --examples tests reach it end to end
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
}

/// Append the refused check's errors, located in the docstring. A refusal that
/// left no error to show still counts as one failure.
fn restated(context: Context, out: *std.ArrayList(u8), at: restating.Overlaid, problems: []const u8) Error!usize {
    const tally = try restating.restate(context.init.arena.allocator(), out, at, problems, context.options.format);
    return @max(tally.errors, 1);
}

fn write(io: std.Io, bytes: []const u8) Error!void {
    std.Io.File.stderr().writeStreamingAll(io, bytes) catch return error.WriteFailed;
}

/// The entry, the `--examples` marker and the switches `selka fix` passes on.
fn parse(args: []const []const u8) ?Options {
    var options: Options = .{};
    var marked = false;
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--examples")) {
            marked = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            options.no_cache = true;
        } else if (std.mem.eql(u8, arg, "--diagnostics=json")) {
            options.format = .json;
        } else if (std.mem.eql(u8, arg, "--diagnostics=text")) {
            options.format = .text;
        } else if (std.mem.startsWith(u8, arg, "--cache-dir=") and arg.len > "--cache-dir=".len) {
            options.cache = arg["--cache-dir=".len..];
        } else if (std.mem.eql(u8, arg, "--cache-dir") and index + 1 < args.len) {
            index += 1;
            options.cache = args[index];
        } else if (options.path.len == 0 and !std.mem.startsWith(u8, arg, "-")) {
            options.path = arg;
        } else return null;
    }
    return if (options.path.len == 0 or !marked) null else options;
}
