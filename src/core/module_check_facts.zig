//! The checks of a loaded project's modules, as the `module-check` kind states them (spec §17.2): for each function a module
//! declares, the digest of its validity key (the region of source it was checked from and the dependency context it was checked
//! in, the pair the front end's checked-body store keys a stored body by), and the names the module's bodies look up in other
//! modules to get that context.
//!
//! The contexts are the front end's own (`semantic_key.prepare`), and the lookups come from the same declaration graph
//! (`semantic_key.Surface`), so what the kind reads is what the context folds: an importer's record depends on the names its bodies
//! use and not on the modules it merely imports.
const std = @import("std");
const language = @import("selka");
const digest_rules = @import("engine/digest.zig");
const record = @import("engine/record.zig");
const check_kind = @import("engine/kinds/module_check.zig");
const interface_kind = @import("engine/kinds/module_interface.zig");
const interface_facts = @import("module_interface_facts.zig");

/// The domain string of a body's digest.
const domain = "selka-module-check-body-v1";
/// The prefix of the part a body is published under.
pub const body_prefix = "body:";

/// One module's check: the argument it is queried under and the answer the kind returns.
pub const Check = struct { argument: []const u8, answer: check_kind.Answer };

/// The query argument for `path` under the program flags `flags`.
pub fn argumentOf(a: std.mem.Allocator, path: []const u8, flags: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\x00{s}", .{ path, flags });
}

