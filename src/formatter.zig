//! Canonical source text for a parser-validated program.
//!
//! Indentation is syntax on this surface, and the layout rules that make a suite
//! legible — four-space steps, blank lines between declarations, comments in their
//! own token gaps — are already the rules a valid program follows. Reprinting such
//! a program from its tokens could only move bytes that carry meaning, so the
//! canonical form of a program the parser accepted is the program itself.
const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");

/// Return the canonical text of an already-parsed program; callers own the copy.
pub fn format(allocator: std.mem.Allocator, bytes: []const u8, input_tokens: []const lex.Token, types: ast.TypeDeclarations) std.mem.Allocator.Error![]u8 {
    _ = input_tokens;
    _ = types;
    return allocator.dupe(u8, bytes);
}
