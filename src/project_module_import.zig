//! FR32: a qualifier that names a module file of the project, in a file that does not import it.
//!
//! `util.twice(2)` in a file with no `import util` is refused by whichever pass first meets the name `util`: as an unknown
//! type, an unknown name, an unknown symbol, or a stray `.` after a type's qualifier. None of those passes can see the disk,
//! and the answer depends on it: when `util.selka` is under the import root, `import util` is the repair, as it is for a
//! standard module. The session knows the import root, so it asks here once a check has failed, and a refusal whose
//! qualifier is such a module becomes `E_MODULE_NOT_IMPORTED` carrying the import. A refusal whose qualifier is no module
//! file keeps its own message, and nothing is looked up for a program that checks.
const std = @import("std");
const product = @import("product.zig");
const diagnostic = @import("diagnostic.zig");
const import_fix = @import("import_fix.zig");
const project = @import("project.zig");
const source = @import("source.zig");
const unknown_qualifier = @import("unknown_qualifier.zig");

/// Where the project's module files are looked for: the import root, read through `io`.
pub const Root = struct { io: std.Io, path: []const u8 };

/// The most dotted segments of a qualifier read: `shared.units.area` is three.
const max_segments = 8;
/// How many directories deep, and how many directory entries, the search for a nested module file goes.
const max_depth = 4;
const max_visited = 4000;

/// `items` with each refusal of a qualifier that is a module file of the project, which this file does not import,
/// rewritten as `E_MODULE_NOT_IMPORTED` with the `import` line as its repair. `src` is the source the spans index: a
/// merged project maps each span back to the module that wrote it. Returns `items` itself when none is rewritten.
pub fn explain(allocator: std.mem.Allocator, root: Root, items: []const diagnostic.Diagnostic, src: source.Source) std.mem.Allocator.Error![]const diagnostic.Diagnostic {
    var rewritten: ?[]diagnostic.Diagnostic = null;
    for (items, 0..) |item, at| {
        if (item.severity != .err) continue;
        const start = qualifierStart(item.code, item.message, item.span, src.bytes) orelse continue;
        const anchored = start == item.span.start;
        const named = moduleNamed(allocator, root, src.bytes, start, if (anchored) item.span.end else null) orelse continue;
        if (ownFile(src, item.span, named.module)) continue;
        const edit = import_fix.moduleEdit(allocator, src, item.span, named.module) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InternalError => continue,
        } orelse continue;
        const copy = rewritten orelse try allocator.dupe(diagnostic.Diagnostic, items);
        rewritten = copy;
        // A qualifier written in a type's place was refused at the `.` after it; the import is about the name.
        if (!anchored) copy[at].span = .{ .start = start, .end = start + named.written.len };
        copy[at].code = import_fix.code;
        copy[at].message = try import_fix.unimportedProjectMessage(allocator, named.written, named.module);
        copy[at].provenance.fix = .{ .edit = edit };
    }
    return rewritten orelse items;
}

/// `found`, the project's own refusal (an unknown symbol, or the parser's stop at the `.` after a qualifier in a type's place,
/// alone or among the diagnostics the parser recovered), rewritten the same way when its qualifier is a module file this module
/// does not import. `own` is the problem module's source, which `found.site.span` indexes.
pub fn explainProblem(allocator: std.mem.Allocator, root: Root, found: *project.Problem, own: source.Source) std.mem.Allocator.Error!void {
    if (found.recovered.len != 0) {
        found.recovered = try explain(allocator, root, found.recovered, own);
        return;
    }
    const span = found.site.span;
    const start = qualifierStart(found.code, found.message, span, own.bytes) orelse return;
    const anchored = start == span.start;
    const named = moduleNamed(allocator, root, own.bytes, start, if (anchored) span.end else null) orelse return;
    if (isOwn(own.path, named.module) or import_fix.importsModule(own.bytes, named.module)) return;
    if (!anchored) found.site.span = .{ .start = start, .end = start + named.written.len };
    found.code = import_fix.code;
    found.message = try import_fix.unimportedProjectMessage(allocator, named.written, named.module);
    found.fix = try import_fix.edit(allocator, import_fix.placement(own.bytes, named.module), named.module);
}

/// Where the qualifier a refusal is about starts, or null when the refusal is not one of the four a missing import causes:
/// an unknown type or an unknown name at the qualifier, an unknown symbol of this module at the qualifier, or the `.` after a
/// qualifier written in a type's place, which the parser cannot continue.
fn qualifierStart(code: []const u8, message: []const u8, span: source.Span, bytes: []const u8) ?usize {
    if (span.start >= bytes.len) return null;
    if (std.mem.eql(u8, code, "E_UNKNOWN_TYPE") and (std.mem.eql(u8, message, "type is not declared") or unknown_qualifier.isMessage(message))) return span.start;
    if (std.mem.eql(u8, code, "E_UNKNOWN_NAME") and std.mem.startsWith(u8, message, "name is not defined in this scope")) return span.start;
    if (std.mem.eql(u8, code, "E_UNKNOWN_SYMBOL") and std.mem.startsWith(u8, message, "this module declares no `")) return span.start;
    if (!std.mem.eql(u8, code, "E_SYNTAX") or !std.mem.startsWith(u8, message, "unexpected token")) return null;
    if (bytes[span.start] != '.') return null;
    var start = span.start;
    while (start > 0 and isQualifierByte(bytes[start - 1])) start -= 1;
    return if (start < span.start) start else null;
}

