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
    declarations = ["enum U0:\n    value(payload: u64)\n"]
    readers = ['func read0(x: U0) -> u64:\n    match x:\n        case U0.value(payload=n):\n            return n\n']
    values = ["    const v0 = U0.value(payload=18446744073709551615u64)"]
    for i in range(1, depth + 1):
        declarations.append(f"enum U{i}:\n    value(payload: U{i-1})\n")
        readers.append(f"func read{i}(x: U{i}) -> u64:\n    match x:\n        case U{i}.value(payload=n):\n            return read{i-1}(n)\n")
        values.append(f"    const v{i} = U{i}.value(payload=v{i-1})")
    body = "\n".join(values) + (f"\n    if read{depth}(v{depth}) == 18446744073709551615u64:\n"
                                "        return 7\n    return 0\n")
    return "\n".join(declarations + readers) + "\nfunc main() -> i64:\n" + body


UNIT_RESULT = """result Done:
    ok: None,
    err: i64


func noop() -> Unit:
    return


func done() -> Done:
    return Ok(noop())


func chained() -> Done:
    try done()
    return done()


func main() -> i64:
    match chained():
        case Done.ok(_):
            return 42
        case Done.err(code):
            return code
"""

GENERIC_OVERFLOW = """func add[T: integer](a: T, b: T) -> T:
    return a + b


func main() -> i64:
    return i64(add[i8](127i8, 1i8))
"""

GENERIC_NOMINAL = """class A:
    x: i64


class B:
    x: i64


func id[T](x: T) -> T:
    return x


func main() -> i64:
    mut a = id[A](A(x=3))
    mut b = id[B](B(x=4))
    return a.x + b.x
"""

INTEGERS = """func widen(x: u32) -> u64:
    return u64(x)


func main() -> i64:
    mut a = 127i8
    mut b = 255u8
    mut c = 32767i16
    mut d = 65535u16
    mut e = 2147483647i32
    mut f = 4294967295u32
    return i64(a) + i64(b) + i64(c) + i64(d) + i64(e) + i64(widen(f))
"""

SHORT_CIRCUIT = """func main() -> i64:
    if False and divtrunc(1, 0) == 0:
        return 1
    if True or divtrunc(1, 0) == 0:
        return 7
    return 0
"""

CALLS = """func add(a: i64, b: i64) -> i64:
    return a + b


func main() -> i64:
    return 11 + add(add(2, 3), add(4, 5))
"""

BOOLEAN = """func invert(x: bool) -> bool:
    return not x


func main() -> i64:
    if invert(False) == True:
        return 1
    return 0
"""

MUTUAL = """func even(n: i64) -> bool:
    if n == 0:
        return True
    return odd(n - 1)


func odd(n: i64) -> bool:
    if n == 0:
        return False
    return even(n - 1)


func main() -> i64:
    if even(100):
        return 1
    return 0
"""

RECURSIVE = """func descend(n: i64) -> i64:
    if n == 0:
        return 0
    return descend(n - 1) + 1


func main() -> i64:
    return descend(20000)
"""

DOMAIN_COPY = """domain D: i64:
    private func raw(x: i64) -> D:
        return wrap[D](x)

    func make(x: i64) -> D:
        return D.raw(x)

    func value(x: D) -> i64:
        return unwrap(x)

    func add(x: D, y: D) -> D:
        return D.make(unwrap(x) + unwrap(y))


func forward(x: D) -> D:
    return x


func main() -> i64:
    mut d = D.make(2)
    mut old = d
    mut i = 0
    while i < 5:
        d = D.add(forward(d), old)
        i += 1
    return D.value(d)
"""

DOMAIN_BOOL = """domain Flag: bool:
    func make(x: bool) -> Flag:
        return wrap[Flag](x)

    func invert(x: Flag) -> Flag:
        return wrap[Flag](not unwrap(x))

    func value(x: Flag) -> bool:
        return unwrap(x)


func main() -> i64:
    mut x = Flag.invert(Flag.make(False))
    if Flag.value(x):
        return 7
    return 0
"""

DOMAIN_U64_CAST = """domain Id: u64:
    func make(x: u64) -> Id:
        return wrap[Id](x)

    func value(x: Id) -> u64:
        return unwrap(x)


func main() -> i64:
    return i64(Id.value(Id.make(18446744073709551615u64)))
"""

DOMAIN_U8_OVERFLOW = """domain Count: u8:
    func make(x: u8) -> Count:
        return wrap[Count](x)

    func increment(x: Count) -> Count:
        return wrap[Count](unwrap(x) + 1u8)

    func value(x: Count) -> u8:
        return unwrap(x)


func main() -> i64:
    return i64(Count.value(Count.increment(Count.make(255u8))))
"""

