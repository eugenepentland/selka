#!/usr/bin/env python3
"""Create the Lox maintenance trial run directories (break feature, planted GC bug) for
mylang, Go, Rust and Zig. Run only when the machine is clear; it builds nothing itself.

usage: setup_maint.py [--tasks break,gcbug] [--langs mylang,go,rust,zig]
"""
import argparse
import shutil
import subprocess
import sys
from pathlib import Path

T = Path("/home/epentland/ai/trials/devspeed-20260923")
P = Path("/home/epentland/ai/trials/devspeed-20260923-private")
SP = Path("/tmp/claude-1000/-home-epentland-ai-canopy-mylang/481b72b0-e2f9-4f0f-bcf8-35b9cdd4c0b4/scratchpad")
LOX = P / "probe" / "benchmarks" / "lox"
MYLANG = "/home/epentland/ai/canopy/mylang-worktrees/devspeed-audit-20260923/.install/bin/mylang"
TOOLS = {"mylang": [("mylang", MYLANG)],
         "go": [("go", "/home/epentland/.local/bin/go")],
         "rust": [("cargo", "/home/epentland/.cargo/bin/cargo")],
         "zig": [("zig", "/home/epentland/.local/bin/zig")]}

# The planted bug: the GC stops marking a closure's upvalues (VM engine only).
PLANT = {
    "mylang": ("heap.my", "            mark_object(mut rt.marker, payload.function)\n            for upvalue in payload.upvalues:\n                mark_object(mut rt.marker, upvalue)\n",
               "            mark_object(mut rt.marker, payload.function)\n"),
    "go": ("internal/heap/gc.go", "\t\trt.markObject(o.Function)\n\t\tfor _, u := range o.Upvalues {\n\t\t\trt.markObject(u)\n\t\t}\n",
           "\t\trt.markObject(o.Function)\n"),
    "rust": ("src/heap.rs", "                self.mark_object(closure.function);\n                for &upvalue in &closure.upvalues {\n                    self.mark_object(upvalue);\n                }\n",
             "                self.mark_object(closure.function);\n"),
    "zig": ("src/heap.zig", "                try rt.markObject(closure_obj.function);\n                for (closure_obj.upvalues) |captured| try rt.markOptional(captured);\n",
            "                try rt.markObject(closure_obj.function);\n"),
}

INTRO = {
    "mylang": "You are maintaining code in **mylang**, a Python-syntax, statically checked language that compiles to native code. Its documentation is in `{T}/kit/docs/` and `{T}/kit/README.md`. The compiler is `{d}/bin/mylang` — always invoke it by that absolute path (`{d}/bin/mylang --help` lists commands).",
    "go": "You are maintaining code in **Go**. The Go toolchain is `{d}/bin/go` — always invoke it by that absolute path.",
    "rust": "You are maintaining code in **Rust**. Cargo is `{d}/bin/cargo` — always invoke it by that absolute path.",
    "zig": "You are maintaining code in **Zig** (0.17 development snapshot). The compiler is `{d}/bin/zig` — always invoke it by that absolute path.",
}


