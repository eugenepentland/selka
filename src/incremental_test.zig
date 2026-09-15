//! Stable identity and interface-fingerprint behavior across body and signature edits.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const incremental = @import("incremental.zig");
const File = struct { path: []const u8, bytes: []const u8 };
const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        for (self.entries) |entry| if (std.mem.eql(u8, entry.path, path)) {
            if (entry.bytes.len > limit) return error.TooLarge;
            return allocator.dupe(u8, entry.bytes);
        };
        return error.NotFound;
    }
};
const test_contract: incremental.Contract = .{ .compiler_sha256 = "test-compiler-v1", .target_abi = "x86_64-linux-gnu" };

fn describe(entries: []const File, allocator: std.mem.Allocator) !incremental.Report {
    return describeWith(entries, allocator, test_contract);
}

fn describeWith(entries: []const File, allocator: std.mem.Allocator, contract: incremental.Contract) !incremental.Report {
    var files: Files = .{ .entries = entries };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    return incremental.describe(allocator, &compilation, contract);
}
fn declaration(report: incremental.Report, module: []const u8, name: []const u8) incremental.Declaration {
    for (report.modules) |unit| if (std.mem.eql(u8, unit.name, module)) {
        for (unit.declarations) |item| if (std.mem.eql(u8, item.name, name)) return item;
    };
    unreachable;
}

// spec: INCREMENTAL-ID-1
test "module and declaration identities ignore body edits and interface fingerprints follow signatures" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\import data
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        },
        .{ .path = "data.my", .bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value() -> i64 effects():
        \\    return 41
        },
    };
    const first = try describe(&entries, t.allocator);
    defer incremental.deinit(first, t.allocator);
    const first_identity = declaration(first, "data", "value").identity;
    const first_body = declaration(first, "data", "value").body_sha256.?;
    const first_interface = first.project_interface_sha256;

    entries[1].bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value() -> i64 effects():
        \\    # a comment in the body
        \\    return 41
    ;
    const second = try describe(&entries, t.allocator);
    defer incremental.deinit(second, t.allocator);
    try t.expectEqualStrings(first_identity, declaration(second, "data", "value").identity);
    try t.expect(!std.mem.eql(u8, first_body, declaration(second, "data", "value").body_sha256.?));
    try t.expectEqualStrings(first_interface, second.project_interface_sha256);

    entries[1].bytes =
        \\module data
        \\export value
        \\
        \\
        \\def value(step: i64) -> i64 effects():
        \\    return 41 + step
    ;
    const third = try describe(&entries, t.allocator);
    defer incremental.deinit(third, t.allocator);
    try t.expect(!std.mem.eql(u8, first_interface, third.project_interface_sha256));
}

fn moduleIdentityOf(report: incremental.Report, name: []const u8) []const u8 {
    for (report.modules) |unit| if (std.mem.eql(u8, unit.name, name)) return unit.identity;
    unreachable;
}

fn nominal(report: incremental.Report, name: []const u8) incremental.Nominal {
    for (report.types) |item| if (std.mem.eql(u8, item.name, name)) return item;
    unreachable;
}

