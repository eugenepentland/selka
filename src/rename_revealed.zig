//! The sentence a shadowing repair's refusal adds when the rename only reveals errors the name clash was hiding (FR19).
//!
//! A binding that hides a module-level name stops the check of the function it is in, so the function's own errors are
//! never shown. Once the binding is renamed the function is checked for the first time, and an error there makes the rename
//! refuse (the project must check as before). The rename is right all the same, so the refusal says what happened: the error,
//! with its code and its own message, where to find it, and that the same command works once it is fixed.
const std = @import("std");

/// The errors a rename reveals: how many, and the first with its severity, code and message.
pub const Revealed = struct { count: usize, severity: []const u8, code: []const u8, message: []const u8 };

/// The longest message of the first error the sentence quotes, in bytes.
const quoted_limit = 240;

/// The sentence that follows the refusal's list of differing diagnostics: `". The rename itself is right: ..."`.
pub fn sentence(allocator: std.mem.Allocator, revealed: Revealed) std.mem.Allocator.Error![]const u8 {
    const many = revealed.count > 1;
    const text = if (revealed.message.len > quoted_limit) revealed.message[0..quoted_limit] else revealed.message;
    return std.fmt.allocPrint(allocator, ". The rename itself is right: the name clash had stopped the check of the function it is in, " ++
        "so the program had {s} that no check could show{s} {s}[{s}]: {s}. {s} printed below. Fix {s}, then run the same command again", .{
        if (many) "errors" else "an error",
        if (many) "; the first is" else ":",
        revealed.severity,
        revealed.code,
        text,
        if (many) "Their places are" else "Its place is",
        if (many) "them" else "it",
    });
}
