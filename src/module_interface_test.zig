//! Module interface artifacts (MODULE-INTERFACE-1..3): what an interface keeps,
//! when its hash changes, and that a module checked against its imports'
//! interfaces alone reports what the whole program reports.
const source_names = @import("source_names.zig");
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const iface = language.module_interface;
const oracle = language.module_interface_oracle;
const effect_set = language.effect_set;

const shapes_source =
    \\
    \\
    \\public record Inner:
    \\    x: int
    \\
    \\
    \\public record Outer:
    \\    items: Inner[]
    \\
;

const lib_source =
    \\import shapes
    \\
    \\
    \\const LIMIT: int = 10
    \\
    \\
    \\record Scratch:
    \\    note: int
    \\
    \\
    \\public func firsts(o: shapes.Outer) -> shapes.Inner[]:
    \\    return o.items
    \\
    \\
    \\public func count(o: shapes.Outer) -> int:
    \\    mut total = 0
    \\    for item in o.items:
    \\        total += item.x
    \\    return total + 3
    \\
    \\
    \\func helper(n: int) -> int:
    \\    if n > 100:
    \\        return helper(n - 1)
    \\    return n + LIMIT
    \\
    \\
    \\public func twice(x: int) -> int:
    \\    return x * 2
    \\
    \\
    \\public func first[T](values: T[]) -> T:
    \\    return values[helper(0) - LIMIT]
    \\
    \\
    \\@deprecated("use count")
    \\public func old_count(o: shapes.Outer) -> int:
    \\    return count(o)
    \\
    \\
    \\func triangle(n: int) -> int:
    \\    mut total = 0
    \\    for k in range(n):
    \\        total += k + LIMIT
    \\    return total
    \\
    \\
    \\public const TRIANGLE: int = triangle(4)
    \\
;

const main_source =
    \\import shapes
    \\import lib
    \\
    \\
    \\func main() -> int:
    \\    mut o = shapes.Outer(items=[shapes.Inner(x=1)])
    \\    mut xs = lib.firsts(o)
    \\    return lib.count(o) + lib.twice(xs[0].x) + lib.first([1, 2]) + lib.old_count(o) + lib.TRIANGLE
    \\
;

/// The three-module project with `lib` and `shapes` replaced where given.
const Sources = struct { lib: []const u8 = lib_source, shapes: []const u8 = shapes_source };

/// One whole-program check of the project and every module's interface.
const Built = struct {
    whole: *oracle.Whole,
    set: language.module_interface_build.Set,

    fn deinit(self: Built) void {
        self.whole.deinit();
    }

    fn module(self: Built, name: []const u8) iface.Interface {
        for (self.set.interfaces) |interface| if (std.mem.eql(u8, interface.module, name)) return interface;
        @panic("no such module");
    }

    fn position(self: Built, name: []const u8) usize {
        for (self.set.interfaces, 0..) |interface, index| if (std.mem.eql(u8, interface.module, name)) return index;
        @panic("no such module");
    }

    fn hash(self: Built, name: []const u8) [32]u8 {
        return self.set.interface_hashes[self.position(name)];
    }

    fn implementation(self: Built, name: []const u8) [32]u8 {
        return self.set.implementation_hashes[self.position(name)];
    }

    /// The role of the function `module::name` in its module's interface.
    fn role(self: Built, name: []const u8, function: []const u8) ?iface.Role {
        for (self.module(name).declarations.functions) |entry| {
            if (std.mem.endsWith(u8, entry.key, function) and entry.key[entry.key.len - function.len - 1] == 0x1f) return entry.role;
        }
        return null;
    }
};

fn build(sources: Sources) !Built {
    const modules = [_]oracle.Override{
        .{ .path = source_names.library, .bytes = sources.lib },
        .{ .path = "shapes.selka", .bytes = sources.shapes },
    };
    var whole: *oracle.Whole = undefined;
    oracle.Whole.open(t.allocator, t.io, .{ .root = "", .name = "main", .bytes = main_source, .modules = &modules }, &whole) catch |err| {
        if (err != error.OutOfMemory) whole.deinit();
        return err;
    };
    errdefer whole.deinit();
    return .{ .whole = whole, .set = try whole.buildInterfaces() };
}

/// The interface hash of `module` in the project with `sources`.
fn hashOf(sources: Sources, module: []const u8) ![32]u8 {
    const built = try build(sources);
    defer built.deinit();
    return built.hash(module);
}

/// `text` with the first `old` replaced by `new`, owned by `arena`.
fn edit(arena: std.mem.Allocator, text: []const u8, old: []const u8, new: []const u8) ![]const u8 {
    const at = std.mem.indexOf(u8, text, old) orelse return error.TestUnexpectedResult;
    return std.mem.concat(arena, u8, &.{ text[0..at], new, text[at + old.len ..] });
}

