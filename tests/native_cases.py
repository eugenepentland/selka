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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    root = Path(__file__).resolve().parents[1]
    fixtures = [(name, (root / "tests" / "fixtures" / f"{name}.my").read_text()) for name in ("arithmetic", "sum", "gcd")]
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
                assert compiled.returncode == 0, compiled.stderr.decode(errors="replace")
                budgets = [[], ["--max-steps=1"], ["--max-frames=1"]]
                if name == "recursive": budgets[0] = ["--max-frames=25000"]
                for options in budgets:
                    vm = invoke([compiler, "run", source, *options])
                    native = invoke([executable, *options])
                    assert signature(vm) == signature(native), (name, mode, options, vm.stderr, native.stderr)
                    pairs += 1
                if name == "calls":
                    for budget in range(1, 60):
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
        for bad in ("--max-steps=0", "--max-frames=-1", "--max-steps=18446744073709551616", "--unknown"):
            assert invoke([temp / "built", bad]).returncode == 2
    print(f"native parity: {len(fixtures)} scalar fixtures, {pairs} executed comparisons across -O0/-O2 with undefined-behavior sanitization; builder/budgets passed")


if __name__ == "__main__":
    main()
