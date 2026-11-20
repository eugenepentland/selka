//! `selka rename`: rename one declaration and every use the checker resolves to it, across a project, all or nothing.
//!
//! The project is what `selka fix` visits for the same argument: one entry's program, or every `.selka` file under a
//! directory, programs and tests included (`fix_command.entriesOf`). The command
//!
//! 1. reads the target (`rename_target.zig`, decision D-FR3-1) and the old name it spells;
//! 2. finds the files that hold the old name as code, and checks, in order, the entries whose programs load them, until
//!    every such file has been checked once; each check resolves every token spelled the old name (`rename_uses.zig`);
//! 3. refuses when any such token is left unresolved, when the new name is taken, would shadow or be shadowed, is a
//!    reserved word, or when a use lies outside the project;
//! 4. applies the edits to a copy in memory, checks the same entries again over that copy, and writes the files only when
//!    every check has the same verdict as before: the same diagnostics by code, severity and position, a renamed token's
//!    position read back through the edits.
//!
//! It runs no other process. String literals, comments and data files are never edited; the old name's whole-word
//! mentions there are counted and the first few printed.
const std = @import("std");
const product = @import("compiler_root").compiler_language.product;
const rename_revealed = @import("rename_revealed.zig");
const rename_wire = @import("rename_wire.zig");
const language = @import("selka");
const selka_core = @import("selka_core");
const frontend = selka_core.frontend;
const project_entry = selka_core.project_entry;
const uses = language.rename_uses;
const grammar = language.rename_target;
const ast = language.ast;
const source = language.source;
const lexer = language.lexer;
const diagnostic = language.diagnostic;

const usage =
    \\usage: selka rename [--dry-run] [--json] <entry.selka|directory> <target> <new-name>
    \\  target: module::name             a function, constant, record, enum, union, domain, alias or constraint
    \\          module::Type.member      a record field, or an enum case or union variant
    \\          module::Type.Case.field  a named field of a case
    \\          FILE:LINE:COLUMN         the declaration of the name at that position, or of the use there (parameters, locals)
    \\
;
/// Largest source file read, the loader's own ceiling.
const file_limit = 16 * 1024 * 1024;
/// The verdict refusal's opening words.
const same_check = "the renamed project does not check as before";
/// Places a refusal or a mention list prints before it says how many more there are.
const shown = 8;

/// Parsed command line.
const Options = struct {
    path: []const u8 = "",
    target: []const u8 = "",
    name: []const u8 = "",
    dry_run: bool = false,
    json: bool = false,
};

/// A place in a file: an absolute path and a byte range of that file's own bytes.
const Place = struct { path: []const u8, start: usize, end: usize };

/// A declaration's identity across the checks of several entries: its file and the offset of its name.
const Key = struct { path: []const u8, start: usize };

/// What a resolved token means, in file coordinates.
const Meaning = union(enum) {
    declaration: Key,
    shorthand: struct { field: Key, local: Key },
    other,
    ambiguous,
};

/// One resolved token of the old or new spelling, and what it declares when it is a declaration.
/// `hides` marks a local declared under a name that is a module-level name or an import alias of its module: a binding
/// `E_SHADOWING` refuses (D-FR18-2).
const Token = struct { place: Place, meaning: Meaning, pair: ?Place = null, declares: uses.Declares = .none, hides: bool = false };

/// The kind of thing the target is, which decides where its new name could clash.
const Kind = enum { module_level, field, case, local };

/// The declaration being renamed, and the declarations of the new name it would clash with: another module-level name of
/// its module, or a sibling field or case of its type.
/// `also` holds the other bindings a `hiding:NAME` rename renames with `key` (D-FR18-1).
const Target = struct { key: Key, kind: Kind, label: []const u8, flags: Flags = .{}, clashes: []const Place = &.{}, reach: Reach = .public, also: []const Key = &.{} };

/// Whether `key` is the target's declaration or one of the bindings renamed with it.
fn isTarget(target: Target, key: Key) bool {
    if (keyEql(key, target.key)) return true;
    for (target.also) |other| if (keyEql(key, other)) return true;
    return false;
}

/// Where uses of a target can be: its own file (a local), its module and the test files that import it (a private
/// declaration), or every module that imports its module (a public one).
const Reach = enum { file, private, public };

/// What makes a target one the command will not rename.
const Flags = struct { extern_c: bool = false, standard: bool = false };

/// One diagnostic of a verdict, positioned in the bytes the check read. `declared` is where the declaration an
/// `E_SHADOWING` refusal says its binding would hide is (the refusal's `declared here` note), when it names one.
const Finding = struct { code: []const u8, severity: []const u8, path: []const u8, start: usize, message: []const u8 = "", declared: ?Key = null };

/// One entry's check: its verdict and where it was checked from.
const Checked = struct { entry: []const u8, findings: []Finding, lines: []const []const u8 };

/// An entry whose program did not load: the reason, and the files it reached before it stopped.
const Unloaded = struct { entry: []const u8, problem: []const u8, paths: []const []const u8 };

/// A token of the old name the rename did not follow, and why.
const Unfollowed = struct { place: Place, entry: []const u8, problem: []const u8 };

/// A local's visibility in file coordinates.
const Visible = struct { declaration: Key, function: Key, end: usize };

/// Everything one invocation gathers.
const Run = struct {
    allocator: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    options: Options,
    old: []const u8 = "",
    state: State = .{},
    context: Context = .{},
};

/// What a run keeps across the checks of its phases.
const Context = struct {
    /// The file that declares the target, and for a qualified spelling the member path after its module's name.
    declared: Declared = .{},
    /// The renamed copy the second phase of a shadowing repair reads instead of the disk, by absolute path (D-FR18-2).
    overlay: std.array_hash_map.String([]const u8) = .empty,
    /// In that phase, the name the repaired bindings hid, whose tokens must all still resolve; empty otherwise.
    hidden: []const u8 = "",
    /// In that phase, the bindings being renamed, in the copy's coordinates, for the checks to find the target.
    wanted: []const Key = &.{},
};

/// Where a qualified target is declared.
const Declared = struct { path: []const u8 = "", member: []const u8 = "" };

/// Resolved tokens by place.
const Tokens = std.array_hash_map.Auto(u64, Token);

/// What the checks found, merged over entries.
const State = struct {
    /// Every resolved token of the old name, and of the new name (declarations a rename could collide with), by place.
    /// In the second phase of a shadowing repair, `hidden` holds the tokens of the name the bindings hid.
    tokens: struct { old: Tokens = .empty, new: Tokens = .empty, hidden: Tokens = .empty } = .{},
    /// Locals declared under either name.
    locals: std.ArrayList(Visible) = .empty,
    /// The files under the project that hold the old name as code, and every token of it there.
    candidates: std.ArrayList(Place) = .empty,
    /// The verdicts before the rename, one per checked entry.
    before: std.ArrayList(Checked) = .empty,
    target: ?Target = null,
    /// The entries whose programs did not load, which the rename cannot follow, and every file a program that did load reached.
    /// The modules every loaded graph holds, by file, with what each imports.
    reach: struct {
        unloaded: std.ArrayList(Unloaded) = .empty,
        loaded: std.StringHashMapUnmanaged(void) = .empty,
        modules: std.array_hash_map.String(ModuleInfo) = .empty,
        /// Every name a file has as a module of some root (one file can be `shared.units` from one root and `units` from
        /// its own directory).
        named: std.ArrayList(struct { name: []const u8, path: []const u8 }) = .empty,
        /// Each path as given, with its links resolved.
        real: std.StringHashMapUnmanaged([]const u8) = .empty,
    } = .{},
    /// Whether every check had a checked tree, which a field or a pattern case needs.
    unchecked: std.ArrayList([]const u8) = .empty,
};

/// Run `selka rename` with the arguments after the command name: 0 when the rename is done (or, with `--dry-run`,
/// computed), 1 when it is refused, 2 on a usage or host failure.
pub fn run(process: std.process.Init, args: []const []const u8) u8 {
    return runCommand(process, args) catch |err| {
        var buffer: [192]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "selka rename: {s}\n", .{@errorName(err)}) catch "selka rename: host failure\n";
        std.Io.File.stderr().writeStreamingAll(process.io, message) catch return 2;
        return 2;
    };
}

fn runCommand(process: std.process.Init, args: []const []const u8) !u8 {
    const options = parse(args) orelse {
        try std.Io.File.stderr().writeStreamingAll(process.io, usage);
        return 2;
    };
    const allocator = process.arena.allocator();
    var session: Run = .{ .allocator = allocator, .gpa = process.gpa, .io = process.io, .options = options };
    if (grammar.checkName(options.name)) |problem| switch (problem) {
        .not_identifier => {
            try std.Io.File.stderr().writeStreamingAll(process.io, "selka rename: the new name must be one plain name (letters, digits and `_`)\n");
            return 2;
        },
        .reserved_word => return refuseWith(&session, "reserved", "`{s}` is a reserved word, so no declaration can take it", .{options.name}, &.{}),
    };
    const spelling = grammar.parse(options.target) orelse {
        try std.Io.File.stderr().writeStreamingAll(process.io, "selka rename: the target is neither `module::name` nor `FILE:LINE:COLUMN`\n");
        try std.Io.File.stderr().writeStreamingAll(process.io, usage);
        return 2;
    };
    const root = std.Io.Dir.cwd().realPathFileAlloc(process.io, options.path, allocator) catch {
        try std.Io.File.stderr().writeStreamingAll(process.io, try std.fmt.allocPrint(allocator, "selka rename: {s}: no such file or directory\n", .{options.path}));
        return 2;
    };
    const entries = try @import("fix_command.zig").projectEntries(process, root) orelse {
        try std.Io.File.stderr().writeStreamingAll(process.io, try std.fmt.allocPrint(allocator, "selka rename: {s} is neither a .selka entry nor a directory\n", .{options.path}));
        return 2;
    };
    session.old = switch (spelling) {
        .qualified => |qualified| grammar.lastName(qualified),
        .position => |at| (try nameAt(&session, at)) orelse {
            try std.Io.File.stderr().writeStreamingAll(process.io, try std.fmt.allocPrint(allocator, "selka rename: {s}: no name at that position\n", .{options.target}));
            return 2;
        },
        .hiding => |name| name,
    };
    if (std.mem.eql(u8, session.old, options.name)) {
        try std.Io.File.stderr().writeStreamingAll(process.io, "selka rename: the new name is the old one\n");
        return 2;
    }
    const scope = projectScope(root, entries);
    const graphs = try loadGraphs(&session, entries);
    if (spelling == .hiding) return repairHiding(&session, graphs, scope);
    // Check the first program that loads the declaring file, which finds the target and its kind.
    session.context.declared = (try declaringFile(&session, spelling)) orelse return refuse(&session, "missing", try missingMessage(&session, spelling), &.{});
    const declaring = session.context.declared.path;
    const first = graphLoading(graphs, declaring) orelse return refuseWith(&session, "missing", "no program under {s} loads {s}", .{ options.path, try shortPath(&session, declaring) }, &.{});
    try checkEntry(&session, first.path, spelling);
    const target = session.state.target orelse return refuse(&session, "missing", try missingMessage(&session, spelling), &.{});
    // Then the programs that load the other files a use can be in.
    const relevant = try relevantFiles(&session, target);
    for (try cover(&session, graphs, relevant, first.path)) |entry| try checkEntry(&session, entry, spelling);
    if (target.flags.standard) return refuseWith(&session, "outside", "{s} is declared in the standard library, which is not part of the project", .{target.label}, &.{});
    if (target.flags.extern_c) return refuseWith(&session, "extern", "{s} is an `extern func`: its name is the C function's, which the linked C source defines; rename it there and here by hand", .{target.label}, &.{});
    if (!under(scope, target.key.path)) return refuseWith(&session, "outside", "{s} is declared in {s}, outside {s}", .{ target.label, target.key.path, options.path }, &.{});
    // A binding `E_SHADOWING` refuses: the project does not check, so the rename is proven over a copy (D-FR18-2).
    if (hidingBinding(&session, target)) return repair(&session, scope, &.{target.key}, target.label);
    // Every token spelled the old name in the project must have been resolved.
    var edits: std.ArrayList(Edit) = .empty;
    var unresolved: std.ArrayList(Place) = .empty;
    var outside: std.ArrayList(Place) = .empty;
    var unfollowed: std.ArrayList(Unfollowed) = .empty;
    for (session.state.candidates.items) |place| {
        const token = session.state.tokens.old.get(placeKey(place)) orelse {
            if (unloadedReach(&session, place.path)) |unloaded| {
                try unfollowed.append(allocator, .{ .place = place, .entry = unloaded.entry, .problem = unloaded.problem });
            } else try unresolved.append(allocator, place);
            continue;
        };
        switch (token.meaning) {
            .ambiguous => try unresolved.append(allocator, place),
            .other => {},
            .declaration => |key| if (keyEql(key, target.key)) {
                if (!under(scope, place.path)) try outside.append(allocator, place) else try edits.append(allocator, try editFor(&session, token, .plain));
            },
            .shorthand => |pair| {
                if (keyEql(pair.field, target.key)) try edits.append(allocator, try editFor(&session, token, .shorthand_field));
                if (keyEql(pair.local, target.key)) try edits.append(allocator, try editFor(&session, token, .shorthand_local));
            },
        }
    }
    if (unresolved.items.len != 0) {
        const count = unresolved.items.len;
        const unproven = "{d} use{s} of `{s}` could not be resolved to a declaration, so the rename cannot prove it renames every use of {s}{s}";
        // A program whose bodies do not check has no checked tree: a field or a case there resolves only through a declared type.
        const why = if (session.state.unchecked.items.len != 0) " (a program that loads them does not check, so their types are not known)" else "";
        return refuseWith(&session, "unresolved", unproven, .{ count, plural(count), session.old, target.label, why }, unresolved.items);
    }
    if (outside.items.len != 0) return refuseWith(&session, "outside", "{d} use{s} of {s} lie outside {s}, where nothing is renamed", .{ outside.items.len, plural(outside.items.len), target.label, options.path }, outside.items);
    if (try clash(&session, target)) |status| return status;
    try collapsePairs(&session, edits.items);
    const files = try applyEdits(&session, edits.items);
    // A name that `E_SHADOWING` refuses bindings for hiding: the rename cures those refusals (F-79).
    const hiding = try hidingTarget(&session, target);
    if (hiding.len != 0) return renameCuring(&session, target, files, hiding, .{ .scope = scope, .unfollowed = unfollowed.items });
    // The same checks over the renamed copy.
    for (session.state.before.items) |before| {
        const after = try checkAfter(&session, before.entry, files);
        if (try compareVerdicts(&session, before, after, files, same_check)) |status| return status;
    }
    if (!options.dry_run) try writeFiles(&session, files);
    try report(&session, target, files, .{ .scope = scope, .unfollowed = unfollowed.items });
    return 0;
}

