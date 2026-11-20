//! How a checked name reads in a diagnostic or a printed value: the module qualifier goes from the head and from every
//! type argument, and a `::` inside the arguments never ends the head early (F-S1a-6).
const std = @import("std");
const t = std.testing;
const typed = @import("typed.zig");
const display_name = @import("display_name.zig");
const lint = @import("lint.zig");
const io_render = @import("io_render.zig");

test "local drops only the module qualifier of the head of an instance name" {
    try t.expectEqualStrings("put[repro::Value]", display_name.local("repro::put[repro::Value]"));
    try t.expectEqualStrings("Box<repro::Row>", display_name.local("app::Box<repro::Row>"));
    try t.expectEqualStrings("put", display_name.local("app::put"));
    try t.expectEqualStrings("put", display_name.local("put"));
    try t.expectEqualStrings("put[repro::Value]", display_name.local("put[repro::Value]"));
}

test "module is the head's qualifier and is empty when the head has none" {
    try t.expectEqualStrings("repro", display_name.module("repro::put[repro::Value]"));
    try t.expectEqualStrings("", display_name.module("put[repro::Value]"));
    try t.expectEqualStrings("shared.geometry", display_name.module("shared.geometry::Point"));
}

test "readable drops the qualifier of every type argument too" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings("zig_str_map_put[Value]", try display_name.readable(a, "support_zig_hashmap::zig_str_map_put[repro::Value]"));
    try t.expectEqualStrings("pair[Row,Item]", try display_name.readable(a, "app::pair[lib::Row,app::Item]"));
    try t.expectEqualStrings("Box<Row>", try display_name.readable(a, "app::Box<lib::Row>"));
    try t.expectEqualStrings("Choice.some_value<PathKind>", try display_name.readable(a, "main::Choice.some_value<filesystem::PathKind>"));
    try t.expectEqualStrings("outer[Option<Row>]", try display_name.readable(a, "app::outer[Option<lib::Row>]"));
    try t.expectEqualStrings("shown", try display_name.readable(a, "app::shown"));
    try t.expectEqualStrings("shown[i64]", try display_name.readable(a, "shown[i64]"));
}

test "readable returns a name without type arguments as a slice of the name" {
    const name = "app::build";
    try t.expectEqual(@as([*]const u8, name.ptr + 5), (try display_name.readable(t.failing_allocator, name)).ptr);
}

test "the lint and render helpers split an instance name by its head" {
    try t.expectEqualStrings("put[repro::Value]", lint.localName("repro::put[repro::Value]"));
    try t.expectEqualStrings("repro", lint.moduleName("repro::put[repro::Value]"));
    try t.expectEqualStrings("put[repro::Value]", lint.localName("put[repro::Value]"));
    try t.expectEqualStrings("", lint.moduleName("put[repro::Value]"));
    try t.expectEqualStrings("Box<lib::Row>", io_render.shortName("app::Box<lib::Row>"));
}

test "spelled names the builtin scalars of the type arguments as the source does" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings("shown[int]", try display_name.spelled(a, "shown[i64]"));
    try t.expectEqualStrings("pair[int, Row]", try display_name.spelled(a, "app::pair[i64,lib::Row]"));
    try t.expectEqualStrings("Box[float]", try display_name.spelled(a, "app::Box<f64>"));
    // Only a whole word: `i64x` and `my_i64` are user names.
    try t.expectEqualStrings("put[i64x, my_i64, int]", try display_name.spelled(a, "put[i64x,my_i64,i64]"));
    try t.expectEqualStrings("build", try display_name.spelled(a, "app::build"));
    // A name with nothing to respell allocates nothing (a hint of every check asks, and the memory it asks with is not an arena).
    const plain = "app::build";
    try t.expectEqual(@as([*]const u8, plain.ptr + 5), (try display_name.spelled(t.failing_allocator, plain)).ptr);
    // `readable` keeps the checked spelling; a printed value's name is `printed` (below).
    try t.expectEqualStrings("shown[i64]", try display_name.readable(a, "shown[i64]"));
}

