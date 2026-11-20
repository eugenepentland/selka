//! The single declaration authority for a source-written `from` contract.
//! Semantic preparation supplies type facts, including possibly managed generic
//! parameters, and invokes this before any body or summary cache is consulted.
const std = @import("std");
const ast = @import("../ast.zig");
const typed = @import("../typed.zig");
const source = @import("../source.zig");
const diagnostic = @import("../diagnostic.zig");
const declaration_borrow = @import("../declaration_borrow.zig");
const return_borrow = @import("../return_borrow.zig");

/// Declaration type facts supplied before bodies or cached summaries are read.
/// Generic declarations keep their original contract through scalar instances.
pub const Types = struct {
    parameters: []const bool,
    result: ?typed.Type,
    records: []const typed.Record,
    /// Whether the declared failure type (`fails E`) may hold managed storage; false without one.
    failure_managed: bool = false,
    /// Each parameter's concrete type, null where it is not concrete (a type parameter); empty when not known.
    parameter_types: []const ?typed.Type = &.{},
};

/// Resolve source names and require plain or `mut` parameters whose types may
/// contain managed storage. The returned positions belong to `a`, in parameter
/// order. `types` supplies facts, not a second eligibility decision.
pub fn declaration(a: std.mem.Allocator, src: source.Source, function: ast.Function, types: Types, sink: *diagnostic.Sink) diagnostic.Error!typed.ReturnOrigin {
    const parameters = function.signature.parameters;
    const names = function.signature.borrowing;
    if (names.len == 0) return .fresh;
    std.debug.assert(types.parameters.len == parameters.len);
    var positions: std.ArrayList(u16) = .empty;
    defer positions.deinit(a);
    for (names, 0..) |name, source_index| {
        var found: ?usize = null;
        for (parameters, 0..) |parameter, position| {
            if (std.mem.eql(u8, src.text(name), src.text(parameter.name))) {
                found = position;
                break;
            }
        }
        const position = found orelse return sink.failOwnership(
            .{ .code = "E_BORROW_SOURCE", .rule = .R4 },
            name,
            "a `from` source must name a parameter of this function",
        );
        if (parameters[position].own or !types.parameters[position]) return sink.failOwnership(
            .{ .code = "E_BORROW_SOURCE", .rule = .R4 },
            name,
            "a `from` source must be a plain or mut parameter whose type contains managed storage",
        );
        // Rule Z3 (a build-time limit): the ownership certificate cannot yet state a borrow of a `mut` parameter's final value
        // returned inside a `Result` that owns its error, so Core could not build it (F-RA-115, lane O3 D-O3-5).
        if (parameters[position].mut and function.signature.failure_type != null and types.failure_managed) return sink.failOwnership(
            .{ .code = "E_CORE_UNSUPPORTED", .rule = .Z3 },
            name,
            "a function that fails with a managed error cannot return a borrow of its `mut` parameter yet; return a copy (drop this `from`), fail with an `int`, or split the update from the read",
        );
        const index = std.math.cast(u16, position) orelse return error.InternalError;
        if (std.mem.indexOfScalar(u16, positions.items, index) != null) return sink.failOwnershipFix(
            .{ .code = "E_BORROW_SOURCE", .rule = .R4 },
            name,
            "each `from` source must be named once; remove this duplicate source",
            .{ .span = .{ .start = names[source_index - 1].end, .end = name.end }, .text = "" },
        );
        try positions.append(a, index);
    }
    if (function.signature.type_parameters.len == 0) {
        const result = types.result orelse return error.InternalError;
        const signature: typed.FunctionSignature = .{ .return_type = result, .return_origin = .{ .params = positions.items } };
        if (return_borrow.shape(types.records, signature).kind == .none) return sink.failOwnershipFix(
            .{ .code = "E_BORROW_SOURCE", .rule = .R4 },
            function.signature.return_type,
            "this result contains no managed storage; remove its `from` clause",
            .{ .span = declaration_borrow.clause(function.signature) orelse return error.InternalError, .text = "" },
        );
    }
    // A source lends only storage it holds, and a plain text or bytes parameter is passed as a view, which lends only a result
    // of its own kind (`return_borrow.sourceLends`): when no source can lend the result, the contract is one Core cannot
    // declare (`build.zig`, `lendingSources`). No return can then be a borrow of a source, so the clause says nothing and its
    // removal is certain. A generic declaration (no result here) is judged at
    // each instance by Core's ownership check (`instance_borrow.zig`).
    if (types.result) |result| if (types.parameter_types.len == parameters.len) {
        const signature: typed.FunctionSignature = .{ .return_type = result, .return_origin = .{ .params = positions.items } };
        const leaf = return_borrow.shape(types.records, signature);
        // A result with no managed storage is the clause above's question (a scalar generic instance ignores borrowing).
        const lends = leaf.kind == .none or for (positions.items) |position| {
            if (return_borrow.sourceLends(types.records, parameters[position].mut, types.parameter_types[position], leaf)) break true;
        } else false;
        if (!lends) return sink.failOwnershipFix(
            .{ .code = "E_BORROW_SOURCE", .rule = .R4 },
            names[0],
            "a source lends only storage it holds, and a plain text or bytes parameter arrives as a view, which lends only a text or bytes result of its own kind, so no `from` source can lend this result; remove the `from` clause",
            .{ .span = declaration_borrow.clause(function.signature) orelse return error.InternalError, .text = "" },
        );
    };
    std.mem.sort(u16, positions.items, {}, std.sort.asc(u16));
    return .{ .params = try positions.toOwnedSlice(a) };
}
