//! F19: a `@noalloc` promise is judged on the body a build emits.
//!
//! The check once lowered a promised function as a root (owned `str` parameters) while the build lowers it as a
//! callee (borrowed views), so it judged a different body. These tests pin the verdicts on the callee body, and
//! that no later transformation, in any of the build's pass modes, gives a function an allocation its debug body
//! (the body the check judged) does not reach.
const std = @import("std");
const language = @import("selka");
const ir = @import("ir.zig");
const build = @import("build.zig");
const cost = @import("cost.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const contracts = @import("allocation_contract.zig");
const span_forms = @import("span_forms.zig");

const fixture = @embedFile("noalloc_built_body_fixture.selka");

/// The build's pass modes: `null` is the debug pipeline (ownership only), then `--unoptimized`, the verified
/// optimizer and the trusted one that `--optimize-debug` and `--release` run.
const stages = [_]?passes.Mode{ null, .off, .verify, .trusted };

/// Promises over the three text predicates and `ord` (F20). Each reads a borrowed text through a runtime helper that
/// has a span form, so the body a build emits over a view copies nothing. Before F20 the helpers took a block, and
/// the build copied the view twice per call.
const text_promises =
    \\import strings
    \\
    \\@noalloc
    \\func digits(text: str) -> bool:
    \\    return strings.is_digit(text)
    \\
    \\@noalloc
    \\func letters(text: str) -> bool:
    \\    return strings.is_alpha(text)
    \\
    \\@noalloc
    \\func spaces(text: str) -> bool:
    \\    return strings.is_space(text)
    \\
    \\@noalloc
    \\func code(text: str) -> int:
    \\    return ord(text)
    \\
    \\func main(out: Stream) -> int:
    \\    if digits("123") and letters("abc") and spaces(" ") and code("a") == 97:
    \\        print(out, 1)
    \\    return 0
;

/// The promised functions of `text_promises`.
const promised_names = [_][]const u8{ "digits", "letters", "spaces", "code" };

const Built = struct { module: ir.Module, result: passes.Result };

/// The module a build rooted at `main` emits in `stage`, as `pipeline.emittedCached` runs its passes.
fn emitted(a: std.mem.Allocator, checked: support.Checked, stage: ?passes.Mode) !Built {
    var refusal: build.Refusal = .{};
    var module = try build.buildExecutable(a, .{ .program = checked.program.?, .source = checked.src }, &refusal);
    const result = if (stage) |mode| try passes.run(a, &module, mode) else try passes.debug(a, &module);
    return .{ .module = module, .result = result };
}

/// Whether each function of `module` reaches an allocation site through its own body or an internal callee.
fn reaching(a: std.mem.Allocator, module: *const ir.Module) ![]bool {
    const reached = try a.alloc(bool, module.functions.items.len);
    for (reached, module.functions.items, 0..) |*slot, function, index| {
        slot.* = function.signature.linkage == .internal and (try contracts.witness(a, module, index)) != null;
    }
    return reached;
}

fn indexOf(module: *const ir.Module, name: []const u8) ?usize {
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return index;
    }
    return null;
}

/// The index in `module` of the function whose name ends in `name` (a project names its functions by module).
fn named(module: *const ir.Module, name: []const u8) ?usize {
    for (module.functions.items, 0..) |function, index| {
        if (std.mem.endsWith(u8, function.name, name)) return index;
    }
    return null;
}

/// The name of the first function of `after` that reaches an allocation although its namesake in `before` does not.
fn firstNewAllocation(a: std.mem.Allocator, before: *const ir.Module, after: *const ir.Module) !?[]const u8 {
    const was = try reaching(a, before);
    const is = try reaching(a, after);
    for (is, after.functions.items) |reached, function| {
        if (!reached) continue;
        const twin = indexOf(before, function.name) orelse return function.name;
        if (!was[twin]) return function.name;
    }
    return null;
}

/// Every function of `stage`'s module that reaches an allocation also reaches one in the debug module.
fn expectNoNewAllocation(a: std.mem.Allocator, checked: support.Checked, stage: ?passes.Mode) !void {
    const debug = try emitted(a, checked, null);
    const later = try emitted(a, checked, stage);
    // A failure prints the name of the function a pass gave an allocation.
    try std.testing.expectEqual(@as(?[]const u8, null), try firstNewAllocation(a, &debug.module, &later.module));
}

/// Every function carrying a `@noalloc` promise reaches no allocation in `stage`'s module.
fn expectPromisesHold(a: std.mem.Allocator, checked: support.Checked, stage: ?passes.Mode) !void {
    const built = try emitted(a, checked, stage);
    var kept: usize = 0;
    for (checked.program.?.functions) |function| {
        if (function.policy.noalloc == null) continue;
        const index = named(&built.module, function.name).?;
        kept += 1;
        try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.witness(a, &built.module, index));
    }
    try std.testing.expect(kept >= 10);
}

fn checkedFixture(a: std.mem.Allocator) !support.Checked {
    const checked = try support.checkSource(a, fixture);
    try std.testing.expect(checked.passed);
    return checked;
}

