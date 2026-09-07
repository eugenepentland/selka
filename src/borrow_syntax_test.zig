//! Concise slice and grouped loans lower to the existing lexical borrow machinery.
const std = @import("std");
const t = std.testing;
const print = std.debug.print;
const language = @import("compiler.zig");
const buffers = "buffer B:i64;result Open{ok:B,err:i64}result Status{ok:i64,err:i64}result Changed{ok:bool,err:i64}";
const entry = "fn main(heap:allocator)->i64{match work(heap){Status.ok(n)=>{return n;},Status.err(e)=>{return e;}}}";

fn result(text: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "borrow-syntax.my", text);
    defer compilation.deinit();
    const execution = compilation.execute(t.allocator) catch |err| {
        for (compilation.diagnostics.items) |item| print("{s}: {s} at {s}\n", .{ item.code, item.message, compilation.src.text(item.span) });
        return err;
    };
    try t.expectEqual(expected, execution.value);
    const native = try compilation.emitC(t.allocator);
    defer t.allocator.free(native);
    try t.expect(native.len > 0);
}
fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "invalid-borrow-syntax.my", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec: BORROW-SYNTAX-1
test "whole slices and grouped loans mutate independent buffers and restore growth" {
    try result(buffers ++ "fn work(heap:allocator)->Status{" ++
        "let mut a=try acquire_buffer<Open>(heap,4);let mut b=try acquire_buffer<Open>(heap,2);" ++
        "discard try resize_buffer<Changed>(a,2,3);discard try resize_buffer<Changed>(b,1,7);" ++
        "borrow mut a[..] as av,b[..] as bv{write_slice(av,1,read_slice(bv,0));}" ++
        "discard try resize_buffer<Changed>(a,3,11);" ++
        "borrow a[..] as av,b[..] as bv{return new Status.ok(cast<i64>(len_slice(av))+read_slice(av,1)+read_slice(av,2)+read_slice(bv,0));}}" ++ entry, 28);
    try result(buffers ++ "fn work(heap:allocator)->Status{let a=try acquire_buffer<Open>(heap,8);" ++
        "borrow a[..] as av{return new Status.ok(cast<i64>(len_slice(av)));}}" ++ entry, 0);
}

test "whole arrays and narrowed slice reborrows preserve copy and parent access" {
    try result("fn main()->i64{let mut a=new [3]i64 [2,3,5];let original=a;" ++
        "borrow mut a[..] as av{borrow mut av[1..3] as tail{borrow mut tail[..] as full{write_slice(full,0,7);}" ++
        "write_slice(tail,1,11);}write_slice(av,0,13);}return a[0]+a[1]+a[2]+original[1];}", 34);
    try result("fn main()->i64{let a=new [0]i64 [];let b=new [2]i64 [4,6];" ++
        "borrow a[..] as av,b[..] as bv,b[1..2] as tail{return cast<i64>(len_slice(av))+read_slice(bv,0)+read_slice(tail,0);}}", 10);
    try result("fn main()->i64{let mut a=1;let b=2;borrow mut a as av,b as bv{write_ref(av,read_ref(bv));}return a;}", 2);
}

test "grouped loans release on continue break return and try propagation" {
    try result("fn main()->i64{let mut a=new [1]i64 [0];let mut b=new [1]i64 [0];let mut i=0;while i<3{" ++
        "i+=1;borrow mut a[..] as av,mut b[..] as bv{write_slice(av,0,read_slice(av,0)+1);" ++
        "write_slice(bv,0,read_slice(bv,0)+2);if i<3{continue;}break;}}" ++
        "borrow mut a[..] as av,mut b[..] as bv{write_slice(av,0,read_slice(av,0)+read_slice(bv,0));}return a[0];}", 9);
    try result(buffers ++ "fn work(heap:allocator)->Status{let a=try acquire_buffer<Open>(heap,0);let b=try acquire_buffer<Open>(heap,0);" ++
        "borrow a[..] as av,b[..] as bv{discard len_slice(av);discard len_slice(bv);discard try fail();}return new Status.ok(0);}" ++
        "fn fail()->Status{return new Status.err(17);}" ++ entry, 17);
}

test "grouped reference calls and generic whole slices use ordinary reborrow semantics" {
    try result("fn identity(r:&mut i64)->&mut i64 from r{return r;}" ++
        "fn main()->i64{let mut x=2;let mut y=3;borrow mut x as a,mut y as b{" ++
        "borrow mut identity(a) as ar,mut identity(b) as br{write_ref(ar,7);write_ref(br,11);}write_ref(a,read_ref(a)+read_ref(b));}return x;}", 18);
    try result("fn copy<T:copy>(a:&mut []T,b:&[]T)->T{borrow mut a[..] as av,b[..] as bv{write_slice(av,0,read_slice(bv,0));}" ++
        "return read_slice(a,0);}fn main()->i64{let mut a=new [1]i64 [3];let b=new [1]i64 [8];" ++
        "borrow mut a[..] as av,b[..] as bv{return copy::<i64>(av,bv);}}", 8);
}