test "whitespace and comment edits preserve module, declaration, interface and body identities" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\def value() -> i64:
        \\    return 41
        \\
        \\
        \\def helper() -> i64:
        \\    return value()
        \\
        \\
        \\def main() -> i64:
        \\    return helper()
        },
    };
    const first = try describe(&entries, t.allocator);
    defer incremental.deinit(first, t.allocator);
    const first_module = try t.allocator.dupe(u8, moduleIdentityOf(first, "main"));
    defer t.allocator.free(first_module);
    const first_value = declaration(first, "main", "value");
    const first_helper = declaration(first, "main", "helper");
    const first_value_identity = try t.allocator.dupe(u8, first_value.identity);
    defer t.allocator.free(first_value_identity);
    const first_value_interface = try t.allocator.dupe(u8, first_value.interface_sha256.?);
    defer t.allocator.free(first_value_interface);
    const first_value_body = try t.allocator.dupe(u8, first_value.body_sha256.?);
    defer t.allocator.free(first_value_body);
    const first_helper_identity = try t.allocator.dupe(u8, first_helper.identity);
    defer t.allocator.free(first_helper_identity);
    const first_helper_body = try t.allocator.dupe(u8, first_helper.body_sha256.?);
    defer t.allocator.free(first_helper_body);

    entries[0].bytes =
        \\module main
        \\# a comment before the declarations
        \\
        \\
        \\def value() -> i64:
        \\    return 41
        \\
        \\
        \\# a comment between declarations
        \\def helper() -> i64:
        \\    return value()
        \\
        \\
        \\def main() -> i64:
        \\    return helper()
    ;
    const second = try describe(&entries, t.allocator);
    defer incremental.deinit(second, t.allocator);
    try t.expectEqualStrings(first_module, moduleIdentityOf(second, "main"));
    try t.expectEqualStrings(first_value_identity, declaration(second, "main", "value").identity);
    try t.expectEqualStrings(first_value_interface, declaration(second, "main", "value").interface_sha256.?);
    try t.expectEqualStrings(first_value_body, declaration(second, "main", "value").body_sha256.?);
    try t.expectEqualStrings(first_helper_identity, declaration(second, "main", "helper").identity);
    try t.expectEqualStrings(first_helper_body, declaration(second, "main", "helper").body_sha256.?);

    entries[0].bytes =
        \\module main
        \\
        \\
        \\def value() -> i64:
        \\    # a comment inside the body
        \\    return 41
        \\
        \\
        \\def helper() -> i64:
        \\    return value()
        \\
        \\
        \\def main() -> i64:
        \\    return helper()
    ;
    const third = try describe(&entries, t.allocator);
    defer incremental.deinit(third, t.allocator);
    try t.expectEqualStrings(first_value_identity, declaration(third, "main", "value").identity);
    try t.expectEqualStrings(first_value_interface, declaration(third, "main", "value").interface_sha256.?);
    try t.expect(!std.mem.eql(u8, first_value_body, declaration(third, "main", "value").body_sha256.?));
    try t.expectEqualStrings(first_helper_identity, declaration(third, "main", "helper").identity);
    try t.expectEqualStrings(first_helper_body, declaration(third, "main", "helper").body_sha256.?);
}

test "private body edits preserve identities while signature edits change the interface hash" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\def helper(x: i64) -> i64:
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return helper(1)
        },
    };
    const first = try describe(&entries, t.allocator);
    defer incremental.deinit(first, t.allocator);
    const first_helper = declaration(first, "main", "helper");
    const identity = try t.allocator.dupe(u8, first_helper.identity);
    defer t.allocator.free(identity);
    const interface = try t.allocator.dupe(u8, first_helper.interface_sha256.?);
    defer t.allocator.free(interface);

    entries[0].bytes =
        \\module main
        \\
        \\
        \\def helper(x: i64) -> i64:
        \\    return x + 1
        \\
        \\
        \\def main() -> i64:
        \\    return helper(1)
    ;
    const second = try describe(&entries, t.allocator);
    defer incremental.deinit(second, t.allocator);
    try t.expectEqualStrings(identity, declaration(second, "main", "helper").identity);
    try t.expectEqualStrings(interface, declaration(second, "main", "helper").interface_sha256.?);

    entries[0].bytes =
        \\module main
        \\
        \\
        \\def helper(x: i64, y: i64) -> i64:
        \\    return x + y
        \\
        \\
        \\def main() -> i64:
        \\    return helper(1, 2)
    ;
    const third = try describe(&entries, t.allocator);
    defer incremental.deinit(third, t.allocator);
    try t.expectEqualStrings(identity, declaration(third, "main", "helper").identity);
    try t.expect(!std.mem.eql(u8, interface, declaration(third, "main", "helper").interface_sha256.?));
}

