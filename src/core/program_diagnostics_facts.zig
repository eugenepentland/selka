//! The diagnostics of a whole program, as the `program-diagnostics` kind states them (spec §17.2): the text `check` prints, and the
//! `module-passes` arguments of the modules it is assembled from, in module order.
const std = @import("std");
const language = @import("selka");
const digest_rules = @import("engine/digest.zig");
const record = @import("engine/record.zig");
const program_kind = @import("engine/kinds/program_diagnostics.zig");
const graph_answer = @import("project_graph_answer.zig");
const passes_facts = @import("module_passes_facts.zig");
const noalloc_facts = @import("noalloc_closure_facts.zig");

/// The first line of the payload.
pub const payload_magic = "selka-program-diagnostics-v1";
/// The domain string of the rendered part's digest.
const domain = "selka-program-diagnostics-part-v1";

/// What the program's diagnostics are rendered under: the front end's settings and the format its command asked for.
pub const Settings = struct { options: language.project.Options, format: language.diagnostic_output.Format };

/// The query argument of the program entered at `entry`: `project-graph`'s.
pub fn argumentOf(a: std.mem.Allocator, entry: []const u8, options: language.project.Options) std.mem.Allocator.Error![]const u8 {
    return graph_answer.argumentOf(a, entry, options);
}

/// The rendered diagnostics `items` of the program over `src`, one after another, as the command prints its warnings. Rendering
/// does not note them in the friction log.
pub fn render(a: std.mem.Allocator, src: language.source.Source, items: []const language.diagnostic.Diagnostic, format: language.diagnostic_output.Format) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (items) |item| try out.appendSlice(a, try language.diagnostic_output.render(a, item, src, format));
    return out.items;
}

/// The program's answer for the modules `passes` (in module order) and the generic `@noalloc` functions instantiated in it (`roots`),
/// or null when a module or an instance's promise is not recorded: the assembly would read a part that does not exist.
pub fn compute(a: std.mem.Allocator, rendered: []const u8, passes: []const passes_facts.Passes, roots: []const noalloc_facts.Root) std.mem.Allocator.Error!?program_kind.Answer {
    const modules = try a.alloc([]const u8, passes.len);
    for (passes, modules) |module, *slot| {
        if (module.answer == null) return null;
        slot.* = module.argument;
    }
    var instances: std.ArrayList([]const u8) = .empty;
    for (roots) |root| {
        if (root.module.len == 0) return null;
        if (!root.instance) continue;
        if (root.answer == null) return null;
        try instances.append(a, root.argument);
    }
    var state = std.crypto.hash.Blake3.init(.{});
    state.update(domain);
    state.update("\x00");
    state.update(rendered);
    var digest: [32]u8 = undefined;
    state.final(&digest);
    const parts = try a.dupe(record.Part, &.{.{ .name = "rendered", .digest = digest }});
    const payload = try std.fmt.allocPrint(a, "{s}\n{s}", .{ payload_magic, rendered });
    return .{ .payload = payload, .parts = parts, .modules = modules, .noalloc = instances.items };
}

test "a program with an unrecorded module has no answer, and the digest follows the text" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const recorded: passes_facts.Passes = .{ .argument = "a.selka", .answer = .{ .payload = "", .parts = &.{}, .bodies = &.{}, .texts = &.{} } };
    const missing: passes_facts.Passes = .{ .argument = "b.selka", .answer = null };
    try std.testing.expectEqual(@as(?program_kind.Answer, null), try compute(a, "text", &.{ recorded, missing }, &.{}));
    const first = (try compute(a, "one", &.{recorded}, &.{})).?;
    const second = (try compute(a, "two", &.{recorded}, &.{})).?;
    try std.testing.expect(!std.mem.eql(u8, &first.parts[0].digest, &second.parts[0].digest));
    try std.testing.expectEqualStrings("a.selka", first.modules[0]);
    try std.testing.expect(std.mem.startsWith(u8, first.payload, payload_magic));
    _ = digest_rules;
}