/// Whether the target is a local or parameter whose name is a module-level name or an import alias of its module: a
/// binding `E_SHADOWING` refuses.
fn hidingBinding(run_: *Run, target: Target) bool {
    if (target.kind != .local) return false;
    const token = run_.state.tokens.old.get(keyHash(target.key.path, target.key.start)) orelse return false;
    return token.hides;
}

/// The entry that did not load and reached `path`, when no entry that loaded reached it.
fn unloadedReach(run_: *Run, path: []const u8) ?Unloaded {
    if (run_.state.reach.loaded.contains(path)) return null;
    for (run_.state.reach.unloaded.items) |unloaded| for (unloaded.paths) |reached| {
        if (std.mem.eql(u8, reached, path)) return unloaded;
    };
    return null;
}

fn plural(count: usize) []const u8 {
    return if (count == 1) "" else "s";
}

fn parse(args: []const []const u8) ?Options {
    var options: Options = .{};
    var positional: usize = 0;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--dry-run")) {
            if (options.dry_run) return null;
            options.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            if (options.json) return null;
            options.json = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return null;
        } else {
            switch (positional) {
                0 => options.path = arg,
                1 => options.target = arg,
                2 => options.name = arg,
                else => return null,
            }
            positional += 1;
        }
    }
    return if (positional == 3) options else null;
}

// ---- The project and its entries ---------------------------------------------------------------------------------------

/// The directory a path must lie under to be part of the project: the directory named, or the entry's own directory.
fn projectScope(root: []const u8, entries: []const []const u8) []const u8 {
    if (entries.len == 1 and std.mem.eql(u8, entries[0], root)) return std.fs.path.dirname(root) orelse root;
    return root;
}

fn under(scope: []const u8, path: []const u8) bool {
    if (!std.mem.startsWith(u8, path, scope)) return false;
    return path.len == scope.len or path[scope.len] == '/';
}

/// The identifier at a one-based position of a file, or null when there is none.
fn nameAt(run_: *Run, at: grammar.Position) !?[]const u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(run_.io, at.path, run_.allocator, .limited(file_limit)) catch return null;
    const offset = offsetOf(bytes, at.line, at.column) orelse return null;
    if (offset >= bytes.len or !identifierByte(bytes[offset])) return null;
    var start = offset;
    while (start > 0 and identifierByte(bytes[start - 1])) start -= 1;
    var end = offset;
    while (end < bytes.len and identifierByte(bytes[end])) end += 1;
    // A reserved word names nothing.
    if (!lexer.isIdentifier(bytes[start..end])) return null;
    return bytes[start..end];
}

fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// The byte offset of a one-based line and column (columns count bytes, as diagnostics print them).
fn offsetOf(bytes: []const u8, line: usize, column: usize) ?usize {
    var current: usize = 1;
    var start: usize = 0;
    while (current < line) {
        const newline = std.mem.indexOfScalarPos(u8, bytes, start, '\n') orelse return null;
        start = newline + 1;
        current += 1;
    }
    const offset = start + column - 1;
    const line_end = std.mem.indexOfScalarPos(u8, bytes, start, '\n') orelse bytes.len;
    return if (offset < line_end) offset else null;
}

/// One entry's resolved project settings, the absolute paths of the modules its program loads, and why it did not load
/// when it did not (an import of a package the program locks, which a plain check cannot find).
const Graph = struct { path: []const u8, paths: []const []const u8, problem: ?[]const u8 = null };

/// One module of the project as the loaded graphs show it: its name and the files of the modules it imports.
const ModuleInfo = struct { name: []const u8, imports: []const []const u8 };

/// Load an entry's module graph without parsing a body.
fn loadGraph(run_: *Run, entry_path: []const u8) !?Graph {
    var report_: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(run_.allocator, run_.io, entry_path, &report_) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    var session = frontend.Session.init(run_.gpa, run_.io, entry.root);
    defer session.deinit();
    entry.configure(&session);
    var problem: ?[]const u8 = null;
    session.loadModules(run_.allocator, entry.name) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const rendered = session.project.renderProblem(run_.allocator) catch "";
            const first = std.mem.sliceTo(rendered, '\n');
            problem = if (first.len != 0) first else @errorName(err);
        },
    };
    const modules = session.project.modules.items;
    var paths: std.ArrayList([]const u8) = .empty;
    for (modules) |module| {
        // A standard module is the compiler's own, never a file of the project.
        if (std.mem.startsWith(u8, module.src.path, "@")) continue;
        const absolute = try absolutePath(run_, entry.root, module.src.path);
        try paths.append(run_.allocator, absolute);
    }
    if (paths.items.len == 0) try paths.append(run_.allocator, entry_path);
    if (problem == null) for (modules) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@")) continue;
        const absolute = try absolutePath(run_, entry.root, module.src.path);
        try run_.state.reach.named.append(run_.allocator, .{ .name = try run_.allocator.dupe(u8, module.name), .path = absolute });
        const slot = try run_.state.reach.modules.getOrPut(run_.allocator, absolute);
        if (slot.found_existing) continue;
        var imports: std.ArrayList([]const u8) = .empty;
        for (module.imports) |imported| {
            if (imported.target >= modules.len) continue;
            const target = modules[imported.target];
            if (std.mem.startsWith(u8, target.src.path, "@")) continue;
            try imports.append(run_.allocator, try absolutePath(run_, entry.root, target.src.path));
        }
        slot.value_ptr.* = .{ .name = try run_.allocator.dupe(u8, module.name), .imports = imports.items };
    };
    return .{ .path = entry_path, .paths = paths.items, .problem = problem };
}

/// A module's file as one absolute path with every symbolic link resolved, so a file reached under two names (a link
/// beside its target) is one file.
fn absolutePath(run_: *Run, root: []const u8, path: []const u8) ![]const u8 {
    const lexical = if (std.fs.path.isAbsolute(path)) try run_.allocator.dupe(u8, path) else try std.fs.path.resolve(run_.allocator, &.{ root, path });
    const slot = try run_.state.reach.real.getOrPut(run_.allocator, lexical);
    if (!slot.found_existing) slot.value_ptr.* = std.Io.Dir.cwd().realPathFileAlloc(run_.io, lexical, run_.allocator) catch lexical;
    return slot.value_ptr.*;
}

/// Load every entry's graph, in `fix`'s order, without parsing a body. The entries that share a project root are loaded
/// together, as the imports of one generated module, so a module many programs import is read once; when that load
/// fails, each entry of the root is loaded alone. A program that does not load (it imports a package it locks, which a
/// plain check cannot find) is kept aside: its files are not followed, and the report says so.
fn loadGraphs(run_: *Run, entries: []const []const u8) ![]const Graph {
    var roots: std.array_hash_map.String(std.ArrayList(Pending)) = .empty;
    for (entries) |entry_path| {
        var report_: std.ArrayList(u8) = .empty;
        const entry = project_entry.resolve(run_.allocator, run_.io, entry_path, &report_) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        const slot = try roots.getOrPut(run_.allocator, entry.root);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(run_.allocator, .{ .path = entry_path, .entry = entry });
    }
    var by_entry: std.StringHashMapUnmanaged(Graph) = .empty;
    for (roots.values()) |group| {
        if (try loadTogether(run_, group.items, &by_entry)) continue;
        for (group.items) |pending| {
            const graph = (try loadGraph(run_, pending.path)) orelse continue;
            try by_entry.put(run_.allocator, pending.path, graph);
        }
    }
    var graphs: std.ArrayList(Graph) = .empty;
    for (entries) |entry_path| {
        const graph = by_entry.get(entry_path) orelse continue;
        if (graph.problem) |problem| {
            try run_.state.reach.unloaded.append(run_.allocator, .{ .entry = entry_path, .problem = problem, .paths = graph.paths });
            continue;
        }
        for (graph.paths) |path| try run_.state.reach.loaded.put(run_.allocator, path, {});
        try graphs.append(run_.allocator, graph);
    }
    return graphs.items;
}

/// An entry waiting to be loaded, with its resolved project settings.
const Pending = struct { path: []const u8, entry: project_entry.Entry };

/// The name of the module that imports every entry of a root.
const together_name = "rename_entries_of_this_root";

/// Load the entries of one root as the imports of one generated module, and give each its graph: the files its own
/// imports reach. False when the load fails, or two entries of the root are configured differently.
fn loadTogether(run_: *Run, group: []const Pending, by_entry: *std.StringHashMapUnmanaged(Graph)) !bool {
    if (group.len < 2) return false;
    var text: std.ArrayList(u8) = .empty;
    for (group, 0..) |pending, position| {
        if (!std.mem.eql(u8, pending.entry.name, group[0].entry.name) and !sameConfiguration(pending.entry, group[0].entry)) return false;
        try text.print(run_.allocator, "import {s} as rename_entry_{d}\n", .{ pending.entry.name, position });
    }
    const root = group[0].entry.root;
    var session = frontend.Session.init(run_.gpa, run_.io, root);
    defer session.deinit();
    group[0].entry.configure(&session);
    var options = group[0].entry.limits();
    // The budgets bound one program; the generated module holds every program of the root.
    options.max_modules = std.math.maxInt(usize);
    options.max_total_bytes = std.math.maxInt(usize);
    session.configureProject(options, together_name);
    const relative = try std.fmt.allocPrint(run_.allocator, "{s}.selka", .{together_name});
    session.setProviders(&.{.{ .path = relative, .text = text.items }});
    session.loadModules(run_.allocator, together_name) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return false,
    };
    const modules = session.project.modules.items;
    var paths = try run_.allocator.alloc(?[]const u8, modules.len);
    for (modules, 0..) |module, position| {
        paths[position] = null;
        if (std.mem.startsWith(u8, module.src.path, "@") or position == 0) continue;
        paths[position] = try absolutePath(run_, root, module.src.path);
    }
    for (modules, 0..) |module, position| {
        const path = paths[position] orelse continue;
        try run_.state.reach.named.append(run_.allocator, .{ .name = try run_.allocator.dupe(u8, module.name), .path = path });
        const slot = try run_.state.reach.modules.getOrPut(run_.allocator, path);
        if (slot.found_existing) continue;
        var imports: std.ArrayList([]const u8) = .empty;
        for (module.imports) |imported| if (paths[imported.target]) |target| try imports.append(run_.allocator, target);
        slot.value_ptr.* = .{ .name = try run_.allocator.dupe(u8, module.name), .imports = imports.items };
    }
    // Each entry's graph is the closure of its own module over the imports.
    for (modules[0].imports, group) |imported, pending| {
        var seen = try run_.allocator.alloc(bool, modules.len);
        @memset(seen, false);
        var stack: std.ArrayList(usize) = .empty;
        var reached: std.ArrayList([]const u8) = .empty;
        try stack.append(run_.allocator, imported.target);
        seen[imported.target] = true;
        while (stack.pop()) |at| {
            if (paths[at]) |path| try reached.append(run_.allocator, path);
            for (modules[at].imports) |next| if (!seen[next.target]) {
                seen[next.target] = true;
                try stack.append(run_.allocator, next.target);
            };
        }
        try by_entry.put(run_.allocator, pending.path, .{ .path = pending.path, .paths = reached.items });
    }
    return true;
}

