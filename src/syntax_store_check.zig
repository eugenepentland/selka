//! The round trip `selka dump-syntax --store-check` and the stored-syntax tests make: encode a module, reassemble it and hold it against the parse.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const literals_fact = @import("ast_literals.zig");
const store = @import("syntax_store.zig");
const frontend_cache = @import("frontend_cache.zig");

/// What `check` found: how many bodies are lazy, how many functions keep their tree in the declaration part and the entry's size.
pub const Summary = struct { lazy: usize, eager: usize, bytes: usize };

/// Encode `program`, reassemble the entry and hold the result against the parse: the tables and declarations must encode to the same
/// bytes `frontend_cache.encodeSyntax` writes for the parse. The error is `Mismatch` when they do not.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program) (store.Error || error{Mismatch})!Summary {
    const entry = try store.encode(allocator, src, program);
    defer allocator.free(entry);
    const decided = try store.layout(allocator, program);
    defer allocator.free(decided.bodies);
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const rebuilt = try store.reassemble(arena_state.allocator(), entry);
    const expected = try frontend_cache.encodeSyntax(allocator, program);
    defer allocator.free(expected);
    const actual = try frontend_cache.encodeSyntax(allocator, rebuilt);
    defer allocator.free(actual);
    if (!std.mem.eql(u8, expected, actual)) return error.Mismatch;
    const declarations = try store.decodeDeclarations(arena_state.allocator(), entry);
    const found = try store.factsOf(arena_state.allocator(), src, program);
    if (!literals_fact.same(declarations.facts.literals, found.literals) or declarations.facts.retired != found.retired) return error.Mismatch;
    return .{ .lazy = decided.bodies.len, .eager = decided.eager, .bytes = entry.len };
}
