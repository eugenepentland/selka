//! Source ownership, direct cleanup, and rejection boundaries for zero-RC stage 1.
const std = @import("std");
const language = @import("mylang");
const contract = @import("single_owner.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const zero = @import("zero_rc.zig");
const report = std.debug.print;

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC recursive copies preserve mixed children after original destruction" {
    try executes(std.testing.allocator,
        \\enum Tree:
        \\    leaf(items: dict[str, str[]])
        \\    node(child: Tree)
        \\func score(tree: Tree) -> int:
        \\    match tree:
        \\        case Tree.leaf(items=items):
        \\            return len(items["key-1"][0])
        \\        case Tree.node(child=child):
        \\            return 1 + score(child)
        \\func main(out: Stream) -> int:
        \\    mut tree = Tree.leaf(items={"key-" + str(1): ["value-" + str(1)]})
        \\    for i in range(200):
        \\        tree = Tree.node(child=tree)
        \\    mut original = [tree]
        \\    const saved = original.copy()
        \\    original.clear()
        \\    out.print(score(saved[0]))
        \\    return 0
    , "207\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC owned options deeply copy and pattern borrows cannot escape" {
    try executes(std.testing.allocator,
        \\func size(value: str?) -> int:
        \\    match value:
        \\        case Some(text):
        \\            return len(text)
        \\        case None:
        \\            return 0
        \\func main(out: Stream) -> int:
        \\    mut values: str?[] = [Some("value-" + str(1)), None]
        \\    const saved = values.copy()
        \\    values.clear()
        \\    out.print(size(saved[0]), size(saved[1]))
        \\    return 0
    , "7 0\n");
    try refuses(std.testing.allocator,
        \\enum Value:
        \\    text(value: str)
        \\func escape(owner: Value) -> str:
        \\    match owner:
        \\        case Value.text(value=text):
        \\            return text
        \\func main() -> int:
        \\    return len(escape(Value.text(value="text")))
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC dictionary pop transfers owned values and defaults" {
    try executes(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut values = {1: "value-" + str(1), 2: "value-" + str(2)}
        \\    const first = values.pop(1)
        \\    const second = values.pop(2, "unused-" + str(3))
        \\    const missing = values.pop(3, "fallback-" + str(4))
        \\    values[9] = "unused-" + str(9)
        \\    _ = values.pop(9)
        \\    out.print(first, second, missing, len(values))
        \\    mut keys = {"key-" + str(1), "key-" + str(2)}
        \\    const key = keys.pop()
        \\    keys.clear()
        \\    out.print(key)
        \\    return 0
    , "value-1 value-2 fallback-4 0\nkey-2\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC recursive owned values borrow match payloads" {
    try executes(std.testing.allocator,
        \\enum Expr:
        \\    text(value: str)
        \\    add(left: Expr, right: Expr)
        \\func evaluate(e: Expr) -> int:
        \\    match e:
        \\        case Expr.text(value=v):
        \\            return len(v)
        \\        case Expr.add(left=l, right=r):
        \\            return evaluate(l) + evaluate(r)
        \\func main(out: Stream) -> int:
        \\    const tree = Expr.add(left=Expr.text(value="one-" + str(1)), right=Expr.text(value="two-" + str(2)))
        \\    out.print(evaluate(tree))
        \\    return 0
    , "10\n");
}

// spec: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC dictionaries grow replace and deeply copy managed entries" {
    try executes(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut values: dict[str, str[]] = {}
        \\    for i in range(40):
        \\        values["key-" + str(i)] = ["value-" + str(i)]
        \\    mut saved = values.copy()
        \\    values["key-1"] = ["changed"]
        \\    out.print(values["key-1"][0], saved["key-1"][0], len(saved))
        \\    values.clear()
        \\    out.print(saved["key-2"][0])
        \\    return 0
    , "changed value-1 40\nvalue-2\n");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC dictionaries consume keys and values and reject borrowed extraction" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut values: dict[str, int] = {}
        \\    const key = "key-" + str(1)
        \\    values[key] = 1
        \\    return len(key)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values = {1: "value-" + str(1)}
        \\    const value = values[1]
        \\    return len(value)
    , "E_SINGLE_OWNER_BORROW");
}

const ProjectEntry = struct {
    source: []const u8,
    /// Supply the entry module; embedded standard modules use the normal loader.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        const entry: *ProjectEntry = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        return a.dupe(u8, entry.source);
    }
};

fn checked(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    if (std.mem.startsWith(u8, source, "import ")) {
        var entry: ProjectEntry = .{ .source = source };
        var project: language.embedded_project.Program = undefined;
        try project.init(a, .{ .context = &entry, .read = ProjectEntry.read });
        return project.compilation.program.?;
    }
    var unit = try language.Compilation.init(a, "zero-rc.my", source);
    unit.check() catch |err| {
        for (unit.diagnostics.items) |diagnostic| report("{s} at {d}: {s}\n", .{ diagnostic.code, diagnostic.span.start, diagnostic.message });
        return err;
    };
    return unit.program.?;
}

fn refuses(parent: std.mem.Allocator, source: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    var failure: contract.Failure = .{};
    try std.testing.expectError(error.Rejected, contract.checkMode(arena.allocator(), try checked(arena.allocator(), source), &failure, true));
    try std.testing.expectEqualStrings(code, failure.code);
}

fn executes(parent: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a, source);
    var failure: contract.Failure = .{};
    contract.checkMode(a, program, &failure, true) catch |err| {
        report("zero-RC source: {s} at {d}\n", .{ failure.message, failure.span.start });
        return err;
    };
    const main_fn = program.functions[@backingInt(program.main)];
    const parameter_names = try a.alloc([]const u8, main_fn.signature.parameter_count);
    const capabilities = try a.alloc(u8, parameter_names.len);
    for (parameter_names, capabilities, main_fn.scope.locals[0..parameter_names.len]) |*name, *cap, local| {
        name.* = local.name;
        cap.* = local.ty.capabilityIndex() orelse 255;
    }
    inline for (.{ false, true }) |optimized| {
        var refusal: build.Refusal = .{};
        var module = build.buildExecutable(a, .{ .program = program, .single_owner = true, .zero_rc = true }, &refusal) catch |err| {
            report("zero-RC builder: {s}\n", .{refusal.reason});
            return err;
        };
        const result = if (optimized) try passes.run(a, &module, .verify) else try passes.debug(a, &module);
        contract.verifyLowered(&module, &failure) catch |err| {
            report("zero-RC lowering: {s} at {d}\n{s}\n", .{ failure.message, failure.span.start, try @import("print.zig").module(a, &module) });
            return err;
        };
        const run = support.runOwned(a, &module, .{ .own = false, .release = optimized, .verify = optimized, .analysis = support.analysis(&result), .main = .{ .parameters = parameter_names, .capabilities = capabilities } }) catch |err| {
            report("zero-RC execution (optimized={}):\n{s}\n", .{ optimized, try @import("print.zig").module(a, &module) });
            return err;
        };
        if (run.status != 0) report("zero-RC run:\n{s}{s}\n", .{ run.stdout, run.stderr });
        try std.testing.expectEqual(@as(u8, 0), run.status);
        try std.testing.expectEqualStrings(expected, run.stdout);
        try std.testing.expectEqualStrings("", run.stderr);
        try std.testing.expect(zero.emittedClean(run.llvm));
    }
}

// spec: NEW-CORE-ZERO-RC-1
test "zero RC string and byte ownership rejects aliases and borrowed returns" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const text = "x" + str(7)
        \\    const saved = text
        \\    return len(saved) + len(text)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func keep(text: str) -> str:
        \\    return text
        \\func main() -> int:
        \\    return len(keep("x"))
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const data = bytes(byte_buffer([1, 2]))
        \\    const saved = data
        \\    return len(saved) + len(data)
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut data = byte_buffer([1, 2])
        \\    const saved = data
        \\    _ = data.append_byte(3)
        \\    return len(saved)
    , "E_SINGLE_OWNER_MOVED");
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC strings reject overlapping mutation and record field escapes" {
    try refuses(std.testing.allocator,
        \\func combine(text: str, mut target: str):
        \\    target += text
        \\func main() -> int:
        \\    mut text = "x"
        \\    combine(text, mut text)
        \\    return len(text)
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\record Box:
        \\    text: str
        \\func keep(box: Box) -> str:
        \\    return box.text
        \\func main() -> int:
        \\    return len(keep(Box(text="x")))
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC refuses snapshot and byte views" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values = [1, 2]
        \\    const saved = values.snapshot()
        \\    return len(saved)
    , "E_ZERO_RC_UNSUPPORTED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values = bytes(byte_buffer([1, 2]))
        \\    const saved = values.view(0, 1)
        \\    return len(saved)
    , "E_ZERO_RC_UNSUPPORTED");
}