ENUM_MATCH = """enum Color:
    red
    green
    blue


func score(x: Color) -> i64:
    match x:
        case Color.blue:
            return 3
        case Color.red:
            return 1
        case Color.green:
            return 2


func main() -> i64:
    return score(Color.red) * 100 + score(Color.green) * 10 + score(Color.blue)
"""

ENUM_COPY = """enum State:
    idle
    active


func toggle(x: State) -> State:
    if x == State.idle:
        return State.active
    return State.idle


func main() -> i64:
    mut x = State.idle
    mut old = x
    mut i = 0
    while i < 11:
        x = toggle(x)
        i += 1
    if x != old:
        return 7
    return 0
"""

ENUM_TRAP = """enum Choice:
    safe
    fail


func main() -> i64:
    mut x = Choice.fail
    match x:
        case Choice.safe:
            return 7
        case Choice.fail:
            return divtrunc(1, 0)
"""

ENUM_CONTINUATION = """enum State:
    a
    b


func main() -> i64:
    mut total = 0
    mut state = State.a
    mut i = 0
    while i < 4:
        match state:
            case State.b:
                total += 3
                state = State.a
            case State.a:
                total += 1
                state = State.b
        i += 1
    return total
"""

ENUM_SINGLE = """enum Only:
    value


func forward(x: Only) -> Only:
    return x


func main() -> i64:
    match forward(Only.value):
        case Only.value:
            return 9
"""

VARIANT_NESTED = """enum E:
    a
    b
    c


enum Inner:
    number(value: i64)
    flag(value: bool)
    code(value: E)


enum Outer:
    empty
    inner(value: Inner)


func forward(x: Outer) -> Outer:
    return x


func score(x: Outer) -> i64:
    match x:
        case Outer.empty:
            return 0
        case Outer.inner(value=v):
            match v:
                case Inner.number(value=n):
                    return n
                case Inner.flag(value=b):
                    if b:
                        return 1
                    return 0
                case Inner.code(value=e):
                    match e:
                        case E.a:
                            return 2
                        case E.b:
                            return 3
                        case E.c:
                            return 4


func main() -> i64:
    return score(forward(Outer.inner(value=Inner.number(value=-9223372036854775808)))) + score(Outer.inner(value=Inner.flag(value=True))) + score(Outer.inner(value=Inner.code(value=E.c))) + score(Outer.empty)
"""

VARIANT_U64 = """enum U:
    none
    value(value: u64)


func main() -> i64:
    match U.value(value=18446744073709551615u64):
        case U.none:
            return 0
        case U.value(value=n):
            if n == 18446744073709551615u64:
                return 7
            return 1
"""

VARIANT_SIGNED_DOMAIN = """domain D: i8:
    func make(x: i8) -> D:
        return wrap[D](x)

    func value(x: D) -> i8:
        return unwrap(x)


enum U:
    d(value: D)
    none


func main() -> i64:
    match U.d(value=D.make(-128i8)):
        case U.none:
            return 0
        case U.d(value=d):
            return i64(D.value(d))
"""

VARIANT_COPY = """enum U:
    none
    value(value: i16)


func main() -> i64:
    mut x = U.value(value=-32768i16)
    mut old = x
    x = U.none
    match old:
        case U.none:
            return 1
        case U.value(value=n):
            match x:
                case U.none:
                    return i64(n)
                case U.value(value=_):
                    return 2
"""

RESULT_REMAP = """enum E:
    missing


result Input:
    err: E,
    ok: i64


result Output:
    ok: bool,
    err: E


func convert(r: Input) -> Output:
    const value = try r
    return Ok(value > 5)


func handle(r: Output) -> i64:
    match r:
        case Output.ok(b):
            if b:
                return 7
            return 1
        case Output.err(e):
            match e:
                case E.missing:
                    return 3


func main() -> i64:
    return 100 + handle(convert(Ok(8))) + handle(convert(Err(E.missing)))
"""

RESULT_EARLY = """result R:
    ok: i64,
    err: i64


func total(a: i64, b: i64) -> i64:
    return a + b


func work(r: R) -> R:
    const value = try r
    return Ok(total(99, value) + divtrunc(1, 0))


func main() -> i64:
    mut a: R = Ok(7)
    mut b = a
    _ = b
    match work(Err(-9)):
        case R.ok(n):
            return n
        case R.err(e):
            return 100 + e
"""

RESULT_NESTED = """result R:
    ok: i64,
    err: i64


enum U:
    empty
    r(value: R)


func main() -> i64:
    mut u = U.r(value=Err(-17))
    match u:
        case U.empty:
            return 0
        case U.r(value=r):
            match r:
                case R.ok(n):
                    return n
                case R.err(e):
                    return e
"""

