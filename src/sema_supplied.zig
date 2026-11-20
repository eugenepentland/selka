//! Calls of the standard library's `builtin func` declarations, however they are spelled (W10).
//!
//! The module's own spelling (`strings.upper(text)`) is recognised before resolution, as it always was
//! (`sema_collections.checkRecognizedHome`, `sema_simd.isLaneCall`, `scalar_text_helpers.attempt`). Every other spelling
//! resolves first: an import alias (`import strings as s`), a re-export (`export strings.upper`), keyword arguments or
//! explicit type arguments. When the resolved declaration is a `builtin func`, the call is answered here with the same
//! operation, so no spelling of a supplied function runs anything but the operation. A non-generic declaration's own
//! body is the parser's call of itself (`Parser.suppliedBody`), answered the same way, so its function value runs the
//! operation too.
const std = @import("std");
const product = @import("product.zig");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const builtin_functions = @import("builtin_functions.zig");
const Error = diagnostic.Error;
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");

/// The module a supplied declaration belongs to: the embedded module its source is, or the file's base name for a
/// source granted the standard library's trust.
pub fn moduleOf(src: source.Source, declaration: ast.Function) []const u8 {
    const path = src.locate(declaration.name.start).path;
    if (builtin_functions.embeddedModule(path)) |module| return module;
    const base = std.fs.path.basename(path);
    return product.sourceStem(base);
}

/// What supplies `declaration`, or null when it is not a `builtin func`.
pub fn supplierOf(src: source.Source, declaration: ast.Function) ?builtin_functions.Supplier {
    if (!declaration.policy.builtin) return null;
    return builtin_functions.supplier(moduleOf(src, declaration), src.text(declaration.name), declaration.signature.parameters.len);
}

/// Refuse a `builtin func` that no supplier answers: a declaration cannot claim an operation the compiler lacks.
pub fn requireSupplier(src: source.Source, declaration: ast.Function, sink: *diagnostic.Sink) Error!void {
    if (!declaration.policy.builtin or supplierOf(src, declaration) != null) return;
    return sink.fail(builtin_functions.supplier_code, declaration.name, "no operation of the compiler supplies this `builtin func`; check its module, name and parameter count, or give it a body");
}

/// Whether a `builtin func` keeps an empty checked body: every one but a home, whose body is its operation.
pub fn bodiless(src: source.Source, declaration: ast.Function) bool {
    const supplier = supplierOf(src, declaration) orelse return false;
    return !supplier.valueRuns();
}

/// The call a supplied function's body makes of itself: its name span is the declaration's own (`Parser.suppliedBody`),
/// which no call written in a source can have.
pub fn isSelfCall(declaration: ast.Function, call: Call) bool {
    return declaration.policy.builtin and call.owner == null and call.name.start == declaration.name.start and call.name.end == declaration.name.end;
}

/// Answer a call of a supplied declaration with its operation, or null when the supplier is a body builder (the
/// `parallel` and `testing` functions are ordinary calls whose bodies Core writes) or the receiver is not the row's.
/// `call.arguments` are in parameter order.
pub fn answer(comptime Checker: type, self: *Checker, node: ast.Node, call: Call, supplier: builtin_functions.Supplier, temporaries: []const typed.Type) Error!?typed.Node {
    switch (supplier) {
        .home => |row| return self.checkSuppliedHome(node, row, call.arguments, temporaries),
        .lane => |operation| {
            var out: typed.Node = .{ .span = node.span, .ty = .unit, .data = .unit };
            try @import("sema_simd.zig").checkOperation(Checker, self, node, call, operation, &out);
            return out;
        },
        .scalar => |candidate| {
            var out: typed.Node = .{ .span = node.span, .ty = .unit, .data = .unit };
            if (!try @import("scalar_text_helpers.zig").attemptHelper(Checker, self, node, call, candidate, &out)) return null;
            return out;
        },
        .parallel, .testing, .json, .registers => return null,
    }
}

/// The body of a non-generic `builtin func`: its call of itself is the operation, checked against the parameters.
pub fn selfCall(comptime Checker: type, self: *Checker, node: ast.Node, call: Call, temporaries: []const typed.Type) Error!?typed.Node {
    const id = self.current_function orelse return null;
    const declaration = self.syntaxFunction(id);
    if (!isSelfCall(declaration, call)) return null;
    const supplier = supplierOf(self.src, declaration) orelse return null;
    return answer(Checker, self, node, call, supplier, temporaries);
}

