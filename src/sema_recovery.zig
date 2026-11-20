//! Statement recovery inside one function body (F-RC-214): a statement that fails to check reports its error, and checking
//! goes on with the next statement, so a body's independent errors are reported in one run. What the failed statement would
//! have bound or assigned is unknown afterwards, so its names are poisoned: a later statement that fails and mentions one of
//! them is taken to fail because of the first error, and its diagnostics are dropped. A block in which a statement failed
//! fails itself once its last statement is checked, so the checks that close a compound statement (its flow, its pending
//! results, its definite assignments) never judge a statement that did not check. At most `limit` failed statements of one
//! function are reported; the function's check then stops as it did at the first one before.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const import_fix = @import("import_fix.zig");

/// The failed statements one function reports at most.
pub const limit = 20;

/// The recovery state of the function being checked; `reset` starts a function.
pub const State = struct {
    /// Failed statements whose diagnostics this function reports.
    kept: u16 = 0,
    /// Whether a statement of this function failed and checking went on.
    recovered: bool = false,
    /// Whether the function reached `limit`: its check stops, and no enclosing statement resumes it.
    stopped: bool = false,
    /// Set when a block fails because one of its statements failed: the enclosing statement's failure is that one, whose
    /// diagnostics are already judged.
    nested: bool = false,
    /// Names a failed statement binds or assigns.
    poisoned: std.ArrayList([]const u8) = .empty,
    /// The sink's length once the function's first failed statement had reported: where its check used to stop.
    cutoff: ?usize = null,

    /// Forget the previous function's recovery.
    pub fn reset(self: *State) void {
        self.kept = 0;
        self.recovered = false;
        self.stopped = false;
        self.nested = false;
        self.poisoned.clearRetainingCapacity();
        self.cutoff = null;
    }
};

/// Statement `id` failed, with its diagnostics at `before..` of the sink: whether checking goes on with the next statement.
/// A failure that mentions a poisoned name loses its diagnostics; any other is kept and counted.
pub fn resumeAfter(comptime Checker: type, self: *Checker, id: ast.StatementId, before: usize) Error!bool {
    const state = &self.recovery;
    const nested = state.nested;
    state.nested = false;
    if (state.stopped) return false;
    if (!nested) {
        // Past the limit the function's check stops, as it stopped at its first error before, without this failure.
        if (state.kept >= limit) {
            self.sink.items.shrinkRetainingCapacity(before);
            state.stopped = true;
            return false;
        }
        const text = self.src.text(self.syntax.statements.items[@backingInt(id)].span);
        if (state.recovered and mentions(text, state.poisoned.items)) {
            self.sink.items.shrinkRetainingCapacity(before);
        } else if (!repeats(self.sink.items.items, before)) {
            state.kept += 1;
        } else self.sink.items.shrinkRetainingCapacity(before);
    }
    if (!state.recovered) state.cutoff = self.sink.items.items.len;
    state.recovered = true;
    try poison(Checker, self, id);
    return true;
}

/// A block one of whose statements failed ends here: it fails, and its enclosing statement fails with it.
pub fn failBlock(comptime Checker: type, self: *Checker) Error {
    self.recovery.nested = true;
    return error.SourceError;
}

/// Close the task handles a failed block declared at or after `first_local` without judging them: the statement that would
/// have read a handle may be the one that failed.
pub fn dropHandles(comptime Checker: type, self: *Checker, first_local: usize) void {
    var kept: usize = 0;
    for (self.tasks.handles.items) |held| {
        if (@backingInt(held.slot) >= first_local) continue;
        self.tasks.handles.items[kept] = held;
        kept += 1;
    }
    self.tasks.handles.shrinkRetainingCapacity(kept);
}