test "effect-bound edits change the function interface hash" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\def touch() -> i64 effects(clock):
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return touch()
        },
    };
    const first = try describe(&entries, t.allocator);
    defer incremental.deinit(first, t.allocator);
    const identity = try t.allocator.dupe(u8, declaration(first, "main", "touch").identity);
    defer t.allocator.free(identity);
    const interface = try t.allocator.dupe(u8, declaration(first, "main", "touch").interface_sha256.?);
    defer t.allocator.free(interface);

    entries[0].bytes =
        \\module main
        \\
        \\
        \\def touch() -> i64 effects(random):
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return touch()
    ;
    const second = try describe(&entries, t.allocator);
    defer incremental.deinit(second, t.allocator);
    try t.expectEqualStrings(identity, declaration(second, "main", "touch").identity);
    try t.expect(!std.mem.eql(u8, interface, declaration(second, "main", "touch").interface_sha256.?));
}

test "an exported body edit inside its declared ceiling preserves the API fingerprint and still changes the body hash" {
    const output_body =
        \\module main
        \\export emit
        \\
        \\
        \\def emit() -> i64 effects(output, managed_allocation):
        \\    print("x")
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    return emit()
    ;
    const allocation_body =
        \\module main
        \\export emit
        \\
        \\
        \\def emit() -> i64 effects(output, managed_allocation):
        \\    items: list[i64] = []
        \\    items.append(1)
        \\    return items[0]
        \\
        \\
        \\def main() -> i64:
        \\    return emit()
    ;
    var entries = [_]File{.{ .path = "main.my", .bytes = output_body }};
    const first = try describe(&entries, t.allocator);
    defer incremental.deinit(first, t.allocator);
    const first_interface = try t.allocator.dupe(u8, declaration(first, "main", "emit").interface_sha256.?);
    defer t.allocator.free(first_interface);
    const first_body = try t.allocator.dupe(u8, declaration(first, "main", "emit").body_sha256.?);
    defer t.allocator.free(first_body);

    entries[0].bytes = allocation_body;
    const second = try describe(&entries, t.allocator);
    defer incremental.deinit(second, t.allocator);
    // Declared ceilings are the published contract: two bodies inside the same
    // bound keep the same API fingerprint (and every consumer's type check).
    try t.expectEqualStrings(first_interface, declaration(second, "main", "emit").interface_sha256.?);
    try t.expectEqualStrings(first.project_interface_sha256, second.project_interface_sha256);
    // The implementation still changed, so body cacheability and runtime-test
    // receipts keyed on the body must invalidate.
    try t.expect(!std.mem.eql(u8, first_body, declaration(second, "main", "emit").body_sha256.?));
}

test "record field and union case edits change the nominal interface hash" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\class Point:
        \\    x: i64
        \\
        \\
        \\union Event:
        \\    count: i64,
        \\    flag: bool
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        },
    };
    const first = try describe(&entries, t.allocator);
    defer incremental.deinit(first, t.allocator);
    const point_identity = try t.allocator.dupe(u8, nominal(first, "main::Point").identity);
    defer t.allocator.free(point_identity);
    const point_interface = try t.allocator.dupe(u8, nominal(first, "main::Point").interface_sha256.?);
    defer t.allocator.free(point_interface);
    const event_identity = try t.allocator.dupe(u8, nominal(first, "main::Event").identity);
    defer t.allocator.free(event_identity);
    const event_interface = try t.allocator.dupe(u8, nominal(first, "main::Event").interface_sha256.?);
    defer t.allocator.free(event_interface);

    entries[0].bytes =
        \\module main
        \\
        \\
        \\class Point:
        \\    x: i64
        \\    y: i64
        \\
        \\
        \\union Event:
        \\    count: i64,
        \\    flag: bool
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    const second = try describe(&entries, t.allocator);
    defer incremental.deinit(second, t.allocator);
    try t.expectEqualStrings(point_identity, nominal(second, "main::Point").identity);
    try t.expect(!std.mem.eql(u8, point_interface, nominal(second, "main::Point").interface_sha256.?));

    entries[0].bytes =
        \\module main
        \\
        \\
        \\class Point:
        \\    x: i64
        \\
        \\
        \\union Event:
        \\    count: i64,
        \\    flag: bool,
        \\    empty
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    ;
    const third = try describe(&entries, t.allocator);
    defer incremental.deinit(third, t.allocator);
    try t.expectEqualStrings(event_identity, nominal(third, "main::Event").identity);
    try t.expect(!std.mem.eql(u8, event_interface, nominal(third, "main::Event").interface_sha256.?));
}