// FR25 item 5: a message writes a list as the source does, `T[]`; `typed.surfaceTypeText` keeps `list[T]` for the interface files.
test "spelled and messageTypeText write a list type argument as T[] where surfaceTypeText writes list[T]" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings("Box[int[]]", try display_name.spelled(a, "app::Box<List<i64>>"));
    try t.expectEqualStrings("Box[str[][]]", try display_name.spelled(a, "app::Box<List<List<str>>>"));
    try t.expectEqualStrings("put[int[], Row]", try display_name.spelled(a, "app::put[List<i64>,lib::Row]"));
    try t.expectEqualStrings("dict[str, int[]]", try typed.messageTypeText(a, "dict[str, list[int]]"));
    try t.expectEqualStrings("func(own int[]) -> int", try typed.messageTypeText(a, "func(own list[int]) -> int"));
    try t.expectEqualStrings("(func(int) -> int)[]", try typed.messageTypeText(a, "list[func(int) -> int]"));
    // Only a standalone `list[`: a name that ends in it is the user's.
    try t.expectEqualStrings("mylist[int]", try typed.messageTypeText(a, "mylist[int]"));
    try t.expectEqualStrings("list[int]", try typed.surfaceTypeText(a, "List<i64>"));
}

// FR26 item 6: a message writes an option as the source does, `T?`; the interface files keep `Option[T]`.
test "spelled and messageTypeText write an option type argument as T? where surfaceTypeText writes Option[T]" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings("Box[int?]", try display_name.spelled(a, "app::Box<Option<i64>>"));
    try t.expectEqualStrings("Box[int?[]]", try display_name.spelled(a, "app::Box<List<Option<i64>>>"));
    try t.expectEqualStrings("Box[int[]?]", try display_name.spelled(a, "app::Box<Option<List<i64>>>"));
    try t.expectEqualStrings("put[int?, Row?]", try display_name.spelled(a, "app::put[Option<i64>,Option<lib::Row>]"));
    try t.expectEqualStrings("dict[str, int?]", try typed.messageTypeText(a, "dict[str, Option[int]]"));
    try t.expectEqualStrings("int??", try typed.messageTypeText(a, "Option[Option[int]]"));
    try t.expectEqualStrings("func(own int?) -> int?", try typed.messageTypeText(a, "func(own Option[int]) -> Option[int]"));
    try t.expectEqualStrings("(func(int) -> int)?", try typed.messageTypeText(a, "Option[func(int) -> int]"));
    // A module's own `Option`, a name that ends in the word and a text with no closing bracket are the user's or left as written.
    try t.expectEqualStrings("m.Option[int]", try typed.messageTypeText(a, "m.Option[int]"));
    try t.expectEqualStrings("MyOption[int]", try typed.messageTypeText(a, "MyOption[int]"));
    try t.expectEqualStrings("Option[int", try typed.messageTypeText(a, "Option[int"));
    try t.expectEqualStrings("Option[int]", try typed.surfaceTypeText(a, "Option<i64>"));
}

test "printed spells the type arguments of a generic instance as the source writes them" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings("Holder[int]", try display_name.printed(a, "main::Holder<i64>"));
    try t.expectEqualStrings("Pair[int, str]", try display_name.printed(a, "Pair<i64,str>"));
    try t.expectEqualStrings("Holder[PathKind]", try display_name.printed(a, "main::Holder<filesystem::PathKind>"));
    try t.expectEqualStrings("Holder[int[]]", try display_name.printed(a, "Holder<List<i64>>"));
    try t.expectEqualStrings("Holder[Holder[float]]", try display_name.printed(a, "Holder<Holder<f64>>"));
    try t.expectEqualStrings("Choice.some_value[PathKind]", try display_name.printed(a, "main::Choice.some_value<filesystem::PathKind>"));
    // A name that is no instance is a slice of the name and allocates nothing.
    const plain = "app::Row";
    try t.expectEqual(@as([*]const u8, plain.ptr + 5), (try display_name.printed(t.failing_allocator, plain)).ptr);
}

test "release gives back what printed allocated for an instance name" {
    const instance = "app::Pair<i64,str>";
    const shown = try display_name.printed(t.allocator, instance);
    try t.expectEqualStrings("Pair[int, str]", shown);
    display_name.release(t.allocator, shown, instance);
}

test "release gives back what spelled allocated and leaves a slice of the name alone" {
    // The testing allocator reports a leak: the respelled instance name is freed with its intermediate copy.
    const instance = "app::put[i64]";
    const respelled = try display_name.spelled(t.allocator, instance);
    try t.expectEqualStrings("put[int]", respelled);
    display_name.release(t.allocator, respelled, instance);
    // A name with nothing to respell is a slice of the name: nothing is allocated and nothing is freed.
    const plain = "app::build";
    const same = try display_name.spelled(t.failing_allocator, plain);
    display_name.release(t.failing_allocator, same, plain);
}