/// After a failed function's check: drop what the statements after its first failed statement reported other than errors,
/// so a body with one error reports what it reported when its check stopped at that error.
pub fn trimFailed(sink: *diagnostic.Sink, state: State) void {
    const cutoff = state.cutoff orelse return;
    const items = sink.items.items;
    if (cutoff > items.len) return;
    var kept = cutoff;
    for (items[cutoff..]) |item| {
        if (item.severity != .err) continue;
        items[kept] = item;
        kept += 1;
    }
    sink.items.shrinkRetainingCapacity(kept);
}

const Error = diagnostic.Error;

/// Whether the failed statement's new diagnostics only repeat ones already reported (a body a loop checks again).
fn repeats(items: []const diagnostic.Diagnostic, before: usize) bool {
    if (items.len == before) return false;
    for (items[before..]) |item| {
        if (item.severity != .err) continue;
        if (!diagnostic.holds(items[0..before], item)) return false;
    }
    return true;
}

/// Record the names statement `id` and the statements nested in it bind or assign.
fn poison(comptime Checker: type, self: *Checker, id: ast.StatementId) Error!void {
    var work: std.ArrayList(ast.StatementId) = .empty;
    defer work.deinit(self.allocator);
    try work.append(self.allocator, id);
    while (work.pop()) |next| {
        const statement = self.syntax.statements.items[@backingInt(next)];
        const name = switch (statement.data) {
            .binding => |binding| binding.name,
            .assignment => |assignment| assignment.name,
            else => null,
        };
        if (name) |span| if (span.start < span.end) try self.recovery.poisoned.append(self.allocator, self.src.text(span));
        try ast.appendNested(self.allocator, &work, statement);
    }
}

/// A failed statement that reported a missing standard-module import hides the ones after it in the same statement: the
/// refusal ends the statement's check, so `print(out, hex.encode(b"hi"), bytes.find(b"abc", b"c"))` names `hex` and leaves
/// `bytes` for a second check, and `selka fix` takes a second round for it (FR28). This reads the rest of the statement's
/// first logical line for the other `module.name` qualifiers and reports each standard module the file does not import, with
/// its import line, as the first refusal did. A qualifier counts only when no local, declaration or import of the file binds
/// its name, the rule the refusal itself follows, and only a statement that holds no block is read (`ast.appendNested`).
pub fn siblingImports(comptime Checker: type, self: *Checker, id: ast.StatementId, before: usize) Error!void {
    if (before >= self.sink.items.items.len or !reported(self.sink.items.items[before..])) return;
    const statement = self.syntax.statements.items[@backingInt(id)];
    var nested: std.ArrayList(ast.StatementId) = .empty;
    defer nested.deinit(self.allocator);
    try ast.appendNested(self.allocator, &nested, statement);
    if (nested.items.len != 0) return;
    const text = self.src.text(statement.span);
    var from: usize = 0;
    while (nextQualifier(text, from)) |found| : (from = found.end) {
        const name = text[found.start..found.end];
        if (!import_fix.standardModule(name) or self.active.contains(name) or self.functions.contains(name)) continue;
        const span: @import("source.zig").Span = .{ .start = statement.span.start + @as(u32, @intCast(found.start)), .end = statement.span.start + @as(u32, @intCast(found.end)) };
        if (self.catalog.module_names) |names| if (try names.topLevel(span)) continue;
        const edit = (try import_fix.moduleEdit(self.allocator, self.src, span, name)) orelse continue;
        const item: diagnostic.Diagnostic = .{ .code = import_fix.code, .span = span, .message = try import_fix.unimportedMessage(self.allocator, name) };
        if (diagnostic.holds(self.sink.items.items[before..], item)) continue;
        try self.sink.appendFix(item, edit);
    }
}

/// Whether one of the diagnostics is the refusal of a standard module the file does not import.
fn reported(items: []const diagnostic.Diagnostic) bool {
    for (items) |item| if (item.severity == .err and std.mem.eql(u8, item.code, import_fix.code)) return true;
    return false;
}

