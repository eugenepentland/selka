//! Which published fix edits one `selka fix` round applies. A fix is all of
//! one diagnostic's edits; a round takes every fix whose edits collide with no
//! edit already taken, leaves a colliding fix for the next round (which sees
//! the updated file), and withholds a fix whose own edits overlap one another,
//! because no order of applying them is sound (FIX-MIGRATION-OVERLAP-1). The one
//! exception to "colliding edits wait" is the `import` lines of a file that calls
//! several standard modules it does not import: each such fix inserts at the point
//! where its line belongs in the sorted directive block, so two modules that belong
//! at one point would collide and cost a round each. Their insertions at one point
//! are merged into one, in the order the block keeps (FR28).
//! The other exception is `W_COPY_RETURNED`, whose fix is taken only in a round that takes no other fix (`select`).
const std = @import("std");
/// The code whose fix inserts an `import` line (`import_fix.code` in the front end, which this file does not import).
const import_code = "E_MODULE_NOT_IMPORTED";

/// One edit a child check published, with its file resolved to an absolute path.
pub const Edit = struct { path: []const u8, start: usize, end: usize, text: []const u8 };
/// One diagnostic's fix: all of its edits apply together or not at all. `warning` is whether the diagnostic's severity is
/// `warning`, which a run on one named file leaves alone unless it is given `--warnings` (`fix_command.zig`).
pub const Fix = struct { code: []const u8, edits: []const Edit, warning: bool = false };
/// One edit a round applies and the diagnostic code whose fix it belongs to.
pub const Planned = struct { code: []const u8, edit: Edit };
/// One round's decision: the distinct edits to apply, and the fixes withheld
/// because their own edits overlap.
pub const Plan = struct { chosen: []const Planned, withheld: []const Fix };

/// The code whose fix declares a function's result `from` a parameter (`copy_from_repair.code` in the front end, which this file
/// does not import). It is judged against the callers as they are written now, so it waits for a round no other fix is in.
const from_code = "W_COPY_RETURNED";

/// Choose one round's edits from the fixes a check published, in order. An
/// edit identical to a chosen one (the same repair reported twice, as a
/// generic function's instances do) is a duplicate, not a collision, and is
/// applied once. A `W_COPY_RETURNED` fix is chosen only when no other fix is:
/// another repair of the same round may rewrite a caller so that it takes the
/// result, which the fix's judge did not see, and the next round's check judges
/// it again against the callers as they then are.
pub fn select(allocator: std.mem.Allocator, fixes: []const Fix) std.mem.Allocator.Error!Plan {
    var taken: std.ArrayList(Planned) = .empty;
    var withheld: std.ArrayList(Fix) = .empty;
    var last: std.ArrayList(Fix) = .empty;
    for (fixes) |fix| {
        if (std.mem.eql(u8, fix.code, from_code)) try last.append(allocator, fix) else try choose(allocator, fix, &taken, &withheld);
    }
    if (taken.items.len == 0) for (last.items) |fix| try choose(allocator, fix, &taken, &withheld);
    return .{ .chosen = taken.items, .withheld = withheld.items };
}

/// Take `fix` into the round's edits, withhold it when its own edits overlap, or leave it for the next round when it collides.
fn choose(allocator: std.mem.Allocator, fix: Fix, taken: *std.ArrayList(Planned), withheld: *std.ArrayList(Fix)) std.mem.Allocator.Error!void {
    if (selfOverlapping(fix)) return withheld.append(allocator, fix);
    if (try mergedImport(allocator, fix, taken.items)) return;
    if (collides(fix, taken.items)) return;
    for (fix.edits) |edit| {
        const seen = for (taken.items) |other| {
            if (same(edit, other.edit)) break true;
        } else false;
        if (!seen) try taken.append(allocator, .{ .code = fix.code, .edit = edit });
    }
}

