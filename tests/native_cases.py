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
    declarations = ["union U0:\n    value: u64\n"]
    readers = ["def read0(x: U0) -> u64:\n    match x:\n        case U0.value(n):\n            return n\n"]
    values = ["    v0 = U0.value(18446744073709551615u64)"]
    for i in range(1, depth + 1):
        declarations.append(f"union U{i}:\n    value: U{i-1}\n")
        readers.append(f"def read{i}(x: U{i}) -> u64:\n    match x:\n        case U{i}.value(n):\n            return read{i-1}(n)\n")
        values.append(f"    v{i} = U{i}.value(v{i-1})")
    body = "\n".join(values) + (f"\n    if read{depth}(v{depth}) == 18446744073709551615u64:\n"
                                "        return 7\n    return 0\n")
    return "\n".join(declarations + readers) + "\ndef main() -> i64:\n" + body


UNIT_RESULT = """result Done:
    ok: None,
    err: i64


def noop() -> None:
    return


def done() -> Done:
    return Ok(noop())


def chained() -> Done:
    done()?
    return done()


def main() -> i64:
    match chained():
        case Done.ok(_):
            return 42
        case Done.err(code):
            return code
"""

GENERIC_OVERFLOW = """def add[T: integer](a: T, b: T) -> T:
    return a + b


def main() -> i64:
    return i64(add[i8](127i8, 1i8))
"""

GENERIC_NOMINAL = """class A:
    x: i64


class B:
    x: i64


def id[T](x: T) -> T:
    return x


def main() -> i64:
    a = id[A](A(x=3))
    b = id[B](B(x=4))
    return a.x + b.x
"""

INTEGERS = """def widen(x: u32) -> u64:
    return u64(x)


def main() -> i64:
    a = 127i8
    b = 255u8
    c = 32767i16
    d = 65535u16
    e = 2147483647i32
    f = 4294967295u32
    return i64(a) + i64(b) + i64(c) + i64(d) + i64(e) + i64(widen(f))
"""

SHORT_CIRCUIT = """def main() -> i64:
    if False and divtrunc(1, 0) == 0:
        return 1
    if True or divtrunc(1, 0) == 0:
        return 7
    return 0
"""

CALLS = """def add(a: i64, b: i64) -> i64:
    return a + b


def main() -> i64:
    return 11 + add(add(2, 3), add(4, 5))
"""

BOOLEAN = """def invert(x: bool) -> bool:
    return not x


def main() -> i64:
    if invert(False) == True:
        return 1
    return 0
"""

MUTUAL = """def even(n: i64) -> bool:
    if n == 0:
        return True
    return odd(n - 1)


def odd(n: i64) -> bool:
    if n == 0:
        return False
    return even(n - 1)


def main() -> i64:
    if even(100):
        return 1
    return 0
"""

RECURSIVE = """def descend(n: i64) -> i64:
    if n == 0:
        return 0
    return descend(n - 1) + 1


def main() -> i64:
    return descend(20000)
"""

DOMAIN_COPY = """domain D: i64:
    private def raw(x: i64) -> D:
        return wrap[D](x)

    def make(x: i64) -> D:
        return D.raw(x)

    def value(x: D) -> i64:
        return unwrap(x)

    def add(x: D, y: D) -> D:
        return D.make(unwrap(x) + unwrap(y))


def forward(x: D) -> D:
    return x


def main() -> i64:
    d = D.make(2)
    old = d
    i = 0
    while i < 5:
        d = D.add(forward(d), old)
        i += 1
    return D.value(d)
"""

DOMAIN_BOOL = """domain Flag: bool:
    def make(x: bool) -> Flag:
        return wrap[Flag](x)

    def invert(x: Flag) -> Flag:
        return wrap[Flag](not unwrap(x))

    def value(x: Flag) -> bool:
        return unwrap(x)


def main() -> i64:
    x = Flag.invert(Flag.make(False))
    if Flag.value(x):
        return 7
    return 0
"""

DOMAIN_U64_CAST = """domain Id: u64:
    def make(x: u64) -> Id:
        return wrap[Id](x)

    def value(x: Id) -> u64:
        return unwrap(x)


def main() -> i64:
    return i64(Id.value(Id.make(18446744073709551615u64)))
"""

DOMAIN_U8_OVERFLOW = """domain Count: u8:
    def make(x: u8) -> Count:
        return wrap[Count](x)

    def increment(x: Count) -> Count:
        return wrap[Count](unwrap(x) + 1u8)

    def value(x: Count) -> u8:
        return unwrap(x)


def main() -> i64:
    return i64(Count.value(Count.increment(Count.make(255u8))))
"""

ENUM_MATCH = """enum Color:
    red,
    green,
    blue


def score(x: Color) -> i64:
    match x:
        case Color.blue:
            return 3
        case Color.red:
            return 1
        case Color.green:
            return 2


def main() -> i64:
    return score(Color.red) * 100 + score(Color.green) * 10 + score(Color.blue)
"""

ENUM_COPY = """enum State:
    idle,
    active


def toggle(x: State) -> State:
    if x == State.idle:
        return State.active
    return State.idle


def main() -> i64:
    x = State.idle
    old = x
    i = 0
    while i < 11:
        x = toggle(x)
        i += 1
    if x != old:
        return 7
    return 0
"""

