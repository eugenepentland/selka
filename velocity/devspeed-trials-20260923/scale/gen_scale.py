#!/usr/bin/env python3
"""Generate the same synthetic project in mylang, Go, Rust and Zig.

usage: gen_scale.py OUTDIR MODULES FUNCS_PER_MODULE

Shape (identical in every language): MODULES modules m000..mNNN in an import chain;
each module declares one record/struct and FUNCS functions. Function i of module m
builds a list of n ints, folds it through the record, and calls function i of module
m-1 with n-1, so every function is reachable from main and every module depends on the
one before it. Each module carries one test of its first function. `main` calls
function i of the last module for every i and prints the sum.

The edit ladder (run_scale.py) edits a function body in the middle module (EDIT_BODY
marker), or appends a new public function there (interface edit).
"""
import sys
from pathlib import Path


def mylang(out: Path, M: int, F: int):
    d = out / "mylang"
    d.mkdir(parents=True, exist_ok=True)
    for m in range(M):
        lines = [f"module m{m:03d}"]
        if m > 0:
            lines.append(f"import m{m-1:03d}")
        lines += ["", "", f"public record Acc{m:03d}:", "    total: int", "    count: int", ""]
        for i in range(F):
            call = f" + m{m-1:03d}.f{m-1:03d}_{i:02d}(n - 1)" if m > 0 else ""
            lines += [
                "",
                f"public def f{m:03d}_{i:02d}(n: int) -> int:",
                "    xs: list[int] = []",
                "    for k in range(n):",
                f"        xs.append(k * {i + 1} + {m})  # EDIT_BODY" if i == 0 else f"        xs.append(k * {i + 1} + {m})",
                f"    acc = Acc{m:03d}(total=0, count=0)",
                "    for x in xs:",
                "        if x % 3 == 0:",
                f"            acc = Acc{m:03d}(total=acc.total + x, count=acc.count + 1)",
                "        else:",
                f"            acc = Acc{m:03d}(total=acc.total - 1, count=acc.count)",
                f"    return acc.total{call}",
                "",
            ]
        lines += ["", f"public def test_m{m:03d}() -> bool:", f"    return f{m:03d}_00(3) > -1000000000", ""]
        (d / f"m{m:03d}.my").write_text("\n".join(lines))
    last = f"m{M-1:03d}"
    main = ["module main", f"import {last}", "", "", "def main(out: Stream) -> int:", "    total = 0"]
    for i in range(F):
        main.append(f"    total += {last}.f{M-1:03d}_{i:02d}(5)")
    main += ["    out.print(total)", "    return 0", ""]
    (d / "main.my").write_text("\n".join(main))


def go(out: Path, M: int, F: int):
    d = out / "go"
    d.mkdir(parents=True, exist_ok=True)
    (d / "go.mod").write_text("module example.com/big\n\ngo 1.27\n")
    for m in range(M):
        p = d / f"m{m:03d}"
        p.mkdir(exist_ok=True)
        lines = [f"package m{m:03d}", ""]
        if m > 0:
            lines += [f'import "example.com/big/m{m-1:03d}"', ""]
        lines += [f"type Acc{m:03d} struct {{", "\tTotal int", "\tCount int", "}", ""]
        for i in range(F):
            call = f" + m{m-1:03d}.F{m-1:03d}_{i:02d}(n-1)" if m > 0 else ""
            body = f"\t\txs = append(xs, k*{i + 1}+{m})" + (" // EDIT_BODY" if i == 0 else "")
            lines += [
                f"func F{m:03d}_{i:02d}(n int) int {{",
                "\txs := []int{}",
                "\tfor k := 0; k < n; k++ {",
                body,
                "\t}",
                f"\tacc := Acc{m:03d}{{}}",
                "\tfor _, x := range xs {",
                "\t\tif x%3 == 0 {",
                f"\t\t\tacc = Acc{m:03d}{{Total: acc.Total + x, Count: acc.Count + 1}}",
                "\t\t} else {",
                f"\t\t\tacc = Acc{m:03d}{{Total: acc.Total - 1, Count: acc.Count}}",
                "\t\t}",
                "\t}",
                f"\treturn acc.Total{call}",
                "}",
                "",
            ]
        (p / f"m{m:03d}.go").write_text("\n".join(lines))
        (p / f"m{m:03d}_test.go").write_text(
            f'package m{m:03d}\n\nimport "testing"\n\nfunc TestM{m:03d}(t *testing.T) {{\n\tif F{m:03d}_00(3) <= -1000000000 {{\n\t\tt.Fatal("bad")\n\t}}\n}}\n')
    last = f"m{M-1:03d}"
    main = ["package main", "", "import (", '\t"fmt"', "", f'\t"example.com/big/{last}"', ")", "", "func main() {", "\ttotal := 0"]
    for i in range(F):
        main.append(f"\ttotal += {last}.F{M-1:03d}_{i:02d}(5)")
    main += ["\tfmt.Println(total)", "}", ""]
    (d / "cmd").mkdir(exist_ok=True)
    (d / "cmd" / "main.go").write_text("\n".join(main))


