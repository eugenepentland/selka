//! Familiar statement endings, unit spelling, propagation, and declaration discovery.
const std = @import("std");
const t = std.testing;
const debug = std.debug;
const language = @import("compiler.zig");

fn evaluate(bytes: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, "statements.my", bytes);
    defer compilation.deinit();
    const result = compilation.execute(t.allocator) catch |err| {
        for (compilation.diagnostics.items) |diag| debug.print("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    var after = try language.Compilation.init(t.allocator, "formatted.my", formatted);
    defer after.deinit();
    try t.expectEqual(expected, (try after.execute(t.allocator)).value);
    const twice = try after.format(t.allocator);
    defer t.allocator.free(twice);
    try t.expectEqualStrings(formatted, twice);
}

// spec: FAMILIAR-STMT-1
test "newlines closing braces and EOF replace semicolons while same line statements require separation" {
    try evaluate("type Number=i64\nconst ANSWER:Number=42\nfn main()->i64{\nlet value=ANSWER // retained comment\nreturn value\n}", 42);
    var invalid = try language.Compilation.init(t.allocator, "missing-separator.my", "fn main()->i64{let x=41 return x+1}");
    defer invalid.deinit();
    try t.expectError(error.SourceError, invalid.check());
    try t.expectEqualStrings("E_SYNTAX", invalid.diagnostics.items[0].code);
}

// spec: FAMILIAR-STMT-2
test "postfix question propagates success and error with postfix precedence" {
    try evaluate("result R{ok:i64,err:i64}\nfn first()->R{return new R.ok(41)}\n" ++
        "fn next()->R{let n=first()?\nreturn new R.ok(n+1)}\n" ++
        "fn main()->i64{match next(){R.ok(n)=>{return n},R.err(e)=>{return e}}}", 42);
    try evaluate("result R{ok:i64,err:i64}\nfn first()->R{return new R.err(42)}\n" ++
        "fn next()->R{return new R.ok(first()?+1)}\n" ++
        "fn main()->i64{match next(){R.ok(n)=>{return n},R.err(e)=>{return e}}}", 42);
}

// spec: FAMILIAR-STMT-3
test "parentheses spell unit types values and bare returns" {
    try evaluate("type Done=()\nfn nothing()->Done{return\n}\nfn explicit()->(){return ()}\n" ++
        "fn identity<T:copy>(value:T)->T{return value}\n" ++
        "fn main()->i64{nothing()\nexplicit()\nidentity::<()>(())\nreturn 42}", 42);
}

// spec: FAMILIAR-STMT-4
test "trailing call commas and multiline binary operators preserve semantics" {
    try evaluate("fn add(a:i64,b:i64,)->i64{return a+b}\nfn main()->i64{\n" ++
        "let value=add(20,22,)\nreturn (cast<i64>(value,)\n+0)\n}", 42);
    try evaluate("fn main()->i64{let value=40\n+2\nreturn value}", 42);
    try evaluate("fn main()->i64{let values=new [3]i64[10,20,12];\n" ++
        "return values[0]\n+values[1]\n+values[2];}", 42);
}

// spec: FAMILIAR-STMT-5
test "module declaration discovery and formatting accept newline terminated directives" {
    const bytes = "module example\nimport dependency as dep\nexport Value\ntype Value=i64\nexport main\nfn main()->i64{return 42}";
    var compilation = try language.Compilation.init(t.allocator, "example.my", bytes);
    defer compilation.deinit();
    const declarations = try compilation.listDeclarations(t.allocator);
    defer t.allocator.free(declarations);
    try t.expect(std.mem.indexOf(u8, declarations, "Value") != null);
    const formatted = try compilation.formatModule(t.allocator);
    defer t.allocator.free(formatted);
    var after = try language.Compilation.init(t.allocator, "example.my", formatted);
    defer after.deinit();
    const repeated = try after.listDeclarations(t.allocator);
    defer t.allocator.free(repeated);
    try t.expect(std.mem.indexOf(u8, repeated, "main") != null);
}

// spec: FAMILIAR-STMT-7
test "condition calls admit nested record constructors without consuming condition blocks" {
    try evaluate("struct point{Value:i64}\nfn predicate(first:point,value:point)->bool{return first.Value==value.Value}\n" ++
        "fn main()->i64{let flag=true\nlet item=point{Value:42}\n" ++
        "if flag{if !false && predicate(item,point{Value:42}){return 42}}\nreturn 0}", 42);
}

// spec: FAMILIAR-STMT-8
test "nested generic record constructors retain list type arguments and field contexts" {
    try evaluate("struct Holder<T:copy>{value:T}\nfn main()->i64{\n" ++
        "let holder=Holder<List<i64>>{value:[],}\nlet values=holder.value\nvalues.push(42)\nreturn values[0]}", 42);
}

// spec: FAMILIAR-STMT-9
test "newline suffixes end an expression outside parentheses and continue inside parentheses" {
    try evaluate("fn add(a:i64,b:i64)->i64{return a+b}\nfn main()->i64{return (add\n(20,22))}", 42);
    var compilation = try language.Compilation.init(t.allocator, "newline-suffix.my", "fn add(a:i64)->i64{return a}\nfn main()->i64{let callback=add\n(42)\nreturn 0}");
    defer compilation.deinit();
    try compilation.parse();
    const syntax = compilation.syntax.?;
    const body = syntax.statements.items[@backingInt(syntax.functions[1].body)].data.block;
    try t.expectEqual(@as(usize, 3), body.len);
    const binding = syntax.statements.items[@backingInt(body[0])].data.binding;
    try t.expect(syntax.nodes.items[@backingInt(binding.value)].data == .name);
    const expression = syntax.statements.items[@backingInt(body[1])].data.discard;
    try t.expect(syntax.nodes.items[@backingInt(expression)].data == .integer);
}
