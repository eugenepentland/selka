#!/usr/bin/env python3
"""Exercise checked ownership and noalloc at the public command boundary."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def invoke(compiler, root, *args, status=0, diagnostic=None):
    environment = os.environ.copy()
    environment.update(SELKA_COMPILER_SHARED_CACHE="", SELKA_TEST_SHARED_CACHE="", SELKA_STAGE_SHARED_CACHE="")
    result = subprocess.run([str(compiler), *map(str, args)], cwd=root,
                            env=environment, text=True, capture_output=True)
    output = result.stdout + result.stderr
    if result.returncode != status or (diagnostic is not None and diagnostic not in output):
        raise AssertionError(f"{args}: expected {status} and {diagnostic!r}, got {result.returncode}\n{output}")
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--stage", choices=("default", "retirement"), default="default")
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix="ownership-default-cli-") as temporary:
        root = Path(temporary)
        invalid = root / "moved.selka"
        invalid.write_text("func value() -> int:\n    mut first = [1]\n    const second = own first\n    return len(first) + len(second)\n\npublic func test_value() -> bool:\n    return value() == 2\n\nfunc main() -> int:\n    return value()\n")
        for command in ("check", "run", "build", "test"):
            extra = ("-o", root / "moved") if command == "build" else ()
            output = invoke(compiler, root, command, invalid, *extra, status=1, diagnostic="E_SINGLE_OWNER_MOVED")
            if "ownership rule B3" not in output:
                raise AssertionError(f"{command}: moved-value refusal lost rule B3\n{output}")
        bounded = root / "bounded.selka"
        bounded.write_text("@noalloc\nfunc value() -> int:\n    const values = [1]\n    return len(values)\n\npublic func test_value() -> bool:\n    return value() == 1\n\nfunc main() -> int:\n    return value() - 1\n")
        for command in ("run", "build", "test"):
            extra = ("-o", root / "bounded") if command == "build" else ()
            invoke(compiler, root, command, bounded, *extra, status=1, diagnostic="E_NOALLOC_ALLOCATES")
        valid = root / "valid.selka"
        valid.write_text("@noalloc\nfunc main() -> int:\n    return 0\n")
        invoke(compiler, root, "run", valid)
        for selector in ("--experimental-zero-rc", "--experimental-single-owner"):
            expected = 0 if args.stage == "default" else 2
            message = "has no effect" if args.stage == "default" else "reference counting was removed"
            warning = f"selka: warning: {selector} has no effect; checked ownership is the default; drop the flag\n"
            output = invoke(compiler, root, "check", valid, selector, status=expected, diagnostic=message)
            if args.stage == "default" and output != warning:
                raise AssertionError(f"selector warning changed: {output!r}")
            encoded = invoke(compiler, root, "check", valid, selector, "--diagnostics=json", status=expected, diagnostic=message)
            record = json.loads(encoded)
            if record.get("version") != "diagnostic-v1" or record.get("kind") != "message":
                raise AssertionError(f"selector diagnostic did not preserve JSON output: {encoded}")
            if args.stage == "default" and record.get("message") != warning:
                raise AssertionError(f"JSON selector warning changed: {encoded}")
            output = invoke(compiler, root, "fix", valid, selector, status=expected, diagnostic=message)
            if output.count(message) != 1:
                raise AssertionError(f"fix must report its selector once: {output}")
            if args.stage == "retirement":
                invoke(compiler, root, "check", valid, selector + "=true", status=2, diagnostic=message)
            output = invoke(compiler, root, "run", valid, "--", selector)
            if "has no effect" in output or "reference counting was removed" in output:
                raise AssertionError("guest arguments were interpreted as compiler selectors")
    print(f"checked ownership CLI {args.stage}: passed")


if __name__ == "__main__":
    main()
