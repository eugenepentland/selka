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
