"""Shared fail-closed evidence checks; callers own build/timing admission."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

RC_SITES = {"retain", "release", "unique_test", "uniqueness"}
RC_TOTALS = ("runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks")
RC_SYMBOLS = ("myl_core_retain", "myl_core_release", "myl_core_share", "myl_core_free_block")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n")


def fresh_output(path):
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        raise ValueError(f"refusing to overwrite existing evidence: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path


def mode_flags(mode):
    if mode not in ("ordinary", "zero", "default"):
        raise ValueError(mode)
    return ["--experimental-zero-rc"] if mode == "zero" else []


def clean_env():
    env = dict(os.environ)
    for key in ("MYLANG_COUNTERS", "MYLANG_OPTIONS", "MYLANG_CORE_SANITIZE", "MYL_CORE_LEAKCHECK"):
        env.pop(key, None)
    return env


def call(argv, env=None, cwd=None, timeout=300):
    argv = list(map(str, argv))
    try:
        p = subprocess.run(argv, env=env, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return dict(argv=argv, status=p.returncode, stdout=p.stdout, stderr=p.stderr)
    except subprocess.TimeoutExpired as error:
        def decode(value):
            return value.decode(errors="replace") if isinstance(value, bytes) else value or ""
        return dict(argv=argv, status=124, timed_out=True,
                    stdout=decode(error.stdout), stderr=decode(error.stderr))


def counter_audit(path):
    if not path.exists():
        return {"counts_present": False, "leak_free": False, "rc_events": None}
    counts = json.loads(path.read_text())
    totals = counts["totals"]
    # The sum is a zero/nonzero guard. Site and native hooks may overlap, so it
    # is not an estimate of distinct RC operations.
    events = sum(site["count"] for site in counts["sites"] if site["kind"] in RC_SITES)
    events += sum(totals.get(key, 0) for key in RC_TOTALS)
    # Historical release_unique sites are direct destruction in owned mode;
    # count_test.zig deliberately expects them with zero retain/release/test.
    destruction = sum(site["count"] for site in counts["sites"] if site["kind"] == "release_unique")
    return dict(counts_present=True, counts_sha256=sha(path), counts=counts,
                release_unique_sites=destruction,
                leak_free=totals["live_bytes_at_exit"] == 0, rc_events=events)


def artifact_audit(binary, llvm):
    symbols = subprocess.check_output(["nm", str(binary)], text=True)
    emitted = llvm.read_text()
    forbidden_symbols = [name for name in RC_SYMBOLS if name in symbols]
    forbidden_llvm = [name for name in RC_SYMBOLS if "@" + name in emitted]
    if "load atomic i32" in emitted:
        forbidden_llvm.append("atomic i32 count load")
    if re.search(r"store i32[^\n]*!tbaa !3", emitted):
        forbidden_llvm.append("legacy count-tagged i32 store")
    return dict(binary_sha256=sha(binary), llvm_sha256=sha(llvm),
                symbols_clean=not forbidden_symbols, llvm_clean=not forbidden_llvm,
                forbidden_symbols=forbidden_symbols, forbidden_llvm=forbidden_llvm)


def owned_clean(run, artifact):
    return (run.get("counts_present", False) and run.get("leak_free", False)
            and run.get("rc_events") == 0 and artifact.get("symbols_clean", False)
            and artifact.get("llvm_clean", False))