/// Fold the import line `fix` inserts into the chosen insertion of import lines at the same point of the same file, when there
/// is one: the fixes of `E_MODULE_NOT_IMPORTED` for several modules a file does not import, each placed by the front end's
/// `import_fix.placement` at its slot in the sorted block, so every module that belongs before the same existing line (or after
/// the last one) names the same offset. The merged text is the lines of both, sorted by module name and without repeats, with
/// the one blank line that separates the block from the declarations when either had it: the layout the formatter keeps, so
/// the round leaves a file that is already formatted. Returns whether `fix` was taken in; a fix that is no import insertion,
/// or finds none to join, is left to `collides`.
fn mergedImport(allocator: std.mem.Allocator, fix: Fix, taken: []Planned) std.mem.Allocator.Error!bool {
    if (!std.mem.eql(u8, fix.code, import_code) or fix.edits.len != 1) return false;
    const edit = fix.edits[0];
    if (edit.start != edit.end or !directives(edit.text)) return false;
    for (taken) |*other| {
        if (!std.mem.eql(u8, other.code, import_code) or other.edit.start != other.edit.end or other.edit.start != edit.start) continue;
        if (!std.mem.eql(u8, other.edit.path, edit.path) or !directives(other.edit.text)) continue;
        other.edit.text = try joinDirectives(allocator, other.edit.text, edit.text);
        return true;
    }
    return false;
}

/// Whether `text` is only `import NAME` lines, optionally followed by one blank line: what `import_fix.edit` writes.
fn directives(text: []const u8) bool {
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, text, "\n"), '\n');
    var any = false;
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "import ") or line.len == "import ".len) return false;
        if (std.mem.indexOfAny(u8, line["import ".len..], " \t;") != null) return false;
        any = true;
    }
    return any;
}

/// The `import` lines of two insertions, sorted by module name (bytewise, as `import_fix.placement` orders them) and joined
/// without repeats; the blank line after the block stays when either insertion ended with one.
fn joinDirectives(allocator: std.mem.Allocator, first: []const u8, second: []const u8) std.mem.Allocator.Error![]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(allocator);
    for ([_][]const u8{ first, second }) |text| {
        var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, text, "\n"), '\n');
        while (lines.next()) |line| {
            const name = line["import ".len..];
            const known = for (names.items) |other| {
                if (std.mem.eql(u8, other, name)) break true;
            } else false;
            if (!known) try names.append(allocator, name);
        }
    }
    std.mem.sort([]const u8, names.items, {}, nameBefore);
    var out: std.ArrayList(u8) = .empty;
    for (names.items) |name| try out.print(allocator, "import {s}\n", .{name});
    if (std.mem.endsWith(u8, first, "\n\n") or std.mem.endsWith(u8, second, "\n\n")) try out.append(allocator, '\n');
    return out.items;
}