AGGREGATE_RESULT = """class R:
    a: FixedArray[i64, 2]
    b: i64


result Outcome:
    ok: R,
    err: R


func work(x: Outcome) -> Outcome:
    const value = try x
    return Ok(value)


func main() -> i64:
    mut old = R(b=3, a=FixedArray[i64, 2]([4, 5]))
    mut changed = old
    changed.a = replace(old.a, 0, 9)
    match work(Err(changed)):
        case Outcome.ok(_):
            return 0
        case Outcome.err(r):
            return r.a[0] + old.a[0]
"""

AGGREGATE_BOUNDS = """func main() -> i64:
    mut a: FixedArray[i64, 2] = FixedArray[int, 2]([7, 9])
    return a[-1]
"""

AGGREGATE_REPLACE_BOUNDS = """class R:
    n: i64


func main() -> i64:
    mut a: FixedArray[R, 1] = [R(n=7)]
    _ = replace(a, 18446744073709551615u64, R(n=9))
    return 0
"""

AGGREGATE_EMPTY = """class Empty:
    pass


func main() -> i64:
    mut a: FixedArray[Empty, 0] = []
    _ = Empty()
    return i64(len(a))
"""

AGGREGATE_PROPAGATION = """class R:
    n: i64


result Small:
    err: i64,
    ok: i64


result Big:
    ok: R,
    err: i64


func widen(x: Small) -> Big:
    const value = try x
    return Ok(R(n=100 + value))


func narrow(x: Big) -> Small:
    const value = try x
    return Ok(value.n)


func main() -> i64:
    mut r = narrow(widen(Err(-9)))
    match r:
        case Small.ok(n):
            return n
        case Small.err(n):
            return 100 + n
"""


def cases(root):
    """Return the shared native value, ownership and trap fixtures."""
    fixtures = [(name, (root / "test" / "fixtures" / f"{name}.selka").read_text())
                for name in ("arithmetic", "sum", "gcd", "python-calls")]
    fixtures.append(("unit-result", UNIT_RESULT))
    fixtures += [(name, (root / "examples" / f"{name}.selka").read_text())
                 for name in ("arrays", "records", "conversions", "tables", "propagation", "generics",
                              "generic-records", "generic-updates", "generic-variants", "generic-results")]
    fixtures.append(("generic-overflow", GENERIC_OVERFLOW))
    fixtures.append(("generic-nominal", GENERIC_NOMINAL))
    fixtures.append(("integers", INTEGERS))
    expressions = ["9223372036854775807 + 1", "-9223372036854775808 - 1", "3037000500 * 3037000500",
                   "-(-9223372036854775808)", "divtrunc(-9223372036854775808, -1)",
                   "remtrunc(-9223372036854775808, -1)",
                   "divtrunc(1, 0)", "remtrunc(1, 0)", "divtrunc(-7, 3)", "remtrunc(-7, 3)",
                   "i64(255u8 + 1u8)", "i64(127i8 + 1i8)",
                   "i64(18446744073709551615u64 * 18446744073709551615u64)", "i64(u8(-1))"]
    fixtures += [(f"arithmetic-{i}", f"func main() -> i64:\n    return {expr}\n") for i, expr in enumerate(expressions)]
    fixtures += [
        ("short-circuit", SHORT_CIRCUIT),
        ("calls", CALLS),
        ("boolean", BOOLEAN),
        ("mutual", MUTUAL),
        ("recursive", RECURSIVE),
    ]
    fixtures += [
        ("domain-copy", DOMAIN_COPY),
        ("domain-bool", DOMAIN_BOOL),
        ("domain-u64-cast", DOMAIN_U64_CAST),
        ("domain-u8-overflow", DOMAIN_U8_OVERFLOW),
    ]
    fixtures += [
        ("enum-match", ENUM_MATCH),
        ("enum-copy", ENUM_COPY),
        ("enum-trap", ENUM_TRAP),
        ("enum-continuation", ENUM_CONTINUATION),
        ("enum-single", ENUM_SINGLE),
    ]
    fixtures += [
        ("variant-nested", VARIANT_NESTED),
        ("variant-u64", VARIANT_U64),
        ("variant-signed-domain", VARIANT_SIGNED_DOMAIN),
        ("variant-copy", VARIANT_COPY),
        ("result-remap", RESULT_REMAP),
        ("result-early", RESULT_EARLY),
        ("result-nested", RESULT_NESTED),
    ]
    # Exercise the largest packed value and the first boxed one without deep nesting syntax.
    fixtures.append(("packed-127", packed(62)))
    fixtures.append(("boxed-130", packed(65)))
    fixtures += [
        ("aggregate-result", AGGREGATE_RESULT),
        ("aggregate-bounds", AGGREGATE_BOUNDS),
        ("aggregate-replace-bounds", AGGREGATE_REPLACE_BOUNDS),
        ("aggregate-empty", AGGREGATE_EMPTY),
        ("aggregate-propagation", AGGREGATE_PROPAGATION),
    ]
    return fixtures
