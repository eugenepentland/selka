#!/usr/bin/env python3
"""Build a guest executable through C using the repository's pinned Zig."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import time


def publish(candidate, output):
    """Keep identical executable files; atomically replace only a complete build."""
    if output.is_file() and os.access(output, os.X_OK):
        if candidate.stat().st_size == output.stat().st_size:
            with candidate.open('rb') as fresh, output.open('rb') as old:
                while True:
                    chunk = fresh.read(65536)
                    if chunk != old.read(65536):
                        break
                    if not chunk:
                        return False
    os.replace(candidate, output)
    return True


def compile_native(zig, mode, temporary, provider, candidate):
    started = time.monotonic()
    optimize = "-O0" if mode == "Debug" else "-O2"

    def run(arguments, cwd=None, env=None):
        remaining = 180 - (time.monotonic() - started)
        if remaining <= 0:
            raise subprocess.TimeoutExpired(arguments, 180)
        return subprocess.run([zig, "cc", *arguments], timeout=remaining, cwd=cwd, env=env).returncode == 0

    generated = temporary / 'program.o'
    flags = ["-std=c11", optimize, "-fdebug-compilation-dir=mylang-generated",
             "-ffile-prefix-map=" + str(temporary) + "=mylang-generated",
             "-fdebug-prefix-map=" + str(temporary) + "=mylang-generated"]
    if provider is not None:
        flags.append("-DMYLANG_NATIVE_PROVIDER=1")
    if not run([*flags, '-c', 'program.c', '-o', str(generated)], cwd=temporary):
        return False
    objects = [str(generated)]
    if provider is not None:
        adapter = temporary / 'provider.o'
        # Assembly .incbin inputs are not necessarily tracked by Zig's C cache.
        # Use fresh provider cache storage while preserving the caller's directory.
        provider_env = dict(os.environ, ZIG_GLOBAL_CACHE_DIR=str(temporary / 'provider-cache'),
                            ZIG_LOCAL_CACHE_DIR=str(temporary / 'provider-local-cache'))
        if not run(['-std=c11', optimize, '-I', str(Path(__file__).resolve().parents[1] / 'src'),
                    '-c', str(provider.resolve()), '-o', str(adapter)], env=provider_env):
            return False
        objects.append(str(adapter))
    return run([optimize, *objects, '-o', str(candidate)])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--project", action="store_true", help="compile a module entry and its reachable imports")
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, default=Path("zig-out/bin/mylang"))
    parser.add_argument("--provider", type=Path, help="trusted C adapter implementing native_providers.h")
    parser.add_argument("--zig", default="zig")
    parser.add_argument("--mode", choices=["Debug", "ReleaseFast"], default="Debug")
    parser.add_argument("--report", action="store_true", help="emit JSON build timings and output publication status on stdout")
    args = parser.parse_args()
    try:
        zig = shutil.which(args.zig)
        if zig is None:
            raise FileNotFoundError(args.zig)
        zig = str(Path(zig).resolve())
        expected = (Path(__file__).resolve().parents[1] / ".zigversion").read_text().strip()
        actual = subprocess.run([zig, "version"], check=True, capture_output=True, text=True, timeout=30).stdout.strip()
        if actual != expected:
            parser.error(f"native compilation requires Zig {expected}; found {actual}")
        frontend_start = time.monotonic()
        generated = subprocess.run([str(args.compiler.resolve()), "emit-project-c" if args.project else "emit-c", str(args.source.resolve())], capture_output=True, timeout=60)
        frontend_seconds = time.monotonic() - frontend_start
        sys.stderr.buffer.write(generated.stderr)
        if generated.returncode:
            return generated.returncode if generated.returncode in (1, 2) else 2
        output = args.output.resolve()
        # Compile beside the destination so publication is a same-filesystem rename.
        with tempfile.TemporaryDirectory(prefix=".mylang-native-", dir=output.parent) as temp:
            source = Path(temp) / "program.c"
            candidate = Path(temp) / "program"
            source.write_bytes(generated.stdout)
            native_start = time.monotonic()
            success = compile_native(zig, args.mode, Path(temp), args.provider, candidate)
            native_seconds = time.monotonic() - native_start
            if not success:
                return 2
            changed = publish(candidate, output)
            if args.report:
                print(json.dumps({
                    "version": "native-build-v1", "mode": args.mode,
                    "zig_version": actual, "output": str(output), "output_changed": changed,
                    "generated_c_bytes": len(generated.stdout),
                    "generated_c_sha256": hashlib.sha256(generated.stdout).hexdigest(),
                    "frontend_seconds": frontend_seconds, "native_seconds": native_seconds,
                    "driver_reused_compilation": False,
                }, separators=(",", ":")))
            return 0
    except (OSError, subprocess.SubprocessError) as error:
        print(f"native: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
