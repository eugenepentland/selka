//! Plain-English sentences for public interface changes. The change review prints
//! these for each declaration a change adds, removes or alters, in the wording of
//! the plan's sentence table. Pure: nothing is read or written, and every result is
//! allocated in the caller's allocator (an arena in practice).
const std = @import("std");
const types = @import("overview_types.zig");
const collect = @import("overview_collect.zig");

const Declaration = types.Declaration;
const Field = types.Field;
const Case = types.Case;

/// The sentence a caller prints when two declarations differ but `changed` names no difference.
pub const fallback = "declaration changed";

/// One parameter read from a signature: `[named] [mut] name: type [= default]`.
const Param = struct { name: []const u8, type: []const u8, default: ?[]const u8, mut: bool, named: bool };
/// A function's parameters and return type, read from its folded signature.
const Shape = struct { params: []const Param, ret: []const u8 };
/// A constant's name, type and value, read from its folded signature.
const Constant = struct { name: []const u8, type: []const u8, value: []const u8 };

/// The sentences for a declaration this change adds: one "New ..." row.
pub fn added(a: std.mem.Allocator, decl: Declaration) std.mem.Allocator.Error![]const []const u8 {
    return one(a, try addedSentence(a, decl));
}

/// The sentence for a declaration this change removes from the public interface.
pub fn removed(a: std.mem.Allocator, decl: Declaration) std.mem.Allocator.Error![]const []const u8 {
    return one(a, try std.fmt.allocPrint(a, "Removed {s}.", .{try code(a, try shape(a, decl))}));
}

/// The sentence for a declaration that became public: "Now public:" and its added sentence.
pub fn nowPublic(a: std.mem.Allocator, decl: Declaration) std.mem.Allocator.Error![]const []const u8 {
    return one(a, try std.fmt.allocPrint(a, "Now public: {s}", .{try addedSentence(a, decl)}));
}

/// The sentence for a declaration that stopped being public.
pub fn noLongerPublic(a: std.mem.Allocator, decl: Declaration) std.mem.Allocator.Error![]const []const u8 {
    return one(a, try std.fmt.allocPrint(a, "No longer public: {s}.", .{try code(a, try shape(a, decl))}));
}

/// Every clause that applies between the two sides of one public declaration, in the
/// order the review prints them. Empty when nothing interface-visible differs.
pub fn changed(a: std.mem.Allocator, old: Declaration, new: Declaration) std.mem.Allocator.Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    if (isFunction(old) and isFunction(new)) try signatureClauses(a, &out, old, new);
    try capabilityClauses(a, &out, old.details.function, new.details.function);
    try contractClauses(a, &out, old.details.contracts, new.details.contracts);
    try fieldClauses(a, &out, old.details.fields, new.details.fields);
    try caseClauses(a, &out, old.details.cases, new.details.cases);
    if (isConstant(old) and isConstant(new)) try constantClauses(a, &out, old, new);
    try docClause(a, &out, old.doc, new.doc);
    return out.toOwnedSlice(a);
}

fn one(a: std.mem.Allocator, sentence: []const u8) ![]const []const u8 {
    const out = try a.alloc([]const u8, 1);
    out[0] = sentence;
    return out;
}

fn addedSentence(a: std.mem.Allocator, decl: Declaration) ![]const u8 {
    if (isFunction(decl)) {
        const signature = try fold(a, stripPrefix(head(decl), "func "));
        return withDoc(a, try std.fmt.allocPrint(a, "New function {s}.", .{try code(a, signature)}), decl.doc);
    }
    if (std.mem.eql(u8, decl.kind, "type")) return newType(a, decl);
    return std.fmt.allocPrint(a, "New {s}.", .{try code(a, try fold(a, head(decl)))});
}

