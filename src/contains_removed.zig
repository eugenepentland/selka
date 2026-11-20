//! The refusal of the removed `.contains(value)` method, worded for the receiver it was called on (FR19).
//!
//! `seen.contains(name)` used to answer for a dictionary, a set, text, bytes and a list. The one refusal said "removed for
//! dictionaries; use `key in mapping`", which is false for a list (it has no `in`) and named the wrong type for the rest.
//! Each receiver type now gets its own sentence, naming the call as written and the spelling that replaces it, and the
//! repair is offered where it is certain: `name in seen` for a dictionary, a set, text or bytes, and
//! `lists.contains(values, name)` with its `import` for a list. The checker's three places that reach the method (a local
//! receiver, an expression receiver, a text constant) and the generic body check call `refuse` with what they know.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const import_fix = @import("import_fix.zig");
const removed_names = @import("removed_names.zig");
const repetition = @import("repetition.zig");
const runtime_values = @import("runtime_values.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");

/// The method this module answers for.
pub const method = "contains";

/// The receiver type the method was called on.
pub const Receiver = enum { dictionary, set, text, bytes, list };

/// The receiver kind of a checked type, or null when the type is no collection the method ever reached.
pub fn receiverOf(records: []const typed.Record, ty: typed.Type) ?Receiver {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const record = records[ty.recordIndex()];
    if (!record.isCollection()) return null;
    return fromKind(record.collection.kind, typed.isSet(record));
}

/// The receiver kind of a managed collection family, `set` telling a set from a dictionary (they share a family).
pub fn fromKind(kind: runtime_values.ManagedKind, set: bool) Receiver {
    return switch (kind) {
        .list => .list,
        .dictionary => if (set) .set else .dictionary,
        .string => .text,
        .bytes => .bytes,
    };
}

/// What the call is: the whole `receiver.contains(argument)`, its receiver, and the one positional argument when it has
/// exactly that (null for any other arity or a named argument, which are worded with placeholders and offer no repair).
pub const Call = struct {
    /// The method's name, where the diagnostic is, as the removed spelling always was.
    name: source.Span,
    call: source.Span,
    receiver: source.Span,
    argument: ?source.Span,
};

/// Refuse `contains` called on a `kind` receiver with the sentence for that type and, where the edit is certain, its repair.
/// The edit swaps the operands (`seen.contains(name)` reads the receiver first, `name in seen` the name first), so it is
/// offered when the receiver is a plain read (a name or fields of one, which cannot trap or change) and the argument names
/// no `mut` or `own` place, the only spellings by which evaluating it could change what the receiver reads (the rule of
/// list membership, F-25: `repetition.swapCertain`).
pub fn refuse(allocator: std.mem.Allocator, src: source.Source, sink: *diagnostic.Sink, kind: Receiver, found: Call) diagnostic.Error {
    const receiver = src.text(found.receiver);
    const argument: ?[]const u8 = if (found.argument) |span| src.text(span) else null;
    const sketch = placeholders(kind);
    const call_text = src.text(found.call);
    const written: []const u8 = if (argument != null and call_text.len <= 60 and std.mem.indexOfScalar(u8, call_text, '\n') == null)
        call_text
    else
        try std.fmt.allocPrint(allocator, ".contains({s})", .{sketch.needle});
    // The argument as it stands before `in`: parenthesized when it binds looser (`(a and b) in seen`).
    const needle_text: []const u8 = if (argument) |text| (if (kind != .list and bindsLooser(text)) try std.fmt.allocPrint(allocator, "({s})", .{text}) else text) else sketch.needle;
    const receiver_text: []const u8 = if (argument != null and receiver.len <= 40 and std.mem.indexOfScalar(u8, receiver, '\n') == null) receiver else sketch.container;
    const message = switch (kind) {
        .dictionary => try std.fmt.allocPrint(allocator, "`{s}` was removed for dictionaries; use `{s} in {s}`", .{ written, needle_text, receiver_text }),
        .set => try std.fmt.allocPrint(allocator, "`{s}` was removed for sets; use `{s} in {s}`", .{ written, needle_text, receiver_text }),
        .text => try std.fmt.allocPrint(allocator, "`{s}` was removed for text; use `{s} in {s}`, which tests for a substring", .{ written, needle_text, receiver_text }),
        .bytes => try std.fmt.allocPrint(allocator, "`{s}` was removed for bytes; use `{s} in {s}`, which tests for a byte or a run of bytes", .{ written, needle_text, receiver_text }),
        .list => try std.fmt.allocPrint(allocator, "`{s}` was removed for lists, which have no `in`; use `lists.contains({s}, {s})`", .{ written, receiver_text, needle_text }),
    };
    var item: diagnostic.Diagnostic = .{ .code = removed_names.code, .span = found.name, .message = message };
    const swap_certain = argument != null and repetition.swapCertain(false, plainRead(receiver), argument.?, receiver);
    if (swap_certain) {
        if (try repair(allocator, src, kind, found.call, receiver, needle_text)) |fix| item.provenance.fix = fix;
    }
    try sink.items.append(allocator, item);
    return error.SourceError;
}

