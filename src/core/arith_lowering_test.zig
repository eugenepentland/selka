//! Pins `emit_llvm.zig` to the arithmetic lowerings proved in `proofs/arith` (package C8 of
//! docs/audits/ownership-certificates-plan-2026-10-26.md).
//!
//! `proofs/arith/templates.txt` is the LLVM text the Lean formulas of `proofs/arith/Arith/Formulas.lean`
//! render to (`lake exe arith-templates`), one case per operation, type and check mode, and the gate
//! action `arith-proof` fails when the file is not what Lean renders. This test builds one tiny
//! function per case as Core IR, emits LLVM, reduces the function's text to the template's shape and
//! requires the two to be equal. The reduction is structural, not a byte golden: registers are
//! renamed `a`, `b` and `t1`, `t2`, ... in order of definition, the cold trap block of each check
//! becomes one `trapif <condition> <kind>` line (the kind is read from the trap site's table entry),
//! and the widening casts that only feed a trap's diagnostic operands are dropped.
//!
//! A second test compiles one tiny program, a function per operation and type (168: the language
//! operators `//`, `%`, `divtrunc`, `remtrunc`, `shift_left`, `shift_right`, `saturating_add`, a cast
//! between every pair of integer types, a cast from a float), through the whole front end and the
//! debug pipeline, and compares each function with the same templates, so the check modes the builder
//! chooses (a widening cast carries no check, a constant divisor skips the tests it rules out) are
//! pinned too. The forms the fact pass chooses (`proven`, `narrow`) have no source spelling and are
//! built by hand in the first test.
//!
//! A case the template file lacks, or a template no case builds, fails the test, so a new width or
//! mode in either place is noticed.
const std = @import("std");
const ir = @import("ir.zig");
const emit_llvm = @import("emit_llvm.zig");
const facts = @import("facts.zig");
const support = @import("test_support.zig");

/// Where the Lean-rendered templates live, relative to the repository root.
const templates_path = "proofs/arith/templates.txt";

/// One case of the template file: its id and its normalized instruction lines.
const Template = struct { id: []const u8, body: []const u8 };

/// What one case builds: the operation, its operand type, its result type and the check mode.
const Spec = struct {
    op: ir.Op,
    ty: ir.Type,
    result: ir.Type,
    mode: []const u8,
};

/// The language type with the name `text` (`i8` ... `u64`), or null.
fn typeNamed(text: []const u8) ?ir.Type {
    const names = [_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" };
    const types = [_]ir.Type{ .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 };
    for (names, types) |name, ty| if (std.mem.eql(u8, name, text)) return ty;
    return null;
}

/// The Core operation named `text`, or null.
fn opNamed(text: []const u8) ?ir.Op {
    const names = [_][]const u8{ "div", "rem", "floor_div", "floor_rem", "shift_left", "shift_right", "saturating_add", "convert", "float_to_int" };
    const ops = [_]ir.Op{ .div, .rem, .floor_div, .floor_rem, .shift_left, .shift_right, .saturating_add, .convert, .float_to_int };
    for (names, ops) |name, op| if (std.mem.eql(u8, name, text)) return op;
    return null;
}

/// Read a case id (`floor_div.i32.exact`, `convert.i64.u8.none`, `saturating_add.i16`).
fn specOf(id: []const u8) ?Spec {
    var parts = std.mem.splitScalar(u8, id, '.');
    const op = opNamed(parts.next() orelse return null) orelse return null;
    const first = typeNamed(parts.next() orelse return null) orelse return null;
    if (op == .saturating_add) return .{ .op = op, .ty = first, .result = first, .mode = "" };
    if (op == .convert) {
        const to = typeNamed(parts.next() orelse return null) orelse return null;
        return .{ .op = op, .ty = first, .result = to, .mode = parts.next() orelse return null };
    }
    const mode = parts.next() orelse return null;
    if (op == .float_to_int) return .{ .op = op, .ty = .f64, .result = first, .mode = mode };
    return .{ .op = op, .ty = first, .result = first, .mode = mode };
}

/// Split the template file into its cases.
fn parseTemplates(arena: std.mem.Allocator, text: []const u8) ![]Template {
    var list: std.ArrayList(Template) = .empty;
    var lines = std.mem.splitScalar(u8, text, '\n');
    var current: ?[]const u8 = null;
    var body: std.ArrayList(u8) = .empty;
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "case ")) {
            current = line["case ".len..];
            body.clearRetainingCapacity();
        } else if (std.mem.eql(u8, line, "end")) {
            try list.append(arena, .{ .id = current orelse return error.BadTemplates, .body = try arena.dupe(u8, body.items) });
            current = null;
        } else if (current != null) {
            try body.appendSlice(arena, line);
            try body.append(arena, '\n');
        }
    }
    return list.items;
}

