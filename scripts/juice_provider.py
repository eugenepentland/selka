#!/usr/bin/env python3
"""Read-only Linux provider re-resolution for retained native Juice artifacts.

Results are evidence for comparison, never an input-closure attestation. Callers
must bind tools, artifacts and provider inputs before work and keep live guards
through publication. Unknown loader behavior returns None and requires fresh work.
"""
from dataclasses import dataclass
import hashlib
import verification_code_identity as code_identity
import os
from pathlib import Path
import re
import selectors
import stat
import struct
import subprocess
import sys
import time
from typing import Mapping

_LOADED_CODE_OBJECT = sys._getframe().f_code
LOADED_CODE_SHA256 = code_identity.loaded_code_sha256(_LOADED_CODE_OBJECT)
OUTPUT_LIMIT = 1024 * 1024
TIMEOUT_SECONDS = 15
_INTERPRETERS = frozenset(("/lib64/ld-linux-x86-64.so.2",
                           "/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2",
                           "/usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"))
_ADDRESS = r"\(0x[0-9a-fA-F]+\)"
_MAPPED = re.compile(r"[^\s]+\s+=>\s+(/[^\s]+)\s+" + _ADDRESS)
_DIRECT = re.compile(r"(/[^\s]+)\s+" + _ADDRESS)
_VDSO = re.compile(r"linux-vdso\.so\.1\s+" + _ADDRESS)


@dataclass(frozen=True)
class Tools:
    """Exact watched executable paths selected by the coordinator."""
    readelf: Path
    ldd: Path
    loader: Path = Path("/lib64/ld-linux-x86-64.so.2")
    ldconfig: Path = Path("/sbin/ldconfig")


def environment(native: dict) -> dict[str, str]:
    """Match juice/platform.environment without inheriting the coordinator env.

    Collector VALGRIND_LIB and counted-run MYLANG_COUNTERS are added only by their
    execution paths, after native library discovery; neither belongs here.
    """
    work = native["paths"]["run"]
    if type(work) is not str or not Path(work).is_absolute():
        raise ValueError("native runtime path must be absolute")
    extra = native["manifest"]["environment"]
    if not _strings(extra):
        raise ValueError("native runtime environment must contain string pairs")
    result = {"PATH": "/bin:/usr/bin", "LC_ALL": "C", "LANG": "C", "TZ": "UTC",
              "PWD": work, "HOME": str(Path(work) / "home"),
              "TMPDIR": str(Path(work) / "tmp")}
    result.update(extra)
    return result


def search_scopes(runtime_env: Mapping[str, str], tool_env: Mapping[str, str],
                  tools: Tools) -> list[Path] | None:
    """Enumerate conservative glibc directory scopes, including absent cache files.

    Callers must watch direct entries in each returned directory (including file
    writes and replacements), not traverse unrelated subdirectories. Absent
    directories require watches on the existing parent and missing name chain.
    Returned scopes include every reported glibc-hwcaps subdirectory. Bind
    tool/loader aliases and bytes, /etc/ld.so.cache and /etc/ld.so.preload absence
    BEFORE this query. Existing preload files and unsupported search modes fail
    closed. Repeat the query after work; it does not create its own watch proof.
    A workload whose artifacts all resolve to empty maps needs no loader scopes.
    """
    if not _loader_environment(runtime_env) or not _loader_environment(tool_env):
        return None
    if str(tools.loader) not in _INTERPRETERS or not Path(tools.ldconfig).is_absolute():
        return None
    try:
        if os.path.lexists("/etc/ld.so.preload"):
            return None
        help_text = _run([str(tools.loader), "--help"], runtime_env)
        cache_text = _run([str(tools.ldconfig), "-p", "-C", "/etc/ld.so.cache"], tool_env)
        if help_text is None or cache_text is None:
            return None
        roots = _system_paths(help_text)
        capabilities = _hwcaps(help_text)
        cached = _cache_paths(cache_text)
        if roots is None or capabilities is None or cached is None:
            return None
        roots.update(cached)
        roots.add(str(Path(tools.loader).parent))
        paths = runtime_env.get("LD_LIBRARY_PATH", "")
        if paths:
            roots.update(paths.split(":"))
        scopes = {Path(value) for value in roots}
        for root in roots:
            scoped = Path(root) / "glibc-hwcaps"
            scopes.add(scoped)
            scopes.update(scoped / capability for capability in capabilities)
        return sorted(scopes)
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError):
        return None


