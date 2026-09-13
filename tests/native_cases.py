"""Shared scalar semantics/trap fixtures for VM/native comparison; never infer runtime parity."""
import re
import subprocess


def invoke(argv):
    return subprocess.run([str(a) for a in argv], capture_output=True, timeout=90)


def signature(result):
    if result.returncode == 0:
        return (0, result.stdout)
    match = re.search(rb":(\d+):(\d+): error\[(R_[A-Z_]+)\]", result.stderr)
    assert result.returncode == 1 and match, result.stderr.decode(errors="replace")
    return (1, match.groups(), result.stdout)


def packed(depth):
    """Build a variant chain `depth` levels deep, the widest packed layout under test."""
    declarations = ["union U0{value:u64}"]
    readers = ["fn read0(x:U0)->u64{match x{U0.value(n)=>{return n;}}}"]
    values = ["let v0=new U0.value(18446744073709551615u64);"]
    for i in range(1, depth + 1):
        declarations.append(f"union U{i}{{value:U{i-1}}}")
        readers.append(f"fn read{i}(x:U{i})->u64{{match x{{U{i}.value(n)=>{{return read{i-1}(n);}}}}}}")
        values.append(f"let v{i}=new U{i}.value(v{i-1});")
    body = "".join(values) + f"if read{depth}(v{depth})==18446744073709551615u64{{return 7;}}return 0;"
    return " ".join(declarations + readers) + " fn main()->i64{" + body + "}"


def cases(root):
    """Return the shared native value, ownership and trap fixtures."""
    fixtures = [(name, (root / "test" / "fixtures" / f"{name}.my").read_text())
                for name in ("arithmetic", "sum", "gcd", "python-calls")]
    fixtures.append(("unit-result", "result Done{ok:unit,err:i64}fn noop()->unit{}fn done()->Done{return new Done.ok(noop());}"
                     "fn chained()->Done{done()?;return done();}"
                     "fn main()->i64{match chained(){Done.ok(_)=>{return 42;},Done.err(code)=>{return code;}}}"))
    fixtures += [(name, (root / "examples" / f"{name}.my").read_text())
                 for name in ("arrays", "records", "conversions", "tables", "propagation", "generics",
                              "generic-records", "generic-updates", "generic-variants", "generic-results")]
    fixtures.append(("generic-overflow", "fn add<T:integer>(a:T,b:T)->T{return a+b;}fn main()->i64{return cast<i64>(add::<i8>(127i8,1i8));}"))
    fixtures.append(("generic-nominal", "struct A{x:i64}struct B{x:i64}fn id<T:copy>(x:T)->T{return x;}fn main()->i64{let a=id::<A>(new A{x:3});let b=id::<B>(new B{x:4});return a.x+b.x;}"))
    fixtures.append(("integers", "fn widen(x: u32) -> u64 { return cast<u64>(x); } fn main() -> i64 { let a = 127i8; let b = 255u8; let c = 32767i16; let d = 65535u16; let e = 2147483647i32; let f = 4294967295u32; return cast<i64>(a) + cast<i64>(b) + cast<i64>(c) + cast<i64>(d) + cast<i64>(e) + cast<i64>(widen(f)); }"))
    expressions = ["9223372036854775807 + 1", "-9223372036854775808 - 1", "3037000500 * 3037000500",
                   "-(-9223372036854775808)", "-9223372036854775808 / -1", "-9223372036854775808 % -1",
                   "1 / 0", "1 % 0", "-7 / 3", "-7 % 3", "cast<i64>(255u8 + 1u8)", "cast<i64>(127i8 + 1i8)",
                   "cast<i64>(18446744073709551615u64 * 18446744073709551615u64)", "cast<i64>(cast<u8>(-1))"]
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
        ("variant-copy", "union U{none,value:i16} fn main()->i64{let mut x=new U.value(-32768i16);let old=x;x=new U.none;match old{U.none=>{return 1;},U.value(n)=>{match x{U.none=>{return cast<i64>(n);},U.value(_)=>{return 2;}}}}}"),
        ("result-remap", "enum E{missing} result Input{err:E,ok:i64} result Output{ok:bool,err:E} fn convert(r:Input)->Output{return new Output.ok(r?>5);} fn handle(r:Output)->i64{match r{Output.ok(b)=>{if b{return 7;}return 1;},Output.err(e)=>{match e{E.missing=>{return 3;}}}}} fn main()->i64{return 100+handle(convert(new Input.ok(8)))+handle(convert(new Input.err(new E.missing)));}"),
        ("result-early", "result R{ok:i64,err:i64} fn sum(a:i64,b:i64)->i64{return a+b;} fn work(r:R)->R{return new R.ok(sum(99,r?)+1/0);} fn main()->i64{let a=new R.ok(7);let b=a;_ = b;match work(new R.err(-9)){R.ok(n)=>{return n;},R.err(e)=>{return 100+e;}}}"),
        ("result-nested", "result R{ok:i64,err:i64} union U{empty,r:R} fn main()->i64{let u=new U.r(new R.err(-17));match u{U.empty=>{return 0;},U.r(r)=>{match r{R.ok(n)=>{return n;},R.err(e)=>{return e;}}}}}"),
    ]
    # Exercise the largest packed value and the first boxed one without deep nesting syntax.
    fixtures.append(("packed-127", packed(62)))
    fixtures.append(("boxed-130", packed(65)))
    fixtures += [
        ("aggregate-result", "struct R{a:[2]i64,b:i64} result Outcome{ok:R,err:R} fn work(x:Outcome)->Outcome{return new Outcome.ok(x?);} fn main()->i64{let old=new R{b:3,a:new [2]i64[4,5]};let mut changed=old;changed.a=replace(old.a,0,9);match work(new Outcome.err(changed)){Outcome.ok(_)=>{return 0;},Outcome.err(r)=>{return r.a[0]+old.a[0];}}}"),
        ("aggregate-bounds", "fn main()->i64{let a=new [2]i64[7,9];return a[-1];}"),
        ("aggregate-replace-bounds", "struct R{n:i64} fn main()->i64{let a=new [1]R[new R{n:7}];_ = replace(a,18446744073709551615u64,new R{n:9});return 0;}"),
        ("aggregate-empty", "struct Empty{} fn main()->i64{let a=new [0]Empty[];_ = new Empty{};return cast<i64>(len(a));}"),
        ("aggregate-propagation", "struct R{n:i64} result Small{err:i64,ok:i64} result Big{ok:R,err:i64} fn widen(x:Small)->Big{return new Big.ok(new R{n:100+x?});} fn narrow(x:Big)->Small{return new Small.ok((x?).n);} fn main()->i64{let r=narrow(widen(new Small.err(-9)));match r{Small.ok(n)=>{return n;},Small.err(n)=>{return 100+n;}}}"),
    ]
    return fixtures
