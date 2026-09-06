"""Compile and execute shared scalar semantics/trap cases; never infer runtime parity."""
import argparse
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def invoke(argv):
    return subprocess.run([str(a) for a in argv], capture_output=True, timeout=90)


def signature(result):
    if result.returncode == 0:
        return (0, result.stdout)
    match = re.search(rb":(\d+):(\d+): error\[(R_[A-Z_]+)\]", result.stderr)
    assert result.returncode == 1 and match, result.stderr.decode(errors="replace")
    return (1, match.groups(), result.stdout)


def project_signature(result):
    if result.returncode == 0:
        return (0, result.stdout)
    primary = re.search(rb"^(.+):(\d+):(\d+): error\[(R_[A-Z_]+)\]", result.stderr, re.M)
    assert result.returncode == 1 and primary, result.stderr.decode(errors="replace")
    frames = []
    for line in result.stderr.splitlines():
        match = re.match(rb"  in (\S+) at (.+):(\d+):(\d+)$", line)
        if match is None:
            match = re.match(rb"  at (\S+) \((.+):(\d+):(\d+)\)$", line)
        if match:
            frames.append(match.groups())
    return (1, primary.groups(), tuple(frames), result.stdout)


def project_cases(compiler, zig, root, temp):
    fixtures = [
        ("calls", {
            "main.my": "module main; import left; import right; fn main() -> i64 { return left::work(3) + right::work(4); }",
            "left.my": "module left; export work; fn work(x: i64) -> i64 { return helper(x) * 2; } fn helper(x: i64) -> i64 { return x + 1; }",
            "right.my": "module right; export work; fn work(x: i64) -> i64 { return x + 3; }",
        }),
        ("overflow", {
            "main.my": "module main; import facade; fn main() -> i64 { return facade::value(); }",
            "facade.my": "module facade; import shared.math; export value; fn value() -> i64 { return math::overflow(); }",
            "shared/math.my": "module shared.math; export overflow; fn overflow() -> i64 {\n return 9223372036854775807 + 1;\n}",
        }),
        ("recursive", {
            "main.my": "module main; import helper; fn main() -> i64 { return helper::count(30); }",
            "helper.my": "module helper; export count; fn count(x: i64) -> i64 { if x == 0 { return 0; } return count(x - 1) + 1; }",
        }),
        ("short-circuit", {
            "main.my": "module main; import helper; fn main() -> i64 { if false && helper::bad() { return 0; } return 7; }",
            "helper.my": "module helper; export bad; fn bad() -> bool { return 1 / 0 == 0; }",
        }),
        ("widths", {
            "main.my": "module main; import helper as h; fn main() -> i64 { return cast<i64>(h::widen(255u8)); }",
            "helper.my": "module helper; export widen; fn widen(x: u8) -> u64 { return cast<u64>(x); }",
        }),
    ]
    fixtures.append(("domains", {
        "main.my": "module main; import shared.units as u; fn forward(x:u::Distance)->u::Distance{return x;} fn main()->i64{return u::Distance.number(forward(u::Distance.make(12)));}",
        "shared/units.my": "module shared.units; export Distance; domain Distance:i64 { private fn raw(x:i64)->Distance{return wrap<Distance>(x);} fn make(x:i64)->Distance{if x<0{return Distance.raw(0);}return Distance.raw(x);} fn number(x:Distance)->i64{return unwrap(x);} }",
    }))
    fixtures.append(("enums", {
        "main.my": "module main; import shared.colors as c; fn main()->i64 { let x=c::choose(true);match x { c::Color.blue=>{return c::score(x);},c::Color.red=>{return 0;} } }",
        "shared/colors.my": "module shared.colors; export Color;export choose;export score;enum Color{red,blue} fn choose(x:bool)->Color{if x{return new Color.blue;}return new Color.red;} fn score(x:Color)->i64{if x==new Color.blue{return 12;}return 1;}",
    }))
    fixtures.append(("results", {
        "main.my": "module main; import values as v; fn main()->i64{match v::work(new v::Input.err(-128i8)){v::Output.ok(discard)=>{return 0;},v::Output.err(n)=>{return 1000+cast<i64>(n);}}}",
        "values.my": "module values; export Input;export Output;export work;result Input{err:i8,ok:i64} result Output{ok:bool,err:i8} fn work(r:Input)->Output{return new Output.ok(1+try r>0);}",
    }))
    fixtures.append(("aggregates", {
        "main.my": "module main; import data as d; fn main()->i64{let old=d::make();match d::change(old){d::Outcome.ok(r)=>{return r.values[0]+old.values[0];},d::Outcome.err(discard)=>{return 0;}}}",
        "data.my": "module data;export R;export Outcome;export make;export change;struct R{values:[2]i64} result Outcome{ok:R,err:R} fn make()->R{return new R{values:new [2]i64[7,8]};} fn change(r:R)->Outcome{return new Outcome.ok(update(r){values:replace(r.values,0,9)});}",
    }))
    fixtures.append(("aggregate-trap", {
        "main.my": "module main; import data as d; fn main()->i64{return d::read(d::make());}",
        "data.my": "module data;export R;export make;export read;struct R{values:[1]i64} fn make()->R{return new R{values:new [1]i64[7]};} fn read(r:R)->i64{return r.values[1];}",
    }))
    fixtures.append(("references", {
        "main.my": "module main; import views as v; fn main()->i64{let mut a=new [3]i64[2,3,5];let old=a;borrow mut a[0..3] as all{borrow mut v::tail(all) as selected{discard v::set(9,selected);}}return old[1]+a[1];}",
        "views.my": "module views;export tail;export set;fn tail(x:&mut []i64)->&mut []i64 from x{borrow mut x[1..len_slice(x)] as selected{return selected;}} fn set(n:i64,x:&mut []i64)->i64{write_slice(x,0,n);return read_slice(x,0);}",
    }))
    fixtures.append(("reference-trap", {
        "main.my": "module main; import views as v;fn main()->i64{let a=new [2]i64[2,3];borrow a[0..2] as all{return v::read(all);}}",
        "views.my": "module views;export read;fn read(x:&[]i64)->i64{return read_slice(x,2);}",
    }))
    fixtures.append(("buffers", {
        "main.my": "module main; import storage as s;fn main(heap:allocator)->i64{match s::make(heap){s::A.ok(b)=>{return read_buffer(b,1);},s::A.err(e)=>{return e;}}}",
        "storage.my": "module storage;export B;export A;export make;buffer B:i64;result A{err:i64,ok:B} result S{err:i64,ok:bool} fn make(heap:allocator)->A{let mut b=try acquire_buffer<A>(heap,1);discard try append_buffer<S>(b,7);discard try reserve_buffer<S>(b,heap,3);discard try resize_buffer<S>(b,3,9);return new A.ok(b);}",
    }))
    fixtures.append(("pool-handles", {
        "main.my": "module main;import data as d;fn main(heap:allocator)->i64{arena heap as scratch{match d::make(scratch){d::O.ok(bundle)=>{let id=read_field(bundle,id);let p=take_field(bundle,p);match read_pool<d::R>(p,id){d::R.ok(n)=>{return n;},d::R.err(e)=>{return e;}}},d::O.err(e)=>{return e;}}}}",
        "data.my": "module data;export P;export Id;export Bundle;export O;export R;export make;pool P(Id):i64;struct Bundle{p:P,id:Id}result O{ok:Bundle,err:i64}result A{ok:P,err:i64}result I{ok:Id,err:i64}result R{ok:i64,err:i64}fn make(heap:allocator)->O{let mut p=try acquire_pool<A>(heap,1);let id=try insert_pool<I>(p,7);return new O.ok(new Bundle{p:p,id:id});}",
    }))
    codec_root = root / "examples" / "domain-codecs"
    fixtures.append(("domain-codecs", {name: (codec_root / name).read_text() for name in ("main.my", "data.my")}))
    pairs = 0
    for name, files in fixtures:
        directory = temp / ("module case " + name)
        for relative, text in files.items():
            path = directory / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        entry = directory / "main.my"
        generated = invoke([compiler, "emit-project-c", entry])
        assert generated.returncode == 0, generated.stderr
        source = directory / "program.c"
        source.write_bytes(generated.stdout)
        for mode in ("-O0", "-O2"):
            executable = directory / "program"
            built = invoke([zig, "cc", "-std=c11", mode, "-fsanitize=undefined", "-fno-sanitize-recover=undefined", source, "-o", executable])
            assert built.returncode == 0, (name, mode, built.returncode, built.stderr)
            for options in ([], ["--max-steps=1"], ["--max-frames=1"]):
                vm = invoke([compiler, "run-project", entry, *options])
                native = invoke([executable, *options])
                assert project_signature(vm) == project_signature(native), (name, mode, options, vm.stderr, native.stderr)
                pairs += 1
            if name in ("calls", "domains", "enums", "results", "aggregates", "references", "domain-codecs"):
                for budget in range(1, 100):
                    options = [f"--max-steps={budget}"]
                    vm = invoke([compiler, "run-project", entry, *options])
                    native = invoke([executable, *options])
                    assert project_signature(vm) == project_signature(native), (name, mode, budget, vm.stderr, native.stderr)
                    pairs += 1
                    if vm.returncode == 0: break
                else: raise AssertionError("module call case never completed")
        if name == "calls":
            for mode in ("Debug", "ReleaseFast"):
                executable = directory / "user-built"
                built = invoke([sys.executable, root / "scripts/native.py", entry, "--project", "--mode", mode, "-o", executable, "--compiler", compiler, "--zig", zig])
                assert built.returncode == 0, (name, mode, built.returncode, built.stderr)
                assert invoke([executable]).stdout == b"15\n"
    entry = temp / "unsupported" / "main.my"
    entry.parent.mkdir()
    entry.write_text("module main; import helper; fn main() -> i64 { return 0; }")
    (entry.parent / "helper.my").write_text("module helper; " + (root / "examples/resource-io.my").read_text())
    supported = invoke([compiler, "emit-project-c", entry])
    assert supported.returncode == 0, supported.stderr
    (entry.parent / "helper.my").write_text("module helper; fn unused()->i64{return false;}")
    rejected = invoke([compiler, "emit-project-c", entry])
    assert rejected.returncode == 1 and rejected.stdout == b"" and b"E_TYPE" in rejected.stderr, rejected
    assert b"helper.my:" in rejected.stderr, rejected.stderr
    existing = entry.parent / "existing"
    existing.write_bytes(b"preserve existing artifact")
    rejected = invoke([sys.executable, root / "scripts/native.py", entry, "--project", "-o", existing, "--compiler", compiler, "--zig", zig])
    assert rejected.returncode == 1 and existing.read_bytes() == b"preserve existing artifact", rejected.stderr
    print(f"module native parity: {len(fixtures)} project fixtures, {pairs} executed comparisons including file paths/call frames across -O0/-O2; project builder and invalid-source checks passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    root = Path(__file__).resolve().parents[1]
    fixtures = [(name, (root / "test" / "fixtures" / f"{name}.my").read_text()) for name in ("arithmetic", "sum", "gcd")]
    fixtures += [(name, (root / "examples" / f"{name}.my").read_text()) for name in ("arrays", "records", "conversions", "tables", "references", "reference-parameters", "slices", "returned-references", "propagation", "buffers", "buffer-views", "allocator-capabilities", "arena-reset", "pools", "arenas")]
    fixtures.append(("integers", "fn widen(x: u32) -> u64 { return cast<u64>(x); } fn main() -> i64 { let a = 127i8; let b = 255u8; let c = 32767i16; let d = 65535u16; let e = 2147483647i32; let f = 4294967295u32; return cast<i64>(a) + cast<i64>(b) + cast<i64>(c) + cast<i64>(d) + cast<i64>(e) + cast<i64>(widen(f)); }"))
    expressions = ["9223372036854775807 + 1", "-9223372036854775808 - 1", "3037000500 * 3037000500", "-(-9223372036854775808)", "-9223372036854775808 / -1", "-9223372036854775808 % -1", "1 / 0", "1 % 0", "-7 / 3", "-7 % 3", "cast<i64>(255u8 + 1u8)", "cast<i64>(127i8 + 1i8)", "cast<i64>(18446744073709551615u64 * 18446744073709551615u64)", "cast<i64>(cast<u8>(-1))"]
    fixtures += [(f"arithmetic-{i}", f"fn main() -> i64 {{ return {expr}; }}") for i, expr in enumerate(expressions)]
    fixtures += [
        ("short-circuit", "fn main() -> i64 { if false && 1 / 0 == 0 { return 1; } if true || 1 / 0 == 0 { return 7; } return 0; }"),
        ("calls", "fn add(a: i64, b: i64) -> i64 { return a + b; } fn main() -> i64 { return 11 + add(add(2, 3), add(4, 5)); }"),
        ("boolean", "fn invert(x: bool) -> bool { return !x; } fn main() -> i64 { if invert(false) == true { return 1; } return 0; }"),
        ("mutual", "fn even(n: i64) -> bool { if n == 0 { return true; } return odd(n - 1); } fn odd(n: i64) -> bool { if n == 0 { return false; } return even(n - 1); } fn main() -> i64 { if even(100) { return 1; } return 0; }"),
        ("recursive", "fn descend(n: i64) -> i64 { if n == 0 { return 0; } return descend(n - 1) + 1; } fn main() -> i64 { return descend(20000); }"),
    ]
    fixtures += [
        ("domain-copy", "domain D:i64 { private fn raw(x:i64)->D{return wrap<D>(x);} fn make(x:i64)->D{return D.raw(x);} fn value(x:D)->i64{return unwrap(x);} fn add(x:D,y:D)->D{return D.make(unwrap(x)+unwrap(y));} } fn pass(x:D)->D{return x;} fn main()->i64{let mut d=D.make(2);let old=d;let mut i=0;while i<5{d=D.add(pass(d),old);i+=1;}return D.value(d);}"),
        ("domain-bool", "domain Flag:bool { fn make(x:bool)->Flag{return wrap<Flag>(x);} fn invert(x:Flag)->Flag{return wrap<Flag>(!unwrap(x));} fn value(x:Flag)->bool{return unwrap(x);} } fn main()->i64{let x=Flag.invert(Flag.make(false));if Flag.value(x){return 7;}return 0;}"),
        ("domain-u64-cast", "domain Id:u64 { fn make(x:u64)->Id{return wrap<Id>(x);} fn value(x:Id)->u64{return unwrap(x);} } fn main()->i64{return cast<i64>(Id.value(Id.make(18446744073709551615u64)));}"),
        ("domain-u8-overflow", "domain Count:u8 { fn make(x:u8)->Count{return wrap<Count>(x);} fn increment(x:Count)->Count{return wrap<Count>(unwrap(x)+1u8);} fn value(x:Count)->u8{return unwrap(x);} } fn main()->i64{return cast<i64>(Count.value(Count.increment(Count.make(255u8))));}"),
    ]
    fixtures += [
        ("enum-match", "enum Color { red, green, blue } fn score(x:Color)->i64 { match x { Color.blue=>{return 3;},Color.red=>{return 1;},Color.green=>{return 2;} } } fn main()->i64{return score(new Color.red)*100+score(new Color.green)*10+score(new Color.blue);}"),
        ("enum-copy", "enum State { idle, active } fn toggle(x:State)->State{if x==new State.idle{return new State.active;}return new State.idle;} fn main()->i64{let mut x=new State.idle;let old=x;let mut i=0;while i<11{x=toggle(x);i+=1;}if x!=old{return 7;}return 0;}"),
        ("enum-trap", "enum Choice { safe, fail } fn main()->i64 { let x=new Choice.fail; match x { Choice.safe=>{return 7;},Choice.fail=>{return 1/0;} } }"),
        ("enum-continuation", "enum State{a,b} fn main()->i64{let mut total=0;let mut state=new State.a;let mut i=0;while i<4{match state{State.b=>{total+=3;state=new State.a;},State.a=>{total+=1;state=new State.b;}}i+=1;}return total;}"),
        ("enum-single", "enum Only { value } fn pass(x:Only)->Only{return x;} fn main()->i64{match pass(new Only.value){Only.value=>{return 9;}}}"),
    ]
    fixtures += [
        ("variant-nested", "enum E{a,b,c} union Inner{number:i64,flag:bool,code:E} union Outer{empty,inner:Inner} fn pass(x:Outer)->Outer{return x;} fn score(x:Outer)->i64{match x{Outer.empty=>{return 0;},Outer.inner(v)=>{match v{Inner.number(n)=>{return n;},Inner.flag(b)=>{if b{return 1;}return 0;},Inner.code(e)=>{match e{E.a=>{return 2;},E.b=>{return 3;},E.c=>{return 4;}}}}}}} fn main()->i64{return score(pass(new Outer.inner(new Inner.number(-9223372036854775808))))+score(new Outer.inner(new Inner.flag(true)))+score(new Outer.inner(new Inner.code(new E.c)))+score(new Outer.empty);}"),
        ("variant-u64", "union U{none,value:u64} fn main()->i64{match new U.value(18446744073709551615u64){U.none=>{return 0;},U.value(n)=>{if n==18446744073709551615u64{return 7;}return 1;}}}"),
        ("variant-signed-domain", "domain D:i8{fn make(x:i8)->D{return wrap<D>(x);} fn value(x:D)->i8{return unwrap(x);}} union U{d:D,none} fn main()->i64{match new U.d(D.make(-128i8)){U.none=>{return 0;},U.d(d)=>{return cast<i64>(D.value(d));}}}"),
        ("variant-copy", "union U{none,value:i16} fn main()->i64{let mut x=new U.value(-32768i16);let old=x;x=new U.none;match old{U.none=>{return 1;},U.value(n)=>{match x{U.none=>{return cast<i64>(n);},U.value(discard)=>{return 2;}}}}}"),
        ("result-remap", "enum E{missing} result Input{err:E,ok:i64} result Output{ok:bool,err:E} fn convert(r:Input)->Output{return new Output.ok(try r>5);} fn handle(r:Output)->i64{match r{Output.ok(b)=>{if b{return 7;}return 1;},Output.err(e)=>{match e{E.missing=>{return 3;}}}}} fn main()->i64{return 100+handle(convert(new Input.ok(8)))+handle(convert(new Input.err(new E.missing)));}"),
        ("result-early", "result R{ok:i64,err:i64} fn sum(a:i64,b:i64)->i64{return a+b;} fn work(r:R)->R{return new R.ok(sum(99,try r)+1/0);} fn main()->i64{let a=new R.ok(7);let b=a;acknowledge b;match work(new R.err(-9)){R.ok(n)=>{return n;},R.err(e)=>{return 100+e;}}}"),
        ("result-nested", "result R{ok:i64,err:i64} union U{empty,r:R} fn main()->i64{let u=new U.r(new R.err(-17));match u{U.empty=>{return 0;},U.r(r)=>{match r{R.ok(n)=>{return n;},R.err(e)=>{return e;}}}}}"),
    ]
    # Exercise the largest packed value without relying on deeply nested syntax.
    declarations = ["union U0{value:u64}"]
    readers = ["fn read0(x:U0)->u64{match x{U0.value(n)=>{return n;}}}"]
    values = ["let v0=new U0.value(18446744073709551615u64);"]
    for i in range(1, 63):
        declarations.append(f"union U{i}{{value:U{i-1}}}")
        readers.append(f"fn read{i}(x:U{i})->u64{{match x{{U{i}.value(n)=>{{return read{i-1}(n);}}}}}}")
        values.append(f"let v{i}=new U{i}.value(v{i-1});")
    fixtures.append(("packed-127", " ".join(declarations + readers) + " fn main()->i64{" + "".join(values) + "if read62(v62)==18446744073709551615u64{return 7;}return 0;}"))
    for i in range(63, 66):
        declarations.append(f"union U{i}{{value:U{i-1}}}")
        readers.append(f"fn read{i}(x:U{i})->u64{{match x{{U{i}.value(n)=>{{return read{i-1}(n);}}}}}}")
        values.append(f"let v{i}=new U{i}.value(v{i-1});")
    fixtures.append(("boxed-130", " ".join(declarations + readers) + " fn main()->i64{" + "".join(values) + "if read65(v65)==18446744073709551615u64{return 7;}return 0;}"))
    fixtures += [
        ("aggregate-result", "struct R{a:[2]i64,b:i64} result Outcome{ok:R,err:R} fn work(x:Outcome)->Outcome{return new Outcome.ok(try x);} fn main()->i64{let old=new R{b:3,a:new [2]i64[4,5]};let changed=update(old){a:replace(old.a,0,9)};match work(new Outcome.err(changed)){Outcome.ok(discard)=>{return 0;},Outcome.err(r)=>{return r.a[0]+old.a[0];}}}"),
        ("aggregate-bounds", "fn main()->i64{let a=new [2]i64[7,9];return a[-1];}"),
        ("aggregate-replace-bounds", "struct R{n:i64} fn main()->i64{let a=new [1]R[new R{n:7}];discard replace(a,18446744073709551615u64,new R{n:9});return 0;}"),
        ("aggregate-empty", "struct Empty{} fn main()->i64{let a=new [0]Empty[];discard new Empty{};return cast<i64>(len(a));}"),
        ("aggregate-partial", "result R{ok:i64,err:i64} struct Pair{a:R,b:R,n:i64} fn main()->i64{let p=new Pair{a:new R.ok(7),b:new R.err(9),n:3};let a=take_field(p,a);acknowledge a;let b=take_field(p,b);match b{R.ok(discard)=>{return 0;},R.err(n)=>{return n+read_field(p,n);}}}"),
        ("aggregate-propagation", "struct R{n:i64} result Small{err:i64,ok:i64} result Big{ok:R,err:i64} fn widen(x:Small)->Big{return new Big.ok(new R{n:100+try x});} fn narrow(x:Big)->Small{return new Small.ok((try x).n);} fn main()->i64{let r=narrow(widen(new Small.err(-9)));match r{Small.ok(n)=>{return n;},Small.err(n)=>{return 100+n;}}}"),
    ]
    fixtures += [
        ("reference-mixed", "fn edit(a:i64,x:&mut i64,b:i64,y:&i64)->i64{write_ref(x,read_ref(x)+a+b+read_ref(y));return read_ref(x);} fn main()->i64{let mut x=1;let y=7;borrow mut x as r{borrow y as s{discard edit(2,r,3,s);}}return x;}"),
        ("reference-range", "fn main()->i64{let a=new [2]i64[1,2];borrow a[-1..1] as r{return cast<i64>(len_slice(r));}}"),
        ("reference-read-bounds", "fn main()->i64{let a=new [2]i64[1,2];borrow a[1..2] as r{return read_slice(r,1);}}"),
        ("reference-write-bounds", "struct R{x:i64} fn main()->i64{let mut a=new [1]R[new R{x:7}];borrow mut a[0..1] as r{write_slice(r,-1,new R{x:9});}return 0;}"),
        ("reference-empty", "fn main()->i64{let a=new [0]i64[];borrow a[0..0] as r{return cast<i64>(len_slice(r));}}"),
        ("reference-shared", "fn sum(a:&i64,b:&i64)->i64{return read_ref(a)+read_ref(b);} fn main()->i64{let x=7;borrow x as r{borrow r as child{return read_ref(r)+sum(child,r);}}}"),
        ("reference-recursive", "fn count(n:i64,x:&mut i64)->i64{if n==0{return read_ref(x);}write_ref(x,read_ref(x)+1);return count(n-1,x);} fn main()->i64{let mut x=0;borrow mut x as r{return count(40,r);}}"),
        ("reference-return-whole", "struct R{x:i64} fn same(x:&mut R)->&mut R from x{return x;} fn main()->i64{let mut x=new R{x:7};let old=x;borrow mut x as r{borrow mut same(r) as selected{write_ref(selected,new R{x:9});}}return old.x+x.x;}"),
    ]
    fixtures += [
        ("arena-limit", "fn count(heap:allocator,n:i64)->i64{if n==0{return 7;}arena heap as scratch{return count(scratch,n-1);}}fn main(heap:allocator)->i64{return count(heap,260);}"),
        ("arena-empty-owner", "buffer B:i64;result A{ok:B,err:i64}result S{ok:bool,err:i64}fn main(heap:allocator)->i64{arena heap as scratch{match acquire_buffer<A>(scratch,0){A.ok(b)=>{match reset_arena<S>(scratch){S.err(e)=>{discard b;return e;},S.ok(discard)=>{discard b;return 9;}}},A.err(e)=>{return e;}}}}"),
        ("arena-wrong-growth", "buffer B:i64;result A{ok:B,err:i64}result S{ok:bool,err:i64}fn main(heap:allocator)->i64{arena heap as scratch{match acquire_buffer<A>(scratch,1){A.ok(acquired)=>{let mut b=acquired;acknowledge reserve_buffer<S>(b,heap,1);return 0;},A.err(e)=>{return e;}}}}"),
        ("arena-root-reset", "result S{err:i64,ok:bool}fn main(heap:allocator)->i64{match reset_arena<S>(heap){S.err(e)=>{return e;},S.ok(discard)=>{return 0;}}}"),
    ]
    pool_prefix = "pool P(Id):i64;result A{ok:P,err:i64}result I{err:i64,ok:Id}result S{ok:bool,err:i64}result W{ok:i64,err:i64} "
    fixtures += [
        ("pool-owner-quota", pool_prefix + "fn count(heap:allocator,n:i64)->i64{if n==0{return 9;}match acquire_pool<A>(heap,0){A.ok(p)=>{let value=count(heap,n-1);discard p;return value;},A.err(e)=>{return e;}}}fn main(heap:allocator)->i64{return count(heap,65);}"),
        ("pool-total-quota", pool_prefix + "fn count(heap:allocator,n:i64)->i64{if n==0{return 9;}match acquire_pool<A>(heap,4096){A.ok(p)=>{let value=count(heap,n-1);discard p;return value;},A.err(e)=>{return e;}}}fn main(heap:allocator)->i64{return count(heap,5);}"),
        ("pool-slot-limit", pool_prefix + "fn main(heap:allocator)->i64{match acquire_pool<A>(heap,4097){A.ok(discard)=>{return 9;},A.err(e)=>{return e;}}}"),
        ("pool-full", pool_prefix + "fn work(heap:allocator)->W{let mut p=try acquire_pool<A>(heap,0);let id=try insert_pool<I>(p,7);discard id;return new W.ok(9);}fn main(heap:allocator)->i64{match work(heap){W.ok(n)=>{return n;},W.err(e)=>{return e;}}}"),
        ("pool-equality", pool_prefix + "fn work(heap:allocator)->W{let mut p=try acquire_pool<A>(heap,1);let a=try insert_pool<I>(p,7);let saved=a;discard try remove_pool<S>(p,a);let b=try insert_pool<I>(p,8);let mut other=try acquire_pool<A>(heap,1);let c=try insert_pool<I>(other,9);discard clear_pool(p);if saved==a && a!=b && b!=c{return new W.ok(7);}return new W.ok(0);}fn main(heap:allocator)->i64{match work(heap){W.ok(n)=>{return n;},W.err(e)=>{return e;}}}"),
    ]
    buffer_prefix = "buffer B:i64; result A{err:i64,ok:B} result S{err:i64,ok:bool} fn code(s:S)->i64{match s{S.ok(discard)=>{return 0;},S.err(e)=>{return e;}}} "
    for name, body in (
        ("statuses", "let mut n=code(append_buffer<S>(b,7));n+=code(append_buffer<S>(b,8));n+=code(write_buffer<S>(b,-1,9));n+=code(resize_buffer<S>(b,-1,0));n+=code(resize_buffer<S>(b,2,0));n+=code(reserve_buffer<S>(b,heap,-1));n+=code(reserve_buffer<S>(b,heap,0));return n+read_buffer(b,0);"),
        ("read-bounds", "return read_buffer(b,0);"),
        ("slice-bounds", "borrow b[0..1] as view{return read_slice(view,0);}"),
        ("capacity-overflow", "return code(reserve_buffer<S>(b,heap,18446744073709551615u64));"),
    ):
        fixtures.append(("buffer-" + name, buffer_prefix + "fn main(heap:allocator)->i64{match acquire_buffer<A>(heap,1){A.ok(acquired)=>{let mut b=acquired;" + body + "},A.err(e)=>{return e;}}}"))
    pairs = 0
    with tempfile.TemporaryDirectory(prefix="mylang-native-parity-") as temp:
        temp = Path(temp)
        for name, text in fixtures:
            source = temp / (name + "-\"quoted.my")
            source.write_text(text)
            generated = invoke([compiler, "emit-c", source])
            assert generated.returncode == 0, generated.stderr.decode(errors="replace")
            c_file = temp / "program.c"
            c_file.write_bytes(generated.stdout)
            for mode in ("-O0", "-O2"):
                executable = temp / "program"
                compiled = invoke([args.zig, "cc", "-std=c11", mode, "-fsanitize=undefined", "-fno-sanitize-recover=undefined", c_file, "-o", executable])
                assert compiled.returncode == 0, (name, mode, compiled.returncode, compiled.stderr.decode(errors="replace"))
                budgets = [[], ["--max-steps=1"], ["--max-frames=1"]]
                if name == "recursive": budgets[0] = ["--max-frames=25000"]
                for options in budgets:
                    vm = invoke([compiler, "run", source, *options])
                    native = invoke([executable, *options])
                    assert signature(vm) == signature(native), (name, mode, options, vm.stderr, native.stderr)
                    pairs += 1
                if name == "calls" or name.startswith(("variant-", "result-")) or name in ("arrays", "records", "conversions", "tables", "aggregate-result", "aggregate-partial", "aggregate-propagation", "aggregate-empty", "references", "reference-parameters", "slices", "returned-references", "propagation", "reference-mixed", "reference-empty", "reference-shared", "reference-return-whole"):
                    for budget in range(1, 200):
                        options = [f"--max-steps={budget}"]
                        vm = invoke([compiler, "run", source, *options])
                        native = invoke([executable, *options])
                        assert signature(vm) == signature(native), (name, budget, vm.stderr, native.stderr)
                        pairs += 1
                        if vm.returncode == 0: break
                    else: raise AssertionError("call case did not complete within acceptance budget")
        # The user-facing builder also verifies the exact toolchain and produces a runnable executable.
        source = temp / "builder.my"
        source.write_text("fn main() -> i64 { return 7; }")
        result = invoke([sys.executable, root / "scripts" / "native.py", source, "-o", temp / "built", "--compiler", compiler, "--zig", args.zig])
        assert result.returncode == 0, result.stderr
        assert invoke([temp / "built"]).stdout == b"7\n"
        wrong_zig = temp / "wrong-zig"
        wrong_zig.write_text(f"#!{sys.executable}\nprint('0.15.1')\n")
        wrong_zig.chmod(0o755)
        wrong = invoke([sys.executable, root / "scripts" / "native.py", source, "-o", temp / "must-not-exist", "--compiler", compiler, "--zig", wrong_zig])
        assert wrong.returncode == 2 and not (temp / "must-not-exist").exists(), wrong.stderr
        project_cases(compiler, args.zig, root, temp)
        for bad in ("--max-steps=0", "--max-frames=-1", "--max-steps=18446744073709551616", "--unknown"):
            assert invoke([temp / "built", bad]).returncode == 2
    print(f"native parity: {len(fixtures)} value fixtures, {pairs} executed comparisons across -O0/-O2 with undefined-behavior sanitization; builder/budgets passed")


if __name__ == "__main__":
    main()
