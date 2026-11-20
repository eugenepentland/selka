//! Checking of builtin calls: float intrinsics and numeric conversions, prelude
//! calls, `sorted`/`list.sort` keywords and key lambdas, `open`/file methods,
//! `print` and `Stream` writes, and the `Some`/`None`/`Ok`/`Err` constructors.
//! Each check is a free function over the concrete checker type; `Checks`
//! exposes the ones the rest of the checker calls as `self.name(...)`.
const buffer_operations = @import("buffer_operations.zig");
const collections = @import("collection_lower.zig");
const dictionary_views = @import("dictionary_views.zig");
const option_flow = @import("option_flow.zig");
const call_arguments = @import("call_arguments.zig");
const io_builtins = @import("io_builtins.zig");
const retired_methods = @import("retired_methods.zig");
const file_operations = @import("file_operations.zig");
const Span = @import("source.zig").Span;
const callables = @import("callables.zig");
const literal_peer = @import("literal_peer.zig");
const std = @import("std");
const print_signature = buffer_operations.stream_print_signature;
const sorted_signature = buffer_operations.sorted_signature;
const list_sort_signature = buffer_operations.list_sort_signature;
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const numeric_surface = @import("numeric_surface.zig");
const prelude = @import("prelude.zig");
const prelude_builtins = @import("prelude_builtins.zig");
const enum_cases = @import("enum_cases.zig");
const sema_exchange = @import("sema_exchange.zig");
const gathers = @import("sema_gathers.zig");
const sema_shared = @import("sema_shared.zig");
const call_argument_code = sema_shared.call_argument_code;
const eCollectionMethod = sema_shared.eCollectionMethod;
const eFileArgument = sema_shared.eFileArgument;
const Pending = sema_shared.Pending;
const Work = sema_shared.Work;
const uninferred_lambda = sema_shared.uninferred_lambda;
/// The accepted spelling for Python 2's `cmp=` comparison function.
const sort_cmp_alternative = "there is no cmp= argument; to order by a comparison of two elements write a top-level " ++
    "`func compare(first: T, second: T) -> int` and call `sort.sort_by_compare(mut values, compare)` (stable and in place; " ++
    "`sort.sort_by_compare_with` passes a context value as a third argument), or let key= map each element to one value that is compared instead";
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
        /// `sort(mut values, key=..., reverse=...)`: the prelude form of a list's
        /// in-place sort, whose receiver is the first operand.
        pub fn checkPreludeListSort(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), base: typed.NodeId) Error!typed.Node {
            return impl.checkPreludeListSort(Checker, self, node, call, base);
        }
        /// Hint the keyword operands of `sort(mut values, key=..., reverse=...)`
        /// from the receiver's element type before they are checked, so a lambda
        /// key answers the same diagnostic the method spelling did.
        pub fn hintPreludeListSort(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
            return impl.hintPreludeListSort(Checker, self, call);
        }
        /// `receiver.sort(key=..., reverse=...)` on any list expression: the
        /// receiver is checked already; hint and check the named operands in
        /// source order, then sort the list the receiver evaluated to in place.
        pub fn checkMethodListSort(self: *Checker, node: ast.Node, base: typed.NodeId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkMethodListSort(Checker, self, node, base, temporaries);
        }
        /// Check numeric `int(x)`/`float(x)` conversions and optional-returning
        /// `parse_int(text)`/`parse_float(text)` operations.
        pub fn checkNumericConversion(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), target: NumericTarget, out: *typed.Node) Error!void {
            return impl.checkNumericConversion(Checker, self, node, call, target, out);
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
        /// Recognize the stage-2 output functions whose first argument is the stream.
        pub fn streamFunction(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?StreamFunction {
            return impl.streamFunction(Checker, self, call);
        }
        /// Check one recognized output function (`print`, `write` or `flush`).
        pub fn checkStreamFunction(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), found: StreamFunction, out: *typed.Node) Error!void {
            return impl.checkStreamFunction(Checker, self, node, call, found, out);
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
        pub fn floatFma(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?bool {
            return impl.floatFma(Checker, self, call);
        }
        pub fn checkFloatFma(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), narrow: bool, out: *typed.Node) Error!void {
            return impl.checkFloatFma(Checker, self, node, call, narrow, out);
        }
        /// Recognize the compiler-internal byte read `__read_<type>_<le|be>` (the `bytes.read_*` functions).
        pub fn byteRead(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?ByteRead {
            return impl.byteRead(Checker, self, call);
        }
        /// Check one compiler-internal byte read: the bytes and the offset, read as the named width.
        pub fn checkByteRead(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), read: ByteRead, out: *typed.Node) Error!void {
            return impl.checkByteRead(Checker, self, node, call, read, out);
        }
        pub fn numericConversion(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?NumericTarget {
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
        /// Refuse a named `Stream`'s `print` or `write` method spelling (F-s).
        pub fn refuseStreamSpelling(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
            return impl.refuseStreamSpelling(Checker, self, node, call);
        }
    };
}
/// Recognize the compiler-internal fused multiply-add spellings: `__float_fma` (binary64) and `__f32_fma`
/// (binary32). The public spellings are `math.fma` and `math.f32_fma`; the intrinsics stay out of user code.
fn floatFma(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?bool {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    const name = self.src.text(call.name);
    if (std.mem.eql(u8, name, "__float_fma")) return false;
    if (std.mem.eql(u8, name, "__f32_fma")) return true;
    return null;
}
/// Whether a call site lies in compiler-embedded standard-library source, where the intrinsics are spelled.
fn trustedIntrinsicSite(comptime Checker: type, self: *Checker, span: source.Span) bool {
    _ = @sizeOf(Checker);
    const library = @import("standard_library.zig");
    if (self.src.trusted_intrinsics or library.trusted(self.src.path, self.src.bytes, false)) return true;
    const original = self.src.originalSpan(span) catch return false;
    const unit = self.src.origins[original.input].original;
    return library.trusted(unit.path, unit.bytes, unit.trusted_intrinsics);
}
fn checkFloatFma(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), narrow: bool, out: *typed.Node) Error!void {
    if (!trustedIntrinsicSite(Checker, self, node.span)) return self.sink.fail("E_INTERNAL_NAME", node.span, "this fused multiply-add intrinsic is reserved for compiler-internal standard-library sources; use `math.fma` or `math.f32_fma`");
    if (call.arguments.len != 3 or call.argument_names.len != 0) return self.sink.fail("E_ARITY", node.span, "fused multiply-add takes three positional arguments");
    const records = self.catalog.records;
    const a = self.resolved.at(@backingInt(call.arguments[0])).?;
    const ty_a = self.nodes.items[@backingInt(a)].ty;
    const width_ok = if (narrow) numeric_surface.isF32(ty_a, records) else numeric_surface.isFloat(ty_a, records);
    if (!width_ok) return self.sink.fail("E_TYPE", node.span, "fused multiply-add requires floating operands of the named width");
    for (call.arguments[1..]) |argument| {
        const id = self.resolved.at(@backingInt(argument)).?;
        try self.require(self.nodes.items[@backingInt(id)].ty, ty_a, node.span);
    }
    const b = self.resolved.at(@backingInt(call.arguments[1])).?;
    const c = self.resolved.at(@backingInt(call.arguments[2])).?;
    out.* = try self.numericBuilderFor(node.span, ty_a).fma(a, b, c);
}
/// One compiler-internal fixed-width byte read: the named width (`u16`..`u64`, `i16`..`i64`, `f32`, `f64`) and its byte order.
pub const ByteRead = struct { ty: []const u8, big_endian: bool };
/// The width names a byte read accepts.
fn byteReadWidth(name: []const u8) ?[]const u8 {
    const widths = [_][]const u8{ "u8", "i8", "u16", "i16", "u32", "i32", "u64", "i64", "f32", "f64" };
    for (widths) |width| if (std.mem.eql(u8, name, width)) return width;
    return null;
}
/// Recognize `__read_<width>_<le|be>`: the compiler-internal spelling the `bytes.read_*` functions call. Floats and
/// single octets are little-endian only, so `__read_f32_be` and `__read_u8_be` are not reads and fall through to the
/// ordinary unknown-name refusal.
fn byteRead(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?ByteRead {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    const name = self.src.text(call.name);
    const prefix = "__read_";
    if (!std.mem.startsWith(u8, name, prefix)) return null;
    const rest = name[prefix.len..];
    const cut = std.mem.lastIndexOfScalar(u8, rest, '_') orelse return null;
    const width = byteReadWidth(rest[0..cut]) orelse return null;
    const order = rest[cut + 1 ..];
    const big = std.mem.eql(u8, order, "be");
    if (!big and !std.mem.eql(u8, order, "le")) return null;
    if (big and (width[0] == 'f' or width[width.len - 1] == '8')) return null;
    return .{ .ty = width, .big_endian = big };
}
/// Check one byte read: the first argument is `bytes` (a view, a slice or an owned value), the second an `int` offset.
fn checkByteRead(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), read: ByteRead, out: *typed.Node) Error!void {
    if (!trustedIntrinsicSite(Checker, self, node.span)) return self.sink.fail("E_INTERNAL_NAME", node.span, "this byte read is reserved for compiler-internal standard-library sources; use the `bytes.read_*` functions");
    if (call.arguments.len != 2 or call.argument_names.len != 0) return self.sink.fail("E_ARITY", node.span, "a byte read takes two positional arguments: the bytes and the offset");
    const records = self.catalog.records;
    const data = self.resolved.at(@backingInt(call.arguments[0])).?;
    const data_type = self.nodes.items[@backingInt(data)].ty;
    if (!data_type.isAggregate() or !typed.isByteString(records[data_type.recordIndex()])) return self.sink.fail("E_TYPE", node.span, "a byte read takes bytes as its first argument");
    const offset = self.resolved.at(@backingInt(call.arguments[1])).?;
    try self.require(self.nodes.items[@backingInt(offset)].ty, .i64, node.span);
    // Integer widths are scalar identities (`int` is `i64`); binary32 and binary64 are the prelude's `f32` and `float`.
    const result: typed.Type = if (std.mem.eql(u8, read.ty, "f64"))
        self.catalog.names.get("float") orelse return error.InternalError
    else if (std.mem.eql(u8, read.ty, "f32"))
        self.catalog.names.get("f32") orelse return error.InternalError
    else
        std.meta.stringToEnum(typed.Type, read.ty) orelse return error.InternalError;
    out.* = .{ .span = node.span, .ty = result, .data = .{ .byte_load = .{ .bytes = data, .offset = offset, .big_endian = read.big_endian, .op_span = node.span } } };
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
    const value = self.resolved.at(@backingInt(call.arguments[0])).?;
    const ty_value = self.nodes.items[@backingInt(value)].ty;
    if (!numeric_surface.isBinaryFloat(ty_value, self.catalog.records)) return self.sink.fail("E_TYPE", node.span, "this prelude operation requires a float argument");
    out.* = try self.numericBuilderFor(node.span, ty_value).unary(op, value);
}
/// The type a numeric conversion names: `float(x)` and `parse_float(x)` build binary64, `f32(x)`
/// builds binary32, and `int(x)` and `parse_int(x)` build `i64`.
pub const NumericTarget = enum { int, float, f32 };

fn numericConversion(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?NumericTarget {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    const name = self.src.text(call.name);
    const target: NumericTarget = if (std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "parse_float"))
        .float
    else if (std.mem.eql(u8, name, "f32") or std.mem.eql(u8, name, "parse_f32"))
        .f32
    else if (std.mem.eql(u8, name, "int") or std.mem.eql(u8, name, "parse_int"))
        .int
    else
        return null;
    if (self.active.contains(name) or self.functions.contains(name)) return null;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    return target;
}

/// `float(v)` widens each lane of a `Simd[f32, N]`, and `f32(v)` rounds each lane of a `Simd[float, N]` to binary32,
/// as the scalar conversions do (SIMD-LANE-CONVERT-1). Other conversions of a Simd are refused.
fn checkLaneConversion(comptime Checker: type, self: *Checker, node: ast.Node, lanes: typed.Array, target: NumericTarget, value: typed.NodeId, out: *typed.Node) Error!void {
    const records = self.catalog.records;
    const refusal = "float(v) widens Simd[f32, N] lanes and f32(v) rounds Simd[float, N] lanes; other conversions of a Simd are refused";
    const element: typed.Type = switch (target) {
        .float => if (numeric_surface.isF32(lanes.element, records)) self.catalog.names.get("float").? else return self.sink.fail("E_TYPE", node.span, refusal),
        .f32 => if (numeric_surface.isFloat(lanes.element, records)) self.catalog.names.get("f32").? else return self.sink.fail("E_TYPE", node.span, refusal),
        .int => return self.sink.fail("E_TYPE", node.span, refusal),
    };
    const result = try self.catalog.instantiateShape(self.allocator, .{ .element = element, .length = lanes.length, .vector = true }, node.span, self.sink);
    out.* = .{ .span = node.span, .ty = result, .data = .{ .vector_convert = .{ .operand = value, .op_span = node.span } } };
}

fn checkNumericConversion(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), target: NumericTarget, out: *typed.Node) Error!void {
    const value = self.resolved.at(@backingInt(call.arguments[0])).?;
    const ty_value = self.nodes.items[@backingInt(value)].ty;
    const records = self.catalog.records;
    const input_float = numeric_surface.isBinaryFloat(ty_value, records);
    const parses = std.mem.startsWith(u8, self.src.text(call.name), "parse_");
    const floating = target == .float;
    if (ty_value.isAggregate() and records[ty_value.recordIndex()].collection.kind == .string) {
        if (!parses) {
            const repair = if (target == .f32) "parse_f32" else if (floating) "parse_float" else "parse_int";
            const claimed = self.active.contains(repair) or self.functions.contains(repair) or self.catalog.names.contains(repair) or self.catalog.templates.names.contains(repair) or
                if (self.catalog.module_names) |names| try names.topLevelSpelling(call.name, repair) else false;
            const operand = self.syntax.nodes.items[@backingInt(call.arguments[0])];
            const conversion: numeric_surface.TextConversion = .{ .name = call.name, .call = node.span, .operand = self.src.text(operand.span), .primary = numeric_surface.primaryOperand(operand) };
            return numeric_surface.rejectTextConversion(self.sink, conversion, repair, claimed);
        }
        const builder: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        out.* = try builder.access(value, if (target == .f32) .parse_f32 else if (floating) .parse_float else .parse_int, &.{}, false);
        return;
    }
    if (parses) return self.sink.fail("E_TYPE", node.span, "parse_int, parse_float and parse_f32 require a str argument");
    if (numeric_surface.vectorShape(ty_value, records)) |lanes| return checkLaneConversion(Checker, self, node, lanes, target, value, out);
    if (@import("extern_types.zig").is(ty_value, records)) return @import("extern_types.zig").refuse(self.sink, node.span, .conversion);
    if (!input_float and !ty_value.isInteger()) return self.sink.fail("E_TYPE", node.span, "numeric conversion requires an integer or float");
    switch (target) {
        .float => {
            const wide = self.catalog.names.get("float").?;
            if (numeric_surface.isF32(ty_value, records)) {
                out.* = try self.numericBuilderFor(node.span, wide).convert(value, ty_value);
            } else out.* = if (input_float) self.nodes.items[@backingInt(value)] else try self.numericBuilderFor(node.span, wide).fromInteger(value);
        },
        .f32 => {
            const narrow = self.catalog.names.get("f32").?;
            if (numeric_surface.isF32(ty_value, records)) {
                out.* = self.nodes.items[@backingInt(value)];
            } else out.* = if (input_float) try self.numericBuilderFor(node.span, narrow).convert(value, ty_value) else try self.numericBuilderFor(node.span, narrow).fromInteger(value);
        },
        .int => if (input_float) {
            out.* = try self.numericBuilderFor(node.span, ty_value).toInteger(value, .i64);
        } else {
            out.* = .{ .span = node.span, .ty = .i64, .data = .{ .cast = value } };
        },
    }
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
    if (call.arguments.len == 0 or call.arguments.len > 3) return null;
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
    if (std.mem.eql(u8, name, "exchange")) return sema_exchange.hintReplacement(Checker, self, call);
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
    // PY-GENERATOR-1: a generator argument is checked as what its call
    // consumes; a second positional argument leaves it a plain generator.
    if (call.arguments.len == 1 or (call.arguments.len != 0 and std.mem.eql(u8, name, "sorted")))
        if (gathers.Use.consuming(name)) |use| {
            _ = try self.consumeGenerator(call.arguments[0], use);
        };
    if (std.mem.eql(u8, name, "sorted")) {
        const keywords = try sortedKeywords(Checker, self, call);
        if (keywords.key != null or keywords.reverse != null) {
            try work.append(self.allocator, .{ .id = call_id, .sorted_key = true });
            try work.append(self.allocator, .{ .id = call.arguments[0] });
            return true;
        }
    } else try call_arguments.positional(call, self.sink);
    try hintPreludeArguments(Checker, self, name, call);
    // The two values of `min` and `max` share one type: a literal one takes the other's checked type (`literal_peer`).
    const extreme = std.mem.eql(u8, name, "min") or std.mem.eql(u8, name, "max");
    if (extreme and call.arguments.len == 2) if (literal_peer.awaiting(Checker, self, call.arguments[0], call.arguments[1])) |pair| {
        try work.append(self.allocator, .{ .id = pair.literal, .hint_from = .{ .id = pair.peer, .literal = .argument } });
        try work.append(self.allocator, .{ .id = pair.peer });
        return true;
    };
    const ranged = prelude_builtins.materializes(name) or std.mem.eql(u8, name, "set");
    const materialized = if (ranged and call.arguments.len == 1) try rangeSource(Checker, self, call.arguments[0]) else null;
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
    // `Kind.cases()` and `Kind.from_name(text)` are calls on an enum type that answer where the prelude names do.
    if (try enum_cases.check(Checker, self, node, call, out)) return true;
    if (!try preludeName(Checker, self, call)) return false;
    const name = self.src.text(call.name);
    if (std.mem.eql(u8, name, "copy")) {
        try self.checkPreludeCopy(node, call, out);
        return true;
    }
    if (std.mem.eql(u8, name, "sorted")) {
        out.* = try checkSortedCall(Checker, self, node.span, call);
        return true;
    }
    if (std.mem.eql(u8, name, "take") or std.mem.eql(u8, name, "exchange")) {
        out.* = try sema_exchange.check(Checker, self, node, call, name);
        return true;
    }
    try call_arguments.positional(call, self.sink);
    const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
    // PY-GENERATOR-1: `sum`, `any`, `all`, `min`, `max`, `set`, `dict` and
    // `list` of a generator are the value its loop already folded or built.
    if (call.arguments.len == 1 and (self.foldedGenerator(call.arguments[0]) or listGenerator(Checker, self, name, call.arguments[0]))) {
        out.* = self.nodes.items[@backingInt(self.resolved.at(@backingInt(call.arguments[0])).?)];
        out.span = node.span;
        return true;
    }
    if (std.mem.eql(u8, name, "dict")) {
        out.* = try checkDictConstructor(Checker, self, node, call);
        return true;
    }
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
            for (range.arguments, bounds) |id, *slot| slot.* = self.resolved.at(@backingInt(id)).?;
            out.* = try builtins.rangeList(node.span, bounds);
            if (building_set) out.* = try self.checkSetFromIterable(node.span, try retainNode(Checker, self, out.*));
            return true;
        }
        const input = self.resolved.at(@backingInt(call.arguments[0])).?;
        // `set(iterable)` (SET-1); `list(s)` of a set, and `list(d)` of a
        // dictionary or a key or value view, is the fresh list of its keys or
        // values in insertion order (PRELUDE-KEYS-1).
        if (building_set) {
            out.* = try self.checkSetFromIterable(node.span, input);
        } else {
            const listed = try preludeList(Checker, self, node.span, input);
            out.* = if (listed != input) self.nodes.items[@backingInt(listed)] else try builtins.copyList(node.span, input);
        }
        return true;
    }
    const values = try self.allocator.alloc(typed.NodeId, call.arguments.len);
    for (call.arguments, values) |id, *slot| slot.* = self.resolved.at(@backingInt(id)).?;
    // A set folds and orders as the list of its elements in insertion order
    // (SET-1), and the folds read a dictionary's keys the same way (PRELUDE-KEYS-1).
    // `copy(set)` copies the set itself and `repr(set)` is the set's text, `{...}` as `print` shows it (F-38); every other
    // folding or materializing prelude name reads a set as its keys in insertion order.
    const copies_set = std.mem.eql(u8, name, "copy") or std.mem.eql(u8, name, "repr");
    const folds_set = values.len == 1 and (folding(name) or typed.setRecord(self.catalog.records, self.nodes.items[@backingInt(values[0])].ty) != null);
    if (!copies_set and folds_set) values[0] = try preludeList(Checker, self, node.span, values[0]);
    out.* = (try builtins.build(node.span, name, values)) orelse return false;
    return true;
}
/// The list a prelude call reads for `input`: the fresh list of a set's
/// elements or a dictionary's keys in insertion order (the key snapshot of
/// its dictionary representation), the snapshot of a key or value view, or
/// `input` itself for any other value (SET-1, PRELUDE-KEYS-1).
fn preludeList(comptime Checker: type, self: *Checker, span: source.Span, input: typed.NodeId) Error!typed.NodeId {
    const ty = self.nodes.items[@backingInt(input)].ty;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    if (dictionary_views.identify(self.catalog, ty)) |view| if (view == .keys or view == .values) {
        const snapshot = try dictionary_views.snapshot(Checker, self, span, input, view);
        return b.node(snapshot.ty, snapshot.data);
    };
    if (!ty.isAggregate() or !self.catalog.records[ty.recordIndex()].isCollection()) return input;
    if (self.catalog.records[ty.recordIndex()].collection.kind != .dictionary) return input;
    const keys = try b.access(input, .keys, &.{}, false);
    return b.node(keys.ty, keys.data);
}
/// Add a built checked expression to the node table.
fn retainNode(comptime Checker: type, self: *Checker, value: typed.Node) Error!typed.NodeId {
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, value);
    return id;
}
/// Whether a prelude builtin folds its one sequence argument.
fn folding(name: []const u8) bool {
    inline for (.{ "sum", "min", "max", "any", "all" }) |builtin| {
        if (std.mem.eql(u8, name, builtin)) return true;
    }
    return false;
}
/// Whether `list(...)`'s argument is a generator its own loop built into a list.
fn listGenerator(comptime Checker: type, self: *Checker, name: []const u8, id: ast.NodeId) bool {
    if (!std.mem.eql(u8, name, "list")) return false;
    const node = self.syntax.nodes.items[@backingInt(id)];
    return node.data == .gather and node.data.gather.shape == .generator;
}
const dict_argument_message = "dict() copies a dictionary";
const dict_argument_alternative = "pair two lists with an explicit loop: `for k, v in zip(keys, values):` then `d[k] = v`";
/// PY-GENERATOR-1: `dict()` with its type from context and `dict(mapping)`, a
/// copy; `dict(...)` of a generator is answered by the generator's own loop.
fn checkDictConstructor(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!typed.Node {
    if (call.arguments.len > 1) return self.sink.fail("E_ARITY", node.span, "dict() takes at most one mapping or generator of (key, value) pairs");
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    if (call.arguments.len == 0) {
        const expected = self.expected_types.get(node.span) orelse return self.sink.fail("E_DICT_INFERENCE", node.span, "an empty dictionary needs its type from context: `counts: dict[str, int] = dict()`");
        if (!expected.isAggregate() or self.catalog.records[expected.recordIndex()].collection.kind != .dictionary or typed.isSet(self.catalog.records[expected.recordIndex()]))
            return self.sink.fail("E_DICT_TYPE", node.span, "dict() builds a dictionary, but this position expects another type");
        return b.block(&.{}, try b.node(expected, .{ .array = &.{} }));
    }
    const input = self.resolved.at(@backingInt(call.arguments[0])).?;
    const input_type = self.nodes.items[@backingInt(input)].ty;
    const mapping = input_type.isAggregate() and self.catalog.records[input_type.recordIndex()].collection.kind == .dictionary and !typed.isSet(self.catalog.records[input_type.recordIndex()]);
    if (!mapping) return self.sink.failRelated("E_DICT_TYPE", node.span, dict_argument_message, .{ .span = node.span, .message = dict_argument_alternative, .role = .alternative });
    return b.access(input, .copy, &.{}, false);
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
    const slot: typed.Callable = .{ .parameters = parameters, .return_type = result, .mutates = &.{}, .return_origin = .fresh };
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
    for (self.resolved_nodes.items[saved_resolved..]) |index| self.resolved.put(index, null);
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
    const input_type = if (self.resolved.at(@backingInt(call.arguments[0]))) |value|
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
    // PRELUDE-KEYS-1: a set or dictionary sorts its keys.
    if (input_schema.isCollection() and input_schema.collection.kind == .dictionary) return input_schema.collection.key.?;
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
        sort.key = self.resolved.at(@backingInt(id)).?;
        _ = try builtins.sortKey(self.syntax.nodes.items[@backingInt(id)].span, element, sort.key.?);
    } else if (keywords.reverse != null) try self.requireSortable(element, span);
    if (keywords.reverse) |id| {
        sort.reverse = self.resolved.at(@backingInt(id)).?;
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
    // `sorted(s)` of a set orders the list of its elements (SET-1), and
    // `sorted(d)` a dictionary's keys (PRELUDE-KEYS-1).
    const input = try preludeList(Checker, self, span, self.resolved.at(@backingInt(call.arguments[0])).?);
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
    try self.refuseSortMethod(node, .{ .name = call.name, .arguments = call.arguments, .names = call.argument_names, .receiver = call.owner.? });
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
    try self.refuseSortMethod(node, .{ .name = call.name, .arguments = call.arguments, .names = call.argument_names, .receiver = self.syntax.nodes.items[@backingInt(call.base)].span });
    return checkListSortKeywords(Checker, self, node, .{
        .base = base,
        .name = call.name,
        .arguments = call.arguments,
        .names = call.argument_names,
        .temporaries = temporaries,
    });
}

/// One list's in-place sort written with keyword operands, from either
/// spelling: the method `values.sort(key=…, reverse=…)` or the prelude
/// `sort(mut values, key=…, reverse=…)`, whose operand list starts at the
/// keywords. Both lower to the same keyed sort over a fresh local owner.
const ListSort = struct {
    base: typed.NodeId,
    name: source.Span,
    arguments: []const ast.NodeId,
    names: []const ?source.Span,
    temporaries: []const typed.Type = &.{},
};

fn checkListSortKeywords(comptime Checker: type, self: *Checker, node: ast.Node, sort: ListSort) Error!typed.Node {
    const keywords = try listSortKeywords(Checker, self, sort.name, sort.arguments, sort.names);
    const list = self.nodes.items[@backingInt(sort.base)].ty;
    const element = try self.listElement(list, node.span);
    try hintSortKeywords(Checker, self, keywords, element);
    for (sort.arguments) |argument| _ = try self.expressionWithTemporaries(argument, sort.temporaries);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const owner = try b.local(list);
    const lowered = try checkedSort(Checker, self, node.span, element, keywords, owner);
    const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
    var statements: std.ArrayList(typed.StatementId) = .empty;
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = owner, .value = sort.base } }));
    try statements.appendSlice(self.allocator, try builtins.keyedSort(lowered));
    return b.block(statements.items, try b.node(.unit, .unit));
}