test "inserting a declaration or comment does not change a later declaration identity" {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\def later() -> i64:
        \\    return 7
        \\
        \\
        \\def main() -> i64:
        \\    return later()
        },
    };
    const first = try describe(&entries, t.allocator);
    defer incremental.deinit(first, t.allocator);
    const identity = try t.allocator.dupe(u8, declaration(first, "main", "later").identity);
    defer t.allocator.free(identity);
    const interface = try t.allocator.dupe(u8, declaration(first, "main", "later").interface_sha256.?);
    defer t.allocator.free(interface);

    entries[0].bytes =
        \\module main
        \\# inserted comment
        \\
        \\
        \\def inserted() -> i64:
        \\    return 1
        \\
        \\
        \\def later() -> i64:
        \\    return 7
        \\
        \\
        \\def main() -> i64:
        \\    return later()
    ;
    const second = try describe(&entries, t.allocator);
    defer incremental.deinit(second, t.allocator);
    try t.expectEqualStrings(identity, declaration(second, "main", "later").identity);
    try t.expectEqualStrings(interface, declaration(second, "main", "later").interface_sha256.?);
}

test "specializationIdentity includes arguments, provider, target ABI and compiler identity" {
    const base = try incremental.specializationIdentity(t.allocator, "template", "args", "provider", "target", "compiler");
    defer t.allocator.free(base);
    const same = try incremental.specializationIdentity(t.allocator, "template", "args", "provider", "target", "compiler");
    defer t.allocator.free(same);
    try t.expectEqualStrings(base, same);
    for ([_][6][]const u8{
        .{ "template2", "args", "provider", "target", "compiler", "" },
        .{ "template", "args2", "provider", "target", "compiler", "" },
        .{ "template", "args", "provider2", "target", "compiler", "" },
        .{ "template", "args", "provider", "target2", "compiler", "" },
        .{ "template", "args", "provider", "target", "compiler2", "" },
    }) |variant| {
        const changed = try incremental.specializationIdentity(t.allocator, variant[0], variant[1], variant[2], variant[3], variant[4]);
        defer t.allocator.free(changed);
        try t.expect(!std.mem.eql(u8, base, changed));
    }
}

test "typeIdentity distinguishes a nominal type from a generic template of the same name" {
    const nominal_identity = try incremental.typeIdentity(t.allocator, "main", "record", "Box");
    defer t.allocator.free(nominal_identity);
    const template_identity = try incremental.typeIdentity(t.allocator, "main", "record-template", "Box");
    defer t.allocator.free(template_identity);
    try t.expect(!std.mem.eql(u8, nominal_identity, template_identity));
    const stable = try incremental.typeIdentity(t.allocator, "main", "record", "Box");
    defer t.allocator.free(stable);
    try t.expectEqualStrings(nominal_identity, stable);
}