/// Whether `mode` is one of `names`.
fn modeIs(mode: []const u8, names: []const []const u8) bool {
    for (names) |name| if (std.mem.eql(u8, mode, name)) return true;
    return false;
}

/// The check an instruction of `mode` carries.
fn checkOf(mode: []const u8) ir.Check {
    if (modeIs(mode, &.{ "exact", "const", "const-1", "narrow", "narrow-const" })) return .exact;
    if (modeIs(mode, &.{ "none", "" })) return .none;
    return .proven;
}

/// What a built case needs to be emitted.
const Built = struct {
    module: ir.Module,
    analysis: emit_llvm.Analysis,
    verify: bool,
};

/// Facts for function 1 (the function under test) that put the listed instructions in `[lo, hi]`.
fn factsFor(arena: std.mem.Allocator, function: *const ir.Function, refs: []const ir.Ref, range: facts.Interval) !facts.Facts {
    const n = function.insts.items.len;
    const known: facts.Facts = .{
        .ranges = try arena.alloc(?facts.Interval, n),
        .aggregates = .{
            .lists = try arena.alloc(facts.ListFact, n),
            .dicts = try arena.alloc(facts.DictFact, n),
            .fields = try arena.alloc(?[]const ?facts.Interval, n),
        },
        .floats = try arena.alloc(?facts.FloatInterval, n),
        .reachable = try arena.alloc(bool, function.blocks.items.len),
    };
    @memset(known.ranges, null);
    @memset(known.aggregates.lists, .{});
    @memset(known.aggregates.dicts, .{});
    @memset(known.aggregates.fields, null);
    @memset(known.floats, null);
    @memset(known.reachable, true);
    for (refs) |ref| known.ranges[ref.index()] = range;
    return known;
}

/// The constant a `const` mode divides by.
fn constantFor(mode: []const u8) i64 {
    return if (std.mem.eql(u8, mode, "const-1")) -1 else 7;
}

/// How many operands the function under test takes and whether the second is a constant.
const Shape = struct { unary: bool, constant: bool };

fn shapeOf(spec: Spec) Shape {
    return .{
        .unary = spec.op == .convert or spec.op == .float_to_int,
        .constant = std.mem.startsWith(u8, spec.mode, "const") or std.mem.eql(u8, spec.mode, "narrow-const"),
    };
}

/// Whether the emitter chooses this case's form from the facts' ranges (the `u32`-operand 64-bit
/// division and the `i32`-result 64-bit float conversion).
fn needsFacts(mode: []const u8) bool {
    return std.mem.startsWith(u8, mode, "narrow") or std.mem.eql(u8, mode, "proven-narrow");
}

/// The parameter types of the function under test.
fn parameterTypes(arena: std.mem.Allocator, spec: Spec, shape: Shape) ![]const ir.Type {
    if (shape.unary or shape.constant) return arena.dupe(ir.Type, &.{spec.ty});
    return arena.dupe(ir.Type, &.{ spec.ty, spec.ty });
}