/// The receiver kind a standard module's missing `contains` was meant for, when the operator `in` answers it: text for
/// `strings`, bytes for `bytes`, a set for `sets` and a dictionary for `dicts`. Null for any other module (`lists` has the
/// function, and no other module holds values `in` asks about).
pub fn receiverOfModule(module: []const u8) ?Receiver {
    const modules = [_]struct { name: []const u8, kind: Receiver }{
        .{ .name = "strings", .kind = .text },
        .{ .name = "bytes", .kind = .bytes },
        .{ .name = "sets", .kind = .set },
        .{ .name = "dicts", .kind = .dictionary },
    };
    for (modules) |known| if (std.mem.eql(u8, known.name, module)) return known.kind;
    return null;
}

/// What a collection of `kind` is called when a message says what a first argument is: `text`, `bytes`, `a set`.
pub fn holder(kind: Receiver) []const u8 {
    return switch (kind) {
        .dictionary => "a dictionary",
        .set => "a set",
        .text => "text",
        .bytes => "bytes",
        .list => "a list",
    };
}

/// The call `module.contains(container, needle)` as written, when both operands are plain: a name or a path of fields from
/// one, an integer literal or a simple string literal. Only those are read, so that nothing in the call needs
/// evaluating in another order, and a keyword argument, a comment or a line break leaves the call unread.
pub const Written = struct { call: source.Span, container: []const u8, needle: []const u8 };

/// The `Written` call that starts at `start` in `bytes` with the qualified name `spelled` (`strings.contains`), or null when
/// the text there is not that name followed by two plain operands in a call.
pub fn writtenCall(bytes: []const u8, start: usize, spelled: []const u8) ?Written {
    if (start > bytes.len or std.mem.indexOfAny(u8, spelled, " \t\r\n#") != null) return null;
    if (!std.mem.startsWith(u8, bytes[start..], spelled)) return null;
    var at = start + spelled.len;
    if (at >= bytes.len or bytes[at] != '(') return null;
    at += 1;
    const container_end = plainOperandEnd(bytes, at) orelse return null;
    const container = bytes[at..container_end];
    at = container_end;
    if (at >= bytes.len or bytes[at] != ',') return null;
    at += 1;
    if (at < bytes.len and bytes[at] == ' ') at += 1;
    const needle_end = plainOperandEnd(bytes, at) orelse return null;
    if (needle_end >= bytes.len or bytes[needle_end] != ')') return null;
    return .{ .call = .{ .start = start, .end = needle_end + 1 }, .container = container, .needle = bytes[at..needle_end] };
}

/// The end of the plain operand that starts at `at`, or null: a name and the fields after it, `10`, `"text"` or `b"data"`.
fn plainOperandEnd(bytes: []const u8, at: usize) ?usize {
    if (at >= bytes.len) return null;
    var end = at;
    if (std.ascii.isDigit(bytes[at])) {
        while (end < bytes.len and std.ascii.isDigit(bytes[end])) end += 1;
        return end;
    }
    if (bytes[at] == '"' or (bytes[at] == 'b' and at + 1 < bytes.len and bytes[at + 1] == '"')) {
        end += if (bytes[at] == 'b') 2 else 1;
        while (end < bytes.len) : (end += 1) switch (bytes[end]) {
            '\\' => end += 1,
            '"' => return end + 1,
            '\n' => return null,
            else => {},
        };
        return null;
    }
    while (true) {
        if (end >= bytes.len or !(std.ascii.isAlphabetic(bytes[end]) or bytes[end] == '_')) return null;
        while (end < bytes.len and wordByte(bytes[end])) end += 1;
        if (end >= bytes.len or bytes[end] != '.') return end;
        end += 1;
    }
}