test "grouped loans retain alias permission scope and suspension diagnostics" {
    try reject("fn main()->i64{let mut a=new [1]i64 [0];borrow mut a[..] as av,mut a[..] as bv{return 0;}}", "E_BORROW_CONFLICT");
    try reject("fn main()->i64{let mut a=new [1]i64 [0];borrow a[..] as av,mut a[..] as bv{return 0;}}", "E_BORROW_CONFLICT");
    try reject("fn main()->i64{let a=new [1]i64 [0];let b=new [1]i64 [0];borrow a[..] as av,b[..] as bv{write_slice(bv,0,1);}return 0;}", "E_REFERENCE_READ_ONLY");
    try reject("fn main()->i64{let a=new [1]i64 [0];borrow mut a[..] as av{return 0;}}", "E_IMMUTABLE");
    try reject("fn main()->i64{let a=new [1]i64 [0];let b=new [1]i64 [0];borrow a[..] as av,b[..] as bv{}return read_slice(bv,0);}", "E_REFERENCE_SCOPE");
    try reject("fn main()->i64{let a=new [1]i64 [0];borrow a[..] as av,a[..] as av{return 0;}}", "E_SHADOWING");
    try reject("fn main()->i64{let mut a=new [1]i64 [0];borrow mut a[..] as av{borrow av[..] as child,av[..] as other{return 0;}}}", "E_BORROW_SUSPENDED");
    try reject("fn main()->i64{let a=0;borrow a[..] as av{return 0;}}", "E_SLICE_TYPE");
    try reject(buffers ++ "fn work(heap:allocator)->Status{let mut a=try acquire_buffer<Open>(heap,1);borrow a[..] as av{discard try resize_buffer<Changed>(a,1,0);}return new Status.ok(0);}" ++ entry, "E_BORROW_CONFLICT");
    try reject(buffers ++ "fn work(heap:allocator)->Status{let a=try acquire_buffer<Open>(heap,1);borrow a as owner{borrow owner[..] as av{return new Status.ok(0);}}}" ++ entry, "E_SLICE_TYPE");
    try reject("buffer B:i64;buffer Outer:B;fn f(a:Outer)->i64{borrow a[..] as av{return 0;}}fn main()->i64{return 0;}", "E_SLICE_TYPE");
}

test "generic grouped loans reject conflicts escapes and readonly upgrades before instantiation" {
    try reject("fn f<T:copy>(a:&mut []T)->T{borrow mut a[..] as av,a[..] as bv{return read_slice(av,0);}}", "E_BORROW_SUSPENDED");
    try reject("fn f<T:copy>(a:&[]T)->T{borrow mut a[..] as av{return read_slice(av,0);}}", "E_REFERENCE_READ_ONLY");
    try reject("fn f<T:copy>(a:&[]T,b:&[]T)->T{borrow a[..] as av,b[..] as bv{}return read_slice(bv,0);}", "E_UNKNOWN_NAME");
}

test "grouped borrow syntax bounds lowered depth and rejects incomplete clauses" {
    var text: std.Io.Writer.Allocating = .init(t.allocator);
    defer text.deinit();
    try text.writer.writeAll("fn main()->i64{let a=0;borrow ");
    for (0..260) |_| try text.writer.writeAll("a as r,");
    try text.writer.writeAll("a as last{return 0;}}");
    try reject(text.written(), "E_NESTING_LIMIT");
    try reject("fn main()->i64{let a=new [1]i64 [0];borrow a[..] as av,{return 0;}}", "E_SYNTAX");
    try reject("fn main()->i64{let a=new [1]i64 [0];borrow a[..1] as av{return 0;}}", "E_SYNTAX");
    try reject("fn main()->i64{let a=new [1]i64 [0];borrow a[0..] as av{return 0;}}", "E_EXPRESSION");
}

fn manyBuffers(allocator: std.mem.Allocator) !void {
    var text: std.Io.Writer.Allocating = .init(t.allocator);
    defer text.deinit();
    try text.writer.writeAll(buffers ++ "fn work(heap:allocator)->Status{");
    for (0..8) |i| try text.writer.print("let mut a{d}=try acquire_buffer<Open>(heap,0);", .{i});
    try text.writer.writeAll("borrow ");
    for (0..8) |i| {
        if (i != 0) try text.writer.writeByte(',');
        try text.writer.print("mut a{d}[..] as v{d}", .{ i, i });
    }
    try text.writer.writeAll("{");
    for (0..8) |i| try text.writer.print("discard len_slice(v{d});", .{i});
    try text.writer.writeAll("return new Status.ok(8);}}" ++ entry);
    var compilation = try language.Compilation.init(allocator, "eight-buffers.my", text.written());
    defer compilation.deinit();
    try t.expectEqual(@as(i64, 8), (try compilation.execute(allocator)).value);
}

test "eight grouped owned buffers clean up on early return and allocator failures" {
    try manyBuffers(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), manyBuffers, .{});
}

test "generic whole buffer owners retain element constraints and owned lifetimes" {
    try result("buffer V<T:copy>:T;result Open{ok:V<i64>,err:i64}result Changed{ok:bool,err:i64}result Status{ok:i64,err:i64}" ++
        "fn first<T:copy>(v:V<T>)->T{borrow v[..] as view{return read_slice(view,0);}}" ++
        "fn work(heap:allocator)->Status{let mut v=try acquire_buffer<Open>(heap,4);discard try resize_buffer<Changed>(v,1,19);" ++
        "return new Status.ok(first::<i64>(v));}" ++ entry, 19);
    try reject("fn leak(input:&[]i64)->&[]i64 from input{let a=new [1]i64 [0];borrow a[..] as av,input[..] as iv{discard len_slice(iv);return av;}}fn main()->i64{return 0;}", "E_RETURN_LIFETIME");
}