/// Whether two entries of one root load modules under the same settings.
fn sameConfiguration(left: project_entry.Entry, right: project_entry.Entry) bool {
    const a = left.configuration orelse return right.configuration == null;
    const b = right.configuration orelse return false;
    return std.mem.eql(u8, a.path, b.path);
}

/// The file that declares the target: the position's file, or the file of the module a qualified spelling names (the
/// first one in entry order, when two programs under the directory have a module of that name).
fn declaringFile(run_: *Run, spelling: grammar.Spelling) !?Declared {
    switch (spelling) {
        .position => |at| return .{ .path = std.Io.Dir.cwd().realPathFileAlloc(run_.io, at.path, run_.allocator) catch return null },
        .hiding => return null,
        .qualified => |qualified| {
            const named = run_.state.reach.named.items;
            if (std.mem.indexOf(u8, qualified, "::")) |split| {
                for (named) |item| if (std.mem.eql(u8, item.name, qualified[0..split])) return .{ .path = item.path, .member = qualified[split + 2 ..] };
                return null;
            }
            var cursor = qualified.len;
            while (std.mem.lastIndexOfScalar(u8, qualified[0..cursor], '.')) |dot| {
                cursor = dot;
                for (named) |item| if (std.mem.eql(u8, item.name, qualified[0..dot])) return .{ .path = item.path, .member = qualified[dot + 1 ..] };
            }
            return null;
        },
    }
}

/// The smallest graph that loads `path` (the file's own, when it is an entry): the cheapest check that sees it.
fn graphLoading(graphs: []const Graph, path: []const u8) ?Graph {
    var best: ?Graph = null;
    for (graphs) |graph| for (graph.paths) |loaded| {
        if (!std.mem.eql(u8, loaded, path)) continue;
        if (best == null or graph.paths.len < best.?.paths.len) best = graph;
        break;
    };
    return best;
}

/// The files a use of the target can be in. A local is used only in its own file. A private declaration (and a parameter
/// of a private function, whose callers may name it) is reachable from its module and the test files that import it. A
/// public one is reachable from every module that imports its module, directly or through others (a field of a value
/// reaches a module only through calls into modules that import the type's).
fn relevantFiles(run_: *Run, target: Target) ![]const []const u8 {
    var files: std.ArrayList([]const u8) = .empty;
    try files.append(run_.allocator, target.key.path);
    if (target.reach == .file) return files.items;
    const modules = &run_.state.reach.modules;
    var included: std.StringHashMapUnmanaged(void) = .empty;
    try included.put(run_.allocator, target.key.path, {});
    var changed = true;
    while (changed) {
        changed = false;
        for (modules.keys(), modules.values()) |path, module| {
            if (included.contains(path)) continue;
            const imports_one = for (module.imports) |imported| {
                if (included.contains(imported)) break true;
            } else false;
            if (!imports_one) continue;
            if (target.reach == .private) {
                // Only a test file reaches its module's private declarations, and only directly.
                const direct = for (module.imports) |imported| {
                    if (std.mem.eql(u8, imported, target.key.path)) break true;
                } else false;
                if (!direct or !product.isTestSource(path)) continue;
            }
            try included.put(run_.allocator, path, {});
            try files.append(run_.allocator, path);
            changed = true;
        }
    }
    // A program that does not load may use a public name too: its files that hold the name are listed as not followed.
    if (target.reach == .public) for (run_.state.reach.unloaded.items) |unloaded| for (unloaded.paths) |path| {
        if (included.contains(path) or run_.state.reach.loaded.contains(path)) continue;
        try included.put(run_.allocator, path, {});
        try files.append(run_.allocator, path);
    };
    return files.items;
}

fn smallerGraph(_: void, left: Graph, right: Graph) bool {
    return left.paths.len < right.paths.len;
}

/// The graphs to check so that every relevant file that holds the old name is loaded by one: in order, each graph that
/// loads such a file no graph before it loaded, smallest first. `checked` is the entry already checked.
fn cover(run_: *Run, graphs: []const Graph, files: []const []const u8, checked: []const u8) ![]const []const u8 {
    var wanted: std.StringHashMapUnmanaged(void) = .empty;
    for (files) |path| if (try holdsName(run_, path)) try wanted.put(run_.allocator, path, {});
    var covered: std.StringHashMapUnmanaged(void) = .empty;
    for (graphs) |graph| if (std.mem.eql(u8, graph.path, checked)) for (graph.paths) |path| try covered.put(run_.allocator, path, {});
    // Smallest programs first: a module checked as its own entry has every body checked, and the fewest other files.
    const ordered = try run_.allocator.dupe(Graph, graphs);
    std.mem.sort(Graph, ordered, {}, smallerGraph);
    var selected: std.ArrayList([]const u8) = .empty;
    for (ordered) |graph| {
        if (std.mem.eql(u8, graph.path, checked)) continue;
        const needed = for (graph.paths) |path| {
            if (wanted.contains(path) and !covered.contains(path)) break true;
        } else false;
        if (!needed) continue;
        try selected.append(run_.allocator, graph.path);
        for (graph.paths) |path| try covered.put(run_.allocator, path, {});
    }
    return selected.items;
}

/// Whether a file holds the old name as code, and if so record each such token as a candidate.
fn holdsName(run_: *Run, path: []const u8) !bool {
    const bytes = readFile(run_, path) catch return false;
    if (std.mem.indexOf(u8, bytes, run_.old) == null) return false;
    const scan = try scanFile(run_, bytes);
    const filter = candidateFilter(run_, path);
    var any = false;
    for (scan.code.items) |start| {
        if (!filter.admits(bytes, start, run_.old.len)) continue;
        try run_.state.candidates.append(run_.allocator, .{ .path = path, .start = start, .end = start + run_.old.len });
        any = true;
    }
    return any;
}

fn candidateFilter(run_: *Run, path: []const u8) grammar.Filter {
    const target = run_.state.target orelse return .all;
    if (std.mem.eql(u8, path, target.key.path)) return .all;
    // Bindings renamed together are declared in their own files too.
    for (target.also) |key| if (std.mem.eql(u8, path, key.path)) return .all;
    return switch (target.kind) {
        .module_level => .qualified,
        .local => .labels,
        .field, .case => .members,
    };
}

/// Where a name occurs in one file: as code (a token, or a name inside an f-string's hole), in a string, in a comment.
const Scan = struct { code: std.ArrayList(usize) = .empty, strings: std.ArrayList(usize) = .empty, comments: std.ArrayList(usize) = .empty };

fn scanFile(run_: *Run, bytes: []const u8) !Scan {
    return scanName(run_, bytes, run_.old);
}

/// `scanFile` for any name.
fn scanName(run_: *Run, bytes: []const u8, name: []const u8) !Scan {
    var result: Scan = .{};
    var sink: diagnostic.Sink = .{ .allocator = run_.allocator };
    const tokens = lexer.lex(run_.allocator, bytes, &sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => &.{},
    };
    var position: usize = 0;
    var token: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, position, name)) |found| {
        position = found + 1;
        const end = found + name.len;
        if (found > 0 and identifierByte(bytes[found - 1])) continue;
        if (end < bytes.len and identifierByte(bytes[end])) continue;
        while (token < tokens.len and tokens[token].span.end <= found) token += 1;
        if (token < tokens.len and tokens[token].span.start <= found) {
            const covering = tokens[token];
            switch (covering.tag) {
                .bytes => try result.strings.append(run_.allocator, found),
                .format => if (inHole(bytes[covering.span.start..covering.span.end], found - covering.span.start))
                    try result.code.append(run_.allocator, found)
                else
                    try result.strings.append(run_.allocator, found),
                else => if (covering.span.start == found and covering.span.end == end) try result.code.append(run_.allocator, found),
            }
        } else try result.comments.append(run_.allocator, found);
    }
    return result;
}

/// Whether `offset` of an f-string token's text lies inside an interpolation hole, `{...}`.
fn inHole(literal: []const u8, offset: usize) bool {
    var depth: usize = 0;
    var index: usize = 0;
    while (index < literal.len and index < offset) : (index += 1) {
        const byte = literal[index];
        if (depth == 0) {
            if (byte == '{') {
                if (index + 1 < literal.len and literal[index + 1] == '{') {
                    index += 1;
                    continue;
                }
                depth = 1;
            }
        } else if (byte == '{') {
            depth += 1;
        } else if (byte == '}') {
            depth -= 1;
        }
    }
    return depth > 0;
}

// ---- Checking an entry -------------------------------------------------------------------------------------------------

fn placeKey(place: Place) u64 {
    return keyHash(place.path, place.start);
}

fn keyHash(path: []const u8, start: usize) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(path);
    hasher.update(std.mem.asBytes(&start));
    return hasher.final();
}

fn keyEql(left: Key, right: Key) bool {
    return left.start == right.start and std.mem.eql(u8, left.path, right.path);
}

/// Check one entry, over the files on disk (`overlay` null) or over the renamed copy, and return its verdict; the first
/// time, also resolve both names and find the target.
fn checkEntry(run_: *Run, entry_path: []const u8, spelling: ?grammar.Spelling) !void {
    var scratch = std.heap.ArenaAllocator.init(run_.gpa);
    defer scratch.deinit();
    const arena = scratch.allocator();
    var report_: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(run_.allocator, run_.io, entry_path, &report_) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try run_.state.before.append(run_.allocator, .{ .entry = entry_path, .findings = &.{}, .lines = try splitLines(run_, report_.items) });
            return;
        },
    };
    var session = frontend.Session.init(run_.gpa, run_.io, entry.root);
    defer session.deinit();
    // The second phase of a shadowing repair checks the copy with the bindings renamed.
    if (run_.context.overlay.count() != 0) session.setProviders(try overlayProviders(run_, entry.root, run_.context.overlay.keys(), run_.context.overlay.values()));
    const compilation = try checkSession(run_, arena, &session, entry, &report_);
    try run_.state.before.append(run_.allocator, try verdict(run_, entry_path, entry.root, report_.items));
    const merged = compilation orelse {
        try run_.state.unchecked.append(run_.allocator, entry_path);
        return;
    };
    try resolveNames(run_, arena, entry.root, merged);
    if (run_.state.target != null) return;
    if (spelling) |given| {
        run_.state.target = try findTarget(run_, entry.root, merged, given);
    } else if (run_.context.wanted.len != 0) {
        if (try describe(run_, entry.root, merged, run_.context.wanted[0])) |found| {
            var target = found;
            target.also = run_.context.wanted[1..];
            run_.state.target = target;
        }
    }
}

/// The providers that overlay `texts` on the files at `paths` (absolute) for a session rooted at `root`, under every name
/// the loader may read each by (a link beside its target, D-FR3-10).
fn overlayProviders(run_: *Run, root: []const u8, paths: []const []const u8, texts: []const []const u8) ![]const frontend.Provider {
    var overlays: std.ArrayList(frontend.Provider) = .empty;
    for (paths, texts) |path, text| {
        var names = run_.state.reach.real.iterator();
        while (names.next()) |item| {
            if (!std.mem.eql(u8, item.value_ptr.*, path)) continue;
            const relative = try std.fs.path.relative(run_.allocator, root, null, root, item.key_ptr.*);
            try overlays.append(run_.allocator, .{ .path = relative, .text = text });
        }
        const relative = try std.fs.path.relative(run_.allocator, root, null, root, path);
        try overlays.append(run_.allocator, .{ .path = relative, .text = text });
    }
    return overlays.items;
}

/// Check an entry in `session` as `selka check` does, rendering diagnostics as `diagnostic-v1` lines into `report_`;
/// the merged program when the graph loaded and merged (its bodies checked or not).
fn checkSession(run_: *Run, arena: std.mem.Allocator, session: *frontend.Session, entry: project_entry.Entry, report_: *std.ArrayList(u8)) !?*language.project_compile.Compilation {
    _ = run_;
    session.setHoleTraps(false);
    session.setFormat(.json);
    session.setReportFormat(.json);
    entry.configure(session);
    session.declare(arena, entry.name, report_) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    session.mergeDeclared(arena, report_) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    const compilation = session.mergedProgram();
    const library = !compilation.declaresMain();
    const outcome = if (library) session.checkLibraryMerged(arena, null, report_) else session.checkMerged(arena, report_);
    if (outcome) |_| {
        report_.appendSlice(arena, try session.warnings(arena)) catch return error.OutOfMemory;
    } else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {},
    }
    entry.validate(arena, session, report_) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {},
    };
    return compilation;
}

