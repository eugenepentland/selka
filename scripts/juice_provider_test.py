#!/usr/bin/env python3
"""Provider checks never certify unknown loader behavior as reusable evidence."""
import hashlib
import os
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest import mock

import juice_provider as provider


def elf(path: Path, interpreter=None, dynamic=False):
    headers = [(1, 5, 0, 0, 0, 0, 0, 4096)]
    payload = b""
    if interpreter is not None:
        text = interpreter.encode() + b"\0"
        headers.append((3, 4, 512, 0, 0, len(text), len(text), 1))
        payload = text
    if dynamic:
        headers.append((2, 4, 0, 0, 0, 0, 0, 8))
    identity = b"\x7fELF\x02\x01\x01" + bytes(9)
    header = struct.pack("<16sHHIQQQIHHHHHH", identity, 2, 62, 1, 0, 64, 0, 0,
                         64, 56, len(headers), 0, 0, 0)
    table = b"".join(struct.pack("<IIQQQQQQ", *fields) for fields in headers)
    path.write_bytes((header + table).ljust(512, b"\0") + payload)
    return path


class Providers(unittest.TestCase):
    def setUp(self):
        self.area = tempfile.TemporaryDirectory()
        self.addCleanup(self.area.cleanup)
        self.root = Path(self.area.name)
        self.artifact = elf(self.root / "plain")
        self.tools = provider.Tools(Path("/usr/bin/readelf"), Path("/usr/bin/ldd"))
        self.native = {"paths": {"run": str(self.root / "run")},
                       "manifest": {"environment": {"CUSTOM": "declared"}}}
        self.env = provider.environment(self.native)

    def resolve(self, artifacts=None, runtime=None, tool_env=None):
        return provider.resolve(artifacts or {"plain": self.artifact},
                                self.env if runtime is None else runtime,
                                {"PATH": "/usr/bin", "LC_ALL": "C"} if tool_env is None else tool_env,
                                self.tools)

    def dynamic(self):
        elf(self.artifact, "/lib64/ld-linux-x86-64.so.2", True)
        return self.artifact

    def trace(self, library):
        return ("linux-vdso.so.1 (0x123)\n"
                f"libsample.so => {library} (0xabc)\n"
                "/lib64/ld-linux-x86-64.so.2 (0xdef)\n")

    def hashed(self, path):
        return hashlib.sha256(path.read_bytes()).hexdigest()

    # spec: NEW-CORE-JUICE-PLAN-1
    def test_native_environment_is_explicit_and_discovery_only(self):
        with mock.patch.dict(os.environ, {"LD_PRELOAD": "/unbound/inject.so",
                                          "VALGRIND_LIB": "/ambient", "SECRET": "ambient"}):
            actual = provider.environment(self.native)
        self.assertEqual(actual, {"PATH": "/bin:/usr/bin", "LC_ALL": "C", "LANG": "C",
            "TZ": "UTC", "PWD": str(self.root / "run"), "HOME": str(self.root / "run/home"),
            "TMPDIR": str(self.root / "run/tmp"), "CUSTOM": "declared"})
        self.assertFalse((self.root / "run").exists())

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_static_elf_requires_no_ldd_and_no_loader_scope(self):
        with mock.patch.object(provider, "_run", return_value="There is no dynamic section") as run:
            rows = self.resolve()
        self.assertEqual(rows, {"plain": {}})
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0][0], str(self.tools.readelf))

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_each_artifact_has_fresh_literal_provider_mapping(self):
        self.dynamic()
        counted = elf(self.root / "counted", "/lib64/ld-linux-x86-64.so.2", True)
        first = self.root / "first.so"
        second = self.root / "second.so"
        first.write_bytes(b"provider one")
        second.write_bytes(b"provider two")
        interpreter = "/lib64/ld-linux-x86-64.so.2"
        real_hash = provider._hash
        def digest(path):
            return "f" * 64 if str(path) == interpreter else real_hash(path)
        outputs = ["(NEEDED) libsample.so", self.trace(first), "provider ELF", "loader ELF",
                   "(NEEDED) libsample.so", self.trace(second), "provider ELF", "loader ELF"]
        with mock.patch.object(provider, "_run", side_effect=outputs) as run, \
             mock.patch.object(provider, "_hash", side_effect=digest):
            rows = self.resolve({"plain": self.artifact, "counted": counted})
        self.assertEqual(rows, {"plain": {str(first): self.hashed(first), interpreter: "f" * 64},
                                "counted": {str(second): self.hashed(second), interpreter: "f" * 64}})
        self.assertEqual(run.call_args_list[1].args[1], self.env)
        self.assertEqual(run.call_args_list[5].args[1], self.env)

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_unknown_interpreter_is_rejected_before_any_tool(self):
        elf(self.artifact, str(self.root / "guest-interpreter"), True)
        with mock.patch.object(provider, "_run") as run:
            self.assertIsNone(self.resolve())
        run.assert_not_called()

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_approved_alias_cannot_use_different_loader_than_search_query(self):
        elf(self.artifact, "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2", True)
        def actual(path, **kwargs):
            return self.root / ("guest-loader" if str(path).startswith("/lib/x86_") else "queried-loader")
        with mock.patch.object(Path, "resolve", actual), mock.patch.object(provider, "_run") as run:
            self.assertIsNone(self.resolve())
        run.assert_not_called()

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_embedded_search_and_auditing_are_ineligible(self):
        self.dynamic()
        for tag in ("RPATH", "RUNPATH", "AUDIT", "DEPAUDIT", "FILTER", "AUXILIARY"):
            with self.subTest(tag=tag), mock.patch.object(provider, "_run", return_value=f"({tag}) [$ORIGIN]") as run:
                self.assertIsNone(self.resolve())
                self.assertEqual(run.call_count, 1)

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_injection_and_cwd_loader_paths_rejected_even_for_static(self):
        for extra in ({"LD_PRELOAD": "/injected"}, {"LD_AUDIT": "/audit"},
                      {"LD_DEBUG": "libs"}, {"GLIBC_TUNABLES": "glibc.cpu.hwcaps=-AVX2"},
                      {"LD_LIBRARY_PATH": "relative"}, {"LD_LIBRARY_PATH": "/safe:"},
                      {"LD_LIBRARY_PATH": ":/safe"}, {"LD_LIBRARY_PATH": "/$ORIGIN"},
                      {"LD_LIBRARY_PATH": "/safe;/other"}):
            with self.subTest(extra=extra), mock.patch.object(provider, "_run") as run:
                self.assertIsNone(self.resolve(runtime=self.env | extra))
                self.assertIsNone(self.resolve(tool_env=self.env | extra))
                run.assert_not_called()
        with mock.patch.object(provider, "_run", return_value="no dynamic section"):
            self.assertEqual(self.resolve(runtime=self.env | {"LD_LIBRARY_PATH": "/one:/two"}), {"plain": {}})

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_missing_malformed_or_incomplete_provider_trace_is_not_proof(self):
        self.dynamic()
        for output in (None, "libbad.so => not found\n", "unexpected text\n",
                       "linux-vdso.so.1 (0x123)\n", "relative.so (0xabc)\n"):
            with self.subTest(output=output), mock.patch.object(provider, "_run", side_effect=["(NEEDED)", output]):
                self.assertIsNone(self.resolve())

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_bad_elf_and_setid_never_reach_ldd(self):
        malformed = [b"not an ELF", self.artifact.read_bytes()[:40]]
        for data in malformed:
            self.artifact.write_bytes(data)
            with mock.patch.object(provider, "_run") as run:
                self.assertIsNone(self.resolve())
                run.assert_not_called()
        elf(self.artifact)
        self.artifact.chmod(0o4755)
        with mock.patch.object(provider, "_run") as run:
            self.assertIsNone(self.resolve())
            run.assert_not_called()

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_no_interpreter_dynamic_object_cannot_be_treated_as_static(self):
        elf(self.artifact, dynamic=True)
        with mock.patch.object(provider, "_run", return_value="(NEEDED) libbad.so"):
            self.assertIsNone(self.resolve())

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_dependency_local_search_cannot_escape_declared_loader_scopes(self):
        self.dynamic()
        for tags in ("(RUNPATH) [/other]", "(NEEDED) Shared library: [relative/lib.so]",
                     "(NEEDED) Shared library: [/absolute/lib.so]"):
            with self.subTest(tags=tags), mock.patch.object(provider, "_run", return_value=tags) as run:
                self.assertIsNone(self.resolve())
                self.assertEqual(run.call_count, 1)
        library = self.root / "local-search.so"
        library.write_bytes(b"fake provider")
        with mock.patch.object(provider, "_run", side_effect=["(NEEDED)", self.trace(library), "(RPATH) [$ORIGIN]"]), \
             mock.patch.object(provider, "_hash", return_value="a" * 64):
            self.assertIsNone(self.resolve())

    def help_text(self):
        return ("This program interpreter self-identifies as: /lib64/ld-linux-x86-64.so.2\n\n"
                "Shared library search path:\n"
                "  (libraries located via /etc/ld.so.cache)\n"
                "  /lib/x86_64-linux-gnu (system search path)\n"
                "  /usr/lib (system search path)\n\n"
                "Subdirectories of glibc-hwcaps directories, in priority order:\n"
                "  x86-64-v4\n  x86-64-v3 (supported, searched)\n")

    def cache_text(self):
        return ("2 libs found in cache `/etc/ld.so.cache'\n"
                "\tlibfirst.so (libc6,x86-64) => /optional/current/libfirst.so\n"
                "\tlibabsent.so (libc6,x86-64) => /optional/absent/libabsent.so\n"
                "Cache generated by: ldconfig (GNU libc) stable release version 2.41\n")

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_search_scopes_include_absent_cache_candidates_and_literal_env_dirs(self):
        environment = self.env | {"LD_LIBRARY_PATH": "/explicit/provider:/explicit/other"}
        with mock.patch.object(provider.os.path, "lexists", return_value=False), \
             mock.patch.object(provider, "_run", side_effect=[self.help_text(), self.cache_text()]) as run:
            scopes = provider.search_scopes(environment, {"PATH": "/usr/bin"}, self.tools)
        roots = [Path(value) for value in (
            "/explicit/other", "/explicit/provider", "/lib/x86_64-linux-gnu", "/lib64",
            "/optional/absent", "/optional/current", "/usr/lib")]
        expected = set(roots)
        for root in roots:
            expected.update((root / "glibc-hwcaps", root / "glibc-hwcaps/x86-64-v4",
                             root / "glibc-hwcaps/x86-64-v3"))
        self.assertEqual(scopes, sorted(expected))
        self.assertIn(Path("/optional/absent/glibc-hwcaps/x86-64-v4"), scopes)
        self.assertNotIn(Path("/usr/lib/firmware"), scopes)
        self.assertEqual(run.call_args_list[0].args, ([str(self.tools.loader), "--help"], environment))
        self.assertEqual(run.call_args_list[1].args[0],
                         [str(self.tools.ldconfig), "-p", "-C", "/etc/ld.so.cache"])

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_search_scope_schema_and_preload_fail_closed(self):
        with mock.patch.object(provider.os.path, "lexists", return_value=True), \
             mock.patch.object(provider, "_run") as run:
            self.assertIsNone(provider.search_scopes(self.env, self.env, self.tools))
            run.assert_not_called()
        unknown = [("unknown loader", self.cache_text()),
                   (self.help_text(), "unknown cache"),
                   (self.help_text().replace("system search path", "unknown search"), self.cache_text()),
                   (self.help_text(), self.cache_text().replace("2 libs", "3 libs")),
                   (self.help_text(), self.cache_text().replace("/optional/absent/libabsent.so", "relative.so")),
                   (self.help_text(), self.cache_text() + "unexpected extra row\n")]
        for help_text, cache_text in unknown:
            with self.subTest(cache_text=cache_text), mock.patch.object(provider.os.path, "lexists", return_value=False), \
                 mock.patch.object(provider, "_run", side_effect=[help_text, cache_text]):
                self.assertIsNone(provider.search_scopes(self.env, self.env, self.tools))

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_legacy_unknown_or_unsafe_hwcaps_are_not_complete_scopes(self):
        unknown = [self.help_text().split("Subdirectories of glibc-hwcaps", 1)[0],
                   self.help_text() + "Legacy HWCAP subdirectories under library search path directories:\n  tls\n",
                   self.help_text().replace("x86-64-v4", "../escape"),
                   self.help_text().replace("x86-64-v4", "$PLATFORM"),
                   self.help_text().replace("supported, searched", "unknown selection"),
                   self.help_text() + "  x86-64-v4\n",
                   self.help_text() + "Unknown new search format:\n  another-root\n"]
        for text in unknown:
            with self.subTest(text=text), mock.patch.object(provider.os.path, "lexists", return_value=False), \
                 mock.patch.object(provider, "_run", side_effect=[text, self.cache_text()]):
                self.assertIsNone(provider.search_scopes(self.env, self.env, self.tools))

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_provider_content_change_changes_resolution_digest(self):
        self.dynamic()
        library = self.root / "changing.so"
        library.write_bytes(b"original")
        real_hash = provider._hash
        def digest(path):
            return "a" * 64 if str(path) == "/lib64/ld-linux-x86-64.so.2" else real_hash(path)
        with mock.patch.object(provider, "_run", side_effect=["(NEEDED)", self.trace(library), "provider ELF", "loader ELF"]), \
             mock.patch.object(provider, "_hash", side_effect=digest):
            original = self.resolve()
        library.write_bytes(b"replacement")
        with mock.patch.object(provider, "_run", side_effect=["(NEEDED)", self.trace(library), "provider ELF", "loader ELF"]), \
             mock.patch.object(provider, "_hash", side_effect=digest):
            changed = self.resolve()
        self.assertNotEqual(original, changed)

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_tool_errors_fail_closed(self):
        for failure in (OSError("unavailable"), ValueError("bad text")):
            with self.subTest(failure=failure), mock.patch.object(provider, "_run", side_effect=failure):
                self.assertIsNone(self.resolve())
        with mock.patch.object(provider, "_run", return_value=None):
            self.assertIsNone(self.resolve())

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_provider_hash_streams_and_rejects_replacement(self):
        path = self.root / "large.so"
        data = b"abc" * (1024 * 1024)
        path.write_bytes(data)
        original = Path.open
        reads = []
        class Stream:
            def __init__(self, wrapped): self.wrapped = wrapped
            def __enter__(self): return self
            def __exit__(self, *args): return self.wrapped.__exit__(*args)
            def fileno(self): return self.wrapped.fileno()
            def read(self, size):
                reads.append(size)
                if not 0 < size <= 1024 * 1024:
                    raise AssertionError("unbounded provider read")
                return self.wrapped.read(size)
        def bounded(target, *args, **kwargs):
            return Stream(original(target, *args, **kwargs))
        with mock.patch.object(Path, "open", bounded):
            self.assertEqual(provider._hash(path), hashlib.sha256(data).hexdigest())
        self.assertGreater(len(reads), 1)
        before = path.stat()
        substitute = self.root / "replacement.so"
        substitute.write_bytes(b"replacement")
        with mock.patch.object(provider.os, "fstat", side_effect=[before, before]), \
             mock.patch.object(Path, "stat", return_value=substitute.stat()):
            self.assertIsNone(provider._hash(path))

    # spec-case: NEW-CORE-JUICE-PLAN-1
    def test_tool_output_and_timeout_are_bounded(self):
        environment = {"PATH": "/bin:/usr/bin"}
        self.assertEqual(provider._run([sys.executable, "-c", "print('tool result')"], environment), "tool result\n")
        with mock.patch.object(provider, "OUTPUT_LIMIT", 64):
            self.assertIsNone(provider._run([sys.executable, "-c", "print('x'*1000)"], environment))
        with mock.patch.object(provider, "TIMEOUT_SECONDS", 0.02):
            self.assertIsNone(provider._run([sys.executable, "-c", "import time; time.sleep(10)"], environment))
        self.assertIsNone(provider._run([sys.executable, "-c", "raise SystemExit(1)"], environment))


if __name__ == "__main__":
    unittest.main()
