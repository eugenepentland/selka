#!/usr/bin/env python3
"""Blackbox tests of the native component coordinator; Python is test-only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import tempfile
import unittest
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
        (self.sources / "main.selka").write_text("func main() -> int:\n    return 0\n")
        self.planner_sources = self.root / "selfhost/components/cache_plan"
        self.planner_sources.mkdir(parents=True)
        (self.planner_sources / "main.selka").write_text("func main() -> int:\n    return 0\n")
        self.cache = self.workspace / "cache"
        self.install = self.workspace / "installed"
        self.output_stamp = self.workspace / "component-outputs.json"
        self.version = subprocess.check_output([ZIG, "version"], text=True).strip()
        # The compiler `zig build` has just built, as a script: it logs each call and writes the component after -o.
        self.compiler_script = (
            "#!/bin/sh\n"
            # `selka native show --digest`: the toolchain identity, which the fixture's tests choose.
            "if test \"$1\" = native; then\n"
            "  test \"${COMPONENT_FIXTURE_IDENTITY_FAIL:-0}\" = 0 || exit 1\n"
            "  printf '%s\\n' \"${COMPONENT_FIXTURE_IDENTITY:-" + "a" * 64 + "}\"; exit 0\n"
            "fi\n"
            "case \"$ZIG_GLOBAL_CACHE_DIR\" in */cache/zig-global) ;; *) exit 12;; esac\n"
            "printf 'component\\n' >> \"$COMPONENT_FIXTURE_LOG\"\n"
            "printf 'stores:%s|%s|%s|%s|%s\\n' \"${SELKA_COMPILER_SHARED_CACHE-unset}\" \"${SELKA_TEST_SHARED_CACHE-unset}\" "
            "\"${SELKA_STAGE_SHARED_CACHE-unset}\" \"${SELKA_CORE_RUNTIME_CACHE-unset}\" \"${SELKA_FRONTEND_CACHE-unset}\" "
            ">> \"$COMPONENT_FIXTURE_LOG\"\n"
            "printf 'modes:%s|%s|%s\\n' \"${SELKA_CACHE_PLAN_MODE-unset}\" \"${SELKA_TEST_INDEX_MODE-unset}\" \"${SELKA_COMPONENT_DIR-unset}\" "
            ">> \"$COMPONENT_FIXTURE_LOG\"\n"
            "printf 'where:%s %s %s %s\\n' \"$PWD\" \"$TMPDIR\" \"$ZIG_LOCAL_CACHE_DIR\" \"$*\" >> \"$COMPONENT_FIXTURE_LOG\"\n"
            "test \"${COMPONENT_FIXTURE_FAIL:-0}\" = 0 || exit 7\n"
            "if test -n \"${COMPONENT_FIXTURE_MUTATE_COMPILER:-}\"; then printf changed >> \"$0\"; fi\n"
            "while test $# -gt 0; do\n"
            "  if test \"$1\" = -o; then shift; printf '%s' \"${COMPONENT_FIXTURE_OUTPUT:-native-component}\" > \"$1\"; exit 0; fi\n"
            "  shift\n"
            "done\nexit 8\n"
        )
        self.compiler = self.workspace / "zig-out/bin/selka"
        self.write_compiler()
        library = self.workspace / "lib"
        library.mkdir()
        (library / "runtime.h").write_text("pinned-library")
        self.zig = self.workspace / "fake-zig"
        self.zig.write_text(
            "#!/bin/sh\ncase \"$1\" in\n"
            f"version) printf '%s\\n' {shlex.quote(self.version)};;\n"
            f"env) printf '%s\\n' {shlex.quote(f'.lib_dir = "{library}", .target = "test-native"')};;\n"
            "*) exit 11;;\nesac\n"
        )
        self.zig.chmod(0o755)
        self.log = self.workspace / "calls.log"
        self.environment = {name: value for name, value in os.environ.items()
                            if not name.startswith("SELKA_") and name != "ZIG"}
        self.environment["COMPONENT_FIXTURE_LOG"] = str(self.log)

    def write_compiler(self):
        self.compiler.parent.mkdir(parents=True, exist_ok=True)
        self.compiler.write_text(self.compiler_script)
        self.compiler.chmod(0o755)

    def invoke(self, *flags, success=True, umask=-1):
        command = [BUILDER, "--root", str(self.root), "--zig", str(self.zig),
                   "--cache-dir", str(self.cache), "--install-dir", str(self.install),
                   "--compiler", str(self.compiler), *flags]
        result = subprocess.run(command, env=self.environment, capture_output=True, text=True, timeout=30, umask=umask)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
            lines = result.stdout.strip().splitlines()
            return lines[0] if lines else ""
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(result.stderr.startswith("components: "), result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("stack trace", result.stderr.lower())
        return result.stderr

    def input_stamp(self, *flags):
        stamp = self.workspace / "inputs.json"
        command = [BUILDER, "--root", str(self.root), "--zig", str(self.zig),
                   "--cache-dir", str(self.cache), "--install-dir", str(self.install),
                   "--compiler", str(self.compiler), "--inputs-stamp", str(stamp), *flags]
        result = subprocess.run(command, env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return stamp

    def test_input_stamp_builds_no_component(self):
        stamp = self.input_stamp()
        before = stamp.stat()
        original = stamp.read_bytes()
        self.input_stamp()
        self.assertEqual(stamp.read_bytes(), original)
        self.assertEqual(stamp.stat().st_ino, before.st_ino)
        self.assertEqual(stamp.stat().st_mtime_ns, before.st_mtime_ns)
        self.assertFalse(self.install.exists())
        self.assertFalse((self.cache / "artifacts").exists())
        self.assertFalse(self.log.exists())

    def test_input_stamp_tracks_source_content_additions_and_removals(self):
        original = self.input_stamp().read_bytes()
        added = self.sources / "new.selka"
        added.write_text("const n = 1\n")
        first = self.input_stamp().read_bytes()
        self.assertNotEqual(first, original)
        added.write_text("const n = 2\n")
        self.assertNotEqual(self.input_stamp().read_bytes(), first)
        added.unlink()
        self.assertEqual(self.input_stamp().read_bytes(), original)

    def test_input_stamp_tracks_declared_top_level_inputs(self):
        original = self.input_stamp().read_bytes()
        for name in ("added.zig", "added.json"):
            added = self.root / "selfhost" / name
            added.write_text("{}")
            self.assertNotEqual(self.input_stamp().read_bytes(), original)
            added.unlink()
        (self.root / "selfhost/notes.txt").write_text("not a declared input")
        self.assertEqual(self.input_stamp().read_bytes(), original)

    def test_input_stamp_tracks_toolchain_library_and_binary(self):
        original = self.input_stamp().read_bytes()
        (self.workspace / "lib/runtime.h").write_text("changed-library")
        library_changed = self.input_stamp().read_bytes()
        self.assertNotEqual(library_changed, original)
        with self.zig.open("a") as script:
            script.write("# changed tool bytes\n")
        self.assertNotEqual(self.input_stamp().read_bytes(), library_changed)

    def test_discovered_inputs_are_rechecked_before_build(self):
        stamp = self.input_stamp()
        self.invoke("--verify-inputs-stamp", str(stamp), "--output-stamp", str(self.output_stamp))
        (self.sources / "main.selka").write_text("changed after discovery")
        self.assertIn("inputs changed", self.invoke("--verify-inputs-stamp", str(stamp),
            "--output-stamp", str(self.output_stamp), success=False))
        self.assertFalse(self.output_stamp.exists())

    def test_discovered_inputs_are_rechecked_before_output_publication(self):
        self.compiler_script = self.compiler_script.replace(
            "exit 0; fi", 'printf "changed" >> "$COMPONENT_FIXTURE_MUTATE"; exit 0; fi')
        self.write_compiler()
        self.environment["COMPONENT_FIXTURE_MUTATE"] = str(self.sources / "main.selka")
        stamp = self.input_stamp()
        self.assertIn("inputs changed", self.invoke("--verify-inputs-stamp", str(stamp),
            "--output-stamp", str(self.output_stamp), success=False))
        self.assertFalse(self.output_stamp.exists())

    def test_restored_input_bytes_do_not_restore_build_authority(self):
        self.compiler_script = self.compiler_script.replace("exit 0; fi", (
            'cp -p "$COMPONENT_FIXTURE_MUTATE" "$COMPONENT_FIXTURE_MUTATE.restore"; '
            'printf "changed" >> "$COMPONENT_FIXTURE_MUTATE"; '
            'cp -p "$COMPONENT_FIXTURE_MUTATE.restore" "$COMPONENT_FIXTURE_MUTATE"; '
            'rm "$COMPONENT_FIXTURE_MUTATE.restore"; exit 0; fi'))
        self.write_compiler()
        source = self.sources / "main.selka"
        original = source.read_bytes()
        before = source.stat()
        self.environment["COMPONENT_FIXTURE_MUTATE"] = str(source)
        stamp = self.input_stamp()
        self.assertIn("input metadata changed", self.invoke("--verify-inputs-stamp", str(stamp),
            "--output-stamp", str(self.output_stamp), success=False))
        self.assertEqual(source.read_bytes(), original)
        self.assertEqual(source.stat().st_mtime_ns, before.st_mtime_ns)
        self.assertFalse(self.output_stamp.exists())

    def test_output_stamp_is_published_only_after_success(self):
        stamp = self.workspace / "outputs.json"
        self.invoke("--output-stamp", str(stamp))
        keys = json.loads(stamp.read_text())
        self.assertEqual(set(keys), {"test-index", "cache-plan"})
        self.assertEqual(keys["test-index"], digest(self.install / "test-index.json"))
        self.environment["COMPONENT_FIXTURE_FAIL"] = "1"
        self.invoke("--uncached", "--output-stamp", str(stamp), success=False)
        self.assertFalse(stamp.exists())

    def test_install_from_does_not_create_or_lock_component_cache(self):
        self.invoke("--output-stamp", str(self.output_stamp))
        unused_cache = self.workspace / "unused-cache"
        destination = self.workspace / "pure-install"
        self.invoke("--install-from", str(self.install), "--install-stamp", str(self.output_stamp),
                    "--install-dir", str(destination), "--cache-dir", str(unused_cache))
        self.assertFalse(unused_cache.exists())
        self.assertTrue((destination / "test-index.json").exists())
        self.assertIn("cannot be combined", self.invoke(
            "--install-from", str(self.install), "--install-stamp", str(self.output_stamp),
            "--inputs-stamp", str(self.workspace / "invalid-inputs.json"), success=False))

    def test_install_from_repairs_missing_corrupt_and_nonexecutable_outputs(self):
        self.invoke("--output-stamp", str(self.output_stamp))
        destination = self.workspace / "restored"
        flags = ("--install-from", str(self.install), "--install-stamp", str(self.output_stamp), "--install-dir", str(destination))
        self.invoke(*flags)
        manifest = json.loads((destination / "test-index.json").read_text())
        artifact = destination / manifest["artifact"]
        artifact.chmod(0o755)
        artifact.write_bytes(b"corrupted")
        self.invoke(*flags)
        self.assertEqual(digest(artifact), manifest["sha256"])
        artifact.chmod(0o644)
        self.invoke(*flags)
        self.assertEqual(stat.S_IMODE(artifact.stat().st_mode), 0o555)
        artifact.unlink()
        (destination / "test-index.json").unlink()
        self.invoke(*flags)
        self.assertEqual(digest(artifact), manifest["sha256"])
        self.assertTrue((destination / "test-index.json").exists())
        self.assertEqual(self.calls(), 2)

    def test_install_from_rejects_corrupt_or_missing_source_before_publication(self):
        self.invoke("--output-stamp", str(self.output_stamp))
        destination = self.workspace / "refused"
        manifest = json.loads((self.install / "cache-plan.json").read_text())
        artifact = self.install / manifest["artifact"]
        artifact.chmod(0o755)
        original = artifact.read_bytes()
        artifact.write_bytes(b"corrupted")
        flags = ("--install-from", str(self.install), "--install-stamp", str(self.output_stamp), "--install-dir", str(destination))
        self.assertIn("digest mismatch", self.invoke(*flags, success=False))
        self.assertFalse(destination.exists())
        artifact.unlink()
        self.assertIn("digest mismatch", self.invoke(*flags, success=False))
        self.assertFalse(destination.exists())
        artifact.write_bytes(original)
        self.invoke(*flags)
        self.assertTrue((destination / "test-index.json").exists())

    def test_install_from_rejects_manifest_path_escape(self):
        self.invoke("--output-stamp", str(self.output_stamp))
        path = self.install / "test-index.json"
        manifest = json.loads(path.read_text())
        manifest["artifact"] = "../escape"
        path.write_text(json.dumps(manifest))
        destination = self.workspace / "refused"
        self.assertIn("manifest differs from completion stamp", self.invoke(
            "--install-from", str(self.install), "--install-stamp", str(self.output_stamp),
            "--install-dir", str(destination), success=False))
        self.assertFalse(destination.exists())

    def calls(self, kind="component"):
        return self.log.read_text().splitlines().count(kind)

    def artifact(self, key):
        return self.cache / "artifacts" / key / "test-index"

    def test_unchanged_cache_and_source_change(self):
        first = self.invoke()
        self.assertEqual(first, self.invoke())
        self.assertEqual(self.calls(), 2)
        receipt = json.loads((self.cache / "artifacts" / first / "receipt.json").read_text())
        # The components are built for the AVX2 floor, not the machine that builds them: the receipt names that model and no
        # /proc/cpuinfo field, and the compiler is asked for it (`--cpu x86-64-v3`).
        self.assertEqual(receipt["identity"]["target"]["cpu"], "x86-64-v3")
        self.assertIn("cpu-x86-64-v3", receipt["identity"]["flags"])
        self.assertIn(" --cpu x86-64-v3 ", [line for line in self.log.read_text().splitlines() if line.startswith("where:")][0] + " ")
        (self.sources / "graph.selka").write_text("# new module\n")
        self.assertNotEqual(first, self.invoke())
        self.assertEqual(self.calls(), 3)

    def test_planner_change_is_independent_of_test_index(self):
        index_key = self.invoke()
        before = json.loads((self.install / "cache-plan.json").read_text())
        self.assertEqual(before["component"], "cache-plan")
        (self.planner_sources / "graph.selka").write_text("# planner-only edit\n")
        self.assertEqual(index_key, self.invoke())
        after = json.loads((self.install / "cache-plan.json").read_text())
        self.assertNotEqual(before["key"], after["key"])
        self.assertEqual(self.calls(), 3)

    def test_compiler_change_during_build_refuses_publication(self):
        self.environment["COMPONENT_FIXTURE_MUTATE_COMPILER"] = "1"
        self.assertIn("component compiler changed during component build", self.invoke(success=False))
        self.assertFalse((self.install / "test-index.json").exists())
        self.assertEqual(list((self.cache / "artifacts").glob("*/receipt.json")), [])

    def test_identity_covers_embedded_input_bytes(self):
        (self.sources / "schema.json").write_text('{"version":1}')
        first = self.invoke()
        (self.sources / "schema.json").write_text('{"version":2}')
        self.assertNotEqual(first, self.invoke())

    def test_toolchain_library_change_rekeys_components(self):
        first = self.invoke()
        (self.workspace / "lib/runtime.h").write_text("changed-library")
        self.assertNotEqual(first, self.invoke())

    def test_compiler_change_changes_key(self):
        first = self.invoke()
        self.compiler_script += "# a rebuilt compiler\n"
        self.write_compiler()
        self.assertNotEqual(first, self.invoke())
        self.assertEqual(self.calls(), 4)

    # GH-3f: the bytes of a component depend on the compiler's toolchain identity (the runtime object's name holds it), so a
    # receipt made under one identity is never the one a rebuild under another is compared with: a library update that moves
    # the identity makes a new receipt, where it used to fail "not reproducible".
    def test_identity_change_makes_a_new_receipt_and_is_never_a_reproducibility_failure(self):
        first = self.invoke()
        self.environment["COMPONENT_FIXTURE_IDENTITY"] = "b" * 64
        self.environment["COMPONENT_FIXTURE_OUTPUT"] = "built under another identity"
        second = self.invoke("--uncached")
        self.assertNotEqual(first, second)
        self.assertEqual(self.artifact(first).read_bytes(), b"native-component")
        self.assertEqual(self.artifact(second).read_bytes(), b"built under another identity")
        receipt = json.loads((self.cache / "artifacts" / second / "receipt.json").read_text())
        self.assertEqual(receipt["identity"]["toolchain"]["tool_identity"], "b" * 64)
        del self.environment["COMPONENT_FIXTURE_IDENTITY"]
        del self.environment["COMPONENT_FIXTURE_OUTPUT"]
        self.assertEqual(first, self.invoke("--uncached"), "back under the first identity its own receipt is compared and agrees")

    def test_a_compiler_that_prints_no_identity_fails_concisely(self):
        self.environment["COMPONENT_FIXTURE_IDENTITY_FAIL"] = "1"
        self.assertIn("command failed", self.invoke(success=False))
        del self.environment["COMPONENT_FIXTURE_IDENTITY_FAIL"]
        self.environment["COMPONENT_FIXTURE_IDENTITY"] = "not a digest"
        self.assertIn("printed no toolchain identity", self.invoke(success=False))
        self.assertFalse(self.log.exists(), "no component was compiled")

    def test_compiler_runs_with_built_in_implementations_and_no_component_folder(self):
        # No cycle (GH-D5): the compiler that builds the components needs none of them.
        self.environment["SELKA_COMPONENT_DIR"] = str(self.workspace / "installed-components")
        self.invoke()
        modes = [line for line in self.log.read_text().splitlines() if line.startswith("modes:")]
        self.assertEqual(modes, ["modes:reference|reference|unset"] * 2)

    def test_missing_or_unreadable_compiler_fails_concisely(self):
        command = [BUILDER, "--root", str(self.root), "--zig", str(self.zig),
                   "--cache-dir", str(self.cache), "--install-dir", str(self.install)]
        result = subprocess.run(command, env=self.environment, capture_output=True, text=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--compiler is required", result.stderr)
        self.assertIn("cannot find the component compiler",
                      self.invoke("--compiler", str(self.workspace / "absent"), success=False))

    def test_unknown_machine_environment_never_fails_preparation(self):
        # The compiler judges its own toolchain; a loader or include override reaches it and fails nothing here.
        self.environment.update(LD_LIBRARY_PATH=str(self.workspace / "elsewhere"), CPATH=str(self.workspace / "headers"))
        stamp = self.input_stamp()
        self.invoke("--verify-inputs-stamp", str(stamp), "--output-stamp", str(self.output_stamp))
        self.assertTrue((self.install / "cache-plan.json").exists())

    def test_installed_manifest_marks_owned_checked_default_components(self):
        key = self.invoke()
        for name in ("test-index", "cache-plan"):
            manifest = json.loads((self.install / f"{name}.json").read_text())
            self.assertEqual(manifest["memory_mode"], "zero-rc-v1")
            self.assertEqual(manifest["ownership_selection"], "checked-default-v1")
            self.assertEqual(set(manifest), {"format", "component", "protocol", "schema", "artifact", "sha256", "key",
                                             "memory_mode", "ownership_selection"})
        receipt = json.loads((self.cache / "artifacts" / key / "receipt.json").read_text())
        self.assertIn("checked-default-v1", receipt["identity"]["flags"])
        self.assertEqual(receipt["identity"]["compiler"], digest(self.compiler))
        self.assertNotIn("native_inputs", receipt["identity"])

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
        (self.sources / "main.selka").write_text("changed")
        self.environment["COMPONENT_FIXTURE_FAIL"] = "1"
        self.invoke(success=False)
        self.assertEqual(before, (self.install / "test-index.json").read_bytes())
        self.assertFalse(list((self.cache / "artifacts").glob("*.build")))
        self.assertFalse((self.cache / "staging/component").exists())

    def test_failed_planner_build_preserves_each_selected_installation(self):
        self.invoke()
        before_index = (self.install / "test-index.json").read_bytes()
        before_planner = (self.install / "cache-plan.json").read_bytes()
        (self.planner_sources / "main.selka").write_text("changed planner")
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

    def stores(self):
        return [line[len("stores:"):] for line in self.log.read_text().splitlines() if line.startswith("stores:")]

    def test_store_locations_reach_the_component_compiler_and_change_no_key_or_byte(self):
        # GATE3B: a request that gives its workers stores of its own gives the component compiler the same; the other
        # SELKA_ variables stay dropped (the object store is switched off), and no key or byte depends on a location.
        for side in ("a", "b"):
            for leaf in ("compiler", "tests", "objects", "frontend"):
                (self.workspace / side / leaf).mkdir(parents=True)
        a, b = self.workspace / "a", self.workspace / "b"
        self.environment.update(SELKA_COMPILER_SHARED_CACHE=str(a / "compiler"), SELKA_TEST_SHARED_CACHE=str(a / "tests"),
                                SELKA_STAGE_SHARED_CACHE="", SELKA_CORE_RUNTIME_CACHE=str(a / "objects"),
                                SELKA_FRONTEND_CACHE=str(a / "frontend"))
        first = self.invoke()
        self.assertEqual(self.stores(), ["%s|%s|||unset" % (a / "compiler", a / "tests")] * 2)
        receipt = (self.cache / "artifacts" / first / "receipt.json").read_bytes()
        self.environment.update(SELKA_COMPILER_SHARED_CACHE=str(b / "compiler"), SELKA_TEST_SHARED_CACHE=str(b / "tests"),
                                SELKA_STAGE_SHARED_CACHE=str(b / "stages"))
        self.assertEqual(first, self.invoke("--uncached"), "the same key, and the rebuilt bytes equal the receipt's")
        self.assertEqual(self.stores()[2:], ["%s|%s|%s||unset" % (b / "compiler", b / "tests", b / "stages")] * 2)
        self.assertEqual(receipt, (self.cache / "artifacts" / first / "receipt.json").read_bytes())
        for name in ("SELKA_COMPILER_SHARED_CACHE", "SELKA_TEST_SHARED_CACHE", "SELKA_STAGE_SHARED_CACHE",
                     "SELKA_CORE_RUNTIME_CACHE", "SELKA_FRONTEND_CACHE"):
            del self.environment[name]
        self.invoke("--uncached")
        self.assertEqual(self.stores()[4:], ["unset|unset|unset||unset"] * 2, "a request that names no store names none")

    def places(self):
        return [line[len("where:"):] for line in self.log.read_text().splitlines() if line.startswith("where:")]

    def test_builder_identity_is_independent_of_builder_location(self):
        global BUILDER
        first = self.invoke()
        identity = json.loads((self.cache / "artifacts" / first / "receipt.json").read_text())["identity"]
        self.assertEqual(identity["format"], 6)
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
        (self.sources / "graph.selka").write_text("# another key\n")
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
            self.assertIn(str(staging / "src/main.selka"), arguments)
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

    def test_malformed_component_receipt_fails_concisely(self):
        key = self.invoke()
        (self.cache / "artifacts" / key / "receipt.json").write_text("{")
        self.invoke(success=False)
        self.assertEqual(self.calls(), 2)

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




if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--builder", type=Path, required=True)
    parser.add_argument("--zig", type=Path, required=True)
    args, remaining = parser.parse_known_args()
    BUILDER = str(args.builder.resolve())
    ZIG = str(args.zig.resolve())
    unittest.main(argv=[__file__, *remaining])
