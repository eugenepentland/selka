//! Production scopes and counted scopes obey one journal protocol.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const llvm = @import("qbe_build_llvm.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def snapshot(items: mut list[int]) -> int:
    \\    before = items
    \\    items.append(9)
    \\    return len(before)
    \\def main() -> int:
    \\    items = [1]
    \\    for i in range(3):
    \\        _ = snapshot(mut items)
    \\    return len(items)
;
fn emitted() !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "scope_inline.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
// Every scope branch must consume a w boolean; raw l pointers/counts lose
// their high bits at QBE jnz even when their LLVM translation appears sound.
fn scopeBranchesUseBooleans(il: []const u8) !bool {
    var widths: std.StringHashMapUnmanaged(u8) = .empty;
    defer widths.deinit(t.allocator);
    var lines = std.mem.splitScalar(u8, il, '\n');
    var scope = false;
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " ");
        if (std.mem.indexOf(u8, line, " =")) |equal| {
            if (equal + 2 < line.len) try widths.put(t.allocator, line[0..equal], line[equal + 2]);
        }
        if (std.mem.startsWith(u8, line, "# RC-SCOPE-IL-1 pin") or
            std.mem.startsWith(u8, line, "# RC-SCOPE-IL-1 end")) scope = true;
        if (std.mem.startsWith(u8, line, "@rcspindone") or
            std.mem.startsWith(u8, line, "@rcsenddone")) scope = false;
        if (scope and std.mem.startsWith(u8, line, "jnz ")) {
            const comma = std.mem.indexOfScalar(u8, line, ',') orelse return false;
            if ((widths.get(line[4..comma]) orelse 0) != 'w') return false;
        }
    }
    return true;
}
// spec: RC-SCOPE-IL-1
test "RC-SCOPE-IL-1 production pin journal links before guarded capture and keeps native refusals" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var result = try emitted();
    defer result.deinit();
    const il = try named(result.value, "main");
    const begin = std.mem.indexOf(u8, il, "# RC-SCOPE-IL-1 begin") orelse return error.TestUnexpectedResult;
    const pin = std.mem.indexOf(u8, il, "# RC-SCOPE-IL-1 pin") orelse return error.TestUnexpectedResult;
    try t.expect(begin < pin);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_rc_scope_begin") == null);
    try t.expect(std.mem.indexOf(u8, il, "# RC-SCOPE-IL-1 end") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_rc_scope_pin") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_rc_scope_end") != null);
    try t.expect(std.mem.indexOf(u8, il, "$myl_native_list_header_type") != null);
    try t.expect(std.mem.indexOf(u8, il, "# myl-rc-state") != null);
    try t.expect(try scopeBranchesUseBooleans(il));
    const journal = il[pin..];
    try t.expect(std.mem.indexOf(u8, journal, "=l loadl") != null);
    try t.expect(std.mem.indexOf(u8, journal, "=w cnel") != null);
    try t.expect(std.mem.indexOf(u8, journal, "18446744073709551615") != null);
    try t.expect(std.mem.indexOf(u8, journal, "=l add") != null);
    try t.expect(std.mem.indexOf(u8, journal, "=w cugtl") != null);
}
// spec-case: RC-SCOPE-IL-1
test "RC-SCOPE-IL-1 stats and sites keep native journal event attribution" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc_sites);
    var result = try emitted();
    defer result.deinit();
    const il = try named(result.value, "main");
    try t.expect(std.mem.indexOf(u8, il, "# RC-SCOPE-IL-1") == null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_rc_scope_begin") != null);
    try t.expect(std.mem.indexOf(u8, il, "call $myl_qbe_rc_scope_pin") != null);
    try t.expect(std.mem.indexOf(u8, il, "myl-rcsite") != null);
}
const state_unit =
    \\export function l $myl_f_state(l %ctx, l %a0) {
    \\@start
    \\ %h =l call $myl_qbe_heap(l %ctx)
    \\ %r =l add %h, 5640
    \\ # myl-rc-state %r
    \\ %rc =l loadl %r
    \\ %s =l add %rc, 248
    \\ # myl-rc-state %s
    \\ %p =l loadl %s
    \\ storel %p, %s
    \\ ret %p
    \\}
;
// spec-case: RC-SCOPE-IL-1
test "RC-SCOPE-IL-1 LLVM bookkeeping accesses are apart from guest storage" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const signatures: llvm.Signatures = .empty;
    const table: llvm.RuntimeTable = .{};
    var diagnostic: llvm.Diagnostic = .{ .unit = "state-unit" };
    const ir = try llvm.translate(arena.allocator(), state_unit, .{ .signatures = &signatures, .runtime = &table }, &diagnostic);
    try t.expectEqual(@as(usize, 3), std.mem.count(u8, ir, "!alias.scope !9999998, !noalias !9999999"));
    try t.expect(std.mem.indexOf(u8, ir, "!9999997 = distinct !{!9999997, !0, !\"rc state\"}") != null);
    try t.expect(std.mem.indexOf(u8, ir, "!9999999 = !{!1, !5}") != null);
}

// spec-case: RC-SCOPE-IL-1
test "RC-SCOPE-IL-1 pruning empty GC roots preserves runtime bookkeeping addresses" {
    const input = " %root_mark =l call $myl_qbe_root_mark(l %ctx)\n %root_head =l add %heap, 16\n storel %root_mark, %root_head\n %state =l add %heap, 5640\n %bytes =l add %heap, 24\n %rc =l loadl %state\n";
    const kept = try @import("qbe_il_passes.zig").dropUnusedRoots(t.allocator, input);
    defer t.allocator.free(kept);
    try t.expect(std.mem.indexOf(u8, kept, "%root_head") == null);
    try t.expect(std.mem.indexOf(u8, kept, "add %heap, 5640") != null);
    try t.expect(std.mem.indexOf(u8, kept, "add %heap, 24") != null);
}