// spec: INCREMENTAL-INTERFACE-1
test "project interface follows exported constants and effect ceilings but not comments" {
    const consts_41 =
        \\module main
        \\export K
        \\
        \\
        \\const K: i64 = 41
        \\
        \\
        \\def main() -> i64:
        \\    return K
    ;
    const consts_42 =
        \\module main
        \\export K
        \\
        \\
        \\const K: i64 = 42
        \\
        \\
        \\def main() -> i64:
        \\    return K
    ;
    var consts = [_]File{.{ .path = "main.my", .bytes = consts_41 }};
    const c0 = try describe(&consts, t.allocator);
    defer incremental.deinit(c0, t.allocator);
    consts[0].bytes = consts_42;
    const c1 = try describe(&consts, t.allocator);
    defer incremental.deinit(c1, t.allocator);
    try t.expect(!std.mem.eql(u8, c0.project_interface_sha256, c1.project_interface_sha256));

    const effect_clock =
        \\module main
        \\export tick
        \\
        \\
        \\def tick() -> i64 effects(clock):
        \\    return 1
        \\
        \\
        \\def main() -> i64:
        \\    return tick()
    ;
    const effect_random =
        \\module main
        \\export tick
        \\
        \\
        \\def tick() -> i64 effects(random):
        \\    return 1
        \\
        \\
        \\def main() -> i64:
        \\    return tick()
    ;
    var effects = [_]File{.{ .path = "main.my", .bytes = effect_clock }};
    const e0 = try describe(&effects, t.allocator);
    defer incremental.deinit(e0, t.allocator);
    effects[0].bytes = effect_random;
    const e1 = try describe(&effects, t.allocator);
    defer incremental.deinit(e1, t.allocator);
    try t.expect(!std.mem.eql(u8, e0.project_interface_sha256, e1.project_interface_sha256));

    const generic =
        \\module main
        \\export id
        \\
        \\
        \\def id[T](n: T) -> T effects():
        \\    return n
        \\
        \\
        \\def main() -> i64:
        \\    return id[i64](41)
    ;
    const generic_comment =
        \\module main
        \\# unrelated comment before the generic
        \\export id
        \\
        \\
        \\def id[T](n: T) -> T effects():
        \\    return n
        \\
        \\
        \\def main() -> i64:
        \\    return id[i64](41)
    ;
    var generic_files = [_]File{.{ .path = "main.my", .bytes = generic }};
    const g0 = try describe(&generic_files, t.allocator);
    defer incremental.deinit(g0, t.allocator);
    generic_files[0].bytes = generic_comment;
    const g1 = try describe(&generic_files, t.allocator);
    defer incremental.deinit(g1, t.allocator);
    try t.expectEqualStrings(g0.project_interface_sha256, g1.project_interface_sha256);
}

// spec-case: INCREMENTAL-INTERFACE-1
test "default argument values change the declaration interface" {
    const default_41 =
        \\module main
        \\export value
        \\
        \\
        \\def value(n: i64 = 41) -> i64 effects():
        \\    return n
        \\
        \\
        \\def main() -> i64:
        \\    return value()
    ;
    const default_42 =
        \\module main
        \\export value
        \\
        \\
        \\def value(n: i64 = 42) -> i64 effects():
        \\    return n
        \\
        \\
        \\def main() -> i64:
        \\    return value()
    ;
    var entries = [_]File{.{ .path = "main.my", .bytes = default_41 }};
    const d0 = try describe(&entries, t.allocator);
    defer incremental.deinit(d0, t.allocator);
    const interface_zero = declaration(d0, "main", "value").interface_sha256.?;
    entries[0].bytes = default_42;
    const d1 = try describe(&entries, t.allocator);
    defer incremental.deinit(d1, t.allocator);
    const interface_one = declaration(d1, "main", "value").interface_sha256.?;
    try t.expect(!std.mem.eql(u8, interface_zero, interface_one));
    try t.expect(!std.mem.eql(u8, d0.project_interface_sha256, d1.project_interface_sha256));
}

