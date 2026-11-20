//! The refused half of the `@sealed` rules (W11, `docs/records-and-unions.md#sealed-records`): each way another module
//! could build or change a sealed record, with its code and message, and the places the rules allow (the declaring
//! module's test file). The accepted shapes are `tests/lang/sealed_records.selka`.
const std = @import("std");
const t = std.testing;
const options = @import("test_paths");
/// Failure detail goes to the test's stderr.
const report = std.debug.print;

/// The module every case imports: a sealed record with defaults and an invariant, a holder whose default is the sealed
/// module's own, a sealed `@linear` protocol state, and the functions that make and end them.
const seal_module =
    \\@invariant(self.value >= 0)
    \\@sealed
    \\public record Token:
    \\    value: int = 1
    \\    items: int[] = []
    \\
    \\public record Box:
    \\    tok: Token = Token()
    \\
    \\@sealed
    \\@linear
    \\public record Staged:
    \\    target: int
    \\
    \\@sealed
    \\public record Id:
    \\    n: int
    \\
    \\public func id(n: int) -> Id:
    \\    return Id(n=n)
    \\
    \\public record Pair:
    \\    a: int
    \\    b: str
    \\
    \\public enum Mode:
    \\    off
    \\    on(pair: Pair)
    \\
    \\@sealed
    \\public record Switch:
    \\    mode: Mode = Mode.off
    \\    opt: str? = None
    \\    limit: int? = None
    \\
    \\public func switch_on(level: int) -> Switch:
    \\    return Switch(mode=Mode.on(pair=Pair(a=level, b="x")), opt=Some("first"), limit=Some(level))
    \\
    \\public func raise(mut s: Switch):
    \\    match mut s.mode:
    \\        case on(pair=p):
    \\            p.a = p.a + 1
    \\        case off:
    \\            pass
    \\
    \\public func make(v: int) -> Token:
    \\    return Token(value=v)
    \\
    \\public func begin(target: int) -> Staged:
    \\    return Staged(target=target)
    \\
    \\public func commit(own s: Staged) -> int:
    \\    return own s.target
    \\
    \\public func bump_any[T: copy + field(value: int)](mut x: T):
    \\    x.value = x.value + 1
;

/// One file of a case: its name and its text.
const File = struct { name: []const u8, text: []const u8 };

/// The JSON diagnostics `selka check` prints for `entry`, with `seal.selka` and the other files beside it.
fn checked(a: std.mem.Allocator, files: []const File, entry: []const u8) !std.process.RunResult {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(t.io, .{ .sub_path = "seal.selka", .data = seal_module });
    for (files) |file| {
        if (std.fs.path.dirname(file.name)) |parent| try directory.dir.createDirPath(t.io, parent);
        try directory.dir.writeFile(t.io, .{ .sub_path = file.name, .data = file.text });
    }
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    return std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", try std.fs.path.join(a, &.{ root, entry }), "--no-cache", "--diagnostics=json" } });
}

/// `body`, the rest of a module `main` that imports `seal`, is refused with `code` and a message containing `fragment`.
fn expectRefused(body: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try std.mem.concat(a, u8, &.{ "import seal\n\n", body, "\n\nfunc main() -> int:\n    return 0\n" });
    try expectFilesRefused(&.{.{ .name = "main.selka", .text = text }}, "main.selka", code, fragment);
}

/// The check of `entry` among `files` is refused, first with `code`, and the message contains `fragment`.
fn expectFilesRefused(files: []const File, entry: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const result = try checked(arena.allocator(), files, entry);
    const stderr = result.stderr;
    const found = std.mem.indexOf(u8, stderr, "\"code\":\"");
    if (found == null) report("expected {s}, got no diagnostic:\n{s}\n", .{ code, stderr });
    try t.expect(found != null);
    const rest = stderr[found.? + 8 ..];
    const end = std.mem.indexOfScalar(u8, rest, '"').?;
    if (!std.mem.eql(u8, rest[0..end], code) or std.mem.indexOf(u8, stderr, fragment) == null) report("expected {s} with `{s}`, got:\n{s}\n", .{ code, fragment, stderr });
    try t.expectEqualStrings(code, rest[0..end]);
    try t.expect(std.mem.indexOf(u8, stderr, fragment) != null);
}

/// A command's standard output contains `fragment`; both streams go to stderr when it does not.
fn expectContains(result: std.process.RunResult, fragment: []const u8) !void {
    const found = std.mem.indexOf(u8, result.stdout, fragment) != null;
    if (!found) report("expected `{s}` in:\n{s}{s}\n", .{ fragment, result.stdout, result.stderr });
    try t.expect(found);
}