fn changed(a: [32]u8, b: [32]u8) bool {
    return !std.mem.eql(u8, &a, &b);
}

/// One module checked against the others' interfaces, compared with the whole program.
fn checkAgainstInterfaces(arena: std.mem.Allocator, built: Built, library: *oracle.Library, module: []const u8) !oracle.Comparison {
    const reference = try built.whole.result(arena);
    const bytes = if (std.mem.eql(u8, module, "main")) main_source else if (std.mem.eql(u8, module, "lib")) lib_source else shapes_source;
    var single: *oracle.Single = undefined;
    oracle.Single.open(t.allocator, .{ .module = module, .bytes = bytes, .is_entry = std.mem.eql(u8, module, "main"), .library = library }, &single) catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    defer single.deinit();
    const result = try single.result(arena, library, module);
    var comparison = try oracle.compare(arena, reference, result, module);
    if (!single.declaredOnly()) comparison.unmapped += 1;
    return comparison;
}

/// The interfaces of `built`, encoded and decoded, as a library.
fn libraryOf(arena: std.mem.Allocator, built: Built) !oracle.Library {
    const list = try arena.alloc(iface.Interface, built.set.interfaces.len);
    for (built.set.interfaces, list) |interface, *decoded| decoded.* = iface.decode(arena, try iface.encode(arena, interface)) orelse return error.TestUnexpectedResult;
    return oracle.Library.of(arena, list);
}

fn hasShape(interface: iface.Interface, name: []const u8) bool {
    for (interface.declarations.shapes) |shape| if (std.mem.eql(u8, shape.name, name)) return true;
    return false;
}

/// Add `effects` to the facts of the function whose key ends in `suffix`.
fn claim(functions: []iface.Function, suffix: []const u8, effects: effect_set.Mask) bool {
    for (functions) |*function| if (std.mem.endsWith(u8, function.key, suffix)) {
        function.fact.graph_mask |= effects;
        return true;
    };
    return false;
}

fn mismatches(comparison: oracle.Comparison) usize {
    return comparison.mismatches();
}

// spec: MODULE-INTERFACE-1
test "an interface keeps each exported declaration and what it reaches, and only the bodies a dependent reads" {
    const built = try build(.{});
    defer built.deinit();
    const lib = built.module("lib");
    try t.expectEqualStrings("lib", lib.module);
    try t.expectEqual(@as(usize, 1), lib.imports.len);
    try t.expectEqualStrings("shapes", lib.imports[0]);
    // A declared body is `pass`; the facts that stand in for it travel beside it.
    try t.expect(std.mem.indexOf(u8, lib.text, "public func count(o: shapes.Outer) -> int:\n    pass") != null);
    try t.expectEqual(iface.Role.declared, built.role("lib", "count").?);
    // A template keeps its body, and the private helper and constant it names come along.
    try t.expect(std.mem.indexOf(u8, lib.text, "return values[helper(0) - LIMIT]") != null);
    try t.expectEqual(iface.Role.template, built.role("lib", "first").?);
    try t.expectEqual(iface.Role.declared, built.role("lib", "helper").?);
    try t.expectEqual(iface.Role.constant, built.role("lib", "LIMIT").?);
    // A small leaf is declared like any other body; the deprecation stays on its declaration.
    try t.expectEqual(iface.Role.declared, built.role("lib", "twice").?);
    try t.expect(std.mem.indexOf(u8, lib.text, "return x * 2") == null);
    try t.expect(std.mem.indexOf(u8, lib.text, "@deprecated(\"use count\")\npublic func old_count") != null);
    // A constant is evaluated where it is used, running the bodies it calls.
    try t.expectEqual(iface.Role.constant, built.role("lib", "TRIANGLE").?);
    try t.expectEqual(iface.Role.evaluated, built.role("lib", "triangle").?);
    try t.expect(std.mem.indexOf(u8, lib.text, "total += k + LIMIT") != null);
    // A private record nothing exported reaches is not part of the interface.
    try t.expect(std.mem.indexOf(u8, lib.text, "Scratch") == null);
    // `firsts` returns `list[shapes.Inner]`: the foreign record's shape is covered.
    try t.expect(hasShape(lib, "shapes::Inner"));
    // The artifact is self-contained, canonical and deterministic.
    const bytes = try iface.encode(t.allocator, lib);
    defer t.allocator.free(bytes);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const decoded = iface.decode(arena.allocator(), bytes).?;
    try t.expectEqualSlices(u8, &built.hash("lib"), &iface.interfaceHash(decoded));
    const again = try build(.{});
    defer again.deinit();
    const second = try iface.encode(t.allocator, again.module("lib"));
    defer t.allocator.free(second);
    try t.expectEqualSlices(u8, bytes, second);
    try t.expectEqualSlices(u8, &built.implementation("main"), &again.implementation("main"));
}

