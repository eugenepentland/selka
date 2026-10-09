//! Recognition and argument shaping for the ordinary I/O builtins.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Call = @import("call_arguments.zig").Call;

/// Diagnostic reported for malformed builtin I/O calls.
pub const argument_code = "E_IO_ARGUMENT";

/// Diagnostic reported for a bare `print`/`eprint` that names no `Stream`.
pub const output_capability_code = "E_OUTPUT_CAPABILITY";

/// Fix text carried by `E_OUTPUT_CAPABILITY`.
pub const output_capability_message = "print needs a Stream; add `out: Stream` to this function and pass one from main";

/// Builtin whose spelling is reserved unless a local or declared function shadows it.
pub const Builtin = enum {
    print,
    open,
    read_file,
    read_text,
    write_file,
    write_text,
    exists,
    listdir,
    mkdir,
    remove,
    /// Number of positional value arguments, excluding the leading capability.
    pub fn arity(self: Builtin) usize {
        return switch (self) {
            .print => 0,
            .write_file, .write_text => 2,
            else => 1,
        };
    }
};

/// Resolve a reserved builtin spelling, or null for ordinary call names.
pub fn builtin(name: []const u8) ?Builtin {
    return std.meta.stringToEnum(Builtin, name);
}

/// Positional operands plus the optional `sep=`/`end=` text of a `print` call.
pub const Arguments = struct { values: []const ast.NodeId, separator: ?ast.NodeId, terminator: ?ast.NodeId };

/// Split `print` operands into positional values and its two accepted keywords.
pub fn printArguments(src: source.Source, call: Call, sink: *diagnostic.Sink) diagnostic.Error!Arguments {
    if (call.type_arguments.len != 0) return sink.fail("E_ARITY", call.name, "print takes no type arguments");
    if (call.argument_names.len == 0) return .{ .values = call.arguments, .separator = null, .terminator = null };
    var out: Arguments = .{ .values = call.arguments, .separator = null, .terminator = null };
    var positional: usize = 0;
    for (call.arguments, call.argument_names) |argument, name| {
        const keyword = name orelse {
            if (out.separator != null or out.terminator != null) return sink.fail(argument_code, call.name, "positional print arguments must precede `sep=` and `end=`");
            positional += 1;
            continue;
        };
        const spelling = src.text(keyword);
        const unknown = "print accepts only the `sep=` and `end=` keyword arguments";
        const slot = if (std.mem.eql(u8, spelling, "sep")) &out.separator else if (std.mem.eql(u8, spelling, "end"))
            &out.terminator
        else
            return sink.fail(argument_code, keyword, unknown);
        if (slot.* != null) return sink.fail(argument_code, keyword, "print received this keyword argument more than once");
        slot.* = argument;
    }
    out.values = call.arguments[0..positional];
    return out;
}