/// `New record` or `New enum`, with the fields or cases the declaration lists.
fn newType(a: std.mem.Allocator, decl: Declaration) ![]const u8 {
    const first = firstLine(head(decl));
    const keyword_end = std.mem.indexOfScalar(u8, first, ' ') orelse first.len;
    const keyword = first[0..keyword_end];
    const name = try code(a, std.mem.trim(u8, first[keyword_end..], " :"));
    const is_enum = std.mem.eql(u8, keyword, "enum");
    if (is_enum) {
        const names = try caseNames(a, decl.details.cases);
        if (names.len == 0) return withDoc(a, try std.fmt.allocPrint(a, "New enum {s}.", .{name}), decl.doc);
        return withDoc(a, try std.fmt.allocPrint(a, "New enum {s} with cases {s}.", .{ name, try codedList(a, names) }), decl.doc);
    }
    const fields = try fieldTexts(a, decl.details.fields);
    if (fields.len == 0) return withDoc(a, try std.fmt.allocPrint(a, "New record {s}.", .{name}), decl.doc);
    return withDoc(a, try std.fmt.allocPrint(a, "New record {s} with fields {s}.", .{ name, try codedList(a, fields) }), decl.doc);
}

/// The declaration as `removed` and `noLongerPublic` show it: a function or constant in
/// full, a record or enum by its header line alone.
fn shape(a: std.mem.Allocator, decl: Declaration) ![]const u8 {
    if (std.mem.eql(u8, decl.kind, "type")) return fold(a, firstLine(head(decl)));
    return fold(a, head(decl));
}

fn signatureClauses(a: std.mem.Allocator, out: *std.ArrayList([]const u8), old: Declaration, new: Declaration) !void {
    const before = try shapeOf(a, old);
    const after = try shapeOf(a, new);
    try paramClauses(a, out, before.params, after.params);
    if (!std.mem.eql(u8, before.ret, after.ret)) {
        try out.append(a, try std.fmt.allocPrint(a, "returns {s} instead of {s}", .{ try code(a, after.ret), try code(a, before.ret) }));
    }
    try failureClause(a, out, old.details.function, new.details.function);
}

fn paramClauses(a: std.mem.Allocator, out: *std.ArrayList([]const u8), before: []const Param, after: []const Param) !void {
    for (after) |param| {
        if (findNamed(Param, before, param.name) == null) try out.append(a, try addedParam(a, param));
    }
    for (before) |param| {
        if (findNamed(Param, after, param.name) == null) try out.append(a, try std.fmt.allocPrint(a, "no longer takes {s}", .{try code(a, param.name)}));
    }
    for (after) |param| {
        const prior = findNamed(Param, before, param.name) orelse continue;
        if (!std.mem.eql(u8, prior.type, param.type)) {
            try out.append(a, try std.fmt.allocPrint(a, "takes {s} as {s} instead of {s}", .{ try code(a, param.name), try code(a, param.type), try code(a, prior.type) }));
        }
    }
    for (after) |param| {
        const prior = findNamed(Param, before, param.name) orelse continue;
        if (prior.mut != param.mut) try out.append(a, try mutSentence(a, param));
    }
    for (after) |param| {
        const prior = findNamed(Param, before, param.name) orelse continue;
        if (prior.named != param.named) try out.append(a, try keywordSentence(a, param));
    }
}

/// `now takes name: T`, with the declared `mut` or `named` spelling and any default.
fn addedParam(a: std.mem.Allocator, param: Param) ![]const u8 {
    const modifiers = try std.fmt.allocPrint(a, "{s}{s}", .{ if (param.named) "named " else "", if (param.mut) "mut " else "" });
    const spelled = try std.fmt.allocPrint(a, "{s}{s}: {s}", .{ modifiers, param.name, param.type });
    const base = try std.fmt.allocPrint(a, "now takes {s}", .{try code(a, spelled)});
    if (param.default) |value| return std.fmt.allocPrint(a, "{s} (defaults to {s})", .{ base, try code(a, value) });
    return base;
}

fn mutSentence(a: std.mem.Allocator, param: Param) ![]const u8 {
    const verb = if (param.mut) "now changes" else "no longer changes";
    return std.fmt.allocPrint(a, "{s} the caller's {s}", .{ verb, try code(a, param.name) });
}