// spec-case: MODULE-INTERFACE-1
test "an interface artifact rejects a foreign version, a truncated payload and a failed allocation" {
    const built = try build(.{});
    defer built.deinit();
    const bytes = try iface.encode(t.allocator, built.module("shapes"));
    defer t.allocator.free(bytes);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expect(iface.decode(arena.allocator(), bytes[0 .. bytes.len - 1]) == null);
    const foreign = try std.mem.concat(arena.allocator(), u8, &.{ bytes, "x" });
    try t.expect(iface.decode(arena.allocator(), foreign) == null);
    const renamed = try arena.allocator().dupe(u8, bytes);
    renamed[8] = 'X';
    try t.expect(iface.decode(arena.allocator(), renamed) == null);
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    try t.expectError(error.OutOfMemory, iface.encode(failing.allocator(), built.module("shapes")));
}

// spec-case: MODULE-INTERFACE-2
test "embedded content and outcomes invalidate the source implementation identity" {
    var inputs = [_]language.source.Embed{.{ .literal = .{ .start = 0, .end = 1 }, .path = "asset", .status = .ok, .digest = @splat(1) }};
    const src: language.source.Source = .{ .path = source_names.library, .bytes = "unchanged", .line_starts = &.{0}, .embeds = &inputs };
    const first = iface.implementationHash("lib", src, &.{});
    inputs[0].digest = @splat(2);
    try t.expect(changed(first, iface.implementationHash("lib", src, &.{})));
    inputs[0].digest = @splat(1);
    inputs[0].status = .missing;
    try t.expect(changed(first, iface.implementationHash("lib", src, &.{})));
}

// spec: MODULE-INTERFACE-2
test "a body-only edit keeps the interface hash and changes only the implementation hash" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const base = try build(.{});
    defer base.deinit();
    const edited = try build(.{ .lib = try edit(arena.allocator(), lib_source, "total + 3", "total + 4") });
    defer edited.deinit();
    try t.expectEqualSlices(u8, &base.hash("lib"), &edited.hash("lib"));
    try t.expect(changed(base.implementation("lib"), edited.implementation("lib")));
    // Its importers compile to the same objects: their implementation hashes hold.
    try t.expectEqualSlices(u8, &base.implementation("main"), &edited.implementation("main"));
    // A declaration moved down the file moves positions, not the interface.
    const moved = try build(.{ .lib = try edit(arena.allocator(), lib_source, "import shapes\n", "import shapes\n\n\n# a comment\n") });
    defer moved.deinit();
    try t.expectEqualSlices(u8, &base.hash("lib"), &moved.hash("lib"));
    try t.expect(changed(iface.positionsHash(base.module("lib")), iface.positionsHash(moved.module("lib"))));
    // An unreachable private declaration is not part of the interface either.
    const private = try build(.{ .lib = try edit(arena.allocator(), lib_source, "    note: int", "    note: bool") });
    defer private.deinit();
    try t.expectEqualSlices(u8, &base.hash("lib"), &private.hash("lib"));
}

// spec-case: MODULE-INTERFACE-2
test "every edit a dependent can observe changes the interface hash" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try hashOf(.{}, "lib");
    // A signature, a fact, a template body, a constant and a deprecation.
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "count(o: shapes.Outer) -> int", "count(o: shapes.Outer, bias: int = 0) -> int") }, "lib")));
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "    mut total = 0\n", "    mut total = 0\n    const extra: int[] = [1]\n    total += len(extra)\n") }, "lib")));
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "values[helper(0) - LIMIT]", "values[helper(1) - LIMIT - 1]") }, "lib")));
    // A small leaf's body is a declared body like any other: no dependent reads it.
    try t.expectEqualSlices(u8, &base, &(try hashOf(.{ .lib = try edit(a, lib_source, "x * 2", "x * 3") }, "lib")));
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "LIMIT: int = 10", "LIMIT: int = 11") }, "lib")));
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "total += k + LIMIT", "total += k + LIMIT + 1") }, "lib")));
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "use count", "use count instead") }, "lib")));
    // A private helper's fact reaches the interface through the template that
    // calls it; no declared function calls it.
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "    return n + LIMIT", "    const grow: int[] = [n]\n    return len(grow) + LIMIT") }, "lib")));
    // A field added to a record `lib` reaches only through `list[shapes.Inner]`
    // changes `shapes` and `lib` alike.
    const reshaped = try edit(a, shapes_source, "    x: int\n", "    x: int\n    y: int = 0\n");
    try t.expect(changed(try hashOf(.{}, "shapes"), try hashOf(.{ .shapes = reshaped }, "shapes")));
    try t.expect(changed(base, try hashOf(.{ .shapes = reshaped }, "lib")));
}