// spec: NEW-CORE-ZERO-RC-2
test "zero RC text growth copies slices and static ASCII characters execute" {
    try executes(std.testing.allocator,
        \\func segment(text: str) -> str:
        \\    return text[2:5]
        \\func main(out: Stream) -> int:
        \\    mut text = ""
        \\    for i in range(200):
        \\        text += "aλz"
        \\    const old = text.copy()
        \\    const part = segment(text)
        \\    text += text
        \\    const first = part[0]
        \\    const second = part[2]
        \\    out.print(len(old), len(text), first, second, ord(first))
        \\    return 0
    , "600 1200 z λ 122\n");
}

// spec-case: NEW-CORE-ZERO-RC-2
test "zero RC nested records deeply copy text bytes buffers and arrays" {
    try executes(std.testing.allocator,
        \\record Row:
        \\    text: str
        \\    data: bytes
        \\    buffer: byte_buffer
        \\    names: FixedArray[str, 2]
        \\func main(out: Stream) -> int:
        \\    const row = Row(text="row:" + str(7), data=bytes(byte_buffer([8])), buffer=byte_buffer([9]), names=FixedArray[str, 2](["a", "b"]))
        \\    mut rows = [row]
        \\    mut saved = rows.copy()
        \\    rows.clear()
        \\    _ = saved[0].buffer.append_byte(10)
        \\    out.print(saved[0].text, len(saved[0].data), len(saved[0].buffer), saved[0].names[1])
        \\    return 0
    , "row:7 1 2 b\n");
}

// spec-case: NEW-CORE-ZERO-RC-2
test "zero RC buffer and bytes copies preserve independent storage" {
    try executes(std.testing.allocator,
        \\func grow(mut target: byte_buffer):
        \\    _ = target.append_byte(7)
        \\func main(out: Stream) -> int:
        \\    mut buffer = byte_buffer([1, 2])
        \\    const old = bytes(buffer)
        \\    const data = old.copy()
        \\    mut copied = buffer.copy()
        \\    grow(mut buffer)
        \\    _ = copied.append_utf8("λ")
        \\    out.print(len(old), len(data), len(buffer), len(copied))
        \\    return 0
    , "2 2 3 4\n");
}

