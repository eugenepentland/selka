"""Bounded concrete differential inputs, independent of compiler success receipts."""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import tempfile

VERSION = "differential-corpus-v1"
ADAPTERS = {"incremental-v1", "interfaces-v1"}
MAX_FILES = 4096
MAX_CASES = 4096
MAX_FILE = 1 << 20
MAX_PAYLOAD = 32 << 20
MAX_RECORD = 48 << 20


class CorpusError(ValueError):
    """A corpus or worker cannot support a completed differential campaign."""


def copy_baseline(source, destination, *, strict):
    """Strict workers read only the visible regular-file scope watched by recipes."""
    def ignored(directory, names):
        excluded = []
        for name in names:
            if name.startswith(".") or name == "__pycache__" or name.endswith(".pyc"):
                excluded.append(name)
                continue
            path = Path(directory) / name
            if path.is_symlink():
                raise CorpusError("strict baseline contains a symlink: " + str(path))
            if not path.is_dir() and not path.is_file():
                raise CorpusError("strict baseline contains a nonregular entry")
        return excluded
    shutil.copytree(source, destination, ignore=ignored if strict else None)


def isolate_baseline(directory):
    """Bind nearest project configuration and refuse policies outside retained files."""
    directory = Path(directory)
    configuration = directory / "mylang.json"
    if not configuration.exists():
        configuration.write_bytes(b'{"version":2}\n')
    for path in directory.rglob("mylang.json"):
        with path.open("rb") as handle:
            data = handle.read(MAX_FILE + 1)
        if len(data) > MAX_FILE:
            raise CorpusError("project configuration exceeds corpus limit")
        try:
            document = json.loads(data, object_pairs_hook=unique_object)
        except (UnicodeError, json.JSONDecodeError):
            # Malformed JSON is a bounded compiler rejection, and cannot cause
            # the compiler to load an external import policy.
            continue
        if not isinstance(document, dict) or "import_policy" not in document:
            continue
        policy = document["import_policy"]
        safe_path(policy)
        target = path.parent / policy
        if not target.is_file() or target.is_symlink():
            raise CorpusError("project import policy is not a retained regular file")
        if not target.resolve().is_relative_to(directory.resolve()):
            raise CorpusError("project import policy escapes the retained baseline")


def safe_path(value):
    if not isinstance(value, str) or not value or len(value) > 4096 or "\\" in value or "\x00" in value:
        raise CorpusError("invalid corpus path")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in value.split("/")):
        raise CorpusError("corpus path must be relative without traversal")
    return value


def file_record(name, data):
    safe_path(name)
    if len(data) > MAX_FILE:
        raise CorpusError("corpus file exceeds limit")
    return {"path": name, "sha256": hashlib.sha256(data).hexdigest(),
            "data": base64.b64encode(data).decode("ascii")}