fn splitLines(run_: *Run, text: []const u8) ![]const []const u8 {
    var lines: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, text, '\n');
    while (iterator.next()) |line| if (line.len != 0) try lines.append(run_.allocator, try run_.allocator.dupe(u8, line));
    return lines.items;
}

fn verdict(run_: *Run, entry_path: []const u8, root: []const u8, text: []const u8) !Checked {
    var findings: std.ArrayList(Finding) = .empty;
    var other: std.ArrayList([]const u8) = .empty;
    var iterator = std.mem.splitScalar(u8, text, '\n');
    while (iterator.next()) |line| {
        if (line.len == 0) continue;
        const parsed = std.json.parseFromSliceLeaky(rename_wire.Wire, run_.allocator, line, .{ .ignore_unknown_fields = true }) catch {
            try other.append(run_.allocator, try run_.allocator.dupe(u8, line));
            continue;
        };
        const item = parsed.diagnostic orelse {
            try other.append(run_.allocator, try run_.allocator.dupe(u8, line));
            continue;
        };
        const location = item.location orelse {
            try findings.append(run_.allocator, .{ .code = try run_.allocator.dupe(u8, item.code), .severity = try run_.allocator.dupe(u8, item.severity), .path = "", .start = 0, .message = try run_.allocator.dupe(u8, item.message) });
            continue;
        };
        const start = if (location.bytes) |bytes| bytes.start else 0;
        // The `declared here` note of a shadowing refusal is the declaration its binding would hide.
        var declared: ?Key = null;
        if (std.mem.eql(u8, item.code, diagnostic.shadowing)) if (rename_wire.declaredHere(item.notes)) |spot| {
            declared = .{ .path = try absolutePath(run_, root, spot.path), .start = spot.start };
        };
        try findings.append(run_.allocator, .{
            .code = try run_.allocator.dupe(u8, item.code),
            .severity = try run_.allocator.dupe(u8, item.severity),
            .path = try absolutePath(run_, root, location.path),
            .start = start,
            .message = try run_.allocator.dupe(u8, item.message),
            .declared = declared,
        });
    }
    return .{ .entry = entry_path, .findings = findings.items, .lines = other.items };
}

/// Convert one entry's resolver tables into file coordinates and merge them into the run's state.
fn resolveNames(run_: *Run, arena: std.mem.Allocator, root: []const u8, compilation: *language.project_compile.Compilation) !void {
    for ([_][]const u8{ run_.old, run_.options.name, run_.context.hidden }, 0..) |name, which| {
        if (name.len == 0) continue;
        const table = try uses.resolve(arena, compilation, name);
        if (!table.checked and which == 0) try run_.state.unchecked.append(run_.allocator, root);
        const target_map = switch (which) {
            0 => &run_.state.tokens.old,
            1 => &run_.state.tokens.new,
            else => &run_.state.tokens.hidden,
        };
        for (table.occurrences.values()) |occurrence| {
            const place = try placeOf(run_, root, compilation, occurrence.span);
            const meaning: Meaning = switch (occurrence.meaning) {
                .declaration => |span| .{ .declaration = try keyOf(run_, root, compilation, span) },
                .shorthand => |pair| .{ .shorthand = .{ .field = try keyOf(run_, root, compilation, pair.field), .local = try keyOf(run_, root, compilation, pair.local) } },
                .other => .other,
                .ambiguous => .ambiguous,
            };
            const pair: ?Place = if (occurrence.pair) |span| try placeOf(run_, root, compilation, span) else null;
            const slot = try target_map.getOrPut(run_.allocator, placeKey(place));
            if (!slot.found_existing) {
                const hides = occurrence.declares == .local and try hidesInModule(compilation, occurrence.span, name);
                slot.value_ptr.* = .{ .place = place, .meaning = meaning, .pair = pair, .declares = occurrence.declares, .hides = hides };
            } else if (!sameMeaning(slot.value_ptr.meaning, meaning)) slot.value_ptr.meaning = .ambiguous;
        }
        for (table.locals.items) |visible| {
            const declaration = try keyOf(run_, root, compilation, visible.declaration);
            const function = try keyOf(run_, root, compilation, visible.function);
            const original = compilation.src.originalSpan(.{ .start = visible.end, .end = visible.end }) catch continue;
            try run_.state.locals.append(run_.allocator, .{ .declaration = declaration, .function = function, .end = original.span.end });
        }
    }
}

/// Whether `name` is a module-level name or an import alias of the module that writes `span`: what a local of that name
/// would hide, so `E_SHADOWING` refuses it (`module_names.Names.topLevel`).
fn hidesInModule(compilation: *language.project_compile.Compilation, span: source.Span, name: []const u8) !bool {
    const original = compilation.src.originalSpan(span) catch return error.InternalError;
    const module = original.input;
    if (module >= compilation.index.units.len or module >= compilation.index.project.modules.items.len) return false;
    if (compilation.index.units[module].names.contains(name)) return true;
    for (compilation.index.project.modules.items[module].imports) |imported| {
        if (std.mem.eql(u8, imported.alias, name)) return true;
    }
    return false;
}

fn sameMeaning(left: Meaning, right: Meaning) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .declaration => |key| keyEql(key, right.declaration),
        .shorthand => |pair| keyEql(pair.field, right.shorthand.field) and keyEql(pair.local, right.shorthand.local),
        .other, .ambiguous => true,
    };
}

fn placeOf(run_: *Run, root: []const u8, compilation: *language.project_compile.Compilation, span: source.Span) !Place {
    const original = compilation.src.originalSpan(span) catch return error.InternalError;
    const module = compilation.index.project.modules.items[original.input];
    return .{ .path = try absolutePath(run_, root, module.src.path), .start = original.span.start, .end = original.span.end };
}

fn keyOf(run_: *Run, root: []const u8, compilation: *language.project_compile.Compilation, span: source.Span) !Key {
    const place = try placeOf(run_, root, compilation, span);
    return .{ .path = place.path, .start = place.start };
}

// ---- Finding the target ------------------------------------------------------------------------------------------------

fn findTarget(run_: *Run, root: []const u8, compilation: *language.project_compile.Compilation, spelling: grammar.Spelling) !?Target {
    return switch (spelling) {
        .position => |at| targetAt(run_, root, compilation, at),
        .qualified => |qualified| targetNamed(run_, root, compilation, qualified),
        .hiding => null,
    };
}

fn targetAt(run_: *Run, root: []const u8, compilation: *language.project_compile.Compilation, at: grammar.Position) !?Target {
    const path = std.Io.Dir.cwd().realPathFileAlloc(run_.io, at.path, run_.allocator) catch return null;
    const bytes = std.Io.Dir.cwd().readFileAlloc(run_.io, path, run_.allocator, .limited(file_limit)) catch return null;
    var offset = offsetOf(bytes, at.line, at.column) orelse return null;
    while (offset > 0 and identifierByte(bytes[offset - 1])) offset -= 1;
    const token = run_.state.tokens.old.get(keyHash(path, offset)) orelse return null;
    const key: Key = switch (token.meaning) {
        .declaration => |key| key,
        // A shorthand pattern field names both; a position names the local it binds.
        .shorthand => |pair| pair.local,
        .other, .ambiguous => return null,
    };
    return describe(run_, root, compilation, key);
}

/// What kind of declaration the one at `key` is, from the merged program that holds it, and what its new name would
/// clash with there.
fn describe(run_: *Run, root: []const u8, compilation: *language.project_compile.Compilation, key: Key) !?Target {
    const span = (try mergedSpan(run_, root, compilation, key)) orelse return null;
    const context: Describing = .{ .run = run_, .root = root, .compilation = compilation, .key = key, .span = span };
    if (try context.moduleLevel()) |target| return target;
    if (try context.member()) |target| return target;
    return context.local();
}

/// One declaration being described.
const Describing = struct {
    run: *Run,
    root: []const u8,
    compilation: *language.project_compile.Compilation,
    key: Key,
    span: source.Span,

    fn label(self: Describing, comptime format: []const u8, args: anytype) ![]const u8 {
        return std.fmt.allocPrint(self.run.allocator, format, args);
    }

    /// The places of the declarations among `names` that already have the new name.
    fn siblings(self: Describing, comptime T: type, names: []const T) ![]const Place {
        var clashes: std.ArrayList(Place) = .empty;
        for (names) |item| if (std.mem.eql(u8, self.compilation.src.text(item.name), self.run.options.name)) {
            try clashes.append(self.run.allocator, try placeOf(self.run, self.root, self.compilation, item.name));
        };
        return clashes.items;
    }

    fn moduleLevel(self: Describing) !?Target {
        const src = self.compilation.src;
        const new = self.run.options.name;
        for (self.compilation.index.units, 0..) |unit, module| for (unit.symbols.items) |symbol| {
            const declared = src.mappedSpan(module, symbol.span) catch continue;
            if (declared.start != self.span.start) continue;
            var clashes: std.ArrayList(Place) = .empty;
            if (unit.names.get(new)) |other| {
                const at = src.mappedSpan(module, unit.symbols.items[other].span) catch continue;
                try clashes.append(self.run.allocator, try placeOf(self.run, self.root, self.compilation, at));
            }
            for (self.compilation.index.project.modules.items[module].imports) |imported| if (std.mem.eql(u8, imported.alias, new)) {
                const at = src.mappedSpan(module, imported.span) catch continue;
                try clashes.append(self.run.allocator, try placeOf(self.run, self.root, self.compilation, at));
            };
            var extern_c = false;
            for (self.compilation.syntax.functions) |function| {
                if (function.name.start == self.span.start and function.policy.c_abi) extern_c = true;
            }
            const flags: Flags = .{ .extern_c = extern_c, .standard = !fileExists(self.run, self.key.path) };
            const name = try self.label("`{s}::{s}`", .{ self.compilation.index.project.modules.items[module].name, symbol.name });
            const reach: Reach = if (symbol.exported) .public else .private;
            return .{ .key = self.key, .kind = .module_level, .label = name, .flags = flags, .clashes = clashes.items, .reach = reach };
        };
        return null;
    }

    fn member(self: Describing) !?Target {
        const syntax = self.compilation.syntax;
        const src = self.compilation.src;
        const old = self.run.old;
        for (syntax.types.records) |entry| for (entry.fields) |field| if (field.name.start == self.span.start) {
            const name = try self.label("the field `{s}.{s}`", .{ src.text(entry.name), old });
            return .{ .key = self.key, .kind = .field, .label = name, .clashes = try self.siblings(ast.Parameter, entry.fields), .reach = reachOf(self.compilation, entry.name) };
        };
        for (syntax.types.variants) |variants| for (variants.cases) |case| {
            const reach = reachOf(self.compilation, variants.name);
            if (case.name.start == self.span.start) {
                const name = try self.label("the case `{s}.{s}`", .{ src.text(variants.name), old });
                return .{ .key = self.key, .kind = .case, .label = name, .clashes = try self.siblings(ast.Variant, variants.cases), .reach = reach };
            }
            for (case.fields) |field| if (field.name.start == self.span.start) {
                const name = try self.label("the field `{s}.{s}.{s}`", .{ src.text(variants.name), src.text(case.name), old });
                return .{ .key = self.key, .kind = .field, .label = name, .clashes = try self.siblings(ast.Parameter, case.fields), .reach = reach };
            };
        };
        return null;
    }

    fn local(self: Describing) !?Target {
        const declared = for (self.run.state.locals.items) |visible| {
            if (keyEql(visible.declaration, self.key)) break true;
        } else false;
        if (!declared) return null;
        // A parameter's name is also written at the call sites that label it.
        for (self.compilation.syntax.functions) |function| for (function.signature.parameters) |parameter| if (parameter.name.start == self.span.start) {
            const name = try self.label("the parameter `{s}`", .{self.run.old});
            return .{ .key = self.key, .kind = .local, .label = name, .reach = reachOf(self.compilation, function.name) };
        };
        return .{ .key = self.key, .kind = .local, .label = try self.label("the local `{s}`", .{self.run.old}), .reach = .file };
    }
};

/// Public when the module-level declaration whose name is at `span` is exported, else private.
fn reachOf(compilation: *language.project_compile.Compilation, span: source.Span) Reach {
    for (compilation.index.units, 0..) |unit, module| for (unit.symbols.items) |symbol| {
        const declared = compilation.src.mappedSpan(module, symbol.span) catch continue;
        if (declared.start == span.start) return if (symbol.exported) .public else .private;
    };
    return .public;
}

fn fileExists(run_: *Run, path: []const u8) bool {
    std.Io.Dir.cwd().access(run_.io, path, .{}) catch return false;
    return true;
}

fn mergedSpan(run_: *Run, root: []const u8, compilation: *language.project_compile.Compilation, key: Key) !?source.Span {
    for (compilation.index.project.modules.items, 0..) |module, position| {
        const path = try absolutePath(run_, root, module.src.path);
        if (!std.mem.eql(u8, path, key.path)) continue;
        return compilation.src.mappedSpan(position, .{ .start = key.start, .end = key.start + run_.old.len }) catch null;
    }
    return null;
}

