//! `byte_format.format` and its text-taking forms treat a template that does not fit its arguments as a mistake in the program: they
//! trap `R_ASSERT` and the report names the octet and the reason. The accepted templates and the Zig-exact numbers are tested in
//! tests/lang/byte_format_templates.selka.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");

/// Run a program that formats `template` with the arguments in `call` and require the `R_ASSERT` trap whose report holds `reason`.
fn faults(call: []const u8, reason: []const u8) !void {
    const source = try std.fmt.allocPrint(t.allocator, "import byte_builder\nimport byte_format\nfunc main() -> int:\n    mut out = byte_builder.create()\n    {s}\n    return len(byte_builder.finish(out))\n", .{call});
    defer t.allocator.free(source);
    var program: language.embedded_project.Program = undefined;
    try fixture.load(&program, t.allocator, source);
    defer program.deinit();
    const outcome = try native.runWithOptions(&program.compilation, .{});
    try t.expect(outcome.trapped());
    try t.expectEqualStrings("R_ASSERT", outcome.trap.code);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, reason) != null);
}

test "a template that does not fit its arguments traps R_ASSERT naming the octet and the reason" {
    try faults("byte_format.format(mut out, b\"a {d} b {d}\", [1.0])", "more `{d}` than numbers, at octet 8 of the template");
    try faults("byte_format.format(mut out, b\"a {d}\", [1.0, 2.0])", "more numbers than `{d}` placeholders, at octet 5");
    try faults("byte_format.format(mut out, b\"a {s}\", [])", "more `{s}` than texts, at octet 2");
    try faults("byte_format.format1(mut out, b\"a\", [], b\"x\")", "more texts than `{s}` placeholders, at octet 1");
    try faults("byte_format.format(mut out, b\"{d:.}\", [1.0])", "a placeholder is `{d}`, `{d:.N}` with N in 0 to 17, or `{s}`, at octet 0");
    try faults("byte_format.format(mut out, b\"{d:.18}\", [1.0])", "a placeholder is `{d}`, `{d:.N}` with N in 0 to 17, or `{s}`");
    try faults("byte_format.format(mut out, b\"{x}\", [])", "a placeholder is `{d}`, `{d:.N}` with N in 0 to 17, or `{s}`");
    try faults("byte_format.format(mut out, b\"abc {d\", [1.0])", "a `{` with no closing `}`, at octet 4");
    try faults("byte_format.format(mut out, b\"abc }\", [])", "a lone `}`; write `}}` for a brace, at octet 4");
}

test "a template fault is a trap, but a well-formed template with every argument used runs to completion" {
    try fixture.run(t.allocator,
        \\import byte_builder
        \\import byte_format
        \\func main() -> int:
        \\    mut out = byte_builder.create()
        \\    byte_format.format2(mut out, b"{s}{d:.1}{s}", [1.25], b"<", b">")
        \\    return len(byte_builder.finish(out)) + 38
    , 43);
}