def _system_paths(text: str) -> set[str] | None:
    marker = "Shared library search path:\n"
    if text.count(marker) != 1 or "This program interpreter self-identifies as:" not in text:
        return None
    section = text.split(marker, 1)[1].split("\n\n", 1)[0]
    roots = set()
    for row in section.splitlines():
        row = row.strip()
        if row == "(libraries located via /etc/ld.so.cache)":
            continue
        match = re.fullmatch(r"(/[^\s$]+) \((?:system search path|LD_LIBRARY_PATH)\)", row)
        if match is None:
            return None
        roots.add(match.group(1))
    return roots or None


def _hwcaps(text: str) -> tuple[str, ...] | None:
    marker = "Subdirectories of glibc-hwcaps directories, in priority order:\n"
    if text.count(marker) != 1 or re.search(r"legacy[^\n]*hwcap", text, re.IGNORECASE):
        return None
    result = []
    for row in text.split(marker, 1)[1].splitlines():
        row = row.strip()
        if not row:
            continue
        match = re.fullmatch(r"([A-Za-z0-9][A-Za-z0-9_-]{0,63})(?: \(supported, searched\))?", row)
        if match is None or match.group(1) in result:
            return None
        result.append(match.group(1))
        if len(result) > 64:
            return None
    return tuple(result) if result else None


def _cache_paths(text: str) -> set[str] | None:
    rows = text.splitlines()
    if not rows:
        return None
    header = re.fullmatch(r"([0-9]+) libs found in cache `/etc/ld\.so\.cache'", rows[0])
    if header is None or int(header.group(1)) > 16384:
        return None
    count = int(header.group(1))
    if len(rows) < count + 1:
        return None
    roots = set()
    for row in rows[1:count + 1]:
        entry = re.fullmatch(r"\s*[^\s]+ \([^\r\n]+\) => (/[^\s$]+)", row)
        if entry is None:
            return None
        roots.add(str(Path(entry.group(1)).parent))
    tail = rows[count + 1:]
    if tail and (len(tail) != 1 or not tail[0].startswith("Cache generated by: ")):
        return None
    return roots


def _strings(env) -> bool:
    return isinstance(env, Mapping) and all(type(k) is str and type(v) is str
        and "\0" not in k + v and k and "=" not in k for k, v in env.items())


def _loader_environment(env) -> bool:
    if not _strings(env) or "GLIBC_TUNABLES" in env:
        return False
    if any(key.startswith("LD_") and key != "LD_LIBRARY_PATH" for key in env):
        return False
    paths = env.get("LD_LIBRARY_PATH", "")
    return not paths or all(path.startswith("/") and "$" not in path and ";" not in path
                            for path in paths.split(":"))


def _run(argv: list[str], env: Mapping[str, str]) -> str | None:
    """Bound time and combined output without running a shell or an application."""
    with subprocess.Popen(argv, env=dict(env), cwd="/", stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, start_new_session=True) as child:
        deadline = time.monotonic() + TIMEOUT_SECONDS
        chunks = []
        length = 0
        try:
            with selectors.DefaultSelector() as ready:
                ready.register(child.stdout, selectors.EVENT_READ)
                while ready.get_map():
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not ready.select(remaining):
                        return None
                    data = os.read(child.stdout.fileno(), 65536)
                    if not data:
                        ready.unregister(child.stdout)
                        break
                    length += len(data)
                    if length > OUTPUT_LIMIT:
                        return None
                    chunks.append(data)
            remaining = deadline - time.monotonic()
            if remaining <= 0 or child.wait(timeout=remaining) != 0:
                return None
            return b"".join(chunks).decode("utf-8", errors="strict")
        finally:
            if child.poll() is None:
                # ldd is a script; terminate its loader children as well.
                os.killpg(child.pid, 9)
                child.wait()