test "the check accepts the promises of the fixture, whose bodies the build emits without an allocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try checkedFixture(a);
    const failures = try contracts.collectProgram(a, checked.program.?, checked.src.?);
    try std.testing.expectEqual(@as(usize, 0), failures.len);
}

test "every promise of the fixture holds in the module each pass mode emits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try checkedFixture(a);
    try expectPromisesHold(a, checked, stages[0]);
    try expectPromisesHold(a, checked, stages[1]);
    try expectPromisesHold(a, checked, stages[2]);
    try expectPromisesHold(a, checked, stages[3]);
}

test "no pass mode gives a function an allocation its debug body does not reach" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try checkedFixture(a);
    try expectNoNewAllocation(a, checked, stages[1]);
    try expectNoNewAllocation(a, checked, stages[2]);
    try expectNoNewAllocation(a, checked, stages[3]);
}

test "the comparison names a function a pass gave an allocation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try checkedFixture(a);
    const debug = try emitted(a, checked, null);
    var later = try emitted(a, checked, null);
    try std.testing.expectEqual(@as(?[]const u8, null), try firstNewAllocation(a, &debug.module, &later.module));
    // A buffer allocated at the start of `text_length`, as a pass that added one would leave it.
    const index = named(&later.module, "text_length").?;
    const function = &later.module.functions.items[index];
    const added: ir.Ref = @fromBackingInt(@intCast(function.insts.items.len));
    try function.insts.append(a, .{ .op = .buffer_new, .ty = .void });
    try function.blocks.items[0].insts.insert(a, 0, added);
    const offender = (try firstNewAllocation(a, &debug.module, &later.module)).?;
    try std.testing.expect(std.mem.endsWith(u8, offender, "text_length"));
}

test "the fixture makes each release transformation act, so the comparison above is not vacuous" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try checkedFixture(a);
    const unoptimized = (try emitted(a, checked, .off)).result;
    const verified = (try emitted(a, checked, .verify)).result;
    const trusted = (try emitted(a, checked, .trusted)).result;
    try std.testing.expect(unoptimized.counts.inlined > 0);
    try std.testing.expect(verified.counts.unswitched > 0);
    try std.testing.expect(verified.counts.versioned > 0);
    try std.testing.expect(trusted.counts.vectorized > 0);
    try std.testing.expect(trusted.own.promoted > 0);
    try std.testing.expect(trusted.own.in_place > 0);
    try std.testing.expect(trusted.counts.proven > 0);
}

/// Each promised function of `text_promises` reaches no allocation in `stage`'s module, which calls the span forms
/// and declares neither block form.
fn expectTextPromisesHold(a: std.mem.Allocator, checked: support.Checked, stage: ?passes.Mode) !void {
    const built = try emitted(a, checked, stage);
    for (promised_names) |name| {
        try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.witness(a, &built.module, named(&built.module, name).?));
    }
    try std.testing.expect(indexOf(&built.module, "myl_core_span_text_every") != null);
    try std.testing.expect(indexOf(&built.module, "myl_core_span_text_ord") != null);
    try std.testing.expectEqual(@as(?usize, null), indexOf(&built.module, "myl_core_text_every"));
    try std.testing.expectEqual(@as(?usize, null), indexOf(&built.module, "myl_core_text_ord"));
}

test "the text predicates and ord keep a promise over a borrowed view in every pass mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try support.checkSource(a, text_promises);
    try std.testing.expect(checked.passed);
    // The check judges the body the build emits, and accepts all four.
    try std.testing.expectEqual(@as(usize, 0), (try contracts.collectProgram(a, checked.program.?, checked.src.?)).len);
    try expectTextPromisesHold(a, checked, stages[0]);
    try expectTextPromisesHold(a, checked, stages[1]);
    try expectTextPromisesHold(a, checked, stages[2]);
    try expectTextPromisesHold(a, checked, stages[3]);
}

test "a promise whose built body copies a borrowed view is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const checked = try support.checkSource(a, text_promises);
    try std.testing.expect(checked.passed);
    const program = checked.program.?;
    var built = try emitted(a, checked, null);
    // As built, nothing copies the view, and the check accepts every promise.
    try std.testing.expectEqual(@as(?contracts.Violation, null), try contracts.validate(a, program, checked.src.?, &built.module));
    // Inject the lowering of the predicates before F20: the view parameter copied to an owned text at the call. No
    // helper of the language copies a view that way now, so this keeps the check's refusal path covered.
    const index = named(&built.module, "digits").?;
    const function = &built.module.functions.items[index];
    const view = param: {
        for (function.insts.items, 0..) |inst, at| {
            if (inst.op == .param) break :param @as(ir.Ref, @fromBackingInt(@intCast(at)));
        }
        return error.TestUnexpectedResult;
    };
    const copy: ir.Ref = @fromBackingInt(@intCast(function.insts.items.len));
    try function.insts.append(a, .{ .op = .str_from_view, .ty = .str, .a = view });
    try function.blocks.items[0].insts.append(a, copy);
    try std.testing.expect((try contracts.witness(a, &built.module, index)) != null);
    // The offender is the promised function, and no other.
    const refused = (try contracts.validate(a, program, checked.src.?, &built.module)).?;
    try std.testing.expect(std.mem.endsWith(u8, refused.function, "digits"));
    try std.testing.expect(!refused.unresolved);
}