// spec-case: NEW-CORE-ZERO-RC-2
test "zero RC mut text replacement early returns and loop moves execute" {
    try executes(std.testing.allocator,
        \\func grow(mut text: str):
        \\    text += "λ"
        \\func select(flag: bool) -> str:
        \\    mut text = "value:" + str(9)
        \\    grow(mut text)
        \\    if flag:
        \\        return text
        \\    text = "other"
        \\    return text
        \\func main(out: Stream) -> int:
        \\    mut values: str[] = []
        \\    for i in range(4):
        \\        const text = select(i == 0)
        \\        values.append(text)
        \\    const last = values.pop()
        \\    out.print(values[0], last)
        \\    return 0
    , "value:9λ other\n");
}

// spec: NEW-CORE-ZERO-RC-3
test "zero RC runtime admission and emitted count operations fail closed" {
    try std.testing.expect(zero.contract("myl_core_str_chars") != null);
    try std.testing.expect(zero.contract("myl_core_task_submit") == null);
    try std.testing.expect(zero.contract("foreign_alloc") == null);
    try std.testing.expect(!zero.emittedClean("  %c = load atomic i32, ptr %p unordered, align 8\n"));
    try std.testing.expect(!zero.emittedClean("  call void @myl_core_release(ptr %p)\n"));
    try std.testing.expect(!zero.emittedClean("  call preserve_mostcc void @myl_core_retain_slow(ptr %p)\n"));
    try std.testing.expect(zero.emittedClean("  call void @myl_core_drop_owned(ptr %p)\n"));
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try checked(a,
        \\func main() -> int:
        \\    const value = round(1.234, 2)
        \\    if value > 1.0:
        \\        return 1
        \\    return 0
    );
    var refusal: build.Refusal = .{};
    try std.testing.expectError(error.Unsupported, build.buildExecutable(a, .{ .program = program, .zero_rc = true }, &refusal));
    try std.testing.expect(std.mem.indexOf(u8, refusal.reason, "unaudited zero-RC runtime helper") != null);
}

