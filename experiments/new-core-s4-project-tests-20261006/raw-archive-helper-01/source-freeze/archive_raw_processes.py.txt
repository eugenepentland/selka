#!/usr/bin/env python3
"""Lossless raw-process curation; summaries/journals/program sources remain outside.

Select only a completed raw `processes` directory, never its qualification parent.
This tool leaves that directory intact. Root may commit the resulting archive and
member index alongside the still-readable parent summary, journal and sources.
"""
import argparse
from contextlib import contextmanager
import errno
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import stat
import tarfile

FORMAT = "mylang-s4-raw-process-archive-v1"
CHUNK = 1024 * 1024


def safe_name(name):
    if (not isinstance(name, str) or not name or "\\" in name or "\0" in name
            or any(0xD800 <= ord(char) <= 0xDFFF for char in name)):
        raise ValueError("unsafe member path")
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or path.as_posix() != name or name == ".":
        raise ValueError("unsafe member path")
    return path.parts


def absolute(path):
    path = Path(path).absolute()
    if ".." in path.parts:
        raise ValueError("parent traversal is not permitted")
    return path


def opened(name, flags, directory=None):
    flags |= os.O_NOFOLLOW | os.O_CLOEXEC
    noatime = getattr(os, "O_NOATIME", 0)
    try:
        return os.open(name, flags | noatime, mode=0o600, dir_fd=directory)
    except OSError as error:
        if error.errno != errno.EPERM or not noatime:
            raise
        return os.open(name, flags, mode=0o600, dir_fd=directory)


