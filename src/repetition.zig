//! Retirement recognition and certain migrations for sequence repetition.
//! The checker retains old operand types long enough to diagnose every site;
//! accepted programs use explicit standard-library words.
const std = @import("std");
const typed = @import("typed.zig");
const numeric_surface = @import("numeric_surface.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const eRemoved = "E_REPETITION_REMOVED";
const helperReturn = "    return {s}\n";
const helperEmptyReturn = "        return {s}\n";

/// The sequence kinds `*` repeats: text, immutable octets and lists.
pub fn repeatable(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = records[ty.recordIndex()];
    // A value record such as `float` has a collection kind field too; only a
    // managed collection is a sequence.
    if (!record.isCollection()) return false;
    return switch (record.collection.kind) {
        .string, .list => true,
        .bytes => !std.mem.eql(u8, record.name, "byte_buffer"),
        else => false,
    };
}

/// One checked repetition: the sequence operand, the count operand and which
/// of the two the source wrote first.
pub const Operands = struct { sequence: typed.NodeId, count: typed.NodeId, count_first: bool };

/// Diagnose retired repetition while retaining its type for migration checking.
pub fn build(comptime Checker: type, checker: *Checker, span: source.Span, operands: Operands) diagnostic.Error!typed.Node {
    // A repair looks around the whole program: bodies filled on demand are filled first.
    try @import("ast.zig").ensureAll(programOf(Checker, checker));
    const sequence = checker.nodes.items[@backingInt(operands.sequence)];
    const count = checker.nodes.items[@backingInt(operands.count)];
    const schema = checker.catalog.records[sequence.ty.recordIndex()];
    const module: []const u8 = switch (schema.collection.kind) {
        .string => "strings",
        .bytes => "byte_builder",
        .list => "lists",
        else => unreachable,
    };
    var replacement: ?[]const u8 = null;
    const unsigned = count.ty == .u64;
    const count_text = if (unsigned) checker.src.text(count.span) else try integerCountText(checker.allocator, checker.src, count.span, count.ty);
    const order_certain = !operands.count_first or (pure(checker.nodes.items, checker.catalog.records, operands.count) and pure(checker.nodes.items, checker.catalog.records, operands.sequence));
    if (count_text != null and order_certain and !unsigned) {
        if (schema.collection.kind == .list) {
            for (checker.syntax.nodes.items) |syntax| {
                const same_span = syntax.span.start == sequence.span.start and syntax.span.end == sequence.span.end;
                if (!same_span or syntax.data != .list_literal) continue;
                if (syntax.data.list_literal.len != 1) continue;
                const value = checker.syntax.nodes.items[@backingInt(syntax.data.list_literal[0])];
                switch (value.data) {
                    .integer, .boolean, .text, .bytes, .name => {},
                    else => continue,
                }
                if (value.data == .name) {
                    if (!checker.active.contains(checker.src.text(value.data.name))) continue;
                    if (!pure(checker.nodes.items, checker.catalog.records, operands.count)) continue;
                }
                replacement = try std.fmt.allocPrint(checker.allocator, "lists.filled({s}, {s})", .{ count_text.?, checker.src.text(value.span) });
                break;
            }
        } else replacement = try std.fmt.allocPrint(checker.allocator, "{s}.repeat({s}, {s})", .{ module, checker.src.text(sequence.span), count_text.? });
    }
    if (replacement == null and count_text != null) {
        try helperFix(Checker, checker, span, .{ .sequence = sequence.span, .count_text = count_text.?, .module = module, .count_first = operands.count_first, .unsigned = unsigned });
    } else try removed(Checker, checker, span, .{
        .code = eRemoved,
        .message = "sequence repetition was removed; use strings.repeat, byte_builder.repeat, or lists.filled; repeat a multi-element list with a loop",
        .module = module,
    }, replacement);
    return .{ .span = span, .ty = sequence.ty, .data = .{ .binary = .{
        .op = .mul,
        .op_span = span,
        .left = if (operands.count_first) operands.count else operands.sequence,
        .right = if (operands.count_first) operands.sequence else operands.count,
    } } };
}

/// Widen a count exactly when every value of its integer type fits the library count.
pub fn integerCountText(allocator: std.mem.Allocator, src: source.Source, span: source.Span, ty: typed.Type) std.mem.Allocator.Error!?[]const u8 {
    if (ty == .u64 or !ty.isInteger()) return null;
    return if (ty == .i64) src.text(span) else try std.fmt.allocPrint(allocator, "int({s})", .{src.text(span)});
}

const HelperOperands = struct { sequence: source.Span, count_text: []const u8, module: []const u8, count_first: bool, unsigned: bool = false, assignment: ?[]const u8 = null, sequence_text: ?[]const u8 = null };

fn helperFix(comptime Checker: type, checker: *Checker, span: source.Span, operands: HelperOperands) diagnostic.Error!void {
    const helper = try freshName(checker.allocator, checker.src, "repeat_sequence", span.start);
    const value = try freshName(checker.allocator, checker.src, "repeat_source", span.start);
    const count = try freshName(checker.allocator, checker.src, "repeat_times", span.start);
    const list = std.mem.eql(u8, operands.module, "lists");
    const generic = try freshName(checker.allocator, checker.src, "RepeatType", span.start);
    const sequence_type: []const u8 = if (list) try std.fmt.allocPrint(checker.allocator, "{s}[]", .{generic}) else if (std.mem.eql(u8, operands.module, "strings")) "str" else "bytes";
    const count_type: []const u8 = if (operands.unsigned) "u64" else "int";
    const parameters = if (operands.count_first) try std.fmt.allocPrint(checker.allocator, "{s}: {s}, {s}: {s}", .{
        count, count_type, value, sequence_type,
    }) else try std.fmt.allocPrint(checker.allocator, "{s}: {s}, {s}: {s}", .{ value, sequence_type, count, count_type });
    const type_parameters: []const u8 = if (list) try std.fmt.allocPrint(checker.allocator, "[{s}: copy + storable]", .{generic}) else "";
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    const body = if (list) list_body: {
        const out = try freshName(checker.allocator, checker.src, "repeat_output", span.start);
        const element = try freshName(checker.allocator, checker.src, "repeat_element", span.start);
        if (operands.unsigned) {
            const index = try freshName(checker.allocator, checker.src, "repeat_index", span.start);
            break :list_body try std.fmt.allocPrint(checker.allocator, "    mut {s}: {s} = []\n" ++
                "    if len({s}) == 0:\n" ++
                helperEmptyReturn ++
                "    mut {s} = 0u64\n" ++
                "    while {s} < {s}:\n" ++
                "        for {s} in {s}:\n" ++
                "            append(mut {s}, copy({s}))\n" ++
                "        {s} += 1u64\n" ++
                helperReturn, .{
                out, sequence_type, value, out, index, index, count, element, value, out, element, index, out,
            });
        }
        break :list_body try std.fmt.allocPrint(checker.allocator, "    mut {s}: {s} = []\n" ++
            "    if len({s}) == 0:\n" ++
            helperEmptyReturn ++
            "    for _ in range({s}):\n" ++
            "        for {s} in {s}:\n" ++
            "            append(mut {s}, copy({s}))\n" ++
            helperReturn, .{
            out, sequence_type, value, out, count, element, value, out, element, out,
        });
    } else if (operands.unsigned) unsigned_text: {
        const copies = try freshName(checker.allocator, checker.src, "repeat_copies", span.start);
        const out = try freshName(checker.allocator, checker.src, "repeat_output", span.start);
        const empty: []const u8 = if (std.mem.eql(u8, operands.module, "strings")) "\"\"" else "b\"\"";
        break :unsigned_text try std.fmt.allocPrint(checker.allocator, "    if {s} == 0u64 or len({s}) == 0:\n" ++
            helperEmptyReturn ++
            "    mut {s} = copy({s})\n" ++
            "    mut {s} = 1u64\n" ++
            "    while {s} <= {s} - {s}:\n" ++
            "        {s} = {s} + {s}\n" ++
            "        {s} *= 2u64\n" ++
            "    if {s} < {s}:\n" ++
            "        {s} = {s} + {s}[:len({s}) * int({s} - {s})]\n" ++
            helperReturn, .{
            count, value, empty, out, value, copies, copies, count, copies, out, out, out, copies, copies, count, out, out, out, value, count, copies, out,
        });
    } else text_body: {
        const library = try importRepair(Checker, checker, span, operands.module);
        if (library.edit) |edit| try edits.append(checker.allocator, edit);
        break :text_body try std.fmt.allocPrint(checker.allocator, "    return {s}.repeat({s}, {s})\n", .{ library.spelling, value, count });
    };
    var end = checker.src.bytes.len;
    if (checker.src.origins.len != 0) {
        const original = checker.src.originalSpan(span) catch return error.InternalError;
        const origin = checker.src.origins[original.input];
        end = origin.start + origin.original.bytes.len;
    }
    const declaration = try std.fmt.allocPrint(checker.allocator, "\n\nfunc {s}{s}({s}) -> {s}:\n{s}", .{ helper, type_parameters, parameters, sequence_type, body });
    try edits.append(checker.allocator, .{ .span = .{ .start = end, .end = end }, .text = declaration });
    const sequence = operands.sequence_text orelse checker.src.text(operands.sequence);
    const replacement = if (operands.count_first) try std.fmt.allocPrint(checker.allocator, "{s}({s}, {s})", .{
        helper, operands.count_text, sequence,
    }) else try std.fmt.allocPrint(checker.allocator, "{s}({s}, {s})", .{ helper, sequence, operands.count_text });
    const repaired = if (operands.assignment) |name| try std.fmt.allocPrint(checker.allocator, "{s} = {s}", .{ name, replacement }) else replacement;
    var item: diagnostic.Diagnostic = .{ .code = eRemoved, .span = span, .message = "sequence repetition was removed; this helper preserves operand order and independent copies" };
    item.provenance.fix = .{ .edit = .{ .span = span, .text = repaired }, .more = try edits.toOwnedSlice(checker.allocator) };
    try checker.sink.items.append(checker.allocator, item);
}

/// Whether `lists.contains(container, needle)` keeps what `needle in container` observes (F-25): the operands swap
/// places, so the swap is certain when either one is a pure read (a local, a field of one, a literal: it cannot trap and
/// does nothing) and the other names no `mut` or `own` argument (`take(mut ...)`, `exchange(mut ...)` included), the
/// only spellings by which evaluating it could change what the pure one reads.
pub fn swapCertain(needle_pure: bool, container_pure: bool, needle_text: []const u8, container_text: []const u8) bool {
    if (needle_pure and container_pure) return true;
    if (needle_pure) return !marksPlace(container_text);
    if (container_pure) return !marksPlace(needle_text);
    return false;
}

/// Whether `text` contains the word `mut` or `own` outside a quoted literal.
fn marksPlace(text: []const u8) bool {
    var index: usize = 0;
    var quote: u8 = 0;
    while (index < text.len) : (index += 1) {
        const byte = text[index];
        if (quote != 0) {
            if (byte == '\\') index += 1 else if (byte == quote) quote = 0;
            continue;
        }
        if (byte == '"' or byte == '\'') {
            quote = byte;
            continue;
        }
        if (index != 0 and (std.ascii.isAlphanumeric(text[index - 1]) or text[index - 1] == '_')) continue;
        for ([_][]const u8{ "mut", "own" }) |word| {
            if (!std.mem.startsWith(u8, text[index..], word)) continue;
            const end = index + word.len;
            if (end == text.len or !(std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) return true;
        }
    }
    return false;
}

/// Whether a checked operand can be reordered without changing observable work.
pub fn pure(nodes: []const typed.Node, records: []const typed.Record, id: typed.NodeId) bool {
    return switch (nodes[@backingInt(id)].data) {
        .integer, .boolean, .unit, .local => true,
        .array => |items| blk: {
            for (items) |item| if (!pure(nodes, records, item)) break :blk false;
            break :blk true;
        },
        .wrap => |value| numeric_surface.isBinaryFloat(nodes[@backingInt(id)].ty, records) and pure(nodes, records, value),
        .unwrap => |value| numeric_surface.isBinaryFloat(nodes[@backingInt(value)].ty, records) and pure(nodes, records, value),
        .unary => |value| (value.op == .not or value.op == .f64_neg) and pure(nodes, records, value.operand),
        .field => |value| pure(nodes, records, value.base),
        else => false,
    };
}

/// Recognize a literal list whose element evaluations are all resolved pure reads.
pub fn literalListPure(comptime Checker: type, checker: *Checker, id: @import("ast.zig").NodeId) bool {
    const node = checker.syntax.nodes.items[@backingInt(id)];
    if (node.data != .list_literal) return false;
    for (node.data.list_literal) |element| {
        const checked = checker.resolved.at(@backingInt(element)) orelse return false;
        if (!pure(checker.nodes.items, checker.catalog.records, checked) and !literalListPure(Checker, checker, element)) return false;
    }
    return true;
}

/// Recognize a dictionary-values call (`dicts.values(mapping)`) whose receiver is
/// made only of local field reads.
pub fn dictionaryValuesPure(comptime Checker: type, checker: *Checker, span: source.Span) bool {
    const text = checker.src.text(span);
    const prefix = "dicts.values(";
    if (!std.mem.startsWith(u8, text, prefix) or !std.mem.endsWith(u8, text, ")")) return false;
    const receiver = text[prefix.len .. text.len - 1];
    if (receiver.len == 0) return false;
    for (receiver) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.') return false;
    const base = receiver[0 .. std.mem.indexOfScalar(u8, receiver, '.') orelse receiver.len];
    return checker.active.contains(base);
}

/// The diagnostic and library import associated with one retired sequence operation.
pub const Removal = struct { code: []const u8, message: []const u8, module: []const u8 };

/// Append a retirement diagnostic and, when certain, its origin-local import and rewrite.
pub fn removed(comptime Checker: type, checker: *Checker, span: source.Span, removal: Removal, replacement: ?[]const u8) diagnostic.Error!void {
    const module = removal.module;
    var item: diagnostic.Diagnostic = .{ .code = removal.code, .span = span, .message = removal.message };
    if (replacement) |text| {
        const library = try importRepair(Checker, checker, span, module);
        const prefix = try std.fmt.allocPrint(checker.allocator, "{s}.", .{module});
        const at = std.mem.indexOf(u8, text, prefix) orelse return error.InternalError;
        const rewritten = try std.fmt.allocPrint(checker.allocator, "{s}{s}{s}", .{ text[0..at], library.spelling, text[at + module.len ..] });
        item.provenance.fix = .{ .edit = .{ .span = span, .text = rewritten } };
        if (library.edit) |edit| item.provenance.fix.?.more = try checker.allocator.dupe(diagnostic.Edit, &.{edit});
    }
    try checker.sink.items.append(checker.allocator, item);
}

/// Rewrite a list repetition assignment with one snapshot and one count evaluation.
pub fn listAssignmentFix(comptime Checker: type, checker: *Checker, span: source.Span, name: source.Span, count: source.Span) diagnostic.Error!void {
    const values = try freshName(checker.allocator, checker.src, "repeated_source", span.start);
    const times = try freshName(checker.allocator, checker.src, "repeated_count", span.start);
    const element = try freshName(checker.allocator, checker.src, "repeated_element", span.start);
    var start = span.start;
    while (start > 0 and checker.src.bytes[start - 1] != '\n') start -= 1;
    const indent = checker.src.bytes[start..span.start];
    const binding = checker.src.text(name);
    // migrate-embedded: skip host-generated repair template; not a guest program
    const replacement = try std.fmt.allocPrint(checker.allocator, "const {s} = copy({s})\n" ++
        "{s}mut {s} = int({s})\n" ++
        "{s}if len({s}) == 0:\n" ++
        "{s}    {s} = 0\n" ++
        "{s}{s} = []\n" ++
        "{s}for _ in range({s}):\n" ++
        "{s}    for {s} in {s}:\n" ++
        "{s}        append(mut {s}, copy({s}))", .{
        values, binding, indent, times, checker.src.text(count), indent, values, indent, times, indent, binding, indent, times, indent, element, values, indent, binding, element,
    });
    try checker.sink.appendFix(.{ .code = eRemoved, .span = span, .message = "list repetition assignment was removed; repeat the independent snapshot with explicit loops" }, .{ .span = span, .text = replacement });
}

/// Keep an unsigned augmented count in its original width and operand order.
pub fn unsignedAssignmentFix(comptime Checker: type, checker: *Checker, span: source.Span, operands: struct { name: source.Span, count: source.Span, module: []const u8 }) diagnostic.Error!void {
    const snapshot = try freshName(checker.allocator, checker.src, "repeated_source", span.start);
    var start = span.start;
    while (start > 0 and checker.src.bytes[start - 1] != '\n') start -= 1;
    const count = try freshName(checker.allocator, checker.src, "repeated_count", span.start);
    const indent = checker.src.bytes[start..span.start];
    const prefix = try std.fmt.allocPrint(checker.allocator, "const {s} = copy({s})\n{s}const {s} = {s}\n{s}{s}", .{
        snapshot, checker.src.text(operands.name), indent, count, checker.src.text(operands.count), indent, checker.src.text(operands.name),
    });
    try helperFix(Checker, checker, span, .{
        .sequence = operands.name,
        .count_text = count,
        .module = operands.module,
        .count_first = false,
        .unsigned = true,
        .assignment = prefix,
        .sequence_text = snapshot,
    });
}

fn freshName(allocator: std.mem.Allocator, src: source.Source, stem: []const u8, offset: usize) diagnostic.Error![]const u8 {
    return @import("migration_support.zig").freshOriginNameAt(allocator, src, stem, offset) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidSourceSpan => return error.InternalError,
    };
}

const ImportRepair = struct { spelling: []const u8, edit: ?diagnostic.Edit };

fn importRepair(comptime Checker: type, checker: *Checker, span: source.Span, module: []const u8) diagnostic.Error!ImportRepair {
    try @import("ast.zig").ensureAll(programOf(Checker, checker));
    var start: usize = 0;
    var bytes = checker.src.bytes;
    if (checker.src.origins.len != 0) {
        const original = checker.src.originalSpan(span) catch return error.InternalError;
        start = checker.src.origins[original.input].start;
        bytes = checker.src.origins[original.input].original.bytes;
    }
    var insertion = start;
    var header_allowed = true;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    var offset: usize = 0;
    while (lines.next()) |line| {
        const clean = std.mem.trim(u8, line[0 .. std.mem.indexOfScalar(u8, line, '#') orelse line.len], " \t\r");
        const in_literal = literalContains(Checker, checker, start + offset + (line.len - std.mem.trimStart(u8, line, " \t").len));
        if (header_allowed and std.mem.startsWith(u8, clean, "module ")) insertion = start + offset + line.len + @intFromBool(offset + line.len < bytes.len);
        if (clean.len != 0) header_allowed = false;
        if (!in_literal and std.mem.startsWith(u8, clean, "import ")) {
            var words = std.mem.tokenizeAny(u8, clean[7..], " \t");
            const imported = words.next() orelse continue;
            if (std.mem.eql(u8, imported, module)) {
                const spelling = if (words.next()) |as| if (std.mem.eql(u8, as, "as")) words.next() orelse module else module else module;
                if (!checker.active.contains(spelling)) return .{ .spelling = spelling, .edit = null };
            }
        }
        offset += line.len + 1;
    }
    var spelling = module;
    var index: usize = 0;
    while (containsName(bytes, spelling)) : (index += 1) spelling = try std.fmt.allocPrint(checker.allocator, "{s}_wave1_{d}", .{ module, index });
    const import_text = if (std.mem.eql(u8, spelling, module)) try std.fmt.allocPrint(checker.allocator, "import {s}\n", .{module}) else try std.fmt.allocPrint(checker.allocator, "import {s} as {s}\n", .{ module, spelling });
    return .{ .spelling = spelling, .edit = .{ .span = .{ .start = insertion, .end = insertion }, .text = import_text } };
}

fn programOf(comptime Checker: type, checker: *Checker) @import("ast.zig").Program {
    return if (@hasField(Checker, "syntax")) checker.syntax else checker.program;
}

fn literalContains(comptime Checker: type, checker: *Checker, offset: usize) bool {
    const syntax = programOf(Checker, checker);
    for (syntax.docstrings) |doc| if (offset >= doc.span.start and offset < doc.span.end) return true;
    for (syntax.nodes.items) |node| {
        if (node.data != .text and node.data != .bytes and node.data != .format) continue;
        if (offset >= node.span.start and offset < node.span.end) return true;
    }
    return false;
}

fn containsName(bytes: []const u8, name: []const u8) bool {
    var words = std.mem.tokenizeAny(u8, bytes, " \t\r\n.,:()[]{}+-*/=<>!\"'");
    while (words.next()) |word| if (std.mem.eql(u8, word, name)) return true;
    return false;
}

/// Repair callers of the former fallible standard-library repetition function.
pub fn legacyRepeatCall(comptime Checker: type, checker: *Checker, node: @import("ast.zig").Node, input: @FieldType(@FieldType(@import("ast.zig").Node, "data"), "call"), out: *typed.Node) diagnostic.Error!void {
    if (out.data != .call) return;
    const declaration = checker.syntaxFunction(out.data.call.function);
    if (!std.mem.eql(u8, checker.src.text(declaration.name), "repeat")) return;
    if (!std.mem.endsWith(u8, checker.src.locate(declaration.name.start).path, "@stdlib/strings.selka")) return;
    if (checker.expected_types.get(node.span)) |expected| {
        if (typed.resultShape(expected, checker.catalog.records)) |shape| {
            if (shape.ok_type != out.ty) return;
            const replacement = try std.fmt.allocPrint(checker.allocator, "Ok({s})", .{checker.src.text(node.span)});
            try checker.sink.appendFix(.{ .code = eRemoved, .span = node.span, .message = "strings.repeat now returns str directly; wrap it in Ok only when a Result is required" }, .{ .span = node.span, .text = replacement });
            const value: typed.NodeId = @fromBackingInt(checker.nodes.items.len);
            try checker.nodes.append(checker.allocator, out.*);
            out.ty = expected;
            out.data = .{ .variant = .{ .tag = shape.ok_tag, .value = value } };
            return;
        }
    }
    // The `try` around the call and the `match` on it lie in the call's function body.
    const around = try @import("ast.zig").scanAt(checker.syntax, node.span.start);
    for (checker.syntax.nodes.items[around.node_start..around.node_end]) |parent| {
        if (parent.data != .propagate) continue;
        const operand = checker.syntax.nodes.items[@backingInt(parent.data.propagate)];
        if (operand.span.start != node.span.start or operand.span.end != node.span.end) continue;
        try checker.sink.appendFix(.{ .code = eRemoved, .span = parent.span, .message = "strings.repeat now returns str directly; remove try" }, .{ .span = parent.span, .text = checker.src.text(node.span) });
        return;
    }
    for (checker.syntax.statements.items[around.statement_start..around.statement_end]) |statement| {
        if (statement.data != .match) continue;
        const value = checker.syntax.nodes.items[@backingInt(statement.data.match.value)];
        if (value.span.start != node.span.start or value.span.end != node.span.end) continue;
        const call_text = checker.src.text(node.span);
        const spelling = std.mem.trim(u8, call_text[0 .. std.mem.indexOfScalar(u8, call_text, '(') orelse return], " \t");
        const owner = if (input.owner) |owner| checker.src.text(owner) else spelling[0 .. std.mem.lastIndexOfScalar(u8, spelling, '.') orelse return];
        try legacyMatch(Checker, checker, statement, node, owner);
        return;
    }
}

fn legacyMatch(comptime Checker: type, checker: *Checker, statement: @import("ast.zig").Statement, node: @import("ast.zig").Node, owner: []const u8) diagnostic.Error!void {
    const name = try freshName(checker.allocator, checker.src, "repeated_result", statement.span.start);
    var start = statement.span.start;
    while (start > 0 and checker.src.bytes[start - 1] != '\n') start -= 1;
    const indent = checker.src.bytes[start..statement.span.start];
    const insertion = try std.fmt.allocPrint(checker.allocator, "{s}const {s}: Result[str, {s}.Error] = Ok({s})\n", .{ indent, name, owner, checker.src.text(node.span) });
    var item: diagnostic.Diagnostic = .{ .code = eRemoved, .span = node.span, .message = "strings.repeat now returns str directly; the Result wrapper preserves existing match arms, and a negative count succeeds with empty text" };
    item.provenance.fix = .{ .edit = .{ .span = node.span, .text = name }, .more = try checker.allocator.dupe(diagnostic.Edit, &.{.{ .span = .{ .start = start, .end = start }, .text = insertion }}) };
    try checker.sink.items.append(checker.allocator, item);
}

/// Source operands and the concrete library family of an abstract repetition.
pub const SymbolicRepetition = struct { sequence: @import("ast.zig").NodeId, count: @import("ast.zig").NodeId, module: []const u8, exact_count: bool, count_type: typed.Type = .i64 };

/// Diagnose repetition in an uninstantiated generic body without inventing its types.
pub fn symbolicRepeat(comptime Checker: type, checker: *Checker, operation: @FieldType(@FieldType(@import("ast.zig").Node, "data"), "binary"), operands: SymbolicRepetition) diagnostic.Error!void {
    const sequence = checker.program.nodes.items[@backingInt(operands.sequence)];
    const count = checker.program.nodes.items[@backingInt(operands.count)];
    const left = checker.program.nodes.items[@backingInt(operation.left)];
    const right = checker.program.nodes.items[@backingInt(operation.right)];
    const span = source.Span.join(left.span, right.span);
    var replacement: ?[]const u8 = null;
    const count_first = operation.left == operands.count;
    const unsigned = operands.exact_count and operands.count_type == .u64;
    const count_text = if (unsigned) checker.src.text(count.span) else if (operands.exact_count) try integerCountText(checker.allocator, checker.src, count.span, operands.count_type) else null;
    const order_certain = !count_first or (syntaxPure(Checker, checker, operands.sequence) and syntaxPure(Checker, checker, operands.count));
    if (count_text != null and order_certain and !unsigned) {
        if (std.mem.eql(u8, operands.module, "lists")) {
            if (sequence.data == .list_literal and sequence.data.list_literal.len == 1) {
                const value_id = sequence.data.list_literal[0];
                const value = checker.program.nodes.items[@backingInt(value_id)];
                const stable_value = switch (value.data) {
                    .integer, .boolean, .text, .bytes => true,
                    else => false,
                };
                const reorder = syntaxPure(Checker, checker, operands.count) or stable_value;
                if (syntaxPure(Checker, checker, value_id) and reorder) replacement = try std.fmt.allocPrint(checker.allocator, "lists.filled({s}, {s})", .{ count_text.?, checker.src.text(value.span) });
            }
        } else replacement = try std.fmt.allocPrint(checker.allocator, "{s}.repeat({s}, {s})", .{ operands.module, checker.src.text(sequence.span), count_text.? });
    }
    if (replacement == null and count_text != null) {
        try helperFix(Checker, checker, span, .{ .sequence = sequence.span, .count_text = count_text.?, .module = operands.module, .count_first = count_first, .unsigned = unsigned });
    } else try removed(Checker, checker, span, .{ .code = eRemoved, .message = "sequence repetition was removed; use an explicit library word or loop, preserving generic type requirements", .module = operands.module }, replacement);
}

fn syntaxPure(comptime Checker: type, checker: *Checker, id: @import("ast.zig").NodeId) bool {
    return switch (checker.program.nodes.items[@backingInt(id)].data) {
        .integer, .boolean, .text, .bytes, .unit => true,
        .list_literal => |elements| literal: {
            for (elements) |element| if (!syntaxPure(Checker, checker, element)) break :literal false;
            break :literal true;
        },
        .name => |name| checker.active.contains(checker.src.text(name)),
        .field => |field| syntaxPure(Checker, checker, field.base),
        .unary => |unary| unary.op == .not and syntaxPure(Checker, checker, unary.operand),
        else => false,
    };
}

/// Diagnose a generic list scan and publish only a type-correct, pure-operand repair.
pub fn symbolicMembership(comptime Checker: type, checker: *Checker, node: @import("ast.zig").Node, equality: bool, values_view: bool) diagnostic.Error!void {
    const membership = node.data.membership;
    const container = checker.program.nodes.items[@backingInt(membership.container)];
    const needle = checker.program.nodes.items[@backingInt(membership.needle)];
    const pure_container = if (values_view) dictionaryValuesPure(Checker, checker, container.span) else syntaxPure(Checker, checker, membership.container);
    const certain = equality and swapCertain(syntaxPure(Checker, checker, membership.needle), pure_container, checker.src.text(needle.span), checker.src.text(container.span));
    const replacement = if (certain) try std.fmt.allocPrint(checker.allocator, "{s}lists.contains({s}{s}{s}, {s})", .{
        if (membership.negate) "not " else "", if (values_view) "list(" else "", checker.src.text(container.span), if (values_view) ")" else "", checker.src.text(needle.span),
    }) else null;
    try removed(Checker, checker, node.span, .{ .code = "E_LIST_MEMBERSHIP_REMOVED", .message = "list membership was removed; use lists.contains and require equality for its element type", .module = "lists" }, replacement);
}