def make_shim(real, log, dest):
    subprocess.run([sys.executable, str(SP / "make_shim.py"), real, str(log), str(dest)], check=True)
    s = dest.read_text().replace("t0 = time.time()", 'os.environ["TMPDIR"] = "/home/epentland/.cache/mylang-tmp"\nt0 = time.time()', 1)
    dest.write_text(s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tasks", default="break,gcbug")
    ap.add_argument("--langs", default="mylang,go,rust,zig")
    a = ap.parse_args()
    for task in a.tasks.split(","):
        for lang in a.langs.split(","):
            run = f"M-{task}-{lang}"
            d = T / "runs" / run
            shutil.rmtree(d, ignore_errors=True)
            (d / "bin").mkdir(parents=True)
            (d / "lox" / "ports").mkdir(parents=True)
            for item in ("SPEC.md", "bench", "corpus", "harness", ".gitignore"):
                src = LOX / item
                (shutil.copytree if src.is_dir() else shutil.copy)(src, d / "lox" / item)
            shutil.rmtree(d / "lox" / "harness" / "__pycache__", ignore_errors=True)
            port = d / "lox" / "ports" / lang
            shutil.copytree(LOX / "ports" / lang, port, ignore=shutil.ignore_patterns(".mylang-cache", "target", ".zig-cache", "zig-out"))
            if lang == "mylang":
                note = (port / "NOTES.md").read_text()
                trial = ("\n> Trial note (2026-09-23): `driver_tests.my` and `driver_cases.json` were removed from this copy because they "
                         "no longer compile on the installed compiler. Unit tests are `mylang test .` in this directory; end-to-end "
                         "correctness is the conformance corpus (`python3 ../../harness/lox_bench.py conformance --binary <lox> --engine both`).\n")
                first, rest = note.split("\n", 1)
                (port / "NOTES.md").write_text(first + "\n" + trial + rest)
                import json as _json
                bj = _json.loads((port / "bench.json").read_text())
                bj["test"]["run"] = ["sh", "-c", "\"$0\" test . --cache-dir \"$1/test\"", "{mylang}", "{cache}"]
                bj["test"]["force"] = ["sh", "-c", "\"$0\" test . --cache-dir \"$1/test\" --force", "{mylang}", "{cache}"]
                (port / "bench.json").write_text(_json.dumps(bj, indent=2))
            for name, real in TOOLS[lang]:
                make_shim(real, SP / "logs" / f"{run}.jsonl", d / "bin" / name)
            h = d / "lox" / "harness" / "lox_bench.py"
            s = h.read_text()
            s = s.replace('    raise SystemExit("cannot find the mylang checkout containing .tmp/lox-bench")', "    return HERE.parent")
            s = s.replace('"mylang": str(lox_bench_dir() / "mylang-main-26f16e90" / "bin" / "mylang"),', f'"mylang": {str(d / "bin" / "mylang")!r},')
            s = s.replace('"go": shutil.which("go") or str(home / ".local" / "bin" / "go"),', f'"go": {str(d / "bin" / "go")!r},')
            s = s.replace('"cargo": shutil.which("cargo") or str(home / ".cargo" / "bin" / "cargo"),', f'"cargo": {str(d / "bin" / "cargo")!r},')
            s = s.replace('"zig": shutil.which("zig") or str(home / ".local" / "bin" / "zig"),', f'"zig": {str(d / "bin" / "zig")!r},')
            h.write_text(s)
            if task == "gcbug":
                rel, old, new = PLANT[lang]
                f = port / rel
                body = f.read_text()
                assert body.count(old) == 1, (lang, rel)
                f.write_text(body.replace(old, new))
            spec = (P / "maint" / f"spec_{task}.md").read_text().replace("LANG", lang)
            intro = INTRO[lang].format(T=T, d=d)
            docs_rule = "the documentation named above" if lang == "mylang" else "nothing else"
            (d / "TASK.md").write_text(
                f"# Trial task ({run})\n\n{intro}\n\nRules:\n"
                f"- Work only inside `{d}/`. Do not read anything outside it except {docs_rule} (no compiler source, no other trial directories, no other checkouts), and do not use the web. Put scratch files inside `{d}/` too.\n"
                f"- Deliverables: your changes in `lox/ports/{lang}/`, `build.sh` in `{d}/` (builds `prog` there), unit tests in the port's style, and `FRICTION.md` in `{d}/`.\n"
                f"- Verify your work, then stop. Hidden tests will check the exact behaviour below.\n\n{spec}\n## FRICTION.md\n\n"
                "A candid log for the designers of the language and its tools. For every point where you were blocked, surprised or slowed down: what you tried; what the compiler, runtime or tool said (quote the error code or message); how you resolved it; roughly how many attempts it cost; and whether the documentation or tooling helped, misled or was silent. Note which tools you used to find your way around the code (grep, compiler queries, tests...). End with the three changes to the language or its tooling that would have saved you the most time, ranked.\n")
            print(run)


if __name__ == "__main__":
    main()
