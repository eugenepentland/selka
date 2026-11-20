//! `selka check` and `selka build` agree (G3 fix 1b). Every program here is one G2 (the stage-2 EDA
//! port) found that `check` accepted and `build` refused with `E_CORE_UNSUPPORTED` (ownership rule Z3):
//! either the program is valid and the passes now schedule it, or it is invalid and the checker now
//! reports it, with the diagnostic `build` would have had to give.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

/// Run the release passes (the inliner and the ownership scheduler among them) over `source`. A shape the
/// scheduler cannot place fails here, the way `selka build` fails with `E_CORE_UNSUPPORTED`.
fn schedules(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(), source);
    try std.testing.expect(std.mem.indexOf(u8, text, "fn main") != null);
}

/// Check `source` and require the single-owner checker to refuse it with `code`.
fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const program = try support.checkedProgram(a, source);
    try std.testing.expectError(error.Rejected, unique.check(a, program, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
}

// F-G2e-A-1: a named `own` capability handed to a call left a provider pin on its old binding, which the
// ownership pass then saw read after the call consumed the capability.
test "G3-1b a named own capability handed to a call builds, and the callee owns it" {
    try schedules(std.testing.allocator,
        \\func my_take(own fs: Filesystem) -> int:
        \\    if fs.exists("a"):
        \\        return 1
        \\    return 2
        \\
        \\
        \\func main(own fs: Filesystem, out: Stream) -> int:
        \\    const k = my_take(own fs)
        \\    print(out, k)
        \\    return 0
    );
}

test "G3-1b an own capability forwarded through a local, a record and a second call builds" {
    try schedules(std.testing.allocator,
        \\import filesystem
        \\import random
        \\
        \\
        \\record Caps:
        \\    fs: Filesystem
        \\    entropy: Entropy
        \\
        \\
        \\record Holder:
        \\    caps: Caps
        \\    n: int
        \\
        \\
        \\func make(own fs: Filesystem, own entropy: Entropy) -> Holder:
        \\    return Holder(caps=Caps(fs=own fs, entropy=own entropy), n=0)
        \\
        \\
        \\func bump(mut h: Holder):
        \\    h.n = h.n + 1
        \\
        \\
        \\func again(own fs: Filesystem, own entropy: Entropy) -> Holder:
        \\    mut h = make(own fs, own entropy)
        \\    bump(mut h)
        \\    return h
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut fs = filesystem.memory()
        \\    mut entropy = random.seeded_entropy(3)
        \\    mut h = again(own fs, own entropy)
        \\    bump(mut h)
        \\    print(out, h.n)
        \\    return 0
    );
}

// The take-mix repro of `move_out_build` (F-G2p-eval): a constructor that takes some fields of a `mut`
// record and passes the record whole to a helper. The inliner leaves the helper's updated record in a
// tuple, and the borrow of a wide field was re-anchored on the record the tuple had already consumed.
test "G3-1b a constructor that takes fields of a mut record and then passes it whole to an inlined helper builds" {
    try schedules(std.testing.allocator,
        \\record Rules:
        \\    a: float
        \\    b: float
        \\    c: float
        \\    d: float
        \\    e: float
        \\    f: float
        \\
        \\
        \\record Forms:
        \\    keys: int[]
        \\    size: int
        \\
        \\
        \\record Build:
        \\    a: int[]
        \\    rules: Rules
        \\    forms: Forms
        \\    n: int
        \\
        \\
        \\func take_forms(mut b: Build) -> Forms:
        \\    return Forms(keys=take(mut b.forms.keys), size=b.forms.size)
        \\
        \\
        \\func move_out(mut b: Build) -> Build:
        \\    return Build(a=take(mut b.a), rules=b.rules, forms=take_forms(mut b), n=b.n)
        \\
        \\
        \\func main() -> int:
        \\    mut b = Build(a=[1], rules=Rules(a=1.0, b=2.0, c=3.0, d=4.0, e=5.0, f=6.0), forms=Forms(keys=[1], size=1), n=3)
        \\    const moved = move_out(mut b)
        \\    return len(moved.a) + len(b.a) + int(moved.rules.f)
    );
}

// Render-7 (g2p-render): `const original = nets` is a read-only borrow of `nets`, so a later change to
// `nets` while `original` is still read is an overlap. `copy(original)` is a read of `original`; the checker
// did not count it, and only the build refused.
const alias_prelude =
    \\record Net:
    \\    name: bytes
    \\    pins: int[]
    \\
    \\
    \\func collect(mut nets: Net[]):
    \\    append(mut nets, Net(name=b"a", pins=[1]))
    \\
    \\
    \\func apply(mut nets: Net[], n: int):
    \\    for i in range(0, len(nets)):
    \\        nets[i].pins = [n]
    \\
    \\
    \\func main() -> int:
    \\    return run()
    \\
    \\
;

fn aliasProgram(a: std.mem.Allocator, body: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ alias_prelude, "func run() -> int:\n    mut nets: Net[] = []\n    collect(mut nets)\n", body });
}

