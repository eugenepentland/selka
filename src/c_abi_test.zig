//! Front-end contracts for direct C imports: the accepted signatures (scalars, `str` and `bytes` spans, `bytes` results,
//! `extern type` handles, `mut` out-parameters), the refusals with their codes, and the handle uses `E_EXTERN_TYPE` refuses.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const options = @import("test_paths");
const entry =
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "foreign.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}
test "direct C imports preserve formatting and mark the C ABI" {
    const source =
        \\extern func labs(host: Host, x: i64) -> i64
        \\
        \\
        \\func main(host: Host) -> i64:
        \\    return labs(host, -7)
    ;
    var c = try language.Compilation.init(t.allocator, "foreign.selka", source);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "extern func labs") != null);
    try c.check();
    try t.expect(c.program.?.functions[0].policy.c_abi);
}

// spec: C-FFI-1
test "direct C declarations reject retired effect clauses and unsupported signatures" {
    try reject(
        \\extern func f(host: Host, x: Unit) -> i64 effects(host)
    ++ entry, "E_EFFECTS_REMOVED");
    // Generic extern declarations fail structurally before the parser reaches
    // the retired effect clause; preserve that original diagnostic precedence.
    try reject(
        // migrate-embedded: skip intentional generic-extern parser rejection
        \\extern func f[T](host: Host, x: T) -> T effects(host)
    ++ entry, "E_HOST_DECLARATION");
    var no_clause = try language.Compilation.init(t.allocator, "foreign-no-clause.selka",
        \\extern func f(host: Host) -> i64
    ++ entry);
    defer no_clause.deinit();
    try no_clause.check();
    try reject(
        \\extern func f(host: Host) effects(host)
    ++ entry, "E_EFFECTS_REMOVED");
    try reject(
        \\extern func myl_intrude(host: Host) -> i64 effects(host)
    ++ entry, "E_EFFECTS_REMOVED");
    try reject(
        \\extern func f(host: Host) -> i64 effects(host)
        \\
        \\
        \\func main(host: Host) -> i64 effects():
        \\    return f(host)
    , "E_EFFECTS_REMOVED");
}

// spec-case: HOST-CAPABILITY-1
test "foreign declarations require a leading Host capability parameter" {
    try reject(
        \\extern func f(x: i64) -> i64 effects(host)
    ++ entry, "E_EFFECTS_REMOVED");
}

// spec-case: C-FFI-1
test "a project's own C function may start with the product's name: only the runtime's prefixes are reserved" {
    var c = try language.Compilation.init(t.allocator, "foreign.selka", "extern func selka_sqlite_open(host: Host, flags: i32) -> i32\n" ++ entry);
    defer c.deinit();
    try c.check();
    try reject("extern func mylang_intrude(host: Host) -> int\n" ++ entry, "E_EXTERN_SYMBOL"); // rename: keep
    try reject("extern func myl_intrude(host: Host) -> int\n" ++ entry, "E_EXTERN_SYMBOL");
}

// spec-case: C-FFI-1
test "modern C declarations retain signature symbol and Host validation" {
    try reject("extern func f(host: Host, x: Unit) -> int\n" ++ entry, "E_EXTERN_SIGNATURE");
    try reject("extern func f[T](host: Host, x: T) -> T\n" ++ entry, "E_HOST_DECLARATION");
    try reject("extern func f(host: Host)\n" ++ entry, "E_EXTERN_SIGNATURE");
    try reject("extern func myl_intrude(host: Host) -> int\n" ++ entry, "E_EXTERN_SYMBOL");
    try reject("extern func f(x: int) -> int\n" ++ entry, "E_HOST_CAPABILITY");
}

/// `selka check` of `source` as a file; its first diagnostic's code, or "" when it checks.
fn checkedCode(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(t.io, .{ .sub_path = "program.selka", .data = source });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", try std.fs.path.join(a, &.{ root, "program.selka" }), "--no-cache" } });
    const marker = std.mem.indexOf(u8, result.stderr, "error[") orelse return "";
    const end = std.mem.indexOfScalarPos(u8, result.stderr, marker, ']') orelse return error.Malformed;
    return a.dupe(u8, result.stderr[marker + 6 .. end]);
}

/// The declarations the handle tests below share: an opaque type and a C function that makes one.
const handle_head =
    \\extern type Thing
    \\
    \\extern func thing_new(host: Host, value: i64) -> Thing
    \\
    \\