/// Build the entry `main` (function 0); it does not call the function under test, which is function 1.
fn addEntry(arena: std.mem.Allocator, module: *ir.Module) !void {
    var main = try support.Hand.init(arena, module, "main", .{ .params = &.{}, .ret = .i64 });
    _ = try main.emit(.{ .op = .ret, .ty = .void, .a = try main.int(.i64, 0) });
    _ = try main.finish();
}

/// Build the one-operation function `f` of a case.
fn build(arena: std.mem.Allocator, spec: Spec) !Built {
    var module: ir.Module = .{};
    try addEntry(arena, &module);
    const shape = shapeOf(spec);
    var hand = try support.Hand.init(arena, &module, "f", .{ .params = try parameterTypes(arena, spec, shape), .ret = spec.result });
    const a = try hand.param(0);
    var b: ir.Ref = .none;
    if (shape.constant) b = try hand.int(spec.ty, constantFor(spec.mode));
    if (!shape.unary and !shape.constant) b = try hand.param(1);
    const result = try hand.emit(.{ .op = spec.op, .ty = spec.result, .a = a, .b = b, .check = checkOf(spec.mode) });
    _ = try hand.emit(.{ .op = .ret, .ty = .void, .a = result });
    var analysis: emit_llvm.Analysis = .{};
    if (needsFacts(spec.mode)) {
        const known = if (spec.op == .float_to_int)
            try factsFor(arena, &hand.function, &.{result}, .{ .lo = -1000, .hi = 1000 })
        else
            try factsFor(arena, &hand.function, &.{ a, b }, .{ .lo = 0, .hi = std.math.maxInt(u32) });
        analysis.facts = try arena.dupe(?facts.Facts, &.{ null, known });
    }
    _ = try hand.finish();
    return .{ .module = module, .analysis = analysis, .verify = std.mem.eql(u8, spec.mode, "proven-verify") };
}

fn noLocation(_: *const anyopaque, _: u32) emit_llvm.Location {
    return .{ .line = 1, .column = 1 };
}

/// The text of an emitted module and the span of its function `f`.
const Emitted = struct { text: []const u8, body: []const u8 };

/// Emit a hand-built case and find its function `f`.
fn emitted(arena: std.mem.Allocator, built: *const Built) !Emitted {
    const context: u8 = 0;
    const text = try emit_llvm.emitModule(arena, &built.module, .{
        .locator = .{ .context = &context, .locate = noLocation },
        .source_path = "arith.selka",
        .main = .{},
        .analysis = built.analysis,
        .verify = built.verify,
    });
    return functionOf(arena, text, "f");
}

/// The function `name` of an emitted module, without the `define` line and the closing brace.
fn functionOf(arena: std.mem.Allocator, text: []const u8, name: []const u8) !Emitted {
    const needle = try std.fmt.allocPrint(arena, "@\"my.{s}\"(", .{name});
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, needle)) |at| : (from = at + needle.len) {
        const line_start = if (std.mem.lastIndexOfScalar(u8, text[0..at], '\n')) |newline| newline + 1 else 0;
        if (!std.mem.startsWith(u8, text[line_start..], "define ")) continue;
        const start = std.mem.indexOfScalarPos(u8, text, at, '\n') orelse return error.NoFunction;
        const end = std.mem.indexOf(u8, text[start..], "\n}") orelse return error.NoFunction;
        return .{ .text = text, .body = text[start + 1 .. start + end] };
    }
    return error.NoFunction;
}

/// The trap kind of site `index`: the first field of its table entry, named like `emit_llvm.TrapKind`.
fn siteKind(sites: []const u8, index: []const u8, arena: std.mem.Allocator) ![]const u8 {
    const key = try std.fmt.allocPrint(arena, "@myl.site.{s} = private constant %myl.site {{ i32 ", .{index});
    const at = std.mem.indexOf(u8, sites, key) orelse return error.NoSite;
    const rest = sites[at + key.len ..];
    const number = try std.fmt.parseInt(u8, rest[0..std.mem.indexOfScalar(u8, rest, ',').?], 10);
    const kind = std.enums.fromInt(emit_llvm.TrapKind, number) orelse return error.UnknownKind;
    return @tagName(kind);
}