test "keyword parameter names and generic requirements stay in the public contract" {
    const named_step =
        \\module main
        \\export value
        \\
        \\
        \\def value(step: i64 = 1) -> i64 effects():
        \\    return step
        \\
        \\
        \\def main() -> i64:
        \\    return value()
    ;
    const named_n =
        \\module main
        \\export value
        \\
        \\
        \\def value(n: i64 = 1) -> i64 effects():
        \\    return n
        \\
        \\
        \\def main() -> i64:
        \\    return value()
    ;
    var entries = [_]File{.{ .path = "main.my", .bytes = named_step }};
    const named_first = try describe(&entries, t.allocator);
    defer incremental.deinit(named_first, t.allocator);
    const named_interface = try t.allocator.dupe(u8, declaration(named_first, "main", "value").interface_sha256.?);
    defer t.allocator.free(named_interface);
    entries[0].bytes = named_n;
    const named_second = try describe(&entries, t.allocator);
    defer incremental.deinit(named_second, t.allocator);
    try t.expect(!std.mem.eql(u8, named_interface, declaration(named_second, "main", "value").interface_sha256.?));
    try t.expect(!std.mem.eql(u8, named_first.project_interface_sha256, named_second.project_interface_sha256));

    const unconstrained =
        \\module main
        \\export identity
        \\
        \\
        \\def identity[T](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return identity[i64](1)
    ;
    const constrained =
        \\module main
        \\export identity
        \\
        \\
        \\def identity[T: copy](x: T) -> T effects():
        \\    return x
        \\
        \\
        \\def main() -> i64:
        \\    return identity[i64](1)
    ;
    var generic_entries = [_]File{.{ .path = "main.my", .bytes = unconstrained }};
    const generic_first = try describe(&generic_entries, t.allocator);
    defer incremental.deinit(generic_first, t.allocator);
    const generic_interface = try t.allocator.dupe(u8, declaration(generic_first, "main", "identity").interface_sha256.?);
    defer t.allocator.free(generic_interface);
    generic_entries[0].bytes = constrained;
    const generic_second = try describe(&generic_entries, t.allocator);
    defer incremental.deinit(generic_second, t.allocator);
    try t.expect(!std.mem.eql(u8, generic_interface, declaration(generic_second, "main", "identity").interface_sha256.?));
    try t.expect(!std.mem.eql(u8, generic_first.project_interface_sha256, generic_second.project_interface_sha256));
}

// spec: INCREMENTAL-SPEC-1
// spec-case: INCREMENTAL-SPEC-1
test "specialization key follows the concrete provider shape and target contract" {
    const payload_one =
        \\module main
        \\export HasValue
        \\export value_of
        \\constraint HasValue[T] = copy + field(value: i64)
        \\
        \\
        \\record Payload:
        \\    value: i64
        \\
        \\
        \\def value_of[T: HasValue](item: T) -> i64 effects():
        \\    return item.value
        \\
        \\
        \\def main() -> i64:
        \\    return value_of(Payload(value=7))
    ;
    const payload_padded =
        \\module main
        \\export HasValue
        \\export value_of
        \\constraint HasValue[T] = copy + field(value: i64)
        \\
        \\
        \\record Payload:
        \\    padding: i64
        \\    value: i64
        \\
        \\
        \\def value_of[T: HasValue](item: T) -> i64 effects():
        \\    return item.value
        \\
        \\
        \\def main() -> i64:
        \\    return value_of(Payload(padding=0, value=7))
    ;
    var entries = [_]File{.{ .path = "main.my", .bytes = payload_one }};
    const s0 = try describe(&entries, t.allocator);
    defer incremental.deinit(s0, t.allocator);
    try t.expectEqual(@as(usize, 1), s0.specializations.len);
    const key0 = s0.specializations[0].key_sha256;
    entries[0].bytes = payload_padded;
    const s1 = try describe(&entries, t.allocator);
    defer incremental.deinit(s1, t.allocator);
    try t.expect(!std.mem.eql(u8, key0, s1.specializations[0].key_sha256));

    entries[0].bytes = payload_one;
    const other_target = try describeWith(&entries, t.allocator, .{ .compiler_sha256 = "test-compiler-v1", .target_abi = "aarch64-linux-gnu" });
    defer incremental.deinit(other_target, t.allocator);
    try t.expect(!std.mem.eql(u8, key0, other_target.specializations[0].key_sha256));
}

test "materialize, dupModule, dupDeclaration, dupNominal, dupSpecialization and dupFragment release partial copies" {
    try t.checkAllAllocationFailures(t.allocator, allocationScenario, .{});
}

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var entries = [_]File{
        .{ .path = "main.my", .bytes =
        \\module main
        \\
        \\
        \\def main() -> i64:
        \\    return 0
        },
    };
    const report = try describe(&entries, allocator);
    incremental.deinit(report, allocator);
}
