"""Run a public guest and relink its recorded objects to count real admission."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--compiler", type=Path, required=True)
parser.add_argument("--qbe", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
options = parser.parse_args()
options.output.mkdir(parents=True, exist_ok=True)
root = Path(__file__).resolve().parents[2]
source = Path(__file__).with_name("local-list.my")
wrapper = Path(__file__).with_name("admission-wrap.c")
for backend in ("qbe", "llvm"):
    cache = options.output / f"guest-{backend}"
    executable = options.output / f"local-{backend}"
    subprocess.run([
        str(options.compiler), "build", str(source), "--backend", backend,
        "--qbe", str(options.qbe), "--keep-symbols", f"--cache-dir={cache}",
        "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
    manifest = json.loads(Path(f"{executable}.qbe-manifest.json").read_text())
    objects = Path(manifest["functions"][0]["object"]).parent
    receipt = next(objects.glob("link-*.args"))
    wrapper_object = options.output / f"wrap-{backend}.o"
    subprocess.run(["zig", "cc", "-O3", "-UNDEBUG", "-I", str(root / "src"),
                    "-c", str(wrapper), "-o", str(wrapper_object)], check=True)
    wrapped = options.output / f"counted-{backend}"
    arguments = []
    for argument in receipt.read_bytes().split(b"\0"):
        if argument == b"\x01objects":
            arguments.extend(str(path) for path in sorted(objects.glob("*.o")))
            arguments.append(str(wrapper_object))
        elif argument == b"\x01output":
            arguments.append(str(wrapped))
        else:
            arguments.append(argument.decode())
    subprocess.run(["zig", *arguments, "--wrap=myl_qbe_local_list"], check=True)
    subprocess.run([str(wrapped)], check=True)