/// `line` without the attachments the templates do not carry: `, !prof !0`, `, !dbg !N`, ` #2`.
fn stripped(line: []const u8) []const u8 {
    var out = line;
    for ([_][]const u8{ ", !dbg", ", !prof", " #" }) |marker| {
        if (std.mem.indexOf(u8, out, marker)) |at| out = out[0..at];
    }
    return std.mem.trim(u8, out, " ");
}

/// Whether `line` is a block label (`b0:`, `trap.4:`).
fn isLabel(line: []const u8) bool {
    return line.len > 1 and line[line.len - 1] == ':' and std.mem.indexOfScalar(u8, line, ' ') == null;
}

/// The register names (`%x`) that occur in `text`, in order.
fn registersIn(arena: std.mem.Allocator, text: []const u8, out: *std.ArrayList([]const u8)) !void {
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (text[i] != '%') continue;
        var j = i + 1;
        while (j < text.len and (std.ascii.isAlphanumeric(text[j]) or text[j] == '.' or text[j] == '_')) : (j += 1) {}
        try out.append(arena, text[i..j]);
        i = j - 1;
    }
}

/// The instruction lines of a function body: no blanks, no attachments.
fn instructionLines(arena: std.mem.Allocator, body: []const u8) ![]const []const u8 {
    var all: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |raw| {
        const line = stripped(raw);
        if (line.len != 0) try all.append(arena, line);
    }
    return all.items;
}

/// The lines that stay, and the registers the trap calls take as diagnostic operands.
const Reduced = struct { kept: []const []const u8, diagnostic: []const []const u8 };

/// Replace each cold trap block by one `trapif CONDITION KIND` line and drop the labels and the entry's
/// scaffolding. A trap is `br i1 %c, label %trap, label %next`, then `trap:`, the call, `unreachable`, `next:`.
fn reduceTraps(arena: std.mem.Allocator, all: []const []const u8, module_text: []const u8) !Reduced {
    var kept: std.ArrayList([]const u8) = .empty;
    var diagnostic: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < all.len) : (i += 1) {
        const line = all[i];
        if (std.mem.startsWith(u8, line, "br i1 ")) {
            const condition = line["br i1 ".len..(std.mem.indexOfScalar(u8, line, ',') orelse return error.BadBranch)];
            const call = all[i + 2];
            const site_at = (std.mem.indexOf(u8, call, "@myl.site.") orelse return error.BadTrap) + "@myl.site.".len;
            const site_number = call[site_at..][0..std.mem.indexOfAny(u8, call[site_at..], ",)").?];
            try registersIn(arena, call, &diagnostic);
            try kept.append(arena, try std.fmt.allocPrint(arena, "trapif {s} {s}", .{ condition, try siteKind(module_text, site_number, arena) }));
            i += 4;
        } else if (!isScaffolding(line)) try kept.append(arena, line);
    }
    return .{ .kept = kept.items, .diagnostic = diagnostic.items };
}

/// A block label, the entry's unconditional jump, or its frame slot.
fn isScaffolding(line: []const u8) bool {
    return isLabel(line) or std.mem.startsWith(u8, line, "br label ") or std.mem.startsWith(u8, line, "%slot = alloca");
}

/// Whether `name` is one of the diagnostic operand registers.
fn isDiagnostic(reduced: Reduced, name: []const u8) bool {
    for (reduced.diagnostic) |other| if (std.mem.eql(u8, other, name)) return true;
    return false;
}

