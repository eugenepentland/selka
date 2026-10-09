//! The contract a violated `@requires`, `@ensures` or `@invariant` names, read back from
//! its trap record (CONTRACT-TRAP-1): the runtime writes the clause as the record's
//! `operation`, ``subject kind `clause`[: message]``, and a `diagnostic-v1` record
//! carries it as a `contract` object, with the caller that broke a precondition.
const source_names = @import("selka").source_names;
const std = @import("std");

/// A source position as `diagnostic-v1` spells one.
pub const Location = struct { path: []const u8, start: Start };

/// A line and column, both 1-based.
pub const Start = struct { line: u64, column: u64 };

/// The `contract` object of a `diagnostic-v1` record.
pub const Contract = struct {
    /// `requires`, `ensures` or `invariant`.
    kind: []const u8,
    /// The function (or `Domain.member`) whose clause, or the type whose invariant, failed.
    subject: []const u8,
    /// The clause's condition as written.
    clause: []const u8,
    /// The clause's message, when it has one.
    message: ?[]const u8 = null,
    /// For a precondition, the call site that broke it: the next frame out.
    caller: ?Location = null,
};

// twin-drift-ok: the new core's port of native_trap_detail.contract, which S5-D deletes with the old back end; it reads the operation text, not the record bytes.
/// The contract a trap with `code` and record `operation` reports, or null when the trap
/// is not a contract's or its operation does not name a clause. `caller` is the frame
/// that called the trapping function; only a precondition keeps it.
pub fn parse(code: []const u8, operation: []const u8, caller: ?Location) ?Contract {
    var contract_code = false;
    for ([_][]const u8{ "R_REQUIRES", "R_ENSURES", "R_INVARIANT" }) |known| contract_code = contract_code or std.mem.eql(u8, code, known);
    if (!contract_code) return null;
    const subject_end = std.mem.indexOfScalar(u8, operation, ' ') orelse return null;
    const kind_end = std.mem.indexOfScalarPos(u8, operation, subject_end + 1, ' ') orelse return null;
    const open = std.mem.indexOfScalarPos(u8, operation, kind_end, '`') orelse return null;
    const close = std.mem.lastIndexOfScalar(u8, operation, '`') orelse return null;
    if (close <= open) return null;
    const kind = operation[subject_end + 1 .. kind_end];
    const tail = operation[close + 1 ..];
    return .{
        .kind = kind,
        .subject = operation[0..subject_end],
        .clause = operation[open + 1 .. close],
        .message = if (std.mem.startsWith(u8, tail, ": ")) tail[2..] else null,
        .caller = if (std.mem.eql(u8, kind, "requires")) caller else null,
    };
}

// spec-case: CONTRACT-TRAP-1
test "a contract trap's operation names its kind, subject, clause, message and a precondition's caller" {
    const caller: Location = .{ .path = source_names.entry, .start = .{ .line = 6, .column = 12 } };
    const required = parse("R_REQUIRES", "half requires `amount > 0`: amount must be positive", caller).?;
    try std.testing.expectEqualStrings("requires", required.kind);
    try std.testing.expectEqualStrings("half", required.subject);
    try std.testing.expectEqualStrings("amount > 0", required.clause);
    try std.testing.expectEqualStrings("amount must be positive", required.message.?);
    try std.testing.expectEqual(@as(u64, 6), required.caller.?.start.line);
    const ensured = parse("R_ENSURES", "grow ensures `result > 100`", caller).?;
    try std.testing.expectEqualStrings("ensures", ensured.kind);
    try std.testing.expect(ensured.message == null);
    try std.testing.expect(ensured.caller == null);
    try std.testing.expect(parse("R_ASSERT", "half requires `amount > 0`", caller) == null);
    try std.testing.expect(parse("R_REQUIRES", "no clause here", caller) == null);
}
