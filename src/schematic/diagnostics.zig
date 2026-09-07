//! Stable pilot diagnostics distinguish syntax, supported-subset and connectivity errors.
const std = @import("std");
const print = std.debug.print;
const Issue = @import("host.zig").Issue;
/// Human explanation of the guest's stable numeric issue code.
pub fn message(code: i64) []const u8 {
    return switch (code) {
        1 => "unexpected closing parenthesis",
        2 => "S-expression nesting exceeds 128 lists",
        3 => "unterminated quoted string",
        4 => "unclosed list at end of source",
        5 => "schematic exceeds bounded node, component or pin capacity",
        6 => "unsupported string escape; use quote, backslash, n, r or t",
        7 => "input exceeds 1 MiB",
        8 => "input must be UTF-8 containing XML 1.0 characters",
        10, 16 => "expected one parameterless defmodule containing one design-block",
        11 => "instance requires a quoted reference and component specification",
        12 => "duplicate component reference",
        13 => "pin needs numeric pads and a nonempty net; names cannot contain whitespace or escapes",
        14 => "pin number is absent from the supplied pinout or two-terminal primitive",
        15 => "pin is connected or marked NC more than once",
        17 => "unsupported DSL form; this pilot does not evaluate arbitrary Netlisp expressions",
        18 => "pinout must contain exactly one unique label for each pad 1 through 41",
        19 => "expected one IC matching the supplied pinout and supported two-terminal primitives",
        20 => "every physical pad must be connected or explicitly marked nc-ok",
        21 => "invalid interface, direction, port-group or lane rename",
        22 => "duplicate expanded port name",
        23 => "port has no connected pad",
        24 => "guest could not acquire or extend bounded model storage",
        else => "guest schematic validation failed",
    };
}
/// Print a source path, line, column and stable code without exposing a host stack trace.
pub fn report(issue: Issue, paths: []const []const u8, documents: []const []const u8) void {
    if (issue.file < 0 or issue.file >= documents.len or issue.file >= paths.len) {
        print("SCHEMATIC_{d}: {s}\n", .{ issue.code, message(issue.code) });
        return;
    }
    const file: usize = @intCast(issue.file);
    const position: usize = @intCast(@max(0, issue.position));
    var line: usize = 1;
    var column: usize = 1;
    for (documents[file][0..@min(position, documents[file].len)]) |byte| {
        if (byte == '\n') {
            line += 1;
            column = 1;
        } else column += 1;
    }
    print("{s}:{d}:{d}: SCHEMATIC_{d}: {s}\n", .{ paths[file], line, column, issue.code, message(issue.code) });
}