/// Drop the widening casts of the diagnostic operands and rename the registers: the parameters `a` and `b`,
/// the rest `t1`, `t2`, ... in order of definition.
fn renumber(arena: std.mem.Allocator, reduced: Reduced) ![]const u8 {
    var names: std.StringHashMapUnmanaged([]const u8) = .empty;
    try names.put(arena, "%p0", "a");
    try names.put(arena, "%p1", "b");
    var out: std.ArrayList(u8) = .empty;
    var counter: usize = 0;
    for (reduced.kept) |line| {
        if (std.mem.indexOf(u8, line, " = ")) |eq| {
            if (isDiagnostic(reduced, line[0..eq])) continue;
            counter += 1;
            try names.put(arena, line[0..eq], try std.fmt.allocPrint(arena, "t{d}", .{counter}));
        }
        var registers: std.ArrayList([]const u8) = .empty;
        try registersIn(arena, line, &registers);
        var text = line;
        // Longest names first, so `%v1` never eats the front of `%v10`.
        std.mem.sort([]const u8, registers.items, {}, longerFirst);
        for (registers.items) |name| {
            text = try replaceName(arena, text, name, names.get(name) orelse continue);
        }
        try out.appendSlice(arena, text);
        try out.append(arena, '\n');
    }
    return out.items;
}

/// Reduce an emitted function to the template shape.
fn normalize(arena: std.mem.Allocator, module_text: Emitted) ![]const u8 {
    const reduced = try reduceTraps(arena, try instructionLines(arena, module_text.body), module_text.text);
    return renumber(arena, reduced);
}

fn longerFirst(_: void, a: []const u8, b: []const u8) bool {
    return a.len > b.len;
}

/// `text` with every whole-token occurrence of the register `name` replaced.
fn replaceName(arena: std.mem.Allocator, text: []const u8, name: []const u8, replacement: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (std.mem.startsWith(u8, text[i..], name)) {
            const after = i + name.len;
            const boundary = after == text.len or !(std.ascii.isAlphanumeric(text[after]) or text[after] == '.' or text[after] == '_');
            if (boundary) {
                try out.appendSlice(arena, replacement);
                i = after;
                continue;
            }
        }
        try out.append(arena, text[i]);
        i += 1;
    }
    return out.items;
}

/// Run every template against the emitter; returns the failures, one message each.
fn checkAll(arena: std.mem.Allocator, templates: []const Template) ![]const []const u8 {
    var failures: std.ArrayList([]const u8) = .empty;
    for (templates) |template| {
        const spec = specOf(template.id) orelse {
            try failures.append(arena, try std.fmt.allocPrint(arena, "{s}: the test does not know this case id", .{template.id}));
            continue;
        };
        const built = try build(arena, spec);
        const body = emitted(arena, &built) catch |err| {
            try failures.append(arena, try std.fmt.allocPrint(arena, "{s}: emitting failed with {s}", .{ template.id, @errorName(err) }));
            continue;
        };
        const got = try normalize(arena, body);
        if (!std.mem.eql(u8, got, template.body)) {
            try failures.append(arena, try std.fmt.allocPrint(arena, "{s}:\n--- emitter\n{s}--- template\n{s}", .{ template.id, got, template.body }));
        }
    }
    return failures.items;
}

test "the emitter's arithmetic sequences are the ones proofs/arith proves" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, templates_path, arena, .limited(16 << 20));
    const templates = try parseTemplates(arena, text);
    const failures = try checkAll(arena, templates);
    try std.testing.expectEqualStrings("", try firstFailures(arena, failures));
    try std.testing.expectEqual(expected_cases, templates.len);
}

/// One function of the tiny program, the call that keeps it reachable from `main`, and the template it must lower to.
const Source = struct { definition: []const u8, call: []const u8, template: Template };

