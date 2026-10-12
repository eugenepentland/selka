"""Qualification fixture for direct exclusive admission; not a production launcher."""
import os
from pathlib import Path


def verify(environment, expected_cpus, *, descriptors=(8, 9)):
    """Return admission provenance only with both inherited exclusive locks held.

    The direct shell timing launcher keeps these descriptors through exec. This
    contract deliberately does not accept the Python admission context manager,
    whose separate holder has a different descriptor and process ownership.
    """
    if environment.get("MYLANG_ADMISSION_KIND") != "timing":
        raise ValueError("exclusive timing admission required")
    directory = Path(environment.get("MYLANG_ADMISSION_DIR", ""))
    if not directory.is_absolute() or directory.resolve() != directory:
        raise ValueError("canonical admission directory required")
    affinity = sorted(os.sched_getaffinity(0))
    if not expected_cpus or sorted(set(expected_cpus)) != affinity:
        raise ValueError("declared measurement affinity differs")
    locks = []
    for descriptor, filename in zip(descriptors, ("admit.lock", "timing1.lock"), strict=True):
        path = directory / filename
        try:
            held = os.fstat(descriptor)
            live = path.stat()
            records = Path(f"/proc/self/fdinfo/{descriptor}").read_text().splitlines()
        except OSError as error:
            raise ValueError("inherited admission descriptor unavailable") from error
        if (held.st_dev, held.st_ino) != (live.st_dev, live.st_ino):
            raise ValueError("inherited admission descriptor names another file")
        fields = [line.split() for line in records if line.startswith("lock:")]
        if not any(row[2:5] == ["FLOCK", "ADVISORY", "WRITE"]
                   and row[5] == str(os.getpid()) for row in fields):
            raise ValueError("inherited exclusive lock is not owned by this process")
        locks.append({"descriptor": descriptor, "path": str(path),
                      "device": held.st_dev, "inode": held.st_ino})
    return {"contract": "direct-exclusive-admission-v1", "pid": os.getpid(),
            "directory": str(directory), "affinity": affinity, "locks": locks}
