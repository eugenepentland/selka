"""Execute independent text/data assertions on VM and native C at two optimization levels."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def invoke(args):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, timeout=120)
    assert result.returncode == 0, (args, result.stderr.decode(errors="replace"))
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--zig", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="stdlib-text-") as directory:
        directory = Path(directory)
        for name in ("text_data", "text_data_errors", "text_data_float_edges"):
            entry = directory / "main.my"
            entry.write_bytes((root / "src/stdlib/fixtures" / f"{name}.my").read_bytes())
            assert invoke([args.compiler, "run-project", entry]) == b"42\n"
            source = directory / "program.c"
            source.write_bytes(invoke([args.compiler, "emit-project-c", entry]))
            for optimization in ("-O0", "-O2"):
                binary = directory / "program"
                invoke([args.zig, "cc", "-std=c11", optimization, "-fsanitize=undefined",
                        "-fno-sanitize-recover=undefined", source, "-o", binary])
                assert invoke([binary]) == b"42\n", (name, optimization)
    print("text/data: 3 independent fixtures pass VM and native O0/O2 with UBSan")


if __name__ == "__main__":
    main()
