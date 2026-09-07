//! Builtin modules obey project loading rules and execute generic, non-EDA queries.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const source =
    "module main;import std_json;fn parse(heap:allocator)->std_json::Parsed{" ++
    "let text=\"{\\\"answer\\\":42,\\\"items\\\":[\\\"a\\\",\\\"b\\\"]}\";" ++
    "let mut bytes=try acquire_buffer<std_json::Input>(heap,len(text));" ++
    "borrow text[0..len(text)] as view{let mut i=0u64;while i<len_slice(view){discard try append_buffer<std_json::Status>(bytes,read_slice(view,i));i+=1u64;}}" ++
    "return std_json::parse(heap,bytes,4096);}" ++
    "fn main(heap:allocator)->i64{match parse(heap){std_json::Parsed.err(e)=>{return e;},std_json::Parsed.ok(doc)=>{" ++
    "borrow doc[0..len_buffer(doc)] as view{" ++
    "let answer=std_json::field(view,1,\"answer\");let missing=std_json::field(view,1,\"missing\");" ++
    "let items=std_json::field(view,1,\"items\");" ++
    "if missing!=0 || !std_json::textis(view,items+1,\"a\") || std_json::compare(view,items+1,items+2)>=0{return -1;}" ++
    "return std_json::get(view,answer,5);}}}}";
fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    if (source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, source);
}
// spec: STANDARD-MODULES-1
test "standard modules load through embedded providers and resolve literal key queries" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = read });
    defer program.deinit();
    const outcome = try language.vm.run(t.allocator, program.compilation.code.?);
    try t.expectEqual(@as(i64, 42), outcome.value);
    try t.expectEqual(@as(usize, 2), program.loaded.modules.items.len);
}
// spec: STANDARD-MODULES-2
test "standard modules remain inside the total project byte budget" {
    var project = language.project.Project.init(t.allocator);
    defer project.deinit();
    try t.expectError(error.SourceError, project.load(.{ .context = null, .read = read }, "main", .{ .max_total_bytes = source.len + 1 }));
    try t.expectEqualStrings("E_PROJECT_BYTES", project.problem.?.code);
}

const Fixture = struct {
    text: []const u8,
    fn load(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Fixture = @ptrCast(@alignCast(context.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        if (self.text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, self.text);
    }
};
fn runLibrary(text: []const u8, expected: i64) !void {
    var fixture: Fixture = .{ .text = text };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &fixture, .read = Fixture.load });
    defer program.deinit();
    const outcome = try language.vm.run(t.allocator, program.compilation.code.?);
    try t.expectEqual(expected, outcome.value);
}
// spec: STANDARD-MODULES-3
test "standard byte helpers validate text parse integer bounds and retain named failures" {
    try runLibrary("module main;import std_bytes;import std_result;fn main()->i64{" ++
        "if !std_bytes::utf8(\"hello\") || std_bytes::compare(\"a\",\"b\")>=0{return -1;}" ++
        "match std_bytes::integer(\"9223372036854775808\"){std_result::Result<i64,std_result::Error>.ok(discard)=>{return -2;}," ++
        "std_result::Result<i64,std_result::Error>.err(e)=>{if e.category!=new std_result::Category.overflow{return -3;}}}" ++
        "match std_bytes::integer(\"-9223372036854775808\"){std_result::Result<i64,std_result::Error>.ok(n)=>{if n!= -9223372036854775808{return -4;}},std_result::Result<i64,std_result::Error>.err(discard)=>{return -5;}}" ++
        "match std_bytes::find(\"abcd\",\"bc\"){std_result::Option<u64>.none=>{return -6;},std_result::Option<u64>.some(n)=>{return cast<i64>(n);}}}", 1);
}
// spec: STANDARD-MODULES-4
test "standard JSON view imports compile and escaped output is bounded" {
    try runLibrary("module main;import std_json_view;import std_bytes;fn main(heap:allocator)->i64{" ++
        "match std_bytes::escaped(heap,\"a\\\"\\n\",64){std_bytes::Built.err(discard)=>{return -1;},std_bytes::Built.ok(bytes)=>{" ++
        "borrow bytes[0..len_buffer(bytes)] as text{return std_bytes::compare(text,\"\\\"a\\\\\\\"\\\\u000a\\\"\");}}}}", 0);
}
// spec: STANDARD-MODULES-5
test "checked JSON distinguishes absent null wrong type and emits optional data without tape offsets" {
    try runLibrary(@embedFile("stdlib/fixtures/checked_json.my"), 0);
}
// spec: STANDARD-MODULES-6
test "standard error context survives propagation and UTF8 and capacity failures stay distinct" {
    try runLibrary(@embedFile("stdlib/fixtures/error_contracts.my"), 3);
}
// spec: STANDARD-MODULES-7
test "standard generic results cannot be silently ignored" {
    try t.expectError(error.SourceError, runLibrary(
        "module main;import std_bytes;fn main()->i64{let forgotten=std_bytes::integer(\"1\");return 0;}",
        0,
    ));
}