/// Refuse a resolved call whose operation answers `answered` where the declaration says `declared`: the declaration is
/// the defect (`E_BUILTIN_SIGNATURE`). The three dictionary views and the two loop sources are exempt
/// (`builtin_functions.unsigned_results`): a call answers what no signature can name.
pub fn requireDeclaredResult(src: source.Source, declaration: ast.Function, answered: typed.Type, declared: typed.Type, at: source.Span, sink: *diagnostic.Sink) Error!void {
    if (answered == declared) return;
    if (builtin_functions.unsignedResult(moduleOf(src, declaration), src.text(declaration.name))) return;
    return sink.fail(builtin_functions.signature_code, at, "this `builtin func` declares a result its operation does not answer; the standard library's declaration is wrong");
}

/// The row and the arguments of a resolved home call that left trailing parameters to their defaults.
pub const WrittenHome = struct {
    /// The home row for the count of arguments the call wrote.
    row: @import("retired_methods.zig").Retirement,
    /// The written arguments, in parameter order.
    arguments: []const ast.NodeId,
};

/// The home row a resolved call of a supplied home answers with when it wrote only the first `written` of the
/// declaration's parameters and left the rest to their defaults (a search's `start` and `end`, W13-Q3): those are not
/// passed, so `b.find(data, needle)` through an alias is the unbounded search its direct spelling is. Null when the
/// call wrote every parameter or wrote one past a default it skipped (`end=` without `start`), where the bound row
/// with the default written in is the answer.
pub fn writtenHome(src: source.Source, declaration: ast.Function, call: Call, written: usize) ?WrittenHome {
    if (written >= call.arguments.len or call.evaluation_order.len < written) return null;
    for (call.evaluation_order[0..written]) |target| if (target >= written) return null;
    const row = builtin_functions.home(moduleOf(src, declaration), src.text(declaration.name), written) orelse return null;
    return .{ .row = row, .arguments = call.arguments[0..written] };
}

/// Whether a resolved home call may pass `actual` where its declaration names `expected`: a `byte_buffer` where a
/// `bytes` read takes `bytes` (W13-Q5). The operation's own check then decides, as it does for the module's own
/// spelling, so the buffer is lent to the operation its method runs.
pub fn lendsBuffer(supplier: builtin_functions.Supplier, actual: typed.Type, expected: typed.Type, records: []const typed.Record) bool {
    const row = switch (supplier) {
        .home => |home| home,
        else => return false,
    };
    if (!@import("retired_methods.zig").lendsBuffer(row)) return false;
    if (!actual.isAggregate() or !expected.isAggregate()) return false;
    const given = records[actual.recordIndex()];
    const wanted = records[expected.recordIndex()];
    if (!given.isCollection() or !wanted.isCollection()) return false;
    const shared = @import("sema_shared.zig");
    return shared.isMutableBytes(given) and wanted.collection.kind == .bytes and !shared.isMutableBytes(wanted);
}

/// The supplier of the `builtin func` a call names through an alias or a re-export, resolved without reporting
/// anything, or null when the call names no supplied function of the embedded library. A local that shares the
/// qualifier's name is a value, never the module.
pub fn resolvedSupplier(comptime Checker: type, self: *Checker, call: Call) Error!?builtin_functions.Supplier {
    const names = self.catalog.module_names orelse return null;
    const text = self.src.text(call.name);
    var alias: ?[]const u8 = null;
    var name: []const u8 = text;
    if (call.owner) |owner| {
        alias = self.src.text(owner);
    } else if (std.mem.lastIndexOfScalar(u8, text, '.')) |dot| {
        if (dot == 0 or dot + 1 == text.len) return null;
        alias = text[0..dot];
        name = text[dot + 1 ..];
    } else return null;
    if (self.active.contains(alias.?)) return null;
    const target = try names.functionTarget(call.name, alias, name) orelse return null;
    const module = builtin_functions.embeddedModule(target.path) orelse return null;
    return builtin_functions.supplier(module, target.name, call.arguments.len);
}

/// The message for a function value of a supplied operation that no one body can be.
pub fn valueMessage(allocator: std.mem.Allocator, module: []const u8, name: []const u8) Error![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "`{s}.{s}` is an operation the compiler checks at each call against its arguments, not a function value; call it directly, or pass a named function that calls it",
        .{ module, name },
    );
}