// spec-case: NEW-CORE-ZERO-RC-1
test "zero RC CLI mode is distinct from earlier single owner mode" {
    const args = @import("cli_args.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var failure: args.Failure = .usage;
    const old = try args.parse(arena.allocator(), .build, &.{ "app.my", "-o", "app", "--experimental-single-owner" }, "zig", &failure);
    const new = try args.parse(arena.allocator(), .build, &.{ "app.my", "-o", "app", "--experimental-zero-rc" }, "zig", &failure);
    try std.testing.expect(!old.build.show.codegen.zero_rc);
    try std.testing.expect(new.build.show.codegen.zero_rc and new.build.show.codegen.single_owner);
}

// spec: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC views cross function boundaries and owned copies survive mutation" {
    try executes(std.testing.allocator,
        \\func segment(source: TextView, start: int) -> TextView:
        \\    return source.borrow(start, start + 3)
        \\func size(source: TextView) -> int:
        \\    return len(source)
        \\func main(out: Stream) -> int:
        \\    mut text = "aλz" + str(7)
        \\    const full = text.borrow(0, len(text))
        \\    const part = segment(full, 1)
        \\    const saved = part.copy()
        \\    out.print(size(part), part, saved, part[0])
        \\    text += "!"
        \\    out.print(saved, len(text))
        \\    return 0
    , "3 λz7 λz7 λ\nλz7 5\n");
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC views borrow mutable byte storage and copy independently" {
    try executes(std.testing.allocator,
        \\func tail(source: ByteView) -> ByteView:
        \\    return source.borrow(1, 99)
        \\func main(out: Stream) -> int:
        \\    mut data = byte_buffer([1, 2, 3, 4])
        \\    const full = data.borrow(0, len(data))
        \\    const part = tail(full)
        \\    const saved = part.copy()
        \\    out.print(len(part), part[-1], part[0])
        \\    _ = data.append_byte(5)
        \\    out.print(len(saved), saved[0], len(data))
        \\    return 0
    , "3 4 2\n3 2 5\n");
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC views reject mutation invalidation escape and ambiguous returns" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut text = "value:" + str(7)
        \\    const view = text.borrow(0, 3)
        \\    text += "changed"
        \\    return len(view)
    , "E_ZERO_RC_VIEW_INVALIDATED");
    try refuses(std.testing.allocator,
        \\func dangling() -> TextView:
        \\    const text = "value:" + str(7)
        \\    return text.borrow(0, 3)
        \\func main() -> int:
        \\    return len(dangling())
    , "E_ZERO_RC_VIEW_SIGNATURE");
    try refuses(std.testing.allocator,
        \\func choose(a: TextView, b: TextView) -> TextView:
        \\    return a
        \\func main() -> int:
        \\    return 0
    , "E_ZERO_RC_VIEW_SIGNATURE");
    try refuses(std.testing.allocator,
        \\func wrong(source: TextView) -> TextView:
        \\    const text = "value:" + str(7)
        \\    return text.borrow(0, 3)
        \\func main() -> int:
        \\    return 0
    , "E_ZERO_RC_VIEW_ESCAPE");
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC views keep transitive owners alive across branches and loops" {
    try executes(std.testing.allocator,
        \\func choose(source: TextView, flag: bool) -> TextView:
        \\    if flag:
        \\        return source.borrow(1, -1)
        \\    return source
        \\func relay(source: TextView, flag: bool) -> TextView:
        \\    return choose(source, flag)
        \\func main(args: str[], out: Stream) -> int:
        \\    const text = "aλ🙂z" + str(7)
        \\    const full = text.borrow(-99, 99)
        \\    const part = relay(full, len(args) == 0)
        \\    mut total = 0
        \\    for i in range(4):
        \\        const item = part.borrow(i, i + 1)
        \\        total += len(item)
        \\    const reversed = full.borrow(3, 1)
        \\    const empty = full.borrow(99, 100)
        \\    out.print(part, part[-2], total, len(reversed), len(empty))
        \\    return 0
    , "λ🙂z 🙂 3 0 0\n");
    try executes(std.testing.allocator,
        \\func last(source: ByteView) -> ByteView:
        \\    return source.borrow(-1, 999)
        \\func main(out: Stream) -> int:
        \\    mut data = byte_buffer([])
        \\    mut total = 0
        \\    for i in range(256):
        \\        _ = data.append_byte(i)
        \\        const view = data.borrow(0, len(data))
        \\        const end = last(view)
        \\        total += end[0]
        \\    out.print(total, len(data))
        \\    return 0
    , "32640 256\n");
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC views reject moves branches loop backedges and overlapping arguments" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const text = "value:" + str(7)
        \\    const view = text.borrow(0, 3)
        \\    const moved = text
        \\    return len(moved) + len(view)
    , "E_ZERO_RC_VIEW_INVALIDATED");
    try refuses(std.testing.allocator,
        \\func probe(flag: bool) -> int:
        \\    mut text = "value:" + str(7)
        \\    const view = text.borrow(0, 3)
        \\    if flag:
        \\        text = "new"
        \\    return len(view)
        \\func main() -> int:
        \\    return probe(True)
    , "E_ZERO_RC_VIEW_INVALIDATED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut text = "value:" + str(7)
        \\    const view = text.borrow(0, 3)
        \\    mut total = 0
        \\    for i in range(3):
        \\        total += len(view) + i
        \\        text += "!"
        \\    return total
    , "E_ZERO_RC_VIEW_INVALIDATED");
    try refuses(std.testing.allocator,
        \\func combine(view: TextView, mut text: str) -> int:
        \\    text += "!"
        \\    return len(view)
        \\func main() -> int:
        \\    mut text = "value:" + str(7)
        \\    const view = text.borrow(0, 3)
        \\    return combine(view, mut text)
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func combine(mut text: str, view: TextView) -> int:
        \\    text += "!"
        \\    return len(view)
        \\func main() -> int:
        \\    mut text = "value:" + str(7)
        \\    const view = text.borrow(0, 3)
        \\    return combine(mut text, view)
    , "E_ZERO_RC_VIEW_INVALIDATED");
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC views refuse aggregate storage mutable bindings and byte rendering" {
    try refuses(std.testing.allocator,
        \\func size(view: TextView) -> int:
        \\    return len(view)
        \\func main() -> int:
        \\    const callback = size
        \\    const text = "abc"
        \\    const view = text.borrow(0, 3)
        \\    return callback(view)
    , "E_ZERO_RC_VIEW_ESCAPE");
    try refuses(std.testing.allocator,
        \\record Holder:
        \\    view: TextView
        \\func main() -> int:
        \\    const text = "value:" + str(7)
        \\    const holder = Holder(view=text.borrow(0, 3))
        \\    return len(holder.view)
    , "E_ZERO_RC_VIEW_ESCAPE");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const text = "value:" + str(7)
        \\    mut view = text.borrow(0, 3)
        \\    return len(view)
    , "E_ZERO_RC_VIEW_UNSUPPORTED");
    try refuses(std.testing.allocator,
        \\func size(mut view: TextView) -> int:
        \\    return len(view)
        \\func main() -> int:
        \\    return 0
    , "E_ZERO_RC_VIEW_SIGNATURE");
    try refuses(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    const data = bytes(byte_buffer([1, 2]))
        \\    const view = data.borrow(0, 2)
        \\    out.print(view)
        \\    return 0
    , "E_ZERO_RC_VIEW_UNSUPPORTED");
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC views retain field and temporary owners and generic copies are owned" {
    try executes(std.testing.allocator,
        \\record Holder:
        \\    text: str
        \\func copied[T: integer](source: TextView, start: T) -> str:
        \\    const part = source.borrow(int(start), 99)
        \\    return part.copy()
        \\func main(out: Stream) -> int:
        \\    const holder = Holder(text="aλz" + str(7))
        \\    const field = holder.text.borrow(1, 3)
        \\    const temporary = ("value:" + str(9)).borrow(0, 99)
        \\    const saved = copied(field, 1)
        \\    out.print(field, temporary, saved)
        \\    return 0
    , "λz value:9 z\n");
}

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC views reject conditional bindings and loop exit invalidation" {
    try refuses(std.testing.allocator,
        \\func choose(source: TextView, flag: bool) -> int:
        \\    const part = if (flag) then (source.borrow(0, 1)) else (source.borrow(1, 2))
        \\    return len(part)
        \\func main() -> int:
        \\    return 0
    , "E_ZERO_RC_VIEW_INVALIDATED");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut text = "value:" + str(7)
        \\    const view = text.borrow(0, 3)
        \\    for i in range(3):
        \\        text += str(i)
        \\        break
        \\    return len(view)
    , "E_ZERO_RC_VIEW_INVALIDATED");
}