/// The next identifier at or after `from` in the first logical line of `text` that is followed by `.` and a name and is not
/// itself a member (`record.hex.size`), skipping text and bytes literals and comments. The line ends at the first newline
/// outside brackets and literals, so the body of a block a statement carries is never read.
fn nextQualifier(text: []const u8, from: usize) ?struct { start: usize, end: usize } {
    var depth: usize = 0;
    var at: usize = 0;
    while (at < text.len) {
        const byte = text[at];
        if (byte == '\n' and depth == 0) return null;
        if (byte == '#' or byte == '"' or byte == '\'') {
            at = skipLiteral(text, at);
            continue;
        }
        if (byte == '(' or byte == '[' or byte == '{') depth += 1;
        if ((byte == ')' or byte == ']' or byte == '}') and depth > 0) depth -= 1;
        if (!std.ascii.isAlphabetic(byte) and byte != '_') {
            at += 1;
            continue;
        }
        const start = at;
        while (at < text.len and identifierByte(text[at])) at += 1;
        const member = start > 0 and text[start - 1] == '.';
        const word = at + 1 < text.len and text[at] == '.' and (std.ascii.isAlphabetic(text[at + 1]) or text[at + 1] == '_');
        if (start >= from and word and !member) return .{ .start = start, .end = at };
    }
    return null;
}

/// The offset just past the comment, text literal or bytes literal that starts at `at` (a triple-quoted literal ends at its
/// closing triple, any other one at its closing quote or the end of its line).
fn skipLiteral(text: []const u8, at: usize) usize {
    const byte = text[at];
    if (byte == '#') return std.mem.indexOfScalarPos(u8, text, at, '\n') orelse text.len;
    const triple = at + 2 < text.len and text[at + 1] == byte and text[at + 2] == byte;
    var cursor = at + if (triple) @as(usize, 3) else 1;
    while (cursor < text.len) : (cursor += 1) {
        if (text[cursor] == '\\') {
            cursor += 1;
        } else if (triple and std.mem.startsWith(u8, text[cursor..], text[at .. at + 3])) {
            return cursor + 3;
        } else if (!triple and text[cursor] == byte) {
            return cursor + 1;
        } else if (!triple and text[cursor] == '\n') {
            return cursor;
        }
    }
    return text.len;
}

/// Whether `text` holds one of `names` as a whole identifier.
fn mentions(text: []const u8, names: []const []const u8) bool {
    for (names) |name| {
        var from: usize = 0;
        while (std.mem.indexOfPos(u8, text, from, name)) |at| : (from = at + 1) {
            const before_ok = at == 0 or !identifierByte(text[at - 1]);
            const end = at + name.len;
            const after_ok = end == text.len or !identifierByte(text[end]);
            if (before_ok and after_ok) return true;
        }
    }
    return false;
}

fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

test "a poisoned name is found only as a whole identifier" {
    try std.testing.expect(mentions("total = total + 1", &.{"total"}));
    try std.testing.expect(!mentions("subtotal = 1", &.{"total"}));
    try std.testing.expect(!mentions("total_x = 1", &.{"total"}));
    try std.testing.expect(mentions("f(x.total)", &.{"total"}));
}

test "the qualifiers of a statement's first logical line are read outside literals, comments, members and blocks" {
    const text = "print(out, hex.encode(b\"bytes.x\"), rec.time.zone, bytes.find(a,\n  b)) # lists.x\n    strings.upper(x)";
    const first = nextQualifier(text, 0).?;
    try std.testing.expectEqualStrings("hex", text[first.start..first.end]);
    const second = nextQualifier(text, first.end).?;
    try std.testing.expectEqualStrings("rec", text[second.start..second.end]);
    const third = nextQualifier(text, second.end).?;
    try std.testing.expectEqualStrings("bytes", text[third.start..third.end]);
    try std.testing.expect(nextQualifier(text, third.end) == null);
    try std.testing.expect(nextQualifier("x = 3.5 + y", 0) == null);
}