/// Keyword-only is not part of the `name: T` sentence, so a change to it gets its own clause.
fn keywordSentence(a: std.mem.Allocator, param: Param) ![]const u8 {
    const verb = if (param.named) "now takes" else "no longer takes";
    return std.fmt.allocPrint(a, "{s} {s} only by keyword", .{ verb, try code(a, param.name) });
}

fn failureClause(a: std.mem.Allocator, out: *std.ArrayList([]const u8), old: ?types.Function, new: ?types.Function) !void {
    const before = failsOf(old);
    const after = failsOf(new);
    if (sameText(before, after)) return;
    const sentence: []const u8 = if (before == null)
        try std.fmt.allocPrint(a, "can now fail with {s}", .{try code(a, after.?)})
    else if (after == null)
        "can no longer fail"
    else
        try std.fmt.allocPrint(a, "fails with {s} instead of {s}", .{ try code(a, after.?), try code(a, before.?) });
    try out.append(a, sentence);
}

fn capabilityClauses(a: std.mem.Allocator, out: *std.ArrayList([]const u8), old: ?types.Function, new: ?types.Function) !void {
    const before = authorityOf(old);
    const after = authorityOf(new);
    for (try missingTypes(a, after, before)) |name| {
        try out.append(a, try std.fmt.allocPrint(a, "now needs {s}", .{try code(a, name)}));
    }
    for (try missingTypes(a, before, after)) |name| {
        try out.append(a, try std.fmt.allocPrint(a, "no longer needs {s}", .{try code(a, name)}));
    }
}

fn contractClauses(a: std.mem.Allocator, out: *std.ArrayList([]const u8), old: []const []const u8, new: []const []const u8) !void {
    for (new) |text| {
        if (!containsText(old, text)) try out.append(a, try contractSentence(a, "gained", text));
    }
    for (old) |text| {
        if (!containsText(new, text)) try out.append(a, try contractSentence(a, "lost", text));
    }
}

fn contractSentence(a: std.mem.Allocator, verb: []const u8, text: []const u8) ![]const u8 {
    const noun = if (std.mem.startsWith(u8, text, "@invariant")) "invariant" else "contract";
    return std.fmt.allocPrint(a, "{s} {s} {s}", .{ verb, noun, try code(a, text) });
}

fn fieldClauses(a: std.mem.Allocator, out: *std.ArrayList([]const u8), old: []const Field, new: []const Field) !void {
    for (new) |field| {
        const prior = findNamed(Field, old, field.name) orelse {
            try out.append(a, try std.fmt.allocPrint(a, "gained field {s}", .{try code(a, try fieldDeclared(a, field))}));
            continue;
        };
        if (!std.mem.eql(u8, prior.type, field.type)) {
            try out.append(a, try std.fmt.allocPrint(a, "field {s} is {s} instead of {s}", .{ try code(a, field.name), try code(a, field.type), try code(a, prior.type) }));
        }
        if (!sameText(prior.default, field.default)) try out.append(a, try defaultSentence(a, field.name, prior.default, field.default));
    }
    for (old) |field| {
        if (findNamed(Field, new, field.name) == null) try out.append(a, try std.fmt.allocPrint(a, "lost field {s}", .{try code(a, field.name)}));
    }
}

fn defaultSentence(a: std.mem.Allocator, name: []const u8, before: ?[]const u8, after: ?[]const u8) ![]const u8 {
    const field = try code(a, name);
    if (before == null) return std.fmt.allocPrint(a, "field {s} now defaults to {s}", .{ field, try code(a, after.?) });
    if (after == null) return std.fmt.allocPrint(a, "field {s} no longer defaults to {s}", .{ field, try code(a, before.?) });
    return std.fmt.allocPrint(a, "field {s} defaults to {s} instead of {s}", .{ field, try code(a, after.?), try code(a, before.?) });
}

fn caseClauses(a: std.mem.Allocator, out: *std.ArrayList([]const u8), old: []const Case, new: []const Case) !void {
    for (new) |item| {
        const prior = findNamed(Case, old, item.name) orelse {
            try out.append(a, try std.fmt.allocPrint(a, "gained case {s}", .{try code(a, item.name)}));
            continue;
        };
        try caseFieldClauses(a, out, prior, item);
    }
    for (old) |item| {
        if (findNamed(Case, new, item.name) == null) try out.append(a, try std.fmt.allocPrint(a, "lost case {s}", .{try code(a, item.name)}));
    }
}