/// The declaration a `module::name`, `module::Type.member` or `module.name` spelling names.
fn targetNamed(run_: *Run, root: []const u8, compilation: *language.project_compile.Compilation, qualified: []const u8) !?Target {
    _ = qualified;
    for (compilation.index.project.modules.items, 0..) |module, position| {
        if (std.mem.startsWith(u8, module.src.path, "@")) continue;
        if (!std.mem.eql(u8, try absolutePath(run_, root, module.src.path), run_.context.declared.path)) continue;
        const span = memberSpan(compilation, position, run_.context.declared.member) orelse return null;
        const key = try keyOf(run_, root, compilation, span);
        return describe(run_, root, compilation, key);
    }
    return null;
}

/// The declaration `member` names in module `module`: a module-level name (`f`, `Domain.f`), then a type's field or case
/// (`T.x`), then a case's field (`T.C.x`).
fn memberSpan(compilation: *language.project_compile.Compilation, module: usize, member: []const u8) ?source.Span {
    const unit = compilation.index.units[module];
    if (unit.names.get(member)) |symbol| {
        // A re-export (`export units.make`) names the declaration it publishes.
        var at: struct { module: usize, symbol: usize } = .{ .module = module, .symbol = symbol };
        var remaining = compilation.index.units.len + 1;
        while (remaining != 0) : (remaining -= 1) {
            const declared = compilation.index.units[at.module].symbols.items[at.symbol];
            const origin = declared.re_export orelse return compilation.src.mappedSpan(at.module, declared.span) catch null;
            at = .{ .module = origin.module, .symbol = origin.symbol };
        }
        return null;
    }
    var parts = std.mem.splitScalar(u8, member, '.');
    const type_name = parts.next() orelse return null;
    const first = parts.next() orelse return null;
    const second = parts.next();
    if (parts.next() != null) return null;
    const symbol = unit.names.get(type_name) orelse return null;
    const declared = compilation.src.mappedSpan(module, unit.symbols.items[symbol].span) catch return null;
    const syntax = compilation.syntax;
    for (syntax.types.records) |entry| if (entry.name.start == declared.start) {
        if (second != null) return null;
        for (entry.fields) |field| if (std.mem.eql(u8, compilation.src.text(field.name), first)) return field.name;
    };
    for (syntax.types.variants) |variants| if (variants.name.start == declared.start) for (variants.cases) |case| {
        if (!std.mem.eql(u8, compilation.src.text(case.name), first)) continue;
        const field_name = second orelse return case.name;
        for (case.fields) |field| if (std.mem.eql(u8, compilation.src.text(field.name), field_name)) return field.name;
    };
    return null;
}

fn missingMessage(run_: *Run, spelling: grammar.Spelling) ![]const u8 {
    return switch (spelling) {
        .qualified => |qualified| std.fmt.allocPrint(run_.allocator, "no declaration `{s}` in the checked project", .{qualified}),
        .position => |at| std.fmt.allocPrint(run_.allocator, "the name at {s}:{d}:{d} is not a declaration this command renames, nor a use of one", .{ at.path, at.line, at.column }),
        .hiding => |name| std.fmt.allocPrint(run_.allocator, "no binding of the project hides `{s}`", .{name}),
    };
}

// ---- Clashes -------------------------------------------------------------------------------------------------------

/// Refuse when the new name is already taken where the target lives, or would shadow or be shadowed.
fn clash(run_: *Run, target: Target) !?u8 {
    const allocator = run_.allocator;
    const new = run_.options.name;
    switch (target.kind) {
        .module_level => {
            var places: std.ArrayList(Place) = .empty;
            try places.appendSlice(allocator, target.clashes);
            if (places.items.len != 0) {
                const status = try refuseWith(run_, "taken", "`{s}` is already declared in the module of {s}", .{ new, target.label }, places.items);
                return status;
            }
            // A local of the declaring module under the new name would hide the renamed declaration.
            for (run_.state.tokens.new.values()) |token| {
                if (token.declares != .local or !std.mem.eql(u8, token.place.path, target.key.path)) continue;
                try places.append(allocator, token.place);
            }
            if (places.items.len != 0) {
                const status = try refuseWith(run_, "shadowing", "a local of the same module is already called `{s}` and would hide {s} (`E_SHADOWING`)", .{ new, target.label }, places.items);
                return status;
            }
        },
        .field, .case => {
            if (target.clashes.len != 0) {
                const status = try refuseWith(run_, "taken", "`{s}` is already a member of the type that holds {s}", .{ new, target.label }, target.clashes);
                return status;
            }
        },
        .local => return clashLocal(run_, target),
    }
    return null;
}

/// `clash` for a local or parameter, and for the bindings a `hiding:NAME` rename renames with it.
fn clashLocal(run_: *Run, target: Target) !?u8 {
    const allocator = run_.allocator;
    const new = run_.options.name;
    var places: std.ArrayList(Place) = .empty;
    var keys: std.ArrayList(Key) = .empty;
    try keys.append(allocator, target.key);
    try keys.appendSlice(allocator, target.also);
    var mine: std.ArrayList(Visible) = .empty;
    for (keys.items) |key| for (run_.state.locals.items) |visible| {
        if (keyEql(visible.declaration, key)) {
            try mine.append(allocator, visible);
            break;
        }
    };
    if (mine.items.len == 0) return null;
    for (mine.items) |renamed| for (run_.state.locals.items) |visible| {
        if (!keyEql(visible.function, renamed.function) or isTarget(target, visible.declaration)) continue;
        const token = run_.state.tokens.new.get(keyHash(visible.declaration.path, visible.declaration.start)) orelse continue;
        if (token.declares != .local) continue;
        if (overlap(renamed, visible)) try places.append(allocator, token.place);
    };
    if (places.items.len != 0) {
        const status = try refuseWith(run_, "shadowing", "`{s}` is already bound where {s} is visible, and a name is bound once where it is visible (`E_SHADOWING`)", .{ new, target.label }, places.items);
        return status;
    }
    // Two bindings renamed together must not be visible at once either.
    for (mine.items, 0..) |left, position| for (mine.items[position + 1 ..]) |right| {
        if (!keyEql(left.function, right.function) or !overlap(left, right)) continue;
        try places.append(allocator, .{ .path = right.declaration.path, .start = right.declaration.start, .end = right.declaration.start + run_.old.len });
    };
    if (places.items.len != 0) {
        const status = try refuseWith(run_, "shadowing", "two of {s} are visible at once, so they cannot share `{s}`: a name is bound once where it is visible (`E_SHADOWING`)", .{ target.label, new }, places.items);
        return status;
    }
    // A module-level name of the module, which a local may not hide.
    for (run_.state.tokens.new.values()) |token| {
        if (token.declares != .module_level) continue;
        const same_file = for (keys.items) |key| {
            if (std.mem.eql(u8, token.place.path, key.path)) break true;
        } else false;
        if (same_file) try places.append(allocator, token.place);
    }
    if (places.items.len != 0) {
        const status = try refuseWith(run_, "shadowing", "`{s}` is a module-level name of the same module, which {s} would hide (`E_SHADOWING`)", .{ new, target.label }, places.items);
        return status;
    }
    return null;
}

/// Two locals of one function overlap when either is declared inside the other's block.
fn overlap(left: Visible, right: Visible) bool {
    return (right.declaration.start >= left.declaration.start and right.declaration.start < left.end) or
        (left.declaration.start >= right.declaration.start and left.declaration.start < right.end);
}

// ---- Edits -------------------------------------------------------------------------------------------------------------

/// One replacement in one file.
const Edit = struct { place: Place, text: []const u8, pair: ?Place = null };

const EditKind = enum { plain, shorthand_field, shorthand_local };

fn editFor(run_: *Run, token: Token, kind: EditKind) !Edit {
    const text = switch (kind) {
        .plain => run_.options.name,
        // `case atom(text)` binds the field `text` to the local `text`: keep the other half's name explicit.
        .shorthand_field => try std.fmt.allocPrint(run_.allocator, "{s}={s}", .{ run_.options.name, run_.old }),
        .shorthand_local => try std.fmt.allocPrint(run_.allocator, "{s}={s}", .{ run_.old, run_.options.name }),
    };
    return .{ .place = token.place, .text = text, .pair = token.pair };
}

/// A pattern field written `label=binding` whose two halves the rename makes equal is written as the one name, the form
/// `selka fix` prefers (`L_PATTERN_SHORTHAND`), so renaming back restores a shorthand the forward rename expanded.
fn collapsePairs(run_: *Run, edits: []Edit) !void {
    for (edits) |*edit| {
        const pair = edit.pair orelse continue;
        const bytes = try readFile(run_, edit.place.path);
        const other = bytes[pair.start..pair.end];
        if (!std.mem.eql(u8, other, run_.options.name)) continue;
        // The halves are `label=binding` in order: cover from the first start to the last end.
        const start = @min(edit.place.start, pair.start);
        const end = @max(edit.place.end, pair.end);
        const between = bytes[start..end];
        const equals = std.mem.indexOfScalar(u8, between, '=') orelse continue;
        if (std.mem.trim(u8, between[0..equals], " ").len == 0) continue;
        edit.place = .{ .path = edit.place.path, .start = start, .end = end };
        edit.text = run_.options.name;
    }
}

/// The renamed copy of one file.
const File = struct { path: []const u8, before: []const u8, after: []const u8, edits: []const Edit };

/// A file's bytes: the renamed copy's in the second phase of a shadowing repair, else the disk's.
fn readFile(run_: *Run, path: []const u8) ![]const u8 {
    if (run_.context.overlay.get(path)) |text| return text;
    return std.Io.Dir.cwd().readFileAlloc(run_.io, path, run_.allocator, .limited(file_limit));
}

fn editLess(_: void, left: Edit, right: Edit) bool {
    return left.place.start < right.place.start;
}

fn applyEdits(run_: *Run, edits: []const Edit) ![]const File {
    var by_path: std.array_hash_map.String(std.ArrayList(Edit)) = .empty;
    for (edits) |edit| {
        const slot = try by_path.getOrPut(run_.allocator, edit.place.path);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(run_.allocator, edit);
    }
    var files: std.ArrayList(File) = .empty;
    for (by_path.keys(), by_path.values()) |path, *list| {
        std.mem.sort(Edit, list.items, {}, editLess);
        // Drop a second edit of one place (two entries can report the same token), and any edit inside a collapsed one.
        var kept: std.ArrayList(Edit) = .empty;
        for (list.items) |edit| {
            if (kept.items.len != 0) {
                const last = kept.items[kept.items.len - 1];
                if (edit.place.start < last.place.end) {
                    if (edit.place.end > last.place.end) kept.items[kept.items.len - 1] = edit;
                    continue;
                }
            }
            try kept.append(run_.allocator, edit);
        }
        const before = try readFile(run_, path);
        var after: std.ArrayList(u8) = .empty;
        var cursor: usize = 0;
        for (kept.items) |edit| {
            try after.appendSlice(run_.allocator, before[cursor..edit.place.start]);
            try after.appendSlice(run_.allocator, edit.text);
            cursor = edit.place.end;
        }
        try after.appendSlice(run_.allocator, before[cursor..]);
        try files.append(run_.allocator, .{ .path = path, .before = before, .after = after.items, .edits = kept.items });
    }
    return files.items;
}

/// Where a byte of a renamed file was before the rename: an offset inside a replacement reads as the replaced text's start.
fn originalOffset(file: File, offset: usize) usize {
    var delta: isize = 0;
    for (file.edits) |edit| {
        const start: isize = @as(isize, @intCast(edit.place.start)) + delta;
        if (@as(isize, @intCast(offset)) < start) break;
        const replaced_end = start + @as(isize, @intCast(edit.text.len));
        if (@as(isize, @intCast(offset)) < replaced_end) return edit.place.start;
        delta += @as(isize, @intCast(edit.text.len)) - @as(isize, @intCast(edit.place.end - edit.place.start));
    }
    return @intCast(@as(isize, @intCast(offset)) - delta);
}

// ---- The check of the renamed copy ---------------------------------------------------------------------------------

