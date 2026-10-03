"""Read-only validation of the frozen compiler-screen protocol and receipts."""
import hashlib
import json
import math
from pathlib import Path
import re
import runpy
import statistics

FOUR = {name + "-" + backend for name in ("baseline", "candidate") for backend in ("llvm", "qbe")}
SIX = FOUR | {"rust", "go"}
EVENTS = ("instructions", "cycles", "branches", "branch-misses")
FOCUSED = {"vm/equality", "vm/string_equality"}
STATS = re.compile(r"\[stats\] engine=(vm|tree) allocations=(\d+) collections=(\d+) freed=(\d+) live=(\d+)\n")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load(path):
    return json.loads(Path(path).read_text())


def hashes(root):
    return {str(path.relative_to(root)): sha(path) for path in sorted(root.rglob("*")) if path.is_file()}


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def option(argv, flag):
    require(argv.count(flag) == 1, "missing or repeated command option: " + flag)
    index = argv.index(flag)
    require(index + 1 < len(argv), "option has no value: " + flag)
    return argv[index + 1]


def resolved(value, cwd):
    path = Path(value)
    return (path if path.is_absolute() else cwd / path).resolve()


def checked_samples(doc, manifest, names, phase, rounds, arms, expected_cases=None):
    require(doc.get("verified_after") is True, "measurement unfinished")
    require(doc.get("manifest") == manifest, "measurement manifest differs")
    require(doc.get("phase") == phase and doc.get("rounds") == rounds, "wrong phase or rounds")
    require(type(doc["rounds"]) is int, "round count must be an integer")
    cases = {case["id"]: case for case in doc["cases"]}
    if expected_cases is None:
        expected_cases = {engine + "/" + name for engine in ("vm", "tree") for name in names}
    require(len(doc["cases"]) == len(cases) == len(expected_cases) and set(cases) == expected_cases, "case coverage differs")
    require(set(doc["binary_sha256"]) == arms, "arm coverage differs")
    require(all(doc["binary_sha256"][arm] == manifest["binary_sha256"][arm] for arm in arms), "measured ELF identity differs")
    wanted = {(case, arm, index) for case in cases for arm in arms for index in range(rounds)}
    cells = {(row["case"], row["arm"], row["round"]) for row in doc["samples"]}
    require(cells == wanted and len(cells) == len(doc["samples"]), "missing or duplicate measurement cells")
    stats = {}
    for case in cases.values():
        require(case["id"] == case["engine"] + "/" + case["name"], "case descriptor differs")
        require(sha(case["script"]) == case["script_sha256"], "measurement input changed")
    for row in doc["samples"]:
        require(type(row["round"]) is int and type(row["status"]) is int and row["status"] == 0, "sample failed or invalid status")
        require(row["stdout_sha256"] == sha(cases[row["case"]]["expected"]), "sample output differs")
        require(positive(row["wall_s"]), "invalid wall measurement")
        if phase == "check":
            match = STATS.fullmatch(row["stderr"])
            require(match is not None and match[1] == cases[row["case"]]["engine"], "unexpected smoke diagnostic")
            actual = dict(zip(("allocations", "collections", "freed", "live"), map(int, match.groups()[1:])))
            require(row.get("collector_stats") == actual, "collector stats descriptor differs")
            key = (row["case"], row["round"])
            require(stats.setdefault(key, actual) == actual, "collector stats differ across arms")
        else:
            require(row["stderr"] == "", "measurement diagnostic is not empty")
        if phase == "counters":
            for event in EVENTS:
                require(type(row[event]) is int and row[event] >= 0, "invalid counter")
                require(type(row[event + "_running_pct"]) in (int, float) and row[event + "_running_pct"] == 100, "PMU multiplexed or missing")
            require(positive(row["instructions"]) and positive(row["cycles"]), "zero instruction/cycle counter")
    return cases


def workloads(doc, work, guards):
    bench = work / "reference/benchmarks/lox/bench"
    sizes = load(bench / "sizes.json")
    require(doc["tier"] in ("smoke", "tree", "timed"), "unknown workload tier")
    for case in doc["cases"]:
        key = case["engine"] if doc["tier"] == "timed" else doc["tier"]
        name = case["name"]
        source = bench / "scripts" / (name + ".lox")
        script = work / "inputs" / (name + "." + key + ".lox")
        expected = bench / "expected" / (name + "." + key + ".out")
        require(Path(case["script"]).resolve() == script and Path(case["expected"]).resolve() == expected, "workload path/tier differs")
        require(type(case["size"]) is int and case["size"] == sizes[name][key], "workload size differs")
        first, rest = source.read_text().split("\n", 1)
        require(first.startswith("var N = ") and script.read_text() == "var N = " + str(case["size"]) + ";\n" + rest, "workload source expansion differs")
        for original in (source, expected, bench / "sizes.json"):
            require(str(original) in guards and sha(original) == guards[str(original)], "reference workload is not guarded")