/// The payload changes of one case that exists on both sides.
fn caseFieldClauses(a: std.mem.Allocator, out: *std.ArrayList([]const u8), old: Case, new: Case) !void {
    const name = try code(a, new.name);
    const gained = try fieldsMissing(a, new.fields, old.fields);
    const lost = try fieldsMissing(a, old.fields, new.fields);
    if (gained.len == 1 and lost.len == 1) {
        const carried = try code(a, try fieldDeclared(a, gained[0]));
        const replaced = try code(a, try fieldDeclared(a, lost[0]));
        try out.append(a, try std.fmt.allocPrint(a, "case {s} carries {s} instead of {s}", .{ name, carried, replaced }));
    } else {
        if (gained.len > 0) try out.append(a, try std.fmt.allocPrint(a, "case {s} gained {s}", .{ name, try codedList(a, try fieldTexts(a, gained)) }));
        if (lost.len > 0) try out.append(a, try std.fmt.allocPrint(a, "case {s} lost {s}", .{ name, try codedList(a, try fieldNames(a, lost)) }));
    }
    for (new.fields) |field| {
        const prior = findNamed(Field, old.fields, field.name) orelse continue;
        if (!std.mem.eql(u8, prior.type, field.type)) {
            try out.append(a, try std.fmt.allocPrint(a, "case {s} field {s} is {s} instead of {s}", .{ name, try code(a, field.name), try code(a, field.type), try code(a, prior.type) }));
        }
    }
}

fn constantClauses(a: std.mem.Allocator, out: *std.ArrayList([]const u8), old: Declaration, new: Declaration) !void {
    const before = try constantOf(a, old);
    const after = try constantOf(a, new);
    const name = try code(a, after.name);
    if (!std.mem.eql(u8, before.value, after.value)) {
        try out.append(a, try std.fmt.allocPrint(a, "{s} is now {s} (was {s})", .{ name, try code(a, after.value), try code(a, before.value) }));
    }
    if (!std.mem.eql(u8, before.type, after.type)) {
        try out.append(a, try std.fmt.allocPrint(a, "{s} is now typed {s} (was {s})", .{ name, try code(a, after.type), try code(a, before.type) }));
    }
}

/// The first sentence of a changed docstring. It is shown when another clause exists or
/// when that first sentence itself changed; a docstring removed entirely shows nothing.
fn docClause(a: std.mem.Allocator, out: *std.ArrayList([]const u8), old_doc: []const u8, new_doc: []const u8) !void {
    if (std.mem.eql(u8, old_doc, new_doc)) return;
    const after = collect.firstSentence(new_doc);
    if (after.len == 0) return;
    const before = collect.firstSentence(old_doc);
    if (out.items.len == 0 and std.mem.eql(u8, before, after)) return;
    try out.append(a, try std.fmt.allocPrint(a, "docstring now says: {s}", .{try fold(a, after)}));
}

/// The distinct capability types in `from` that `against` does not name, sorted.
fn missingTypes(a: std.mem.Allocator, from: []const types.Parameter, against: []const types.Parameter) ![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (from) |param| {
        if (hasParamType(against, param.type) or containsText(out.items, param.type)) continue;
        try out.append(a, param.type);
    }
    std.mem.sort([]const u8, out.items, {}, lessText);
    return out.toOwnedSlice(a);
}

fn fieldsMissing(a: std.mem.Allocator, from: []const Field, against: []const Field) ![]const Field {
    var out: std.ArrayList(Field) = .empty;
    for (from) |field| {
        if (findNamed(Field, against, field.name) == null) try out.append(a, field);
    }
    return out.toOwnedSlice(a);
}

