//! Checking of builtin calls: float intrinsics and numeric conversions, prelude
//! calls, `sorted`/`list.sort` keywords and key lambdas, `open`/file methods,
//! `print` and `Stream` writes, and the `Some`/`None`/`Ok`/`Err` constructors.
//! Each check is a free function over the concrete checker type; `Checks`
//! exposes the ones the rest of the checker calls as `self.name(...)`.
const buffer_operations = @import("buffer_operations.zig");
const collections = @import("collection_lower.zig");
const option_flow = @import("option_flow.zig");
const call_arguments = @import("call_arguments.zig");
const io_builtins = @import("io_builtins.zig");
const io_render = @import("io_render.zig");
const file_operations = @import("file_operations.zig");
const callables = @import("callables.zig");
const std = @import("std");
const print_signature = buffer_operations.stream_print_signature;
const sorted_signature = buffer_operations.sorted_signature;
const list_sort_signature = buffer_operations.list_sort_signature;
const ast = @import("ast.zig");
const effect_set = @import("effect_set.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const numeric_surface = @import("numeric_surface.zig");
const prelude = @import("prelude.zig");
const prelude_builtins = @import("prelude_builtins.zig");
const sema_shared = @import("sema_shared.zig");
const call_argument_code = sema_shared.call_argument_code;
const eCollectionMethod = sema_shared.eCollectionMethod;
const eFileArgument = sema_shared.eFileArgument;
const Pending = sema_shared.Pending;
const Work = sema_shared.Work;
const uninferred_lambda = sema_shared.uninferred_lambda;
/// The accepted spelling for Python 2's `cmp=` comparison function.
const sort_cmp_alternative = "there is no comparison-function form; key= maps each element to the value compared instead, such as key=lambda item: (item.rank, item.name)";
/// One sort call's operands as written: the callee name the diagnostics point
/// at, the operands and their keywords, how many leading operands are the
/// positional list, and the signature a rejection shows.
const SortSite = struct { name: source.Span, arguments: []const ast.NodeId, names: []const ?source.Span, positional: usize, signature: []const u8 };
/// The `key=` and `reverse=` operands of one sort call, and whether `reverse=`
/// was written first.
const SortKeywords = struct { key: ?ast.NodeId = null, reverse: ?ast.NodeId = null, reverse_first: bool = false };
/// The Option type a `Some(...)` call must build, and its variant shape.
const ExpectedOption = struct { ty: typed.Type, shape: prelude.OptionShape };
/// A `print`/`write` call on a local `Stream`: the checked receiver and whether it writes.
const StreamMethod = struct { stream: typed.NodeId, write: bool };
const impl = @This();
/// Bind builtin-call checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// The record index of a `Cell(...)` constructor call, unless a local or function named
        /// `Cell` shadows the builtin.
        pub fn cellConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?usize {
            return impl.cellConstructor(Checker, self, call);
        }
        /// Check the free `read_text(fs, path)` spelling, whose leading argument is
        /// the capability the method form carries as its receiver.
        pub fn checkFileAccessCall(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, out: *typed.Node) Error!void {
            return impl.checkFileAccessCall(Checker, self, node, call, kind, out);
        }
        /// Check the qualified `fs.read_text(path)` spelling on a local `Filesystem`.
        pub fn checkFileAccessMethod(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, out: *typed.Node) Error!void {
            return impl.checkFileAccessMethod(Checker, self, node, call, kind, out);
        }
        /// Check the qualified `fs.read_text(path)` spelling on a receiver reached
        /// through an expression, such as a record field. The receiver is already
        /// checked; the value arguments must be too.
        pub fn checkFileAccessOn(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, receiver: typed.NodeId, out: *typed.Node) Error!void {
            return impl.checkFileAccessOn(Checker, self, node, call, kind, receiver, out);
        }
        /// A file method's result type follows its receiver's text or binary mode.
        pub fn checkFileMethod(self: *Checker, node: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), "file_operation"), out: *typed.Node) Error!void {
            return impl.checkFileMethod(Checker, self, node, operation, out);
        }
        /// Check a prelude float operation such as `sqrt(x)`: the argument must be a float.
        pub fn checkFloatIntrinsic(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), op: typed.UnaryOp, out: *typed.Node) Error!void {
            return impl.checkFloatIntrinsic(Checker, self, node, call, op, out);
        }
        /// `values.sort(key=..., reverse=...)` on a list local: sort it in place.
        pub fn checkListSort(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, out: *typed.Node) Error!void {
            return impl.checkListSort(Checker, self, node, call, slot, out);
        }
        /// `receiver.sort(key=..., reverse=...)` on any list expression: the
        /// receiver is checked already; hint and check the named operands in
        /// source order, then sort the list the receiver evaluated to in place.
        pub fn checkMethodListSort(self: *Checker, node: ast.Node, base: typed.NodeId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkMethodListSort(Checker, self, node, base, temporaries);
        }
        /// Check `int(x)` or `float(x)`: a numeric conversion, or an Option-returning parse
        /// when the argument is text.
        pub fn checkNumericConversion(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), floating: bool, out: *typed.Node) Error!void {
            return impl.checkNumericConversion(Checker, self, node, call, floating, out);
        }
        /// Check `Some(value)` against the Option type the context expects.
        pub fn checkOptionConstructor(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
            return impl.checkOptionConstructor(Checker, self, node, call, out);
        }
        /// Build one prelude builtin call, or report that a later recognizer owns it.
        pub fn checkPreludeCall(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
            return impl.checkPreludeCall(Checker, self, node, call, out);
        }
        /// Check a `print` call's operands and its `sep=`/`end=` keywords into a print node.
        pub fn checkPrint(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), target: PrintTarget, out: *typed.Node) Error!void {
            return impl.checkPrint(Checker, self, node, call, target, out);
        }
        /// Check `Ok(value)` or `Err(value)` against the Result type the context expects.
        pub fn checkResultConstructor(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), ok: bool, out: *typed.Node) Error!void {
            return impl.checkResultConstructor(Checker, self, node, call, ok, out);
        }
        /// `print` and `write` on a `Stream` reached through an expression rather
        /// than a bare name, such as a class field (`sink.stream.write(data)`). The
        /// parser hands such a call over as a method call, so it lands here with its
        /// receiver already checked; it lowers exactly like the named-receiver form.
        /// A method call carries positional arguments only, so `sep=` and `end=`
        /// still need the stream bound to a name first.
        pub fn checkStreamReceiverMethod(self: *Checker, node: ast.Node, stream: typed.NodeId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkStreamReceiverMethod(Checker, self, node, stream, temporaries);
        }
        /// Check `stream.write(text)`: one `str` or `bytes` argument, returning the byte count.
        pub fn checkStreamWrite(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), stream: typed.NodeId, out: *typed.Node) Error!void {
            return impl.checkStreamWrite(Checker, self, node, call, stream, out);
        }
        /// Type `None` as the expected Option's empty variant, or as `unit` without context.
        pub fn checkUnit(self: *Checker, node: ast.Node) typed.Node {
            return impl.checkUnit(Checker, self, node);
        }
        /// `debug(...)` writes to standard error with no capability and no effect.
        pub fn debugBuiltin(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
            return impl.debugBuiltin(Checker, self, call);
        }
        /// The Option type and shape the context expects for a `Some(...)` call.
        pub fn expectedOption(self: *Checker, node: ast.Node) Error!ExpectedOption {
            return impl.expectedOption(Checker, self, node);
        }
        /// The Result type the context expects for an `Ok(...)` or `Err(...)` call.
        pub fn expectedResult(self: *Checker, node: ast.Node) Error!typed.Type {
            return impl.expectedResult(Checker, self, node);
        }
        /// Whole-path file helpers are reserved under the same shadowing rule as `print`.
        pub fn fileAccessBuiltin(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?file_operations.Access {
            return impl.fileAccessBuiltin(Checker, self, call);
        }
        /// The whole-path helper a qualified call names on a local `Filesystem`, or
        /// null for an ordinary receiver. The method form is never shadowed by a
        /// same-named function or local: it belongs to the receiver alone.
        pub fn fileAccessMethodKind(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?file_operations.Access {
            return impl.fileAccessMethodKind(Checker, self, call);
        }
        /// Recognize `sqrt`, `floor`, `ceil`, `trunc` and `abs` as prelude float operations.
        /// A local binding, a declared function or a module top-level name of the same name wins.
        pub fn floatIntrinsic(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.UnaryOp {
            return impl.floatIntrinsic(Checker, self, call);
        }
        /// An unannotated empty list literal adopts the element type the builtin fixes,
        /// so `any([])`, `sum([])`, `sorted([])` and `list([])` all infer their schema.
        pub fn hintEmptyPreludeList(self: *Checker, id: ast.NodeId, element: typed.Type) Error!void {
            return impl.hintEmptyPreludeList(Checker, self, id, element);
        }
        /// Hint the operands of one keyword `sorted(values, ...)` once the list
        /// operand is checked.
        pub fn hintSortedArguments(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), keywords: SortKeywords) Error!void {
            return impl.hintSortedArguments(Checker, self, call, keywords);
        }
        /// The list local of a `values.sort(...)` call that passes arguments, the
        /// Python keyword form; null for any other call. A bare `values.sort()`
        /// stays the plain buffer operation.
        pub fn listSortOwner(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?typed.LocalId {
            return impl.listSortOwner(Checker, self, call);
        }
        /// Recognize an unshadowed `int(...)` or `float(...)` call; true for `float`.
        pub fn numericConversion(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?bool {
            return impl.numericConversion(Checker, self, call);
        }
        /// Recognize an unshadowed `Some(...)` call.
        pub fn optionConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
            return impl.optionConstructor(Checker, self, call);
        }
        /// `print`/`eprint` without a receiver are gone: once no local binding,
        /// declared function or imported name shadows the spelling, they name
        /// `E_OUTPUT_CAPABILITY` rather than an ambient sink. The same sentence the
        /// message carries is attached as an `alternative` note, so a tool reads the
        /// accepted spelling as data instead of parsing prose, and the primary
        /// message is unchanged.
        pub fn outputBuiltin(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.Sink {
            return impl.outputBuiltin(Checker, self, call);
        }
        /// The bare prelude builtins answer only when no binding, declaration or module name claims them.
        pub fn preludeName(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
            return impl.preludeName(Checker, self, call);
        }
        /// Queue the operands of one `values.sort(key=..., reverse=...)` call in
        /// source order, hinted by the list's element type.
        pub fn queueListSort(self: *Checker, work: *std.ArrayList(Work), call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
            return impl.queueListSort(Checker, self, work, call);
        }
        /// Queue the operands of one prelude builtin call in evaluation order.
        pub fn queuePreludeCall(self: *Checker, work: *std.ArrayList(Work), call_id: ast.NodeId, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
            return impl.queuePreludeCall(Checker, self, work, call_id, call);
        }
        /// The named operands of one `sorted(...)` call, after its positional list.
        pub fn sortedKeywords(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!SortKeywords {
            return impl.sortedKeywords(Checker, self, call);
        }
        /// Resolve the receiver of `stream.print`/`stream.write` to its local slot, or null.
        pub fn streamLocal(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?typed.LocalId {
            return impl.streamLocal(Checker, self, call);
        }
        /// Recognize `stream.print(...)`/`stream.write(...)` on a `Stream` local.
        pub fn streamMethod(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?StreamMethod {
            return impl.streamMethod(Checker, self, call);
        }
    };
}
/// Recognize `sqrt`, `floor`, `ceil`, `trunc` and `abs` as prelude float operations.
/// A local binding, a declared function or a module top-level name of the same name wins.
fn floatIntrinsic(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.UnaryOp {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    const name = self.src.text(call.name);
    const op = @import("float_intrinsics.zig").operation(name) orelse return null;
    if (self.active.contains(name) or self.functions.contains(name)) return null;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    return op;
}
fn checkFloatIntrinsic(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), op: typed.UnaryOp, out: *typed.Node) Error!void {
    const value = self.resolved[@backingInt(call.arguments[0])].?;
    const ty_value = self.nodes.items[@backingInt(value)].ty;
    if (!numeric_surface.isFloat(ty_value, self.catalog.records)) return self.sink.fail("E_TYPE", node.span, "this prelude operation requires a float argument");
    out.* = try self.numericBuilder(node.span).unary(op, value);
}
fn numericConversion(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?bool {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    const name = self.src.text(call.name);
    const floating = std.mem.eql(u8, name, "float");
    if (!floating and !std.mem.eql(u8, name, "int")) return null;
    if (self.active.contains(name) or self.functions.contains(name)) return null;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    return floating;
}
fn checkNumericConversion(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), floating: bool, out: *typed.Node) Error!void {
    const value = self.resolved[@backingInt(call.arguments[0])].?;
    const ty_value = self.nodes.items[@backingInt(value)].ty;
    const input_float = numeric_surface.isFloat(ty_value, self.catalog.records);
    // `int(text)` and `float(text)` parse rather than convert, so they answer an Option.
    if (ty_value.isAggregate() and self.catalog.records[ty_value.recordIndex()].collection.kind == .string) {
        const builder: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        out.* = try builder.access(value, if (floating) .parse_float else .parse_int, &.{}, false);
        return;
    }
    if (!input_float and !ty_value.isInteger()) return self.sink.fail("E_TYPE", node.span, "numeric conversion requires an integer, float or str");
    if (floating) {
        out.* = if (input_float) self.nodes.items[@backingInt(value)] else try self.numericBuilder(node.span).fromInteger(value);
    } else if (input_float) {
        out.* = try self.numericBuilder(node.span).toInteger(value);
    } else out.* = .{ .span = node.span, .ty = .i64, .data = .{ .cast = value } };
}
/// The bare prelude builtins answer only when no binding, declaration or module name claims them.
fn preludeName(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
    if (call.owner != null or call.type_arguments.len != 0) return false;
    const name = self.src.text(call.name);
    if (!prelude_builtins.reserved(name)) return false;
    if (self.active.contains(name) or self.functions.contains(name)) return false;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return false;
    return true;
}
/// The `range(...)` source of `list(range(...))`, which is never an ordinary expression.
fn rangeSource(comptime Checker: type, self: *Checker, id: ast.NodeId) Error!?@FieldType(@FieldType(ast.Node, "data"), "call") {
    const node = self.syntax.nodes.items[@backingInt(id)];
    if (node.data != .call) return null;
    const call = node.data.call;
    if (call.owner != null or call.type_arguments.len != 0) return null;
    if (!std.mem.eql(u8, self.src.text(call.name), "range")) return null;
    if (self.active.contains("range") or self.functions.contains("range")) return null;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    if (call.arguments.len == 0 or call.arguments.len > 2) return null;
    return call;
}
/// An unannotated empty list literal adopts the element type the builtin fixes,
/// so `any([])`, `sum([])`, `sorted([])` and `list([])` all infer their schema.
fn hintEmptyPreludeList(comptime Checker: type, self: *Checker, id: ast.NodeId, element: typed.Type) Error!void {
    const node = self.syntax.nodes.items[@backingInt(id)];
    if (node.data != .list_literal or node.data.list_literal.len != 0) return;
    try self.hint(id, try collections.listType(&self.catalog, element, node.span));
}
/// Hint the fixed element types of one bare prelude builtin's sequence arguments.
fn hintPreludeArguments(comptime Checker: type, self: *Checker, name: []const u8, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
    if (std.mem.eql(u8, name, "zip")) {
        for (call.arguments) |id| try hintEmptyPreludeList(Checker, self, id, .i64);
        return;
    }
    if (call.arguments.len != 1) return;
    if (std.mem.eql(u8, name, "any") or std.mem.eql(u8, name, "all")) return hintEmptyPreludeList(Checker, self, call.arguments[0], .bool);
    inline for (.{ "sum", "min", "max", "sorted", "reversed", "list" }) |builtin| {
        if (std.mem.eql(u8, name, builtin)) return hintEmptyPreludeList(Checker, self, call.arguments[0], .i64);
    }
}
/// Queue the operands of one prelude builtin call in evaluation order.
fn queuePreludeCall(comptime Checker: type, self: *Checker, work: *std.ArrayList(Work), call_id: ast.NodeId, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
    if (!try preludeName(Checker, self, call)) return false;
    const name = self.src.text(call.name);
    if (std.mem.eql(u8, name, "sorted")) {
        const keywords = try sortedKeywords(Checker, self, call);
        if (keywords.key != null or keywords.reverse != null) {
            try work.append(self.allocator, .{ .id = call_id, .sorted_key = true });
            try work.append(self.allocator, .{ .id = call.arguments[0] });
            return true;
        }
    } else try call_arguments.positional(call, self.sink);
    try hintPreludeArguments(Checker, self, name, call);
    const materialized = if (prelude_builtins.materializes(name) and call.arguments.len == 1) try rangeSource(Checker, self, call.arguments[0]) else null;
    const arguments = if (materialized) |range| range.arguments else call.arguments;
    var index = arguments.len;
    while (index > 0) {
        index -= 1;
        try work.append(self.allocator, .{ .id = arguments[index] });
    }
    return true;
}
/// Build one prelude builtin call, or report that a later recognizer owns it.
fn checkPreludeCall(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
    if (!try preludeName(Checker, self, call)) return false;
    const name = self.src.text(call.name);
    if (std.mem.eql(u8, name, "sorted")) {
        out.* = try checkSortedCall(Checker, self, node.span, call);
        return true;
    }
    try call_arguments.positional(call, self.sink);
    const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
    const building_set = std.mem.eql(u8, name, "set");
    if (building_set and call.arguments.len == 0) {
        out.* = try self.checkEmptySet(node.span);
        return true;
    }
    if (building_set and call.arguments.len != 1)
        return self.sink.fail("E_ARITY", node.span, "set takes at most one argument: `set()` or `set(iterable)`");
    if (prelude_builtins.materializes(name) and call.arguments.len == 1) {
        if (try rangeSource(Checker, self, call.arguments[0])) |range| {
            const bounds = try self.allocator.alloc(typed.NodeId, range.arguments.len);
            for (range.arguments, bounds) |id, *slot| slot.* = self.resolved[@backingInt(id)].?;
            out.* = try builtins.rangeList(node.span, bounds);
            if (building_set) out.* = try self.checkSetFromIterable(node.span, try retainNode(Checker, self, out.*));
            return true;
        }
        const input = self.resolved[@backingInt(call.arguments[0])].?;
        // `set(iterable)` (SET-1); `list(s)` of a set is its snapshot in
        // insertion order.
        if (building_set) {
            out.* = try self.checkSetFromIterable(node.span, input);
        } else if (typed.setRecord(self.catalog.records, self.nodes.items[@backingInt(input)].ty) != null) {
            out.* = try setElements(Checker, self, node.span, input);
        } else out.* = try builtins.copyList(node.span, input);
        return true;
    }
    const values = try self.allocator.alloc(typed.NodeId, call.arguments.len);
    for (call.arguments, values) |id, *slot| slot.* = self.resolved[@backingInt(id)].?;
    // A set folds and orders as the list of its elements in insertion order.
    if (values.len == 1 and typed.setRecord(self.catalog.records, self.nodes.items[@backingInt(values[0])].ty) != null)
        values[0] = try retainNode(Checker, self, try setElements(Checker, self, node.span, values[0]));
    out.* = (try builtins.build(node.span, name, values)) orelse return false;
    return true;
}
/// The fresh list of a set's elements in insertion order: the key snapshot of
/// its dictionary representation.
fn setElements(comptime Checker: type, self: *Checker, span: source.Span, input: typed.NodeId) Error!typed.Node {
    return (collections.Builder(Checker){ .checker = self, .span = span }).access(input, .keys, &.{}, false);
}
/// Add a built checked expression to the node table.
fn retainNode(comptime Checker: type, self: *Checker, value: typed.Node) Error!typed.NodeId {
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, value);
    return id;
}
/// Bind the operands of one sort call by name. `site.positional` leading
/// operands are the list (one for `sorted`, none for `values.sort`); every
/// other operand is `key=` or `reverse=`, each at most once and only by
/// keyword, as Python spells them.
fn sortKeywords(comptime Checker: type, self: *Checker, site: SortSite) Error!SortKeywords {
    var out: SortKeywords = .{};
    for (site.arguments, 0..) |argument, index| {
        const keyword = if (site.names.len == 0) null else site.names[index];
        if (index < site.positional) {
            if (keyword) |name| return self.sink.failCallSite(call_argument_code, name, "the sorted list is positional", null, site.signature);
            continue;
        }
        const name = keyword orelse
            return self.sink.failCallSite(call_argument_code, self.syntax.nodes.items[@backingInt(argument)].span, "key and reverse are keyword-only: write key=callback and reverse=flag", null, site.signature);
        const text = self.src.text(name);
        const repeated = if (std.mem.eql(u8, text, "key")) out.key != null else if (std.mem.eql(u8, text, "reverse")) out.reverse != null else null;
        const is_repeat = repeated orelse {
            // Python 2's comparison function has a mechanical repair, so it
            // is named; any other keyword only gets the signature.
            const related: ?diagnostic.Related = if (std.mem.eql(u8, text, "cmp")) .{ .span = name, .message = sort_cmp_alternative, .role = .alternative } else null;
            return self.sink.failCallSite(call_argument_code, site.name, "sorting accepts only the named arguments key= and reverse=", related, site.signature);
        };
        if (is_repeat) return self.sink.failCallSite(call_argument_code, name, "this sort argument is given more than once", null, site.signature);
        if (std.mem.eql(u8, text, "key")) out.key = argument else {
            out.reverse = argument;
            out.reverse_first = out.key == null;
        }
    }
    return out;
}
/// The named operands of one `sorted(...)` call, after its positional list.
fn sortedKeywords(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!SortKeywords {
    if (call.arguments.len == 0) return self.sink.failCallSite("E_ARITY", call.name, "sorted requires a list", null, sorted_signature);
    return sortKeywords(Checker, self, .{ .name = call.name, .arguments = call.arguments, .names = call.argument_names, .positional = 1, .signature = sorted_signature });
}
/// Hint the operands of one keyword sort over a list of `element`:
/// `reverse` is a `bool`, and a lambda key is
/// `def(element) -> K effects(managed_allocation)` with `K` read off its
/// body or, failing that, its body's own type (LAMBDA-KEY-INFER-1). The
/// slot has exactly the type that spelling interns, return-origin bound
/// included, so it is one type with every other callback of that signature.
/// It admits allocation because its one call site is the keyed sort the
/// enclosing function already charges `managed_allocation` for, so a key
/// that builds a `str` is exact rather than exempt (LAMBDA-KEY-INFER-1).
fn hintSortKeywords(comptime Checker: type, self: *Checker, keywords: SortKeywords, element: typed.Type) Error!void {
    if (keywords.reverse) |flag| try self.hint(flag, .bool);
    const key = keywords.key orelse return;
    const node = self.syntax.nodes.items[@backingInt(key)];
    if (node.data != .name) return;
    const result = if (self.lambdaIndex(node.span)) |index| lambda: {
        const lambda = self.syntax.lambdas[index];
        // Any other arity is the lambda's own E_ARITY against the one-element slot.
        if (lambda.parameters.len != 1) break :lambda .i64;
        const read = try lambdaKeyType(Checker, self, lambda.body, self.src.text(lambda.parameters[0]), element);
        break :lambda read orelse inferLambdaKey(Checker, self, lambda, element) catch |err| {
            // Its E_SORT_KEY stands for the lambda too: its own check adds nothing.
            if (err == error.SourceError) self.lambda_types[index] = uninferred_lambda;
            return err;
        };
    } else try namedKeyResult(Checker, self, node.span) orelse return;
    const parameters = try self.allocator.dupe(typed.Type, &.{element});
    const slot: typed.Callable = .{ .parameters = parameters, .return_type = result, .effects = effect_set.bit(.managed_allocation), .mutates = &.{}, .return_origin = .unknown };
    const callback = try callables.intern(self.allocator, &self.catalog, slot, node.span, self.sink);
    try self.hint(key, callback);
}
/// The declared result of a top-level function named as a sort key, so an
/// unannotated key function fills the key slot with the empty ceiling its
/// one element parameter derives, exactly as it fills any callback
/// parameter; null for a local or anything but a nongeneric function.
fn namedKeyResult(comptime Checker: type, self: *Checker, name: source.Span) Error!?typed.Type {
    const text = self.src.text(name);
    if (self.active.contains(text) or std.mem.indexOf(u8, text, "::") != null) return null;
    const key = if (self.catalog.module_names) |names| module: {
        if (!try names.topLevel(name)) return null;
        break :module try names.reference(name, .function, null, null, self.sink);
    } else text;
    const declaration = self.functions.get(key) orelse return null;
    const function = self.syntax.functions[@backingInt(declaration)];
    if (function.policy.owner != null or function.signature.type_parameters.len != 0) return null;
    const result = try self.catalog.resolve(self.src, function.signature.return_type, self.sink);
    return result;
}
/// LAMBDA-KEY-INFER-1: the key type of a one-parameter sort-key lambda whose
/// body is not a shape `lambdaKeyType` reads is the body's ordinary type. The
/// body is checked once here with its parameter bound to the list's element,
/// and every trace of that trial — typed nodes, statements, locals, resolved
/// entries, the parameter binding, option facts, ownership state and
/// diagnostics — is undone, so the lambda is checked for real, against the
/// slot this type fixes, exactly once later. A body that does not type on
/// its own is `E_SORT_KEY` quoting why, never a guessed `int`.
fn inferLambdaKey(comptime Checker: type, self: *Checker, lambda: ast.Lambda, element: typed.Type) Error!typed.Type {
    const saved_nodes = self.nodes.items.len;
    const saved_statements = self.statements.items.len;
    const saved_locals = self.locals.items.len;
    const saved_resolved = self.resolved_nodes.items.len;
    const saved_diagnostics = self.sink.items.items.len;
    const pending = try self.pendingState(saved_locals);
    const facts = try self.option_facts.snapshot(self.allocator);
    const parameter = lambda.parameters[0];
    const name = self.src.text(parameter);
    const shadowed = self.active.get(name);
    try self.locals.append(self.allocator, .{
        .name = name,
        .declaration = parameter,
        .ty = element,
        .mutable = false,
        .ownership = .{ .initialized = true, .transfer_available = self.transfers(element) },
    });
    try self.active.put(self.allocator, name, @fromBackingInt(saved_locals));
    const outcome = self.expression(lambda.body);
    const key_type: ?typed.Type = if (outcome) |value| self.nodes.items[@backingInt(value)].ty else |err| switch (err) {
        error.SourceError => null,
        else => |failure| return failure,
    };
    for (self.resolved_nodes.items[saved_resolved..]) |index| self.resolved[index] = null;
    self.resolved_nodes.shrinkRetainingCapacity(saved_resolved);
    self.nodes.shrinkRetainingCapacity(saved_nodes);
    self.statements.shrinkRetainingCapacity(saved_statements);
    self.locals.shrinkRetainingCapacity(saved_locals);
    if (shadowed) |slot| try self.active.put(self.allocator, name, slot) else _ = self.active.remove(name);
    self.restorePending(pending);
    self.option_facts.restore(facts);
    var reason: ?diagnostic.Diagnostic = null;
    for (self.sink.items.items[saved_diagnostics..]) |item| if (item.severity == .err) {
        reason = item;
        break;
    };
    self.sink.items.shrinkRetainingCapacity(saved_diagnostics);
    if (key_type) |found| return found;
    const why = reason orelse return error.InternalError;
    const message = try std.fmt.allocPrint(self.allocator, "this lambda's key type cannot be inferred from its body ({s}: {s}); write a top-level key function with a declared result and pass it by name", .{ why.code, why.message });
    return self.sink.fail("E_SORT_KEY", lambda.span, message);
}
/// The key type a sort-key lambda's body returns, read off the body when it
/// is the parameter itself, a field path from it, a negation, arithmetic or
/// `len` of one, or a tuple of those; null when the body does not say.
fn lambdaKeyType(comptime Checker: type, self: *Checker, body: ast.NodeId, parameter: []const u8, element: typed.Type) Error!?typed.Type {
    const node = self.syntax.nodes.items[@backingInt(body)];
    switch (node.data) {
        .name => |name| return if (std.mem.eql(u8, self.src.text(name), parameter)) element else null,
        .field => |field| {
            const base = try lambdaKeyType(Checker, self, field.base, parameter, element) orelse return null;
            if (!base.isAggregate() or base.recordIndex() >= self.catalog.records.len) return null;
            const slot = self.catalog.field_names.items[base.recordIndex()].get(self.src.text(field.name)) orelse return null;
            const declared = self.catalog.records[base.recordIndex()].fields;
            return if (slot < declared.len) declared[slot].ty else null;
        },
        .unary => |unary| return if (unary.op == .neg) lambdaKeyType(Checker, self, unary.operand, parameter, element) else null,
        .binary => |binary| return switch (binary.op) {
            .add, .sub, .mul, .div, .floor_div, .rem => try lambdaKeyType(Checker, self, binary.left, parameter, element) orelse try lambdaKeyType(Checker, self, binary.right, parameter, element),
            else => null,
        },
        .length => return .i64,
        .tuple => |items| {
            if (items.len < 2 or items.len > 8) return null;
            const types = try self.allocator.alloc(typed.Type, items.len);
            for (items, types) |item, *slot| slot.* = try lambdaKeyType(Checker, self, item, parameter, element) orelse return null;
            const tuple = try self.catalog.tupleType(types);
            return tuple;
        },
        else => return null,
    }
}
/// Hint the operands of one keyword `sorted(values, ...)` once the list
/// operand is checked.
fn hintSortedArguments(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), keywords: SortKeywords) Error!void {
    const input = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    const input_type = if (self.resolved[@backingInt(call.arguments[0])]) |value|
        self.nodes.items[@backingInt(value)].ty
    else if (input.data == .name) name: {
        const slot = self.active.get(self.src.text(input.data.name)) orelse return;
        break :name self.locals.items[@backingInt(slot)].ty;
    } else return;
    try hintSortKeywords(Checker, self, keywords, try sortedElement(Checker, self, input_type, input.span));
}
/// The element type of the list a keyword `sorted` call sorts.
fn sortedElement(comptime Checker: type, self: *Checker, input_type: typed.Type, span: source.Span) Error!typed.Type {
    if (!input_type.isAggregate()) return self.sink.fail("E_PRELUDE_TYPE", span, "sorted key requires a list input");
    const input_schema = self.catalog.records[input_type.recordIndex()];
    if (typed.isSet(input_schema)) return input_schema.collection.key.?;
    if (!input_schema.isCollection() or input_schema.collection.kind != .list)
        return self.sink.fail("E_PRELUDE_TYPE", span, "sorted key requires a list input");
    return input_schema.shape.buffer.?;
}
/// Check the already checked operands of one keyword sort of a list of
/// `element` in `owner`: the key maps one element to an ordered key, a
/// sort without a key needs an ordered element, and `reverse` is a `bool`.
fn checkedSort(comptime Checker: type, self: *Checker, span: source.Span, element: typed.Type, keywords: SortKeywords, owner: typed.LocalId) Error!prelude_builtins.KeyedSort {
    const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
    var sort: prelude_builtins.KeyedSort = .{ .span = span, .owner = owner, .reverse_first = keywords.reverse_first };
    if (keywords.key) |id| {
        sort.key = self.resolved[@backingInt(id)].?;
        _ = try builtins.sortKey(self.syntax.nodes.items[@backingInt(id)].span, element, sort.key.?);
    } else if (keywords.reverse != null) try self.requireSortable(element, span);
    if (keywords.reverse) |id| {
        sort.reverse = self.resolved[@backingInt(id)].?;
        if (self.nodes.items[@backingInt(sort.reverse.?)].ty != .bool)
            return self.sink.fail("E_TYPE", self.syntax.nodes.items[@backingInt(id)].span, "reverse= takes a bool: reverse=True sorts in descending order");
    }
    return sort;
}
/// `sorted(values, key=..., reverse=...)`: check the named operands and
/// build the sorted copy.
fn checkSortedCall(comptime Checker: type, self: *Checker, span: source.Span, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!typed.Node {
    const keywords = try sortedKeywords(Checker, self, call);
    const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
    var input = self.resolved[@backingInt(call.arguments[0])].?;
    // `sorted(s)` of a set orders the list of its elements (SET-1).
    if (typed.setRecord(self.catalog.records, self.nodes.items[@backingInt(input)].ty) != null)
        input = try retainNode(Checker, self, try setElements(Checker, self, span, input));
    if (keywords.key == null and keywords.reverse == null) return builtins.sorted(.{ .input = input, .sort = .{ .span = span, .owner = undefined } });
    const element = try sortedElement(Checker, self, self.nodes.items[@backingInt(input)].ty, self.syntax.nodes.items[@backingInt(call.arguments[0])].span);
    return builtins.sorted(.{ .input = input, .sort = try checkedSort(Checker, self, span, element, keywords, undefined) });
}
/// The list local of a `values.sort(...)` call that passes arguments, the
/// Python keyword form; null for any other call. A bare `values.sort()`
/// stays the plain buffer operation.
fn listSortOwner(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?typed.LocalId {
    const owner = call.owner orelse return null;
    if (call.arguments.len == 0 or !std.mem.eql(u8, self.src.text(call.name), "sort")) return null;
    const slot = self.active.get(self.src.text(owner)) orelse return null;
    return if (listLocal(Checker, self, slot)) slot else null;
}
fn listLocal(comptime Checker: type, self: *Checker, slot: typed.LocalId) bool {
    const local_type = self.locals.items[@backingInt(slot)].ty;
    if (!local_type.isAggregate()) return false;
    const schema = self.catalog.records[local_type.recordIndex()];
    return schema.isCollection() and schema.collection.kind == .list;
}
fn listSortKeywords(comptime Checker: type, self: *Checker, name: source.Span, arguments: []const ast.NodeId, names: []const ?source.Span) Error!SortKeywords {
    return sortKeywords(Checker, self, .{ .name = name, .arguments = arguments, .names = names, .positional = 0, .signature = list_sort_signature });
}
/// Queue the operands of one `values.sort(key=..., reverse=...)` call in
/// source order, hinted by the list's element type.
fn queueListSort(comptime Checker: type, self: *Checker, work: *std.ArrayList(Work), call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
    const slot = listSortOwner(Checker, self, call) orelse return false;
    const keywords = try listSortKeywords(Checker, self, call.name, call.arguments, call.argument_names);
    try hintSortKeywords(Checker, self, keywords, self.catalog.records[self.locals.items[@backingInt(slot)].ty.recordIndex()].shape.buffer.?);
    var index = call.arguments.len;
    while (index > 0) {
        index -= 1;
        try work.append(self.allocator, .{ .id = call.arguments[index] });
    }
    return true;
}
/// `values.sort(key=..., reverse=...)` on a list local: sort it in place.
fn checkListSort(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, out: *typed.Node) Error!void {
    const keywords = try listSortKeywords(Checker, self, call.name, call.arguments, call.argument_names);
    const local = &self.locals.items[@backingInt(slot)];
    local.usage.reads += 1;
    local.usage.writes += 1;
    const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;
    const sort = try checkedSort(Checker, self, node.span, element, keywords, slot);
    const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    out.* = try b.block(try builtins.keyedSort(sort), try b.node(.unit, .unit));
}
/// `receiver.sort(key=..., reverse=...)` on any list expression: the
/// receiver is checked already; hint and check the named operands in
/// source order, then sort the list the receiver evaluated to in place.
fn checkMethodListSort(comptime Checker: type, self: *Checker, node: ast.Node, base: typed.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    const call = node.data.method_call;
    const keywords = try listSortKeywords(Checker, self, call.name, call.arguments, call.argument_names);
    const list = self.nodes.items[@backingInt(base)].ty;
    const element = try self.listElement(list, node.span);
    try hintSortKeywords(Checker, self, keywords, element);
    for (call.arguments) |argument| _ = try self.expressionWithTemporaries(argument, temporaries);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const owner = try b.local(list);
    const sort = try checkedSort(Checker, self, node.span, element, keywords, owner);
    const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
    var statements: std.ArrayList(typed.StatementId) = .empty;
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = owner, .value = base } }));
    try statements.appendSlice(self.allocator, try builtins.keyedSort(sort));
    return b.block(statements.items, try b.node(.unit, .unit));
}
/// Whole-path file helpers are reserved under the same shadowing rule as `print`.
fn fileAccessBuiltin(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?file_operations.Access {
    if (call.owner != null) return null;
    const name = self.src.text(call.name);
    const kind = file_operations.access(name) orelse return null;
    if (self.active.contains(name) or self.functions.contains(name)) return null;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    return kind;
}
/// The whole-path helper a qualified call names on a local `Filesystem`, or
/// null for an ordinary receiver. The method form is never shadowed by a
/// same-named function or local: it belongs to the receiver alone.
fn fileAccessMethodKind(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?file_operations.Access {
    const owner = call.owner orelse return null;
    const slot = self.active.get(self.src.text(owner)) orelse return null;
    if (self.locals.items[@backingInt(slot)].ty != .filesystem_cap) return null;
    return file_operations.access(self.src.text(call.name));
}
fn fileShapes(comptime Checker: type, self: *Checker, span: source.Span) Error!typed.FileShapes {
    const text = try collections.preludeType(&self.catalog, "str", span);
    const bytes = try collections.preludeType(&self.catalog, "bytes", span);
    return .{ .text = text, .bytes = bytes, .list = try collections.listType(&self.catalog, text, span) };
}
/// The declared result of one whole-path helper, given the open mode it saw.
fn fileAccessType(comptime Checker: type, self: *Checker, kind: file_operations.Access, mode: file_operations.Mode, span: source.Span) Error!typed.Type {
    const shapes = try fileShapes(Checker, self, span);
    const payload: typed.Type = switch (kind) {
        .open => if (mode.text) .text_file else .file,
        .read_file => shapes.bytes,
        .read_text => shapes.text,
        .listdir => shapes.list,
        .exists => return .bool,
        else => .unit,
    };
    return collections.resultType(&self.catalog, payload, shapes.text, span);
}
/// Check one whole-path helper after its receiver, shared by the free
/// `read_text(fs, path)` and qualified `fs.read_text(path)` spellings.
/// `value_arguments` excludes the capability, so `arguments[0]` is the
/// receiver and the typed operand order matches the free form exactly.
fn checkFileAccess(comptime Checker: type, self: *Checker, node: ast.Node, kind: file_operations.Access, receiver: typed.NodeId, value_arguments: []const ast.NodeId, out: *typed.Node) Error!void {
    const shapes = try fileShapes(Checker, self, node.span);
    const arguments = try self.allocator.alloc(typed.NodeId, value_arguments.len + 1);
    arguments[0] = receiver;
    for (value_arguments, arguments[1..]) |id, *slot| slot.* = self.resolved[@backingInt(id)].?;
    try self.require(self.nodes.items[@backingInt(receiver)].ty, .filesystem_cap, node.span);
    try self.require(self.nodes.items[@backingInt(arguments[1])].ty, shapes.text, self.nodes.items[@backingInt(arguments[1])].span);
    const mode = try openMode(Checker, self, kind, value_arguments);
    if (kind == .write_file) try self.require(self.nodes.items[@backingInt(arguments[2])].ty, shapes.bytes, node.span);
    if (kind == .write_text) try self.require(self.nodes.items[@backingInt(arguments[2])].ty, shapes.text, node.span);
    const direct = kind == .open and self.trapping_open != null and std.meta.eql(self.trapping_open.?, node.span);
    out.ty = if (direct) (if (mode.text) .text_file else .file) else try fileAccessType(Checker, self, kind, mode, node.span);
    out.data = .{ .file_access = .{ .kind = kind, .mode = mode.letter, .text = mode.text, .arguments = arguments, .shapes = shapes } };
}
/// Check the free `read_text(fs, path)` spelling, whose leading argument is
/// the capability the method form carries as its receiver.
fn checkFileAccessCall(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, out: *typed.Node) Error!void {
    try call_arguments.positional(call, self.sink);
    if (call.type_arguments.len != 0 or call.arguments.len != kind.arity()) return self.fileAccessArityFailure(node, kind, call.arguments.len, false);
    return checkFileAccess(Checker, self, node, kind, self.resolved[@backingInt(call.arguments[0])].?, call.arguments[1..], out);
}
/// Require positional arguments of the count a qualified `fs.name(...)` call takes.
fn requireMethodShape(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access) Error!void {
    try call_arguments.positional(call, self.sink);
    if (call.type_arguments.len != 0 or call.arguments.len != kind.methodArity()) return self.fileAccessArityFailure(node, kind, call.arguments.len, true);
}
/// Check the qualified `fs.read_text(path)` spelling on a receiver already checked
/// as an expression, such as a record field, instead of a named local.
fn checkFileAccessOn(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, receiver: typed.NodeId, out: *typed.Node) Error!void {
    try requireMethodShape(Checker, self, node, call, kind);
    return checkFileAccess(Checker, self, node, kind, receiver, call.arguments, out);
}
/// Check the qualified `fs.read_text(path)` spelling on a local `Filesystem`.
fn checkFileAccessMethod(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, out: *typed.Node) Error!void {
    try requireMethodShape(Checker, self, node, call, kind);
    const owner = call.owner.?;
    const slot = self.active.get(self.src.text(owner)).?;
    try self.requireReadable(slot, owner);
    self.locals.items[@backingInt(slot)].usage.reads += 1;
    const receiver: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = owner, .ty = .filesystem_cap, .data = .{ .local = slot } });
    return checkFileAccess(Checker, self, node, kind, receiver, call.arguments, out);
}
/// `open` needs a literal mode so the checker knows whether reads yield text.
fn openMode(comptime Checker: type, self: *Checker, kind: file_operations.Access, value_arguments: []const ast.NodeId) Error!file_operations.Mode {
    if (kind != .open) return .{ .letter = 'r', .text = kind == .read_text or kind == .write_text };
    const spelling = self.syntax.nodes.items[@backingInt(value_arguments[1])];
    if (spelling.data != .text) return self.sink.fail(eFileArgument, spelling.span, "open requires a literal mode such as \"rb\", \"r\", \"wb\", \"w\", \"ab\" or \"a\"");
    return file_operations.parseMode(spelling.data.text) orelse self.sink.fail(eFileArgument, spelling.span, "unsupported open mode; use \"r\", \"w\", \"a\" with an optional \"b\" or \"t\"");
}
/// A file method's result type follows its receiver's text or binary mode.
fn checkFileMethod(comptime Checker: type, self: *Checker, node: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), "file_operation"), out: *typed.Node) Error!void {
    const slot = self.active.get(self.src.text(operation.owner)).?;
    const text = self.locals.items[@backingInt(slot)].ty == .text_file;
    const shapes = try fileShapes(Checker, self, node.span);
    const element: typed.Type = if (text) shapes.text else shapes.bytes;
    const argument: ?typed.NodeId = if (operation.argument) |id| self.resolved[@backingInt(id)].? else null;
    if (operation.kind == .write) try self.require(self.nodes.items[@backingInt(argument.?)].ty, element, node.span);
    if (operation.kind == .read) if (argument) |id| try self.require(self.nodes.items[@backingInt(id)].ty, .i64, node.span);
    out.ty = switch (operation.kind) {
        .read, .readline => element,
        .readlines => try collections.listType(&self.catalog, element, node.span),
        .write => .i64,
        .flush, .close => .unit,
    };
    out.data = .{ .file_method = .{ .kind = operation.kind, .owner = slot, .text = text, .argument = argument, .shapes = shapes } };
}
/// `debug(...)` writes to standard error with no capability and no effect.
fn debugBuiltin(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
    if (call.owner != null or call.type_arguments.len != 0) return false;
    if (!std.mem.eql(u8, self.src.text(call.name), "debug")) return false;
    if (self.active.contains("debug") or self.functions.contains("debug")) return false;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return false;
    return true;
}
/// Resolve the receiver of `stream.print`/`stream.write` to its local slot, or null.
fn streamLocal(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?typed.LocalId {
    const owner = call.owner orelse return null;
    const slot = self.active.get(self.src.text(owner)) orelse return null;
    if (self.locals.items[@backingInt(slot)].ty != .stream_cap) return null;
    const name = self.src.text(call.name);
    if (!std.mem.eql(u8, name, "write") and !std.mem.eql(u8, name, "print")) return null;
    return slot;
}
/// Recognize `stream.print(...)`/`stream.write(...)` on a `Stream` local.
fn streamMethod(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?StreamMethod {
    const slot = streamLocal(Checker, self, call) orelse return null;
    const write = std.mem.eql(u8, self.src.text(call.name), "write");
    self.locals.items[@backingInt(slot)].usage.reads += 1;
    const stream: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = call.owner.?, .ty = .stream_cap, .data = .{ .local = slot } });
    return .{ .stream = stream, .write = write };
}
/// The destination of one `print`-shaped call: an ambient sink, a runtime
/// `Stream` receiver, or the `debug` stderr spelling.
const PrintTarget = struct { sink: typed.Sink = .stdout, stream: ?typed.NodeId = null, debug: bool = false };
/// `print`/`eprint` without a receiver are gone: once no local binding,
/// declared function or imported name shadows the spelling, they name
/// `E_OUTPUT_CAPABILITY` rather than an ambient sink. The same sentence the
/// message carries is attached as an `alternative` note, so a tool reads the
/// accepted spelling as data instead of parsing prose, and the primary
/// message is unchanged.
fn outputBuiltin(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.Sink {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    const name = self.src.text(call.name);
    if (!std.mem.eql(u8, name, "print") and !std.mem.eql(u8, name, "eprint")) return null;
    if (self.active.contains(name) or self.functions.contains(name)) return null;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    return self.sink.failCallSite(io_builtins.output_capability_code, call.name, io_builtins.output_capability_message, .{
        .span = call.name,
        .message = io_builtins.output_capability_message,
        .role = .alternative,
    }, print_signature);
}
fn checkPrintOperand(comptime Checker: type, self: *Checker, id: ast.NodeId, expected_text: bool) Error!typed.NodeId {
    const value = self.resolved[@backingInt(id)].?;
    const ty_value = self.nodes.items[@backingInt(value)].ty;
    if (expected_text) {
        const text_type = try collections.preludeType(&self.catalog, "str", self.nodes.items[@backingInt(value)].span);
        try self.require(ty_value, text_type, self.nodes.items[@backingInt(value)].span);
        return value;
    }
    if (!io_render.printable(ty_value, self.catalog.records)) return self.sink.fail(
        io_builtins.argument_code,
        self.nodes.items[@backingInt(value)].span,
        "print cannot render this value; capabilities, files, owned resources and callbacks have no Python spelling",
    );
    return value;
}
fn checkPrint(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), target: PrintTarget, out: *typed.Node) Error!void {
    const split = try io_builtins.printArguments(self.src, call, self.sink);
    const arguments = try self.allocator.alloc(typed.NodeId, split.values.len);
    for (split.values, arguments) |id, *slot| slot.* = try checkPrintOperand(Checker, self, id, false);
    out.ty = .unit;
    out.data = .{ .print = .{
        .sink = target.sink,
        .arguments = arguments,
        .separator = if (split.separator) |id| try checkPrintOperand(Checker, self, id, true) else null,
        .terminator = if (split.terminator) |id| try checkPrintOperand(Checker, self, id, true) else null,
        .stream = target.stream,
        .debug = target.debug,
    } };
    _ = node;
}
/// `print` and `write` on a `Stream` reached through an expression rather
/// than a bare name, such as a class field (`sink.stream.write(data)`). The
/// parser hands such a call over as a method call, so it lands here with its
/// receiver already checked; it lowers exactly like the named-receiver form.
/// A method call carries positional arguments only, so `sep=` and `end=`
/// still need the stream bound to a name first.
fn checkStreamReceiverMethod(comptime Checker: type, self: *Checker, node: ast.Node, stream: typed.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    const method = node.data.method_call;
    const name = self.src.text(method.name);
    const write = std.mem.eql(u8, name, "write");
    if (!write and !std.mem.eql(u8, name, "print"))
        return self.sink.fail(eCollectionMethod, method.name, "unknown method for a Stream receiver; a Stream has the methods print and write");
    for (method.arguments) |argument| _ = try self.expressionWithTemporaries(argument, temporaries);
    const call: @FieldType(@FieldType(ast.Node, "data"), "call") = .{ .name = method.name, .arguments = method.arguments };
    var out: typed.Node = .{ .span = node.span, .ty = .unit, .data = .unit };
    if (write) try checkStreamWrite(Checker, self, node, call, stream, &out) else try checkPrint(Checker, self, node, call, .{ .stream = stream }, &out);
    return out;
}
fn checkStreamWrite(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), stream: typed.NodeId, out: *typed.Node) Error!void {
    try call_arguments.positional(call, self.sink);
    if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "stream.write takes one str or bytes argument");
    const text = self.resolved[@backingInt(call.arguments[0])].?;
    const value = self.nodes.items[@backingInt(text)];
    const kind = if (value.ty.isAggregate()) self.catalog.records[value.ty.recordIndex()].collection.kind else null;
    if (kind != .string and kind != .bytes) return self.sink.fail("E_TYPE", value.span, "stream.write requires str or bytes");
    out.ty = .i64;
    out.data = .{ .stream_write = .{ .stream = stream, .text = text } };
}
fn optionConstructor(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
    if (call.owner != null or call.type_arguments.len != 0 or !std.mem.eql(u8, self.src.text(call.name), "Some")) return false;
    if (self.active.contains("Some") or self.functions.contains("Some")) return false;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return false;
    return true;
}
fn cellConstructor(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?usize {
    if (self.active.contains("Cell") or self.functions.contains("Cell")) return null;
    return @import("cell_types.zig").constructor(self.src, self.catalog, call, self.sink);
}
fn expectedOption(comptime Checker: type, self: *Checker, node: ast.Node) Error!ExpectedOption {
    const expected = self.expected_types.get(node.span) orelse return self.sink.fail("E_OPTION_INFERENCE", node.span, "Some requires an expected Option type");
    const shape = prelude.optionShape(expected, self.catalog.records) orelse return self.sink.fail("E_TYPE", node.span, "Some requires an expected Option type");
    return .{ .ty = expected, .shape = shape };
}
fn checkOptionConstructor(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    const expected = try expectedOption(Checker, self, node);
    const value = self.resolved[@backingInt(call.arguments[0])].?;
    try self.require(self.nodes.items[@backingInt(value)].ty, expected.shape.element, node.span);
    out.* = .{ .span = node.span, .ty = expected.ty, .data = .{ .variant = .{ .tag = expected.shape.some, .value = value } } };
}
fn checkUnit(comptime Checker: type, self: *Checker, node: ast.Node) typed.Node {
    if (self.expected_types.get(node.span)) |expected| if (prelude.optionShape(expected, self.catalog.records)) |shape| {
        return .{ .span = node.span, .ty = expected, .data = .{ .variant = .{ .tag = shape.none, .value = null } } };
    };
    return .{ .span = node.span, .ty = .unit, .data = .unit };
}
fn expectedResult(comptime Checker: type, self: *Checker, node: ast.Node) Error!typed.Type {
    const expected = self.expected_types.get(node.span) orelse return self.sink.fail("E_RESULT_INFERENCE", node.span, "Ok and Err require a Result type from a binding, return, argument, or field");
    if (typed.resultShape(expected, self.catalog.records) == null) return self.sink.fail("E_TYPE", node.span, "Ok and Err require an expected Result type");
    return expected;
}
fn checkResultConstructor(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), ok: bool, out: *typed.Node) Error!void {
    if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "Ok and Err require one payload");
    out.ty = try expectedResult(Checker, self, node);
    const shape = typed.resultShape(out.ty, self.catalog.records).?;
    const value = self.resolved[@backingInt(call.arguments[0])].?;
    try self.require(self.nodes.items[@backingInt(value)].ty, if (ok) shape.ok_type else shape.error_type, node.span);
    out.data = .{ .variant = .{ .tag = if (ok) shape.ok_tag else shape.error_tag, .value = value } };
}

