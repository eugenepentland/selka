//! Generic syntax retains source contract metadata through executable specialization.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const ast = @import("ast.zig");
const copy = @import("ast_copy.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const source = @import("source.zig");
const fixture =
    \\def choose[T: copy + equality, U: integer](x: T, y: U) -> T:
    \\    return x
    \\
    \\
    \\def main() -> i64:
    \\    return choose[i64, u8](1, 2u8)
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "generic.my", fixture);
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    const parameters = syntax.functions[0].signature.type_parameters;
    try t.expectEqual(@as(usize, 2), parameters.len);
    try t.expectEqual(@as(usize, 2), parameters[0].requirements.len);
    try t.expectEqualStrings("equality", compilation.src.text(parameters[0].requirements[1]));
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const cloned = try copy.clone(arena.allocator(), syntax);
    try t.expect(cloned.functions[0].signature.type_parameters.ptr != parameters.ptr);
    try t.expect(cloned.functions[0].signature.type_parameters[0].requirements.ptr != parameters[0].requirements.ptr);
    const mapped = try source.Source.initMapped(arena.allocator(), &.{ try source.Source.init(arena.allocator(), "prefix.my", "// prefix\n"), compilation.src });
    const mapper: copy.Mapper = .{ .src = mapped, .module = 1, .node_count = syntax.nodes.items.len, .statement_count = syntax.statements.items.len };
    const moved = try mapper.value(arena.allocator(), ast.Function, cloned.functions[0]);
    try t.expectEqualStrings("copy", mapped.text(moved.signature.type_parameters[0].requirements[0]));
    var seen = false;
    for (syntax.types.expressions.applications) |application| {
        seen = true;
        try t.expectEqualStrings("choose", compilation.src.text(application.name));
        try t.expect(cloned.types.expressions.applications[0].arguments.ptr != application.arguments.ptr);
        const moved_application = try mapper.value(arena.allocator(), ast.TypeApplication, application);
        try t.expectEqual(@as(usize, 2), moved_application.arguments.len);
        try t.expectEqualStrings("u8", mapped.text(moved_application.arguments[1]));
    }
    try t.expect(seen);
    const formatted = try compilation.format(allocator);
    defer allocator.free(formatted);
    var roundtrip = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer roundtrip.deinit();
    try roundtrip.parse();
    try t.expectEqual(@as(usize, 2), roundtrip.syntax.?.functions[0].signature.type_parameters.len);
    try compilation.check();
}
// spec: GENERIC-SYNTAX-1
test "generic syntax retains requirements type arguments and relocated owned metadata" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
// `[T]` is the copy spelling, and a square argument list is always a valid index
// expression, so neither a bare parameter nor a list without a call is rejected.
test "generic syntax rejects incomplete duplicate and uncallable annotations" {
    const cases = [_]struct { text: []const u8, code: []const u8 }{
        .{ .text =
        \\def f[](x: i64) -> i64:
        \\    return x
        , .code = "E_SYNTAX" },
        .{ .text =
        \\def f[T: copy, T: integer](x: T) -> T:
        \\    return x
        , .code = "E_GENERIC_PARAMETER" },
        .{ .text =
        \\def f[T: copy + copy](x: T) -> T:
        \\    return x
        , .code = "E_GENERIC_REQUIREMENT" },
    };
    for (cases) |case| {
        var compilation = try language.Compilation.init(t.allocator, "bad.my", case.text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.parse());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
    var compilation = try language.Compilation.init(t.allocator, "bad-call.my",
        \\def f(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return f[i64](1)
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_GENERIC_ARITY", compilation.diagnostics.items[0].code);
}

test "generic syntax list limits accept sixteen and reject seventeen entries" {
    for ([_][]const u8{ "parameters", "requirements", "arguments" }) |kind| {
        for ([_]usize{ 16, 17 }) |count| {
            var text: std.Io.Writer.Allocating = .init(t.allocator);
            defer text.deinit();
            const arguments = std.mem.eql(u8, kind, "arguments");
            const parameters = std.mem.eql(u8, kind, "parameters");
            try text.writer.writeAll(if (arguments) "def main() -> i64:\n    return f[" else if (parameters) "def f[" else "def f[T: ");
            for (0..count) |i| {
                if (i != 0) try text.writer.writeAll(if (parameters or arguments) ", " else " + ");
                if (arguments) try text.writer.writeAll("i64") else if (parameters) try text.writer.print("T{d}: copy", .{i}) else try text.writer.print("R{d}", .{i});
            }
            try text.writer.writeAll(if (arguments) "](1)\n" else "](x: i64) -> i64:\n    return x\n");
            var compilation = try language.Compilation.init(t.allocator, "limits.my", text.written());
            defer compilation.deinit();
            if (count == 16) try compilation.parse() else {
                try t.expectError(error.SourceError, compilation.parse());
                try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
            }
        }
    }
}

test "generic syntax preserves qualified module type arguments when formatting" {
    const text =
        \\module main
        \\import api
        \\
        \\
        \\def main() -> i64:
        \\    return api.identity[api.Number](1)
    ;
    var compilation = try language.Compilation.init(t.allocator, "main.my", text);
    defer compilation.deinit();
    const first = try compilation.formatModule(t.allocator);
    defer t.allocator.free(first);
    var again = try language.Compilation.init(t.allocator, "main.my", first);
    defer again.deinit();
    const second = try again.formatModule(t.allocator);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
}
const named_fixture =
    \\# reusable contract
    \\constraint Prices[P] = copy + op(price(policy: P, subtotal: int) -> int effects())
    \\
    \\
    \\def bare[P: Prices](x: P) -> P:
    \\    return x
    \\
    \\
    \\def mixed[P: Prices + codec + field(tag: bool)](x: P) -> P:
    \\    return x
;
const named_module_fixture =
    \\module checkout
    \\import contracts
    \\
    \\
    \\constraint Local[P] = copy
    \\
    \\
    \\public def total[P: contracts.Prices](policy: P) -> int:
    \\    return 0
;
/// Parse `text` expecting a source error and return the first diagnostic code.
fn errorCode(text: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, "invalid.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    return compilation.diagnostics.items[0].code;
}
/// Parse `text` expecting a source error and return the first diagnostic message.
fn errorMessage(text: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, "invalid.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.parse());
    return compilation.diagnostics.items[0].message;
}
/// Build `[P: N0 + ... + N{count-1}]` and report whether parsing accepts it.
fn boundCountParses(count: usize) !bool {
    var text: std.Io.Writer.Allocating = .init(t.allocator);
    defer text.deinit();
    try text.writer.writeAll("def f[P: ");
    for (0..count) |i| {
        if (i != 0) try text.writer.writeAll(" + ");
        try text.writer.print("N{d}", .{i});
    }
    try text.writer.writeAll("](x: P) -> P:\n    return x\n");
    var compilation = try language.Compilation.init(t.allocator, "limits.my", text.written());
    defer compilation.deinit();
    if (count <= 16) {
        try compilation.parse();
        return true;
    }
    try t.expectError(error.SourceError, compilation.parse());
    try t.expectEqualStrings("E_GENERIC_LIMIT", compilation.diagnostics.items[0].code);
    return false;
}

// spec: NAMED-CONSTRAINT-SYNTAX-1
test "named constraints parse declarations and mixed bounds" {
    var compilation = try language.Compilation.init(t.allocator, "named.my", named_fixture);
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    try t.expectEqual(@as(usize, 1), syntax.types.constraints.len);
    const constraint = syntax.types.constraints[0];
    try t.expectEqualStrings("Prices", compilation.src.text(constraint.name));
    try t.expect(std.mem.startsWith(u8, compilation.src.text(constraint.span), "constraint Prices[P] = copy"));
    try t.expectEqualStrings("P", compilation.src.text(constraint.subject.name));
    try t.expectEqual(@as(usize, 1), constraint.subject.requirements.len);
    try t.expectEqualStrings("copy", compilation.src.text(constraint.subject.requirements[0]));
    try t.expectEqual(@as(usize, 0), constraint.subject.field_requirements.len);
    try t.expectEqual(@as(usize, 1), constraint.subject.operation_requirements.len);
    try t.expectEqualStrings("price", compilation.src.text(constraint.subject.operation_requirements[0].name));
    try t.expectEqual(@as(usize, 2), constraint.subject.operation_requirements[0].parameters.len);
    try t.expectEqualStrings("policy", compilation.src.text(constraint.subject.operation_requirements[0].parameters[0].name));
    try t.expectEqual(@as(usize, 0), constraint.subject.named_requirements.len);
    const bare = syntax.functions[0].signature.type_parameters[0];
    try t.expectEqualStrings("Prices", compilation.src.text(bare.named_requirements[0].name));
    try t.expect(bare.named_requirements[0].alias == null);
    const mixed = syntax.functions[1].signature.type_parameters[0];
    try t.expectEqualStrings("Prices", compilation.src.text(mixed.named_requirements[0].name));
    try t.expectEqual(@as(usize, 1), mixed.requirements.len);
    try t.expectEqualStrings("codec", compilation.src.text(mixed.requirements[0]));
    try t.expectEqual(@as(usize, 1), mixed.field_requirements.len);
    try t.expectEqualStrings("tag", compilation.src.text(mixed.field_requirements[0].name));
}

// spec-case: NAMED-CONSTRAINT-SYNTAX-1
test "named constraints parse module aliases clone relocate and format round trips" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    var sink: language.diagnostic.Sink = .{ .allocator = arena.allocator() };
    const src = try source.Source.init(arena.allocator(), "checkout.my", named_module_fixture);
    const tokens = try lexer.lex(arena.allocator(), named_module_fixture, &sink);
    var p: parser.Parser = .{ .src = src, .arena = &arena, .tokens = tokens, .sink = &sink };
    const syntax = try p.parseModule();
    try t.expectEqual(@as(usize, 1), syntax.types.constraints.len);
    try t.expectEqual(@as(usize, 1), syntax.functions.len);
    const bound = syntax.functions[0].signature.type_parameters[0].named_requirements[0];
    try t.expectEqualStrings("contracts", src.text(bound.alias.?));
    try t.expectEqualStrings("Prices", src.text(bound.name));
    const cloned = try copy.clone(arena.allocator(), syntax);
    try t.expect(cloned.types.constraints.ptr != syntax.types.constraints.ptr);
    try t.expect(cloned.functions[0].signature.type_parameters[0].named_requirements.ptr != syntax.functions[0].signature.type_parameters[0].named_requirements.ptr);
    const mapped = try source.Source.initMapped(arena.allocator(), &.{ try source.Source.init(arena.allocator(), "prefix.my", "// prefix\n"), src });
    const mapper: copy.Mapper = .{ .src = mapped, .module = 1, .node_count = syntax.nodes.items.len, .statement_count = syntax.statements.items.len };
    const moved_constraint = try mapper.value(arena.allocator(), ast.Constraint, cloned.types.constraints[0]);
    try t.expectEqualStrings("Local", mapped.text(moved_constraint.name));
    const moved_bound = try mapper.value(arena.allocator(), ast.BoundReference, cloned.functions[0].signature.type_parameters[0].named_requirements[0]);
    try t.expectEqualStrings("contracts", mapped.text(moved_bound.alias.?));
    try t.expectEqualStrings("Prices", mapped.text(moved_bound.name));
    var compilation = try language.Compilation.init(t.allocator, "checkout.my", named_module_fixture);
    defer compilation.deinit();
    const first = try compilation.formatModule(t.allocator);
    defer t.allocator.free(first);
    var again = try language.Compilation.init(t.allocator, "checkout.my", first);
    defer again.deinit();
    const second = try again.formatModule(t.allocator);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
}

// spec-case: NAMED-CONSTRAINT-SYNTAX-1
test "named constraints reject non-bare subject binders" {
    try t.expectEqualStrings("E_SYNTAX", try errorCode("constraint Prices[P: copy] = copy"));
    try t.expectEqualStrings("E_SYNTAX", try errorCode("constraint Prices[const P] = copy"));
    try t.expectEqualStrings("E_SYNTAX", try errorCode("constraint Prices[P, Q] = copy"));
    try t.expectEqualStrings("E_SYNTAX", try errorCode("constraint Prices[] = copy"));
}

// spec-case: NAMED-CONSTRAINT-SYNTAX-1
test "named constraints reject named right-hand references" {
    try t.expectEqualStrings("E_GENERIC_REQUIREMENT", try errorCode("constraint Prices[P] = copy + Other"));
    try t.expectEqualStrings("a constraint definition cannot reference another named constraint", try errorMessage("constraint Prices[P] = copy + Other"));
    try t.expectEqualStrings("E_GENERIC_REQUIREMENT", try errorCode("constraint Prices[P] = copy + Prices"));
    try t.expectEqualStrings("a constraint definition cannot refer to itself", try errorMessage("constraint Prices[P] = copy + Prices"));
}

// spec-case: NAMED-CONSTRAINT-SYNTAX-1
test "named constraints reject applied bounds and constant-length bounds" {
    try t.expectEqualStrings("E_GENERIC_REQUIREMENT", try errorCode(
        \\def f[P: Prices[int]](x: P) -> P:
        \\    return x
    ));
    try t.expectEqualStrings("E_GENERIC_REQUIREMENT", try errorCode(
        \\def f[const N: Prices](x: i64) -> i64:
        \\    return x
    ));
}

// spec-case: NAMED-CONSTRAINT-SYNTAX-1
test "named constraints count toward the sixteen requirement limit" {
    try t.expect(try boundCountParses(16));
    try t.expect(!(try boundCountParses(17)));
}
