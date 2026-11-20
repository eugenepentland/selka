//! The product's names: the helpers hold for any suffix, and the constants keep the relations code relies on.
const std = @import("std");
const product = @import("product.zig");
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

test "dropSuffix removes the whole suffix whatever its length" {
    try expectEqualStrings("dir/app", product.dropSuffix("dir/app.selka", ".selka"));
    try expectEqualStrings("dir/app", product.dropSuffix("dir/app.sk", ".sk"));
    try expectEqualStrings("app", product.dropSuffix("app.selkai", ".selkai"));
    try expectEqualStrings("", product.dropSuffix(".selka", ".selka"));
}

test "dropSuffix leaves a path without the suffix whole, and does not take a longer ending for it" {
    try expectEqualStrings("dir/app.sk", product.dropSuffix("dir/app.sk", ".selka"));
    try expectEqualStrings("app.selk", product.dropSuffix("app.selk", ".selka"));
    try expectEqualStrings("", product.dropSuffix("", ".selka"));
}

test "hasSuffix tests the whole suffix, so a six-character one is not a three-character one" {
    try expect(product.hasSuffix("a/b.selka", ".selka"));
    try expect(!product.hasSuffix("a/b.selka", ".sk"));
    try expect(!product.hasSuffix("b.ka", ".selka"));
    try expect(product.hasSuffix("b.sk", ".sk"));
}

test "the source helpers apply source_suffix whatever it is" {
    const path = "pkg/main" ++ product.source_suffix;
    try expect(product.isSource(path));
    try expect(!product.isSource("pkg/main.c"));
    try expectEqualStrings("pkg/main", product.sourceStem(path));
    try expectEqualStrings("pkg/main", product.chopSource(path));
    try expectEqualStrings("pkg/main.c", product.sourceStem("pkg/main.c"));
}

test "isTestSource tests the test suffix, which is the source suffix after `_test`" {
    try expect(product.isTestSource("pkg/main_test" ++ product.source_suffix));
    try expect(!product.isTestSource("pkg/main" ++ product.source_suffix));
    try expect(!product.isTestSource("pkg/main_test.c"));
}

test "sourceName appends the suffix to a stem" {
    const name = try product.sourceName(std.testing.allocator, "dir/app");
    defer std.testing.allocator.free(name);
    try expectEqualStrings("dir/app" ++ product.source_suffix, name);
}

test "guestName strips the guest symbol prefix and refuses a symbol without it" {
    try expectEqualStrings("main", product.guestName(product.guest_symbol_prefix ++ "main").?);
    try expectEqualStrings("m::f", product.guestName(product.guest_symbol_prefix ++ "m::f").?);
    try expect(product.guestName("compiler_rt.f") == null);
    try expect(product.guestName("") == null);
}

test "the derived names keep the relations the code relies on" {
    try expect(product.source_suffix[0] == '.');
    try expect(std.mem.startsWith(u8, product.interface_suffix, product.source_suffix));
    try expect(std.mem.endsWith(u8, product.test_suffix, product.source_suffix));
    try expect(std.mem.endsWith(u8, product.project_file, ".json"));
    try expect(std.mem.startsWith(u8, product.core_work_dir, product.work_dir ++ "/"));
    try expect(std.mem.indexOf(u8, product.components_subdir, "/" ++ product.user_dir ++ "/") != null);
    try expect(std.mem.endsWith(u8, product.env_prefix, "_"));
    try expect(std.mem.endsWith(u8, product.core_env_prefix, "_"));
}

test "the documentation runner's tags and its opt-out marker agree with the fence tag" {
    try expect(product.doc_executable_tags.len == 1);
    try expectEqualStrings(product.doc_fence_tag, product.doc_executable_tags[0]);
    try expect(std.mem.endsWith(u8, product.doc_not_marker, product.doc_fence_tag));
}