def command_record(path, doc, manifest, guards):
    command = load(path.with_suffix(".command.json"))
    require(type(command.get("status")) is int and command["status"] == 0, "measurement wrapper did not finish successfully")
    require(command.get("sources_verified_after") is True, "wrapper source postcheck missing")
    sources = {arm: value["hashes"] for arm, value in manifest["candidate_sources"].items()}
    require(command["source_hashes_before"] == command["source_hashes_after"] == sources, "wrapper source identity differs")
    require(command["manifest_sha256"] == sha(path.parent / "binaries.json"), "wrapper manifest identity differs")
    require(command["log_sha256"] == sha(path.with_suffix(".log")), "wrapper log changed")
    argv, cwd = command["argv"], Path(command["cwd"])
    require(len(argv) > 2 and argv[2] == doc["phase"], "wrong wrapper phase")
    runner = str(resolved(argv[1], cwd))
    require(runner in guards and sha(runner) == guards[runner], "audit runner is not guarded")
    require(resolved(option(argv, "--work"), cwd) == path.parent, "wrapper work differs")
    require(resolved(option(argv, "--out"), cwd) == path, "wrapper receipt differs")
    require(set(option(argv, "--arms").split(",")) == set(doc["binary_sha256"]), "wrapper arms differ")
    require(option(argv, "--rounds") == str(doc["rounds"]), "wrapper rounds differ")
    require(option(argv, "--tier") == doc["tier"], "wrapper tier differs")
    require(option(argv, "--cpu") == str(doc["cpu"]), "wrapper CPU differs")
    require(argv.count("--stats") == int(doc["phase"] == "check"), "wrapper stats mode differs")
    engines = set(option(argv, "--engines").split(",")) if "--engines" in argv else {"vm", "tree"}
    require(engines == {case["engine"] for case in doc["cases"]}, "wrapper engine scope differs")
    selected = set(filter(None, option(argv, "--cases").split(","))) if "--cases" in argv else set()
    require(not selected or selected == {case["name"] for case in doc["cases"]}, "wrapper case scope differs")
    require(len(doc["cases"]) == 26 or selected, "partial scope needs explicit case selection")


def paired(doc, baseline, candidate, metric):
    table = {(row["case"], row["arm"], row["round"]): row for row in doc["samples"]}
    rows = {}
    for name in sorted(case["id"] for case in doc["cases"]):
        ratios = []
        for index in range(doc["rounds"]):
            before, after = table[name, baseline, index][metric], table[name, candidate, index][metric]
            require(positive(before) and positive(after), "invalid paired metric")
            ratios.append(after / before)
        ratio = statistics.median(ratios)
        rows[name] = {"candidate_over_baseline": ratio, "reduction_pct": 100 * (1 - ratio),
                      "paired_ratios": ratios, "spread_pct": 100 * (max(ratios) - min(ratios)) / ratio}
    engines = {}
    for engine in ("vm", "tree"):
        values = [row["candidate_over_baseline"] for name, row in rows.items() if name.startswith(engine + "/")]
        if values:
            ratio = statistics.geometric_mean(values)
            engines[engine] = {"cases": len(values), "candidate_over_baseline": ratio, "reduction_pct": 100 * (1 - ratio)}
    return {"baseline": baseline, "candidate": candidate, "metric": metric, "engines": engines, "rows": rows}


def same_math(actual, expected):
    if isinstance(expected, dict):
        return isinstance(actual, dict) and set(actual) == set(expected) and all(same_math(actual[key], value) for key, value in expected.items())
    if isinstance(expected, list):
        return isinstance(actual, list) and len(actual) == len(expected) and all(same_math(a, b) for a, b in zip(actual, expected))
    if type(expected) is float:
        return type(actual) in (float, int) and math.isfinite(actual) and math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12)
    return type(actual) is type(expected) and actual == expected