// spec-case: NEW-CORE-ZERO-RC-CONTAINERS-1
test "zero RC dictionary parameter mutation and key iteration borrow their owner" {
    try executes(std.testing.allocator,
        \\func replace(mut values: dict[str, str[]], key: str):
        \\    values[key.copy()] = ["replacement-" + str(7)]
        \\    _ = values["key-1"].append("second-" + str(8))
        \\
        \\func score(values: dict[str, str[]]) -> int:
        \\    mut total = 0
        \\    for key in values:
        \\        total += len(values[key])
        \\    return total
        \\
        \\func main(out: Stream) -> int:
        \\    mut values = {"key-" + str(1): ["initial-" + str(2)]}
        \\    replace(mut values, "key-1")
        \\    out.print(score(values), values["key-1"][0], values["key-1"][1])
        \\    return 0
    , "2 replacement-7 second-8\n");
}

// spec-case: NEW-CORE-ZERO-RC-RESOURCES-1
test "zero RC entry provider cleanup directly destroys the root capability" {
    try executes(std.testing.allocator,
        \\func main(fs: Filesystem) -> int:
        \\    with fs.read_only() as readonly:
        \\        assert True
        \\    return 0
    , "");
}

// spec: NEW-CORE-ZERO-RC-RESOURCES-1
test "zero RC scoped files keep a local provider alive through early return" {
    try executes(std.testing.allocator,
        \\import filesystem
        \\func write(fs: Filesystem, fail: bool) -> Result[int, str]:
        \\    with fs.open("log.txt", "w") as file:
        \\        _ = file.write("saved")
        \\        if fail:
        \\            return Err("failed")
        \\        return Ok(7)
        \\func main(out: Stream) -> int:
        \\    const fs = filesystem.memory()
        \\    match write(fs, True):
        \\        case Ok(value):
        \\            out.print(value)
        \\        case Err(message):
        \\            out.print(message)
        \\    with fs.open("log.txt", "r") as file:
        \\        out.print(file.read())
        \\    return 0
    , "failed\nsaved\n");
}

// spec: NEW-CORE-ZERO-RC-RESOURCE-SCOPES-1
test "zero RC scoped capabilities protect parents and close nested files" {
    try executes(std.testing.allocator,
        \\import filesystem
        \\func run(fs: Filesystem) -> Result[int, str]:
        \\    _ = fs.mkdir("logs")
        \\    with fs.dir("logs") as logs:
        \\        with logs.open("one.txt", "w") as file:
        \\            _ = file.write("saved")
        \\        with logs.read_only() as readonly:
        \\            with readonly.open("one.txt", "r") as file:
        \\                assert file.read() == "saved"
        \\                _ = try fs.read_text("missing.txt")
        \\        return Ok(1)
        \\func main(out: Stream) -> int:
        \\    const fs = filesystem.memory()
        \\    match run(fs):
        \\        case Ok(value):
        \\            out.print(value)
        \\        case Err(message):
        \\            out.print(len(message) > 0)
        \\    out.print(fs.exists("logs/one.txt"))
        \\    return 0
    , "True\nTrue\n");
    try refuses(std.testing.allocator,
        \\func escape(fs: Filesystem) -> Filesystem:
        \\    with fs.dir("logs") as child:
        \\        return child
        \\func main() -> int:
        \\    return 0
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\func escape(fs: Filesystem) -> Filesystem:
        \\    return fs.dir("logs")
        \\func main() -> int:
        \\    return 0
    , "E_ZERO_RC_UNSUPPORTED");
}

// spec-case: NEW-CORE-ZERO-RC-RESOURCES-1
test "zero RC foreign scalar calls carry no managed ownership" {
    try executes(std.testing.allocator,
        \\extern func abs(host: Host, value: i32) -> i32 effects(host)
        \\func main(host: Host, out: Stream) -> int:
        \\    out.print(abs(host, -17i32))
        \\    return 0
    , "17\n");
}

