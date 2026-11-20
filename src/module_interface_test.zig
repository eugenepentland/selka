//! Module interface artifacts (MODULE-INTERFACE-1..3): what an interface keeps,
//! when its hash changes, and that a module checked against its imports'
//! interfaces alone reports what the whole program reports.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const iface = language.module_interface;
const oracle = language.module_interface_oracle;
/// A broken role pin says why on standard error (`expectPinnedRoles`).
const print = std.debug.print;

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
    \\    return copy(o.items)
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

/// The three-module project with `main`, `lib` and `shapes` replaced where given.
const Sources = struct { lib: []const u8 = lib_source, shapes: []const u8 = shapes_source, main: []const u8 = main_source };

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
        .{ .path = "lib.selka", .bytes = sources.lib },
        .{ .path = "shapes.selka", .bytes = sources.shapes },
    };
    var whole: *oracle.Whole = undefined;
    oracle.Whole.open(t.allocator, t.io, .{ .root = "", .name = "main", .bytes = sources.main, .modules = &modules }, &whole) catch |err| {
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

/// Tamper with the retained mutation fact of the function whose key ends in `suffix`.
fn claim(functions: []iface.Function, suffix: []const u8) bool {
    for (functions) |*function| if (std.mem.endsWith(u8, function.key, suffix)) {
        function.fact.mutates = &.{0};
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
    // A private constant a kept template body names comes along with it.
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
// spec: SYNTAX-RETIREMENT-CACHE-1
// spec: TUPLE-CLAUSE-RETIREMENT-CACHE-1
// spec: TYPED-METADATA-CACHE-1
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
    // The previous serialized layout must miss even with otherwise valid bytes.
    const previous = try arena.allocator().dupe(u8, bytes);
    const old_version = "module-interface-v12";
    try t.expectEqual(old_version.len, iface.format_version.len);
    @memcpy(previous[8 .. 8 + old_version.len], old_version);
    try t.expect(iface.decode(arena.allocator(), previous) == null);
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    try t.expectError(error.OutOfMemory, iface.encode(failing.allocator(), built.module("shapes")));
}

// spec-case: MODULE-INTERFACE-2
test "embedded content and outcomes invalidate the source implementation identity" {
    var inputs = [_]language.source.Embed{.{ .literal = .{ .start = 0, .end = 1 }, .path = "asset", .status = .ok, .digest = @splat(1) }};
    const src: language.source.Source = .{ .path = "lib.selka", .bytes = "unchanged", .line_starts = &.{0}, .embeds = &inputs };
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

/// `lib` with one public function added whose body is `body` (a text of `s`).
fn withBorrowProbe(arena: std.mem.Allocator, body: []const u8) ![]const u8 {
    return std.mem.concat(arena, u8, &.{ lib_source, "\n\npublic func borrow_probe(s: str) -> str from s:\n    return ", body, "\n" });
}

test "O3 module interface declared borrowing excludes body-only origin changes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try hashOf(.{ .lib = try withBorrowProbe(a, "s[1:3]") }, "lib");
    // Another slice of the same parameter: the set is still {s}, so the interface keeps its hash.
    try t.expectEqualSlices(u8, &base, &(try hashOf(.{ .lib = try withBorrowProbe(a, "s[0:2]") }, "lib")));
    // A fresh implementation still satisfies the same declared upper bound.
    try t.expectEqualSlices(u8, &base, &(try hashOf(.{ .lib = try withBorrowProbe(a, "copy(s[1:3])") }, "lib")));
}

// spec-case: MODULE-INTERFACE-2
test "every edit a dependent can observe changes the interface hash" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try hashOf(.{}, "lib");
    // A signature, a fact, a template body, a constant and a deprecation.
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "count(o: shapes.Outer) -> int", "count(o: shapes.Outer, bias: int = 0) -> int") }, "lib")));
    try t.expectEqualSlices(u8, &base, &(try hashOf(.{ .lib = try edit(a, lib_source, "    mut total = 0\n", "    mut total = 0\n    const extra: int[] = [1]\n    total += len(extra)\n") }, "lib")));
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "values[helper(0) - LIMIT]", "values[helper(1) - LIMIT - 1]") }, "lib")));
    // A small leaf's body is a declared body like any other: no dependent reads it.
    try t.expectEqualSlices(u8, &base, &(try hashOf(.{ .lib = try edit(a, lib_source, "x * 2", "x * 3") }, "lib")));
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "LIMIT: int = 10", "LIMIT: int = 11") }, "lib")));
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "total += k + LIMIT", "total += k + LIMIT + 1") }, "lib")));
    try t.expect(changed(base, try hashOf(.{ .lib = try edit(a, lib_source, "use count", "use count instead") }, "lib")));
    // Templates read the private helper's declaration, so its body-only local
    // allocation changes implementation evidence while preserving the interface.
    const original = try build(.{});
    defer original.deinit();
    const helper_edit = try build(.{ .lib = try edit(a, lib_source, "    return n + LIMIT", "    const grow: int[] = [n]\n    return len(grow) + LIMIT") });
    defer helper_edit.deinit();
    try t.expectEqualSlices(u8, &original.hash("lib"), &helper_edit.hash("lib"));
    try t.expect(changed(original.implementation("lib"), helper_edit.implementation("lib")));
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
    // The checked trees of the bodies a module's own check kept are compared by digest too: `main` keeps one body, `lib`
    // its own, and the imports' bodies it never had are not compared.
    try t.expect(main.trees.compared >= 1);
    try t.expect(lib.trees.compared >= 7);
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