fn checkAfter(run_: *Run, entry_path: []const u8, files: []const File) !Checked {
    var scratch = std.heap.ArenaAllocator.init(run_.gpa);
    defer scratch.deinit();
    const arena = scratch.allocator();
    var report_: std.ArrayList(u8) = .empty;
    const entry = project_entry.resolve(run_.allocator, run_.io, entry_path, &report_) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return .{ .entry = entry_path, .findings = &.{}, .lines = try splitLines(run_, report_.items) },
    };
    // The loader reads a module by the path its import names, which may be a link to the edited file. In the second phase
    // of a shadowing repair the copy's other files are overlaid too.
    var paths: std.ArrayList([]const u8) = .empty;
    var texts: std.ArrayList([]const u8) = .empty;
    for (run_.context.overlay.keys(), run_.context.overlay.values()) |path, text| {
        const edited = for (files) |file| {
            if (std.mem.eql(u8, file.path, path)) break true;
        } else false;
        if (edited) continue;
        try paths.append(run_.allocator, path);
        try texts.append(run_.allocator, text);
    }
    for (files) |file| {
        try paths.append(run_.allocator, file.path);
        try texts.append(run_.allocator, file.after);
    }
    var session = frontend.Session.init(run_.gpa, run_.io, entry.root);
    defer session.deinit();
    session.setProviders(try overlayProviders(run_, entry.root, paths.items, texts.items));
    _ = try checkSession(run_, arena, &session, entry, &report_);
    const checked = try verdict(run_, entry_path, entry.root, report_.items);
    // Read each position of a renamed file back through the edits.
    for (checked.findings) |*finding| for (files) |file| {
        if (std.mem.eql(u8, file.path, finding.path)) finding.start = originalOffset(file, finding.start);
    };
    return checked;
}

fn findingLess(_: void, left: Finding, right: Finding) bool {
    const by_path = std.mem.order(u8, left.path, right.path);
    if (by_path != .eq) return by_path == .lt;
    if (left.start != right.start) return left.start < right.start;
    const by_code = std.mem.order(u8, left.code, right.code);
    if (by_code != .eq) return by_code == .lt;
    return std.mem.lessThan(u8, left.severity, right.severity);
}

fn findingEql(left: Finding, right: Finding) bool {
    return left.start == right.start and std.mem.eql(u8, left.code, right.code) and std.mem.eql(u8, left.severity, right.severity) and std.mem.eql(u8, left.path, right.path);
}

/// What a shadowing repair's verdict refusal says differs: the project, apart from the refusals the repair removes.
const repair_check = "the project does not check as before apart from the refusals the rename repairs";

/// Refuse, writing nothing, when the renamed copy's verdict differs from the original's.
/// `what` names the check that differs, for the message.
fn compareVerdicts(run_: *Run, before: Checked, after: Checked, files: []const File, what: []const u8) !?u8 {
    // A position inside replaced text reads as the replacement's start, on both sides: a pattern field the rename writes
    // as one name (`label=binding` to `binding`) moves a diagnostic of either half to where the field starts.
    for (before.findings) |*finding| for (files) |file| {
        if (!std.mem.eql(u8, file.path, finding.path)) continue;
        for (file.edits) |edit| {
            if (finding.start >= edit.place.start and finding.start < edit.place.end) finding.start = edit.place.start;
        }
    };
    std.mem.sort(Finding, before.findings, {}, findingLess);
    std.mem.sort(Finding, after.findings, {}, findingLess);
    var differences: std.ArrayList([]const u8) = .empty;
    var places: std.ArrayList(Place) = .empty;
    var revealed: ?Finding = null;
    var gone: usize = 0;
    var left: usize = 0;
    var right: usize = 0;
    while (left < before.findings.len or right < after.findings.len) {
        if (left < before.findings.len and right < after.findings.len and findingEql(before.findings[left], after.findings[right])) {
            left += 1;
            right += 1;
            continue;
        }
        const take_left = right >= after.findings.len or (left < before.findings.len and findingLess({}, before.findings[left], after.findings[right]));
        const finding = if (take_left) before.findings[left] else after.findings[right];
        try differences.append(run_.allocator, try std.fmt.allocPrint(run_.allocator, "{s} {s} {s}", .{ if (take_left) "gone:" else "new: ", finding.severity, finding.code }));
        try places.append(run_.allocator, .{ .path = finding.path, .start = finding.start, .end = finding.start });
        if (take_left) gone += 1 else if (revealed == null) revealed = finding;
        if (take_left) left += 1 else right += 1;
    }
    if (differences.items.len == 0) return null;
    var message: std.ArrayList(u8) = .empty;
    const differ = if (differences.items.len == 1) "diagnostic differs" else "diagnostics differ";
    try message.print(run_.allocator, "{s} (entry {s}): {d} {s}:", .{ what, try shortPath(run_, after.entry), differences.items.len, differ });
    for (differences.items[0..@min(differences.items.len, shown)]) |line| try message.print(run_.allocator, " [{s}]", .{line});
    // A repair that only reveals errors says so: the rename is right, the program has an error the clash was hiding.
    if (gone == 0 and std.mem.eql(u8, what, repair_check)) if (revealed) |first| {
        try message.appendSlice(run_.allocator, try rename_revealed.sentence(run_.allocator, .{
            .count = differences.items.len,
            .severity = first.severity,
            .code = first.code,
            .message = first.message,
        }));
    };
    const status = try refuse(run_, "verdict", message.items, places.items);
    return status;
}

// ---- Repairing a shadowing refusal (D-FR18-2) ----------------------------------------------------------------------
//
// A binding `E_SHADOWING` refuses hides a module-level name or an import alias of its module, so the project does not
// check and a check has no typed tree to resolve fields by. The repair runs in two phases. The first resolves the uses of
// each binding by its block scope in the program as it is (the walk is the one every local rename uses) and writes them,
// in a copy in memory, under a fresh name of the same length that no file holds. The second checks that copy, which now
// has the checker's tables, and runs the ordinary rename over it from the fresh name to the new one: every token of the
// fresh name must resolve to one of the bindings, and every token of the old name in the files the rename edits must
// resolve to something the checker names. The files are written when the copy checks as the project did, apart from the
// `E_SHADOWING` refusals at the renamed bindings, and the renamed project checks as the copy did.

/// What a shadowing repair adds to a report: the refusals it removed, the errors left as they were, and the warnings the
/// refused check did not print.
/// `removed` holds their places located before the files are written.
const Repaired = struct { removed: []const []const u8, unchanged: usize, warnings: usize };

/// `hiding:NAME`: check every program that loads a file holding `NAME`, then repair every binding that hides it.
fn repairHiding(run_: *Run, graphs: []const Graph, scope: []const u8) !u8 {
    const allocator = run_.allocator;
    for (try cover(run_, graphs, run_.state.reach.modules.keys(), "")) |entry| try checkEntry(run_, entry, null);
    var bindings: std.ArrayList(Key) = .empty;
    for (run_.state.tokens.old.values()) |token| {
        if (token.declares != .local or !token.hides) continue;
        if (!under(scope, token.place.path)) continue;
        try bindings.append(allocator, .{ .path = token.place.path, .start = token.place.start });
    }
    if (bindings.items.len == 0) return refuseWith(run_, "missing", "no binding of the project hides `{s}`", .{run_.old}, &.{});
    std.mem.sort(Key, bindings.items, {}, keyLess);
    const count = bindings.items.len;
    const label = try std.fmt.allocPrint(allocator, "the {d} binding{s} hiding `{s}`", .{ count, plural(count), run_.old });
    return repair(run_, scope, bindings.items, label);
}

fn keyLess(_: void, left: Key, right: Key) bool {
    const by_path = std.mem.order(u8, left.path, right.path);
    if (by_path != .eq) return by_path == .lt;
    return left.start < right.start;
}

/// One shadowing repair: the bindings, what they are called, the fresh name of the copy, and the copy the first phase made.
const Repairing = struct { scope: []const u8, label: []const u8, old: []const u8, fresh: []const u8, bindings: []const Key, copied: []const File = &.{} };

/// Rename `bindings`, each a binding that hides a module-level name or an import alias, to the new name.
fn repair(run_: *Run, scope: []const u8, bindings: []const Key, label: []const u8) !u8 {
    const fresh = (try freshName(run_)) orelse
        return refuseWith(run_, "unresolved", "no unused name of {d} letters is left to check the renamed copy with", .{run_.old.len}, &.{});
    var job: Repairing = .{ .scope = scope, .label = label, .old = run_.old, .fresh = fresh, .bindings = bindings };
    job.copied = (try firstPhase(run_, job)) orelse return 1;
    const disk = run_.state.before.items;
    // The second phase, over the copy.
    var wanted: std.ArrayList(Key) = .empty;
    for (bindings) |key| try wanted.append(run_.allocator, .{ .path = key.path, .start = forwardOffset(job.copied, key) });
    run_.state = .{ .reach = run_.state.reach };
    for (job.copied) |file| try run_.context.overlay.put(run_.allocator, file.path, file.after);
    run_.context.hidden = job.old;
    run_.context.wanted = wanted.items;
    run_.old = fresh;
    for (disk) |checked| try checkEntry(run_, checked.entry, null);
    var target = run_.state.target orelse return refuseWith(run_, "unresolved", "the copy with {s} renamed does not resolve them", .{label}, &.{});
    target.label = label;
    const edits = (try copyEdits(run_, job, target)) orelse return 1;
    const repaired = (try compareRepaired(run_, disk, run_.state.before.items, job)) orelse return 1;
    if (try clash(run_, target)) |status| return status;
    try collapsePairs(run_, edits);
    const files = try applyEdits(run_, edits);
    if (try freshLeft(run_, job, files)) |status| return status;
    for (run_.state.before.items) |before| {
        const after = try checkAfter(run_, before.entry, files);
        if (try compareVerdicts(run_, before, after, files, same_check)) |status| return status;
    }
    const written = try diskFiles(run_, job, files);
    run_.context.overlay = .empty;
    run_.context.hidden = "";
    run_.old = job.old;
    if (!run_.options.dry_run) try writeFiles(run_, written);
    try report(run_, target, written, .{ .scope = scope, .unfollowed = &.{}, .repaired = repaired });
    return 0;
}

// ---- Renaming the name a shadowing refusal names (F-79) ---------------------------------------------------------------
//
// The refusal's other end: a function, constant, type or constraint that bindings hide. Renaming it cures the same
// `E_SHADOWING` as renaming the bindings, and with the error gone the later checks run, so a warning the file always
// held is printed for the first time. A plain comparison cannot tell that warning from one the rename caused, so the
// comparison runs through the cured program: a copy in memory with each hiding binding renamed under a fresh name (the
// first phase of a repair) says what the project prints with the clash cured, and the renamed project must print exactly
// that. The copy against the disk is a repair's comparison (errors equal but for the refusals; warnings counted); the
// renamed project against the copy is a rename's (every diagnostic equal), and the two differ by names only.

/// The bindings the checks of the project refuse for hiding the target: each `E_SHADOWING` whose `declared here` note is the
/// target's declaration, once, in file order. None when the target is not a module-level name.
fn hidingTarget(run_: *Run, target: Target) ![]const Key {
    var bindings: std.ArrayList(Key) = .empty;
    if (target.kind != .module_level) return bindings.items;
    for (run_.state.before.items) |checked| for (checked.findings) |finding| {
        if (!std.mem.eql(u8, finding.code, diagnostic.shadowing)) continue;
        const declared = finding.declared orelse continue;
        if (!keyEql(declared, target.key)) continue;
        const key: Key = .{ .path = finding.path, .start = finding.start };
        const seen = for (bindings.items) |item| {
            if (keyEql(item, key)) break true;
        } else false;
        if (!seen) try bindings.append(run_.allocator, key);
    };
    std.mem.sort(Key, bindings.items, {}, keyLess);
    return bindings.items;
}

/// What a rename that cures shadowing refusals says differs from the cured copy.
const cured_check = "the renamed project does not check as the project does with its name clash cured";

/// Rename the target, which `bindings` hide, and write the files when the renamed project checks as the project does with
/// those bindings renamed under a fresh name: the same errors but the refusals, and the same warnings.
fn renameCuring(run_: *Run, target: Target, files: []const File, bindings: []const Key, extra: Extra) !u8 {
    const label = try std.fmt.allocPrint(run_.allocator, "the {d} binding{s} hiding `{s}`", .{ bindings.len, plural(bindings.len), run_.old });
    const fresh = (try freshName(run_)) orelse
        return refuseWith(run_, "unresolved", "no unused name of {d} letters is left to check the cured copy with", .{run_.old.len}, &.{});
    var job: Repairing = .{ .scope = extra.scope, .label = label, .old = run_.old, .fresh = fresh, .bindings = bindings };
    job.copied = (try firstPhase(run_, job)) orelse return 1;
    const disk = run_.state.before.items;
    // The cured program: the copy, checked from the entries as they were checked.
    for (job.copied) |file| try run_.context.overlay.put(run_.allocator, file.path, file.after);
    var cured: std.ArrayList(Checked) = .empty;
    for (disk) |checked| try cured.append(run_.allocator, try checkAfter(run_, checked.entry, &.{}));
    run_.context.overlay = .empty;
    const repaired = (try compareRepaired(run_, disk, cured.items, job)) orelse return 1;
    for (disk, cured.items) |checked, copy| {
        const after = try checkAfter(run_, checked.entry, files);
        if (try compareVerdicts(run_, copy, after, files, cured_check)) |status| return status;
    }
    if (!run_.options.dry_run) try writeFiles(run_, files);
    try report(run_, target, files, .{ .scope = extra.scope, .unfollowed = extra.unfollowed, .repaired = repaired });
    return 0;
}