/// The language spelling of the operation `op` applied to `a` and `operand`, or null for an operation with no spelling.
fn spelled(arena: std.mem.Allocator, op: []const u8, operand: []const u8) !?[]const u8 {
    const Form = struct { name: []const u8, before: []const u8, after: []const u8 };
    const forms = [_]Form{
        .{ .name = "div", .before = "divtrunc(a, ", .after = ")" },
        .{ .name = "rem", .before = "remtrunc(a, ", .after = ")" },
        .{ .name = "floor_div", .before = "a // ", .after = "" },
        .{ .name = "floor_rem", .before = "a % ", .after = "" },
        .{ .name = "shift_left", .before = "shift_left(a, ", .after = ")" },
        .{ .name = "shift_right", .before = "shift_right(a, ", .after = ")" },
        .{ .name = "saturating_add", .before = "saturating_add(a, ", .after = ")" },
    };
    for (forms) |form| {
        if (!std.mem.eql(u8, form.name, op)) continue;
        const text = try std.mem.concat(arena, u8, &.{ form.before, operand, form.after });
        return text;
    }
    return null;
}

/// The function of type `ty` with the body `return expression`; `variable` says whether it has a second parameter.
fn binaryFunction(arena: std.mem.Allocator, index: usize, ty: []const u8, expression: []const u8, variable: bool) !Source {
    const parameters = if (variable) try std.fmt.allocPrint(arena, "a: {s}, b: {s}", .{ ty, ty }) else try std.fmt.allocPrint(arena, "a: {s}", .{ty});
    const arguments = if (variable) try std.fmt.allocPrint(arena, "1{s}, 2{s}", .{ ty, ty }) else try std.fmt.allocPrint(arena, "1{s}", .{ty});
    return .{
        .definition = try std.fmt.allocPrint(arena, "func case{d}({s}) -> {s}:\n    return {s}\n\n", .{ index, parameters, ty, expression }),
        .call = try std.fmt.allocPrint(arena, "    _ = case{d}({s})\n", .{ index, arguments }),
        .template = undefined,
    };
}

/// The language function whose lowering is `template`, or null when no source spells it (the forms the facts choose,
/// and the conversions that carry no check): the operator of the language applied to the function's parameters.
fn sourceFor(arena: std.mem.Allocator, template: Template, index: usize) !?Source {
    var parts = std.mem.splitScalar(u8, template.id, '.');
    const op = parts.next().?;
    const first = parts.next().?;
    const second = parts.next();
    const third = parts.next();
    var source: Source = undefined;
    if (std.mem.eql(u8, op, "saturating_add")) {
        source = try binaryFunction(arena, index, first, (try spelled(arena, op, "b")).?, true);
    } else if (std.mem.eql(u8, op, "convert")) {
        if (!std.mem.eql(u8, third.?, "exact")) return null;
        source = .{
            .definition = try std.fmt.allocPrint(arena, "func case{d}(a: {s}) -> {s}:\n    return {s}(a)\n\n", .{ index, first, second.?, second.? }),
            .call = try std.fmt.allocPrint(arena, "    _ = case{d}(1{s})\n", .{ index, first }),
            .template = undefined,
        };
    } else if (std.mem.eql(u8, op, "float_to_int")) {
        if (!std.mem.eql(u8, second.?, "exact")) return null;
        source = .{
            .definition = try std.fmt.allocPrint(arena, "func case{d}(a: float) -> {s}:\n    return {s}(a)\n\n", .{ index, first, first }),
            .call = try std.fmt.allocPrint(arena, "    _ = case{d}(2.5)\n", .{index}),
            .template = undefined,
        };
    } else {
        const mode = second.?;
        const operand: []const u8 = if (std.mem.eql(u8, mode, "const")) "7" else if (std.mem.eql(u8, mode, "const-1")) "-1" else if (std.mem.eql(u8, mode, "exact")) "b" else return null;
        source = try binaryFunction(arena, index, first, (try spelled(arena, op, operand)).?, std.mem.eql(u8, mode, "exact"));
    }
    source.template = template;
    return source;
}

/// The tiny program with one function per case that has a source form.
fn programOf(arena: std.mem.Allocator, templates: []const Template) ![]const Source {
    var sources: std.ArrayList(Source) = .empty;
    for (templates) |template| {
        if (try sourceFor(arena, template, sources.items.len)) |source| try sources.append(arena, source);
    }
    return sources.items;
}