/// The check of `entry` among `files` passes.
fn expectFilesAccepted(files: []const File, entry: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const result = try checked(arena.allocator(), files, entry);
    if (result.term != .exited or result.term.exited != 0) report("expected a clean check, got:\n{s}\n", .{result.stderr});
    try t.expect(result.term == .exited and result.term.exited == 0);
}

const builds = "only module `seal` and its test file `seal_test` build one";
const changes = "only module `seal` and its test file `seal_test` change its fields";

test "sealed records refuse a constructor call from another module, naming a function that makes one" {
    try expectRefused(
        \\func f() -> int:
        \\    const t = seal.Token(value=5)
        \\    return t.value
    , "E_SEALED_RECORD", "`seal.Token` is sealed: " ++ builds ++ "; call a function of `seal` that returns a `seal.Token`, such as `seal.make`");
}

test "sealed records refuse a construction from defaults" {
    try expectRefused(
        \\func f() -> int:
        \\    return seal.Token().value
    , "E_SEALED_RECORD", builds);
}

test "sealed records refuse a field write through a mut local" {
    try expectRefused(
        \\func f() -> int:
        \\    mut t = seal.make(1)
        \\    t.value = 9
        \\    return t.value
    , "E_SEALED_RECORD", changes);
}

test "sealed records refuse a compound field write through a mut parameter" {
    try expectRefused(
        \\func f(mut t: seal.Token):
        \\    t.value += 1
    , "E_SEALED_RECORD", changes);
}

test "sealed records refuse a write of a field nested in another module's record" {
    try expectRefused(
        \\func f() -> int:
        \\    mut b = seal.Box(tok=seal.make(2))
        \\    b.tok.value = 40
        \\    return b.tok.value
    , "E_SEALED_RECORD", changes);
}

test "sealed records refuse a write through a list element and a match mut binding" {
    try expectRefused(
        \\func f() -> int:
        \\    mut xs = [seal.make(1)]
        \\    xs[0].value = 3
        \\    return xs[0].value
    , "E_SEALED_RECORD", changes);
    try expectRefused(
        \\func f() -> int:
        \\    mut o: seal.Token? = Some(seal.make(5))
        \\    match mut o:
        \\        case Some(tok):
        \\            tok.value = 7
        \\        case None:
        \\            pass
        \\    return 0
    , "E_SEALED_RECORD", changes);
}

test "sealed records refuse an append to a field and a mut field argument" {
    try expectRefused(
        \\func f() -> int:
        \\    mut t = seal.make(1)
        \\    append(mut t.items, 4)
        \\    return len(t.items)
    , "E_SEALED_RECORD", changes);
    try expectRefused(
        \\func grow(mut xs: int[]):
        \\    append(mut xs, 1)
        \\
        \\func f() -> int:
        \\    mut t = seal.make(1)
        \\    grow(mut t.items)
        \\    return len(t.items)
    , "E_SEALED_RECORD", changes);
}

test "sealed records refuse take and exchange of a field" {
    try expectRefused(
        \\func f() -> int:
        \\    mut t = seal.make(1)
        \\    const old = exchange(mut t.value, 3)
        \\    return old
    , "E_SEALED_RECORD", changes);
    try expectRefused(
        \\func f() -> int:
        \\    mut t = seal.make(1)
        \\    const old = take(mut t.items)
        \\    return len(old)
    , "E_SEALED_RECORD", changes);
}

test "sealed records refuse replace, which builds a new value" {
    try expectRefused(
        \\func f() -> int:
        \\    const t = seal.make(1)
        \\    const u = replace(own t, value=9)
        \\    return u.value
    , "E_SEALED_RECORD", "`replace` builds a new `seal.Token`, and `seal.Token` is sealed: " ++ builds);
}

test "sealed records refuse take of a whole value, which leaves one built from its defaults" {
    try expectRefused(
        \\func f() -> int:
        \\    mut t = seal.make(5)
        \\    const old = take(mut t)
        \\    return old.value
    , "E_SEALED_RECORD", "`take` leaves a `seal.Token` built from its defaults in the place");
}

test "sealed records refuse a field default written in another module, at its declaration" {
    try expectRefused(
        \\record Holder:
        \\    tok: seal.Token = seal.Token(value=3)
    , "E_SEALED_RECORD", "this default builds a `seal.Token`, and `seal.Token` is sealed: " ++ builds ++ "; give the field no default, or make it an option");
}