/// The first phase: the copy with each use the scope walk gives the bindings written under the fresh name; null after a
/// refusal when a use lies outside the project.
fn firstPhase(run_: *Run, job: Repairing) !?[]const File {
    const allocator = run_.allocator;
    const bindings: Target = .{ .key = job.bindings[0], .kind = .local, .label = job.label, .also = job.bindings[1..] };
    var first: std.ArrayList(Edit) = .empty;
    var outside: std.ArrayList(Place) = .empty;
    for (run_.state.candidates.items) |place| {
        const token = run_.state.tokens.old.get(placeKey(place)) orelse continue;
        const text = switch (token.meaning) {
            .declaration => |key| if (isTarget(bindings, key)) job.fresh else continue,
            .shorthand => |pair| if (isTarget(bindings, pair.local)) try std.fmt.allocPrint(allocator, "{s}={s}", .{ job.old, job.fresh }) else continue,
            .other, .ambiguous => continue,
        };
        if (!under(job.scope, place.path)) try outside.append(allocator, place) else try first.append(allocator, .{ .place = token.place, .text = text });
    }
    if (outside.items.len != 0) {
        _ = try refuseWith(run_, "outside", "{d} use{s} of {s} lie outside {s}, where nothing is renamed", .{ outside.items.len, plural(outside.items.len), job.label, run_.options.path }, outside.items);
        return null;
    }
    const copied = try applyEdits(run_, first.items);
    return copied;
}

/// The second phase's edits, from the fresh name to the new one. Every token of the fresh name must resolve to one of the
/// bindings, and every token of the old name left in the copy's files to something the checker names; null after a
/// refusal otherwise.
fn copyEdits(run_: *Run, job: Repairing, target: Target) !?[]Edit {
    const allocator = run_.allocator;
    var edits: std.ArrayList(Edit) = .empty;
    var unresolved: std.ArrayList(Place) = .empty;
    for (job.copied) |file| _ = try holdsName(run_, file.path);
    for (run_.state.candidates.items) |place| {
        const token = run_.state.tokens.old.get(placeKey(place)) orelse {
            try unresolved.append(allocator, place);
            continue;
        };
        const renamed: ?EditKind = switch (token.meaning) {
            .declaration => |key| if (isTarget(target, key)) EditKind.plain else null,
            .shorthand => |pair| if (isTarget(target, pair.local)) EditKind.shorthand_local else null,
            .other, .ambiguous => null,
        };
        const kind = renamed orelse {
            try unresolved.append(allocator, place);
            continue;
        };
        try edits.append(allocator, try editFor(run_, token, kind));
    }
    for (job.copied) |file| try hiddenUnresolved(run_, job, file, &unresolved);
    if (unresolved.items.len == 0) return edits.items;
    const count = unresolved.items.len;
    const why = if (run_.state.unchecked.items.len != 0) " (the copy with them renamed still does not check, so types are not known)" else "";
    const format = "{d} use{s} of `{s}` could not be resolved to a declaration, so the rename cannot prove which of them are uses of {s}{s}";
    _ = try refuseWith(run_, "unresolved", format, .{ count, plural(count), job.old, job.label, why }, unresolved.items);
    return null;
}

/// Add each token of the old name in one file of the copy that the checker's tables do not resolve.
fn hiddenUnresolved(run_: *Run, job: Repairing, file: File, unresolved: *std.ArrayList(Place)) !void {
    const scan = try scanName(run_, file.after, job.old);
    for (scan.code.items) |start| {
        const place: Place = .{ .path = file.path, .start = start, .end = start + job.old.len };
        const resolved = if (run_.state.tokens.hidden.get(placeKey(place))) |token| token.meaning != .ambiguous else false;
        if (!resolved) try unresolved.append(run_.allocator, place);
    }
}

/// Refuse when a token of the fresh name is left in a file the rename writes: a use of the bindings the copy did not
/// resolve.
fn freshLeft(run_: *Run, job: Repairing, files: []const File) !?u8 {
    for (job.copied) |file| {
        const renamed = for (files) |item| {
            if (std.mem.eql(u8, item.path, file.path)) break item.after;
        } else file.after;
        const left = try scanName(run_, renamed, job.fresh);
        if (left.code.items.len + left.strings.items.len + left.comments.items.len == 0) continue;
        const status = try refuseWith(run_, "unresolved", "a use of {s} in {s} was not resolved in the renamed copy", .{ job.label, try shortPath(run_, file.path) }, &.{});
        return status;
    }
    return null;
}

/// The files to write: the disk's own bytes, the renamed text, and the first phase's edits under the new name.
fn diskFiles(run_: *Run, job: Repairing, files: []const File) ![]const File {
    var written: std.ArrayList(File) = .empty;
    for (job.copied) |file| {
        const after = for (files) |item| {
            if (std.mem.eql(u8, item.path, file.path)) break item.after;
        } else file.after;
        var named: std.ArrayList(Edit) = .empty;
        for (file.edits) |edit| try named.append(run_.allocator, .{ .place = edit.place, .text = try std.mem.replaceOwned(u8, run_.allocator, edit.text, job.fresh, run_.options.name) });
        try written.append(run_.allocator, .{ .path = file.path, .before = file.before, .after = after, .edits = named.items });
    }
    return written.items;
}

fn placeLess(_: void, left: Place, right: Place) bool {
    return keyLess({}, .{ .path = left.path, .start = left.start }, .{ .path = right.path, .start = right.start });
}

/// How many of `findings` are not in `counted` yet; adds them.
fn countNew(run_: *Run, counted: *std.ArrayList(Finding), findings: []const Finding) !usize {
    var count: usize = 0;
    for (findings) |finding| {
        const seen = for (counted.items) |item| {
            if (findingEql(item, finding)) break true;
        } else false;
        if (seen) continue;
        try counted.append(run_.allocator, finding);
        count += 1;
    }
    return count;
}

/// Where the declaration at `key` is in the copy the first phase made: after the edits before it in its file.
fn forwardOffset(copied: []const File, key: Key) usize {
    for (copied) |file| {
        if (!std.mem.eql(u8, file.path, key.path)) continue;
        var delta: isize = 0;
        for (file.edits) |edit| {
            if (edit.place.start >= key.start) break;
            delta += @as(isize, @intCast(edit.text.len)) - @as(isize, @intCast(edit.place.end - edit.place.start));
        }
        return @intCast(@as(isize, @intCast(key.start)) + delta);
    }
    return key.start;
}

/// A name of the old name's length that is no reserved word and that no file of the project holds as a whole word, for
/// the copy the second phase checks; null when every one is taken.
fn freshName(run_: *Run) !?[]const u8 {
    const allocator = run_.allocator;
    var texts: std.ArrayList([]const u8) = .empty;
    for (run_.state.reach.modules.keys()) |path| try texts.append(allocator, readFile(run_, path) catch continue);
    for (run_.state.reach.unloaded.items) |unloaded| for (unloaded.paths) |path| try texts.append(allocator, readFile(run_, path) catch continue);
    for (run_.state.candidates.items) |place| try texts.append(allocator, readFile(run_, place.path) catch continue);
    const length = run_.old.len;
    const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
    var attempt: usize = 0;
    while (attempt < 4096) : (attempt += 1) {
        const name = try allocator.alloc(u8, length);
        if (length == 1) {
            if (attempt >= 26) return null;
            name[0] = @intCast('a' + attempt);
        } else {
            name[0] = 'q';
            var rest = attempt;
            var index = length;
            while (index > 1) {
                index -= 1;
                name[index] = alphabet[rest % alphabet.len];
                rest /= alphabet.len;
            }
            if (rest != 0) return null;
        }
        if (!lexer.isIdentifier(name) or std.mem.eql(u8, name, run_.old) or std.mem.eql(u8, name, run_.options.name)) continue;
        const used = for (texts.items) |text| {
            if (holdsWord(text, name)) break true;
        } else false;
        if (!used) return name;
    }
    return null;
}

/// Whether `word` occurs in `text` with no identifier byte on either side.
fn holdsWord(text: []const u8, word: []const u8) bool {
    var position: usize = 0;
    while (std.mem.indexOfPos(u8, text, position, word)) |found| {
        position = found + 1;
        if (found > 0 and identifierByte(text[found - 1])) continue;
        const end = found + word.len;
        if (end < text.len and identifierByte(text[end])) continue;
        return true;
    }
    return false;
}

/// Compare the errors of the copy (its checks, `copies`) with the disk's, the `E_SHADOWING` refusals at the renamed
/// bindings aside (D-FR18-3). Null after printing the refusal when they differ; otherwise what the repair removed.
fn compareRepaired(run_: *Run, disk: []const Checked, copies: []const Checked, job: Repairing) !?Repaired {
    var removed: std.ArrayList(Place) = .empty;
    var tally: Tally = .{};
    for (copies) |copy| {
        const original = for (disk) |item| {
            if (std.mem.eql(u8, item.entry, copy.entry)) break item;
        } else continue;
        const left = try diskErrors(run_, original, job, &removed);
        var right: std.ArrayList(Finding) = .empty;
        var warned: std.ArrayList(Finding) = .empty;
        for (copy.findings) |finding| {
            if (!std.mem.eql(u8, finding.severity, "error")) {
                try warned.append(run_.allocator, finding);
                continue;
            }
            var mapped = finding;
            for (job.copied) |file| {
                if (std.mem.eql(u8, file.path, finding.path)) mapped.start = originalOffset(file, finding.start);
            }
            try right.append(run_.allocator, mapped);
        }
        tally.unchanged += try countNew(run_, &tally.counted, left);
        tally.warnings += try countNew(run_, &tally.counted, warned.items);
        const before: Checked = .{ .entry = original.entry, .findings = left, .lines = original.lines };
        const after: Checked = .{ .entry = copy.entry, .findings = right.items, .lines = copy.lines };
        if (try compareVerdicts(run_, before, after, &.{}, repair_check)) |_| return null;
    }
    std.mem.sort(Place, removed.items, {}, placeLess);
    var located_removed: std.ArrayList([]const u8) = .empty;
    for (removed.items) |place| {
        // The places are the disk's; the copy is overlaid now, so read the line and column from the disk's bytes.
        const bytes = for (job.copied) |file| {
            if (std.mem.eql(u8, file.path, place.path)) break file.before;
        } else try readFile(run_, place.path);
        try located_removed.append(run_.allocator, try locatedIn(run_, bytes, place));
    }
    return .{ .removed = located_removed.items, .unchanged = tally.unchanged, .warnings = tally.warnings };
}

/// The errors and warnings a repair's report counts, each once although several checked programs load its module.
const Tally = struct { counted: std.ArrayList(Finding) = .empty, unchanged: usize = 0, warnings: usize = 0 };

/// The disk check's errors without the `E_SHADOWING` refusals at the renamed bindings, which go to `removed` once each.
fn diskErrors(run_: *Run, original: Checked, job: Repairing, removed: *std.ArrayList(Place)) ![]Finding {
    var left: std.ArrayList(Finding) = .empty;
    for (original.findings) |finding| {
        if (!std.mem.eql(u8, finding.severity, "error")) continue;
        if (!std.mem.eql(u8, finding.code, diagnostic.shadowing) or !atBinding(job.bindings, finding)) {
            try left.append(run_.allocator, finding);
            continue;
        }
        const seen = for (removed.items) |item| {
            if (item.start == finding.start and std.mem.eql(u8, item.path, finding.path)) break true;
        } else false;
        if (!seen) try removed.append(run_.allocator, .{ .path = finding.path, .start = finding.start, .end = finding.start + job.old.len });
    }
    return left.items;
}

fn atBinding(bindings: []const Key, finding: Finding) bool {
    for (bindings) |key| if (key.start == finding.start and std.mem.eql(u8, key.path, finding.path)) return true;
    return false;
}

// ---- Writing and reporting ---------------------------------------------------------------------------------------

fn writeFiles(run_: *Run, files: []const File) !void {
    for (files) |file| {
        // Refuse to overwrite a file that changed since it was read.
        const now = try readFile(run_, file.path);
        if (!std.mem.eql(u8, now, file.before)) return error.SourceChanged;
    }
    for (files) |file| try std.Io.Dir.cwd().writeFile(run_.io, .{ .sub_path = file.path, .data = file.after });
}

/// A located place as `path:line:column`, relative to the working directory when it lies under it.
fn located(run_: *Run, place: Place) ![]const u8 {
    const bytes = readFile(run_, place.path) catch return place.path;
    return locatedIn(run_, bytes, place);
}

/// `located` in the given bytes of the place's file.
fn locatedIn(run_: *Run, bytes: []const u8, place: Place) ![]const u8 {
    var line: usize = 1;
    var column: usize = 1;
    for (bytes[0..@min(place.start, bytes.len)]) |byte| {
        if (byte == '\n') {
            line += 1;
            column = 1;
        } else column += 1;
    }
    return std.fmt.allocPrint(run_.allocator, "{s}:{d}:{d}", .{ try shortPath(run_, place.path), line, column });
}