def _interpreter(path: Path) -> tuple[bool, str | None] | None:
    """Inspect bounded amd64 ELF headers before permitting ldd to see a guest."""
    with path.open("rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_mode & (stat.S_ISUID | stat.S_ISGID):
            return None
        data = stream.read(64)
        if len(data) != 64 or data[:7] != b"\x7fELF\x02\x01\x01":
            return None
        header = struct.unpack("<16sHHIQQQIHHHHHH", data)
        if header[1] not in (2, 3) or header[2] != 62 or header[3] != 1:
            return None
        offset, width, count = header[5], header[9], header[10]
        if header[8] != 64 or width != 56 or not 0 < count <= 4096:
            return None
        if offset < 64 or offset + width * count > info.st_size:
            return None
        stream.seek(offset)
        table = stream.read(width * count)
        interpreter = None
        dynamic = False
        for index in range(count):
            kind, _, start, _, _, length, _, _ = struct.unpack_from("<IIQQQQQQ", table, index * width)
            if start + length > info.st_size:
                return None
            if kind == 2:
                dynamic = True
            if kind != 3:
                continue
            if interpreter is not None or not 2 <= length <= 4096:
                return None
            stream.seek(start)
            text = stream.read(length)
            if len(text) != length or text[-1:] != b"\0" or b"\0" in text[:-1]:
                return None
            interpreter = text[:-1].decode("ascii", errors="strict")
            if interpreter not in _INTERPRETERS:
                return None
        return dynamic, interpreter


def _hash(path: Path) -> str | None:
    with path.open("rb") as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode):
            return None
        digest = hashlib.sha256()
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
        after = os.fstat(stream.fileno())
    fields = lambda value: (value.st_dev, value.st_ino, value.st_size,
                            value.st_mtime_ns, value.st_ctime_ns, value.st_mode)
    if fields(before) != fields(after) or fields(after) != fields(path.stat()):
        return None
    return digest.hexdigest()


def _providers(text: str, interpreter: str) -> dict[str, str] | None:
    result = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or _VDSO.fullmatch(line):
            continue
        match = _MAPPED.fullmatch(line) or _DIRECT.fullmatch(line)
        if match is None:
            return None
        path = match.group(1)
        if not Path(path).is_absolute() or "$" in path:
            return None
        digest = _hash(Path(path))
        if digest is None:
            return None
        result[path] = digest
    return result if interpreter in result else None


def _inspect(path: Path, env: Mapping[str, str], tools: Tools) -> str | None:
    text = _run([str(tools.readelf), "--wide", "--program-headers", "--dynamic",
                 "--", str(path)], env)
    if text is None or re.search(r"\((?:RPATH|RUNPATH|FILTER|AUXILIARY|AUDIT|DEPAUDIT)\)", text):
        return None
    # Slash-bearing DT_NEEDED entries bypass ordinary name search and may depend
    # on guest cwd. Keep this narrower than glibc's full supported behavior.
    for value in re.findall(r"\(NEEDED\)[^\n]*\[([^\]]+)\]", text):
        if "/" in value or "$" in value:
            return None
    return text


def resolve(artifacts: Mapping[str, Path], runtime_env: Mapping[str, str],
            tool_env: Mapping[str, str], tools: Tools) -> dict[str, dict[str, str]] | None:
    """Resolve every retained artifact under the exact native runtime environment.

    None means missing or unsupported proof. Empty maps certify static ELFs only.
    ldd may run the approved system loader to trace libraries, never guest main.
    All returned literal provider paths must already be guarded by the caller.
    """
    if not artifacts or not _loader_environment(runtime_env) or not _loader_environment(tool_env):
        return None
    if any(not Path(tool).is_absolute() for tool in (tools.readelf, tools.ldd)):
        return None
    result = {}
    try:
        for kind, artifact in artifacts.items():
            if type(kind) is not str or not Path(artifact).is_absolute():
                return None
            artifact = Path(artifact)
            inspected = _interpreter(artifact)
            if inspected is None:
                return None
            dynamic, interpreter = inspected
            if interpreter is not None and Path(interpreter).resolve(strict=True) != Path(tools.loader).resolve(strict=True):
                return None
            text = _inspect(artifact, tool_env, tools)
            if text is None:
                return None
            needed = re.search(r"\(NEEDED\)", text) is not None
            if interpreter is None:
                if dynamic or needed:
                    return None
                result[kind] = {}
                continue
            if not dynamic:
                return None
            text = _run([str(tools.ldd), str(artifact)], runtime_env)
            rows = None if text is None else _providers(text, interpreter)
            if rows is None:
                return None
            if any(_inspect(Path(path), tool_env, tools) is None for path in rows):
                return None
            result[kind] = rows
        return result
    except (OSError, ValueError, UnicodeError, struct.error, subprocess.SubprocessError):
        return None
