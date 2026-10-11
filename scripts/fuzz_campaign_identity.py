"""Exact local tool and input contracts for developer fuzz campaigns."""
from __future__ import annotations

import hashlib
import marshal
import os
from pathlib import Path
import shutil
import sys
import sysconfig

import verification_snapshot
import verify_cache as verification

LOADED_CODE_SHA256 = hashlib.sha256(marshal.dumps(sys._getframe().f_code)).hexdigest()

COMMON_INPUTS = ["scripts/fuzz_campaign.py", "scripts/fuzz_campaign_identity.py",
                 "scripts/fuzz_campaign_store.py", "scripts/verify_cache.py",
                 "scripts/verification_snapshot.py", "scripts/cache_session.py", "scripts/build-slot.sh"]


def executable(value: str, environment: dict[str, str]) -> Path:
    """Resolve a selected executable without losing its symlink lookup path."""
    found = shutil.which(value, path=environment.get("PATH"))
    if found is None:
        raise verification.VerificationError("executable is unavailable: " + value)
    return Path(found).absolute()


def tools(environment: dict[str, str], binaries: list[Path], zig: Path | None) -> tuple[list[str], list[Path]]:
    """Include Python, admission tools, loader libraries and optional Zig resources."""
    if zig is not None:
        recipes, files = verification.tool_contract(zig, environment)
    else:
        selected = {Path(sys.executable)}
        for name in (*verification.HOST_TOOLS, "ldd"):
            selected.add(executable(name, environment))
        stdlib = Path(sysconfig.get_path("stdlib"))
        recipes = [str(stdlib / "*.py")]
        recipes += [str(p) + "/" for p in sorted(stdlib.iterdir())
                    if p.is_dir() and not p.name.startswith(".")
                    and p.name not in ("site-packages", "dist-packages", "__pycache__")]
        for directory in environment.get("PATH", "").split(os.pathsep):
            if not directory or not Path(directory).is_dir():
                raise verification.VerificationError("tool search directory disappeared")
            recipes.append(str(Path(directory).absolute()) + "/*.verification-tool-membership")
        extensions = list((stdlib / "lib-dynload").glob("*.so"))
        selected.update(verification.shared_libraries(sorted(selected) + extensions, environment))
        selected.update(Path(p) for p in ("/etc/ld.so.cache", "/etc/ld.so.conf", "/etc/os-release")
                        if Path(p).is_file())
        files = sorted(selected)
    libraries = verification.shared_libraries(binaries, environment)
    return recipes, sorted(set(files + binaries + libraries))


def unsupported(environment: dict[str, str]) -> list[str]:
    """External loader/tool injection cannot receive ordinary campaign receipts."""
    reasons = [name for name in verification.UNTRACKED_ENV if environment.get(name)]
    if environment.get("MYL_CORE_LEAKCHECK", "0") != "0":
        reasons.append("MYL_CORE_LEAKCHECK")
    return reasons


def components(directory: Path) -> tuple[list[Path], list[Path]]:
    """Bind explicit manifest artifacts, including permitted dot-prefixed names."""
    files, binaries = [], []
    for name in ("test-index", "cache-plan"):
        path = directory.absolute() / (name + ".json")
        document = verification.read_record(path)
        artifact = document.get("artifact") if document else None
        if (not isinstance(artifact, str) or not artifact or artifact in (".", "..")
                or "/" in artifact or "\\" in artifact or "\0" in artifact):
            raise verification.VerificationError("invalid component manifest: " + str(path))
        binary = path.parent / artifact
        files.extend([path, binary])
        binaries.append(binary)
    return files, binaries


def seed(master: int, ordinal: int) -> int:
    """Versioned independent nonzero libFuzzer-compatible seed, unaffected by budget."""
    value = verification.key({"policy": "independent-seed-shards-v1", "seed": master})
    # Adjacent shard ordinals are a bijection within the supported 1,024-shard
    # budget, avoiding accidental birthday collisions from truncated hashes.
    return (int(value[:16], 16) + ordinal) % 4294967295 + 1


def family(root: Path, kind: str, name: str) -> str:
    """Locate retained inputs across target revisions without carrying verdicts."""
    return verification.key({"domain": "fuzz-corpus-family-v1", "root": str(root),
                             "kind": kind, "name": name})


def action(contract: dict, operation: str, value: object) -> str:
    """Separate exploration shards and concrete-corpus replay evidence."""
    return verification.key({"domain": "fuzz-action-v1", "contract": contract,
                             "operation": operation, "value": value})
