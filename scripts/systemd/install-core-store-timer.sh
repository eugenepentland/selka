#!/usr/bin/env bash
# Preview by default. The closeout coordinator installs this only in round R4.
set -euo pipefail
case "${1:-}" in
    ""|--dry-run) apply=0 ;;
    --apply) apply=1 ;;
    *) echo 'usage: install-core-store-timer.sh [--dry-run|--apply]' >&2; exit 2 ;;
esac
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
python3 - "$script_dir" "$apply" <<'PY'
import importlib.util
import os
from pathlib import Path
import subprocess
import sys

source = Path(sys.argv[1])
root = source.parent.parent
sys.path.insert(0, str(root / "scripts"))
import service_worktree
spec = importlib.util.spec_from_file_location("nightly_installer", root / "scripts/install-nightly-integration-timer.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)
destination = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "systemd" / "user"
command = f'/usr/bin/python3 {installer.quote(root / "scripts/service_worktree.py")} --worktree {installer.quote(root)} --service core -- --apply'
units = {
    "selka-core-store.service": (source / "selka-core-store.service").read_text().replace("@WORKTREE@", installer.working_directory(root)).replace("@COMMAND@", command),
    "selka-core-store.timer": (source / "selka-core-store.timer").read_text(),
}
for name, contents in units.items():
    print(f"{destination / name}:\n{contents}")
if sys.argv[2] == "1":
    service_worktree.register(root)
    destination.mkdir(parents=True, exist_ok=True)
    for name, contents in units.items():
        target = destination / name
        temporary = target.with_suffix(target.suffix + ".new")
        temporary.write_text(contents)
        temporary.replace(target)
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
    subprocess.run(["systemctl", "--user", "enable", "--now", "selka-core-store.timer"], check=True)
else:
    print("Preview only; no unit was written or enabled.")
PY