ENUM_TRAP = """enum Choice:
    safe,
    fail


def main() -> i64:
    x = Choice.fail
    match x:
        case Choice.safe:
            return 7
        case Choice.fail:
            return divtrunc(1, 0)
"""

ENUM_CONTINUATION = """enum State:
    a,
    b


def main() -> i64:
    total = 0
    state = State.a
    i = 0
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


def forward(x: Only) -> Only:
    return x


def main() -> i64:
    match forward(Only.value):
        case Only.value:
            return 9
"""

VARIANT_NESTED = """enum E:
    a,
    b,
    c


union Inner:
    number: i64,
    flag: bool,
    code: E


union Outer:
    empty,
    inner: Inner


def forward(x: Outer) -> Outer:
    return x


def score(x: Outer) -> i64:
    match x:
        case Outer.empty:
            return 0
        case Outer.inner(v):
            match v:
                case Inner.number(n):
                    return n
                case Inner.flag(b):
                    if b:
                        return 1
                    return 0
                case Inner.code(e):
                    match e:
                        case E.a:
                            return 2
                        case E.b:
                            return 3
                        case E.c:
                            return 4


def main() -> i64:
    return score(forward(Outer.inner(Inner.number(-9223372036854775808)))) + score(Outer.inner(Inner.flag(True))) + score(Outer.inner(Inner.code(E.c))) + score(Outer.empty)
"""

VARIANT_U64 = """union U:
    none,
    value: u64


def main() -> i64:
    match U.value(18446744073709551615u64):
        case U.none:
            return 0
        case U.value(n):
            if n == 18446744073709551615u64:
                return 7
            return 1
"""

VARIANT_SIGNED_DOMAIN = """domain D: i8:
    def make(x: i8) -> D:
        return wrap[D](x)

    def value(x: D) -> i8:
        return unwrap(x)


union U:
    d: D,
    none


def main() -> i64:
    match U.d(D.make(-128i8)):
        case U.none:
            return 0
        case U.d(d):
            return i64(D.value(d))
"""

VARIANT_COPY = """union U:
    none,
    value: i16


def main() -> i64:
    x = U.value(-32768i16)
    old = x
    x = U.none
    match old:
        case U.none:
            return 1
        case U.value(n):
            match x:
                case U.none:
                    return i64(n)
                case U.value(_):
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


def convert(r: Input) -> Output:
    return Ok(r? > 5)


def handle(r: Output) -> i64:
    match r:
        case Output.ok(b):
            if b:
                return 7
            return 1
        case Output.err(e):
            match e:
                case E.missing:
                    return 3


def main() -> i64:
    return 100 + handle(convert(Ok(8))) + handle(convert(Err(E.missing)))
"""

RESULT_EARLY = """result R:
    ok: i64,
    err: i64


def total(a: i64, b: i64) -> i64:
    return a + b


def work(r: R) -> R:
    return Ok(total(99, r?) + divtrunc(1, 0))


def main() -> i64:
    a: R = Ok(7)
    b = a
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


union U:
    empty,
    r: R


def main() -> i64:
    u = U.r(Err(-17))
    match u:
        case U.empty:
            return 0
        case U.r(r):
            match r:
                case R.ok(n):
                    return n
                case R.err(e):
                    return e
"""

AGGREGATE_RESULT = """class R:
    a: [2]i64
    b: i64


result Outcome:
    ok: R,
    err: R


def work(x: Outcome) -> Outcome:
    return Ok(x?)


def main() -> i64:
    old = R(b=3, a=[4, 5])
    changed = old
    changed.a = replace(old.a, 0, 9)
    match work(Err(changed)):
        case Outcome.ok(_):
            return 0
        case Outcome.err(r):
            return r.a[0] + old.a[0]
"""

AGGREGATE_BOUNDS = """def main() -> i64:
    a: [2]i64 = [7, 9]
    return a[-1]
"""

AGGREGATE_REPLACE_BOUNDS = """class R:
    n: i64


def main() -> i64:
    a: [1]R = [R(n=7)]
    _ = replace(a, 18446744073709551615u64, R(n=9))
    return 0
"""

AGGREGATE_EMPTY = """class Empty:
    pass


def main() -> i64:
    a: [0]Empty = []
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


def widen(x: Small) -> Big:
    return Ok(R(n=100 + x?))


def narrow(x: Big) -> Small:
    return Ok((x?).n)


def main() -> i64:
    r = narrow(widen(Err(-9)))
    match r:
        case Small.ok(n):
            return n
        case Small.err(n):
            return 100 + n
"""


def cases(root):
    """Return the shared native value, ownership and trap fixtures."""
    fixtures = [(name, (root / "test" / "fixtures" / f"{name}.my").read_text())
                for name in ("arithmetic", "sum", "gcd", "python-calls")]
    fixtures.append(("unit-result", UNIT_RESULT))
    fixtures += [(name, (root / "examples" / f"{name}.my").read_text())
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
    fixtures += [(f"arithmetic-{i}", f"def main() -> i64:\n    return {expr}\n") for i, expr in enumerate(expressions)]
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