def rust(out: Path, M: int, F: int):
    d = out / "rust"
    (d / "src").mkdir(parents=True, exist_ok=True)
    (d / "Cargo.toml").write_text('[package]\nname = "big"\nversion = "0.1.0"\nedition = "2021"\n\n[dependencies]\n')
    for m in range(M):
        lines = ["#![allow(dead_code)]", f"pub struct Acc{m:03d} {{", "    pub total: i64,", "    pub count: i64,", "}", ""]
        for i in range(F):
            call = f" + crate::m{m-1:03d}::f{m-1:03d}_{i:02d}(n - 1)" if m > 0 else ""
            body = f"        xs.push(k * {i + 1} + {m});" + (" // EDIT_BODY" if i == 0 else "")
            lines += [
                f"pub fn f{m:03d}_{i:02d}(n: i64) -> i64 {{",
                "    let mut xs: Vec<i64> = Vec::new();",
                "    for k in 0..n {",
                body,
                "    }",
                f"    let mut acc = Acc{m:03d} {{ total: 0, count: 0 }};",
                "    for x in &xs {",
                "        if x % 3 == 0 {",
                f"            acc = Acc{m:03d} {{ total: acc.total + x, count: acc.count + 1 }};",
                "        } else {",
                f"            acc = Acc{m:03d} {{ total: acc.total - 1, count: acc.count }};",
                "        }",
                "    }",
                f"    acc.total{call}",
                "}",
                "",
            ]
        lines += ["#[cfg(test)]", "mod tests {", "    #[test]", f"    fn test_m{m:03d}() {{", f"        assert!(super::f{m:03d}_00(3) > -1000000000);", "    }", "}", ""]
        (d / "src" / f"m{m:03d}.rs").write_text("\n".join(lines))
    last = f"m{M-1:03d}"
    main = [f"mod m{m:03d};" for m in range(M)] + ["", "fn main() {", "    let mut total: i64 = 0;"]
    for i in range(F):
        main.append(f"    total += {last}::f{M-1:03d}_{i:02d}(5);")
    main += ['    println!("{}", total);', "}", ""]
    (d / "src" / "main.rs").write_text("\n".join(main))


def zig(out: Path, M: int, F: int):
    d = out / "zig"
    d.mkdir(parents=True, exist_ok=True)
    for m in range(M):
        lines = ['const std = @import("std");']
        if m > 0:
            lines.append(f'const m{m-1:03d} = @import("m{m-1:03d}.zig");')
        lines += ["", f"pub const Acc{m:03d} = struct {{", "    total: i64,", "    count: i64,", "};", ""]
        for i in range(F):
            call = f" + m{m-1:03d}.f{m-1:03d}_{i:02d}(gpa, n - 1)" if m > 0 else ""
            body = f"        xs.append(gpa, k * {i + 1} + {m}) catch unreachable;" + (" // EDIT_BODY" if i == 0 else "")
            lines += [
                f"pub fn f{m:03d}_{i:02d}(gpa: std.mem.Allocator, n: i64) i64 {{",
                "    var xs: std.ArrayList(i64) = .empty;",
                "    defer xs.deinit(gpa);",
                "    var k: i64 = 0;",
                "    while (k < n) : (k += 1) {",
                body,
                "    }",
                f"    var acc = Acc{m:03d}{{ .total = 0, .count = 0 }};",
                "    for (xs.items) |x| {",
                "        if (@mod(x, 3) == 0) {",
                "            acc = .{ .total = acc.total + x, .count = acc.count + 1 };",
                "        } else {",
                "            acc = .{ .total = acc.total - 1, .count = acc.count };",
                "        }",
                "    }",
                f"    return acc.total{call};",
                "}",
                "",
            ]
        lines += [f'test "m{m:03d}" {{', f"    try std.testing.expect(f{m:03d}_00(std.testing.allocator, 3) > -1000000000);", "}", ""]
        (d / f"m{m:03d}.zig").write_text("\n".join(lines))
    last = f"m{M-1:03d}"
    main = ['const std = @import("std");', f'const {last} = @import("{last}.zig");', "", "pub fn main() void {",
            "    const gpa = std.heap.smp_allocator;", "    var total: i64 = 0;"]
    for i in range(F):
        main.append(f"    total += {last}.f{M-1:03d}_{i:02d}(gpa, 5);")
    main += ['    std.debug.print("{d}\\n", .{total});', "}", "", "test {"]
    main += [f'    _ = @import("m{m:03d}.zig");' for m in range(M)]
    main += ["}", ""]
    (d / "main.zig").write_text("\n".join(main))


if __name__ == "__main__":
    out, M, F = Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    for gen in (mylang, go, rust, zig):
        gen(out, M, F)
