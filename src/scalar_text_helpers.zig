//! Wave 3's scalar text helpers: `strings.char_count`, `char_at`, `char_slice`,
//! `char_stride`, `chars`, `bytes` and `lists.stride`.
//!
//! Phase 1 of the wave refuses the scalar meaning of `len`, indexing and slicing
//! on a `str`, and direct iteration over one. Each refusal carries the certain
//! rewrite to one of these helpers, so `selka fix` moves a project without
//! changing what it computes. The helpers are recognised here, before ordinary
//! name resolution, and each lowers to the very Core operation the old form
//! used, so a migrated site keeps today's value, evaluation order and trap.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const collections = @import("collection_lower.zig");
const call_arguments = @import("call_arguments.zig");
const frontend_units = @import("frontend_units.zig");
const buffer_operations = @import("buffer_operations.zig");
const import_fix = @import("import_fix.zig");

/// The diagnostic code for iterating a `str` directly.
pub const iteration_code = "E_TEXT_ITERATION";
/// The module whose qualified spelling names a text helper.
const strings_module = "strings";
/// The module whose qualified spelling names the list helper.
const lists_module = "lists";
/// One recognised helper call.
pub const ScalarHelper = enum { char_count, char_at, char_slice, char_stride, chars, bytes, list_stride, char_find, char_rfind, char_index, char_rindex, char_count_of, char_startswith, char_endswith };

const Call = @FieldType(@FieldType(ast.Node, "data"), "call");

/// The helper a qualified call names, or null for every other call. The parser
/// records a module-qualified call as an owner and a member; a relaxed or
/// migrated pass may leave the whole dotted path in the call's name instead, so
/// both shapes name the same helper.
pub fn helper(comptime Checker: type, checker: *Checker, call: Call) ?ScalarHelper {
    if (call.type_arguments.len != 0) return null;
    if (call.owner) |owner| return named(checker.src.text(owner), checker.src.text(call.name));
    const text = checker.src.text(call.name);
    const dot = std.mem.lastIndexOfScalar(u8, text, '.') orelse return null;
    return named(text[0..dot], text[dot + 1 ..]);
}

/// The helper `module.name` names.
pub fn named(module: []const u8, name: []const u8) ?ScalarHelper {
    if (std.mem.eql(u8, module, strings_module)) {
        inline for (.{ "char_count", "char_at", "char_slice", "char_stride", "chars", "bytes", "char_find", "char_rfind", "char_index", "char_rindex", "char_count_of", "char_startswith", "char_endswith" }) |spelling| {
            if (std.mem.eql(u8, name, spelling)) return @field(ScalarHelper, spelling);
        }
        return null;
    }
    if (std.mem.eql(u8, module, lists_module) and std.mem.eql(u8, name, "stride")) return .list_stride;
    return null;
}

/// The module a helper belongs to, whose `import` the call needs (B2).
pub fn moduleOf(candidate: ScalarHelper) []const u8 {
    return if (candidate == .list_stride) lists_module else strings_module;
}

/// The qualifiers the checked unit imports: a project answers per declaring
/// module, a single unit from its own `import` directives.
fn imports(comptime Checker: type, checker: *Checker, span: source.Span, module: []const u8) bool {
    if (@hasField(Checker, "catalog")) if (checker.catalog.module_names) |names| {
        if (names.moduleOf(span) catch null) |declaring| {
            if (std.mem.eql(u8, declaring, module)) return true;
        }
        return names.importsModule(span, module) catch false;
    };
    if (@hasField(Checker, "module_names")) if (checker.module_names) |names| {
        if (names.moduleOf(span) catch null) |declaring| {
            if (std.mem.eql(u8, declaring, module)) return true;
        }
        return names.importsModule(span, module) catch false;
    };
    if (std.mem.eql(u8, pathModule(checker.src.path), module)) return true;
    return import_fix.importsModule(checker.src.bytes, module);
}

/// The module name a unit's file path gives it. Module identity comes from the
/// path, so a file named `strings.selka` *is* the strings module and reaches the
/// helpers it names without an import of itself.
fn pathModule(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| return base[0..dot];
    return base;
}

