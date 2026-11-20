//! A generic declaration's `from` clause, judged at each of its instances (lane HC; lane CB left it open as defect 4's
//! generic case).
//!
//! The declaration authority (`borrow_contract.zig`) refuses a nongeneric clause in which no source can lend the result.
//! A generic declaration's result is not resolved there, and its instances can differ: `T? from name` with `name: bytes`
//! lends for `T = bytes` and not for `T = Inst`. Core keeps a contract with no lending source whole (`build.zig`,
//! `lendingSources`), and the IR verifier refuses it, so `check` accepted an instance that a Debug or `--verify-facts`
//! build refused. The ownership check refuses such an instance with E_BORROW_SOURCE (R4), naming the instance and the call
//! that made it, with the clause's removal where that is certain (`borrow_return_repair.removeConcreteSources`).
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const return_borrow = language.return_borrow;
const Span = language.source.Span;

/// Whether `function`, a generic instance with a `from` clause and a managed result, has no source that can lend the
/// result (`return_borrow.sourceLends` on the instance's concrete types): no source holds storage of the result's leaf, or
/// each is a plain `str` or `bytes` parameter, a view that lends only a text or bytes result of its own kind. A nongeneric
/// function is the declaration authority's.
pub fn unlendable(program: typed.Program, function: typed.Function) bool {
    if (function.type_arguments.len == 0) return false;
    const positions = return_borrow.effectiveSources(program.records, function.signature);
    if (positions.len == 0) return false;
    const leaf = return_borrow.shape(program.records, function.signature);
    for (positions) |position| {
        const mutable = std.mem.indexOfScalar(u16, function.signature.declared_mutates, position) != null;
        const parameter: ?typed.Type = if (position < function.scope.locals.len) function.scope.locals[position].ty else null;
        if (return_borrow.sourceLends(program.records, mutable, parameter, leaf)) return false;
    }
    return true;
}

/// The earliest direct call of `function` in the program's source: a call that made the instance. Null when only a
/// function value names it.
pub fn firstCall(program: typed.Program, function: typed.FunctionId) ?Span {
    var first: ?Span = null;
    for (program.nodes) |node| switch (node.data) {
        .call => |call| if (call.function == function) {
            if (first == null or node.span.start < first.?.start) first = node.span;
        },
        else => {},
    };
    return first;
}

/// The refusal's message: the instance, its result and why no source lends it.
pub fn message(a: std.mem.Allocator, function: typed.Function) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(a, "the instance `{s}` has no `from` source that can lend its result: a source lends only storage it holds, " ++
        "and a plain text or bytes parameter arrives as a view, which lends only a text or bytes result of its own kind; " ++
        "remove the `from` clause, or call it with a type argument one of its sources can lend", .{function.name});
}