test "G3-1b a copy of a const alias read after the owner changed is an overlap the checker reports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try refuses(a, try aliasProgram(a, "    const original = nets\n    apply(mut nets, 3)\n    mut snapshot = copy(original)\n    return len(snapshot)\n"), "E_SINGLE_OWNER_OVERLAP");
    try refuses(a, try aliasProgram(a, "    const original = nets\n    apply(mut nets, 3)\n    mut kept: Net[][] = []\n    append(mut kept, copy(original))\n    return len(kept)\n"), "E_SINGLE_OWNER_OVERLAP");
    // The same overlap when the alias is read by an operation that was always counted.
    try refuses(a, try aliasProgram(a, "    const original = nets\n    apply(mut nets, 3)\n    return len(original)\n"), "E_SINGLE_OWNER_OVERLAP");
}

test "G3-1b a copy of the alias taken before the owner changes, or of the owner itself, is accepted and builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try schedules(a, try aliasProgram(a, "    const original = nets\n    mut snapshot = copy(original)\n    apply(mut nets, 3)\n    return len(snapshot) + len(nets)\n"));
    try schedules(a, try aliasProgram(a, "    mut snapshot = copy(nets)\n    apply(mut nets, 3)\n    return len(snapshot) + len(nets)\n"));
}

// Not a refusal: a program the checker accepts, the passes schedule, and the capability rules still bound.
test "G3-1b the cases G2 recorded that no longer reproduce stay accepted: two list indexes, a match arm, a leaf collection update" {
    try schedules(std.testing.allocator,
        \\record Pin:
        \\    ref: bytes
        \\    fns: int[]
        \\
        \\
        \\record Net:
        \\    pins: Pin[]
        \\
        \\
        \\record Board:
        \\    nets: Net[]
        \\
        \\
        \\func rename_all(mut board: Board):
        \\    for n in range(0, len(board.nets)):
        \\        for p in range(0, len(board.nets[n].pins)):
        \\            board.nets[n].pins[p].ref = b"x"
        \\
        \\
        \\func assert_alt(mut board: Board, which: int?, mut fns: int[]):
        \\    match which:
        \\        case Some(n):
        \\            board.nets[n].pins[0].fns = take(mut fns)
        \\        case None:
        \\            pass
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut board = Board(nets=[Net(pins=[Pin(ref=b"a", fns=[1])])])
        \\    rename_all(mut board)
        \\    mut fns = [2, 3]
        \\    assert_alt(mut board, Some(0), mut fns)
        \\    print(out, len(board.nets[0].pins))
        \\    return 0
    );
}

// G3 fix 2: a function builds and returns a record that holds capabilities. Since 5C a capability is a shareable handle,
// so every way of getting a second copy of one, or one that outlives the record that held it, checks and builds.
const services_prelude =
    \\import filesystem
    \\import random
    \\
    \\
    \\record Services:
    \\    fs: Filesystem
    \\    entropy: Entropy
    \\    runs: int
    \\
    \\
    \\func start(own fs: Filesystem, own entropy: Entropy) -> Services:
    \\    return Services(fs=own fs, entropy=own entropy, runs=0)
    \\
    \\
;

fn servicesProgram(a: std.mem.Allocator, rest: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ services_prelude, rest });
}

test "G3-2 a capability record is built from named capabilities, bound, passed mut and rebuilt by a helper" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try schedules(arena.allocator(), try servicesProgram(arena.allocator(),
        \\func bump(mut services: Services):
        \\    services.runs = services.runs + 1
        \\
        \\
        \\func again(own fs: Filesystem, own entropy: Entropy) -> Services:
        \\    mut services = start(own fs, own entropy)
        \\    bump(mut services)
        \\    return services
        \\
        \\
        \\func main(own fs: Filesystem, own entropy: Entropy, out: Stream) -> int:
        \\    mut services = again(own fs, own entropy)
        \\    bump(mut services)
        \\    print(out, services.runs)
        \\    return 0
    ));
}