/// Whether this check sees a module graph: only then is a missing `import` a
/// fact about the unit rather than a spelling the unit cannot write.
fn checkedAsModule(comptime Checker: type, checker: *Checker) bool {
    if (@hasField(Checker, "catalog")) if (checker.catalog.module_names) |names| return names.moduleGraph();
    if (@hasField(Checker, "module_names")) if (checker.module_names) |names| return names.moduleGraph();
    return false;
}

/// The offset a missing import belongs at, in the coordinates the check reports
/// in: the unit's own bytes, or the declaring module's mapped into a project's.
fn placement(comptime Checker: type, checker: *Checker, span: source.Span, module_name: []const u8) diagnostic.Error!?import_fix.Placement {
    if (@hasField(Checker, "catalog")) if (checker.catalog.module_names) |names| {
        const original = names.src.originalSpan(span) catch return error.InternalError;
        const unit = &names.index.project.modules.items[original.input];
        const local = import_fix.placement(unit.src.bytes, module_name);
        const mapped = names.src.mappedSpan(original.input, .{ .start = local.offset, .end = local.offset }) catch return null;
        return .{ .offset = mapped.start, .blank_after = local.blank_after };
    };
    return import_fix.placement(checker.src.bytes, module_name);
}

/// Refuse a helper call whose module the unit does not import, with the
/// `import` line as its certain repair (B2).
pub fn requireImport(comptime Checker: type, checker: *Checker, span: source.Span, candidate: ScalarHelper) diagnostic.Error!void {
    // A single-file program cannot write an `import` at all (the single-unit
    // grammar has no directive), so the prelude spellings stand in for one. The
    // rule binds where a module exists: a checked project module must import the
    // module whose function it names.
    if (!checkedAsModule(Checker, checker)) return;
    const module = moduleOf(candidate);
    if (imports(Checker, checker, span, module)) return;
    const message = try import_fix.message(checker.allocator, checker.src.text(span), module);
    if (try placement(Checker, checker, span, module)) |where| return checker.sink.failFix(import_fix.code, span, message, try import_fix.edit(checker.allocator, where, module));
    return checker.sink.fail(import_fix.code, span, message);
}

/// The argument positions of a helper that accept an omitted endpoint (`None`).
pub fn optionalPositions(candidate: ScalarHelper) []const usize {
    return switch (candidate) {
        .char_slice, .char_stride, .list_stride => &.{ 1, 2 },
        else => &.{},
    };
}

/// Give each `None` endpoint its expected `Option[int]`, so the literal is
/// checked as an optional integer before the call is lowered.
pub fn hintEndpoints(comptime Checker: type, checker: *Checker, call: Call, candidate: ScalarHelper) diagnostic.Error!void {
    const optional = optionalPositions(candidate);
    if (optional.len == 0) return;
    const option = try collections.optionType(&checker.catalog, .i64, call.name);
    for (call.arguments, 0..) |argument, position| {
        if (std.mem.indexOfScalar(usize, optional, position) == null) continue;
        const span = checker.syntax.nodes.items[@backingInt(argument)].span;
        if (frontend_units.isNone(checker.src, span)) try checker.hint(argument, option);
    }
}

/// Queue a helper call's arguments for checking, in source order, and answer
/// whether this call was one. The call itself is checked by `attempt` after its
/// arguments, exactly like a declared call.
/// `resolved` is the helper an alias or a re-export of the declared helper names (W10), when the caller resolved one.
pub fn queue(comptime Checker: type, checker: *Checker, work: anytype, call: Call, resolved: ?ScalarHelper) diagnostic.Error!bool {
    const candidate = helper(Checker, checker, call) orelse resolved orelse return false;
    try call_arguments.positional(call, checker.sink);
    try hintEndpoints(Checker, checker, call, candidate);
    var index = call.arguments.len;
    while (index > 0) {
        index -= 1;
        try work.append(checker.allocator, .{ .id = call.arguments[index] });
    }
    return true;
}

/// Whether a call's helper name is in iteration position only.
pub fn loopSource(candidate: ScalarHelper) bool {
    return candidate == .chars or candidate == .bytes;
}

/// Check one recognised helper call, answering whether it was one.
pub fn attempt(comptime Checker: type, checker: *Checker, node: ast.Node, call: Call, out: *typed.Node) diagnostic.Error!bool {
    const candidate = helper(Checker, checker, call) orelse return false;
    try requireImport(Checker, checker, node.span, candidate);
    return attemptHelper(Checker, checker, node, call, candidate, out);
}

