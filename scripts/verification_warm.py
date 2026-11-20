"""Extra live authorities for formerly fresh verification groups.

The build inventory still owns each action and its content recipes. This module
binds the small non-file inputs those recipes cannot express. No guard or
serialized diagnostic is a reusable success by itself.

Guardian's cohort, and the SPEC history replay that borrowed its Git authority,
were removed with Guardian (GH-2, 18 November 2026): neither is reused now.
"""
import os
import runpy
import re
import sys

import verification_code_identity as code_identity
from verification_snapshot import SnapshotError, _Inotify

PREPARATION = frozenset(("input-discovery", "environment-discovery", "component-preparation"))
QUALIFICATION = frozenset(("juice", "juice-runtime"))
FILTERED = frozenset(("unit", "core", "cli", "golden", "tooling_unit", "text_scalar_unit"))
KEYED = frozenset(("identity-qualification", "coverage", "guest", "language"))


def disposition(group, *, force=False, unsupported=False, filtered=False):
    """Keep forced requests authoritative and filter only affected native roots."""
    name = group["id"]
    if name in QUALIFICATION:
        return "owed"
    if (name in PREPARATION and group.get("reason") == "validated preparation discovery v1"
            and not force and not unsupported):
        return "prepared"
    if group["cacheable"] and not force and not unsupported and not (filtered and name in FILTERED):
        return "cacheable"
    return "fresh"


class NamedPathAuthority:
    """Watch only named candidate existence/type, including absent and aliased paths."""
    def __init__(self, root, names):
        self.root, self.names = root, sorted(names)
        self.watcher = _Inotify()
        self.identity = None

    def values(self):
        return [{"path": name, "exists": (self.root / name).exists(), "directory": (self.root / name).is_dir()}
                for name in self.names]

    def __enter__(self):
        try:
            for name in self.names:
                path = self.root / name
                # Include each alias's resolved destination in the watch. The
                # semantic record remains root-relative and contains no stat.
                for candidate in {path, path.resolve()}:
                    ancestor = candidate.parent
                    while not ancestor.exists():
                        ancestor = ancestor.parent
                    first = candidate.relative_to(ancestor).parts[0]
                    self.watcher.add(ancestor, directory=True).names.add(os.fsencode(first))
            self.identity = self.values()
            if not self.unchanged():
                raise SnapshotError("coverage candidates changed during discovery")
            return self
        except BaseException:
            self.watcher.close()
            raise

    def __exit__(self, *_):
        self.watcher.close()

    def unchanged(self):
        return self.watcher.drain() and self.values() == self.identity


def _coverage(root, stack, snapshots, session):
    namespace = runpy.run_path(str(root / "tests/test_inputs_coverage.py"))
    names = set()
    for source in namespace["ROOTS"]:
        for path in namespace["reachable"](source):
            names.update(name for _, name in namespace["named_paths"](namespace["test_text"](path)))
    guard = stack.enter_context(NamedPathAuthority(root, names))
    snapshots.append(guard)
    return guard.identity


# A guest token the capability scan must not read as code: an f-string, kept whole so
# every identifier in an interpolation still counts; a plain string, whose contents are
# data; or a `#` comment.
_GUEST_TOKEN = re.compile(r"""
    (?P<fstring>(?<![A-Za-z0-9_])[fF][bBrR]?(?:"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'))
  | (?P<string>(?<![A-Za-z0-9_])[bBrR]{0,2}(?:\"\"\"(?:\\.|[^\\])*?\"\"\"|'''(?:\\.|[^\\])*?'''
                                            |"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'))
  | (?P<comment>\#[^\n]*)
""", re.VERBOSE)


def _guest_code(text):
    """Guest source with comments and plain string contents blanked.

    An HTTP header named "Host" in test data is not a use of the `Host` capability, so
    the scan for native providers reads only what the compiler reads as code. f-strings
    stay whole: their interpolations are code.
    """
    def blank(match):
        if match.lastgroup == "fstring":
            return match.group(0)
        return re.sub(r"[^\n]", " ", match.group(0))
    return _GUEST_TOKEN.sub(blank, text)


def _guest_inputs(root, name, stack, snapshots):
    """Admit only the audited in-tree suites with deterministic capability stand-ins."""
    suites = ("tests/guest",) if name == "guest" else ("tests/lang", "tests/value_semantics", "tests/ported")
    sources = sorted({path for suite in suites for path in (root / suite).rglob("*.selka")})
    configurations = set()
    for path in sources:
        directory = path.parent
        while True:
            configurations.add(os.path.relpath(directory / "selka.json", root))
            if directory.parent == directory:
                break
            directory = directory.parent
    guard = stack.enter_context(NamedPathAuthority(root, configurations))
    snapshots.append(guard)
    if any(row["exists"] for row in guard.identity):
        return None, "guest project configuration requires a separate provider-closure review"
    for suite in suites:
        for path in (root / suite).rglob("*"):
            if path.is_symlink() or path.name.endswith(".cases.json"):
                return None, "guest aliases or cases-file providers require fresh compiler admission"
    for path in sources:
        text = path.read_text()
        if re.search(r"\bHost\b|\bextern\b|\bhost\s+(?:func|def)\b", _guest_code(text)):
            return None, "guest Host or native provider requires fresh compiler admission"
        for call in re.finditer(r"\bembed_(?:bytes|text)\s*\(", text):
            literal = re.match(r"\s*([\"'])([^\\]*?)\1\s*\)", text[call.end():])
            if literal is None:
                return None, "nonliteral embedded guest input requires a separate closure review"
            target = (path.parent / literal[2]).resolve()
            if not any(target.is_relative_to(root / directory) for directory in ("tests", "test", "examples", "src", "selfhost")):
                return None, "embedded guest input leaves the declared source closure"
    return {"policy": "deterministic-in-tree-guest-v1", "sources": len(sources),
            "configuration_candidates": guard.identity}, None

def identities(root, groups, env, stack, snapshots, session, metadata=None):
    """Install live extra authorities only for cohorts whose registry enables reuse."""
    result = {}
    for group in groups:
        name = group["id"]
        if not group["cacheable"]:
            continue
        if name == "coverage":
            result[name] = {"named_paths": _coverage(root, stack, snapshots, session)}
        elif name in ("guest", "language"):
            identity, reason = _guest_inputs(root, name, stack, snapshots)
            if identity is None:
                group.update(cacheable=False, reason=reason)
            else:
                result[name] = identity
    return result


_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