test "G3-2 (5C) a capability is shared by two records, stored from a borrow, copied, listed and returned from a fallible function" {
    const backing = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    // One capability, two records: the old `own` markers still check, and both records share the handle.
    try schedules(backing, try servicesProgram(a,
        \\func main(out: Stream) -> int:
        \\    mut fs = filesystem.memory()
        \\    mut entropy = random.seeded_entropy(1)
        \\    mut first = start(own fs, own entropy)
        \\    mut second = start(own fs, own entropy)
        \\    print(out, first.runs + second.runs)
        \\    return 0
    ));
    // A borrowed capability stored in a returned record.
    try schedules(backing, try servicesProgram(a,
        \\func leak(fs: Filesystem, entropy: Entropy) -> Services:
        \\    return Services(fs=fs, entropy=entropy, runs=0)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    print(out, leak(filesystem.memory(), random.seeded_entropy(1)).runs)
        \\    return 0
    ));
    // A copy of the record.
    try schedules(backing, try servicesProgram(a,
        \\func main(out: Stream) -> int:
        \\    mut services = start(filesystem.memory(), random.seeded_entropy(1))
        \\    mut twin = copy(services)
        \\    twin.runs = 1
        \\    print(out, services.runs + twin.runs)
        \\    return 0
    ));
    // A capability field read out of a record borrowed through a mut parameter.
    try schedules(backing, try servicesProgram(a,
        \\func take_fs(mut services: Services) -> Filesystem:
        \\    services.runs = services.runs + 1
        \\    return services.fs
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    mut services = start(filesystem.memory(), random.seeded_entropy(1))
        \\    print(out, take_fs(mut services).exists("x"))
        \\    return 0
    ));
    // A list of such records.
    try schedules(backing, try servicesProgram(a,
        \\func main(out: Stream) -> int:
        \\    mut all: Services[] = []
        \\    append(mut all, start(filesystem.memory(), random.seeded_entropy(1)))
        \\    print(out, len(all))
        \\    return 0
    ));
    // A fallible function (a Result holds the record).
    try schedules(backing, try servicesProgram(a,
        \\func start_checked(runs: int) -> Services fails str:
        \\    if runs < 0:
        \\        fail "negative"
        \\    return Services(fs=filesystem.memory(), entropy=random.seeded_entropy(1), runs=runs)
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    match start_checked(2):
        \\        case Ok(services):
        \\            print(out, services.runs)
        \\        case Err(_):
        \\            pass
        \\    return 0
    ));
}

// Debug compilers verify the Core IR they build and the linkage of the units they emit; two valid shapes failed those checks.
test "G3-1b a const alias of an optional list field is a local the IR verifier admits (option of a list view)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: @import("build.zig").Refusal = .{};
    const module = try support.buildSource(a,
        \\record Saved:
        \\    name: str
        \\    poly: float[][]? = None
        \\
        \\
        \\func corners() -> float[][]:
        \\    return [[0.0, 0.0], [1.0, 0.0]]
        \\
        \\
        \\func points(saved: Saved) -> int:
        \\    mut poly = corners()
        \\    const alias = saved.poly
        \\    if alias is not None:
        \\        poly = copy(alias)
        \\    return len(poly)
        \\
        \\
        \\func main() -> int:
        \\    return points(Saved(name="a", poly=Some([[1.0]])))
    , &refusal);
    try std.testing.expect(module.functions.items.len >= 3);
}

/// Two modules served from memory by path.
const TwoModules = struct {
    lib: []const u8,
    main: []const u8,

    fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const self: *const TwoModules = @ptrCast(@alignCast(context.?));
        if (std.mem.eql(u8, path, "main.selka")) return a.dupe(u8, self.main);
        if (std.mem.eql(u8, path, "lib.selka")) return a.dupe(u8, self.lib);
        return error.NotFound;
    }
};