@contextmanager
def root_directory(path):
    path = absolute(path)
    fd = opened("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for component in path.parts[1:]:
            child = opened(component, os.O_RDONLY | os.O_DIRECTORY, fd)
            os.close(fd)
            fd = child
        yield fd
    finally:
        os.close(fd)


@contextmanager
def member_file(root, name):
    parts = safe_name(name)
    fd = os.dup(root)
    try:
        for component in parts[:-1]:
            child = opened(component, os.O_RDONLY | os.O_DIRECTORY, fd)
            os.close(fd)
            fd = child
        leaf = opened(parts[-1], os.O_RDONLY | os.O_NONBLOCK, fd)
        try:
            if not stat.S_ISREG(os.fstat(leaf).st_mode):
                raise ValueError("input must be a regular file")
            with os.fdopen(leaf, "rb", closefd=False) as stream:
                yield stream
        finally:
            os.close(leaf)
    finally:
        os.close(fd)


def fingerprint(value):
    return [value.st_dev, value.st_ino, value.st_mode, value.st_size,
            value.st_mtime_ns, value.st_ctime_ns, value.st_nlink]


def digest_stream(stream):
    digest, size = hashlib.sha256(), 0
    while data := stream.read(CHUNK):
        digest.update(data)
        size += len(data)
    return size, digest.hexdigest()


@contextmanager
def path_file(path):
    path = absolute(path)
    with root_directory(path.parent) as root, member_file(root, path.name) as stream:
        before = fingerprint(os.fstat(stream.fileno()))
        yield stream
        if fingerprint(os.fstat(stream.fileno())) != before:
            raise ValueError("file changed while reading")


def digest_file(path):
    with path_file(path) as stream:
        return digest_stream(stream)[1]


def snapshot(raw):
    files, directories = {}, {}

    def visit(fd, prefix):
        before = fingerprint(os.fstat(fd))
        directories[prefix or "."] = before
        with os.scandir(fd) as entries:
            names = sorted(entry.name for entry in entries)
        for leaf in names:
            name = prefix + "/" + leaf if prefix else leaf
            safe_name(name)
            info = os.stat(leaf, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISDIR(info.st_mode):
                child = opened(leaf, os.O_RDONLY | os.O_DIRECTORY, fd)
                try:
                    if fingerprint(os.fstat(child)) != fingerprint(info):
                        raise ValueError("input directory changed during discovery")
                    visit(child, name)
                finally:
                    os.close(child)
            elif stat.S_ISREG(info.st_mode):
                child = opened(leaf, os.O_RDONLY | os.O_NONBLOCK, fd)
                try:
                    before_file = fingerprint(os.fstat(child))
                    if before_file != fingerprint(info):
                        raise ValueError("input file changed during discovery")
                    with os.fdopen(child, "rb", closefd=False) as stream:
                        size, sha = digest_stream(stream)
                    if fingerprint(os.fstat(child)) != before_file or size != info.st_size:
                        raise ValueError("input file changed while hashing")
                    files[name] = {"size": size, "sha256": sha, "fingerprint": before_file}
                finally:
                    os.close(child)
            else:
                raise ValueError("input must contain only regular files/directories; symlinks are forbidden")
        if fingerprint(os.fstat(fd)) != before:
            raise ValueError("input directory changed while hashing")

    with root_directory(raw) as root:
        visit(root, "")
    return {"files": files, "directories": directories}


def validate_index(index):
    if not isinstance(index, dict) or index.get("format") != FORMAT:
        raise ValueError("invalid archive index format")
    if not isinstance(index.get("files"), dict) or not isinstance(index.get("directories"), dict):
        raise ValueError("invalid archive member inventory")
    for name, value in index["files"].items():
        safe_name(name)
        if (not isinstance(value, dict) or type(value.get("size")) is not int or value["size"] < 0
                or not isinstance(value.get("sha256"), str) or len(value["sha256"]) != 64
                or any(char not in "0123456789abcdef" for char in value["sha256"])):
            raise ValueError("invalid archive member size/hash")
    for name in index["directories"]:
        if name != ".":
            safe_name(name)
    if set(index["files"]) & set(index["directories"]):
        raise ValueError("file/directory member collision")
    if "." not in index["directories"]:
        raise ValueError("archive index is missing its root directory")
    if (type(index.get("file_count")) is not int or index["file_count"] != len(index["files"])
            or type(index.get("total_bytes")) is not int
            or index["total_bytes"] != sum(value["size"] for value in index["files"].values())):
        raise ValueError("archive index totals mismatch")
    for name in set(index["files"]) | (set(index["directories"]) - {"."}):
        parent = str(PurePosixPath(name).parent)
        if parent not in index["directories"]:
            raise ValueError("archive index is missing a parent directory")


def verify_archive(archive, index, raw=None):
    """Never extract: inspect safe headers, exact inventory, hashes and optional bytes."""
    validate_index(index)
    expected = set(index["files"]) | (set(index["directories"]) - {"."})
    seen = set()
    raw_before = snapshot(raw) if raw is not None else None
    if raw_before is not None and raw_before != {key: index[key] for key in ("files", "directories")}:
        raise ValueError("raw input differs from its indexed snapshot")
    with path_file(archive) as source, (root_directory(raw) if raw is not None else context_empty()) as root:
        if digest_stream(source)[1] != index["archive_sha256"]:
            raise ValueError("archive hash mismatch")
        source.seek(0)
        with tarfile.open(fileobj=source, mode="r:gz") as packed:
            for member in packed:
                name = member.name[:-1] if member.isdir() and member.name.endswith("/") else member.name
                safe_name(name)
                if name in seen or name not in expected:
                    raise ValueError("duplicate or unexpected archive member")
                seen.add(name)
                if member.isdir():
                    if name not in index["directories"] or member.size != 0:
                        raise ValueError("archive directory shape mismatch")
                    continue
                if not member.isreg() or name not in index["files"]:
                    raise ValueError("unsafe archive member type; links are forbidden")
                wanted = index["files"][name]
                if member.size != wanted["size"]:
                    raise ValueError("archive member size mismatch")
                with packed.extractfile(member) as stored:
                    if root is None:
                        size, sha = digest_stream(stored)
                    else:
                        with member_file(root, name) as original:
                            before = fingerprint(os.fstat(original.fileno()))
                            digest, size = hashlib.sha256(), 0
                            while data := stored.read(CHUNK):
                                if original.read(len(data)) != data:
                                    raise ValueError("archive round-trip byte mismatch")
                                digest.update(data)
                                size += len(data)
                            if original.read(1) or fingerprint(os.fstat(original.fileno())) != before:
                                raise ValueError("input changed during archive verification")
                            sha = digest.hexdigest()
                    if (size, sha) != (wanted["size"], wanted["sha256"]):
                        raise ValueError("archive member hash mismatch")
    if seen != expected:
        raise ValueError("archive is missing members")
    if raw_before is not None and snapshot(raw) != raw_before:
        raise ValueError("raw input changed during archive verification")
    return len(index["files"])


@contextmanager
def context_empty():
    yield None


@contextmanager
def new_directory(path):
    """The parent must exist; never follow symlinks or reuse an output directory."""
    with root_directory(path.parent) as parent:
        os.mkdir(path.name, mode=0o700, dir_fd=parent)
        child = opened(path.name, os.O_RDONLY | os.O_DIRECTORY, parent)
        try:
            yield child
        finally:
            os.close(child)


def write_json(root, name, value):
    fd = opened(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, root)
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + "\n")


def create_archive(raw, output):
    raw, output = absolute(raw), absolute(output)
    if output == raw or output.is_relative_to(raw):
        raise ValueError("archive output must be outside the immutable raw directory")
    before = snapshot(raw)
    archive, index_path = output / "raw-processes.tar.gz", output / "index.json"
    with new_directory(output) as destination:
        try:
            fd = opened(archive.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, destination)
            with os.fdopen(fd, "wb") as target:
                with gzip.GzipFile(filename="", mode="wb", fileobj=target, mtime=0) as compressed:
                    with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as packed:
                        for name in sorted(set(before["files"]) | (set(before["directories"]) - {"."})):
                            info = tarfile.TarInfo(name)
                            info.mtime, info.uid, info.gid, info.mode = 0, 0, 0, 0o600
                            if name in before["directories"]:
                                info.type, info.mode = tarfile.DIRTYPE, 0o700
                                packed.addfile(info)
                            else:
                                info.size = before["files"][name]["size"]
                                with root_directory(raw) as root, member_file(root, name) as stream:
                                    wanted = before["files"][name]["fingerprint"]
                                    if fingerprint(os.fstat(stream.fileno())) != wanted:
                                        raise ValueError("input file changed before archiving")
                                    packed.addfile(info, stream)
                                    if fingerprint(os.fstat(stream.fileno())) != wanted:
                                        raise ValueError("input file changed while archiving")
            index = {"format": FORMAT, "raw_directory": str(raw), **before,
                     "archive_sha256": digest_file(archive), "file_count": len(before["files"]),
                     "total_bytes": sum(value["size"] for value in before["files"].values())}
            verify_archive(archive, index, raw)
            if snapshot(raw) != before:
                raise ValueError("input changed during archive creation")
            write_json(destination, index_path.name, index)
            if snapshot(raw) != before:
                raise ValueError("input changed before archive completion")
            with root_directory(output) as current:
                original, visible = os.fstat(destination), os.fstat(current)
                if (original.st_dev, original.st_ino) != (visible.st_dev, visible.st_ino):
                    raise ValueError("archive output directory was replaced")
            write_json(destination, "status.json", {"complete": True,
                "lossless_bytes_verified": True, "files": index["file_count"], "bytes": index["total_bytes"]})
            return index
        except Exception as error:
            write_json(destination, "status.json", {"complete": False, "error": str(error)})
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    create = commands.add_parser("create")
    create.add_argument("--raw", type=Path, required=True)
    create.add_argument("--output", type=Path, required=True)
    check = commands.add_parser("verify")
    check.add_argument("--archive", type=Path, required=True)
    check.add_argument("--index", type=Path, required=True)
    check.add_argument("--raw", type=Path, help="Additionally compare every original byte")
    args = parser.parse_args()
    try:
        if args.command == "create":
            index = create_archive(args.raw, args.output)
            count = index["file_count"]
        else:
            with path_file(args.index) as stream:
                index = json.load(stream)
            count = verify_archive(args.archive, index, args.raw)
        print(f"raw archive verified: {count} files; no compiler qualification claim")
        return 0
    except (OSError, ValueError, KeyError, EOFError, tarfile.TarError) as error:
        print(f"archive rejected: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
