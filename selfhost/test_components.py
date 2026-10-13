#!/usr/bin/env python3
"""Blackbox tests of the native component coordinator; Python is test-only."""
import argparse
import contextlib
import hashlib
import io
import json
import os
import platform
from pathlib import Path
import shlex
import stat
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock
import test_component_native as native_qualification
from test_component_native import require_completed_tests

BUILDER = None
ZIG = None


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


class ComponentCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="native-components-test-")
        self.addCleanup(self.temp.cleanup)
        self.workspace = Path(self.temp.name)
        self.root = self.workspace / "project"
        self.sources = self.root / "selfhost/components/test_index"
        self.sources.mkdir(parents=True)
        (self.sources / "main.my").write_text("func main() -> int:\n    return 0\n")
        self.planner_sources = self.root / "selfhost/components/cache_plan"
        self.planner_sources.mkdir(parents=True)
        (self.planner_sources / "main.my").write_text("func main() -> int:\n    return 0\n")
        self.cache = self.workspace / "cache"
        self.install = self.workspace / "installed"
        (self.workspace / "guardian-zig").mkdir()
        self.archive_source = self.workspace / "archive-source"
        (self.archive_source / "src").mkdir(parents=True)
        self.version = subprocess.check_output([ZIG, "version"], text=True).strip()
        (self.archive_source / ".zigversion").write_text(self.version + "\n")
        (self.archive_source / "src/runtime.c").write_text("pinned-runtime")
        self.seed_script = (
            "#!/bin/sh\n"
            "case \"$ZIG_GLOBAL_CACHE_DIR\" in */cache/zig-global) ;; *) exit 12;; esac\n"
            "printf 'component\\n' >> \"$COMPONENT_FIXTURE_LOG\"\n"
            "printf 'where:%s %s %s %s\\n' \"$PWD\" \"$TMPDIR\" \"$ZIG_LOCAL_CACHE_DIR\" \"$*\" >> \"$COMPONENT_FIXTURE_LOG\"\n"
            "case \" $* \" in *' --experimental-zero-rc '*) printf 'owned\\n' >> \"$COMPONENT_FIXTURE_LOG\";; esac\n"
            "test \"${COMPONENT_FIXTURE_FAIL:-0}\" = 0 || exit 7\n"
            "while test $# -gt 0; do\n"
            "  if test \"$1\" = -o; then shift; printf '%s' \"${COMPONENT_FIXTURE_OUTPUT:-native-component}\" > \"$1\"; exit 0; fi\n"
            "  shift\n"
            "done\nexit 8\n"
        )
        self.write_archive()
        library = self.workspace / "lib"
        library.mkdir()
        (library / "runtime.h").write_text("pinned-library")
        self.zig = self.workspace / "fake-zig"
        self.zig.write_text(
            "#!/bin/sh\ncase \"$1\" in\n"
            f"version) printf '%s\\n' {shlex.quote(self.version)};;\n"
            f"env) printf '%s\\n' {shlex.quote(f'.lib_dir = "{library}", .target = "test-native"')};;\n"
            "build) printf 'seed\\n' >> \"$COMPONENT_FIXTURE_LOG\"; "
            "printf 'step:%s\\n' \"$2\" >> \"$COMPONENT_FIXTURE_LOG\"; "
            "test ! -e abandoned || exit 9; test \"$(cat src/runtime.c)\" = pinned-runtime || exit 10; "
            "mkdir -p zig-out/focus; cp src/fake-seed zig-out/focus/mylang; chmod 755 zig-out/focus/mylang;;\n"
            "*) exit 11;;\nesac\n"
        )
        self.zig.chmod(0o755)
        self.log = self.workspace / "calls.log"
        self.environment = {name: value for name, value in os.environ.items()
                            if not name.startswith("MYLANG_") and name != "ZIG"}
        self.environment["COMPONENT_FIXTURE_LOG"] = str(self.log)

    def write_archive(self):
        (self.archive_source / "src/fake-seed").write_text(self.seed_script)
        (self.archive_source / "src/fake-seed").chmod(0o755)
        self.archive = self.workspace / "pinned.tar"
        with tarfile.open(self.archive, "w") as bundle:
            bundle.add(self.archive_source / ".zigversion", arcname=".zigversion")
            bundle.add(self.archive_source / "src", arcname="src")
        pin = {"zig": self.version, "commit": "immutable-commit", "archive_sha256": digest(self.archive)}
        (self.root / "selfhost/component-seed.json").write_text(json.dumps(pin))

    def invoke(self, *flags, success=True, umask=-1):
        command = [BUILDER, "--root", str(self.root), "--zig", str(self.zig),
                   "--cache-dir", str(self.cache), "--install-dir", str(self.install),
                   "--seed-source", str(self.archive), *flags]
        result = subprocess.run(command, env=self.environment, capture_output=True, text=True, timeout=30, umask=umask)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.strip().splitlines()[0]
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(result.stderr.startswith("components: "), result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("stack trace", result.stderr.lower())
        return result.stderr

    def calls(self, kind="component"):
        return self.log.read_text().splitlines().count(kind)

    def owned_pin(self):
        pin = json.loads((self.root / "selfhost/component-seed.json").read_text())
        pin.update(memory_mode="zero-rc-v1", recipe={
            "step": "seed-compiler", "optimize": "ReleaseFast", "target": "native"})
        path = self.root / "selfhost/component-owned-compiler.json"
        path.write_text(json.dumps(pin))
        return path

    def test_owned_route_builds_independent_compiler_and_separates_component_cache(self):
        pin = self.owned_pin()
        historical_pin = self.root / "selfhost/component-seed.json"
        before = historical_pin.read_bytes()
        legacy = self.invoke()
        owned = self.invoke("--owned-compiler-pin", str(pin))
        self.assertNotEqual(legacy, owned)
        self.assertEqual(self.calls("step:affected-compiler"), 1)
        self.assertEqual(self.calls("step:seed-compiler"), 1)
        self.assertEqual(self.calls("owned"), 2)
        receipt = json.loads((self.cache / "artifacts" / owned / "receipt.json").read_text())
        self.assertIn("zero-rc-v1", receipt["identity"]["flags"])
        self.assertEqual(json.loads((self.install / "test-index.json").read_text())["memory_mode"], "zero-rc-v1")
        self.assertEqual(owned, self.invoke("--owned-compiler-pin", str(pin)))
        self.assertEqual(self.calls("component"), 4)
        self.assertEqual(before, historical_pin.read_bytes())

    def test_owned_route_refuses_component_dependent_seed_recipe(self):
        path = self.owned_pin()
        pin = json.loads(path.read_text())
        pin["recipe"]["step"] = "affected-compiler"
        path.write_text(json.dumps(pin))
        self.assertIn("independent", self.invoke("--owned-compiler-pin", str(path), success=False))
        self.assertFalse(self.log.exists())

    def test_owned_route_refuses_wrong_memory_mode(self):
        path = self.owned_pin()
        pin = json.loads(path.read_text())
        pin["memory_mode"] = "rc"
        path.write_text(json.dumps(pin))
        self.assertIn("zero-rc-v1", self.invoke("--owned-compiler-pin", str(path), success=False))
        self.assertFalse(self.log.exists())

    def test_extracted_seed_cache_and_tmp_are_private_but_global_cache_is_preserved(self):
        self.zig.write_text(self.zig.read_text().replace(
            'build) ', 'build) test "$ZIG_LOCAL_CACHE_DIR" = "$PWD/.zig-cache" || exit 21; '
            'test "$TMPDIR" = "$PWD/.tmp/component-compiler" || exit 22; '
            'test -d "$TMPDIR" || exit 23; '
            'test "$ZIG_GLOBAL_CACHE_DIR" = "$COMPONENT_FIXTURE_GLOBAL" || exit 24; '))
        local = self.workspace / "caller-local"
        temporary = self.workspace / "caller-tmp"
        global_cache = self.workspace / "caller-global"
        self.environment.update(ZIG_LOCAL_CACHE_DIR=str(local), TMPDIR=str(temporary),
                                ZIG_GLOBAL_CACHE_DIR=str(global_cache), COMPONENT_FIXTURE_GLOBAL=str(global_cache))
        binary = Path(self.invoke("--seed-only", "--owned-compiler-pin", str(self.owned_pin())))
        receipt = json.loads((binary.parents[3] / "receipt.json").read_text())
        self.assertEqual(receipt["recipe"]["build_environment"], "private-local-and-tmp-v1")
        self.assertFalse(local.exists())
        self.assertFalse(temporary.exists())
        self.assertEqual(Path(self.invoke("--seed-only", "--owned-compiler-pin", str(self.owned_pin()))), binary)
        self.assertEqual(self.calls("seed"), 1)

    def artifact(self, key):
        return self.cache / "artifacts" / key / "test-index"

    def test_unchanged_cache_and_source_change(self):
        first = self.invoke()
        self.assertEqual(first, self.invoke())
        self.assertEqual(self.calls(), 2)
        self.assertEqual(self.calls("seed"), 1)
        receipt = json.loads((self.cache / "artifacts" / first / "receipt.json").read_text())
        if platform.system() == "Linux":
            cpu = receipt["identity"]["target"]["cpu"]
            self.assertTrue(cpu, "native cache identity omitted Linux CPU metadata")
            machine = platform.machine().lower()
            if machine in {"x86_64", "amd64", "i386", "i686"}:
                self.assertTrue(cpu.get("model name", "").strip(), "missing CPU model")
                self.assertTrue(cpu.get("flags", "").strip(), "missing CPU feature flags")
            elif machine in {"aarch64", "arm64"} or machine.startswith("arm"):
                self.assertTrue(cpu.get("Features", "").strip(), "missing ARM CPU features")
        (self.sources / "graph.my").write_text("# new module\n")
        self.assertNotEqual(first, self.invoke())
        self.assertEqual(self.calls(), 3)

    def test_planner_change_is_independent_of_test_index(self):
        index_key = self.invoke()
        before = json.loads((self.install / "cache-plan.json").read_text())
        self.assertEqual(before["component"], "cache-plan")
        (self.planner_sources / "graph.my").write_text("# planner-only edit\n")
        self.assertEqual(index_key, self.invoke())
        after = json.loads((self.install / "cache-plan.json").read_text())
        self.assertNotEqual(before["key"], after["key"])
        self.assertEqual(self.calls(), 3)
        self.assertEqual(self.calls("seed"), 1)

    def test_identity_covers_embedded_input_bytes(self):
        (self.sources / "schema.json").write_text('{"version":1}')
        first = self.invoke()
        (self.sources / "schema.json").write_text('{"version":2}')
        self.assertNotEqual(first, self.invoke())

    def test_toolchain_library_change_requalifies_seed(self):
        first = self.invoke()
        (self.workspace / "lib/runtime.h").write_text("changed-library")
        self.assertNotEqual(first, self.invoke())
        self.assertEqual(self.calls("seed"), 2)

    def test_seed_qualification_changes_key(self):
        first = self.invoke()
        self.seed_script += "# changed qualified seed\n"
        self.write_archive()
        self.assertNotEqual(first, self.invoke())
        self.assertEqual(self.calls("seed"), 2)

    @unittest.skipUnless(os.name == "posix", "POSIX installation modes")
    def test_installed_resources_readable_and_receipt_private(self):
        key = self.invoke(umask=0o077)
        manifest_path = self.install / "test-index.json"
        manifest = json.loads(manifest_path.read_text())
        self.assertEqual(stat.S_IMODE(manifest_path.stat().st_mode), 0o644)
        self.assertEqual(stat.S_IMODE((self.install / manifest["artifact"]).stat().st_mode), 0o555)
        self.assertEqual(stat.S_IMODE((self.cache / "artifacts" / key / "receipt.json").stat().st_mode), 0o600)
        self.assertEqual(digest(self.install / manifest["artifact"]), manifest["sha256"])

    def test_corrupt_artifact_rejected_including_uncached(self):
        key = self.invoke()
        self.artifact(key).write_bytes(b"corrupt")
        self.invoke(success=False)
        self.invoke("--uncached", success=False)
        self.assertEqual(self.calls(), 2)

    def test_missing_artifact_rejected_including_uncached(self):
        key = self.invoke()
        self.artifact(key).unlink()
        self.invoke(success=False)
        self.invoke("--uncached", success=False)
        self.assertEqual(self.calls(), 2)

    def test_installed_artifact_corruption_does_not_replace_selection(self):
        self.invoke()
        manifest_path = self.install / "test-index.json"
        before = manifest_path.read_bytes()
        manifest = json.loads(before)
        installed = self.install / manifest["artifact"]
        installed.chmod(0o755)
        installed.write_bytes(b"corrupt installation")
        self.invoke(success=False)
        self.assertEqual(manifest_path.read_bytes(), before)

    def test_failed_build_preserves_selected_installation(self):
        self.invoke()
        before = (self.install / "test-index.json").read_bytes()
        (self.sources / "main.my").write_text("changed")
        self.environment["COMPONENT_FIXTURE_FAIL"] = "1"
        self.invoke(success=False)
        self.assertEqual(before, (self.install / "test-index.json").read_bytes())
        self.assertFalse(list((self.cache / "artifacts").glob("*.build")))
        self.assertFalse((self.cache / "staging/component").exists())

    def test_failed_planner_build_preserves_each_selected_installation(self):
        self.invoke()
        before_index = (self.install / "test-index.json").read_bytes()
        before_planner = (self.install / "cache-plan.json").read_bytes()
        (self.planner_sources / "main.my").write_text("changed planner")
        self.environment["COMPONENT_FIXTURE_FAIL"] = "1"
        self.invoke(success=False)
        self.assertEqual(before_index, (self.install / "test-index.json").read_bytes())
        self.assertEqual(before_planner, (self.install / "cache-plan.json").read_bytes())
        self.assertFalse(list((self.cache / "artifacts").glob("*.build")))

    def test_caller_zig_global_cache_does_not_reach_component_builds(self):
        self.environment["ZIG_GLOBAL_CACHE_DIR"] = str(self.workspace / "caller-zig-global")
        first = self.invoke()
        identity = json.loads((self.cache / "artifacts" / first / "receipt.json").read_text())["identity"]
        self.assertEqual(identity["build_cache_root"], str(self.cache))
        self.assertIn("private-zig-global-v1", identity["flags"])
        self.environment["ZIG_GLOBAL_CACHE_DIR"] = str(self.workspace / "different-zig-global")
        self.assertEqual(first, self.invoke("--uncached"))
        self.assertEqual(self.calls(), 4)
        self.assertFalse((self.workspace / "caller-zig-global").exists())
        self.assertFalse((self.workspace / "different-zig-global").exists())

    def places(self):
        return [line[len("where:"):] for line in self.log.read_text().splitlines() if line.startswith("where:")]

    def test_builder_identity_is_independent_of_builder_location(self):
        global BUILDER
        first = self.invoke()
        identity = json.loads((self.cache / "artifacts" / first / "receipt.json").read_text())["identity"]
        self.assertEqual(identity["format"], 3)
        self.assertNotIn("coordinator_sha256", identity)
        coordinator = identity["coordinator"]
        self.assertEqual(coordinator["domain"], "selka-components-builder-v1")
        self.assertRegex(coordinator["sources_sha256"], "^[0-9a-f]{64}$")
        self.assertEqual(set(coordinator), {"domain", "sources_sha256", "zig_version", "optimize", "backend", "target"})
        self.assertNotIn(str(Path(BUILDER).parent), json.dumps(coordinator))
        relocated = self.workspace / "elsewhere/deeper/selka-components"
        relocated.parent.mkdir(parents=True)
        relocated.write_bytes(Path(BUILDER).read_bytes() + b"\0relocated builder bytes")
        relocated.chmod(0o755)
        original, BUILDER = BUILDER, str(relocated)
        try:
            self.assertEqual(first, self.invoke())
        finally:
            BUILDER = original
        self.assertEqual(self.calls(), 2)

    def test_every_key_compiles_in_one_stable_staging_directory(self):
        first = self.invoke()
        (self.sources / "graph.my").write_text("# another key\n")
        second = self.invoke()
        self.assertNotEqual(first, second)
        self.invoke("--uncached")
        places = self.places()
        self.assertEqual(len(places), 5)  # two, then the changed test-index, then two uncached
        staging = self.cache / "staging/component"
        for place in places:
            directory, temporary, local, arguments = place.split(" ", 3)
            self.assertEqual(directory, str(staging))
            self.assertEqual(temporary, str(staging / "tmp"))
            self.assertEqual(local, str(staging / "cache/zig-local"))
            self.assertIn(str(staging / "src/main.my"), arguments)
        outputs = {place.split(" -o ", 1)[1].split(" ", 1)[0] for place in places}
        self.assertEqual(outputs, {str(staging / "test-index"), str(staging / "cache-plan")})
        self.assertFalse(staging.exists())
        self.assertFalse(list((self.cache / "artifacts").glob("*.build")))

    def test_uncached_build_checks_reproducibility(self):
        first = self.invoke()
        self.assertEqual(first, self.invoke("--uncached"))
        self.assertEqual(self.calls(), 4)
        self.environment["COMPONENT_FIXTURE_OUTPUT"] = "different"
        self.invoke("--uncached", success=False)
        self.assertEqual(self.artifact(first).read_bytes(), b"native-component")

    def test_abandoned_seed_recovers_and_requalifies(self):
        binary = Path(self.invoke("--seed-only"))
        directory = binary.parents[3]
        receipt = directory / "receipt.json"
        first = json.loads(receipt.read_text())
        receipt.unlink()
        (directory / "source/abandoned").write_text("interrupted build")
        binary.write_bytes(b"partial compiler")
        self.assertEqual(Path(self.invoke("--seed-only")), binary)
        self.assertEqual(json.loads(receipt.read_text()), first)
        self.assertEqual(digest(binary), first["sha256"])
        self.assertEqual(self.calls("seed"), 2)
        self.invoke("--seed-only")
        self.assertEqual(self.calls("seed"), 2)

    def test_malformed_component_receipt_fails_concisely(self):
        key = self.invoke()
        (self.cache / "artifacts" / key / "receipt.json").write_text("{")
        self.invoke(success=False)
        self.assertEqual(self.calls(), 2)

    def test_seed_archive_digest_mismatch_fails_concisely(self):
        self.archive.write_bytes(b"corrupt archive")
        self.invoke("--seed-only", success=False)
        self.assertFalse(list(self.cache.glob("seeds/*/receipt.json")))

    def test_malformed_seed_receipt_fails_concisely(self):
        binary = Path(self.invoke("--seed-only"))
        (binary.parents[3] / "receipt.json").write_text("{")
        self.invoke("--seed-only", success=False)
        self.assertEqual(self.calls("seed"), 1)

    def test_qualified_seed_digest_mismatch_fails_concisely(self):
        binary = Path(self.invoke("--seed-only"))
        binary.write_bytes(b"corrupt seed")
        self.invoke("--seed-only", success=False)
        self.assertEqual(self.calls("seed"), 1)


class NativeQualificationTests(unittest.TestCase):
    def report(self, statuses):
        names = ("passed", "cached", "failed", "skipped", "unsupported")
        return dict(version="native-tests-v1", tests=[dict(name=f"test_{index}", status=status)
                    for index, status in enumerate(statuses)], **{name: statuses.count(name) for name in names})

    def test_completed_native_tests_qualify(self):
        require_completed_tests(json.dumps(self.report(["passed", "passed"])))

    def test_unsupported_or_incomplete_native_tests_never_qualify(self):
        for statuses in (["unsupported"], ["passed", "unsupported"], ["failed"], ["skipped"], []):
            with self.subTest(statuses=statuses), self.assertRaises(RuntimeError):
                require_completed_tests(json.dumps(self.report(statuses)))

    def test_malformed_or_inconsistent_native_test_reports_refuse(self):
        valid = self.report(["passed"])
        for change in (dict(version="unknown"), dict(passed=0), dict(unsupported=None), dict(tests=[dict(status="unknown")])):
            with self.subTest(change=change), self.assertRaises(RuntimeError):
                require_completed_tests(json.dumps(dict(valid, **change)))

    def test_owned_qualification_uses_one_pin_archive_and_installed_component_set(self):
        with tempfile.TemporaryDirectory(prefix="component-qualification-routing-") as temporary:
            directory = Path(temporary)
            for name in ("test-index", "cache-plan"):
                artifact = directory / name
                artifact.write_bytes(name.encode())
                (directory / f"{name}.json").write_text(json.dumps(dict(
                    artifact=name, sha256=digest(artifact), memory_mode="zero-rc-v1")))
            pin, archive = directory / "owned-pin.json", directory / "source.tar"
            args = ["test_component_native.py", "--zig", "pinned-zig", "--builder", "independent-builder",
                    "--component-dir", str(directory), "--owned-compiler-pin", str(pin), "--seed-source", str(archive)]
            outputs = ["/qualified-source/zig-out/focus/mylang\n"] + [json.dumps(self.report(["passed"]))] * 4
            with mock.patch.object(native_qualification.sys, "argv", args), \
                 mock.patch.object(native_qualification.subprocess, "check_output", side_effect=outputs) as checked, \
                 mock.patch.object(native_qualification.subprocess, "run") as executed, \
                 contextlib.redirect_stdout(io.StringIO()):
                native_qualification.main()
            request = checked.call_args_list[0].args[0]
            self.assertEqual(request[request.index("--owned-compiler-pin") + 1], pin)
            self.assertEqual(request[request.index("--seed-source") + 1], archive)
            for call in checked.call_args_list[1:]:
                self.assertIn("--experimental-zero-rc", call.args[0])
                self.assertIn("--json", call.args[0])
                self.assertEqual(call.kwargs["env"]["MYLANG_COMPONENT_DIR"], str(directory))
            self.assertEqual(executed.call_count, 6)
            for call in executed.call_args_list:
                self.assertEqual(call.kwargs["env"]["MYLANG_COMPONENT_DIR"], str(directory))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builder", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    BUILDER = str(args.builder.resolve())
    ZIG = str(args.zig.resolve())
    unittest.main(argv=[__file__, *remaining])
