const std = @import("std");
const t = std.testing;
const sites = @import("qbe_rc_sites.zig");
const native = @import("native_types.zig");
const descriptors = @import("native_descriptors.zig");
const typed = @import("typed.zig");

const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };

// spec: RC-SITES-1
test "sites pass names each runtime and glue call by pc, callee and static type" {
    const a = t.allocator;
    const node: typed.Type = @fromBackingInt(typed.Type.record_base);
    const records = [_]typed.Record{.{ .id = node, .name = "Node", .declaration = span, .fields = &.{}, .shape = .{ .domain = .i64 } }};
    var catalog = try native.Catalog.initRecords(a, &records);
    defer catalog.deinit();
    const descriptor = try descriptors.symbol(a, &catalog, node);
    defer a.free(descriptor);
    const text = try std.fmt.allocPrint(a,
        \\export function l $myl_f_u(l %ctx) {{
        \\@entry
        \\ call $myl_qbe_rc_frame_enter(l %ctx, l %f, l %e, l 1)
        \\ %heap =l call $myl_qbe_heap(l %ctx)
        \\@i3
        \\ storel 3, %position
        \\ call ${s}_rcg_loan(l %heap, l %v1, l %v2)
        \\ %v4 =w call $myl_qbe_rc_unique_local(l %ctx, l ${s}, l %v3, l %v5)
        \\ %v6 =l call $myl_f_other(l %ctx)
        \\ call $memset(l %v1, w 0, l 8)
        \\ dbgloc 4
        \\ call $myl_qbe_rc_scope_begin(l %ctx, l %v7)
        \\@failure
        \\ call $myl_qbe_rc_frame_leave(l %ctx, l %f)
        \\ ret 0
        \\}}
    , .{ descriptor, descriptor });
    defer a.free(text);
    const result = try sites.instrument(a, text, .{ .unit = "myl_f_u", .layouts = &catalog });
    defer a.free(result.text);
    defer a.free(result.markers);
    const il = result.text;
    // Five sites: the prologue's journal entry, the loan, the uniqueness
    // check, the scope and the exit's journal exit. Guest calls, libc and the
    // heap-pointer helper name none.
    try t.expectEqual(@as(usize, 5), std.mem.count(u8, result.markers, "# myl-rcsite "));
    try t.expect(std.mem.indexOf(u8, result.markers, "# myl-rcsite myl_f_u_rcsite0 myl_f_u entry myl_qbe_rc_frame_enter -\n") != null);
    try t.expect(std.mem.indexOf(u8, result.markers, "# myl-rcsite myl_f_u_rcsite1 myl_f_u 3 rcg_loan 4e6f6465\n") != null);
    try t.expect(std.mem.indexOf(u8, result.markers, "# myl-rcsite myl_f_u_rcsite2 myl_f_u 3 myl_qbe_rc_unique_local 4e6f6465\n") != null);
    try t.expect(std.mem.indexOf(u8, result.markers, "# myl-rcsite myl_f_u_rcsite3 myl_f_u 3 myl_qbe_rc_scope_begin -\n") != null);
    try t.expect(std.mem.indexOf(u8, result.markers, "# myl-rcsite myl_f_u_rcsite4 myl_f_u exit myl_qbe_rc_frame_leave -\n") != null);
    // Each site bumps its call count and becomes current right before its call.
    try t.expect(std.mem.indexOf(u8, il, " %rcsite1 =l loadl $myl_f_u_rcsite1\n %rcsite1n =l add %rcsite1, 1\n storel %rcsite1n, $myl_f_u_rcsite1\n storel $myl_f_u_rcsite1, $myl_rc_site_current\n call $myl_t_") != null);
    // A call's own `dbgloc` stays right in front of it.
    try t.expect(std.mem.indexOf(u8, il, "storel $myl_f_u_rcsite3, $myl_rc_site_current\n dbgloc 4\n call $myl_qbe_rc_scope_begin") != null);
    try t.expect(std.mem.indexOf(u8, il, "rcsite\n %heap") == null);
    try t.expectEqual(@as(usize, 5), std.mem.count(u8, il, "$myl_rc_site_current"));
    // The markers follow every other pass, after the function.
    const whole = try sites.append(a, il, result.markers);
    defer a.free(whole);
    const tail = try std.mem.concat(a, u8, &.{ "}\n", result.markers });
    defer a.free(tail);
    try t.expect(std.mem.endsWith(u8, whole, tail));
    try t.expect(std.mem.startsWith(u8, result.markers, "# myl-rcsite myl_f_u_rcsite0 "));
}

// spec-case: RC-SITES-1
test "sites pass leaves a function without runtime calls unchanged" {
    const a = t.allocator;
    var catalog = try native.Catalog.initRecords(a, &.{});
    defer catalog.deinit();
    const text = "export function l $myl_f_u(l %ctx) {\n@entry\n %v1 =l call $myl_f_other(l %ctx)\n ret %v1\n}";
    const result = try sites.instrument(a, text, .{ .unit = "myl_f_u", .layouts = &catalog });
    defer a.free(result.text);
    defer a.free(result.markers);
    try t.expectEqualStrings(text, result.text);
    try t.expectEqual(@as(usize, 0), result.markers.len);
    const whole = try sites.append(a, result.text, result.markers);
    defer a.free(whole);
    try t.expectEqualStrings(text, whole);
}