def analysis(path, work, receipts):
    doc = load(path)
    receipt = Path(doc["receipt"]).resolve()
    require(receipt in receipts and doc["receipt_sha256"] == sha(receipt), "analysis receipt binding differs")
    source = receipts[receipt]
    metric, screen = doc["metric"], source["rounds"] == 1
    focused = {case["id"] for case in source["cases"]} == FOCUSED
    require(metric in ("wall_s", "instructions", "cycles"), "unsupported analysis metric")
    require((metric == "wall_s") == (source["phase"] == "time"), "analysis phase differs")
    require(doc.get("coverage_verified") is True and doc["stable_guards_after"] == 223, "analysis guard/coverage declaration differs")
    require(doc["samples"] == len(source["samples"]) and doc["screen_only"] is screen, "analysis sample declaration differs")
    require(not focused or doc.get("partial_matrix_not_selection") is True, "focused analysis must declare its partial scope")
    expected = {}
    for backend in ("llvm", "qbe"):
        candidate = "candidate-" + backend
        controls = ["baseline-" + backend] + ([] if screen or focused else ["rust", "go"])
        for control in controls:
            expected[candidate + "-over-" + control] = paired(source, control, candidate, metric)
    require(same_math(doc["comparisons"], expected), "saved paired analysis arithmetic differs")
    return {"path": str(path), "sha256": sha(path), "receipt": str(receipt), "metric": metric,
            "math_verified": True, "partial_matrix_not_selection": focused, "comparisons": doc["comparisons"]}


def protocol(doc):
    require(all(key in doc for key in ("cases", "samples", "binary_sha256", "rounds", "phase")), "unknown or incomplete phase receipt")
    phase, rounds, arms = doc["phase"], doc["rounds"], set(doc["binary_sha256"])
    kinds = {("check", 1, frozenset(SIX)): "smoke", ("counters", 1, frozenset(FOUR)): "screen",
             ("time", 3, frozenset(SIX)): "full_wall", ("counters", 3, frozenset(SIX)): "full_counters"}
    kind = kinds.get((phase, rounds, frozenset(arms)))
    if phase == "time" and rounds == 3 and arms == FOUR and {case["id"] for case in doc["cases"]} == FOCUSED:
        kind = "focused_wall"
    require(kind is not None, "unsupported measurement protocol")
    return kind