fn shortPath(run_: *Run, path: []const u8) ![]const u8 {
    const here = std.Io.Dir.cwd().realPathFileAlloc(run_.io, ".", run_.allocator) catch return path;
    if (under(here, path) and path.len > here.len) return path[here.len + 1 ..];
    return path;
}

/// `refuse` with a message formatted from `format` and `args`.
fn refuseWith(run_: *Run, reason: []const u8, comptime format: []const u8, args: anytype, places: []const Place) !u8 {
    const message = try std.fmt.allocPrint(run_.allocator, format, args);
    return refuse(run_, reason, message, places);
}

/// A refusal: nothing is written; the reason, its places, exit 1.
fn refuse(run_: *Run, reason: []const u8, message: []const u8, places: []const Place) !u8 {
    var out: std.ArrayList(u8) = .empty;
    if (run_.options.json) {
        var located_places: std.ArrayList([]const u8) = .empty;
        for (places) |place| try located_places.append(run_.allocator, try located(run_, place));
        const document = .{ .version = "rename-v1", .status = "refused", .reason = reason, .message = message, .places = located_places.items };
        try out.appendSlice(run_.allocator, try std.json.Stringify.valueAlloc(run_.allocator, document, .{}));
        try out.append(run_.allocator, '\n');
        try std.Io.File.stdout().writeStreamingAll(run_.io, out.items);
        return 1;
    }
    try out.print(run_.allocator, "selka rename: refused ({s}): {s}; nothing was written\n", .{ reason, message });
    for (places[0..@min(places.len, shown)]) |place| try out.print(run_.allocator, "  {s}\n", .{try located(run_, place)});
    if (places.len > shown) try out.print(run_.allocator, "  ... and {d} more\n", .{places.len - shown});
    try std.Io.File.stderr().writeStreamingAll(run_.io, out.items);
    return 1;
}

/// Whole-word mentions of the old name left in strings and comments of the project's `.selka` files.
const Mention = struct { place: Place, kind: []const u8 };

fn mentions(run_: *Run, files: []const File, scope: []const u8) ![]const Mention {
    var list: std.ArrayList(Mention) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var paths: std.ArrayList([]const u8) = .empty;
    for (files) |file| try paths.append(run_.allocator, file.path);
    for (run_.state.candidates.items) |place| try paths.append(run_.allocator, place.path);
    for (paths.items) |path| {
        if (!under(scope, path)) continue;
        const slot = try seen.getOrPut(run_.allocator, path);
        if (slot.found_existing) continue;
        const bytes = try readFile(run_, path);
        const scan = try scanFile(run_, bytes);
        for (scan.strings.items) |start| try list.append(run_.allocator, .{ .place = .{ .path = path, .start = start, .end = start + run_.old.len }, .kind = "string" });
        for (scan.comments.items) |start| try list.append(run_.allocator, .{ .place = .{ .path = path, .start = start, .end = start + run_.old.len }, .kind = "comment" });
    }
    return list.items;
}

/// What the rename cannot see about a package: the `packages.json` manifests under the project that name a root holding
/// the declaration, whose locks pin the old bytes, and the programs outside the project that lock it.
fn packageNotes(run_: *Run, target: Target, scope: []const u8) ![]const []const u8 {
    var notes: std.ArrayList([]const u8) = .empty;
    var directory = std.Io.Dir.cwd().openDir(run_.io, scope, .{ .iterate = true, .follow_symlinks = false }) catch return notes.items;
    defer directory.close(run_.io);
    var walker = try directory.walk(run_.allocator);
    defer walker.deinit();
    const Manifest = struct { packages: []const struct { name: []const u8 = "", root: []const u8 = "" } = &.{} };
    while (try walker.next(run_.io)) |item| {
        if (item.kind == .directory and item.basename.len != 0 and (item.basename[0] == '.' or std.mem.eql(u8, item.basename, "zig-out"))) {
            walker.leave(run_.io);
            continue;
        }
        if (item.kind != .file or !std.mem.eql(u8, item.basename, "packages.json")) continue;
        const path = try std.fs.path.join(run_.allocator, &.{ scope, item.path });
        const bytes = readFile(run_, path) catch continue;
        const manifest = std.json.parseFromSliceLeaky(Manifest, run_.allocator, bytes, .{ .ignore_unknown_fields = true }) catch continue;
        for (manifest.packages) |package| {
            const root = try std.fs.path.resolve(run_.allocator, &.{ std.fs.path.dirname(path) orelse scope, package.root });
            if (!under(root, target.key.path)) continue;
            const format = "{s} is declared in the package `{s}` that {s} names: lock files pin its old bytes (lock again), " ++
                "and programs outside {s} that lock it were not renamed";
            try notes.append(run_.allocator, try std.fmt.allocPrint(run_.allocator, format, .{ target.label, package.name, try shortPath(run_, path), run_.options.path }));
        }
    }
    return notes.items;
}

/// What a report adds to the edits: where the project is, and the uses it could not follow.
const Extra = struct { scope: []const u8, unfollowed: []const Unfollowed, repaired: ?Repaired = null };

/// `report` as one `rename-v1` document.
fn reportJson(run_: *Run, target: Target, files: []const File, extra: Extra, left: []const Mention, notes: []const []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    var edit_count: usize = 0;
    for (files) |file| edit_count += file.edits.len;
    const JsonEdit = struct { bytes: struct { start: usize, end: usize }, text: []const u8 };
    const JsonFile = struct { path: []const u8, edits: []const JsonEdit };
    const JsonMention = struct { place: []const u8, kind: []const u8 };
    var json_files: std.ArrayList(JsonFile) = .empty;
    for (files) |file| {
        var json_edits: std.ArrayList(JsonEdit) = .empty;
        for (file.edits) |edit| try json_edits.append(run_.allocator, .{ .bytes = .{ .start = edit.place.start, .end = edit.place.end }, .text = edit.text });
        try json_files.append(run_.allocator, .{ .path = try shortPath(run_, file.path), .edits = json_edits.items });
    }
    var json_mentions: std.ArrayList(JsonMention) = .empty;
    for (left) |mention| try json_mentions.append(run_.allocator, .{ .place = try located(run_, mention.place), .kind = mention.kind });
    const JsonUnfollowed = struct { place: []const u8, entry: []const u8, reason: []const u8 };
    var json_unfollowed: std.ArrayList(JsonUnfollowed) = .empty;
    for (extra.unfollowed) |item| try json_unfollowed.append(run_.allocator, .{ .place = try located(run_, item.place), .entry = try shortPath(run_, item.entry), .reason = item.problem });
    const document = .{
        .version = "rename-v1",
        .status = if (run_.options.dry_run) "dry-run" else "renamed",
        .target = target.label,
        .old = run_.old,
        .new = run_.options.name,
        .declaration = try located(run_, .{ .path = target.key.path, .start = target.key.start, .end = target.key.start }),
        .edits = edit_count,
        .files = json_files.items,
        .checked_entries = run_.state.before.items.len,
        .mentions = json_mentions.items,
        .unfollowed = json_unfollowed.items,
        .notes = notes,
    };
    if (extra.repaired) |repaired| {
        // A shadowing repair also says which refusals it removed (D-FR18-2); every other rename prints as before.
        var removed: std.ArrayList([]const u8) = .empty;
        for (repaired.removed) |place| try removed.append(run_.allocator, place);
        const JsonRepaired = struct { removed: []const []const u8, unchanged_errors: usize, warnings_now_printed: usize };
        const repaired_document = .{
            .version = document.version,
            .status = document.status,
            .target = document.target,
            .old = document.old,
            .new = document.new,
            .declaration = document.declaration,
            .edits = document.edits,
            .files = document.files,
            .checked_entries = document.checked_entries,
            .mentions = document.mentions,
            .unfollowed = document.unfollowed,
            .notes = document.notes,
            .repaired = JsonRepaired{ .removed = removed.items, .unchanged_errors = repaired.unchanged, .warnings_now_printed = repaired.warnings },
        };
        try out.appendSlice(run_.allocator, try std.json.Stringify.valueAlloc(run_.allocator, repaired_document, .{}));
    } else try out.appendSlice(run_.allocator, try std.json.Stringify.valueAlloc(run_.allocator, document, .{}));
    try out.append(run_.allocator, '\n');
    try std.Io.File.stdout().writeStreamingAll(run_.io, out.items);
}

/// The lines a shadowing repair adds to the text report: the refusals it removed, and what else the checks print.
fn reportRepaired(run_: *Run, out: *std.ArrayList(u8), repaired: Repaired, target: Target) !void {
    const count = repaired.removed.len;
    if (target.kind == .local) {
        try out.print(run_.allocator, "removed {d} `E_SHADOWING` refusal{s} of the renamed binding{s}:\n", .{ count, plural(count), plural(target.also.len + 1) });
    } else try out.print(run_.allocator, "removed {d} `E_SHADOWING` refusal{s} of {s} that hid the renamed name:\n", .{ count, plural(count), if (count == 1) "a binding" else "bindings" });
    for (repaired.removed[0..@min(count, shown)]) |place| try out.print(run_.allocator, "  {s}\n", .{place});
    if (count > shown) try out.print(run_.allocator, "  ... and {d} more\n", .{count - shown});
    if (repaired.unchanged == 0) {
        try out.appendSlice(run_.allocator, "no other error before or after\n");
    } else try out.print(run_.allocator, "the other {d} error{s} unchanged\n", .{ repaired.unchanged, if (repaired.unchanged == 1) " is" else "s are" });
    if (repaired.warnings != 0) try out.print(run_.allocator, "{d} warning{s} the refused check did not print {s} printed now\n", .{ repaired.warnings, plural(repaired.warnings), if (repaired.warnings == 1) "is" else "are" });
}

fn report(run_: *Run, target: Target, files: []const File, extra: Extra) !void {
    const left = try mentions(run_, files, extra.scope);
    const notes = try packageNotes(run_, target, extra.scope);
    var strings: usize = 0;
    for (left) |mention| {
        if (std.mem.eql(u8, mention.kind, "string")) strings += 1;
    }
    var edit_count: usize = 0;
    for (files) |file| edit_count += file.edits.len;
    var out: std.ArrayList(u8) = .empty;
    if (run_.options.json) return reportJson(run_, target, files, extra, left, notes);
    const verb = if (run_.options.dry_run) "would rename" else "renamed";
    const entries = run_.state.before.items.len;
    try out.print(run_.allocator, "{s} {s} to `{s}`: {d} edit{s} in {d} file{s}; {d} entr{s} checked as before{s}\n", .{
        verb,      target.label,      run_.options.name, edit_count,                       plural(edit_count),
        files.len, plural(files.len), entries,           if (entries == 1) "y" else "ies", if (extra.repaired != null) " apart from the refusals it repairs" else "",
    });
    if (run_.options.dry_run) for (files) |file| for (file.edits) |edit| {
        try out.print(run_.allocator, "  {s}: `{s}` -> `{s}`\n", .{ try located(run_, edit.place), file.before[edit.place.start..edit.place.end], edit.text });
    };
    if (extra.repaired) |repaired| try reportRepaired(run_, &out, repaired, target);
    if (extra.unfollowed.len != 0) {
        try out.print(run_.allocator, "not followed: {d} use{s} of `{s}` in programs that do not load (a plain check cannot load them), left unchanged:\n", .{ extra.unfollowed.len, plural(extra.unfollowed.len), run_.old });
        for (extra.unfollowed[0..@min(extra.unfollowed.len, shown)]) |item| try out.print(run_.allocator, "  {s} (entry {s}: {s})\n", .{ try located(run_, item.place), try shortPath(run_, item.entry), item.problem });
        if (extra.unfollowed.len > shown) try out.print(run_.allocator, "  ... and {d} more\n", .{extra.unfollowed.len - shown});
    }
    for (notes) |note| try out.print(run_.allocator, "note: {s}\n", .{note});
    if (left.len != 0) {
        const comments = left.len - strings;
        try out.print(run_.allocator, "left unchanged: `{s}` appears as a whole word in ", .{run_.old});
        if (strings != 0) try out.print(run_.allocator, "{d} string literal{s}", .{ strings, plural(strings) });
        if (strings != 0 and comments != 0) try out.appendSlice(run_.allocator, " and ");
        if (comments != 0) try out.print(run_.allocator, "{d} comment{s}", .{ comments, plural(comments) });
        try out.appendSlice(run_.allocator, ":\n");
        for (left[0..@min(left.len, shown)]) |mention| try out.print(run_.allocator, "  {s} ({s})\n", .{ try located(run_, mention.place), mention.kind });
        if (left.len > shown) try out.print(run_.allocator, "  ... and {d} more\n", .{left.len - shown});
    }
    try std.Io.File.stdout().writeStreamingAll(run_.io, out.items);
}