// spec: MODULE-INTERFACE-3
test "a module checked against its imports' interfaces reports what the whole program reports" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const built = try build(.{});
    defer built.deinit();
    var library = try libraryOf(arena.allocator(), built);
    const main = try checkAgainstInterfaces(arena.allocator(), built, &library, "main");
    const lib = try checkAgainstInterfaces(arena.allocator(), built, &library, "lib");
    const shapes = try checkAgainstInterfaces(arena.allocator(), built, &library, "shapes");
    try t.expectEqual(@as(usize, 0), mismatches(main) + mismatches(lib) + mismatches(shapes));
    // `main` read `lib`'s bodies from nowhere: its facts stood in, and it
    // instantiated `lib.first[int]` from the template the interface carries.
    try t.expect(main.functions.compared > 3);
    try t.expectEqual(@as(usize, 1), main.contexts.compared);
    try t.expectEqual(@as(usize, 8), lib.contexts.compared);
    // The deprecation warning at `main`'s call site is the whole program's.
    try t.expectEqual(@as(usize, 1), main.diagnostics.len);
    try t.expect(std.mem.indexOf(u8, main.diagnostics[0], "W_DEPRECATED") != null);
    const whole = try built.whole.result(arena.allocator());
    const comparisons = [_]oracle.Comparison{ main, lib, shapes };
    try t.expectEqual(@as(usize, 0), (try oracle.missingDiagnostics(arena.allocator(), whole, &comparisons)).len);
}

// spec-case: MODULE-INTERFACE-3
test "a wrong fact in an interface makes the per-module check differ from the whole program" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const built = try build(.{});
    defer built.deinit();
    const list = try arena.allocator().dupe(iface.Interface, built.set.interfaces);
    const lib = &list[built.position("lib")];
    const functions = try arena.allocator().dupe(iface.Function, lib.declarations.functions);
    lib.declarations.functions = functions;
    // Claim `count` reads the filesystem, which its body never does.
    try t.expect(claim(functions, "\x1fcount", effect_set.bit(.filesystem)));
    var library = try oracle.Library.of(arena.allocator(), list);
    const main = try checkAgainstInterfaces(arena.allocator(), built, &library, "main");
    try t.expect(mismatches(main) != 0);
}

/// Write every interface of `built` as `<module>.selkai` into `dir`.
fn writeArtifacts(dir: std.Io.Dir, arena: std.mem.Allocator, built: Built) !void {
    for (built.set.interfaces) |interface| {
        try dir.writeFile(t.io, .{ .sub_path = try iface.fileName(arena, interface.module), .data = try iface.encode(arena, interface) });
    }
}

// spec-case: MODULE-INTERFACE-3
test "a library read from a directory decodes only the interfaces a check imports" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const built = try build(.{});
    defer built.deinit();
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try writeArtifacts(temporary.dir, arena.allocator(), built);
    const directory = try temporary.dir.realPathFileAlloc(t.io, ".", arena.allocator());
    var library = oracle.Library.stored(.{ .io = t.io, .directory = directory, .arena = arena.allocator() });
    // `shapes` imports nothing: its check decodes no artifact at all.
    var single: *oracle.Single = undefined;
    try oracle.Single.open(t.allocator, .{ .module = "shapes", .bytes = shapes_source, .is_entry = false, .library = &library }, &single);
    single.deinit();
    try t.expectEqual(@as(u32, 0), library.by_name.count());
    // `main` imports `shapes` and `lib`: exactly those two are read.
    try oracle.Single.open(t.allocator, .{ .module = "main", .bytes = main_source, .is_entry = true, .library = &library }, &single);
    defer single.deinit();
    try t.expect(single.declaredOnly());
    try t.expectEqual(@as(u32, 2), library.by_name.count());
    try t.expect(library.text("absent.selka") == null);
}

// spec-case: MODULE-INTERFACE-3
test "module interfaces retain nested static error pattern declarations" {
    const text =
        \\enum ParseError:
        \\    invalid
        \\    empty
        \\func parse() -> int fails ParseError:
        \\    fail ParseError.invalid
        \\public func check() -> bool:
        \\    match parse():
        \\        case Ok(value):
        \\            return False
        \\        case Err(ParseError.invalid):
        \\            return True
        \\        case Err(ParseError.empty):
        \\            return False
        \\func main() -> int:
        \\    return 0
    ;
    var whole: *oracle.Whole = undefined;
    try oracle.Whole.open(t.allocator, t.io, .{ .root = "", .name = "main", .bytes = text }, &whole);
    defer whole.deinit();
    _ = try whole.buildInterfaces();
}