/// The tree digest of the checked function whose name ends with `name`, from a whole-program result.
fn treeOf(result: oracle.Result, name: []const u8) ?[32]u8 {
    for (result.functions) |function| if (std.mem.endsWith(u8, function.name, name)) return function.tree;
    return null;
}

// spec-case: MODULE-INTERFACE-3
test "a checked function's tree digest moves with its body and with nothing else of the project" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try build(.{});
    defer base.deinit();
    const at = std.mem.indexOf(u8, lib_source, "return total + 3") orelse return error.TestUnexpectedResult;
    const edited = try std.mem.concat(a, u8, &.{ lib_source[0..at], "return total + 4", lib_source[at + "return total + 3".len ..] });
    const reedited = try build(.{ .lib = edited });
    defer reedited.deinit();
    const before = try base.whole.result(a);
    const after = try reedited.whole.result(a);
    try t.expect(treeOf(before, "count") != null);
    try t.expect(!std.mem.eql(u8, &treeOf(before, "count").?, &treeOf(after, "count").?));
    try t.expectEqualSlices(u8, &treeOf(before, "twice").?, &treeOf(after, "twice").?);
    try t.expectEqualSlices(u8, &treeOf(before, "main").?, &treeOf(after, "main").?);
    // A line added above every declaration moves them all and changes no digest.
    const moved = try std.mem.concat(a, u8, &.{ "# a note\n", lib_source });
    const shifted = try build(.{ .lib = moved });
    defer shifted.deinit();
    const later = try shifted.whole.result(a);
    try t.expectEqualSlices(u8, &treeOf(before, "count").?, &treeOf(later, "count").?);
    try t.expectEqualSlices(u8, &treeOf(before, "triangle").?, &treeOf(later, "triangle").?);
}

// spec-case: MODULE-INTERFACE-3
test "O3 module interface stand-in metadata cannot override the source contract" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const built = try build(.{});
    defer built.deinit();
    const list = try arena.allocator().dupe(iface.Interface, built.set.interfaces);
    const lib = &list[built.position("lib")];
    const functions = try arena.allocator().dupe(iface.Function, lib.declarations.functions);
    lib.declarations.functions = functions;
    // A stand-in implementation footprint cannot change a declaration contract.
    try t.expect(claim(functions, "\x1fcount"));
    var library = try oracle.Library.of(arena.allocator(), list);
    const main = try checkAgainstInterfaces(arena.allocator(), built, &library, "main");
    try t.expectEqual(@as(usize, 0), mismatches(main));
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
        \\        case Err(invalid):
        \\            return True
        \\        case Err(empty):
        \\            return False
        \\func main() -> int:
        \\    return 0
    ;
    var whole: *oracle.Whole = undefined;
    try oracle.Whole.open(t.allocator, t.io, .{ .root = "", .name = "main", .bytes = text }, &whole);
    defer whole.deinit();
    _ = try whole.buildInterfaces();
}

const view_main_source =
    \\import texts
    \\
    \\
    \\func main() -> int:
    \\    return len(texts.head("abcdefgh"))
    \\
;

