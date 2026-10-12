#!/usr/bin/env python3
"""Native cache acceptance inside the reviewed bundle. Run under build admission.

Each work directory must be new. This script mutates only its owned project,
bundle copies and tool copies; it never writes through a system library alias.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
LEAF = "public func compute(count: int) -> int:\n    mut sum = 0\n    for i in range(count):\n        sum += i\n    return sum\n"


class Qualification:
    def __init__(self, args):
        self.args = args
        self.work = args.work.resolve()
        self.work.mkdir(parents=True)
        self.project = self.work / "project"
        self.project.mkdir()
        self.bundle = args.bundle.resolve()
        self.zig = args.zig.resolve()
        self.compiler = args.compiler.resolve()
        self.report = {"compiler_sha256": hashlib.sha256(self.compiler.read_bytes()).hexdigest(), "planner_mode": args.planner_mode, "commands": [], "checks": {}}
        (self.project / "app.my").write_text("import leaf\nimport other\n\nfunc main(out: Stream) -> int:\n    out.print(leaf.compute(6), other.compute(3))\n    return 0\n")
        (self.project / "leaf.my").write_text(LEAF)
        (self.project / "other.my").write_text("public func compute(value: int) -> int:\n    return value + 1\n")

    def save(self):
        self.args.report.parent.mkdir(parents=True, exist_ok=True)
        self.args.report.write_text(json.dumps(self.report, indent=2) + "\n")

    def command(self, label, arguments, *, environment=None, allow_failure=False):
        argv = [str(ROOT / "scripts/native-bundle.sh"), str(self.bundle), str(self.zig.parent),
                str(self.compiler), str(self.project), "--", *arguments]
        env = os.environ.copy()
        changes = {"MYLANG_CACHE_PLAN_MODE": self.args.planner_mode, **(environment or {})}
        env.update(changes)
        result = subprocess.run(argv, text=True, capture_output=True, env=env, timeout=180)
        self.report["commands"].append({"label": label, "argv": argv, "environment_changes": changes,
                                        "status": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
        self.save()
        if not allow_failure and result.returncode:
            raise AssertionError(f"{label}: {result.stderr}")
        return result

    def build(self, label, *, release=False, environment=None, allow_failure=False):
        extra = ["--release"] if release else []
        result = self.command(label, ["build", "app.my", "-o", "program", "--cache-dir", "cache", "--report", *extra],
                              environment=environment, allow_failure=allow_failure)
        rows = [json.loads(line) for line in result.stderr.splitlines() if line.startswith('{"version":"cache-report-v1"')]
        return result, rows[-1] if rows else None

    def check(self, name, value):
        self.report["checks"][name] = "passed" if value else "failed"
        self.save()
        if not value:
            raise AssertionError(name)

    def functional(self):
        _, cold = self.build("fresh")
        self.check("fresh", cold["compiled"] == cold["units"] and cold["units"] >= 4 and cold["program"] == "linked")
        _, warm = self.build("unchanged")
        self.check("unchanged_replay", warm["program"] == "replayed")
        shutil.rmtree(self.project / "cache/replay-v1")
        _, objects = self.build("deleted-replay")
        self.check("object_reuse_after_deleted_replay", objects["compiled"] == 0 and objects["reused"] == cold["units"])
        (self.project / "leaf.my").write_text(LEAF.replace("sum += i", "sum += i * 2"))
        _, edited = self.build("edited-leaf")
        self.check("one_affected_unit", edited["compiled"] == 1 and edited["reused"] == cold["units"] - 1)
        result = self.command("guest-output", ["run", "app.my", "--cache-dir", "cache"])
        self.check("guest_output", result.stdout == "30 4\n")
        (self.project / "tests.my").write_text("import leaf\n\npublic func test_leaf() -> bool:\n    return leaf.compute(6) == 30\n\npublic func test_constant() -> bool:\n    return 4 == 4\n")
        for release in (False, True):
            suffix = "release" if release else "debug"
            extra = ["--release"] if release else []
            first = self.command(suffix + "-tests-fresh", ["test", "tests.my", "--json", "--cache-dir", "test-cache-" + suffix, *extra])
            second = self.command(suffix + "-tests-warm", ["test", "tests.my", "--json", "--cache-dir", "test-cache-" + suffix, *extra])
            a, b = json.loads(first.stdout), json.loads(second.stdout)
            self.check(suffix + "_test_receipts", a["passed"] == 2 and a["cached"] == 0 and b["passed"] == 0 and b["cached"] == 2)
        _, released = self.build("release-fresh", release=True)
        _, repeated = self.build("release-warm", release=True)
        self.check("release_build_replay", released["compiled"] == 1 and repeated["program"] == "replayed")
        shutil.rmtree(self.project / "cache/replay-v1")
        _, released_objects = self.build("release-deleted-replay", release=True)
        self.check("release_object_reuse", released_objects["compiled"] == 0 and released_objects["reused"] == 1)
        # Force the object layer to examine damaged owned entries.
        objects = list((self.project / ".selka-native/runtime/units-v1").glob("*.o"))
        self.check("owned_objects_present", len(objects) > 0)
        for path in objects:
            path.write_bytes(b"damaged object")
        shutil.rmtree(self.project / "cache/replay-v1", ignore_errors=True)
        _, recovered = self.build("corrupt-objects")
        self.check("corrupt_object_rejection", recovered["compiled"] == recovered["units"] and recovered["reused"] == 0)

    def refusal(self, label, *, environment=None):
        result, report = self.build(label, environment=environment, allow_failure=True)
        refused = result.returncode != 0 or (report and report["program"] != "replayed" and report["reused"] == 0)
        self.check(label + "_refuses_cached_success", bool(refused))
        self.report["checks"][label + "_uncached_build"] = "passed" if result.returncode == 0 else "failed"
        self.save()

    def adverse(self):
        original_bundle = self.bundle
        self.bundle = self.work / "owned-bundle"
        shutil.copytree(original_bundle, self.bundle, symlinks=True)
        self.build("owned-bundle-baseline")
        root = self.bundle / "rootfs"
        library = root / "usr/lib/x86_64-linux-gnu/libgcc_s.so.1"
        data = library.read_bytes()
        library.write_bytes(data + b"owned mutation")
        self.refusal("library-change")
        library.write_bytes(data)
        self.build("library-restored")
        distro = root / "etc/debian_version"
        data = distro.read_bytes()
        distro.write_bytes(data + b"owned mutation")
        self.refusal("discovery-change")
        distro.write_bytes(data)
        self.build("discovery-restored")
        absent = root / "etc/lsb-release"
        absent.write_text("owned negative dependency\n")
        self.refusal("absent-input-created")
        absent.unlink()
        membership = root / "usr/lib/gcc/x86_64-linux-gnu/99"
        membership.mkdir(parents=True)
        self.refusal("discovery-membership")
        shutil.rmtree(root / "usr/lib/gcc")
        alias = root / "usr/lib64/ld-linux-x86-64.so.2"
        target = os.readlink(alias)
        shutil.copyfile(root / "usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2", root / "usr/lib/x86_64-linux-gnu/owned-loader")
        alias.unlink()
        alias.symlink_to("../lib/x86_64-linux-gnu/owned-loader")
        self.refusal("symlink-retarget")
        alias.unlink()
        alias.symlink_to(target)
        (root / "usr/lib/x86_64-linux-gnu/owned-loader").unlink()
        self.bundle = original_bundle
        self.build("environment-baseline")
        self.refusal("environment-override", environment={"CPATH": "/work/owned-headers"})
        self.build("environment-restored")
        original_zig = self.zig
        tools = self.work / "owned-toolchain"
        shutil.copytree(self.zig.parent, tools, symlinks=True, copy_function=os.link)
        self.zig = tools / "zig"
        self.build("tool-copy-baseline")
        # Atomic replacement breaks the fixture's hardlink before any mutation.
        replacement = tools / "owned-zig"
        replacement.write_bytes(self.zig.read_bytes() + b"owned mutation")
        replacement.chmod(0o755)
        replacement.replace(self.zig)
        self.refusal("tool-change")
        self.zig = original_zig
        self.build("tool-restored")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--adverse", action="store_true")
    parser.add_argument("--planner-mode", choices=("component", "reference"), default="component")
    args = parser.parse_args()
    q = Qualification(args)
    q.functional()
    if args.adverse:
        q.adverse()
    q.save()
    print(json.dumps(q.report["checks"], indent=2))
    if "failed" in q.report["checks"].values():
        raise SystemExit(1)


if __name__ == "__main__":
    main()
