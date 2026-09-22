#!/usr/bin/env python3
"""Rewrite unambiguous checked aggregate list reads, then build matched LTO arms."""
import hashlib, json, os, re, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / ".tmp/svg-gap-audit-20260921/codegen"
OUT = ROOT / "experiments/svg-gap-audit-20260921/codegen"
COMPILER = ROOT / ".tmp/svg-gap-audit-20260921/mylang-audit-compiler"
ENTRY = ROOT / ".tmp/svg-arenas-20260921/guest-gc/main.my"
CALL = re.compile(r"^( %v(\d+) =w call \$myl_native_list_get\(l %v(\d+), l %v(\d+), l %agg(\d+)\))$", re.M)
ALLOC = re.compile(r"^ %agg(\d+) =l alloc8 (\d+)$", re.M)
FRAME_SLOT = re.compile(r"^ %(\w+) =l add %frame_memory, (\d+)$", re.M)
TEMP = re.compile(r"%v(\d+)")

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def rewrite_il(il):
    allocations = {int(a): int(size) for a, size in ALLOC.findall(il)}
    frame_slots = [(name, int(offset)) for name, offset in FRAME_SLOT.findall(il)]
    offsets = sorted(set(offset for _, offset in frame_slots))
    next_offset = {offset: offsets[i + 1] for i, offset in enumerate(offsets[:-1])}
    for name, offset in frame_slots:
        if name.startswith("agg") and offset in next_offset:
            allocations[int(name[3:])] = next_offset[offset] - offset
    next_temp = max(map(int, TEMP.findall(il)), default=0) + 1
    rewritten, cursor, sites = [], 0, []
    for match in CALL.finditer(il):
        output, list_value, index, scratch = map(int, match.groups()[1:])
        size = allocations.get(scratch)
        prefix = il[max(cursor, match.start() - 300):match.start()]
        length_match = re.search(rf" %v(\d+) =l loadl %v{list_value}\n$", prefix)
        if size is None or size <= 0 or length_match is None:
            continue
        length = int(length_match.group(1))
        descriptor_slot, descriptor, actual_size, size_matches, header, storage, offset, source = range(next_temp, next_temp + 8)
        next_temp += 8
        label = f"aggget{output}"
        replacement = (
            f" %v{descriptor_slot} =l add %v{list_value}, 24\n %v{descriptor} =l loadl %v{descriptor_slot}\n"
            f" %v{actual_size} =l loadl %v{descriptor}\n %v{size_matches} =w ceql %v{actual_size}, {size}\n"
            f" jnz %v{size_matches}, @{label}checked, @{label}runtime\n@{label}runtime\n"
            f" %v{output} =w call $myl_native_list_get(l %v{list_value}, l %v{index}, l %agg{scratch})\n"
            f" jmp @{label}done\n@{label}checked\n"
            f" %v{output} =w cultl %v{index}, %v{length}\n"
            f" jnz %v{output}, @{label}copy, @{label}done\n@{label}copy\n"
            f" %v{header} =l add %v{list_value}, 32\n %v{storage} =l loadl %v{header}\n"
            f" %v{offset} =l mul %v{index}, {size}\n %v{source} =l add %v{storage}, %v{offset}\n"
            f" blit %v{source}, %agg{scratch}, {size}\n jmp @{label}done\n@{label}done")
        rewritten.extend((il[cursor:match.start()], replacement))
        cursor = match.end()
        sites.append({"output": output, "receiver": list_value, "index": index,
                      "length": length, "scratch": scratch, "size": size})
    rewritten.append(il[cursor:])
    return "".join(rewritten), sites

records = {}
for accounting in ("none", "both"):
    source = WORK / f"emitted-{accounting}.json"
    target = WORK / f"emitted-{accounting}-aggregate-inline.json"
    document = json.loads(source.read_text())
    sites = []
    for function in document["functions"]:
        function["il"], changed = rewrite_il(function["il"])
        sites.extend({"function": function["name"], **site} for site in changed)
    target.write_text(json.dumps(document, separators=(",", ":")))
    binary = WORK / f"gc-lto-{accounting}-aggregate-inline"
    command = [str(COMPILER), "build", str(ENTRY), "--project", "--provider",
               "src/schematic/native_schematic.c", "--backend", "llvm",
               "--llvm-adapter", str(ROOT / "experiments/llvm-backend/qbe_llvm.py"),
               "--zig", "/home/epentland/.local/bin/zig", "--llvm-opt", "3", "--lto",
               "--keep-symbols", f"--manifest-file={target}", "--cache-dir",
               str(WORK / f"cache-{accounting}-aggregate-inline"), "--report", "-o", str(binary)]
    env = dict(os.environ, MYLANG_HOST_COMPILER=str(COMPILER), MYLANG_MEMORY_LIMIT="268435456")
    result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True)
    (WORK / f"aggregate-inline-{accounting}-build.stdout").write_bytes(result.stdout)
    (WORK / f"aggregate-inline-{accounting}-build.stderr").write_bytes(result.stderr)
    if result.returncode: raise SystemExit(f"{accounting} build failed: {result.stderr.decode(errors='replace')}")
    records[accounting] = {"source_manifest_sha256": sha(source), "rewritten_manifest_sha256": sha(target),
                           "binary_sha256": sha(binary), "rewritten_sites": len(sites),
                           "remaining_list_get_calls": sum(f["il"].count("call $myl_native_list_get") for f in document["functions"]),
                           "sites": sites, "command": command}
(OUT / "aggregate-inline-builds.json").write_text(json.dumps({"compiler_sha256": sha(COMPILER), "builds": records}, indent=2) + "\n")