fn nameBefore(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

/// The fixes `onlyIn` left out: how many have an edit outside the file, and how many other files hold their edits.
pub const Elsewhere = struct { fixes: usize = 0, files: usize = 0 };
/// The fixes of one file and what is left in the others.
pub const OnlyIn = struct { own: []const Fix, elsewhere: Elsewhere };

/// The fixes whose edits all lie in `file`, and a count of the rest. A fix with an edit in another file is not applied, nor split:
/// half of a rename that follows a type into its importers would leave both files wrong, so it waits whole.
pub fn onlyIn(allocator: std.mem.Allocator, file: []const u8, fixes: []const Fix) std.mem.Allocator.Error!OnlyIn {
    var own: std.ArrayList(Fix) = .empty;
    var others: std.StringHashMapUnmanaged(void) = .empty;
    var left: usize = 0;
    for (fixes) |fix| {
        var elsewhere = false;
        for (fix.edits) |edit| if (!std.mem.eql(u8, edit.path, file)) {
            elsewhere = true;
            try others.put(allocator, edit.path, {});
        };
        if (elsewhere) left += 1 else try own.append(allocator, fix);
    }
    return .{ .own = own.items, .elsewhere = .{ .fixes = left, .files = others.count() } };
}

/// The fixes left after those with an edit in one of the `skipped` files are set aside, and the ones set aside.
pub const WithoutFiles = struct { kept: []const Fix, set_aside: []const Fix };

/// Split `fixes` by the files in `skipped`: a fix with any edit in such a file is set aside whole, never trimmed to its
/// other edits, for the reason `onlyIn` gives (half a rename leaves both files wrong). A fix is a generated file's when
/// its edit would rewrite bytes a generator writes again (`selka fix` leaves such a file alone).
pub fn withoutFiles(allocator: std.mem.Allocator, fixes: []const Fix, skipped: *const std.StringHashMapUnmanaged(void)) std.mem.Allocator.Error!WithoutFiles {
    var kept: std.ArrayList(Fix) = .empty;
    var set_aside: std.ArrayList(Fix) = .empty;
    for (fixes) |fix| {
        const hits = for (fix.edits) |edit| {
            if (skipped.contains(edit.path)) break true;
        } else false;
        try (if (hits) set_aside else kept).append(allocator, fix);
    }
    return .{ .kept = kept.items, .set_aside = set_aside.items };
}

/// Whether two different edits of `fix` itself overlap.
fn selfOverlapping(fix: Fix) bool {
    for (fix.edits, 0..) |edit, index| for (fix.edits[index + 1 ..]) |other| {
        if (!same(edit, other) and overlaps(edit, other)) return true;
    };
    return false;
}

/// Whether any edit of `fix` overlaps a different edit already taken.
fn collides(fix: Fix, taken: []const Planned) bool {
    for (fix.edits) |edit| for (taken) |other| {
        if (!same(edit, other.edit) and overlaps(edit, other.edit)) return true;
    };
    return false;
}

fn same(a: Edit, b: Edit) bool {
    return a.start == b.start and a.end == b.end and std.mem.eql(u8, a.path, b.path) and std.mem.eql(u8, a.text, b.text);
}

/// Whether two different edits of one file touch the same bytes or the same
/// insertion point, where applying both would depend on their order.
fn overlaps(a: Edit, b: Edit) bool {
    if (!std.mem.eql(u8, a.path, b.path)) return false;
    if (a.start == b.start) return true;
    return a.start < b.end and b.start < a.end;
}

/// A source file that does not parse, and the module names its `import` lines give.
pub const Unparsed = struct { path: []const u8, imports: []const []const u8 };

/// The codes whose fix renames a declaration together with every qualified reference to it in the modules that import it.
pub const renames = [_][]const u8{ "E_BUILTIN_FUNCTION_NAME", "E_BUILTIN_TYPE_NAME" };

/// Whether `code` is one of the diagnostics whose fix is a rename that follows its declaration into the modules importing it.
pub fn isRename(code: []const u8) bool {
    for (renames) |name| {
        if (std.mem.eql(u8, code, name)) return true;
    }
    return false;
}

/// Why a rename waits: the file that does not parse, and the name it imports the rename's edited module by.
pub const Block = struct { file: Unparsed, module: []const u8 };

/// The file that does not parse and may call what `fix` renames: `fix` is a rename (`renames`), one of its edited files is a
/// module an unparsed file imports, and the unparsed file is not itself edited. Its qualified calls cannot be renamed with the
/// declaration, so applying the rename would leave them naming something that is gone; null when no unparsed file is in the way.
/// A module is known by the last segment of its dotted name, so this is conservative about two modules with one stem.
pub fn blockedBy(fix: Fix, unparsed: []const Unparsed) ?Block {
    if (!isRename(fix.code)) return null;
    for (unparsed) |file| for (fix.edits) |edit| {
        if (std.mem.eql(u8, edit.path, file.path)) continue;
        const stem = std.fs.path.stem(edit.path);
        for (file.imports) |name| {
            const last = name[if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| dot + 1 else 0..];
            if (std.mem.eql(u8, last, stem)) return .{ .file = file, .module = name };
        }
    };
    return null;
}