fn shapeOf(a: std.mem.Allocator, decl: Declaration) !Shape {
    const text = try fold(a, head(decl));
    const open = std.mem.indexOfScalar(u8, text, '(') orelse return .{ .params = &.{}, .ret = "Unit" };
    const close = matchingClose(text, open) orelse return .{ .params = &.{}, .ret = "Unit" };
    return .{ .params = try parseParams(a, text[open + 1 .. close]), .ret = returnType(text[close + 1 ..]) };
}

/// The return type after `->`, without a failure clause or the trailing colon; `Unit` without `->`.
fn returnType(rest_text: []const u8) []const u8 {
    const rest = std.mem.trim(u8, rest_text, " ");
    if (!std.mem.startsWith(u8, rest, "->")) return "Unit";
    var ret = std.mem.trim(u8, rest[2..], " ");
    if (std.mem.indexOf(u8, ret, " fails ")) |at| ret = ret[0..at];
    return std.mem.trimEnd(u8, ret, " :");
}

/// The index of the `)` matching the `(` at `open`, counting `(` and `[` as openers.
fn matchingClose(text: []const u8, open: usize) ?usize {
    var depth: usize = 0;
    for (text[open..], open..) |byte, index| {
        if (byte == '(' or byte == '[') depth += 1;
        if (byte == ')' or byte == ']') {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return index;
        }
    }
    return null;
}

fn parseParams(a: std.mem.Allocator, text: []const u8) ![]const Param {
    var out: std.ArrayList(Param) = .empty;
    const parts = try splitTop(a, text);
    for (parts) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        if (trimmed.len == 0) continue;
        if (parseParam(trimmed)) |param| try out.append(a, param);
    }
    return out.toOwnedSlice(a);
}

/// Split at commas outside brackets and string literals.
fn splitTop(a: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var depth: usize = 0;
    var quoted = false;
    var escaped = false;
    var start: usize = 0;
    for (text, 0..) |byte, index| {
        if (quoted) {
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                quoted = false;
            }
            continue;
        }
        switch (byte) {
            '"' => quoted = true,
            '(', '[' => depth += 1,
            ')', ']' => depth -|= 1,
            ',' => if (depth == 0) {
                try parts.append(a, text[start..index]);
                start = index + 1;
            },
            else => {},
        }
    }
    try parts.append(a, text[start..]);
    return parts.toOwnedSlice(a);
}

/// One parameter: its leading `named` and `mut` words, `name: type`, and an optional default.
fn parseParam(text: []const u8) ?Param {
    var rest = text;
    var mut = false;
    var named = false;
    while (true) {
        if (std.mem.startsWith(u8, rest, "mut ")) {
            mut = true;
            rest = rest[4..];
        } else if (std.mem.startsWith(u8, rest, "named ")) {
            named = true;
            rest = rest[6..];
        } else break;
        rest = std.mem.trimStart(u8, rest, " ");
    }
    const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
    const name = std.mem.trim(u8, rest[0..colon], " ");
    if (name.len == 0) return null;
    const after = std.mem.trim(u8, rest[colon + 1 ..], " ");
    if (std.mem.indexOfScalar(u8, after, '=')) |equal| {
        return .{ .name = name, .type = std.mem.trim(u8, after[0..equal], " "), .default = std.mem.trim(u8, after[equal + 1 ..], " "), .mut = mut, .named = named };
    }
    return .{ .name = name, .type = after, .default = null, .mut = mut, .named = named };
}

fn constantOf(a: std.mem.Allocator, decl: Declaration) !Constant {
    const text = try fold(a, stripPrefix(head(decl), "const "));
    const equal = std.mem.indexOfScalar(u8, text, '=') orelse text.len;
    const value = if (equal < text.len) std.mem.trim(u8, text[equal + 1 ..], " ") else "";
    const left = std.mem.trim(u8, text[0..equal], " ");
    const colon = std.mem.indexOfScalar(u8, left, ':');
    return .{
        .name = std.mem.trim(u8, left[0 .. colon orelse left.len], " "),
        .type = if (colon) |at| std.mem.trim(u8, left[at + 1 ..], " ") else "",
        .value = value,
    };
}