/// Check one helper call whose helper the caller resolved (W10): an import alias, a re-export or the `builtin func`
/// declaration's own body. The module's import was already resolved there.
pub fn attemptHelper(comptime Checker: type, checker: *Checker, node: ast.Node, call: Call, candidate: ScalarHelper, out: *typed.Node) diagnostic.Error!bool {
    try call_arguments.positional(call, checker.sink);
    for (call.arguments) |argument| {
        const marked = checker.syntax.nodes.items[@backingInt(argument)];
        if (marked.data == .mut_argument) return checker.sink.failOwnership(
            .{ .code = "E_MUTATION_MARKER", .rule = .M3 },
            marked.span,
            "a text helper reads its arguments; remove `mut`",
        );
    }
    switch (candidate) {
        .char_count => out.* = try count(Checker, checker, node, call),
        .char_at => out.* = try at(Checker, checker, node, call),
        .char_slice => out.* = try slice(Checker, checker, node, call, false),
        .char_stride => out.* = try slice(Checker, checker, node, call, true),
        .list_stride => out.* = try sequenceStride(Checker, checker, node, call),
        .char_find => out.* = try search(Checker, checker, node, call, .{ .find, .find_start, .find_range }),
        .char_rfind => out.* = try search(Checker, checker, node, call, .{ .rfind, .rfind_start, .rfind_range }),
        .char_index => out.* = try search(Checker, checker, node, call, .{ .text_index, .text_index_start, .text_index_range }),
        .char_rindex => out.* = try search(Checker, checker, node, call, .{ .rindex, .rindex_start, .rindex_range }),
        .char_count_of => out.* = try search(Checker, checker, node, call, .{ .count, .count_start, .count_range }),
        .char_startswith => out.* = try search(Checker, checker, node, call, .{ .starts_with, .starts_with_start, .starts_with_range }),
        .char_endswith => out.* = try search(Checker, checker, node, call, .{ .ends_with, .ends_with_start, .ends_with_range }),
        .chars, .bytes => return checker.sink.fail(
            iteration_code,
            node.span,
            if (candidate == .chars)
                "`strings.chars(value)` is a loop source; write `for c in strings.chars(value):`"
            else
                "`strings.bytes(value)` is a loop source; write `for b in strings.bytes(value):`",
        ),
    }
    return true;
}

/// The number of Unicode scalars, which is what `len(value)` counts today.
fn count(comptime Checker: type, checker: *Checker, node: ast.Node, call: Call) diagnostic.Error!typed.Node {
    if (call.arguments.len != 1) return arity(Checker, checker, call, "strings.char_count(value: str) -> int");
    const base = try receiver(Checker, checker, call.arguments[0], "strings.char_count(value: str) -> int");
    return .{ .span = node.span, .ty = .i64, .data = .{ .length = base } };
}

/// The one-scalar text at a scalar position, which is what `value[index]` is today.
fn at(comptime Checker: type, checker: *Checker, node: ast.Node, call: Call) diagnostic.Error!typed.Node {
    const signature = "strings.char_at(value: str, index: int) -> str";
    if (call.arguments.len != 2) return arity(Checker, checker, call, signature);
    const base = try receiver(Checker, checker, call.arguments[0], signature);
    const index = checker.resolved.at(@backingInt(call.arguments[1])).?;
    try checker.requireInteger(checker.nodes.items[@backingInt(index)].ty, checker.syntax.nodes.items[@backingInt(call.arguments[1])].span);
    try @import("negative_index.zig").check(Checker, checker, index, false);
    // The surface `text[index]` reads a byte from this wave on, so the scalar
    // read is the text `.read` operation.
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = node.span };
    return b.access(base, .read, &.{index}, false);
}