/// The text of the program: every function, then a `main` that calls each.
fn programText(arena: std.mem.Allocator, sources: []const Source) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (sources) |source| try text.appendSlice(arena, source.definition);
    try text.appendSlice(arena, "func main(args: str[], out: Stream) -> int:\n");
    for (sources) |source| try text.appendSlice(arena, source.call);
    try text.appendSlice(arena, "    print(out, 1)\n    return 0\n");
    return text.items;
}

/// Compile the program from source and compare each function with its template; returns the failures.
fn checkProgram(arena: std.mem.Allocator, sources: []const Source) ![]const []const u8 {
    const text = try support.llvmText(arena, try programText(arena, sources));
    var failures: std.ArrayList([]const u8) = .empty;
    for (sources, 0..) |source, index| {
        const name = try std.fmt.allocPrint(arena, "case{d}", .{index});
        const got = try normalize(arena, try functionOf(arena, text, name));
        if (!std.mem.eql(u8, got, source.template.body)) {
            try failures.append(arena, try std.fmt.allocPrint(arena, "{s} from source:\n--- compiler\n{s}--- template\n{s}", .{ source.template.id, got, source.template.body }));
        }
    }
    return failures.items;
}

test "tiny programs compiled from source lower to the same sequences" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, templates_path, arena, .limited(16 << 20));
    const sources = try programOf(arena, try parseTemplates(arena, text));
    try std.testing.expectEqual(expected_programs, sources.len);
    try std.testing.expectEqualStrings("", try firstFailures(arena, try checkProgram(arena, sources)));
}

/// How many cases a source program spells: the four divisions over the eight types (three forms for a signed type, two for
/// an unsigned one), both shifts, `saturating_add`, `convert` between the 56 ordered pairs of distinct types and `float_to_int`.
const expected_programs: usize = 4 * (4 * 3 + 4 * 2) + 2 * 8 + 8 + 56 + 8;

/// The first few failures as one text, so a red run shows what differs.
fn firstFailures(arena: std.mem.Allocator, failures: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (failures[0..@min(failures.len, 8)]) |failure| {
        try out.appendSlice(arena, failure);
        try out.append(arena, '\n');
    }
    return out.items;
}

/// How many cases the template file holds: the four divisions over the eight types (five modes for
/// a signed type, four for an unsigned one, plus `proven-narrow` for `i64` and the three narrowed
/// forms for `u64`), both shifts in three modes, `saturating_add`, `convert` between the 56 ordered
/// pairs of distinct types in three modes, and `float_to_int` in three modes plus the `i64` narrowing.
const expected_cases: usize = 4 * (3 * 5 + 6 + 3 * 4 + 7) + 2 * 8 * 3 + 8 + 56 * 3 + 8 * 3 + 1;

test "the harness refuses malformed templates, modules and traps instead of passing them" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try std.testing.expectError(error.BadTemplates, parseTemplates(arena, "end\n"));
    const without_function = try build(arena, specOf("saturating_add.i8").?);
    var module: ir.Module = .{};
    try addEntry(arena, &module);
    try std.testing.expectError(error.NoFunction, emitted(arena, &.{ .module = module, .analysis = without_function.analysis, .verify = false }));
    try std.testing.expectError(error.NoSite, siteKind("", "9", arena));
    try std.testing.expectError(error.UnknownKind, siteKind("@myl.site.0 = private constant %myl.site { i32 200, i32 1 }\n", "0", arena));
    try std.testing.expectError(error.BadBranch, reduceTraps(arena, &.{"br i1 %c"}, ""));
    try std.testing.expectError(error.BadTrap, reduceTraps(arena, &.{ "br i1 %c, label %t, label %n", "t:", "call void @other()", "unreachable", "n:" }, ""));
}
