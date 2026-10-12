#!/usr/bin/env python3
"""Materialize the reviewed Debian native runtime; never approve host hashes.

Developer provisioning only. The compiler and native-bundle.sh use no Python.
The checked-in release, key fingerprints and package records are a frozen review,
not an updater. A package change requires a new profile and qualification.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import lzma
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.request

PROFILE = Path(__file__).resolve().parent / "native-platform/debian13"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def checked(data: bytes, expected: str, size: int | None = None) -> bytes:
    if digest(data) != expected or (size is not None and len(data) != size):
        raise ValueError("authenticated content hash/size mismatch")
    return data


def download(url: str, destination: Path, expected: str, size: int) -> bytes:
    if destination.exists():
        return checked(destination.read_bytes(), expected, size)
    with urllib.request.urlopen(url, timeout=60) as response:
        data = checked(response.read(size + 1), expected, size)
    destination.write_bytes(data)
    return data


def package_records(data: bytes) -> dict[str, dict[str, str]]:
    records = {}
    for block in lzma.decompress(data).decode().split("\n\n"):
        fields = dict(line.split(": ", 1) for line in block.splitlines()
                      if ": " in line and not line.startswith(" "))
        if "Package" in fields:
            records[fields["Package"]] = fields
    return records


def authenticate(profile: Path, manifest: dict, downloads: Path) -> dict:
    release = checked((profile / "InRelease").read_bytes(), manifest["release_sha256"])
    keys = b"".join(checked((profile / key["file"]).read_bytes(), key["sha256"])
                    for key in manifest["keys"])
    with tempfile.TemporaryDirectory(dir=downloads) as temp:
        keyring = Path(temp) / "keys.gpg"
        keyring.write_bytes(subprocess.run(["gpg", "--batch", "--dearmor"], input=keys,
                                          capture_output=True, check=True).stdout)
        result = subprocess.run(["gpgv", "--status-fd", "1", "--keyring", str(keyring),
                                 str(profile / "InRelease")], capture_output=True, check=True)
    valid = {line.split()[-1] for line in result.stdout.decode().splitlines()
             if line.startswith("[GNUPG:] VALIDSIG ")}
    if not {key["fingerprint"] for key in manifest["keys"]} <= valid:
        raise ValueError("release lacks the reviewed archive/release signatures")
    index = manifest["index"]
    sha_lines = release.decode().split("\nSHA256:\n", 1)[1].split("\n-----BEGIN PGP", 1)[0]
    if [index["sha256"], str(index["size"]), index["path"]] not in [line.split() for line in sha_lines.splitlines()]:
        raise ValueError("package index is absent from signed release")
    index_url = manifest["archive"] + "dists/trixie/main/binary-amd64/by-hash/SHA256/" + index["sha256"]
    data = download(index_url, downloads / "Packages.xz", index["sha256"], index["size"])
    records = package_records(data)
    for package in manifest["packages"]:
        observed = records.get(package["Package"], {})
        if any(observed.get(key) != value for key, value in package.items()):
            raise ValueError("package record differs from authenticated index")
        download(manifest["archive"] + package["Filename"], downloads / Path(package["Filename"]).name,
                 package["SHA256"], int(package["Size"]))
    return {"release_sha256": digest(release), "valid_signatures": sorted(valid),
            "gpgv_stdout": result.stdout.decode(), "gpgv_stderr": result.stderr.decode()}


def materialize(manifest: dict, downloads: Path, root: Path) -> None:
    # Extraction-only runtime closure, not a general Debian installation. There
    # are no maintainer scripts, networking tools, native GCC or system headers.
    root.mkdir()
    for directory in ("usr/lib", "usr/lib64", "usr/bin", "usr/sbin", "etc", "tmp", "proc", "dev", "opt/selka/toolchain", "opt/selka/components", "work"):
        (root / directory).mkdir(parents=True, exist_ok=True)
    # Generated mount points must be reproducible under a different host umask.
    for path in (root, *[p for p in root.rglob("*") if p.is_dir()]):
        path.chmod(0o755)
    (root / "opt/selka/mylang").touch()
    (root / "opt/selka/mylang").chmod(0o644)
    for name, target in (("lib", "usr/lib"), ("lib64", "usr/lib64"), ("bin", "usr/bin"), ("sbin", "usr/sbin")):
        (root / name).symlink_to(target)
    for package in manifest["packages"]:
        subprocess.run(["dpkg-deb", "-x", str(downloads / Path(package["Filename"]).name), str(root)], check=True)
    # Use authenticated Debian ldconfig inside its own root, never the host's
    # loader cache or libraries. -X leaves the package's symlink tree unchanged.
    subprocess.run(["bwrap", "--unshare-user", "--ro-bind", str(root), "/", "--bind",
                    str(root / "etc"), "/etc", "--proc", "/proc", "--dev", "/dev", "--",
                    "/usr/sbin/ldconfig", "-X"], check=True)
    checked((root / "etc/ld.so.cache").read_bytes(), manifest["loader_cache_sha256"])


def tree_manifest(root: Path) -> list[dict]:
    result = []
    for directory, names, files in os.walk(root, followlinks=False):
        for name in sorted(names + files):
            path = Path(directory) / name
            row = {"path": path.relative_to(root).as_posix(), "mode": path.lstat().st_mode & 0o7777}
            if path.is_symlink():
                row.update(kind="symlink", target=os.readlink(path))
            elif path.is_dir():
                row.update(kind="directory")
            elif path.is_file():
                row.update(kind="file", sha256=digest(path.read_bytes()))
            else:
                raise ValueError("unexpected special file in package tree")
            result.append(row)
    return sorted(result, key=lambda row: row["path"])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path, help="new bundle directory (must not exist)")
    parser.add_argument("--downloads", type=Path, help="private retained download directory")
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.exists():
        parser.error("destination already exists; no existing bundle will be overwritten")
    downloads = (args.downloads or destination.parent / "native-bundle-downloads").resolve()
    downloads.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((PROFILE / "manifest.json").read_text())
    authentication = authenticate(PROFILE, manifest, downloads)
    destination.parent.mkdir(parents=True, exist_ok=True)
    # A failed build has no published bundle; its private staging remains only
    # until this context exits. Never repair or refresh reviewed constants here.
    with tempfile.TemporaryDirectory(prefix=".native-bundle-", dir=destination.parent) as temp:
        stage = Path(temp) / "bundle"
        stage.mkdir()
        materialize(manifest, downloads, stage / "rootfs")
        tree = tree_manifest(stage / "rootfs")
        tree_bytes = (json.dumps(tree, sort_keys=True, indent=2) + "\n").encode()
        checked(tree_bytes, manifest["tree_sha256"])
        (stage / "tree.json").write_bytes(tree_bytes)
        (stage / "receipt.json").write_text(json.dumps({"profile": manifest["id"], "authentication": authentication,
                                                        "tree_sha256": digest(tree_bytes)}, indent=2) + "\n")
        stage.rename(destination)
    print(f"Materialized {manifest['id']} at {destination}")


if __name__ == "__main__":
    main()