/// A bounded slice, copied exactly as `value[start:end]` copies it today; a
/// `value[first:last:step]` when `stepped`.
fn slice(comptime Checker: type, checker: *Checker, node: ast.Node, call: Call, stepped: bool) diagnostic.Error!typed.Node {
    const signature = if (stepped) "strings.char_stride(value: str, start: int?, end: int?, step: int) -> str" else "strings.char_slice(value: str, start: int?, end: int?) -> str";
    const expected = if (stepped) @as(usize, 4) else 3;
    if (call.arguments.len != expected) return arity(Checker, checker, call, signature);
    const base = try receiver(Checker, checker, call.arguments[0], signature);
    const start = try bound(Checker, checker, call.arguments[1]);
    const end = try bound(Checker, checker, call.arguments[2]);
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = node.span };
    if (!stepped) return b.textSlice(base, start, end);
    const step = checker.resolved.at(@backingInt(call.arguments[3])).?;
    try checker.requireInteger(checker.nodes.items[@backingInt(step)].ty, checker.syntax.nodes.items[@backingInt(call.arguments[3])].span);
    return b.sliceStep(base, start, end, step);
}

/// A stepped walk of a list, copied exactly as `values[first:last:step]` copies it today.
fn sequenceStride(comptime Checker: type, checker: *Checker, node: ast.Node, call: Call) diagnostic.Error!typed.Node {
    const signature = "lists.stride(values: T[], start: int?, end: int?, step: int) -> T[]";
    if (call.arguments.len != 4) return arity(Checker, checker, call, signature);
    const base = checker.resolved.at(@backingInt(call.arguments[0])).?;
    const ty = checker.nodes.items[@backingInt(base)].ty;
    if (!ty.isAggregate() or checker.catalog.records[ty.recordIndex()].collection.kind != .list)
        return checker.sink.fail("E_TYPE", checker.syntax.nodes.items[@backingInt(call.arguments[0])].span, "lists.stride requires a list");
    const start = try bound(Checker, checker, call.arguments[1]);
    const end = try bound(Checker, checker, call.arguments[2]);
    const step = checker.resolved.at(@backingInt(call.arguments[3])).?;
    try checker.requireInteger(checker.nodes.items[@backingInt(step)].ty, checker.syntax.nodes.items[@backingInt(call.arguments[3])].span);
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = node.span };
    return b.sliceStep(base, start, end, step);
}

/// One checked `str` receiver of a text helper.
fn receiver(comptime Checker: type, checker: *Checker, id: ast.NodeId, signature: []const u8) diagnostic.Error!typed.NodeId {
    const value = checker.resolved.at(@backingInt(id)).?;
    const ty = checker.nodes.items[@backingInt(value)].ty;
    if (!ty.isAggregate() or checker.catalog.records[ty.recordIndex()].collection.kind != .string)
        return checker.sink.fail("E_TYPE", checker.syntax.nodes.items[@backingInt(id)].span, try std.fmt.allocPrint(checker.allocator, "`{s}` requires a str", .{signature}));
    return value;
}

/// One optional slice endpoint: `None` stays omitted, any other value must be an integer.
fn bound(comptime Checker: type, checker: *Checker, id: ast.NodeId) diagnostic.Error!?typed.NodeId {
    const syntax = checker.syntax.nodes.items[@backingInt(id)];
    if (frontend_units.isNone(checker.src, syntax.span)) return null;
    const value = checker.resolved.at(@backingInt(id)).?;
    try checker.requireInteger(checker.nodes.items[@backingInt(value)].ty, syntax.span);
    return value;
}

