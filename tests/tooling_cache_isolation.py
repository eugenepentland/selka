#!/usr/bin/env python3
"""Gate the no-cache and doctest cache boundaries in an isolated working directory."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import resource


def run(compiler, argv, cwd, env=None, status=0, **kwargs):
    result = subprocess.run([str(compiler), *argv], cwd=cwd, env=env, capture_output=True, text=True, timeout=120, **kwargs)
    if result.returncode != status:
        raise AssertionError(f"{argv}: exit {result.returncode}, wanted {status}\n{result.stdout}\n{result.stderr}")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--compiler", type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    with tempfile.TemporaryDirectory(prefix="tooling-isolation-") as temporary:
        root = Path(temporary)
        work = root / "work"
        work.mkdir()
        source = work / "main.my"
        source.write_text('public func test_ok() -> bool:\n    return True\n\nfunc main() -> int:\n    return 0\n')
        cache = root / "selected-cache"
        # spec-case: CLI-CACHE-ISOLATION-1
        run(compiler, ["test", str(source), "--no-cache", "--cache-dir", str(cache)], work)
        assert not (work / ".mylang-cache").exists(), "test --no-cache leaked a cwd cache"
        run(compiler, ["build", str(source), "-o", str(root / "built"), "--no-cache", "--cache-dir", str(cache)], work)
        # --no-cache builds in a private directory under the explicit cache and removes it
        # (NEW-CORE-S5-NO-CACHE-1): nothing is published, and nothing goes to the cwd.
        assert cache.is_dir() and not any(path.name.startswith("no-cache-") for path in cache.iterdir()), "build --no-cache left its private cache"
        assert not (work / ".mylang-cache").exists(), "build --no-cache leaked a cwd cache"
        docs = root / "documentation"
        docs.mkdir()
        (docs / "README.md").write_text("```mylang\nfunc main() -> int:\n    return 0\n```\n")
        scratch = root / "scratch"
        scratch.mkdir()
        environ = dict(os.environ, TMPDIR=str(scratch))
        run(compiler, ["doctest", str(docs), "--jobs", "1"], work, env=environ)
        assert not (docs / ".mylang-cache").exists(), "doctest wrote its document root"
        assert not (work / ".mylang-cache").exists(), "doctest children leaked a cwd cache"
        assert not list(scratch.glob("doctest-*")), "doctest left its scratch workspace"
        source.write_text('func recurse(n: int) -> bool:\n    if n == 0:\n        return True\n    return recurse(n - 1)\n\npublic func test_depth() -> bool:\n    return recurse(20)\n')
        failure = run(compiler, ["test", str(source), "--no-cache", "--cache-dir", str(cache), "--max-frames", "2"], work, status=1)
        assert "R_FRAME_LIMIT" in failure.stdout + failure.stderr
        assert "--max-frames=N" in failure.stdout + failure.stderr
        assert "--max-memory" in failure.stdout + failure.stderr
        # spec-case: MEMORY-HOST-GUEST-1
        source.write_text('func main() -> int:\n    return 0\n')
        # 300,000 frames reserve over 9 GiB virtually, exceeding the host's 8 GiB
        # ceiling without committing pages. The guest's explicit 12G budget fits.
        run(compiler, ["run", str(source), "--max-frames=300000", "--max-memory=12G", "--cache-dir=" + str(cache)], work)
        # A 6GiB external caller limit survives the compiler's tighter 4GiB
        # host guard: a 5GiB reservation fits after restoration, 9GiB does not.
        limited_environment = dict(os.environ, MYLANG_HOST_MEMORY_LIMIT="4G")
        def external_limit():
            resource.setrlimit(resource.RLIMIT_AS, (6 << 30, resource.RLIM_INFINITY))
        run(compiler, ["run", str(source), "--max-frames=160000", "--max-memory=12G", "--cache-dir=" + str(cache)], work, env=limited_environment, preexec_fn=external_limit)
        run(compiler, ["run", str(source), "--max-frames=300000", "--max-memory=12G", "--cache-dir=" + str(cache)], work, env=limited_environment, status=2, preexec_fn=external_limit)
    print("tooling isolation: no-cache test/build, doctest, frame advice and guest host-limit separation passed")


if __name__ == "__main__":
    main()