/// The checker fields the builtin recognizers read, so a test can drive them
/// without checking a whole program.
const RecognizerStub = struct {
    src: source.Source,
    active: std.StringHashMapUnmanaged(void) = .empty,
    functions: std.StringHashMapUnmanaged(void) = .empty,
    catalog: struct { module_names: ?*@import("module_names.zig").Names = null } = .{},
};

test "Some and float() are builtins only until a local of the same name shadows them" {
    const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
    const checks = Checks(RecognizerStub);
    var stub: RecognizerStub = .{ .src = .{ .path = "recognize.my", .bytes = "Some float int", .line_starts = &.{} } };
    defer stub.active.deinit(std.testing.allocator);
    const some: Call = .{ .name = .{ .start = 0, .end = 4 }, .arguments = &.{} };
    const float: Call = .{ .name = .{ .start = 5, .end = 10 }, .arguments = &.{} };
    const int: Call = .{ .name = .{ .start = 11, .end = 14 }, .arguments = &.{} };
    try std.testing.expect(try checks.optionConstructor(&stub, some));
    try std.testing.expectEqual(@as(?bool, true), try checks.numericConversion(&stub, float));
    try std.testing.expectEqual(@as(?bool, false), try checks.numericConversion(&stub, int));
    try stub.active.put(std.testing.allocator, "Some", {});
    try stub.active.put(std.testing.allocator, "float", {});
    try std.testing.expect(!try checks.optionConstructor(&stub, some));
    try std.testing.expectEqual(@as(?bool, null), try checks.numericConversion(&stub, float));
}
