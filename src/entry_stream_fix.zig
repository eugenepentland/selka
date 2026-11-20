//! The repair of an unused Stream parameter of the entry `main` (lane FR35): delete the parameter with the comma that separates
//! it, so the entry still names its Streams `out` and `err` (`E_MAIN` refuses `_out`). The edit is offered only when nothing else
//! can see the change, and a shape that is not certain keeps the message and gets no edit.
const std = @import("std");
const ast = @import("ast.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");

/// The edit that deletes the parameter named at `declaration` from the signature of one of `functions`, or null when the
/// deletion is not certain: the parameter is not plain (`mut`, `own`, `named`, a default), the list has a keyword-only part, the
/// text around it holds more than whitespace and the one separating comma (a comment, a modifier of the neighbour), or `main`
/// is named anywhere else in the source (a call of it would be left with an argument too many).
pub fn deletion(src: source.Source, functions: []const ast.Function, declaration: source.Span) ?diagnostic.Edit {
    const found = locate(functions, declaration) orelse return null;
    const parameters = found.signature.parameters;
    const parameter = parameters[found.position];
    if (found.signature.keyword_only_from != null) return null;
    if (parameter.mut or parameter.own or parameter.named or parameter.default_value != null) return null;
    if (namedElsewhere(src.bytes)) return null;
    const range = listRange(src.bytes, parameters, found.position) orelse return null;
    return .{ .span = range, .text = "" };
}

/// A parameter's signature and its place in it.
const Place = struct { signature: ast.FunctionSignature, position: usize };

/// The signature that declares a parameter named at `declaration`, and its position there.
fn locate(functions: []const ast.Function, declaration: source.Span) ?Place {
    for (functions) |function| {
        for (function.signature.parameters, 0..) |parameter, position| {
            if (parameter.name.start == declaration.start and parameter.name.end == declaration.end) return .{ .signature = function.signature, .position = position };
        }
    }
    return null;
}

/// The bytes that go with the parameter at `position`: it and the comma before the next one when one follows; else the previous
/// one's end up to its own (the comma between them), which leaves a trailing comma as it was; the sole parameter, from the
/// opening parenthesis to the closing one, with the whitespace and the trailing comma between.
fn listRange(bytes: []const u8, parameters: []const ast.Parameter, position: usize) ?source.Span {
    const item: source.Span = .{ .start = parameters[position].name.start, .end = parameters[position].ty.end };
    if (position + 1 < parameters.len) {
        const next = parameters[position + 1].name.start;
        if (item.end > next or !onlySeparator(bytes[item.end..next])) return null;
        return .{ .start = item.start, .end = next };
    }
    if (position > 0) {
        const before = parameters[position - 1].ty.end;
        if (before > item.start or !onlySeparator(bytes[before..item.start])) return null;
        return .{ .start = before, .end = item.end };
    }
    var open = item.start;
    while (open > 0 and isSpace(bytes[open - 1])) open -= 1;
    if (open == 0 or bytes[open - 1] != '(') return null;
    var close = item.end;
    while (close < bytes.len and isSpace(bytes[close])) close += 1;
    if (close < bytes.len and bytes[close] == ',') close += 1;
    while (close < bytes.len and isSpace(bytes[close])) close += 1;
    if (close >= bytes.len or bytes[close] != ')') return null;
    return .{ .start = open, .end = close };
}

/// Whether `gap` is whitespace around exactly one comma: nothing of the neighbouring parameter, no comment.
fn onlySeparator(gap: []const u8) bool {
    var commas: usize = 0;
    for (gap) |byte| {
        if (byte == ',') commas += 1 else if (!isSpace(byte)) return false;
    }
    return commas == 1;
}

fn isSpace(byte: u8) bool {
    return byte == ' ' or byte == '\t' or byte == '\n' or byte == '\r';
}

/// Whether the identifier `main` stands in `bytes` anywhere but after `func` or in a comment line: a call, a qualified call from
/// another module, or any other mention that deleting the parameter could leave wrong. Comments and text are counted when they
/// share a line with code, so the answer errs towards offering no edit.
fn namedElsewhere(bytes: []const u8) bool {
    const name = "main";
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, at, name)) |found| {
        at = found + name.len;
        if (found > 0 and identifierByte(bytes[found - 1])) continue;
        if (at < bytes.len and identifierByte(bytes[at])) continue;
        if (declared(bytes, found) or commentLine(bytes, found)) continue;
        return true;
    }
    return false;
}

/// Whether the name at `at` is the one `func` declares.
fn declared(bytes: []const u8, at: usize) bool {
    var end = at;
    while (end > 0 and (bytes[end - 1] == ' ' or bytes[end - 1] == '\t')) end -= 1;
    const keyword = "func";
    if (end < keyword.len or !std.mem.eql(u8, bytes[end - keyword.len .. end], keyword)) return false;
    return end == keyword.len or !identifierByte(bytes[end - keyword.len - 1]);
}

/// Whether the line that holds `at` is a comment: its first byte that is not a space or a tab is `#`.
fn commentLine(bytes: []const u8, at: usize) bool {
    var start = at;
    while (start > 0 and bytes[start - 1] != '\n') start -= 1;
    while (start < at and (bytes[start] == ' ' or bytes[start] == '\t')) start += 1;
    return start < at and bytes[start] == '#';
}

fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}