/// The sentence for a collection of `kind` asked through a function: what the operator `in` asks, and the spelling that
/// answers it, with the operands of the call when it was read (`found`) and the placeholders of the kind when it was not.
pub fn inAdvice(allocator: std.mem.Allocator, kind: Receiver, found: ?Written) std.mem.Allocator.Error![]const u8 {
    const sketch = placeholders(kind);
    const question = switch (kind) {
        .dictionary => "whether a dictionary has a key",
        .set => "whether a set holds a value",
        .text => "whether text holds a part",
        .bytes => "whether bytes hold a byte or a run of bytes",
        .list => "whether a list holds a value",
    };
    return std.fmt.allocPrint(allocator, "{s} is the operator `in`: write `{s} in {s}`", .{
        question,
        if (found) |call| call.needle else sketch.needle,
        if (found) |call| call.container else sketch.container,
    });
}

/// Whether `declaration` is the standard module's `lists.contains(values, value)`, whose first argument is a list.
pub fn isListsContains(src: source.Source, declaration: ast.Function) bool {
    if (declaration.signature.parameters.len != 2 or !std.mem.eql(u8, src.text(declaration.name), "contains")) return false;
    return std.mem.eql(u8, src.locate(declaration.name.start).path, "@stdlib/lists.selka");
}

/// Where a call of `lists.contains` is written: its whole span, the start of its qualified name and the end of that name.
pub const ListsCall = struct { span: source.Span, start: usize, name_end: usize };

/// Refuse `lists.contains(first, ...)` whose first argument is a collection of `kind` (not a list): the inference that finds
/// `values: T[]` fails on it as it always did (`E_GENERIC_INFERENCE`, at the call), and the refusal now says what to write
/// instead: the operator `in`, as the call's own operands swapped when they are plain, with the repair that makes the edit.
pub fn refuseListsContains(allocator: std.mem.Allocator, src: source.Source, sink: *diagnostic.Sink, kind: Receiver, at: ListsCall) diagnostic.Error {
    const written = writtenCall(src.bytes, at.start, src.bytes[at.start..at.name_end]);
    const advice = try inAdvice(allocator, kind, written);
    const message = try std.fmt.allocPrint(allocator, "`lists.contains` is only for lists, and its first argument is {s}: {s}", .{ holder(kind), advice });
    const fix = if (written) |found| try inFix(allocator, src, kind, found) else null;
    return sink.failRepaired("E_GENERIC_INFERENCE", at.span, message, fix);
}

/// The repair of a call that was read: `needle in container`, or `needle not in container` where the call follows a `not`,
/// in parentheses where an operator beside it would capture it. The operands are plain, so the swap is certain.
pub fn inFix(allocator: std.mem.Allocator, src: source.Source, kind: Receiver, found: Written) diagnostic.Error!?diagnostic.Fix {
    return repair(allocator, src, kind, found.call, found.container, found.needle);
}

/// The operand names a message uses when the call does not have one plain argument.
fn placeholders(kind: Receiver) struct { needle: []const u8, container: []const u8 } {
    return switch (kind) {
        .dictionary => .{ .needle = "key", .container = "mapping" },
        .set => .{ .needle = "value", .container = "values" },
        .text => .{ .needle = "part", .container = "text" },
        .bytes => .{ .needle = "part", .container = "data" },
        .list => .{ .needle = "value", .container = "values" },
    };
}

/// The fix of `receiver.contains(argument)` (`argument` as the message shows it, parenthesized where needed): `argument in receiver` (`argument not in receiver` where the call follows a
/// `not`), parenthesized where its neighbours would capture it; for a list, `lists.contains(receiver, argument)` and the
/// import that call needs.
fn repair(allocator: std.mem.Allocator, src: source.Source, kind: Receiver, call: source.Span, receiver: []const u8, argument: []const u8) diagnostic.Error!?diagnostic.Fix {
    if (kind == .list) {
        const text = try std.fmt.allocPrint(allocator, "lists.contains({s}, {s})", .{ receiver, argument });
        var fix: diagnostic.Fix = .{ .edit = .{ .span = call, .text = text } };
        if (try import_fix.moduleEdit(allocator, src, call, "lists")) |imported| fix.more = try allocator.dupe(diagnostic.Edit, &.{imported});
        return fix;
    }
    const bytes = src.bytes;
    var span = call;
    var negate = false;
    if (negated(bytes, call.start)) |start| {
        span.start = start;
        negate = true;
    }
    const after_safe = safeAfter(bytes, call.end);
    // A `not` whose operand continues (`not seen.contains(x) == y`) is left to the parentheses below.
    if (negate and !after_safe) {
        span = call;
        negate = false;
    }
    const operation: []const u8 = if (negate) "not in" else "in";
    const bare = try std.fmt.allocPrint(allocator, "{s} {s} {s}", .{ argument, operation, receiver });
    const wrap = !(safeBefore(bytes, span.start) and after_safe);
    return .{ .edit = .{ .span = span, .text = if (wrap) try std.fmt.allocPrint(allocator, "({s})", .{bare}) else bare } };
}

