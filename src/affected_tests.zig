//! `selka test --affected`: select only the tests that reach a declaration
//! whose own source lines changed since a reference revision.
//!
//! The derivation costs one `git diff` and a line scan of the changed files, no
//! compilation of its own. The changed lines are mapped onto the top-level
//! declarations of each changed module by indentation alone — a declaration
//! runs from its column-0 header to the next column-0 line — and yield
//! qualified `module::name` changes. A changed line outside every function or
//! constant (an import, a record, a domain, the module header) conservatively
//! changes the whole module. The runner then keeps a test only when the
//! dependency closure it already derived for the test's receipt reaches a
//! changed name, so the selection reuses the checked facts the run builds
//! anyway instead of checking the project a second time.
const std = @import("std");
const ref_diff = @import("ref_diff.zig");

/// Failures a derivation reports: allocation, a reference `git` cannot resolve,
/// or an entry that is not a selka source.
pub const Error = error{ OutOfMemory, GitFailed, InvalidEntry };

/// One derivation's inputs. `git_root` is the entry's own directory in the
/// user's repository, the root every project module path is relative to.
pub const Request = struct {
    memory: std.mem.Allocator,
    io: std.Io,
    git_root: []const u8,
    entry: []const u8,
    reference: []const u8,
};

/// The declarations changed since the reference.
pub const Changes = struct {
    /// Qualified `module::name` functions and constants whose lines changed.
    names: []const []const u8,
    /// Modules whose non-function lines changed: every declaration in them
    /// counts as changed.
    modules: []const []const u8,

    /// Whether one checked function's qualified name is a changed declaration:
    /// the name itself, a generic specialization of it, or any name in a
    /// wholly changed module.
    pub fn reaches(self: Changes, name: []const u8) bool {
        const separator = std.mem.indexOf(u8, name, "::") orelse return false;
        for (self.modules) |module| {
            if (std.mem.eql(u8, name[0..separator], module)) return true;
        }
        for (self.names) |changed| {
            if (!std.mem.startsWith(u8, name, changed)) continue;
            if (name.len == changed.len or name[changed.len] == '[') return true;
        }
        return false;
    }
};

/// The derivation's verdict over the discovered tests, in discovery order.
pub const Selection = struct {
    /// One flag per discovered test: true keeps it in the run.
    keep: []const bool,
    /// Qualified names of the tests dropped as unaffected.
    skipped: []const []const u8,
};

/// The declarations changed since `request.reference`, or `GitFailed` for a
/// revision `git` cannot diff. A changed file that cannot be read changes its
/// whole module.
pub fn changes(request: Request) Error!Changes {
    if (!std.mem.endsWith(u8, request.entry, ".selka")) return error.InvalidEntry;
    const allocator = request.memory;
    const files = try ref_diff.changedModules(allocator, request.io, request.git_root, request.reference);
    var names: std.ArrayList([]const u8) = .empty;
    var modules: std.ArrayList([]const u8) = .empty;
    for (files) |file| {
        const path = try std.fs.path.join(allocator, &.{ request.git_root, file.path });
        const text = std.Io.Dir.cwd().readFileAlloc(request.io, path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                try modules.append(allocator, try pathModule(allocator, file.path));
                continue;
            },
        };
        const module = try moduleName(allocator, text, file.path);
        if (try scanModule(allocator, .{ .text = text, .module = module, .ranges = file.ranges }, &names)) try modules.append(allocator, module);
    }
    return .{ .names = try names.toOwnedSlice(allocator), .modules = try modules.toOwnedSlice(allocator) };
}

/// A module's declared name from its `module` header, or the name its path
/// implies for a header-less entry (`a/b.selka` is `a.b`).
fn moduleName(allocator: std.mem.Allocator, text: []const u8, path: []const u8) std.mem.Allocator.Error![]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (!std.mem.startsWith(u8, line, "module ")) break;
        return allocator.dupe(u8, std.mem.trim(u8, line["module ".len..], " \t"));
    }
    return pathModule(allocator, path);
}

fn pathModule(allocator: std.mem.Allocator, path: []const u8) std.mem.Allocator.Error![]const u8 {
    const stem = if (std.mem.endsWith(u8, path, ".selka")) path[0 .. path.len - ".selka".len] else path;
    const name = try allocator.dupe(u8, stem);
    std.mem.replaceScalar(u8, name, '/', '.');
    return name;
}

/// One changed module: its source, its name and the one-based lines changed.
const Scan = struct { text: []const u8, module: []const u8, ranges: []const ref_diff.LineRange };

/// One top-level block: the zero-based lines it spans and the function or
/// constant it declares, or null for anything else.
const Block = struct { first: usize, last: usize, name: ?[]const u8 };