/// The project whose one module `texts` holds `texts_text`, built and interfaced.
fn textsBuilt(texts_text: []const u8) !Built {
    const modules = [_]oracle.Override{.{ .path = "texts.selka", .bytes = texts_text }};
    var whole: *oracle.Whole = undefined;
    oracle.Whole.open(t.allocator, t.io, .{ .root = "", .name = "main", .bytes = view_main_source, .modules = &modules }, &whole) catch |err| {
        if (err != error.OutOfMemory) whole.deinit();
        return err;
    };
    errdefer whole.deinit();
    return .{ .whole = whole, .set = try whole.buildInterfaces() };
}

/// The view answer the interface stores for the function whose key ends in `function`.
fn storedView(built: Built, function: []const u8) ?u16 {
    for (built.module("texts").declarations.functions) |entry| {
        if (std.mem.endsWith(u8, entry.key, function)) return switch (entry.fact.return_origin) {
            .params => |positions| if (positions.len == 1) positions[0] else null,
            .fresh, .unknown => null,
        };
    }
    return null;
}

// spec-case: MODULE-INTERFACE-3
test "O3 module interface declared return source is part of its hash" {
    const view = try textsBuilt("public func head(source: str) -> str from source:\n    return source[0:4]\n");
    defer view.deinit();
    const copied = try textsBuilt("public func head(source: str) -> str:\n    return copy(source[0:4])\n");
    defer copied.deinit();
    try t.expectEqual(@as(?u16, 0), storedView(view, "head"));
    try t.expectEqual(@as(?u16, null), storedView(copied, "head"));
    try t.expect(changed(view.hash("texts"), copied.hash("texts")));
}

test "O3 module interface source order is neutral and declaration changes invalidate" {
    const first = try textsBuilt("public func head(source: str, other: str = \"unused\") -> str from other, source:\n    return source[0:4]\n");
    defer first.deinit();
    const reordered = try textsBuilt("public func head(source: str, other: str = \"unused\") -> str from source,other:\n    return source[0:4]\n");
    defer reordered.deinit();
    const narrowed = try textsBuilt("public func head(source: str, other: str = \"unused\") -> str from source:\n    return source[0:4]\n");
    defer narrowed.deinit();
    try t.expectEqualSlices(u8, &first.hash("texts"), &reordered.hash("texts"));
    try t.expect(changed(first.hash("texts"), narrowed.hash("texts")));
}

test "O3 module interface codec preserves declared source positions above 63" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const original: iface.Interface = .{ .module = "texts", .text = "", .declarations = .{ .functions = &.{.{
        .key = "fn\x1ftexts\x1f\x1fhead",
        .role = .declared,
        .exported = true,
        .fact = .{ .mutates = &.{69}, .return_origin = .{ .params = &.{ 0, 69 } } },
        .fingerprint = @splat(0),
    }} } };
    const decoded = iface.decode(allocator, try iface.encode(allocator, original)) orelse return error.TestUnexpectedResult;
    try t.expectEqualSlices(u16, &.{ 0, 69 }, decoded.declarations.functions[0].fact.return_origin.params);
    try t.expectEqualSlices(u16, &.{69}, decoded.declarations.functions[0].fact.mutates);
    try t.expectEqualSlices(u8, &iface.interfaceHash(original), &iface.interfaceHash(decoded));
}

/// The interface roles in declaration order, each with whether a function of that role keeps its body in the interface
/// text. This is the closed list of reasons a dependent module reads another module's function body (goal G7 of
/// `docs/goals.md`, work item W9).
const pinned_roles = "declared:pass template:body constant:body conversion:body foreign:body evaluated:body";

/// `module_interface.Role` as `pinned_roles` spells it, written into `buffer`.
fn roleList(buffer: []u8) ![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    for (std.enums.values(iface.Role), 0..) |role, index| {
        if (index != 0) try writer.writeByte(' ');
        try writer.print("{s}:{s}", .{ @tagName(role), if (role.keepsBody()) "body" else "pass" });
    }
    return writer.buffered();
}

/// Why the role list may not change silently, with both lists, when `actual` is not `pinned_roles`; null when it is.
fn pinBroken(allocator: std.mem.Allocator, actual: []const u8) !?[]const u8 {
    if (std.mem.eql(u8, actual, pinned_roles)) return null;
    const message = try std.fmt.allocPrint(allocator,
        \\module_interface.Role changed. A new reason for a dependent module to read a function's body, a role removed or
        \\renamed, or a role that newly keeps or drops its body, is the user's decision under goal G7 (docs/goals.md: a
        \\caller is judged from signatures alone). Record that decision under G7, then update this pin.
        \\  pinned: {s}
        \\  now:    {s}
        \\
    , .{ pinned_roles, actual });
    return message;
}

