//! Read-only versions retain live journals and the original checked fallback.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const proof = @import("qbe_rc_read_version.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };
const source =
    \\def fold(items: list[int]) -> int:
    \\    total = 0
    \\    for item in items:
    \\        total += item
    \\    return total
    \\def fresh() -> int:
    \\    total = 0
    \\    for item in [1, 2, 3, 4]:
    \\        total += item
    \\    return total
    \\def changed(items: mut list[int]) -> int:
    \\    total = 0
    \\    for item in items:
    \\        items.append(item)
    \\        total += item
    \\    return total
    \\def callback(out: Stream, items: list[int]) -> int:
    \\    total = 0
    \\    for item in items:
    \\        out.print(item)
    \\        total += item
    \\    return total
    \\def managed(items: list[list[int]]) -> int:
    \\    total = 0
    \\    for item in items:
    \\        total += len(item)
    \\    return total
    \\def main() -> int:
    \\    return fresh() + fold([5, 6, 7])
;

fn emitted(steps: bool) !std.json.Parsed(Manifest) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_read_version.my", source);
    defer compilation.deinit();
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = steps, .frame_checks = false });
    defer t.allocator.free(text);
    return std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}
fn guarded(text: []const u8) !void {
    const mark = std.mem.indexOf(u8, text, "# RC-READ-LIST-VERSION-1") orelse return error.TestUnexpectedResult;
    const tail = text[mark..];
    try t.expect(std.mem.indexOf(u8, tail, ", 2\n") != null);
    try t.expect(std.mem.indexOf(u8, tail, ", 8\n") != null);
    try t.expect(std.mem.indexOf(u8, tail, "@rcreadloop") != null);
    try t.expect(std.mem.indexOf(u8, tail, "@oi") != null);
    try t.expect(std.mem.indexOf(u8, tail, "\n@fi") != null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_rc_hold_acquire") != null);
    try t.expect(std.mem.indexOf(u8, text, "# rc-exit") != null);
}

// spec: RC-READ-LIST-VERSION-1
test "RC read list versions guard existing held tokens and keep original cleanup" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var manifest = try emitted(false);
    defer manifest.deinit();
    try guarded(try named(manifest.value, "fold"));
    try guarded(try named(manifest.value, "fresh"));
}

// spec-case: RC-READ-LIST-VERSION-1
test "RC read list versions refuse mutation callbacks managed elements and step accounting" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var fast = try emitted(false);
    defer fast.deinit();
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "changed"), "RC-READ-LIST-VERSION-1") == null);
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "callback"), "RC-READ-LIST-VERSION-1") == null);
    try t.expect(std.mem.indexOf(u8, try named(fast.value, "managed"), "RC-READ-LIST-VERSION-1") == null);
    var accounted = try emitted(true);
    defer accounted.deinit();
    try t.expect(std.mem.indexOf(u8, try named(accounted.value, "fold"), "RC-READ-LIST-VERSION-1") == null);
}

// spec-case: RC-READ-LIST-VERSION-1
test "RC read list versions reject generated cleanup calls and bound text scanning" {
    try t.expect(proof.quietCopy(" %v0 =l add %v1, 1\n call $myl_qbe_fail_overflow(l %ctx)\n"));
    try t.expect(!proof.quietCopy(" call $myl_native_owned_drop(l %heap, l %value)\n"));
    try t.expect(!proof.quietCopy(" call $memset(l %value, w 0, l 8)\n"));
    try t.expect(!proof.quietCopy(" %v0 =l call %v1()\n"));
    const large = try t.allocator.alloc(u8, 1024 * 1024 + 1);
    defer t.allocator.free(large);
    @memset(large, ' ');
    try t.expect(!proof.quietCopy(large));
}

// spec-case: RC-READ-LIST-VERSION-1
test "RC read list versions route an external backward head entry through the real guard" {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    const reentry =
        \\def reenter(items: list[int], again: bool) -> int:
        \\    total = 0
        \\    for item in items:
        \\        total += item
        \\    if again:
        \\        return 99
        \\    return total
        \\def main() -> int:
        \\    return reenter([1, 2], False)
    ;
    var compilation = try compiler.Compilation.init(t.allocator, "external_read_loop.my", reentry);
    defer compilation.deinit();
    try compilation.emit();
    const code = @constCast(compilation.code.?.functions[0].scope.instructions);
    const route = try externalHead(code);
    const text = try compilation.emitQbeWithOptions(t.allocator, .{ .step_checks = false, .frame_checks = false });
    defer t.allocator.free(text);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, text, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
    defer manifest.deinit();
    const il = try named(manifest.value, "reenter");
    try guarded(il);
    try t.expect(route.external > route.back);
    // The comparison and conditional may fuse, so inspect the actual target
    // rather than requiring a separate bytecode-PC label for the branch.
    const target = try std.fmt.allocPrint(t.allocator, ", @i{d}\n", .{route.head});
    defer t.allocator.free(target);
    const external_jump = std.mem.lastIndexOf(u8, il, target) orelse return error.TestUnexpectedResult;
    const original_head = try std.fmt.allocPrint(t.allocator, "\n@oi{d}\n", .{route.head});
    defer t.allocator.free(original_head);
    try t.expect(external_jump > (std.mem.indexOf(u8, il, original_head) orelse return error.TestUnexpectedResult));
    const fast = try std.fmt.allocPrint(t.allocator, "jmp @fi{d}\n", .{route.head});
    defer t.allocator.free(fast);
    const original = try std.fmt.allocPrint(t.allocator, "jmp @oi{d}\n", .{route.head});
    defer t.allocator.free(original);
    try t.expect(std.mem.indexOf(u8, il, fast) != null);
    try t.expect(std.mem.indexOf(u8, il, original) != null);
}

fn externalHead(code: []@import("bytecode.zig").Instruction) !struct { head: usize, back: usize, external: usize } {
    var head: ?usize = null;
    var back: usize = 0;
    for (code, 0..) |instruction, pc| {
        if (instruction.op == .jump and instruction.op.jump < pc) {
            head = instruction.op.jump;
            back = pc;
            break;
        }
    }
    var external: ?usize = null;
    for (code[back + 1 ..], back + 1..) |*instruction, pc| {
        if (instruction.op == .jump_if_false) {
            instruction.op.jump_if_false = @intCast(head orelse return error.TestUnexpectedResult);
            external = pc;
            break;
        }
    }
    return .{ .head = head orelse return error.TestUnexpectedResult, .back = back, .external = external orelse return error.TestUnexpectedResult };
}