def validate(work):
    # Import after module initialization; archive uses the same checked hash utility.
    from archive import inventory

    work = work.resolve()
    manifest, prepared, guards = load(work / "binaries.json"), load(work / "prepared.json"), load(work / "guards.json")
    validated_inventory = inventory(work, guards, [], [])
    require(len(guards) == prepared["guards"] == 223, "requires reviewed 223-guard protocol")
    require(sha(work / "guards.json") == prepared["guards_sha256"] and sha(work / "binaries.json") == prepared["manifest_sha256"], "preparation identity differs")
    for path, digest in guards.items():
        require(sha(path) == digest, "guard changed: " + path)
    require(prepared["measured_guests_copied_byte_exact"] is True and prepared["rebuild_allocated_sections_exact"] is True, "measured/rebuilt identity declaration missing")
    require(manifest["source37"]["baseline"] == manifest["source37"]["candidate"] and len(manifest["source37"]["candidate"]) == 37, "compiler-only source changed")
    for arm in ("baseline", "candidate"):
        require(hashes(work / arm) == manifest["source37"][arm], "source37 differs: " + arm)
        modules = {name: value for name, value in manifest["source37"][arm].items() if name.endswith(".my")}
        require(len(modules) == 26 and manifest["candidate_sources"][arm] == {"path": str(work / arm), "hashes": modules}, "wrapper source26 map differs")
    require(set(manifest["binaries"]) == set(manifest["binary_sha256"]) == SIX, "preparation guest scope differs")
    qualification = load(work / "author-qualification.json")
    require(qualification.get("verified_after") is True and sha(work / "author-qualification.json") == manifest["qualification_sha256"], "author qualification changed or unfinished")
    qualified = qualification["before"]["artifacts_sha256"]
    source_map = qualification["before"].get("candidate37", qualification["before"].get("source37"))
    require(source_map == manifest["source37"]["candidate"], "qualified source37 differs")
    after_source = qualification["after"].get("candidate37", qualification["after"].get("source37"))
    require(after_source == source_map, "qualified source37 changed during tests")
    require(qualification["before"]["artifacts_sha256"] == qualification["after"]["artifacts_sha256"], "qualified artifacts changed during tests")
    reproduction, builds = load(work / "rebuild-equivalence.json"), load(work / "rebuilt-build.json")
    require(builds["runtime"] == "rc" and builds["compiler_sha256"] == manifest["compiler_sha256"] and builds["qbe_sha256"] == manifest["qbe_sha256"], "RC rebuild tool binding differs")
    require(len(builds["builds"]) == 2 and all(row["status"] == 0 for row in builds["builds"]), "RC rebuild unfinished")
    require(Path(builds["source"]).resolve() == work / "candidate" and builds["source_sha256"] == manifest["candidate_sources"]["candidate"]["hashes"], "RC rebuild source binding differs")
    for key in ("compiler", "qbe"):
        require(builds[key] in guards and sha(builds[key]) == guards[builds[key]] == builds[key + "_sha256"], "RC rebuild tool is not guarded")
    prepare = load(work / "prepare-command.json")
    require(type(prepare["status"]) is int and prepare["status"] == 0, "preparation build wrapper failed")
    argv, cwd = prepare["argv"], Path(prepare["cwd"])
    require(str(resolved(argv[1], cwd)) in guards, "preparation helper is not guarded")
    for flag, value in (("--work", work), ("--source", work / "candidate"), ("--compiler", Path(builds["compiler"])), ("--qbe", Path(builds["qbe"]))):
        require(resolved(option(argv, flag), cwd) == value, "preparation command differs: " + flag)
    require(option(argv, "--runtime") == "rc" and option(argv, "--name") == "rebuilt", "preparation build mode differs")
    elf_helper = resolved(argv[1], cwd).parent / "elf.py"
    require(str(elf_helper) in guards and sha(elf_helper) == guards[str(elf_helper)], "read-only ELF comparer is not guarded")
    compare_elf = runpy.run_path(str(elf_helper))["compare"]
    rebuilt = {}
    for row in builds["builds"]:
        argv, cwd = row["argv"], Path(row["cwd"])
        backend = option(argv, "--backend")
        require(backend in ("llvm", "qbe") and backend not in rebuilt, "RC rebuild backend scope differs")
        path = resolved(option(argv, "-o"), cwd)
        require(path == work / "bin" / ("rebuilt-" + backend), "RC rebuild output differs")
        require(sha(path) == row["binary_sha256"] and sha(str(path) + ".qbe-manifest.json") == row["manifest_sha256"], "RC rebuilt output changed")
        meta = load(str(path) + ".qbe-manifest.json")
        require(meta["backend"] == backend and meta["runtime_object"] == row["runtime_object"] and sha(row["runtime_object"]) == row["runtime_object_sha256"], "RC rebuild backend/runtime differs")
        require(row["runtime_object"] in guards, "RC rebuild runtime is not guarded")
        require("--rc-runtime" in argv and "--gc-runtime" not in argv, "RC rebuild runtime option differs")
        if backend == "llvm":
            require("--qbe" not in argv and option(argv, "--llvm-opt") == "3" and "--lto" in argv, "LLVM rebuild options differ")
        else:
            require(resolved(option(argv, "--qbe"), cwd) == Path(builds["qbe"]) and "--llvm-opt" not in argv and "--lto" not in argv, "QBE rebuild options differ")
        rebuilt[backend] = row
    for arm, path in manifest["binaries"].items():
        require(sha(path) == manifest["binary_sha256"][arm], "measured guest changed")
    for backend in ("llvm", "qbe"):
        path = Path(manifest["binaries"]["baseline-" + backend])
        origins = [name for name, value in guards.items() if value == sha(path) and Path(name) != path]
        require(any(all(name + suffix in guards and sha(str(path) + suffix) == guards[name + suffix]
                        for suffix in (".qbe-manifest.json", ".qbe-receipt")) for name in origins), "control guest/sidecars not bound to guarded originals")
        meta = load(str(path) + ".qbe-manifest.json")
        require(meta["backend"] == backend and meta["runtime_object"] in guards, "control backend/runtime is not guarded")
    for backend in ("llvm", "qbe"):
        path = Path(manifest["binaries"]["candidate-" + backend])
        digest = sha(path)
        origins = [name for name, value in qualified.items() if value == digest and name in guards]
        matches = []
        for name in origins:
            suffixes = (".qbe-manifest.json", ".qbe-receipt")
            if all(name + suffix in qualified and name + suffix in guards and
                   sha(str(path) + suffix) == qualified[name + suffix] == guards[name + suffix] for suffix in suffixes):
                matches.append(name)
        require(matches, "measured ELF/sidecars not bound to qualified originals")
        meta = load(str(path) + ".qbe-manifest.json")
        require(meta["backend"] == backend and meta["runtime_object"] in qualified and meta["runtime_object"] in guards, "qualified runtime/backend binding missing")
        require(sha(meta["runtime_object"]) == qualified[meta["runtime_object"]] == guards[meta["runtime_object"]], "qualified runtime changed")
        entry = reproduction[backend]
        require(entry["qualified_sha256"] == digest and entry["program_layout_exact"] is True, "rebuild evidence differs")
        require(entry["rebuilt_sha256"] == rebuilt[backend]["binary_sha256"] and entry["allocated_sections_exact"], "rebuild comparison is not bound to the rebuilt guest")
        actual = compare_elf(work / "bin" / ("rebuilt-" + backend), path)
        require(same_math(entry, actual), "actual ELF sections/layout differ from saved rebuild evidence")
        require(all(name.startswith(".debug_") or name in (".symtab", ".strtab", ".shstrtab") for name in entry["nonallocated_metadata_differences"]), "rebuild metadata scope broadened")
    names = {path.stem for path in (work / "reference/benchmarks/lox/bench/scripts").glob("*.lox")}
    require(len(names) == 13, "reference case set differs")
    documents = {path: load(path) for path in sorted(work.glob("*.json"))}
    receipts, coverage = {}, {}
    for path, doc in documents.items():
        if not isinstance(doc, dict) or "phase" not in doc:
            continue
        kind = protocol(doc)
        phase, rounds, arms = doc["phase"], doc["rounds"], set(doc["binary_sha256"])
        focused = kind == "focused_wall"
        require(kind not in coverage, "duplicate measurement protocol")
        checked_samples(doc, manifest, names, phase, rounds, arms, FOCUSED if focused else None)
        require(doc["tier"] == ("smoke" if phase == "check" else "tree" if phase == "counters" else "timed"), "measurement tier differs")
        workloads(doc, work, guards)
        command_record(path, doc, manifest, guards)
        receipts[path] = doc
        coverage[kind] = {"present": True, "receipt": str(path), "completed_rows": len(doc["samples"]), "sha256": sha(path),
                          "command_sha256": sha(path.with_suffix(".command.json")), "phase": phase, "tier": doc["tier"], "rounds": rounds,
                          "partial_matrix_not_selection": focused}
    require("smoke" in coverage and "screen" in coverage, "required smoke/screen receipt absent")
    for kind in ("full_wall", "full_counters", "focused_wall"):
        coverage.setdefault(kind, {"present": False, "completed_rows": 0})
    for path, doc in documents.items():
        if path.name.endswith(".command.json") and isinstance(doc, dict):
            argv = doc.get("argv", [])
            if len(argv) > 2 and argv[2] in ("check", "time", "counters", "rss"):
                out = resolved(option(argv, "--out"), Path(doc["cwd"]))
                require(out in receipts, "measurement command has no completed receipt: " + str(path))
    analyses = []
    for path, doc in documents.items():
        if path in receipts:
            continue
        if isinstance(doc, dict) and "comparisons" in doc and "receipt_sha256" in doc and "metric" in doc:
            analyses.append(analysis(path, work, receipts))
    metrics = []
    for path, doc in receipts.items():
        if doc["phase"] == "check":
            continue
        focused = {case["id"] for case in doc["cases"]} == FOCUSED
        for metric in (("wall_s",) if doc["phase"] == "time" else ("instructions", "cycles")):
            comparisons = {}
            for backend in ("llvm", "qbe"):
                controls = ["baseline-" + backend] + ([] if doc["rounds"] == 1 or focused else ["rust", "go"])
                for control in controls:
                    candidate = "candidate-" + backend
                    comparisons[candidate + "-over-" + control] = paired(doc, control, candidate, metric)
            metrics.append({"receipt": str(path), "receipt_sha256": sha(path), "metric": metric,
                            "partial_matrix_not_selection": focused, "comparisons": comparisons})
    require(inventory(work, guards, [], []) == validated_inventory, "work/guards changed or grew during validation")
    return {"version": "lox-compiler-closeout-v1", "work": str(work), "guards_verified": 223,
            "source37_exact": True, "qualified_RC_ELF_sidecars_exact": True,
            "manifest_sha256": sha(work / "binaries.json"), "coverage": coverage, "analyses": analyses, "computed_metrics": metrics,
            "validated_inventory": validated_inventory,
            "rebuild_ELF_sections_rechecked": True, "read_only_ELF_comparer": {"path": str(elf_helper), "sha256": sha(elf_helper)},
            "arithmetic_tolerance": {"relative": 1e-12, "absolute": 1e-12},
            "limits": ["Raw stdout was checked by the guarded runner; receipts retain its SHA, not full stdout.",
                       "Measurement receipts retain stderr tails up to1500 characters; smoke tails must be exactly one equal stats line.",
                       "ELF rebuilds are reproduction evidence; measurements use whole-file-exact qualified RC guests.",
                       "Historical failed preparations/extras are preserved evidence, not successful coverage."],
            "performance_selection_inferred": False}, guards
