//! The target grammar of `selka rename` (D-FR3-1): one spelling per kind of declaration, and the new name's rules.
const std = @import("std");
const target = @import("rename_target.zig");

// spec: RENAME-GRAMMAR-1
test "RENAME-GRAMMAR-1: module::name names a module-level declaration and ends with its current name" {
    const parsed = target.parse("geometry::area").?;
    try std.testing.expectEqualStrings("geometry::area", parsed.qualified);
    try std.testing.expectEqualStrings("area", target.lastName(parsed.qualified));
    // A dotted module path stays the module's.
    try std.testing.expectEqualStrings("shared.units::Distance", target.parse("shared.units::Distance").?.qualified);
}

// spec: RENAME-GRAMMAR-2
test "RENAME-GRAMMAR-2: module::Type.member names a field or a case, and module::Type.Case.field a case's field" {
    try std.testing.expectEqualStrings("x", target.lastName(target.parse("shapes::Point.x").?.qualified));
    try std.testing.expectEqualStrings("Circle", target.lastName(target.parse("shapes::Shape.Circle").?.qualified));
    try std.testing.expectEqualStrings("radius", target.lastName(target.parse("shapes::Shape.Circle.radius").?.qualified));
}

// spec: RENAME-GRAMMAR-3
test "RENAME-GRAMMAR-3: the call-site spelling module.name is accepted as index-project accepts it" {
    const parsed = target.parse("shapes.Point.x").?;
    try std.testing.expectEqualStrings("shapes.Point.x", parsed.qualified);
    try std.testing.expectEqualStrings("x", target.lastName(parsed.qualified));
}

// spec: RENAME-GRAMMAR-4
test "RENAME-GRAMMAR-4: FILE:LINE:COLUMN names a position, the only spelling a parameter or a local has" {
    const parsed = target.parse("src/main.selka:12:9").?;
    try std.testing.expectEqualStrings("src/main.selka", parsed.position.path);
    try std.testing.expectEqual(@as(usize, 12), parsed.position.line);
    try std.testing.expectEqual(@as(usize, 9), parsed.position.column);
    // A path may hold a colon of its own; the last two fields are the numbers.
    try std.testing.expectEqualStrings("odd:dir/main.selka", target.parse("odd:dir/main.selka:1:1").?.position.path);
}

// spec: RENAME-GRAMMAR-5
test "RENAME-GRAMMAR-5: spellings that name nothing are refused" {
    try std.testing.expect(target.parse("") == null);
    try std.testing.expect(target.parse("area") == null);
    try std.testing.expect(target.parse("::area") == null);
    try std.testing.expect(target.parse("geometry::") == null);
    try std.testing.expect(target.parse("a::b::c") == null);
    try std.testing.expect(target.parse("geometry::Point..x") == null);
    try std.testing.expect(target.parse("main.selka:0:4") == null);
    try std.testing.expect(target.parse("main.selka:3:0") == null);
    try std.testing.expect(target.parse("1geometry::area") == null);
}

// spec: RENAME-GRAMMAR-6
test "RENAME-GRAMMAR-6: the new name is one plain identifier and no reserved word" {
    try std.testing.expect(target.checkName("surface") == null);
    try std.testing.expect(target.checkName("_kept2") == null);
    try std.testing.expectEqual(target.NameProblem.reserved_word, target.checkName("match").?);
    try std.testing.expectEqual(target.NameProblem.reserved_word, target.checkName("return").?);
    try std.testing.expectEqual(target.NameProblem.not_identifier, target.checkName("a.b").?);
    try std.testing.expectEqual(target.NameProblem.not_identifier, target.checkName("9lives").?);
    try std.testing.expectEqual(target.NameProblem.not_identifier, target.checkName("").?);
}

// spec: RENAME-GRAMMAR-7
test "RENAME-GRAMMAR-7: a dotted module path keeps its dots before `::`, and the member path after it ends with the old name" {
    const parsed = target.parse("shared.units::Distance.value").?;
    try std.testing.expectEqualStrings("shared.units::Distance.value", parsed.qualified);
    try std.testing.expectEqualStrings("value", target.lastName(parsed.qualified));
    // The call-site spelling of the same field: every split is tried against the modules the project has.
    try std.testing.expectEqualStrings("value", target.lastName(target.parse("shared.units.Distance.value").?.qualified));
}

// spec: RENAME-GRAMMAR-8
test "RENAME-GRAMMAR-8: outside the declaring file a use stands only where the grammar puts one: qualified, as a label, or in a pattern" {
    const text = "    x = f(count=1) + m.count + count\n        case pair(count, left=_):\n    if v is count:\n    a == count\n";
    const label = std.mem.indexOf(u8, text, "count=1").?;
    const qualified = std.mem.indexOf(u8, text, ".count").? + 1;
    const bare = std.mem.indexOf(u8, text, "+ count").? + 2;
    const shorthand = std.mem.indexOf(u8, text, "(count,").? + 1;
    const tested = std.mem.indexOf(u8, text, "is count").? + 3;
    const compared = std.mem.indexOf(u8, text, "== count").? + 3;
    try std.testing.expect(target.Filter.qualified.admits(text, qualified, 5));
    try std.testing.expect(!target.Filter.qualified.admits(text, label, 5));
    try std.testing.expect(!target.Filter.qualified.admits(text, bare, 5));
    try std.testing.expect(target.Filter.labels.admits(text, label, 5));
    try std.testing.expect(!target.Filter.labels.admits(text, qualified, 5));
    try std.testing.expect(target.Filter.members.admits(text, label, 5));
    try std.testing.expect(target.Filter.members.admits(text, qualified, 5));
    try std.testing.expect(target.Filter.members.admits(text, shorthand, 5));
    try std.testing.expect(target.Filter.members.admits(text, tested, 5));
    try std.testing.expect(!target.Filter.members.admits(text, bare, 5));
    try std.testing.expect(!target.Filter.members.admits(text, compared, 5));
    try std.testing.expect(target.Filter.all.admits(text, bare, 5));
}

// spec: RENAME-GRAMMAR-9
test "RENAME-GRAMMAR-9: hiding:NAME names every binding that hides the module-level name or import alias NAME" {
    try std.testing.expectEqualStrings("live", target.parse("hiding:live").?.hiding);
    try std.testing.expectEqualStrings("you_value", target.parse("hiding:you_value").?.hiding);
    // One plain name: no module path, no member, no position.
    try std.testing.expect(target.parse("hiding:") == null);
    try std.testing.expect(target.parse("hiding:a.b") == null);
    try std.testing.expect(target.parse("hiding:9lives") == null);
    try std.testing.expect(target.parse("hiding:a::b") == null);
    // A position whose file is called `hiding` stays a position.
    try std.testing.expectEqualStrings("hiding", target.parse("hiding:3:4").?.position.path);
}