/// `name: type`, with ` = default` when the field has one.
fn fieldDeclared(a: std.mem.Allocator, field: Field) ![]const u8 {
    if (field.default) |value| return std.fmt.allocPrint(a, "{s}: {s} = {s}", .{ field.name, field.type, value });
    return std.fmt.allocPrint(a, "{s}: {s}", .{ field.name, field.type });
}

fn fieldTexts(a: std.mem.Allocator, fields: []const Field) ![]const []const u8 {
    const out = try a.alloc([]const u8, fields.len);
    for (fields, out) |field, *slot| slot.* = try std.fmt.allocPrint(a, "{s}: {s}", .{ field.name, field.type });
    return out;
}

fn fieldNames(a: std.mem.Allocator, fields: []const Field) ![]const []const u8 {
    const out = try a.alloc([]const u8, fields.len);
    for (fields, out) |field, *slot| slot.* = field.name;
    return out;
}

fn caseNames(a: std.mem.Allocator, cases: []const Case) ![]const []const u8 {
    const out = try a.alloc([]const u8, cases.len);
    for (cases, out) |item, *slot| slot.* = item.name;
    return out;
}

/// `a`, `b`, `c`: each item in backticks, separated by commas.
fn codedList(a: std.mem.Allocator, items: []const []const u8) ![]const u8 {
    const coded = try a.alloc([]const u8, items.len);
    for (items, coded) |item, *slot| slot.* = try code(a, item);
    return std.mem.join(a, ", ", coded);
}

fn code(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "`{s}`", .{text});
}

/// Collapses every run of whitespace to one space and trims both ends.
fn fold(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var blank = false;
    for (std.mem.trim(u8, text, " \t\r\n")) |byte| {
        const space = byte == ' ' or byte == '\t' or byte == '\r' or byte == '\n';
        if (space and blank) continue;
        blank = space;
        try out.append(a, if (space) ' ' else byte);
    }
    return out.toOwnedSlice(a);
}

/// The sentence followed by the first sentence of the docstring, when there is one.
fn withDoc(a: std.mem.Allocator, sentence: []const u8, doc: []const u8) ![]const u8 {
    const first = try fold(a, collect.firstSentence(doc));
    if (first.len == 0) return sentence;
    return std.fmt.allocPrint(a, "{s} {s}", .{ sentence, first });
}

/// The declaration text from its `public` line on, past any contract lines above it.
fn header(signature: []const u8) []const u8 {
    const text = std.mem.trim(u8, signature, " \t\r\n");
    if (std.mem.startsWith(u8, text, "public ")) return text;
    if (std.mem.indexOf(u8, text, "\npublic ")) |at| return text[at + 1 ..];
    return text;
}

/// The declaration without its leading `public `, the form every sentence names.
fn head(decl: Declaration) []const u8 {
    return stripPrefix(header(decl.signature), "public ");
}

fn isFunction(decl: Declaration) bool {
    return std.mem.startsWith(u8, head(decl), "func ");
}

fn isConstant(decl: Declaration) bool {
    return std.mem.startsWith(u8, head(decl), "const ");
}

fn firstLine(text: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    return std.mem.trim(u8, text[0..end], " \t\r");
}

fn stripPrefix(text: []const u8, prefix: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, text, prefix)) text[prefix.len..] else text;
}

fn failsOf(function: ?types.Function) ?[]const u8 {
    return if (function) |value| value.fails else null;
}

fn authorityOf(function: ?types.Function) []const types.Parameter {
    return if (function) |value| value.authority else &.{};
}

fn sameText(a: ?[]const u8, b: ?[]const u8) bool {
    const left = a orelse return b == null;
    const right = b orelse return false;
    return std.mem.eql(u8, left, right);
}

fn containsText(items: []const []const u8, text: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, text)) return true;
    }
    return false;
}

fn hasParamType(items: []const types.Parameter, text: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item.type, text)) return true;
    }
    return false;
}

fn findNamed(comptime T: type, items: []const T, name: []const u8) ?T {
    for (items) |item| {
        if (std.mem.eql(u8, item.name, name)) return item;
    }
    return null;
}

fn lessText(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}
