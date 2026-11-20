//! Generic templates keep symbolic typing while each concrete body checks moves.
const std = @import("std");
const report = std.debug.print;
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");

fn accepted(a: std.mem.Allocator, text: []const u8) !language.typed.Program {
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure) catch |err| {
        const location = unit.src.?.locate(failure.span.start);
        const rule = if (failure.rule) |value| @tagName(value) else "none";
        report("{s}/{s}: {s}\n{s}:{d}:{d}: {s}\nsource:\n{s}\n", .{
            failure.code, rule, failure.message, location.path, location.line, location.column, location.text, text,
        });
        return err;
    };
    return unit.program.?;
}

fn refusedWithoutEdit(a: std.mem.Allocator, text: []const u8, code: []const u8) !ownership.Failure {
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(failure.rule != null);
    var rendered: std.ArrayList(u8) = .empty;
    try ownership.render(a, unit.src.?, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"fix\":") == null);
    return failure;
}

fn refusedWithEdit(a: std.mem.Allocator, text: []const u8, code: []const u8) !ownership.Failure {
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(failure.rule != null);
    var rendered: std.ArrayList(u8) = .empty;
    try ownership.render(a, unit.src.?, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"fix\":") != null);
    return failure;
}

const explicit_templates =
    \\record Holder[T]:
    \\    value: T
    \\func transferred[T](own value: T) -> T:
    \\    mut kept = own value
    \\    return kept
    \\func packed[T](own value: T) -> Holder[T]:
    \\    return Holder[T](value=own value)
    \\func optional[T](own value: T) -> T?:
    \\    return Some(own value)
    \\func paired[T](own left: T, own right: T) -> T[]:
    \\    return [own left, own right]
    \\func pushed[T](own value: T, mut output: T[]):
    \\    append(mut output, own value)
    \\func main() -> int:
    \\    mut texts: str[] = []
    \\    mut text = "pushed"
    \\    pushed[str](own text, mut texts)
    \\    mut numbers: int[] = []
    \\    pushed[int](6, mut numbers)
    \\    _ = transferred[int](1)
    \\    _ = transferred[str]("text")
    \\    _ = packed[int](2)
    \\    _ = packed[str]("packed")
    \\    _ = optional[int](3)
    \\    _ = optional[str]("optional")
    \\    _ = paired[int](4, 5)
    \\    _ = paired[str]("left", "right")
    \\    return 0
;

test "O4 generic own templates serve managed and scalar instances at every storage shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try accepted(arena.allocator(), explicit_templates);
    try std.testing.expectEqual(@as(usize, 11), program.functions.len);
}

test "O4 generic own missing markers are concrete refusals without shared template edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const template =
        \\func transferred[T](own value: T) -> T:
        \\    mut kept = value
        \\    return kept
        \\
    ;
    _ = try accepted(arena.allocator(), template ++
        \\func main() -> int:
        \\    return 0
    );
    _ = try refusedWithoutEdit(arena.allocator(), template ++
        \\func main() -> int:
        \\    _ = transferred[int](1)
        \\    _ = transferred[str]("text")
        \\    return 0
    , "E_OWN_MARKER");
}

test "O4 generic const escapes cannot rewrite a shared initializer for one managed instance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try refusedWithoutEdit(arena.allocator(),
        \\func aliased[T](own value: T) -> T:
        \\    const borrowed = value
        \\    return borrowed
        \\func main() -> int:
        \\    _ = aliased[int](1)
        \\    _ = aliased[str]("text")
        \\    return 0
    , "E_OWN_MARKER");
}

test "F6 generic concrete scalar markers offer certain removal edits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try refusedWithEdit(arena.allocator(),
        \\func copied[T](value: T) -> int:
        \\    _ = value
        \\    const count = 3
        \\    mut kept = own count
        \\    return kept
        \\func main() -> int:
        \\    return copied[int](1)
    , "E_OWN_MARKER");
}

