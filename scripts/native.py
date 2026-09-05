#!/usr/bin/env python3
"""Build a scalar guest executable through C using the repository's pinned Zig."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--project", action="store_true", help="compile a module entry and its reachable imports")
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, default=Path("zig-out/bin/mylang"))
    parser.add_argument("--zig", default="zig")
    parser.add_argument("--mode", choices=["Debug", "ReleaseFast"], default="Debug")
    args = parser.parse_args()
    try:
        expected = (Path(__file__).resolve().parents[1] / ".zigversion").read_text().strip()
        actual = subprocess.run([args.zig, "version"], check=True, capture_output=True, text=True, timeout=30).stdout.strip()
        if actual != expected:
            parser.error(f"native compilation requires Zig {expected}; found {actual}")
        generated = subprocess.run([str(args.compiler.resolve()), "emit-project-c" if args.project else "emit-c", str(args.source.resolve())], capture_output=True, timeout=60)
        sys.stderr.buffer.write(generated.stderr)
        if generated.returncode:
            return generated.returncode if generated.returncode in (1, 2) else 2
        with tempfile.TemporaryDirectory(prefix="mylang-native-") as temp:
            source = Path(temp) / "program.c"
            source.write_bytes(generated.stdout)
            result = subprocess.run([args.zig, "cc", "-std=c11", "-O0" if args.mode == "Debug" else "-O2", str(source), "-o", str(args.output.resolve())], timeout=180)
            return 0 if result.returncode == 0 else 2
    except (OSError, subprocess.SubprocessError) as error:
        print(f"native: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