;
/// `body`, the statements of `main(host: Host, out: Stream) -> int` after one handle `t` is made, is refused with
/// `E_EXTERN_TYPE` and a message containing `wanted`.
fn rejectHandleUse(body: []const u8, wanted: []const u8) !void {
    const source = try std.mem.concat(t.allocator, u8, &.{ handle_head, "func main(host: Host, out: Stream) -> int:\n    const t = thing_new(host, 1)\n", body });
    defer t.allocator.free(source);
    var c = try language.Compilation.init(t.allocator, "handles.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_EXTERN_TYPE", c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, wanted) != null);
}

// spec-case: C-FFI-4
test "C interop: an extern type handle refuses arithmetic, ordering, number conversions and fields, each with its own message" {
    try rejectHandleUse("    const u = t + t\n    return 0\n", "no arithmetic");
    try rejectHandleUse("    const u = t + 1\n    return 0\n", "no arithmetic");
    try rejectHandleUse("    const u = -t\n    return 0\n", "no arithmetic");
    try rejectHandleUse("    if t < Thing():\n        return 1\n    return 0\n", "not ordered");
    try rejectHandleUse("    return int(t)\n", "does not convert");
    try rejectHandleUse("    return int(u64(t))\n", "does not convert");
    try rejectHandleUse("    const u = Thing(5)\n    return 0\n", "does not convert");
    try rejectHandleUse("    return t.value\n", "no fields");
}

test "C interop: an extern type handle cannot be printed, formatted, turned into text or matched" {
    try rejectHandleUse("    print(out, t)\n    return 0\n", "cannot be printed");
    try rejectHandleUse("    print(out, f\"{t}\")\n    return 0\n", "cannot be printed");
    try rejectHandleUse("    const s = str(t)\n    return 0\n", "cannot be printed");
    try rejectHandleUse("    match t:\n        case _:\n            return 0\n", "cannot be matched");
}

test "C interop: an extern type handle never crosses to a parallel task, as an argument or inside a mapped value" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings("E_EXTERN_TYPE", try checkedCode(arena.allocator(), "import parallel\n\n" ++ handle_head ++
        \\func work(t: Thing) -> int:
        \\    return 1
        \\
        \\func main(host: Host) -> int:
        \\    const t = thing_new(host, 1)
        \\    with parallel.group() as g:
        \\        const job = g.submit(work, t)
        \\        return job.result()
        \\
    ));
    try t.expectEqualStrings("E_EXTERN_TYPE", try checkedCode(arena.allocator(), "import parallel\n\n" ++ handle_head ++
        \\record H:
        \\    t: Thing = Thing()
        \\
        \\func work(h: H) -> int:
        \\    return 1
        \\
        \\func main() -> int:
        \\    mut hs: H[] = [H()]
        \\    const r = parallel.map(hs, work)
        \\    return len(r)
        \\
    ));
}

test "C interop: a handle has no JSON form: the json module takes json.Json values, which no handle converts to" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings("E_TYPE", try checkedCode(arena.allocator(), "import json\n\n" ++ handle_head ++
        \\func main(host: Host) -> int:
        \\    const s = json.dumps(thing_new(host, 1))
        \\    return 0
        \\
    ));
}

test "C interop: extern type handles are copied, stored in lists, options, dictionaries and sets, compared and taken" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings("", try checkedCode(arena.allocator(), "import sets\n\n" ++ handle_head ++
        \\record Holder:
        \\    thing: Thing = Thing()
        \\
        \\func main(host: Host) -> int:
        \\    const t = thing_new(host, 1)
        \\    mut xs: Thing[] = [t, Thing()]
        \\    mut o: Thing? = Some(t)
        \\    mut d: dict[Thing, int] = {}
        \\    d[t] = 1
        \\    mut names: dict[str, Thing] = {}
        \\    names["a"] = t
        \\    mut s: set[Thing] = set()
        \\    sets.add(mut s, t)
        \\    mut h = Holder(thing=t)
        \\    const twin = copy(h)
        \\    const old = take(mut h)
        \\    if twin.thing == old.thing and h.thing == Thing() and o is not None:
        \\        return len(xs) + len(d) + len(names) + len(s)
        \\    return 0
        \\
    ));
}

// spec-case: C-FFI-2
test "C interop: extern signatures take str and bytes spans and a bytes result, and refuse a byte_buffer, a str result and mut text" {
    var accepted = try language.Compilation.init(t.allocator, "spans.selka",
        \\extern type Thing
        \\
        \\extern func f(host: Host, a: str, b: bytes, mut n: i64, mut h: Thing, mut flag: bool) -> i32
        \\
        \\extern func g(host: Host, a: str) -> bytes
    ++ entry);
    defer accepted.deinit();
    try accepted.check();
    try reject("extern func f(host: Host, b: byte_buffer) -> i64\n" ++ entry, "E_EXTERN_SIGNATURE");
    try reject("extern func f(host: Host) -> str\n" ++ entry, "E_EXTERN_SIGNATURE");
    try reject("extern func f(host: Host, mut s: str) -> i64\n" ++ entry, "E_EXTERN_SIGNATURE");
    try reject("extern func f(host: Host, mut n: i64) -> bytes\n" ++ entry, "E_EXTERN_SIGNATURE");
    try reject("extern func f(host: Host, xs: i64[]) -> i64\n" ++ entry, "E_EXTERN_SIGNATURE");
}