test "G3-1b a function a function value names is visible to the unit of its adapter, a plain private function is not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var files: TwoModules = .{
        .lib =
        \\func increment(mut value: int) -> Unit:
        \\    value += 1
        \\
        \\
        \\func plain(value: int) -> int:
        \\    return value + 1
        \\
        \\
        \\public func bumped() -> int:
        \\    const operation: func(mut value: int) -> Unit = increment
        \\    mut value = plain(1)
        \\    operation(mut value)
        \\    return value
        ,
        .main =
        \\import lib
        \\
        \\
        \\func main() -> int:
        \\    return lib.bumped()
        ,
    };
    var project = language.project.Project.init(a);
    try project.load(.{ .context = &files, .read = TwoModules.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
    const program = compilation.program.?;
    var increment_private: ?bool = null;
    var plain_private: ?bool = null;
    for (program.functions, 0..) |function, id| {
        if (std.mem.eql(u8, function.name, "lib::increment")) increment_private = program.private[id];
        if (std.mem.eql(u8, function.name, "lib::plain")) plain_private = program.private[id];
    }
    try std.testing.expectEqual(@as(?bool, false), increment_private);
    try std.testing.expectEqual(@as(?bool, true), plain_private);
}

test "the line-1 test locator stops at the largest debug column LLVM accepts, for a merged source past 65,535 bytes" {
    const context: u8 = 0;
    try std.testing.expectEqual(@as(u32, 1), support.firstLine(&context, 0).column);
    try std.testing.expectEqual(@as(u32, 65535), support.firstLine(&context, 79910).column);
    try std.testing.expectEqual(@as(u32, 1), support.firstLine(&context, 79910).line);
}

// Lane CB (9 November 2026), F-PB-2: a dictionary that holds borrowed values (RB2) owns its keys, so a slice of the lent value
// stored as a key escapes its source, as it does for any other dictionary (V2). The borrowed-collection store skipped the
// check, and the build failed instead. The refusal carries the certain `copy(...)` repair of the key.
test "CB F-PB-2 a slice of a lent value stored as a borrowed dictionary's key is refused with the copy repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\import bytes
        \\
        \\
        \\func main() -> int:
        \\    const lines = bytes.split(b"a :1\nb :2", b"\n")
        \\    mut by_head: dict[bytes, bytes] = {}
        \\    for line in lines:
        \\        const at = bytes.find(line, b" :")
        \\        by_head[line[:at]] = line
        \\    return len(by_head)
    ;
    // Every refusal `selka check` reports: a refused function with borrowed collections is reported as it was before RB2,
    // so the value's borrow is refused too (R7), each with its copy repair.
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var every: unique.Every = .{};
    try unique.checkEvery(a, unit.program.?, null, unit.src.?, &every);
    const failures = unique.distinct(&every);
    try std.testing.expectEqual(@as(usize, 2), failures.len);
    const failure = failures[0];
    try std.testing.expectEqualStrings("E_SLICE_ESCAPES", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.V2, failure.rule.?);
    try std.testing.expectEqualStrings("`line[:at]` is lent by the local `lines`, and the dictionary `by_head` needs its own value; write `copy(line[:at])` to keep both", failure.message);
    try std.testing.expectEqualStrings("line[:at]", unit.src.?.text(failure.copy.span.?));
    try std.testing.expectEqualStrings("E_SINGLE_OWNER_OVERLAP", failures[1].code);
    var rendered: std.ArrayList(u8) = .empty;
    try unique.render(a, unit.src.?, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"text\":\"copy(\"") != null);
    // The repaired key, with the value still lent, checks and builds.
    try schedules(a, try std.mem.replaceOwned(u8, a, text, "by_head[line[:at]]", "by_head[copy(line[:at])]"));
}

// F-PB-1: a loop variable read again from its record after a write is still a place of that record, so the inner loop's
// collection (`r.checks`) is read again after each write the inner loop makes.
test "CB F-PB-1 a loop over a field of the loop variable after a write to the record it lies in builds" {
    try schedules(std.testing.allocator,
        \\record Row:
        \\    ok: bool
        \\    checks: int[]
        \\
        \\
        \\record Roll:
        \\    a: int = 0
        \\    b: int = 0
        \\    items: Row[] = []
        \\
        \\
        \\func roll_up(own items: Row[]) -> Roll:
        \\    mut sc = Roll(items=own items)
        \\    for r in sc.items:
        \\        sc.b += 1
        \\        for c in r.checks:
        \\            sc.a += c
        \\    return sc
        \\
        \\
        \\func main() -> int:
        \\    const rows: Row[] = [Row(ok=True, checks=[1, 2])]
        \\    const sc = roll_up(own rows)
        \\    return sc.a + sc.b
    );
}