/// Whether `text` is a name or a path of fields from one (`seen`, `holder.names`): a read that cannot trap or change.
fn plainRead(text: []const u8) bool {
    if (text.len == 0) return false;
    var segment_start = true;
    for (text) |byte| {
        if (byte == '.') {
            if (segment_start) return false;
            segment_start = true;
            continue;
        }
        const digit_inside = !segment_start and std.ascii.isDigit(byte);
        if (!(std.ascii.isAlphabetic(byte) or byte == '_' or digit_inside)) return false;
        segment_start = false;
    }
    return !segment_start;
}

/// Whether the argument, written before `in`, would bind looser than `in` and need parentheses: a comparison, a logical
/// operator or a membership test outside brackets and quotes.
fn bindsLooser(text: []const u8) bool {
    var quote: u8 = 0;
    var depth: usize = 0;
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        const byte = text[index];
        if (quote != 0) {
            if (byte == '\\') index += 1 else if (byte == quote) quote = 0;
            continue;
        }
        switch (byte) {
            '"', '\'' => quote = byte,
            '(', '[', '{' => depth += 1,
            ')', ']', '}' => depth -|= 1,
            '<', '>', '=', '!' => if (depth == 0) return true,
            else => if (depth == 0 and (index == 0 or !wordByte(text[index - 1]))) {
                for ([_][]const u8{ "and", "or", "not", "in", "is", "if", "else" }) |word| {
                    if (!std.mem.startsWith(u8, text[index..], word)) continue;
                    const end = index + word.len;
                    if (end == text.len or !wordByte(text[end])) return true;
                }
            },
        }
    }
    return false;
}

fn wordByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// The start of a `not` that directly precedes `at` (spaces between), or null.
fn negated(bytes: []const u8, at: usize) ?usize {
    var end = at;
    while (end > 0 and (bytes[end - 1] == ' ' or bytes[end - 1] == '\t')) end -= 1;
    if (end < 3 or !std.mem.eql(u8, bytes[end - 3 .. end], "not")) return null;
    if (end > 3 and wordByte(bytes[end - 4])) return null;
    return end - 3;
}

/// Whether what precedes `at` lets a comparison stand there unparenthesized: the start of a line, an opening bracket, a
/// comma, a plain `=`, or one of the words that take a whole condition or value.
fn safeBefore(bytes: []const u8, at: usize) bool {
    var end = at;
    while (end > 0 and (bytes[end - 1] == ' ' or bytes[end - 1] == '\t')) end -= 1;
    if (end == 0) return true;
    switch (bytes[end - 1]) {
        '\n', '(', ',', '[' => return true,
        '=' => return end < 2 or !std.mem.containsAtLeastScalar(u8, "=!<>+-*/%&|^", 1, bytes[end - 2]),
        else => {},
    }
    var start = end;
    while (start > 0 and wordByte(bytes[start - 1])) start -= 1;
    const word = bytes[start..end];
    for ([_][]const u8{ "if", "elif", "while", "return", "and", "or", "not", "assert" }) |known| if (std.mem.eql(u8, word, known)) return true;
    return false;
}

/// Whether what follows `at` ends the expression: the end of a line, a colon, a closing bracket or comma, a comment, or
/// `and` / `or`.
fn safeAfter(bytes: []const u8, at: usize) bool {
    var start = at;
    while (start < bytes.len and (bytes[start] == ' ' or bytes[start] == '\t')) start += 1;
    if (start == bytes.len) return true;
    switch (bytes[start]) {
        '\n', '\r', ':', ')', ',', ']', '}', '#' => return true,
        else => {},
    }
    var end = start;
    while (end < bytes.len and wordByte(bytes[end])) end += 1;
    const word = bytes[start..end];
    return std.mem.eql(u8, word, "and") or std.mem.eql(u8, word, "or");
}
