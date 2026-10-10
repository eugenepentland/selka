//! Complete syntax oracle used to qualify the independently built parser.
const std = @import("std");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const parser = @import("parser.zig");
const component = @import("parser_component.zig");
const lexer_component = @import("lexer_component.zig");
const values = @import("parser_value.zig");

/// Parse one module without loading imports and serialize all logical AST fields.
/// Explicit shadow modes compare components before any document is returned.
/// The sink uses a caller-owned arena so parsed diagnostic repairs stay alive.
pub fn render(allocator: std.mem.Allocator, src: source.Source, sink: *diagnostic.Sink, runtime: component.Runtime) (diagnostic.Error || component.Error || lexer_component.Error || values.Error)![]u8 {
    const tokens = try lexer_component.lex(allocator, src, sink, .{ .io = runtime.io, .environ = runtime.environ, .component_dir = runtime.component_dir, .timeout_ms = runtime.timeout_ms });
    defer allocator.free(tokens);
    var p: parser.Parser = .{ .src = src, .tokens = tokens, .storage = sink.allocator, .sink = sink };
    const program = try component.parse(&p, true, runtime);
    return values.encode(allocator, program);
}
