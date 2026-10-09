//! Read LLVM YAML loop-vectorization successes without inventing missing evidence.
const std = @import("std");
const cost = @import("cost.zig");

/// Consume standard -fsave-optimization-record YAML. Only a Passed/loop-vectorize/
/// Vectorized document supplies a positive count. Missing functions stay unknown;
/// remaining source loops stay unknown, since LLVM may clone or eliminate loops.
pub fn apply(report: *cost.Report, yaml: []const u8) void {
    var documents = std.mem.splitSequence(u8, yaml, "---");
    while (documents.next()) |document| {
        if (!std.mem.startsWith(u8, std.mem.trimStart(u8, document, " \t\r\n"), "!Passed")) continue;
        const pass = field(document, "Pass:") orelse continue;
        const name = field(document, "Name:") orelse continue;
        const raw = field(document, "Function:") orelse continue;
        const function = if (std.mem.startsWith(u8, raw, "my.")) raw[3..] else raw;
        if (!std.mem.eql(u8, pass, "loop-vectorize") or !std.mem.eql(u8, name, "Vectorized")) continue;
        for (report.functions) |*row| {
            if (!std.mem.eql(u8, function, row.name)) continue;
            row.counts.llvm_vectorized_loops = (row.counts.llvm_vectorized_loops orelse 0) + 1;
        }
    }
    report.totals = .{};
    for (report.functions) |row| report.totals.add(row.counts);
}

fn field(document: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, document, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, key)) continue;
        return std.mem.trim(u8, line[key.len..], " \t\r'\"");
    }
    return null;
}