// spec: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC library text helpers preserve independent results" {
    try executes(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut source = "  aλb-" + str(7) + "  "
        \\    const trimmed = source.strip()
        \\    const upper = trimmed.upper()
        \\    const changed = trimmed.replace("b", "B")
        \\    const words = trimmed.split("λ")
        \\    const joined = "/".join(words)
        \\    const spaced = (trimmed + "\t" + trimmed).split()
        \\    const lines = (trimmed + "\r\n" + trimmed).splitlines()
        \\    const reverse = trimmed[::-1]
        \\    source = "changed"
        \\    out.print(trimmed, upper, changed, joined, reverse)
        \\    out.print(len(spaced), len(lines), "7".zfill(3), chr(955), ord(chr(955)))
        \\    out.print("Ab".lower(), "123".isdigit(), "Ab".isalpha(), " \t".isspace())
        \\    out.print(trimmed.find("b"), trimmed.rfind("b"), trimmed.count("λ"))
        \\    out.print(f"{trimmed:>6}")
        \\    return 0
    , "aλb-7 AλB-7 aλB-7 a/b-7 7-bλa\n2 2 007 λ 955\nab True True True\n2 2 1\n aλb-7\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC library byte helpers preserve independent results" {
    try executes(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut source = " λ-7 ".encode()
        \\    const trimmed = source.strip()
        \\    const saved = trimmed.hex()
        \\    const tail = trimmed[1:]
        \\    const decoded = trimmed.decode()
        \\    const parsed = bytes.fromhex(saved)
        \\    source = b"changed"
        \\    out.print(saved, tail.hex(), trimmed.find(b"-"))
        \\    match decoded:
        \\        case Ok(text):
        \\            out.print(text)
        \\        case Err(error):
        \\            out.print(error)
        \\    match parsed:
        \\        case Ok(data):
        \\            out.print(data.hex())
        \\        case Err(error):
        \\            out.print(error)
        \\    match b"\xff".decode():
        \\        case Ok(text):
        \\            out.print(text)
        \\        case Err(error):
        \\            out.print(len(error) > 0)
        \\    return 0
    , "cebb2d37 bb2d37 2\nλ-7\ncebb2d37\nTrue\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC library environment preserve independent results" {
    try executes(std.testing.allocator,
        \\import environment
        \\func main(out: Stream) -> int:
        \\    mut values = {"NAME": "value-" + str(7)}
        \\    const env = environment.fixed(values)
        \\    values.clear()
        \\    out.print(len(env.names()))
        \\    match env.get("NAME"):
        \\        case Some(value):
        \\            out.print(value)
        \\        case None:
        \\            out.print("missing")
        \\    return 0
    , "1\nvalue-7\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC explicit value copies support generic records and scalar values" {
    try executes(std.testing.allocator,
        \\record Item:
        \\    texts: str[]
        \\func clone[T: copy + storable](value: T) -> T:
        \\    return value.copy()
        \\func main(out: Stream) -> int:
        \\    mut item = Item(texts=["value-" + str(7)])
        \\    const saved = clone(item)
        \\    item.texts.clear()
        \\    out.print(len(item.texts), saved.texts[0], clone(42))
        \\    return 0
    , "0 value-7 42\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC indexed writes permit bounds reads and copies of indexed text" {
    try executes(std.testing.allocator,
        \\record State:
        \\    values: str[]
        \\func update(mut s: State):
        \\    s.values[-1] = s.values[0].copy()
        \\func encoded() -> bytes:
        \\    return "abc".encode()
        \\func main(out: Stream) -> int:
        \\    mut s = State(values=["value-" + str(7), "other"])
        \\    update(mut s)
        \\    const saved = s.values[-1].copy()
        \\    s.values.clear()
        \\    out.print(saved, len(encoded()))
        \\    return 0
    , "value-7 3\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC encoding borrowed text allocates independent owned bytes" {
    try executes(std.testing.allocator,
        \\func encoded_size(text: str) -> int:
        \\    const data = text.encode()
        \\    return len(data)
        \\func encode(text: str) -> bytes:
        \\    return text.encode()
        \\func main(out: Stream) -> int:
        \\    mut text = "key-" + str(7)
        \\    out.print(encoded_size(text), text)
        \\    const saved = encode(text)
        \\    text = "replacement-" + str(8)
        \\    out.print(saved.hex(), text)
        \\    return 0
    , "5 key-7\n6b65792d37 replacement-8\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC direct enum and fixed array copies keep their owned children" {
    try executes(std.testing.allocator,
        \\enum Value:
        \\    text(value: str)
        \\func clone(value: Value) -> Value:
        \\    return value.copy()
        \\func show(out: Stream, value: Value):
        \\    match value:
        \\        case Value.text(value=text):
        \\            out.print(text)
        \\func main(out: Stream) -> int:
        \\    mut source = Value.text(value="value-" + str(7))
        \\    const saved = clone(source)
        \\    source = Value.text(value="other")
        \\    show(out, saved)
        \\    mut array = FixedArray[str, 2](["first-" + str(1), "second"])
        \\    const copied = array.copy()
        \\    array[0] = "changed"
        \\    out.print(copied[0], array[0])
        \\    return 0
    , "value-7\nfirst-1 changed\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC keyed sort copies nested values and text keys independently" {
    try executes(std.testing.allocator,
        \\record Item:
        \\    name: str
        \\    values: int[]
        \\func key(item: Item) -> str:
        \\    return item.name.copy()
        \\func main(out: Stream) -> int:
        \\    mut values = [Item(name="b-" + str(1), values=[2]), Item(name="a-" + str(1), values=[1])]
        \\    const ordered = sorted(values, key=key)
        \\    values.clear()
        \\    out.print(ordered[0].name, ordered[0].values[0], ordered[1].values[0])
        \\    return 0
    , "a-1 1 2\n");
}

// spec-case: NEW-CORE-ZERO-RC-TASKS-2
test "zero RC source map rejects a callback returning a borrowed owner" {
    try refuses(std.testing.allocator,
        \\import parallel
        \\func alias(value: str) -> str:
        \\    return value
        \\func main() -> int:
        \\    const result = parallel.map(["item-" + str(1)], alias)
        \\    return len(result)
    , "E_SINGLE_OWNER_BORROW");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC copies recursive list and dictionary graphs without compiler expansion" {
    try executes(std.testing.allocator,
        \\enum Tree:
        \\    leaf(value: str)
        \\    branch(children: Tree[])
        \\    mapping(children: dict[str, Tree])
        \\func score(value: Tree) -> int:
        \\    match value:
        \\        case Tree.leaf(value=text):
        \\            return len(text)
        \\        case Tree.branch(children=children):
        \\            return 1 + score(children[0])
        \\        case Tree.mapping(children=children):
        \\            return 1 + score(children["next"])
        \\func main(out: Stream) -> int:
        \\    mut value = Tree.leaf(value="value-" + str(7))
        \\    for i in range(200):
        \\        value = Tree.branch(children=[Tree.mapping(children={"next": value})])
        \\    const saved = value.copy()
        \\    value = Tree.leaf(value="replaced")
        \\    out.print(score(saved))
        \\    return 0
    , "407\n");
}

// spec-case: NEW-CORE-ZERO-RC-LIBRARY-1
test "zero RC copied records preserve function values without owning them" {
    try executes(std.testing.allocator,
        \\record Item:
        \\    text: str
        \\    read: func(int) -> int
        \\func twice(value: int) -> int:
        \\    return value * 2
        \\func main(out: Stream) -> int:
        \\    mut items = [Item(text="item-" + str(7), read=twice)]
        \\    const saved = items.copy()
        \\    items.clear()
        \\    const function = saved[0].read
        \\    out.print(saved[0].text, function(21))
        \\    return 0
    , "item-7 42\n");
}

// spec: NEW-CORE-ZERO-RC-PAYLOAD-TRANSFER-1
test "zero RC payload transfer preserves recursive success errors and mutable writebacks" {
    try executes(std.testing.allocator,
        \\enum Tree:
        \\    leaf(items: dict[str, str[]])
        \\    node(child: Tree)
        \\func score(tree: Tree) -> int:
        \\    match tree:
        \\        case Tree.leaf(items=items):
        \\            return len(items["key-1"][0])
        \\        case Tree.node(child=child):
        \\            return 1 + score(child)
        \\func make(mut count: int, fail: bool) -> Result[Tree, str]:
        \\    count += 1
        \\    if fail:
        \\        return Err("failure-" + str(count))
        \\    mut tree = Tree.leaf(items={"key-" + str(1): ["value-" + str(1)]})
        \\    for i in range(40):
        \\        tree = Tree.node(child=tree)
        \\    return Ok(tree)
        \\func forward(mut count: int, fail: bool) -> Result[Tree, str]:
        \\    const tree = try make(mut count, fail)
        \\    return Ok(tree)
        \\func run(mut count: int, fail: bool) -> Result[int, str]:
        \\    const tree = try forward(mut count, fail)
        \\    const saved = tree.copy()
        \\    return Ok(score(tree) + score(saved))
        \\func main(out: Stream) -> int:
        \\    mut count = 0
        \\    for i in range(3):
        \\        match run(mut count, i == 1):
        \\            case Ok(value):
        \\                out.print(value)
        \\            case Err(message):
        \\                out.print(message)
        \\    out.print(count)
        \\    return 0
    , "94\nfailure-2\n94\n3\n");
}

// spec-case: NEW-CORE-ZERO-RC-PAYLOAD-TRANSFER-1
test "zero RC payload transfer handles wide option values phis and discarded owners" {
    try executes(std.testing.allocator,
        \\record Wide:
        \\    a: str
        \\    b: str
        \\    c: str
        \\    d: str
        \\    e: str
        \\func make(n: int) -> Wide?:
        \\    if n == 0:
        \\        return None
        \\    return Some(Wide(a="a-" + str(n), b="b-" + str(n), c="c-" + str(n), d="d-" + str(n), e="e-" + str(n)))
        \\func forward(n: int) -> Wide?:
        \\    mut result = make(n)
        \\    if n > 2:
        \\        result = make(n + 1)
        \\    const value = try result
        \\    return Some(value)
        \\func discard(n: int) -> int?:
        \\    _ = try make(n)
        \\    return Some(7)
        \\func main(out: Stream) -> int:
        \\    for i in range(4):
        \\        match forward(i):
        \\            case Some(value):
        \\                out.print(value.a, value.e)
        \\            case None:
        \\                out.print("none")
        \\        match discard(i):
        \\            case Some(value):
        \\                out.print(value)
        \\            case None:
        \\                out.print("empty")
        \\    return 0
    , "none\nempty\na-1 e-1\n7\na-2 e-2\n7\na-4 e-4\n7\n");
}

// spec: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match transfers success errors callbacks and popped payloads" {
    try executes(std.testing.allocator,
        \\func make(mut count: int, fail: bool) -> Result[str[], str]:
        \\    count += 1
        \\    if fail:
        \\        return Err("error-" + str(count))
        \\    return Ok(["item-" + str(count)])
        \\func forward(mut count: int, fail: bool) -> Result[str[], str]:
        \\    match make(mut count, fail):
        \\        case Ok(items):
        \\            return Ok(items)
        \\        case Err(message):
        \\            return Err(message)
        \\func text(n: int) -> str?:
        \\    if n == 0:
        \\        return None
        \\    return Some("text-" + str(n))
        \\func invoke(f: func(int) -> str?, n: int) -> str:
        \\    match f(n):
        \\        case Some(value):
        \\            return value
        \\        case None:
        \\            return "none"
        \\func main(out: Stream) -> int:
        \\    mut count = 0
        \\    mut saved: str[] = []
        \\    for i in range(3):
        \\        match forward(mut count, i == 1):
        \\            case Ok(items):
        \\                saved = items
        \\            case Err(message):
        \\                saved.append(message)
        \\        out.print(saved[0], len(saved))
        \\    mut values: str?[] = [text(7)]
        \\    match values.pop():
        \\        case Some(value):
        \\            saved.append(value)
        \\        case None:
        \\            assert False
        \\    out.print(saved[0], saved[1], invoke(text, 0), invoke(text, 8), count)
        \\    return 0
    , "item-1 1\nitem-1 2\nitem-3 1\nitem-3 text-7 none text-8 3\n");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match rejects repeated moves and keeps named matches borrowed" {
    try refuses(std.testing.allocator,
        \\func make() -> str?:
        \\    return Some("item-" + str(1))
        \\func main() -> int:
        \\    match make():
        \\        case Some(value):
        \\            const saved = value
        \\            return len(saved) + len(value)
        \\        case None:
        \\            return 0
    , "E_SINGLE_OWNER_MOVED");
    try refuses(std.testing.allocator,
        \\func extract(value: str?) -> str:
        \\    match value:
        \\        case Some(text):
        \\            return text
        \\        case None:
        \\            return "none"
        \\func main() -> int:
        \\    return len(extract(Some("value")))
    , "E_SINGLE_OWNER_OVERLAP");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const saved: str? = Some("item-" + str(1))
        \\    match saved:
        \\        case Some(value):
        \\            const moved = value
        \\            return len(moved)
        \\        case None:
        \\            return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match still borrows projected unions" {
    try refuses(std.testing.allocator,
        \\record Holder:
        \\    value: str?
        \\func make() -> Holder:
        \\    return Holder(value=Some("item-" + str(1)))
        \\func main() -> int:
        \\    match make().value:
        \\        case Some(value):
        \\            const moved = value
        \\            return len(moved)
        \\        case None:
        \\            return 0
    , "E_SINGLE_OWNER_BORROW");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const values: str?[] = [Some("item-" + str(1))]
        \\    match values[0]:
        \\        case Some(value):
        \\            const moved = value
        \\            return len(moved)
        \\        case None:
        \\            return 0
    , "E_SINGLE_OWNER_OVERLAP");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match moves explicit copies independently and discards unused cases" {
    try executes(std.testing.allocator,
        \\func make(n: int) -> str[]?:
        \\    return Some(["item-" + str(n)])
        \\func main(out: Stream) -> int:
        \\    mut original = make(1)
        \\    mut saved: str[] = []
        \\    match original.copy():
        \\        case Some(value):
        \\            saved = value
        \\        case None:
        \\            assert False
        \\    original = make(2)
        \\    match make(3):
        \\        case Some(_):
        \\            out.print(saved[0], len(saved))
        \\        case None:
        \\            assert False
        \\    match make(4):
        \\        case Some(unused):
        \\            out.print(saved[0], len(saved))
        \\        case None:
        \\            assert False
        \\    match original:
        \\        case Some(value):
        \\            out.print(value[0])
        \\        case None:
        \\            assert False
        \\    return 0
    , "item-1 1\nitem-1 1\nitem-2\n");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match transfers constructed unions through loop exits" {
    try executes(std.testing.allocator,
        \\enum Item:
        \\    text(value: str[])
        \\func forward(n: int) -> Result[str[], str]:
        \\    if n == 0:
        \\        return Ok([])
        \\    if n == 1:
        \\        return Err("error-" + str(n))
        \\    return Ok(["item-" + str(n)])
        \\func main(out: Stream) -> int:
        \\    mut saved: str[] = []
        \\    for i in range(4):
        \\        match forward(i):
        \\            case Ok(items):
        \\                if len(items) == 0:
        \\                    continue
        \\                saved = items
        \\                break
        \\            case Err(message):
        \\                out.print(message)
        \\    match Item.text(value=["extra-" + str(7)]):
        \\        case Item.text(value=items):
        \\            out.print(saved[0], items[0])
        \\    return 0
    , "error-1\nitem-2 extra-7\n");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match transfers decoded text bytes and validation errors" {
    try executes(std.testing.allocator,
        \\func decode(data: bytes) -> str:
        \\    match data.decode():
        \\        case Ok(text):
        \\            return text
        \\        case Err(message):
        \\            return message
        \\func hex(text: str) -> Result[bytes, str]:
        \\    match bytes.fromhex(text):
        \\        case Ok(data):
        \\            return Ok(data)
        \\        case Err(message):
        \\            return Err(message)
        \\func count(data: bytes) -> str:
        \\    match data.scalar_count():
        \\        case Ok(size):
        \\            return str(size)
        \\        case Err(message):
        \\            return message
        \\func main(out: Stream) -> int:
        \\    out.print(decode(bytes([97, 98])), decode(bytes([255])))
        \\    out.print(count(bytes([97, 98])), count(bytes([255])))
        \\    match hex("6162"):
        \\        case Ok(data):
        \\            out.print(decode(data))
        \\        case Err(message):
        \\            out.print(message)
        \\    match hex("z"):
        \\        case Ok(data):
        \\            out.print(decode(data))
        \\        case Err(message):
        \\            out.print(message)
        \\    return 0
    , "ab invalid UTF-8 in byte string\n2 invalid UTF-8 in byte string\nab\nhexadecimal text requires an even number of hex digits\n");
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match JSON decoding and rendering return owned strings" {
    try executes(std.testing.allocator,
        \\import json
        \\func main(out: Stream) -> int:
        \\    match json.loads("\"item\""):
        \\        case Ok(value):
        \\            out.print(json.dumps(value))
        \\        case Err(_):
        \\            assert False
        \\    return 0
    , "\"item\"\n");
}