test "sealed records refuse a generic instance that writes the record's field or takes it through a field bound" {
    try expectRefused(
        \\func poke[T: copy + field(value: int)](mut x: T):
        \\    x.value = 42
        \\
        \\func f() -> int:
        \\    mut t = seal.make(5)
        \\    poke(mut t)
        \\    return t.value
    , "E_SEALED_RECORD", "(in the instance of `poke` for `seal.Token`)");
    try expectRefused(
        \\func reset[T: copy + field(value: int)](mut x: T) -> T:
        \\    return take(mut x)
        \\
        \\func f() -> int:
        \\    mut t = seal.make(5)
        \\    return reset(mut t).value
    , "E_SEALED_RECORD", "built from its defaults in the place, and `seal.Token` is sealed: " ++ builds ++
        "; use `exchange(mut place, value)` with a value `seal` made (in the instance of `reset` for `seal.Token`)");
}

test "sealed records refuse a test of another module that takes one as an input" {
    try expectRefused(
        \\public func test_token(t: seal.Token) -> bool:
        \\    return t.value >= 0
    , "E_SEALED_RECORD", "the test runner would build this `seal.Token` (from a cases file or a generated input)");
    try expectRefused(
        \\public record Holder:
        \\    toks: seal.Token[]
        \\
        \\public func test_holder(h: Holder?) -> bool:
        \\    return h is None
    , "E_SEALED_RECORD", "only the tests of module `seal` and its test file `seal_test` take one as an input");
}

test "sealed records refuse own of a field that ends a sealed linear value outside its module" {
    try expectRefused(
        \\func f() -> int:
        \\    const s = seal.begin(3)
        \\    return own s.target
    , "E_SEALED_RECORD", "`own` of a field ends the sealed `@linear` `seal.Staged` outside module `seal`; give it to one of its " ++
        "functions that takes `own seal.Staged`, such as `seal.commit`");
}

test "sealed records refuse a construction through a facade's re-exported name" {
    try expectFilesRefused(&.{
        .{ .name = "facade.selka", .text = "import seal\nexport seal.Token\n" },
        .{ .name = "main.selka", .text = "import facade\n\nfunc main() -> int:\n    return facade.Token(value=2).value\n" },
    }, "main.selka", "E_SEALED_RECORD", builds);
}

test "sealed records allow the module's test file to build, change and generate one" {
    try expectFilesAccepted(&.{.{ .name = "seal_test.selka", .text =
        \\import seal
        \\
        \\public func test_build() -> bool:
        \\    mut t = seal.Token(value=3)
        \\    t.value = 4
        \\    const u = replace(own t, value=5)
        \\    return u.value == 5
        \\
        \\public func test_generated(t: seal.Token) -> bool:
        \\    return t.value >= 0
        \\
    }}, "seal_test.selka");
}

test "sealed records allow moves, copies, exchange of a whole value, reads and a generic of the module" {
    try expectFilesAccepted(&.{.{ .name = "main.selka", .text =
        \\import seal
        \\
        \\func main() -> int:
        \\    mut t = seal.make(1)
        \\    const twin = copy(t)
        \\    const old = exchange(mut t, seal.make(2))
        \\    seal.bump_any(mut t)
        \\    mut seen: dict[seal.Id, int] = {}
        \\    seen[seal.id(1)] = old.value + twin.value
        \\    const b = seal.Box()
        \\    return t.value + b.tok.value + seen[seal.id(1)]
        \\
    }}, "main.selka");
}

test "sealed records refuse a test file of the same name in another directory" {
    try expectFilesRefused(&.{.{ .name = "tests/seal_test.selka", .text =
        \\import seal
        \\
        \\public func test_build() -> bool:
        \\    return seal.Token(value=3).value == 3
        \\
    }}, "tests/seal_test.selka", "E_SEALED_RECORD", builds);
}

test "sealed records refuse the attribute on anything but a record" {
    try expectFilesRefused(&.{.{ .name = "main.selka", .text = "@sealed\nenum Kind:\n    a\n    b\n\nfunc main() -> int:\n    return 0\n" }}, "main.selka", "E_ATTRIBUTE_TARGET", "`@sealed` attaches to a `record` declaration");
}

test "sealed records: adding the attribute is an interface change api-diff reports" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const plain = "public record Token:\n    value: int\n\npublic func make(v: int) -> Token:\n    return Token(value=v)\n";
    try directory.dir.writeFile(t.io, .{ .sub_path = "seal.selka", .data = plain });
    try directory.dir.writeFile(t.io, .{ .sub_path = "main.selka", .data = "import seal\n\nfunc main() -> int:\n    return seal.make(1).value\n" });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "main.selka" });
    const baseline = try std.fmt.allocPrint(a, "--write={s}", .{try std.fs.path.join(a, &.{ root, "api.txt" })});
    const against = try std.fmt.allocPrint(a, "--against={s}", .{try std.fs.path.join(a, &.{ root, "api.txt" })});
    _ = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "api-diff", entry, baseline } });
    try directory.dir.writeFile(t.io, .{ .sub_path = "seal.selka", .data = try std.mem.concat(a, u8, &.{ "@sealed\n", plain }) });
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "api-diff", entry, against } });
    try expectContains(result, "breaking=1");
}