/// One scalar search helper: the receiver, a needle, and the optional scalar
/// `start`/`end` the method form took. It lowers to the very operation the method
/// lowered to, so the value, the evaluation order and the trap are the old ones;
/// C1 refuses that method form and rewrites it here (DECISIONS F18).
fn search(comptime Checker: type, checker: *Checker, node: ast.Node, call: Call, kinds: [3]buffer_operations.Kind) diagnostic.Error!typed.Node {
    const signature = "strings.char_<find|rfind|index|rindex|count_of|startswith|endswith>(value: str, needle: str, start: int?, end: int?) -> int";
    if (call.arguments.len < 2 or call.arguments.len > 4) return arity(Checker, checker, call, signature);
    const base = try receiver(Checker, checker, call.arguments[0], signature);
    var resolved: [3]typed.NodeId = undefined;
    for (call.arguments[1..], 0..) |argument, index| {
        const value = checker.resolved.at(@backingInt(argument)).?;
        const syntax = checker.syntax.nodes.items[@backingInt(argument)];
        if (index == 0) {
            const ty = checker.nodes.items[@backingInt(value)].ty;
            if (!ty.isAggregate() or checker.catalog.records[ty.recordIndex()].collection.kind != .string)
                return checker.sink.fail("E_TYPE", syntax.span, "the searched value must be a str");
        } else try checker.requireInteger(checker.nodes.items[@backingInt(value)].ty, syntax.span);
        resolved[index] = value;
    }
    const extra = call.arguments.len - 1;
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = node.span };
    const owner = try b.readOwner(checker.nodes.items[@backingInt(base)].ty);
    const init = try b.stmt(.{ .initialize = .{ .slot = owner, .value = base } });
    const operation = try b.operation(owner, kinds[extra - 1], resolved[0..extra]);
    // The helper's range arguments are the method's: normalize a negative position
    // exactly as the method did, with the same refusal and repair.
    var produced = checker.nodes.items[@backingInt(operation)];
    try checker.normalizeNegativePositions(&produced);
    const value = if (std.meta.eql(produced.data, checker.nodes.items[@backingInt(operation)].data))
        operation
    else blk: {
        const fresh: typed.NodeId = @fromBackingInt(checker.nodes.items.len);
        try checker.nodes.append(checker.allocator, produced);
        break :blk fresh;
    };
    // C2: the helpers keep the scalar window and the scalar answer, so the mark
    // goes on the operation the normalization may have rebuilt behind this block.
    markScalar(Checker, checker, value);
    return b.block(&.{init}, value);
}

/// Mark the search a scalar helper built, so its window and its answer stay in
/// scalar positions (C2). A normalized search sits behind the block that roots
/// its receiver; only an operation can carry the mark.
fn markScalar(comptime Checker: type, checker: *Checker, value: typed.NodeId) void {
    const checked = checker.nodes.items[@backingInt(value)];
    const operation = if (checked.data == .block_value) checked.data.block_value.value else value;
    const data = checker.nodes.items[@backingInt(operation)].data;
    if (data != .buffer_operation) return;
    checker.nodes.items[@backingInt(operation)].data.buffer_operation.scalar = true;
}

fn arity(comptime Checker: type, checker: *Checker, call: Call, signature: []const u8) diagnostic.Error {
    const message = try std.fmt.allocPrint(checker.allocator, "`{s}` takes a fixed argument count, but this call passes {d}", .{ signature, call.arguments.len });
    return checker.sink.fail("E_ARITY", call.name, message);
}

/// The repair's text for one index or bound argument. A constant negative
/// position has wave 1's own certain rewrite — an offset from the length — and
/// the length of a `str` is its scalar count here, so the rewrite composes with
/// this one instead of leaving `text[-1]` as `strings.char_at(text, -1)`, which
/// would trap where the old form counted from the end.
pub fn argumentText(comptime Checker: type, checker: *Checker, base_span: source.Span, value_span: source.Span, clamp: bool) diagnostic.Error![]const u8 {
    const text = checker.src.text(value_span);
    const negative = negativeLiteral(text) orelse return text;
    const base = checker.src.text(base_span);
    return if (clamp)
        std.fmt.allocPrint(checker.allocator, "max(strings.char_count({s}) - {s}, 0)", .{ base, negative })
    else
        std.fmt.allocPrint(checker.allocator, "strings.char_count({s}) - {s}", .{ base, negative });
}

/// The digits of a source text that is exactly one negative integer literal.
fn negativeLiteral(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len < 2 or trimmed[0] != '-') return null;
    const digits = std.mem.trim(u8, trimmed[1..], " \t");
    if (digits.len == 0) return null;
    for (digits) |byte| if (!std.ascii.isDigit(byte)) return null;
    return digits;
}

/// Refuse iterating a `str` directly and attach its certain rewrite.
pub fn refuseIteration(comptime Checker: type, checker: *Checker, span: source.Span, rewrite: []const u8) diagnostic.Error!void {
    const message = "iterating a `str` directly was removed: text has scalar positions and octets, so write " ++
        "`for c in strings.chars(text):` for its Unicode scalars or `for b in strings.bytes(text):` for its octets";
    try checker.sink.appendFix(.{ .code = iteration_code, .span = span, .message = message }, .{ .span = span, .text = rewrite });
}

/// Whether a checked type is immutable text, whose old scalar forms are refused.
pub fn scalarText(checker: anytype, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const schema = checker.catalog.records[ty.recordIndex()];
    return schema.collection.kind == .string;
}