/// The keyword operands of a `sort(mut values, …)` call, after its receiver.
/// The parser allocates one name per operand when the call writes any keyword,
/// and none at all when every operand is positional, so a positional operand
/// leaves the name list empty: `sortKeywords` reports that operand itself.
fn preludeSortOperands(call: @FieldType(@FieldType(ast.Node, "data"), "call")) struct { arguments: []const ast.NodeId, names: []const ?source.Span } {
    const names: []const ?source.Span = if (call.argument_names.len == call.arguments.len) call.argument_names[1..] else &.{};
    return .{ .arguments = call.arguments[1..], .names = names };
}

/// `sort(mut values, key=…, reverse=…)`: the prelude spelling of a list's
/// in-place sort. The receiver, marker included, is the first operand; the
/// keyword operands are the rest.
fn checkPreludeListSort(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), base: typed.NodeId) Error!typed.Node {
    const operands = preludeSortOperands(call);
    return checkListSortKeywords(Checker, self, node, .{
        .base = base,
        .name = call.name,
        .arguments = operands.arguments,
        .names = operands.names,
    });
}

/// Hint the keyword operands of `sort(mut values, key=…, reverse=…)` from the
/// receiver's element type before the operands are checked, exactly as
/// `queueListSort` does for the method spelling. Without it a lambda key is
/// checked with no callback hint and reports `E_LAMBDA_REMOVED` where the
/// method and `sorted` report the key's own `E_SORT_KEY`.
///
/// A shape this cannot read (a positional operand, an unknown or repeated
/// keyword, a receiver that is not a named list local) is left entirely to the
/// checked pass, so no operand is hinted and no diagnostic is reported twice.
fn hintPreludeListSort(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
    if (call.arguments.len < 2) return;
    const operands = preludeSortOperands(call);
    if (operands.names.len != operands.arguments.len) return;
    const marked = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    if (marked.data != .mut_argument) return;
    const place = self.syntax.nodes.items[@backingInt(marked.data.mut_argument)];
    if (place.data != .name) return;
    const slot = self.active.get(self.src.text(place.data.name)) orelse return;
    const receiver = self.locals.items[@backingInt(slot)].ty;
    if (!receiver.isAggregate()) return;
    const record = self.catalog.records[receiver.recordIndex()];
    if (record.collection.kind != .list) return;
    const element = record.shape.buffer orelse return;
    var keywords: SortKeywords = .{};
    for (operands.arguments, operands.names) |argument, keyword| {
        const name = keyword orelse return;
        const text = self.src.text(name);
        if (std.mem.eql(u8, text, "key")) {
            if (keywords.key != null) return;
            keywords.key = argument;
        } else if (std.mem.eql(u8, text, "reverse")) {
            if (keywords.reverse != null) return;
            keywords.reverse = argument;
        } else return;
    }
    try hintSortKeywords(Checker, self, keywords, element);
}
/// Whole-path file helpers are reserved under the same shadowing rule as `print`.
fn fileAccessBuiltin(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?file_operations.Access {
    if (call.owner != null) return null;
    const name = self.src.text(call.name);
    const kind = file_operations.access(name) orelse return null;
    if (kind.isInput()) return null;
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
    const kind = file_operations.access(self.src.text(call.name)) orelse return null;
    // Input methods belong to an `Input` local and the other kinds to a `Filesystem` local, never across.
    const receiver: typed.Type = if (kind.isInput()) .input_cap else .filesystem_cap;
    if (self.locals.items[@backingInt(slot)].ty != receiver) return null;
    return kind;
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
        .lock_directory, .lock_file, .try_lock_file, .create_mode => .file,
        .read_file, .read_regular_file, .stat_path, .stat_follow_path, .list_entries_path, .statfs_path, .read_at_path, .run_process, .process_control => shapes.bytes,
        .read_text, .canonical_path, .read_link_path => shapes.text,
        .listdir, .list_directory => shapes.list,
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
    for (value_arguments, arguments[1..]) |id, *slot| slot.* = self.resolved.at(@backingInt(id)).?;
    if (kind.isInput()) return checkInputAccess(Checker, self, node, kind, arguments, shapes, out);
    if (kind.isStop()) return checkStopControl(Checker, self, node, kind, arguments, shapes, out);
    const process = kind == .run_process or kind == .process_control;
    try self.require(self.nodes.items[@backingInt(receiver)].ty, if (process) .process_cap else .filesystem_cap, node.span);
    try self.require(self.nodes.items[@backingInt(arguments[1])].ty, if (process) shapes.bytes else shapes.text, self.nodes.items[@backingInt(arguments[1])].span);
    const mode = try openMode(Checker, self, kind, value_arguments);
    if (kind == .write_file or kind.publishes() or kind == .read_at_path) {
        const data = self.nodes.items[@backingInt(arguments[2])];
        if (kind == .write_file and data.ty == shapes.text)
            return self.sink.fail("E_TYPE", data.span, "write_file writes bytes; use write_text for a str value");
        try self.require(data.ty, shapes.bytes, node.span);
    }
    if (kind.takesIntegerThird()) try self.require(self.nodes.items[@backingInt(arguments[2])].ty, .i64, node.span);
    if (kind == .atomic_write_file_mode or kind == .replace_file_mode or kind == .replace_file_synced_mode or kind == .read_at_path) try self.require(self.nodes.items[@backingInt(arguments[3])].ty, .i64, node.span);
    if (kind == .write_text or kind == .rename_path or kind == .symlink_path or kind == .link_path) try self.require(self.nodes.items[@backingInt(arguments[2])].ty, shapes.text, node.span);
    const opens = kind.opensFile();
    const direct = opens and self.trapping_open != null and std.meta.eql(self.trapping_open.?, node.span);
    out.ty = if (direct) (if (mode.text) .text_file else .file) else try fileAccessType(Checker, self, kind, mode, node.span);
    out.data = .{ .file_access = .{ .kind = kind, .mode = mode.letter, .text = mode.text, .arguments = arguments, .shapes = shapes } };
}
/// Check `stop_control(stop, op)`: the receiver is a `Stop`, the operation an `int`, and the answer a `bool` (FR5b).
fn checkStopControl(comptime Checker: type, self: *Checker, node: ast.Node, kind: file_operations.Access, arguments: []const typed.NodeId, shapes: typed.FileShapes, out: *typed.Node) Error!void {
    try self.require(self.nodes.items[@backingInt(arguments[0])].ty, .stop_cap, node.span);
    try self.require(self.nodes.items[@backingInt(arguments[1])].ty, .i64, self.nodes.items[@backingInt(arguments[1])].span);
    out.ty = .bool;
    out.data = .{ .file_access = .{ .kind = kind, .mode = 0, .text = false, .arguments = arguments, .shapes = shapes } };
}
/// Check one method of an `Input`: the receiver is an `Input`, `read` and `read_exact` take an `int`, `read_line`
/// takes nothing, and the answers are `bytes`, `bytes?` and `bytes?`. They answer values, never a `Result`: a read
/// that fails traps `R_INPUT`, the way a failed write traps `R_OUTPUT`.
fn checkInputAccess(comptime Checker: type, self: *Checker, node: ast.Node, kind: file_operations.Access, arguments: []const typed.NodeId, shapes: typed.FileShapes, out: *typed.Node) Error!void {
    try self.require(self.nodes.items[@backingInt(arguments[0])].ty, .input_cap, node.span);
    if (kind == .read or kind == .read_exact) try self.require(self.nodes.items[@backingInt(arguments[1])].ty, .i64, self.nodes.items[@backingInt(arguments[1])].span);
    out.ty = switch (kind) {
        .read => shapes.bytes,
        .read_exact, .read_line => try collections.optionType(&self.catalog, shapes.bytes, node.span),
        else => return error.InternalError,
    };
    out.data = .{ .file_access = .{ .kind = kind, .mode = 0, .text = false, .arguments = arguments, .shapes = shapes } };
}
/// Check the free `read_text(fs, path)` spelling, whose leading argument is
/// the capability the method form carries as its receiver.
fn checkFileAccessCall(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, out: *typed.Node) Error!void {
    try call_arguments.positional(call, self.sink);
    if (call.type_arguments.len != 0 or call.arguments.len != kind.arity()) return self.fileAccessArityFailure(node, kind, call.arguments.len, false);
    const first = self.resolved.at(@backingInt(call.arguments[0])).?;
    // A library channel has no rewrite to offer: its refusal says only that the call is the library's, so the call's own failure
    // (a wrong operand type) is still reported before it.
    if (kind == .run_process or kind == .process_control or kind == .stop_control) {
        try checkFileAccess(Checker, self, node, kind, first, call.arguments[1..], out);
        return warnBareFileCall(Checker, self, call, kind);
    }
    // The refusal of the spelling comes first: its rewrite is certain, and the failure of the call itself (a mode that is not a
    // literal) is then about the form the program will have (FR28).
    try warnBareFileCall(Checker, self, call, kind);
    return checkFileAccess(Checker, self, node, kind, first, call.arguments[1..], out);
}
/// Refuse a bare file function (`E_REMOVED_SPELLING`) or a library channel (`E_INTERNAL_NAME`). `exists(fs, path)` is
/// a second spelling of `fs.exists(path)` (W13-Q7): the rewrite makes the capability operand's own text the receiver,
/// which a name, a field, an index or a call can be. `run_process`, `process_control` and `stop_control` are the
/// standard library's channels, which only the library may call (W13-Q6): the refusal says so and has no edit. The
/// checker keeps checking past the refusal and fails the function when its body is done.
fn warnBareFileCall(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access) Error!void {
    const retiring_forms = @import("retiring_forms.zig");
    if (kind.isInput() or call.arguments.len < 2) return;
    const channel = kind == .run_process or kind == .process_control or kind == .stop_control;
    // The library's own calls of its channels are what the channels are for: no site of a retiring spelling, so they
    // are not asked about (and not noted in `file_reads`) at all.
    if (channel and retiring_forms.librarySource(self.src, call.name)) return;
    try retiring_forms.reported(self.sink, call.name);
    const name = self.src.text(call.name);
    const code = retiring_forms.duplicate_code;
    if (channel) {
        return retiring_forms.append(self.sink, retiring_forms.channel_code, call.name, try retiring_forms.channelMessage(self.allocator, name), null);
    }
    const first = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    const second = self.syntax.nodes.items[@backingInt(call.arguments[1])].span;
    const last = self.syntax.nodes.items[@backingInt(call.arguments[call.arguments.len - 1])].span;
    const written = try std.fmt.allocPrint(self.allocator, "{s}(fs, ...)", .{name});
    const head = try std.fmt.allocPrint(self.allocator, "{s}.{s}(", .{ self.src.text(first.span), name });
    const whole = try std.fmt.allocPrint(self.allocator, "{s}{s})", .{ head, self.src.bytes[second.start..@max(second.start, last.end)] });
    const receiver = switch (first.data) {
        .name, .field, .call, .method_call, .index => true,
        else => false,
    };
    if (!receiver) {
        const why = "the capability operand is not a name, field, index or call, which a method needs as its receiver, so the call is written by hand";
        return retiring_forms.append(self.sink, code, call.name, try retiring_forms.duplicateMessage(self.allocator, written, whole, why), null);
    }
    const edit: diagnostic.Edit = .{ .span = .{ .start = call.name.start, .end = second.start }, .text = head };
    return retiring_forms.append(self.sink, code, call.name, try retiring_forms.duplicateMessage(self.allocator, written, whole, null), .{ .edit = edit });
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
    try self.nodes.append(self.allocator, .{ .span = owner, .ty = self.locals.items[@backingInt(slot)].ty, .data = .{ .local = slot } });
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
    // A method call is a use of the handle: a `File` parameter that only its methods touch is not an unread binding.
    self.locals.items[@backingInt(slot)].usage.reads += 1;
    const text = self.locals.items[@backingInt(slot)].ty == .text_file;
    const shapes = try fileShapes(Checker, self, node.span);
    const element: typed.Type = if (text) shapes.text else shapes.bytes;
    const argument: ?typed.NodeId = if (operation.argument) |id| self.resolved.at(@backingInt(id)).? else null;
    if (operation.kind == .write) try self.require(self.nodes.items[@backingInt(argument.?)].ty, element, node.span);
    if (operation.kind == .read) if (argument) |id| try self.require(self.nodes.items[@backingInt(id)].ty, .i64, node.span);
    out.ty = switch (operation.kind) {
        .read, .readline => element,
        .readlines => try collections.listType(&self.catalog, element, node.span),
        .write => .i64,
        .flush, .close => .unit,
        .sync => try collections.resultType(&self.catalog, .unit, shapes.text, node.span),
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
/// Refuse `stream.print(...)` and `stream.write(...)` on a named `Stream` with
/// E_METHOD_REMOVED (F-s). A call that stands alone on its line, or after an
/// `_ =` discard, takes the certain rewrite to `print(stream, ...)` or
/// `write(stream, ...)`, which keeps every argument and keyword. Any other call
/// (a value that is used, or a call sharing its line) is refused without one.
fn refuseStreamSpelling(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
    const spelling = retired_methods.streamMethod(self.src.text(call.name)) orelse return;
    const receiver = call.owner orelse return;
    const arguments = try self.allocator.alloc([]const u8, call.arguments.len);
    for (call.arguments, arguments) |id, *slot| slot.* = self.src.text(self.syntax.nodes.items[@backingInt(id)].span);
    const names = try self.allocator.alloc(?[]const u8, call.argument_names.len);
    for (call.argument_names, names) |name, *slot| slot.* = if (name) |span| self.src.text(span) else null;
    const span = retired_methods.statementSpan(self.src.bytes, node.span) orelse
        return self.sink.fail(retired_methods.code, node.span, try retired_methods.streamMessage(self.allocator, spelling, false));
    const text = try retired_methods.streamCallText(self.allocator, spelling, self.src.text(receiver), arguments, names);
    const message = try retired_methods.streamMessage(self.allocator, spelling, true);
    return self.sink.failFix(retired_methods.code, node.span, message, .{ .span = span, .text = text });
}
/// The three output functions that take the stream as their first argument:
/// `print(out, values..., sep=, end=)`, `write(out, text)` and `flush(out)`. They
/// are the stage-2 spellings; the `stream.print(...)` receiver form keeps working.
const StreamFunctionKind = enum { print, write, flush };
const StreamFunction = struct {
    kind: StreamFunctionKind,
    /// The local the stream names, or null when the first argument is a field chain (`ctx.err`), which is checked as an
    /// expression and must have type `Stream`.
    slot: ?typed.LocalId,
};

/// Recognize `print(out, ...)`/`write(out, ...)`/`flush(out)` where `out` is a local
/// `Stream` or a field chain that may hold one (`ctx.err`, `self.log.stream`), and the
/// spelling is not a declared, imported or local name. A field chain is judged by its
/// type when the call is checked: one that is no `Stream` gets the diagnostic the bare
/// names carry. Any other first argument falls through to that diagnostic as before.
fn streamFunction(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?StreamFunction {
    if (call.owner != null or call.type_arguments.len != 0 or call.arguments.len == 0) return null;
    const name = self.src.text(call.name);
    const kind: StreamFunctionKind = if (std.mem.eql(u8, name, "print"))
        .print
    else if (std.mem.eql(u8, name, "write"))
        .write
    else if (std.mem.eql(u8, name, "flush"))
        .flush
    else
        return null;
    if (self.active.contains(name) or self.functions.contains(name)) return null;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    const first = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    if (first.data == .field and fieldChain(self, call.arguments[0])) return .{ .kind = kind, .slot = null };
    if (first.data != .name) return null;
    const slot = self.active.get(self.src.text(first.data.name)) orelse return null;
    if (self.locals.items[@backingInt(slot)].ty != .stream_cap) return null;
    return .{ .kind = kind, .slot = slot };
}

/// Whether `id` is a name followed by field names only (`ctx.err`): a place read, which has no effect and so may be checked out of
/// the order its call writes it in.
fn fieldChain(self: anytype, id: ast.NodeId) bool {
    var at = id;
    while (true) switch (self.syntax.nodes.items[@backingInt(at)].data) {
        .field => |field| at = field.base,
        .name => return true,
        else => return false,
    };
}

/// The typed `Stream` a field chain reads, or the diagnostic of a bare `print` when it holds anything else.
fn streamFieldValue(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!typed.NodeId {
    const value = try self.expressionWithTemporaries(call.arguments[0], &.{});
    if (self.nodes.items[@backingInt(value)].ty == .stream_cap) return value;
    _ = try outputBuiltin(Checker, self, call);
    return error.InternalError;
}

/// The typed `Stream` value of the recognized first argument.
fn streamFunctionStream(comptime Checker: type, self: *Checker, span: Span, slot: typed.LocalId) Error!typed.NodeId {
    self.locals.items[@backingInt(slot)].usage.reads += 1;
    const stream: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = span, .ty = .stream_cap, .data = .{ .local = slot } });
    return stream;
}

/// The call with its stream argument removed, so the print and write checkers see
/// exactly the arguments they already handle.
fn withoutStreamArgument(call: @FieldType(@FieldType(ast.Node, "data"), "call")) @FieldType(@FieldType(ast.Node, "data"), "call") {
    const labels = if (call.argument_names.len == call.arguments.len) call.argument_names[1..] else &.{};
    return .{ .name = call.name, .arguments = call.arguments[1..], .argument_names = labels, .type_arguments = &.{} };
}

/// Check one recognized output function: `print` and `write` reuse the receiver
/// form's checkers with the stream supplied, and `flush` is one typed node that
/// lowers to the runtime's flush.
fn checkStreamFunction(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), found: StreamFunction, out: *typed.Node) Error!void {
    const first = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    const stream = if (found.slot) |slot| try streamFunctionStream(Checker, self, first.span, slot) else try streamFieldValue(Checker, self, call);
    const rest = withoutStreamArgument(call);
    switch (found.kind) {
        .print => try checkPrint(Checker, self, node, rest, .{ .stream = stream }, out),
        .write => {
            try checkStreamWrite(Checker, self, node, rest, stream, out);
            // The stage-2 spelling answers nothing: a dropped result is not the
            // caller's business, so `write(out, text)` needs no `_ =`.
            out.ty = .unit;
        },
        .flush => {
            try call_arguments.positional(rest, self.sink);
            if (rest.arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "flush takes one Stream and nothing else");
            out.ty = .unit;
            out.data = .{ .stream_flush = .{ .stream = stream } };
        },
    }
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
    const value = self.resolved.at(@backingInt(id)).?;
    const ty_value = self.nodes.items[@backingInt(value)].ty;
    if (expected_text) {
        const text_type = try collections.preludeType(&self.catalog, "str", self.nodes.items[@backingInt(value)].span);
        try self.require(ty_value, text_type, self.nodes.items[@backingInt(value)].span);
        return value;
    }
    if (typed.linear(ty_value, self.catalog.records)) return @import("linear_rules.zig").refuse(self.sink, self.nodes.items[@backingInt(value)].span, .read);
    if (@import("extern_types.zig").contains(ty_value, self.catalog.records)) return @import("extern_types.zig").refuse(self.sink, self.nodes.items[@backingInt(value)].span, .text);
    // One rule for `print`, `str`, `repr` and a hole (PRINT-1): a value that holds a function or a capability has no text, wherever
    // it holds it, and `print` no longer writes a memory address for a list of callbacks or fails later in Core for a list of streams.
    if (@import("collection_text.zig").partWithoutText(ty_value, self.catalog.records)) |part| {
        const span = self.nodes.items[@backingInt(value)].span;
        if (part == ty_value) return self.sink.fail(io_builtins.argument_code, span, "print cannot render this value; capabilities, files, owned resources and callbacks have no Python spelling");
        return self.sink.fail(io_builtins.argument_code, span, try @import("collection_text.zig").printRefusal(self.allocator, "`print`", ty_value, part, self.catalog.records));
    }
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
    // F-s: a stream reached through a field expression has no stream-first form
    // to rewrite to (the first argument must be a name), so the spelling is
    // refused without a repair and the caller binds the stream first.
    if (retired_methods.streamMethod(name)) |spelling|
        return self.sink.fail(retired_methods.code, node.span, try retired_methods.streamMessage(self.allocator, spelling, false));
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
    const text = self.resolved.at(@backingInt(call.arguments[0])).?;
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
    const value = self.resolved.at(@backingInt(call.arguments[0])).?;
    try self.require(self.nodes.items[@backingInt(value)].ty, expected.shape.element, node.span);
    // The option holds its payload: an element of a new list moves out of it (F-55).
    try self.moveTemporaryElement(call.arguments[0], value);
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
    const value = self.resolved.at(@backingInt(call.arguments[0])).?;
    try self.require(self.nodes.items[@backingInt(value)].ty, if (ok) shape.ok_type else shape.error_type, node.span);
    try self.moveTemporaryElement(call.arguments[0], value);
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
    var stub: RecognizerStub = .{ .src = .{ .path = "recognize.selka", .bytes = "Some float int", .line_starts = &.{} } };
    defer stub.active.deinit(std.testing.allocator);
    const some: Call = .{ .name = .{ .start = 0, .end = 4 }, .arguments = &.{} };
    const float: Call = .{ .name = .{ .start = 5, .end = 10 }, .arguments = &.{} };
    const int: Call = .{ .name = .{ .start = 11, .end = 14 }, .arguments = &.{} };
    try std.testing.expect(try checks.optionConstructor(&stub, some));
    try std.testing.expectEqual(@as(?NumericTarget, .float), try checks.numericConversion(&stub, float));
    try std.testing.expectEqual(@as(?NumericTarget, .int), try checks.numericConversion(&stub, int));
    try stub.active.put(std.testing.allocator, "Some", {});
    try stub.active.put(std.testing.allocator, "float", {});
    try std.testing.expect(!try checks.optionConstructor(&stub, some));
    try std.testing.expectEqual(@as(?NumericTarget, null), try checks.numericConversion(&stub, float));
}