/// Append each changed function or constant of one module as `module::name`
/// and answer whether a change touched a line no such declaration owns.
fn scanModule(allocator: std.mem.Allocator, scan: Scan, names: *std.ArrayList([]const u8)) std.mem.Allocator.Error!bool {
    var blocks: std.ArrayList(Block) = .empty;
    defer blocks.deinit(allocator);
    var current: Block = .{ .first = 0, .last = 0, .name = null };
    var pending_attribute = false;
    var lines = std.mem.splitScalar(u8, scan.text, '\n');
    var number: usize = 0;
    while (lines.next()) |line| : (number += 1) {
        current.last = number;
        if (!opensBlock(line)) continue;
        // An attribute opens the block of the declaration it decorates.
        if (pending_attribute) {
            if (line[0] != '@') {
                current.name = declared(line);
                pending_attribute = false;
            }
            continue;
        }
        if (number != 0) {
            current.last = number - 1;
            try blocks.append(allocator, current);
        }
        current = .{ .first = number, .last = number, .name = if (line[0] == '@') null else declared(line) };
        pending_attribute = line[0] == '@';
    }
    try blocks.append(allocator, current);
    var whole = false;
    for (scan.ranges) |range| {
        const first = range.start - 1;
        const last = first + range.len - 1;
        var owned = false;
        for (blocks.items) |block| {
            if (block.last < first or block.first > last) continue;
            owned = true;
            const name = block.name orelse {
                whole = true;
                continue;
            };
            try names.append(allocator, try std.fmt.allocPrint(allocator, "{s}::{s}", .{ scan.module, name }));
        }
        if (!owned) whole = true;
    }
    return whole;
}

/// Whether a line starts a top-level block: it has content at column 0 that is
/// not a comment. Blank, indented and comment lines belong to the open block.
fn opensBlock(line: []const u8) bool {
    if (line.len == 0) return false;
    return std.mem.indexOfScalar(u8, " \t\r#", line[0]) == null;
}

/// The function or constant a column-0 header declares, or null for any other
/// declaration.
fn declared(header: []const u8) ?[]const u8 {
    var line = std.mem.trimEnd(u8, header, " \t\r");
    for ([_][]const u8{ "public ", "host ", "extern " }) |prefix| {
        if (std.mem.startsWith(u8, line, prefix)) line = std.mem.trimStart(u8, line[prefix.len..], " \t");
    }
    const rest = if (std.mem.startsWith(u8, line, "func "))
        line["func ".len..]
    else if (std.mem.startsWith(u8, line, "const "))
        line["const ".len..]
    else
        return null;
    const name = std.mem.trimStart(u8, rest, " \t");
    const end = std.mem.indexOfAny(u8, name, "([: =\t") orelse name.len;
    return if (end == 0) null else name[0..end];
}

// spec: AFFECTED-TEST-2
test "a changed line maps to the top-level declaration that owns it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const text = "import util\n\n\nfunc helper(value: int) -> int:\n    return value + 1\n\n\n@test\nfunc checks() -> bool:\n    return True\n\n\npublic const LIMIT: int = 3\n\n\nrecord Point:\n    x: int\n";
    var names: std.ArrayList([]const u8) = .empty;
    // A body line changes its function, an attribute its declaration, a
    // constant itself.
    try std.testing.expect(!try scanModule(allocator, .{ .text = text, .module = "app", .ranges = &.{.{ .start = 5, .len = 1 }} }, &names));
    try std.testing.expect(!try scanModule(allocator, .{ .text = text, .module = "app", .ranges = &.{.{ .start = 9, .len = 1 }} }, &names));
    try std.testing.expect(!try scanModule(allocator, .{ .text = text, .module = "app", .ranges = &.{.{ .start = 13, .len = 1 }} }, &names));
    try std.testing.expectEqual(@as(usize, 3), names.items.len);
    try std.testing.expectEqualStrings("app::helper", names.items[0]);
    try std.testing.expectEqualStrings("app::checks", names.items[1]);
    try std.testing.expectEqualStrings("app::LIMIT", names.items[2]);
    // An import or a record changes the whole module.
    try std.testing.expect(try scanModule(allocator, .{ .text = text, .module = "app", .ranges = &.{.{ .start = 2, .len = 1 }} }, &names));
    try std.testing.expect(try scanModule(allocator, .{ .text = text, .module = "app", .ranges = &.{.{ .start = 17, .len = 1 }} }, &names));
    const changed: Changes = .{ .names = names.items, .modules = &.{"util"} };
    try std.testing.expect(changed.reaches("app::helper"));
    try std.testing.expect(changed.reaches("app::helper[int]"));
    try std.testing.expect(!changed.reaches("app::helper_two"));
    try std.testing.expect(changed.reaches("util::anything"));
    try std.testing.expect(!changed.reaches("other::helper"));
    try std.testing.expectEqualStrings("a.b", try moduleName(allocator, "func main() -> int:\n    return 0\n", "a/b.selka"));
    try std.testing.expectEqualStrings("renamed", try moduleName(allocator, text, "renamed.selka"));
}