/// Fail with `pinBroken`'s message when the role list is not the pinned one.
fn expectPinnedRoles(actual: []const u8) !void {
    const message = try pinBroken(t.allocator, actual) orelse return;
    defer t.allocator.free(message);
    print("{s}", .{message});
    return error.TestUnexpectedResult;
}

// W9: locality is a tested property (goal G7).
test "W9 the interface roles are a closed list and only declared bodies are replaced by pass" {
    var buffer: [256]u8 = undefined;
    try expectPinnedRoles(try roleList(&buffer));
    // A seventh role, or a role that drops its body, breaks the pin and names the goal.
    const added = (try pinBroken(t.allocator, pinned_roles ++ " inlined:body")).?;
    defer t.allocator.free(added);
    try t.expect(std.mem.indexOf(u8, added, "goal G7") != null);
    const dropped = (try pinBroken(t.allocator, "declared:pass template:body constant:body conversion:pass foreign:body evaluated:body")).?;
    defer t.allocator.free(dropped);
    try t.expect(std.mem.indexOf(u8, dropped, "user's decision") != null);
}

/// One function for each interface role, and ordinary functions with every declaration feature that must not change a
/// function's role.
const roles_lib_source =
    \\public record Small:
    \\    n: int
    \\
    \\
    \\public record Wide:
    \\    n: int
    \\
    \\
    \\const LIMIT: int = 10
    \\
    \\
    \\public func pick[T](xs: T[]) -> T:
    \\    return xs[LIMIT - 10]
    \\
    \\
    \\public conversion func widen(x: Small) -> Wide:
    \\    return Wide(n=x.n)
    \\
    \\
    \\public extern func c_abs(host: Host, value: i32) -> i32
    \\
    \\
    \\func steps(n: int) -> int:
    \\    mut total = 0
    \\    for k in range(n):
    \\        total += k
    \\    return total
    \\
    \\
    \\public const TOTAL: int = steps(3)
    \\
    \\
    \\public func head(xs: str[]) -> str from xs:
    \\    return xs[0]
    \\
    \\
    \\public func grow(mut xs: int[]):
    \\    append(mut xs, LIMIT)
    \\
    \\
    \\@requires(n > 0, "n is positive")
    \\public func halve(n: int) -> int:
    \\    return n // 2
    \\
    \\
    \\@noalloc
    \\public func double(n: int) -> int:
    \\    return n * 2
    \\
    \\
    \\public func parse(text: str) -> int fails i64:
    \\    if len(text) == 0:
    \\        fail 1
    \\    return len(text)
    \\
    \\
    \\public func outer(n: int) -> int:
    \\    return inner(n) + 1
    \\
    \\
    \\func inner(n: int) -> int:
    \\    return n
    \\
    \\
    \\public func keep(own xs: int[]) -> int[]:
    \\    return xs
    \\
;

const roles_main_source =
    \\import lib
    \\
    \\
    \\func main() -> int:
    \\    return lib.halve(4) + lib.TOTAL + lib.outer(1)
    \\
;

test "W9 roleOf by example: each role once, and no declaration feature makes an ordinary function keep its body" {
    const built = try build(.{ .lib = roles_lib_source, .main = roles_main_source });
    defer built.deinit();
    try t.expectEqual(iface.Role.template, built.role("lib", "pick").?);
    try t.expectEqual(iface.Role.constant, built.role("lib", "TOTAL").?);
    // A private constant a kept template body names comes along with it.
    try t.expectEqual(iface.Role.constant, built.role("lib", "LIMIT").?);
    try t.expectEqual(iface.Role.conversion, built.role("lib", "widen").?);
    try t.expectEqual(iface.Role.foreign, built.role("lib", "c_abs").?);
    try t.expectEqual(iface.Role.evaluated, built.role("lib", "steps").?);
    // A `from` result, a `mut` parameter, `@requires`, `@noalloc`, a `fails` clause, an `own` parameter and a call
    // to a private helper are all part of the signature or the body: none of them keeps a body.
    try t.expectEqual(iface.Role.declared, built.role("lib", "head").?);
    try t.expectEqual(iface.Role.declared, built.role("lib", "grow").?);
    try t.expectEqual(iface.Role.declared, built.role("lib", "halve").?);
    try t.expectEqual(iface.Role.declared, built.role("lib", "double").?);
    try t.expectEqual(iface.Role.declared, built.role("lib", "parse").?);
    try t.expectEqual(iface.Role.declared, built.role("lib", "keep").?);
    try t.expectEqual(iface.Role.declared, built.role("lib", "outer").?);
    // The private helper an ordinary body calls is not part of the interface at all: no declaration text names it.
    try t.expectEqual(@as(?iface.Role, null), built.role("lib", "inner"));
    const lib = built.module("lib");
    try t.expect(std.mem.indexOf(u8, lib.text, "return inner(n) + 1") == null);
    try t.expect(std.mem.indexOf(u8, lib.text, "fail 1") == null);
    try t.expect(std.mem.indexOf(u8, lib.text, "return xs[LIMIT - 10]") != null);
    try t.expect(std.mem.indexOf(u8, lib.text, "total += k") != null);
}

