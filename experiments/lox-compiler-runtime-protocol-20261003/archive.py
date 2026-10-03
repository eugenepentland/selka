"""Content-addressed evidence copies; verification never executes payloads."""
import datetime
import json
import os
from pathlib import Path
import shutil
import tempfile

from validation import require, sha


def absolute(path):
    return Path(os.path.abspath(path))


def regular_files(root):
    root = absolute(root)
    if root.is_file():
        yield root
        return
    require(root.is_dir() and not root.is_symlink(), "extra root is not a regular file/directory: " + str(root))
    for parent, directories, files in os.walk(root, followlinks=False):
        current = Path(parent)
        kept = []
        for name in sorted(directories):
            path = current / name
            cache = name in (".zig-cache", "zig-cache", "__pycache__") or (current == root and name.startswith("cache-"))
            cache = cache or (name == "target" and (current / "Cargo.toml").is_file())
            if cache:
                continue
            require(not path.is_symlink(), "directory symlink is not inventoried: " + str(path))
            kept.append(name)
        directories[:] = kept
        for name in sorted(files):
            path = current / name
            require(path.is_file(), "special/missing evidence file: " + str(path))
            yield path


def inventory(work, guards, extras, tools):
    roots = [absolute(work), *map(absolute, extras)]
    paths = set(map(absolute, guards)) | set(map(absolute, tools))
    for root in roots:
        paths.update(regular_files(root))
    records = {}
    for path in sorted(paths):
        require(path.is_file(), "evidence source missing: " + str(path))
        records[str(path)] = {"sha256": sha(path), "bytes": path.stat().st_size,
                              "symlink_target": os.readlink(path) if path.is_symlink() else None}
    return records


def verify(destination, originals=False, expected_manifest=None):
    destination = destination.resolve()
    require(not (destination / "FAILED.json").exists(), "archive is explicitly marked failed")
    manifest_path = destination / "MANIFEST.json"
    require(manifest_path.is_file() and not manifest_path.is_symlink(), "archive manifest must be a regular file")
    require((destination / "objects").is_dir() and not (destination / "objects").is_symlink(), "archive objects must be a regular directory")
    require({path.name for path in destination.iterdir()} == {"MANIFEST.json", "objects"}, "unexpected archive entry")
    if expected_manifest is not None:
        require(sha(manifest_path) == expected_manifest, "archive manifest identity differs")
    manifest = json.loads(manifest_path.read_text())
    require(manifest["version"] == "lox-compiler-evidence-v1", "unknown archive version")
    objects = manifest["objects"]
    require(set(objects) == {item["sha256"] for item in manifest["files"].values()}, "archive object/file sets differ")
    for digest, record in objects.items():
        require(len(digest) == 64 and all(char in "0123456789abcdef" for char in digest), "invalid object identity")
        require(type(record["bytes"]) is int and record["bytes"] >= 0, "invalid object byte count")
    on_disk = set()
    for path in (destination / "objects").rglob("*"):
        require(not path.is_symlink(), "archive object tree must contain no symlinks")
        if path.is_file():
            digest = path.name
            require(len(digest) == 64 and all(char in "0123456789abcdef" for char in digest), "invalid object name")
            require(path.relative_to(destination / "objects").parts == (digest[:2], digest), "object stored in wrong location")
            require(digest not in on_disk, "duplicate object")
            on_disk.add(digest)
            require(digest in objects and sha(path) == digest and path.stat().st_size == objects[digest]["bytes"], "archive object changed")
        else:
            require(path.is_dir(), "archive object tree contains a special file")
    require(on_disk == set(objects), "missing or unexpected archive objects")
    for path, record in manifest["files"].items():
        require(Path(path).is_absolute(), "original identity path is not absolute")
        require(record["bytes"] == objects[record["sha256"]]["bytes"], "file/object size differs")
        if originals:
            original = Path(path)
            require(original.is_file() and sha(original) == record["sha256"], "original changed/missing: " + path)
            link = os.readlink(original) if original.is_symlink() else None
            require(link == record["symlink_target"], "original symlink identity changed: " + path)
    return {"archive": str(destination), "manifest_sha256": sha(manifest_path),
            "objects_verified": len(objects), "original_paths_recorded": len(manifest["files"]),
            "original_identities_checked": originals, "original_identity_claim": "verified" if originals else "not checked",
            "performance_selection_inferred": False}


def create(work, guards, extras, report, destination, tools):
    destination = absolute(destination)
    require(not destination.exists(), "refusing to overwrite archive")
    roots = [absolute(work), *map(absolute, extras)]
    for root in roots:
        require(not destination.is_relative_to(root), "archive cannot be inside an evidence root")
    if "validated_inventory" in report:
        require(inventory(work, guards, [], []) == report["validated_inventory"], "work changed or grew after validation")
    records = inventory(work, guards, extras, tools)
    for path, digest in guards.items():
        require(records[str(absolute(path))]["sha256"] == digest, "guard changed before archive")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = Path(tempfile.mkdtemp(prefix=destination.name + ".pending-", dir=destination.parent))
    try:
        objects = {}
        for path, record in records.items():
            digest = record["sha256"]
            if digest not in objects:
                target = temporary / "objects" / digest[:2] / digest
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
                require(sha(target) == digest and target.stat().st_size == record["bytes"], "copy differs: " + path)
                objects[digest] = {"bytes": record["bytes"]}
        require(inventory(work, guards, extras, tools) == records, "evidence changed or grew during archive")
        manifest = {"version": "lox-compiler-evidence-v1", "created_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    "work": str(absolute(work)), "files": records, "objects": objects, "validated_closeout": report,
                    "extra_roots": list(map(str, map(absolute, extras))), "extras_are_successful_measurements": False,
                    "excluded_build_cache_directories": ["top-level cache-*", ".zig-cache", "zig-cache", "__pycache__", "Cargo-project target"],
                    "guarded_files_override_cache_exclusions": True, "performance_selection_inferred": False}
        (temporary / "MANIFEST.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        verify(temporary, originals=True)
        require(not destination.exists(), "archive destination appeared during sealing")
        temporary.rename(destination)
        require(inventory(work, guards, extras, tools) == records, "evidence changed or grew after archive promotion")
        return verify(destination, originals=True)
    except Exception as error:
        failed = temporary if temporary.exists() else destination
        (failed / "FAILED.json").write_text(json.dumps({"status": "failed; not a completed archive", "error": str(error)}, indent=2) + "\n")
        raise ValueError("archive failed; retained evidence at " + str(failed)) from error