test "a library is judged like a program: its first function is no entry, and a promised main is a callee" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A library has no entry; the checker's placeholder for it is function 0, which here carries a promise over a `str`.
    var library = try language.Compilation.init(a, "library.selka", "@noalloc\nfunc first(text: str, index: int) -> int:\n    return text[index]\n");
    const library_program = try library.checkLibraryProgram();
    try std.testing.expectEqual(@as(usize, 0), (try contracts.collectProgram(a, library_program, library.src)).len);
    // The source `main` is called by the entry wrapper, so it runs over a borrowed `args` too.
    var entry = try language.Compilation.init(a, "entry.selka", "@noalloc\nfunc main(args: str[]) -> int:\n    return len(args[0])\n");
    try entry.check();
    try std.testing.expectEqual(@as(usize, 0), (try contracts.collectProgram(a, entry.program.?, entry.src)).len);
}

test "a span form is allocation-free exactly when its text form is" {
    try expectFormsAgree();
    // The helpers the built body of a bytes or text parameter calls (`selka cost` showed each as an unresolved site).
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_bytes_index_offset"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_bytes_find"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_bytes_search"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_bytes_find_any"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_bytes_contains_value"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_utf8_count"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_bytes_utf8_count_range"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_parse_f32_range"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_buffer_range_valid"));
    // The span forms the list named before this table: still allocation-free.
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_eq"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_starts"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_parse_int_range"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_split_ws_start"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_text_trim_view"));
    // The text predicates' and `ord`'s span forms (F20), derived from the block forms they replace on a view.
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_text_every"));
    try std.testing.expect(cost.runtimeAllocationFree("myl_core_span_text_ord"));
    try std.testing.expectEqualStrings("myl_core_text_every", span_forms.textForm("myl_core_span_text_every").?);
    try std.testing.expectEqualStrings("myl_core_text_ord", span_forms.textForm("myl_core_span_text_ord").?);
    // A span form whose text form allocates, or that has none, stays unlisted.
    try std.testing.expect(!cost.runtimeAllocationFree("myl_core_span_bytes_trim"));
    try std.testing.expect(!cost.runtimeAllocationFree("myl_core_span_encode"));
    try std.testing.expect(!cost.runtimeAllocationFree("myl_core_span_future_helper"));
}

fn expectFormsAgree() !void {
    for (span_forms.redirects) |form| {
        try std.testing.expectEqual(cost.runtimeAllocationFree(form.text), cost.runtimeAllocationFree(form.span));
    }
    for (span_forms.direct) |form| {
        try std.testing.expectEqual(cost.runtimeAllocationFree(form.text), cost.runtimeAllocationFree(form.span));
    }
}

/// The runtime sources, whole: every `myl_core_span_` name they mention is a span helper a lowered body can call.
const runtime_sources = [_][]const u8{
    @embedFile("runtime/core_text.c"),          @embedFile("runtime/core_bytes.c"),   @embedFile("runtime/core_number.c"),
    @embedFile("runtime/core_values.c"),        @embedFile("runtime/core_io.c"),      @embedFile("runtime/core_dict.c"),
    @embedFile("runtime/core_input.c"),         @embedFile("runtime/core_durable.c"), @embedFile("runtime/core_process.c"),
    @embedFile("runtime/core_number_text.zig"),
};

/// Whether `name` is a span form `span_forms` pairs with a text form, or is listed as having none.
fn classified(name: []const u8) bool {
    for (span_forms.redirects) |form| if (std.mem.eql(u8, form.span, name)) return true;
    for (span_forms.direct) |form| if (std.mem.eql(u8, form.span, name)) return true;
    for (span_forms.other) |other| if (std.mem.eql(u8, other, name)) return true;
    return false;
}

/// The first `myl_core_span_` name in `text` that is not classified.
fn firstUnclassified(text: []const u8) ?[]const u8 {
    const prefix = "myl_core_span_";
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, text, at, prefix)) |start| {
        var end = start + prefix.len;
        while (end < text.len and (std.ascii.isLower(text[end]) or std.ascii.isDigit(text[end]) or text[end] == '_')) end += 1;
        if (!classified(text[start..end])) return text[start..end];
        at = end;
    }
    return null;
}

/// No runtime source names a `myl_core_span_` helper that `span_forms` does not know; a failure prints the name.
fn expectAllClassified() !void {
    for (runtime_sources) |text| try std.testing.expectEqual(@as(?[]const u8, null), firstUnclassified(text));
}

test "every span helper the runtime defines is classified beside its text form" {
    try expectAllClassified();
}