// F-PB-3: the borrowed result's derivation walk resolved a phi through an edge recorded for a later entry of its block, and
// two loop phis that feed each other (`continue` before the reassignment) sent it round until it gave up.
test "CB F-PB-3 a from result reassigned from an element in a loop that continues builds" {
    try schedules(std.testing.allocator,
        \\record Inst:
        \\    ref_des: bytes
        \\
        \\
        \\record Block:
        \\    instances: Inst[]
        \\
        \\
        \\func hub_ref(sb: Block) -> bytes from sb:
        \\    mut hub = b""
        \\    for inst in sb.instances:
        \\        if len(inst.ref_des) == 0:
        \\            continue
        \\        hub = inst.ref_des
        \\    return hub
        \\
        \\
        \\func main() -> int:
        \\    const sb = Block(instances=[Inst(ref_des=b"R1"), Inst(ref_des=b"U1")])
        \\    return len(hub_ref(sb))
    );
}

// Defect 4 (lane SK's D-SK-5): a plain text or bytes parameter arrives as a view, which lends only a text or bytes result of its
// own kind. A `from` clause whose every source is such a view declares a contract Core cannot state (invalid IR in a Debug or
// `--verify-facts` build); the declaration now refuses it, with the clause's removal as the repair. A clause with a source that
// lends keeps building (lowering drops the view source).
test "CB defect 4 a from clause with no source that can lend the result is refused with its removal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prelude =
        \\record Inst:
        \\    ref_des: bytes
        \\
        \\
    ;
    const main =
        \\
        \\
        \\func main() -> int:
        \\    return 0
    ;
    const text = prelude ++ "func none_of(name: bytes) -> Inst? from name:\n    return None\n" ++ main;
    const checked = try support.checkSource(a, text);
    try std.testing.expect(!checked.passed);
    try std.testing.expectEqualStrings("E_BORROW_SOURCE", checked.diagnostics[0].code);
    try std.testing.expect(std.mem.indexOf(u8, checked.diagnostics[0].message, "no `from` source can lend this result; remove the `from` clause") != null);
    const fix = checked.diagnostics[0].provenance.fix.?;
    try std.testing.expectEqual(@as(usize, 1), fix.count());
    try std.testing.expectEqualStrings(" from name", text[fix.edit.span.start..fix.edit.span.end]);
    try std.testing.expectEqualStrings("", fix.edit.text);
    // A text source cannot lend bytes, nor a bytes source text.
    try std.testing.expect(!(try support.checkSource(a, prelude ++ "func f(code: bytes) -> str from code:\n    return \"a\"\n" ++ main)).passed);
    try std.testing.expect(!(try support.checkSource(a, prelude ++ "func f(code: str) -> bytes from code:\n    return b\"a\"\n" ++ main)).passed);
    // A view of its own kind, a `mut` parameter and a clause with a lending source stay accepted, and build.
    try schedules(a, prelude ++ "func f(name: bytes) -> bytes from name:\n    return name\n\n\nfunc main() -> int:\n    return len(f(b\"ab\"))\n");
    try schedules(a, prelude ++ "func f(mut name: bytes) -> bytes from name:\n    name = name + b\"c\"\n    return name\n\n\nfunc main() -> int:\n    mut s = b\"ab\"\n    return len(f(mut s))\n");
    try schedules(a, prelude ++
        \\func f(xs: Inst[], name: bytes) -> Inst? from xs, name:
        \\    for x in xs:
        \\        if x.ref_des == name:
        \\            return Some(x)
        \\    return None
        \\
        \\
        \\func main() -> int:
        \\    const xs = [Inst(ref_des=b"U1")]
        \\    if f(xs, b"U1") is None:
        \\        return 1
        \\    return 0
        \\
    );
}

/// The generic case of defect 4 (lane HC): `none_of[T](name: bytes, tag: T) -> T? from name` lends for `T = bytes` and not for
/// `T = Inst`, so the language check accepts the declaration and Core's ownership check refuses the instance that cannot lend.
const unlendable_generic =
    \\record Inst:
    \\    ref_des: bytes
    \\
    \\
    \\func none_of[T](name: bytes, tag: T) -> T? from name:
    \\    return None
    \\
    \\
    \\func pick[T](tag: T) -> int[] from tag:
    \\    return []
    \\
    \\