/// Whether `byte` can be part of a dotted qualifier.
fn isQualifierByte(byte: u8) bool {
    return isName(byte) or byte == '.';
}

/// The module a qualifier spells as written and the dotted name its `import` writes: the same for `util.twice(2)`, and
/// `shared.calc` for `calc.f(x)` when the file is `shared/calc.selka`.
const Named = struct { written: []const u8, module: []const u8 };

/// The module file the qualifier at `start` names, under `root`: the longest leading run of segments that is a module,
/// leaving at least the last segment as the member. Failing that, the first segment alone when exactly one file of that
/// name lies in a directory below the root, which `import` reaches by the directory's dotted path. `first_end`, when
/// given, is where the qualifier's first segment must end (the refusal's span).
fn moduleNamed(allocator: std.mem.Allocator, root: Root, bytes: []const u8, start: usize, first_end: ?usize) ?Named {
    var ends: [max_segments]usize = undefined;
    var count: usize = 0;
    var at = start;
    while (count < max_segments and at < bytes.len and (std.ascii.isAlphabetic(bytes[at]) or bytes[at] == '_')) {
        while (at < bytes.len and isName(bytes[at])) at += 1;
        ends[count] = at;
        count += 1;
        if (at + 1 >= bytes.len or bytes[at] != '.') break;
        at += 1;
    }
    if (count < 2) return null;
    if (first_end) |expected| if (ends[0] != expected) return null;
    var length = count - 1;
    while (length > 0) : (length -= 1) {
        const module = bytes[start..ends[length - 1]];
        if (exists(allocator, root, module)) return .{ .written = module, .module = module };
    }
    const leaf = bytes[start..ends[0]];
    const nested = nestedModule(allocator, root, leaf) orelse return null;
    return .{ .written = leaf, .module = nested };
}

/// The dotted name of the one file `leaf.selka` in a directory below the import root, or null when there is none or more than one
/// (a guess between two is no repair). The search stops at `max_depth` directories deep and `max_visited` entries.
fn nestedModule(allocator: std.mem.Allocator, root: Root, leaf: []const u8) ?[]const u8 {
    if (std.mem.endsWith(u8, leaf, "_test")) return null;
    var search: Search = .{ .allocator = allocator, .io = root.io, .file = std.fmt.allocPrint(allocator, "{s}.selka", .{leaf}) catch return null };
    search.directory(root.path, "", 1);
    return if (search.matches == 1) search.found else null;
}

/// A walk of the directories below the import root for the one file of a given name.
const Search = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    file: []const u8,
    found: []const u8 = "",
    matches: usize = 0,
    visited: usize = 0,

    /// Look in `path`, whose dotted name is `prefix`, and in the module-named directories below it.
    fn directory(self: *Search, path: []const u8, prefix: []const u8, depth: usize) void {
        var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true, .follow_symlinks = false }) catch return;
        defer dir.close(self.io);
        var iterator = dir.iterate();
        while (iterator.next(self.io) catch return) |item| {
            self.visited += 1;
            if (self.visited > max_visited or self.matches > 1) return;
            if (item.kind == .file and depth > 1 and std.mem.eql(u8, item.name, self.file)) {
                const stem = product.chopSource(self.file);
                self.found = std.fmt.allocPrint(self.allocator, "{s}{s}", .{ prefix, stem }) catch return;
                self.matches += 1;
            }
            if (item.kind != .directory or depth >= max_depth or !project.validName(item.name)) continue;
            const below = std.fs.path.join(self.allocator, &.{ path, item.name }) catch return;
            const dotted = std.fmt.allocPrint(self.allocator, "{s}{s}.", .{ prefix, item.name }) catch return;
            self.directory(below, dotted, depth + 1);
        }
    }
};

/// Whether the module `name` is a file under the import root.
fn exists(allocator: std.mem.Allocator, root: Root, name: []const u8) bool {
    const relative = project.modulePath(allocator, name) catch return false;
    const full = std.fs.path.join(allocator, &.{ root.path, relative }) catch return false;
    std.Io.Dir.cwd().access(root.io, full, .{}) catch return false;
    return true;
}

/// Whether `module` is the file the refused span is written in: a file does not import itself.
fn ownFile(src: source.Source, span: source.Span, module: []const u8) bool {
    const mapped = src.origins.len != 0;
    const input = if (mapped) (src.originalSpan(span) catch return true).input else 0;
    return isOwn(if (mapped) src.origins[input].original.path else src.path, module);
}

/// Whether the file at `path` is the one `module` names, by its last segment: a file does not import itself.
fn isOwn(path: []const u8, module: []const u8) bool {
    const last = std.mem.lastIndexOfScalar(u8, module, '.');
    return std.mem.eql(u8, std.fs.path.stem(path), if (last) |dot| module[dot + 1 ..] else module);
}

/// Whether `byte` can continue a name.
fn isName(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}