def decode_file(row):
    if not isinstance(row, dict) or set(row) != {"path", "sha256", "data"}:
        raise CorpusError("invalid corpus file schema")
    safe_path(row["path"])
    if not isinstance(row["data"], str) or len(row["data"]) > 4 * ((MAX_FILE + 2) // 3):
        raise CorpusError("invalid corpus file data")
    try:
        data = base64.b64decode(row["data"], validate=True)
    except (ValueError, binascii.Error) as error:
        raise CorpusError("invalid corpus base64") from error
    if len(data) > MAX_FILE or hashlib.sha256(data).hexdigest() != row["sha256"]:
        raise CorpusError("corpus file checksum or size differs")
    if base64.b64encode(data).decode("ascii") != row["data"]:
        raise CorpusError("noncanonical corpus base64")
    return data


def unique_object(pairs):
    result = {}
    for name, value in pairs:
        if name in result:
            raise CorpusError("duplicate corpus member")
        result[name] = value
    return result


def files(directory):
    """Capture every copied baseline file, including configuration and binary data."""
    found = []
    total = 0
    seen_directories = set()
    for parent, directories, names in os.walk(directory, followlinks=True):
        identity = os.stat(parent)
        inode = (identity.st_dev, identity.st_ino)
        if inode in seen_directories:
            raise CorpusError("cyclic or aliased baseline directory")
        seen_directories.add(inode)
        directories.sort()
        for name in sorted(names):
            path = Path(parent) / name
            if not path.is_file():
                raise CorpusError("baseline contains a nonregular file")
            with path.open("rb") as handle:
                data = handle.read(MAX_FILE + 1)
            total += len(data)
            if total > MAX_PAYLOAD:
                raise CorpusError("baseline payload exceeds limit")
            found.append(file_record(path.relative_to(directory).as_posix(), data))
            if len(found) > MAX_FILES:
                raise CorpusError("too many baseline files")
    return sorted(found, key=lambda row: row["path"])


def checked_files(rows, *, required):
    if not isinstance(rows, list) or len(rows) > MAX_FILES or (required and not rows):
        raise CorpusError("invalid corpus file count")
    names = []
    total = 0
    for row in rows:
        total += len(decode_file(row))
        names.append(row["path"])
    if names != sorted(set(names)):
        raise CorpusError("corpus paths must be unique and sorted")
    paths = set(names)
    for name in names:
        if any(str(parent) in paths for parent in PurePosixPath(name).parents if str(parent) != "."):
            raise CorpusError("corpus path collides with a parent file")
    return total


def validate(document, adapter):
    if not isinstance(document, dict) or set(document) != {"version", "adapter", "base_files", "cases"}:
        raise CorpusError("invalid corpus schema")
    if document["version"] != VERSION or document["adapter"] != adapter or adapter not in ADAPTERS:
        raise CorpusError("unsupported corpus version or adapter")
    total = checked_files(document["base_files"], required=True)
    baseline = {row["path"] for row in document["base_files"]}
    cases = document["cases"]
    if not isinstance(cases, list) or len(cases) > MAX_CASES:
        raise CorpusError("invalid corpus case count")
    for ordinal, case in enumerate(cases):
        if not isinstance(case, dict) or set(case) != {"ordinal", "changes", "labels", "expect", "module", "shape"}:
            raise CorpusError("invalid corpus case schema")
        if type(case["ordinal"]) is not int or case["ordinal"] != ordinal:
            raise CorpusError("corpus ordinals must be contiguous")
        total += checked_files(case["changes"], required=False)
        if any(row["path"] not in baseline for row in case["changes"]):
            raise CorpusError("mutation names an unknown baseline file")
        if not isinstance(case["labels"], list) or len(case["labels"]) > 16:
            raise CorpusError("invalid mutation labels")
        if not all(isinstance(label, str) and len(label) <= 4096 for label in case["labels"]):
            raise CorpusError("invalid mutation label")
        if adapter == "incremental-v1":
            if any(case[field] is not None for field in ("expect", "module", "shape")):
                raise CorpusError("unexpected incremental expectation")
        else:
            if case["expect"] not in ("same", "changed") or len(case["labels"]) != 1:
                raise CorpusError("invalid interface expectation")
            module = case["module"]
            if not isinstance(module, str) or module + ".my" not in baseline:
                raise CorpusError("unknown interface module")
            if case["shape"] is not None and (not isinstance(case["shape"], str) or len(case["shape"]) > 4096):
                raise CorpusError("invalid interface shape")
            if any(row["path"] != module + ".my" for row in case["changes"]):
                raise CorpusError("interface mutation must change only its named module")
        if total > MAX_PAYLOAD:
            raise CorpusError("corpus payload exceeds limit")
    if total > MAX_PAYLOAD:
        raise CorpusError("corpus payload exceeds limit")
    return document


class Corpus:
    """Concrete baseline and attempted mutations; no stored verdict authorizes reuse."""
    def __init__(self, document, adapter):
        self.document = validate(document, adapter)
        self.adapter = adapter

    @classmethod
    def capture(cls, directory, adapter):
        return cls({"version": VERSION, "adapter": adapter, "base_files": files(directory), "cases": []}, adapter)

    @classmethod
    def load(cls, path, adapter):
        try:
            with Path(path).open("rb") as handle:
                data = handle.read(MAX_RECORD + 1)
            if len(data) > MAX_RECORD:
                raise CorpusError("corpus record exceeds limit")
            return cls(json.loads(data, object_pairs_hook=unique_object), adapter)
        except (OSError, UnicodeError, json.JSONDecodeError) as error:
            raise CorpusError("cannot read differential corpus: " + str(error)) from error

    @property
    def cases(self):
        return self.document["cases"]

    def changes(self, directory):
        """Retain actual input bytes, including implicit newline rewrites by a harness."""
        changed = {}
        for row in self.document["base_files"]:
            with (Path(directory) / row["path"]).open("rb") as handle:
                data = handle.read(MAX_FILE + 1)
            if len(data) > MAX_FILE:
                raise CorpusError("mutated corpus file exceeds limit")
            if hashlib.sha256(data).hexdigest() != row["sha256"]:
                changed[row["path"]] = data
        return changed

    def append(self, changes, labels, *, expect=None, module=None, shape=None):
        if len(changes) > MAX_FILES or len(self.cases) >= MAX_CASES:
            raise CorpusError("corpus file or case count exceeds limit")
        if sum(len(data) for data in changes.values()) > MAX_PAYLOAD:
            raise CorpusError("mutation payload exceeds limit")
        rows = [file_record(name, data) for name, data in sorted(changes.items())]
        case = {"ordinal": len(self.cases), "changes": rows, "labels": list(labels),
                "expect": expect, "module": module, "shape": shape}
        self.cases.append(case)
        try:
            validate(self.document, self.adapter)
        except CorpusError:
            self.cases.pop()
            raise
        return case

    def restore(self, directory, case=None):
        directory = Path(directory)
        for row in self.document["base_files"]:
            path = directory / row["path"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(decode_file(row))
        if case is not None:
            for row in case["changes"]:
                (directory / row["path"]).write_bytes(decode_file(row))

    def save(self, path):
        validate(self.document, self.adapter)
        data = json.dumps(self.document, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode() + b"\n"
        if len(data) > MAX_RECORD:
            raise CorpusError("corpus record exceeds limit")
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".corpus-", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, path)
        finally:
            Path(temporary).unlink(missing_ok=True)


def require_worker(result):
    """Only normal compiler success or source rejection can complete a strict case."""
    if result.returncode not in (0, 1):
        raise CorpusError("compiler exited abnormally: " + str(result.returncode))


def load(path, expected_adapter):
    """Read and validate a corpus document for a coordinator's selected adapter."""
    return Corpus.load(path, expected_adapter).document