// spec: STANDARD-MODULES-8
test "borrowed collection mutations are bounded stable and preserve owners" {
    try runLibrary(@embedFile("stdlib/fixtures/collection_borrows.my"), 42);
}

// spec: STANDARD-MODULES-9
test "hash collections probe full tables tombstones replacements and byte keys" {
    try runLibrary(@embedFile("stdlib/fixtures/hash_collections.my"), 42);
}

fn collectionFailureRun(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    var statistics: language.memory.Statistics = .{};
    const outcome = language.vm.runWithOptions(allocator, code, .{ .memory = .{ .statistics = &statistics } });
    try t.expectEqual(@as(usize, 0), statistics.live_allocations);
    try t.expectEqual(statistics.created, statistics.released);
    try t.expectEqual(@as(i64, 42), (try outcome).value);
}
test "collection owners unwind cleanly on every runtime allocation failure" {
    for ([_][]const u8{ @embedFile("stdlib/fixtures/collection_borrows.my"), @embedFile("stdlib/fixtures/hash_collections.my"), @embedFile("stdlib/fixtures/owned_collections.my") }) |text| {
        var fixture: Fixture = .{ .text = text };
        var program: language.embedded_project.Program = undefined;
        try program.init(t.allocator, .{ .context = &fixture, .read = Fixture.load });
        defer program.deinit();
        var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
        try t.checkAllAllocationFailures(no_resize.allocator(), collectionFailureRun, .{program.compilation.code.?});
    }
}

// spec: STDLIB-TEXT-DATA-1
test "text data modules expose byte prefixes and bounded split ranges" {
    try runLibrary("module main;import std_strings;import std_encoding;import std_format;" ++
        "fn main()->i64{if !std_strings::starts_with(\"abc\",\"ab\") || std_strings::ends_with(\"a\",\"ab\"){return -1;}" ++
        "let range=std_strings::trim(\" \\t a \\n\");return cast<i64>(range.end-range.start);}", 1);
}
test "text data codecs and builders handle integer extremes and format escaped objects" {
    try runLibrary(@embedFile("stdlib/fixtures/text_data.my"), 42);
}
test "text data failures reject malformed codecs preserve negative zero and build nested JSON" {
    try runLibrary(@embedFile("stdlib/fixtures/text_data_errors.my"), 42);
}
fn textRuntimeAllocation(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    const outcome = try language.vm.run(allocator, code);
    if (outcome.value == -99) return error.OutOfMemory;
    try t.expectEqual(@as(i64, 42), outcome.value);
}
test "text data builder partial allocation failures release nested owned values" {
    var fixture: Fixture = .{ .text = @embedFile("stdlib/fixtures/text_data.my") };
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = &fixture, .read = Fixture.load });
    defer program.deinit();
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), textRuntimeAllocation, .{program.compilation.code.?});
}
test "text data fixed formatting truncates exact binary fractions across limb boundaries" {
    try runLibrary(@embedFile("stdlib/fixtures/text_data_float_edges.my"), 42);
}
// spec: STDLIB-COMPOSITION-1
test "standard text hash and JSON builders compose into a bounded word histogram" {
    try runLibrary(@embedFile("stdlib/fixtures/word_counts.my"), 42);
}

// spec: STANDARD-OWNED-COLLECTIONS-1
test "owned collection library preserves values across replacement failure and removal" {
    try runLibrary(@embedFile("stdlib/fixtures/owned_collections.my"), 42);
}

// spec: STANDARD-PARITY-1
// spec: STANDARD-PARITY-2
// spec: STANDARD-PARITY-3
test "application library parity sorting priority queues ASCII classes and pair iteration" {
    try runLibrary(@embedFile("stdlib/fixtures/library_parity.my"), 42);
}

// spec: STANDARD-INTEGER-EXTREMA-1
test "integer extrema cover all widths empty defaults and full signed ranges" {
    try runLibrary(@embedFile("stdlib/fixtures/integer_extrema.my"), 42);
}

// spec: STANDARD-JSON-SCHEMA-1
test "ordinary JSON schema helpers iterate nested values and preserve absent null type bounds errors" {
    try runLibrary(@embedFile("stdlib/fixtures/json_schema.my"), 42);
}
