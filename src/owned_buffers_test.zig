//! Owned elements move through buffer mutation and are released on failures.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const definitions = "buffer B:u8;result Open{ok:B,err:i64}buffer Vec<T:storable>:T;result Created<T:storable>{ok:Vec<T>,err:i64}res" ++
    "ult Taken<T:storable>{ok:T,err:i64}result Status{ok:bool,err:i64}result Answer{ok:i64,err:i64}";
const scenario = definitions ++
    "fn append<T:storable>(v:&mut Vec<T>,value:T)->Status noalloc{return append_buffer<Status>(v,value);}" ++
    "fn take<T:storable>(v:&mut Vec<T>,i:u64)->Taken<T> noalloc{return take_buffer<Taken<T>>(v,i);}" ++
    "fn work(heap:allocator)->Answer{let mut all=try acquire_buffer<Created<B>>(heap,2);" ++
    "let mut first=try acquire_buffer<Open>(heap,1);discard try append_buffer<Status>(first,7u8);" ++
    "let mut second=try acquire_buffer<Open>(heap,1);discard try append_buffer<Status>(second,9u8);" ++
    "borrow mut all as v{discard try append::<B>(v,first);discard try append::<B>(v,second);" ++
    "let extracted=try take::<B>(v,0u64);if read_buffer(extracted,0)!=7u8{return new Answer.err(90);}" ++
    "let last=try take::<B>(v,0u64);if read_buffer(last,0)!=9u8{return new Answer.err(91);}" ++
    "match take::<B>(v,0u64){Taken<B>.ok(discard)=>{return new Answer.err(92);},Taken<B>.err(code)=>{if code!=3{return new Answer.err(93);}}}" ++
    "discard try truncate_buffer<Status>(v,0u64);}" ++
    "return new Answer.ok(42);}" ++
    "fn main(heap:allocator)->i64{match work(heap){Answer.ok(n)=>{return n;},Answer.err(e)=>{return e;}}}";
// spec: OWNED-BUFFER-1
test "owned buffer generic insertion and take move selected values" {
    var compilation = try language.Compilation.init(t.allocator, "owned.my", scenario);
    defer compilation.deinit();
    const result = compilation.execute(t.allocator) catch |err| {
        for (compilation.diagnostics.items) |diag| std.debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(@as(i64, 42), result.value);
}

fn runtimeFailures(allocator: std.mem.Allocator, code: language.bytecode.Program) !void {
    var statistics: language.memory.Statistics = .{};
    const result = language.vm.runWithOptions(allocator, code, .{ .memory = .{ .statistics = &statistics } });
    try t.expectEqual(@as(usize, 0), statistics.live_allocations);
    try t.expectEqual(statistics.created, statistics.released);
    try t.expectEqual(@as(i64, 42), (try result).value);
}
test "owned buffers release moved and boxed elements on every allocation failure" {
    var compilation = try language.Compilation.init(t.allocator, "owned.my", scenario);
    defer compilation.deinit();
    try compilation.emit();
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), runtimeFailures, .{compilation.code.?});
}
fn reject(text: []const u8, expected: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-owned.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(expected, compilation.diagnostics.items[0].code);
}
// spec: OWNED-BUFFER-2
test "owned elements reject copying borrowing and unchecked result storage" {
    try reject(definitions ++ "fn f(v:Vec<B>)->B{return read_buffer(v,0);}fn main()->i64{return 0;}", "E_BUFFER_COPY");
    try reject(definitions ++ "fn f(v:Vec<B>)->i64{borrow v[0..0] as s{return 0;}}fn main()->i64{return 0;}", "E_SLICE_TYPE");
    try reject(definitions ++ "fn f(a:[1]B)->i64{borrow a[0..1] as s{return 0;}}fn main()->i64{return 0;}", "E_SLICE_TYPE");
    try reject(definitions ++ "fn f<T:storable>(v:&Vec<T>)->T{return read_buffer(v,0);}fn main()->i64{return 0;}", "E_GENERIC_OPERATION");
    try reject(definitions ++ "fn f(v:&mut Vec<B>,b:B)->Status{return resize_buffer<Status>(v,2,b);}fn main()->i64{return 0;}", "E_BUFFER_COPY");
    try reject("result R{ok:i64,err:i64}buffer Bad:R;fn main()->i64{return 0;}", "E_BUFFER_ELEMENT");
    try reject("resource File:filesystem;buffer Bad:File;fn main()->i64{return 0;}", "E_BUFFER_ELEMENT");
    try reject("resource File:filesystem;struct Inner{file:File}buffer Bad:Inner;fn main()->i64{return 0;}", "E_BUFFER_ELEMENT");
    try reject("resource File:filesystem;buffer Bad:[1]File;fn main()->i64{return 0;}", "E_BUFFER_ELEMENT");
}
// spec: OWNED-BUFFER-3
test "owned container insertion and extraction retain arena provenance" {
    try reject(definitions ++ "fn f(heap:allocator)->Answer{let mut v=try acquire_buffer<Created<B>>(heap,1);arena heap as scratch{let b=try " ++
        "acquire_buffer<Open>(scratch,1);discard try append_buffer<Status>(v,b);}return new Answer.ok(0);}fn main()->i6" ++
        "4{return 0;}", "E_ARENA_ESCAPE");
    try reject(definitions ++ "fn add(v:&mut Vec<B>,b:B)->Status{return append_buffer<Status>(v,b);}fn f(heap:allocator)->Answer{let mut v=tr" ++
        "y acquire_buffer<Created<B>>(heap,1);arena heap as scratch{let b=try acquire_buffer<Open>(scratch,1);borrow mu" ++
        "t v as r{discard try add(r,b);}}return new Answer.ok(0);}fn main()->i64{return 0;}", "E_ARENA_ESCAPE");
    try reject(definitions ++ "fn f(heap:allocator)->Open{arena heap as scratch{let mut v=try acquire_buffer<Created<B>>(scratch,1);let b=try" ++
        " acquire_buffer<Open>(scratch,1);discard try append_buffer<Status>(v,b);return new Open.ok(try take_buffer<Tak" ++
        "en<B>>(v,0));}}fn main()->i64{return 0;}", "E_ARENA_ESCAPE");
}

fn runSource(text: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "owned.my", text);
    defer compilation.deinit();
    try compilation.emit();
    const result = try language.vm.run(t.allocator, compilation.code.?);
    try t.expectEqual(@as(i64, 42), result.value);
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), runtimeFailures, .{compilation.code.?});
}
test "owned buffer reserve replacement and truncation preserve initialized values under OOM" {
    try runSource(@embedFile("stdlib/fixtures/owned_buffer_mutations.my"));
}
fn malformedStorage(resource: bool) !void {
    var compilation = try language.Compilation.init(t.allocator, "malformed.my", "resource File:filesystem;buffer B:i64;fn main()->i64{return 0;}");
    defer compilation.deinit();
    try compilation.emit();
    var code = compilation.code.?;
    const records = try t.allocator.dupe(@import("typed.zig").Record, code.records);
    defer t.allocator.free(records);
    code.records = records;
    var file_id = records[0].id;
    for (records) |record| if (record.shape.resource != null) {
        file_id = record.id;
    };
    for (records) |*record| {
        if (record.shape.resource != null) record.contract.storable = true;
        if (record.shape.buffer != null) record.shape.buffer = if (resource) file_id else record.id;
    }
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, code));
}
// spec: OWNED-BUFFER-4
test "bytecode rejects forged storable resource elements and recursive ownership graphs" {
    try malformedStorage(true);
    try malformedStorage(false);
}