/// The query argument of module `module` of `index`'s project under the program flags `flags`: `argumentOf` its path, with the
/// module it is the test file of (`interfaces.Index.testedModule`) appended to the flags when it is one (FX10). Its bodies' contexts
/// fold that grant (`semantic_key.prepare`), which depends on which modules import the test file and not on anything the record
/// reads, so a record made under one grant is another query than the module's record under the other and is never restored for it.
pub fn moduleArgument(a: std.mem.Allocator, index: *const language.interfaces.Index, module: usize, flags: []const u8) std.mem.Allocator.Error![]const u8 {
    const path = index.project.modules.items[module].src.path;
    const tested = index.testedModule(module) orelse return argumentOf(a, path, flags);
    return argumentOf(a, path, try std.fmt.allocPrint(a, "{s};tests={s}", .{ flags, index.project.modules.items[tested].name }));
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn partLess(_: void, left: record.Part, right: record.Part) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// The two program-wide flags the checker reads and the contracts the contexts are taken under, as the query argument spells them.
/// The contracts are the front end's `semantic_key.Contracts` (the compiler's identity and the mutation-contract version): a
/// dependency context folds them, so a record made under other contracts is another query and is never served.
pub fn flagsOf(a: std.mem.Allocator, project: *const language.project.Project, contracts: language.semantic_key.Contracts) std.mem.Allocator.Error![]const u8 {
    var std_result = false;
    for (project.modules.items) |module| std_result = std_result or std.mem.eql(u8, module.name, "std_result");
    const many = project.modules.items.len > 1 or (project.modules.items.len == 1 and project.modules.items[0].imports.len != 0);
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(contracts.build);
    state.update("\x00");
    state.update(contracts.mutation);
    var digest: [32]u8 = undefined;
    state.final(&digest);
    return std.fmt.allocPrint(a, "std_result={d};module_graph={d};contracts={s}", .{ @intFromBool(std_result), @intFromBool(many), digest_rules.hex(digest)[0..32] });
}

/// The check of every module of `index`'s project, in module order, over `surface`, the declaration graph of the merged
/// program `program` (made with `initRecording`), which was prepared as `prepared`, under the query flags `flags` (`flagsOf`). Everything is
/// allocated in `a`, which should be an arena.
pub fn compute(
    a: std.mem.Allocator,
    surface: *language.semantic_key.Surface,
    program: language.ast.Program,
    index: *language.interfaces.Index,
    prepared: language.semantic_key.Prepared,
    flags: []const u8,
) std.mem.Allocator.Error![]const Check {
    const modules = index.project.modules.items;
    const out = try a.alloc(Check, modules.len);
    for (out, 0..) |*slot, id| slot.* = .{ .argument = try moduleArgument(a, index, id, flags), .answer = try checkOf(a, surface, program, index, prepared, .{ .module = id }) };
    return out;
}

/// Which module `checkOf` answers for, and how it finds the names the module's functions look up.
pub const Which = struct {
    module: usize,
    /// Resolve the names `prepare` recorded for each function (`Prepared.recalled.names`) instead of walking its tree, which also leaves a
    /// lazily loaded body unread. Set for a module the engine computes and records; a module that is compared with the record it stood
    /// against keeps the walk, so the comparison still checks that a record written from recalled names says what the tree says.
    recalled: bool = false,
};

/// The check of module `which.module` of `index`'s project: its payload is the module's per-function facts as the prepared keys record holds
/// them (stable key, region digest, dependency context, recalled names), which is what `semantic_key.Plan` restores from.
pub fn checkOf(
    a: std.mem.Allocator,
    surface: *language.semantic_key.Surface,
    program: language.ast.Program,
    index: *language.interfaces.Index,
    prepared: language.semantic_key.Prepared,
    which: Which,
) std.mem.Allocator.Error!check_kind.Answer {
    const module = which.module;
    const modules = index.project.modules.items;
    var parts: std.ArrayList(record.Part) = .empty;
    var facts: std.ArrayList(language.module_records.FunctionFact) = .empty;
    var found: std.StringHashMapUnmanaged(std.ArrayList([]const u8)) = .empty;
    for (program.functions, 0..) |_, at| {
        const key = language.semantic_key.Surface.functionKey(at);
        if (surface.moduleOfKey(key) != module) continue;
        var state = std.crypto.hash.Blake3.init(.{});
        state.update(domain);
        state.update("\x00");
        state.update(prepared.keys[at]);
        state.update("\x00");
        state.update(&prepared.recalled.digests[at]);
        state.update(&prepared.contexts[at]);
        var digest: [32]u8 = undefined;
        state.final(&digest);
        const name = try std.fmt.allocPrint(a, "{s}{s}", .{ body_prefix, try surface.nameOf(key) });
        try parts.append(a, .{ .name = name, .digest = digest });
        const names = try a.alloc(language.module_records.NameFact, prepared.recalled.names[at].len);
        for (prepared.recalled.names[at], names) |known, *slot| slot.* = .{ .text = known.text, .owner = known.owner };
        try facts.append(a, .{ .key = prepared.keys[at], .region = prepared.recalled.digests[at], .context = prepared.contexts[at], .names = names });
        for (try surface.functionLookups(at, if (which.recalled) prepared.recalled.names[at] else null)) |text| {
            const split = std.mem.indexOfScalar(u8, text, 0x1f) orelse continue;
            const other = std.fmt.parseInt(usize, text[0..split], 10) catch continue;
            if (other != module) try interface_facts.note(a, &found, other, text[split + 1 ..]);
        }
    }
    std.mem.sort(record.Part, parts.items, {}, partLess);
    const payload = try language.module_records.encodeKeys(a, .{ .functions = facts.items });
    return .{
        .payload = payload,
        .parts = parts.items,
        .lookups = try interface_facts.lookupsOf(a, index, &found),
        .files = try embeddedFiles(a, modules[module]),
    };
}

/// The project-relative paths of the files the module's `embed_bytes` and `embed_str` calls name: each literal is relative to
/// the directory of the module. A literal that climbs out of the project is left out (the front end refuses it).
fn embeddedFiles(a: std.mem.Allocator, module: language.project.Module) std.mem.Allocator.Error![]const []const u8 {
    var files: std.ArrayList([]const u8) = .empty;
    const directory = std.fs.path.dirnamePosix(module.src.path) orelse "";
    for (module.src.embeds) |embedded| {
        const joined = if (directory.len == 0) embedded.path else try std.fmt.allocPrint(a, "{s}/{s}", .{ directory, embedded.path });
        const path = (try normalized(a, joined)) orelse continue;
        if (!contains(files.items, path)) try files.append(a, path);
    }
    std.mem.sort([]const u8, files.items, {}, lessThan);
    return files.items;
}

fn contains(list: []const []const u8, path: []const u8) bool {
    for (list) |known| if (std.mem.eql(u8, known, path)) return true;
    return false;
}

/// `path` with `.` and `..` segments resolved, or null when it climbs above its start.
fn normalized(a: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error!?[]const u8 {
    var segments: std.ArrayList([]const u8) = .empty;
    var pieces = std.mem.splitScalar(u8, path, '/');
    while (pieces.next()) |piece| {
        if (piece.len == 0 or std.mem.eql(u8, piece, ".")) continue;
        if (std.mem.eql(u8, piece, "..")) {
            if (segments.items.len == 0) return null;
            _ = segments.pop();
            continue;
        }
        try segments.append(a, piece);
    }
    const joined = try std.mem.join(a, "/", segments.items);
    return joined;
}

test "embedded file paths are resolved against the module's directory and kept inside the project" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("data/table.bin", (try normalized(a, "src/../data/./table.bin")).?);
    try std.testing.expectEqualStrings("src/a/b.txt", (try normalized(a, "src//a/b.txt")).?);
    try std.testing.expectEqual(@as(?[]const u8, null), try normalized(a, "../outside"));
}
