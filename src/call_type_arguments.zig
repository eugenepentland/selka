//! Distinguish `f[T](x)` — explicit type arguments on a generic function — from `Box[T](x)`,
//! the construction of a generic record. Both spell a square-bracket application in call
//! position, so the decision rests on whether the base name declares a function or a type.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Names = @import("module_names.zig").Names;
const Call = @import("call_arguments.zig").Call;

/// Report whether a square-bracket application names a declared function rather than a type.
/// Such an application is a call's type-argument list, so the nominal catalog must not
/// resolve it as a type and the checker rewrites the call instead.
pub fn functionApplication(
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    application: ast.TypeApplication,
    sink: *diagnostic.Sink,
) diagnostic.Error!bool {
    if (names) |module| {
        const kind = try module.symbolKind(application.name);
        return kind == .function;
    }
    const text = src.text(application.name);
    for (program.types.records) |declaration| if (std.mem.eql(u8, src.text(declaration.name), text)) return false;
    for (program.types.variants) |declaration| if (std.mem.eql(u8, src.text(declaration.name), text)) return false;
    for (program.types.domains) |declaration| if (std.mem.eql(u8, src.text(declaration.name), text)) return false;
    for (program.types.resources) |declaration| if (std.mem.eql(u8, src.text(declaration.name), text)) return false;
    _ = sink;
    for (program.functions) |function| {
        if (function.policy.owner != null) continue;
        if (std.mem.eql(u8, src.text(function.name), text)) return true;
    }
    return false;
}

/// Rewrite `f[T](x)` into the call `f` carrying `T` as an explicit type argument.
/// Returns null when the call already has type arguments, names an owner, or is not an
/// application of a declared function.
pub fn split(
    src: source.Source,
    program: ast.Program,
    names: ?*Names,
    call: Call,
    sink: *diagnostic.Sink,
) diagnostic.Error!?Call {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    if (call.name.end == call.name.start or src.bytes[call.name.end - 1] != ']') return null;
    for (program.types.expressions.applications) |application| {
        if (application.span.start != call.name.start or application.span.end != call.name.end) continue;
        if (!try functionApplication(src, program, names, application, sink)) return null;
        var out = call;
        out.name = application.name;
        out.type_arguments = application.arguments;
        return out;
    }
    return null;
}