test "O4 generic own scalar exceptions follow carrier fields inferred calls and owned match payloads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try accepted(arena.allocator(),
        \\record Holder[T]:
        \\    value: T
        \\func field[T](own holder: Holder[T]) -> T:
        \\    mut kept = own holder.value
        \\    return kept
        \\func make[T](own value: T) -> T:
        \\    return value
        \\func inferred[T](own value: T) -> T:
        \\    const built = make(own value)
        \\    const alias = own built
        \\    mut kept = own alias
        \\    return kept
        \\func maybe[T](own value: T) -> T?:
        \\    return Some(own value)
        \\func payload[T: copy + storable](own value: T, fallback: T) -> T:
        \\    match maybe[T](own value):
        \\        case Some(item):
        \\            mut kept = own item
        \\            return kept
        \\        case None:
        \\            return copy(fallback)
        \\func main() -> int:
        \\    _ = field[int](Holder[int](value=1))
        \\    _ = field[str](Holder[str](value="field"))
        \\    _ = inferred[int](2)
        \\    _ = inferred[str]("inferred")
        \\    _ = payload[int](3, 0)
        \\    _ = payload[str]("payload", "fallback")
        \\    return 0
    );
}

test "O4 generic iteration markers use symbolic types without authorizing managed element moves" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const template =
        \\func my_take[T](values: T[]) -> int:
        \\    for value in values:
        \\        mut kept = own value
        \\        _ = kept
        \\    return 0
        \\
    ;
    _ = try accepted(arena.allocator(), template ++
        \\func main() -> int:
        \\    return my_take[int]([1])
    );
    const managed = template ++
        \\func main() -> int:
        \\    return my_take[str](["borrowed"])
    ;
    // The named element remains borrowed while the iteration's source loan is
    // live, so its attempted move reports that overlap before a storage check.
    const failure = try refusedWithoutEdit(arena.allocator(), managed, "E_SINGLE_OWNER_OVERLAP");
    try std.testing.expectEqual(.R7, failure.rule.?);
    try std.testing.expectEqualStrings("own value", managed[failure.span.start..failure.span.end]);
}

fn cachedContract(backing: std.mem.Allocator, cache: *language.semantic_cache.Cache, text: []const u8, refuse: bool) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "generic-cached.selka", text);
    defer unit.deinit();
    try unit.checkWithCache(cache);
    var failure: ownership.Failure = .{};
    if (!refuse) return ownership.checkWithSource(a, unit.program.?, unit.src, &failure);
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    var rendered: std.ArrayList(u8) = .empty;
    defer rendered.deinit(a);
    try ownership.render(a, unit.src, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"fix\":") != null);
}

test "F6 generic concrete marker repairs survive cold warm and relocated semantic replay" {
    var cache = language.semantic_cache.Cache.init(std.testing.allocator, 4 << 20);
    defer cache.deinit();
    const good =
        \\func make[T](own value: T) -> T:
        \\    return value
        \\func inferred[T](own value: T) -> T:
        \\    const fixed = 1
        \\    mut constant_copy = fixed
        \\    _ = constant_copy
        \\    const built = make(own value)
        \\    mut moved = own built
        \\    return moved
        \\func main() -> int:
        \\    _ = inferred[int](1)
        \\    _ = inferred[str]("text")
        \\    return 0
    ;
    const relocated = "# Relocate generic type-dependence facts.\n" ++ good;
    try cachedContract(std.testing.allocator, &cache, good, false);
    try cachedContract(std.testing.allocator, &cache, good, false);
    try cachedContract(std.testing.allocator, &cache, relocated, false);
    try std.testing.expect(cache.statistics.reused != 0);
    const bad = try std.mem.replaceOwned(u8, std.testing.allocator, good, "mut constant_copy = fixed", "mut constant_copy = own fixed");
    defer std.testing.allocator.free(bad);
    const shifted_bad = try std.mem.concat(std.testing.allocator, u8, &.{ "# Relocate a concrete scalar refusal.\n", bad });
    defer std.testing.allocator.free(shifted_bad);
    try cachedContract(std.testing.allocator, &cache, bad, true);
    try cachedContract(std.testing.allocator, &cache, bad, true);
    try cachedContract(std.testing.allocator, &cache, shifted_bad, true);
}
