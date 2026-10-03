"""Compare exact public trap/refusal order against a supplied frozen compiler."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--compiler", type=Path, required=True)
parser.add_argument("--baseline", type=Path, required=True)
parser.add_argument("--qbe", type=Path, required=True)
parser.add_argument("--baseline-qbe", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
options = parser.parse_args()
options.output.mkdir(parents=True, exist_ok=True)
body = """def closed(value: int, index: int) -> int:
    values = [value, value + 1, value + 2]
    alias = values
    return alias[index] + values[1] + alias[-1] + len(values)


def main() -> int:
    assert closed(12, 0) == 42
    return FINAL
"""
checked = 0
for backend in ("qbe", "llvm"):
    for name, final in (
        ("success", "0"), ("overflow", "closed(9223372036854775807, 0)"),
        ("bounds", "closed(13, 3)"), ("negative", "closed(13, -4)"),
    ):
        source = options.output / f"{name}.my"
        source.write_text(body.replace("FINAL", final))
        programs = []
        for lane, compiler, qbe in (
            ("baseline", options.baseline, options.baseline_qbe),
            ("candidate", options.compiler, options.qbe),
        ):
            executable = options.output / f"{lane}-{backend}-{name}"
            subprocess.run([
                str(compiler), "build", str(source), "--mode", "Debug", "--backend", backend,
                "--qbe", str(qbe), f"--cache-dir={options.output / (lane + '-cache-' + backend)}",
                "-o", str(executable),
            ], check=True)
            programs.append(executable)
        trials = [(), ("--max-frames=1",), ("--max-frames=2",)]
        trials += [(f"--max-steps={steps}",) for steps in (1, 20, 60, 100, 150, 200)]
        trials += [(f"--max-memory={memory}",) for memory in (4096, 32768, 65536, 131072, 262144, 524288, 1048576)]
        for arguments in trials:
            results = [subprocess.run([str(executable), *arguments], capture_output=True) for executable in programs]
            actual = [(result.returncode, result.stdout, result.stderr) for result in results]
            if actual[0] != actual[1]:
                raise AssertionError((backend, name, arguments, actual))
            checked += 1
print(f"local list public failures: {checked} exact baseline/candidate matches")