test "C interop: an extern type declaration formats to itself and keeps its parse" {
    const source =
        \\public extern type Thing
        \\
        \\
        \\extern func thing_new(host: Host, value: i64) -> Thing
        \\
        \\
        \\func main(host: Host) -> i64:
        \\    const t = thing_new(host, 1)
        \\    if t == Thing():
        \\        return 1
        \\    return 0
        \\
    ;
    var c = try language.Compilation.init(t.allocator, "fmt.selka", source);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(source, formatted);
    var again = try language.Compilation.init(t.allocator, "fmt.selka", formatted);
    defer again.deinit();
    const twice = try again.format(t.allocator);
    defer t.allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
    try again.check();
}

/// Check `source` and expect its first diagnostic to have `code` and a message holding `message`.
fn rejectWith(source: []const u8, code: []const u8, message: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "foreign.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, message) != null);
}

const address_source =
    \\extern type Function
    \\
    \\
    \\@address
    \\extern func through(host: Host, target: Function, a: i64, b: i64) -> i64
    \\
    \\
    \\@address
    \\extern func at(host: Host, target: u64, text: str, mut count: i64) -> bool
    \\
    \\
    \\@address
    \\extern func at_32(host: Host, target: u32, a: u8) -> Unit
    \\
    \\
    \\func main(host: Host) -> i64:
    \\    mut count = 0
    \\    const found = at(host, u64(16), "x", mut count)
    \\    return through(host, Function(), 1, 2) + count
    \\
;

// spec-case: C-FFI-ADDRESS-1
test "C interop: @address marks an extern func whose target is a handle, a u32 or a u64, and formats to itself" {
    var c = try language.Compilation.init(t.allocator, "address.selka", address_source);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(address_source, formatted);
    try c.check();
    var marked: usize = 0;
    for (c.program.?.functions) |function| {
        if (function.policy.address) marked += 1;
        if (function.policy.address) try t.expect(function.policy.c_abi);
    }
    try t.expectEqual(@as(usize, 3), marked);
}

// spec-case: C-FFI-ADDRESS-1
test "C interop: @address refuses every other target, a missing one, a mut one, and a declaration that is not an extern func" {
    const wanted = "takes the function it calls as the parameter after `host`";
    try rejectWith("@address\nextern func f(host: Host, target: i64) -> i64\n" ++ entry, "E_EXTERN_ADDRESS", wanted);
    try rejectWith("@address\nextern func f(host: Host, target: u16, x: i64) -> i64\n" ++ entry, "E_EXTERN_ADDRESS", wanted);
    try rejectWith("@address\nextern func f(host: Host, target: bool) -> i64\n" ++ entry, "E_EXTERN_ADDRESS", wanted);
    try rejectWith("@address\nextern func f(host: Host, target: str) -> i64\n" ++ entry, "E_EXTERN_ADDRESS", wanted);
    try rejectWith("@address\nextern func f(host: Host) -> i64\n" ++ entry, "E_EXTERN_ADDRESS", wanted);
    try rejectWith("@address\nextern func f(host: Host, mut target: u64) -> i64\n" ++ entry, "E_EXTERN_ADDRESS", wanted);
    // The rest of the signature follows a plain `extern func`'s rules.
    try reject("@address\nextern func f(host: Host, target: u64, xs: i64[]) -> i64\n" ++ entry, "E_EXTERN_SIGNATURE");
    try reject("@address\nextern func f(host: Host, target: u64) -> str\n" ++ entry, "E_EXTERN_SIGNATURE");
    try reject("@address\nextern func f(target: u64) -> i64\n" ++ entry, "E_HOST_CAPABILITY");
    try rejectWith("@address\nfunc f(target: u64) -> i64:\n    return 0\n" ++ entry, "E_ATTRIBUTE_TARGET", "`@address` attaches to an `extern func` declaration");
    try rejectWith("@address\nrecord R:\n    x: i64\n" ++ entry, "E_ATTRIBUTE_TARGET", "`@address` attaches to an `extern func` declaration");
    try rejectWith("@address\n@address\nextern func f(host: Host, target: u64) -> i64\n" ++ entry, "E_DUPLICATE_ATTRIBUTE", "repeated");
}