;

/// Check `body` after `unlendable_generic` with the language check, which must accept it, then with Core's ownership check
/// over its source; returns the refusal, if any, and the checked text.
fn instanceRefusal(a: std.mem.Allocator, body: []const u8) !struct { failure: ?unique.Failure, text: []const u8 } {
    const text = try std.mem.concat(a, u8, &.{ unlendable_generic, body });
    const checked = try support.checkSource(a, text);
    try std.testing.expect(checked.passed);
    var failure: unique.Failure = .{};
    unique.checkWithSource(a, checked.program.?, checked.src.?, &failure) catch |err| switch (err) {
        error.Rejected => return .{ .failure = failure, .text = text },
        else => return err,
    };
    return .{ .failure = null, .text = text };
}

test "HC a generic instance whose from sources cannot lend its result is refused at the call that made it, with the clause's removal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const refused = try instanceRefusal(a,
        \\func main() -> int:
        \\    if none_of(b"x", b"y") is None:
        \\        return 0
        \\    if none_of(b"x", Inst(ref_des=b"y")) is None:
        \\        return 1
        \\    return 2
        \\
    );
    const failure = refused.failure.?;
    try std.testing.expectEqualStrings("E_BORROW_SOURCE", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.R4, failure.rule.?);
    try std.testing.expect(std.mem.indexOf(u8, failure.message, "the instance `none_of[Inst]` has no `from` source that can lend its result") != null);
    // At the call that made the instance, with the declaration beside it.
    try std.testing.expect(std.mem.startsWith(u8, refused.text[failure.span.start..failure.span.end], "none_of(b\"x\", Inst("));
    try std.testing.expectEqualStrings("none_of", refused.text[failure.notes.related.?.span.start..failure.notes.related.?.span.end]);
    // Every source is a plain `bytes` parameter: its removal is certain.
    const edits = failure.repair.explicit_fix;
    try std.testing.expectEqual(@as(usize, 1), edits.len);
    try std.testing.expectEqualStrings(" from name", refused.text[edits[0].span.start..edits[0].span.end]);
    try std.testing.expectEqualStrings("", edits[0].text);
    // A type parameter source may lend in another instance, so `pick[bytes]` is refused with no edit.
    const typed_source = (try instanceRefusal(a, "func main() -> int:\n    return len(pick(b\"q\"))\n")).failure.?;
    try std.testing.expectEqualStrings("E_BORROW_SOURCE", typed_source.code);
    try std.testing.expect(std.mem.indexOf(u8, typed_source.message, "`pick[bytes]`") != null);
    try std.testing.expect(typed_source.repair == .none);
    // A list lends only a list of its own element type: `pick[List<bytes>]` cannot lend `int[]` either.
    const other_element = (try instanceRefusal(a, "func main() -> int:\n    return len(pick([b\"q\"]))\n")).failure.?;
    try std.testing.expect(std.mem.indexOf(u8, other_element.message, "`pick[List<bytes>]`") != null);
    // Instances whose sources lend are accepted and build.
    const lending = "func main() -> int:\n    if none_of(b\"x\", b\"y\") is None:\n        return 0\n    return len(pick([1, 2]))\n";
    try std.testing.expect((try instanceRefusal(a, lending)).failure == null);
    try schedules(a, unlendable_generic ++ "func main() -> int:\n    if none_of(b\"x\", b\"y\") is None:\n        return 0\n    return 1\n");
}

// A leaf callee that returns the static empty list under `from` (`return []` beside borrows, 4e): the leaf inliner cloned the
// block-less constants a body reads but not the sentinel, so the inlined `list_view_of` read no value and the fact pass indexed
// past its tables (a Debug compiler panicked in every build mode; lane HC found it on main `41c2b5d5c`).
test "HC a leaf callee returning an empty list under from inlines and builds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.optimizedText(arena.allocator(),
        \\func pick(tag: int[]) -> int[] from tag:
        \\    return []
        \\
        \\
        \\func main() -> int:
        \\    return len(pick([1, 2]))
        \\
    );
    // `pick` is inlined into `main`, which reads the cloned sentinel.
    try std.testing.expect(std.mem.indexOf(u8, text, "fn main") != null);
}
