//! RC loop code generation: operand words stay promotable and loop copies
//! carry no ownership work the collector's copy does not.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn emit(source: []const u8, mode: runtime.Selection) !std.json.Parsed(Manifest) {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(mode);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_loop_codegen.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = false, .frame_checks = false });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

/// Whether any `%sN` operand word's address reaches something other than a
/// load or store address: a call argument, arithmetic, a blit or a stored value.
fn operandEscapes(il: []const u8) bool {
    var aliases: [64][]const u8 = undefined;
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, il, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        const copy = std.mem.indexOf(u8, line, " =l copy %s") orelse std.mem.indexOf(u8, line, " =l add %s");
        if (copy) |at| {
            const rest = line[at + " =l copy %s".len ..];
            if (rest.len != 0 and std.ascii.isDigit(rest[0]) and count < aliases.len) {
                aliases[count] = line[0..at];
                count += 1;
            }
        }
    }
    lines = std.mem.splitScalar(u8, il, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        for (aliases[0..count]) |alias| {
            if (!mentions(line, alias)) continue;
            if (std.mem.startsWith(u8, line, alias)) continue;
            if (std.mem.indexOf(u8, line, " =l load") != null or std.mem.indexOf(u8, line, " =w load") != null) continue;
            if (std.mem.startsWith(u8, line, "store") and std.mem.endsWith(u8, line, alias)) continue;
            return true;
        }
    }
    return false;
}

fn mentions(line: []const u8, name: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, line, from, name)) |at| {
        const end = at + name.len;
        if (end == line.len or !std.ascii.isAlphanumeric(line[end])) return true;
        from = end;
    }
    return false;
}

const moves =
    \\def made(n: int) -> list[int]:
    \\    values: list[int] = []
    \\    for i in range(n):
    \\        values.append(i)
    \\    return values
    \\def main() -> int:
    \\    rows: list[list[int]] = []
    \\    for i in range(3):
    \\        row = made(i)
    \\        rows.append(row)
    \\    kept = rows
    \\    return len(kept)
;

// spec: RC-OPERAND-STAGE-1
test "RC-OPERAND-STAGE-1 ownership helpers receive staged cells, never operand words" {
    var rc = try emit(moves, .rc);
    defer rc.deinit();
    const main = try named(rc.value, "main");
    try t.expect(std.mem.indexOf(u8, main, "%rcstage") != null);
    try t.expect(std.mem.indexOf(u8, main, "copy %rcarg") != null);
    try t.expect(!operandEscapes(main));
    try t.expect(!operandEscapes(try named(rc.value, "made")));
    var gc = try emit(moves, .gc);
    defer gc.deinit();
    try t.expect(std.mem.indexOf(u8, try named(gc.value, "main"), "%rcstage") == null);
}