// spec-case: W10-ROLE-1
test "W10 a builtin func takes the declared role, generic or not: it has no body for a dependent to read" {
    const span: language.source.Span = .{ .start = 0, .end = 0 };
    const type_parameter: language.ast.TypeParameter = .{ .name = span, .requirements = &.{} };
    const generic: language.ast.Function = .{ .policy = .{ .builtin = true }, .signature = .{ .type_parameters = &.{type_parameter}, .parameters = &.{}, .return_type = span }, .name = span, .body = @fromBackingInt(0) };
    const plain: language.ast.Function = .{ .policy = .{ .builtin = true }, .signature = .{ .parameters = &.{}, .return_type = span }, .name = span, .body = @fromBackingInt(0) };
    try t.expectEqual(iface.Role.declared, language.module_interface_build.roleOf(generic));
    try t.expectEqual(iface.Role.declared, language.module_interface_build.roleOf(plain));
    try t.expect(!iface.Role.declared.keepsBody());
}

/// The oracle's comparison of the test file `lib_test` with the whole program, served `lib` as its interface or, with
/// `tested`, as its full source (`Whole.testedSource`).
fn checkTestFile(arena: std.mem.Allocator, whole: *oracle.Whole, library: *oracle.Library, bytes: []const u8, tested: bool) !oracle.Comparison {
    const reference = try whole.result(arena);
    const source = if (tested) try whole.testedSource(0) else null;
    var single: *oracle.Single = undefined;
    oracle.Single.open(t.allocator, .{ .module = "lib_test", .bytes = bytes, .is_entry = true, .library = library, .tested = source }, &single) catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    defer single.deinit();
    const checked = try single.result(arena, library, "lib_test");
    const result = if (source) |found| try oracle.withoutModule(arena, checked, found.module) else checked;
    return oracle.compare(arena, reference, result, "lib_test");
}

// FX10: a test file may name its module's private declarations, which no interface carries. Checked against `lib`'s
// interface, the test file's call of the private `page` is an unknown name and its contexts differ; served `lib`'s full
// source, as the oracle now serves a test file the module it tests, it agrees with the whole program.
test "the oracle checks a test file against the full source of the module it tests" {
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const lib = "func page(n: int) -> int:\n    return n + 1\n\npublic func serve() -> int:\n    return page(1)\n";
    const tester = "import lib\n\npublic func test_page() -> bool:\n    return lib.page(1) == 2\n" ++ oracle.main_stub;
    const modules = [_]oracle.Override{.{ .path = "lib.selka", .bytes = lib }};
    var whole: *oracle.Whole = undefined;
    try oracle.Whole.open(t.allocator, t.io, .{ .root = "", .name = "lib_test", .bytes = tester, .modules = &modules }, &whole);
    defer whole.deinit();
    const set = try whole.buildInterfaces();
    const list = try arena.alloc(iface.Interface, set.interfaces.len);
    for (set.interfaces, list) |interface, *decoded| decoded.* = iface.decode(arena, try iface.encode(arena, interface)) orelse return error.TestUnexpectedResult;
    var library = try oracle.Library.of(arena, list);
    try t.expectEqualStrings("lib", (try whole.testedSource(0)).?.module);
    const against_interface = try checkTestFile(arena, whole, &library, tester, false);
    try t.expect(mismatches(against_interface) != 0);
    const against_source = try checkTestFile(arena, whole, &library, tester, true);
    try t.expectEqual(@as(usize, 0), mismatches(against_source));
}