const match_mut = "`match mut` asks to write a field of `seal.Switch`, and `seal.Switch` is sealed: only module `seal` and its test file " ++
    "`seal_test` change its fields; read it with a plain `match`";

test "sealed records refuse match mut on a field through a mut local and a mut parameter" {
    try expectRefused(
        \\func f() -> int:
        \\    mut s = seal.switch_on(2)
        \\    match mut s.mode:
        \\        case on(pair=p):
        \\            p.a = 99
        \\        case off:
        \\            return 1
        \\    return 0
    , "E_SEALED_RECORD", match_mut);
    try expectRefused(
        \\func f(mut s: seal.Switch):
        \\    match mut s.mode:
        \\        case on(pair=p):
        \\            p.b = "forged"
        \\        case off:
        \\            pass
    , "E_SEALED_RECORD", match_mut);
}

test "sealed records refuse match mut on an option field, scalar payloads included" {
    try expectRefused(
        \\func f() -> int:
        \\    mut s = seal.switch_on(2)
        \\    match mut s.opt:
        \\        case Some(text):
        \\            text = "forged"
        \\        case None:
        \\            pass
        \\    return 0
    , "E_SEALED_RECORD", match_mut);
    try expectRefused(
        \\func f() -> int:
        \\    mut s = seal.switch_on(2)
        \\    match mut s.limit:
        \\        case Some(n):
        \\            n = 7
        \\        case None:
        \\            pass
        \\    return 0
    , "E_SEALED_RECORD", match_mut);
}

test "sealed records refuse match mut through a list element and a nested path" {
    try expectRefused(
        \\func f() -> int:
        \\    mut xs = [seal.switch_on(2)]
        \\    match mut xs[0].mode:
        \\        case on(pair=p):
        \\            p.a = 5
        \\        case off:
        \\            pass
        \\    return 0
    , "E_SEALED_RECORD", match_mut);
    try expectRefused(
        \\record Holder:
        \\    sw: seal.Switch
        \\
        \\func f() -> int:
        \\    mut h = Holder(sw=seal.switch_on(2))
        \\    match mut h.sw.mode:
        \\        case on(pair=p):
        \\            p.a = 5
        \\        case off:
        \\            pass
        \\    return 0
    , "E_SEALED_RECORD", match_mut);
}

test "sealed records refuse a nested match mut on a binding's own field" {
    try expectRefused(
        \\func f() -> int:
        \\    mut o: seal.Switch? = Some(seal.switch_on(1))
        \\    match mut o:
        \\        case Some(sw):
        \\            match mut sw.mode:
        \\                case on(pair=p):
        \\                    p.a = 3
        \\                case off:
        \\                    pass
        \\        case None:
        \\            pass
        \\    return 0
    , "E_SEALED_RECORD", match_mut);
}

test "sealed records refuse match mut in a generic instance through a field bound" {
    try expectRefused(
        \\func bump[T: copy + field(mode: seal.Mode)](mut x: T):
        \\    match mut x.mode:
        \\        case on(pair=p):
        \\            p.a = 1
        \\        case off:
        \\            pass
        \\
        \\func f() -> int:
        \\    mut s = seal.switch_on(2)
        \\    bump(mut s)
        \\    return 0
    , "E_SEALED_RECORD", "read it with a plain `match` (in the instance of `bump` for `seal.Switch`)");
}

test "sealed records allow a plain match outside the module and match mut inside it and its test file" {
    try expectFilesAccepted(&.{.{ .name = "main.selka", .text =
        \\import seal
        \\
        \\func main() -> int:
        \\    mut s = seal.switch_on(2)
        \\    seal.raise(mut s)
        \\    match s.mode:
        \\        case on(pair=p):
        \\            return p.a
        \\        case off:
        \\            return 0
        \\
    }}, "main.selka");
    try expectFilesAccepted(&.{.{ .name = "seal_test.selka", .text =
        \\import seal
        \\
        \\public func test_writes_the_mode() -> bool:
        \\    mut s = seal.switch_on(2)
        \\    match mut s.mode:
        \\        case on(pair=p):
        \\            p.a = 9
        \\        case off:
        \\            return False
        \\    return True
        \\
    }}, "seal_test.selka");
}
