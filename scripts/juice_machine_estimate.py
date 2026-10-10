#!/usr/bin/env python3
"""Experimental Core counts + llvm-mca costs for audited final-code regions.

The region map is an explicit, binary-specific annotation, not an automatic
source-to-machine correspondence claim. No guest code or payload is executed.
Only long, register-only loops with covered tails are accepted in this version.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

spec = importlib.util.spec_from_file_location("juice_core_cost", Path(__file__).with_name("juice_ir_estimate.py"))
core = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = core
spec.loader.exec_module(core)
Unknown = core.Unknown


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


@dataclass
class Instruction:
    address: int
    symbol: str
    text: str


def disassemble(text):
    instructions = {}
    symbol = None
    for line in text.splitlines():
        if match := re.fullmatch(r"[0-9a-f]+ <([^>]+)>:", line):
            symbol = match[1]
        elif match := re.fullmatch(r"\s*([0-9a-f]+):\s+(.*)", line):
            address = int(match[1], 16)
            if address in instructions:
                raise Unknown("ambiguous disassembly address")
            instructions[address] = Instruction(address, symbol, match[2].split("#")[0].strip())
    return instructions


def region(instructions, piece):
    start, end = int(piece["start"], 16), int(piece["end"], 16)
    if start not in instructions or end not in instructions or end < start:
        raise Unknown("region endpoint is not an instruction")
    selected = [i for a,i in sorted(instructions.items()) if start <= a <= end]
    if any(i.symbol != piece["symbol"] for i in selected):
        raise Unknown("region crosses its declared symbol")
    return selected


def grouping(selected):
    """Recognize the audited decrement-to-zero latch; infer backend unroll factor."""
    branch = re.fullmatch(r"jne\s+([0-9a-f]+)\s+<[^>]+>", selected[-1].text)
    if not branch or int(branch[1],16) != selected[0].address:
        raise Unknown("region is not a straight-line loop with its own backedge")
    update = selected[-2].text
    if match := re.fullmatch(r"add\s+(r\w+),0x([0-9a-f]+)", update):
        step = int(match[2],16)
        if step >= 1 << 63:
            step -= 1 << 64
        factor, register = -step, match[1]
    elif match := re.fullmatch(r"dec\s+(r\w+)", update):
        factor, register = 1, match[1]
    else:
        raise Unknown("unsupported native loop latch")
    if not 1 <= factor <= 64:
        raise Unknown("unsupported native grouping factor")
    legacy = {"rax": "a", "rbx": "b", "rcx": "c", "rdx": "d"}
    if register in legacy:
        stem = legacy[register]
        aliases = {register, "e" + stem + "x", stem + "x", stem + "l", stem + "h"}
    elif register in ("rsi", "rdi", "rbp", "rsp"):
        aliases = {register, "e" + register[1:], register[1:], register[1:] + "l"}
    else:
        aliases = {register, register + "d", register + "w", register + "b"}
    # In this restricted register-only model the counter must be private.
    for i in selected[:-2]:
        if any(re.search(rf"\b{re.escape(alias)}\b", i.text) for alias in aliases):
            raise Unknown("loop counter participates in payload work")
        if i.text.split()[0].startswith("j"):
            raise Unknown("internal branch in a native loop")
    return factor


def normalize(selected):
    result = []
    for i in selected:
        text = i.text
        if re.search(r"\bnop\b", text):
            # Preserve instruction count. MCA does not model the fetch/decode
            # effects of the original multi-byte encoding (retained separately).
            result.append("nop")
            continue
        if re.match(r"j\w+\s", text):
            text = text.split()[0] + " .Ltarget"
        elif text.split()[0] not in {"mov", "xor", "shl", "shr", "sar", "add", "sub",
                                     "inc", "dec", "cmp", "test", "and", "or",
                                     "vpsllq", "vpsrlq", "vpsrad", "vpblendd", "vpxor"}:
            raise Unknown(f"unsupported native instruction: {text}")
        if "[" in text or "PTR" in text:
            raise Unknown("native memory operation requires a memory model")
        # objdump prints sign-extended imm8/imm32 as a 64-bit unsigned hex word;
        # LLVM's Intel-syntax assembler expects its signed form here.
        text = re.sub(r"0x[fF]{8}[0-9a-fA-F]{8}\b", lambda m: str(int(m[0],16) - (1 << 64)), text)
        result.append(text)
    return result


def apply_profile(assembly, profile):
    """Apply only explicitly calibrated instruction forms, never blanket costs."""
    if profile is None:
        return assembly
    register = r"r(?:ax|bx|cx|dx|si|di|bp|sp|[89]|1[0-5])"
    output = []
    for line in assembly.splitlines():
        match = re.fullmatch(rf"(mov|xor)\s+({register}),\s*({register})", line)
        key = match[1] + "_reg64_distinct" if match and match[2] != match[3] else None
        if key in profile["latencies"]:
            output.extend([f"# LLVM-MCA-LATENCY {profile['latencies'][key]}", line, "# LLVM-MCA-LATENCY"])
        else:
            output.append(line)
    return "\n".join(output) + "\n"


def prepare(ir, function, parameters, mapping, instructions):
    result = core.estimate(ir, function, parameters)
    if result["status"] != "estimated":
        raise Unknown(result.get("reason", "machine model needs concrete loop bounds"))
    if function not in mapping["functions"]:
        raise Unknown("no audited mapping for this function")
    loops = {loop["header"]: loop for loop in result["loops"]}
    covered, prepared = set(), []
    for index, description in enumerate(mapping["functions"][function]["regions"]):
        header = description["core_header"]
        if header in covered or header not in loops:
            raise Unknown("duplicate or missing Core loop mapping")
        covered.add(header)
        loop = loops[header]
        per_entry = loop["iterations_per_entry"]["value"]
        entries = loop["entries"]["value"]
        if per_entry is None or entries is None or per_entry < 10000:
            raise Unknown("only long, concrete loops are qualified for this region model")
        code, pieces = [], []
        for piece in description["pieces"]:
            selected = region(instructions, piece)
            repeat = 1
            if "repeat_core_header" in piece:
                inner_header = piece["repeat_core_header"]
                if inner_header in covered or inner_header not in loops:
                    raise Unknown("duplicate or missing nested Core loop mapping")
                covered.add(inner_header)
                inner = loops[inner_header]
                if inner["entries"]["value"] != entries * per_entry:
                    raise Unknown("nested loop entry count does not match its parent")
                factor = grouping(selected)
                count = inner["iterations_per_entry"]["value"]
                if count is None or count % factor or not 1 <= count // factor <= 64:
                    raise Unknown("nested loop needs a bounded exact expansion with no uncovered tail")
                repeat = count // factor
            code.extend(normalize(selected) * repeat)
            pieces.append(dict(**piece, expansion=repeat, original_instructions=[i.text for i in selected]))
        if description["kind"] == "single_loop":
            if len(description["pieces"]) != 1:
                raise Unknown("single loop has multiple pieces")
            factor = grouping(region(instructions, description["pieces"][0]))
        elif description["kind"] == "expanded_nest":
            factor = 1
        else:
            raise Unknown("unknown region composition")
        if per_entry % factor:
            raise Unknown("nonzero native remainder loop is not mapped")
        count = entries * (per_entry // factor)
        assembly = ".intel_syntax noprefix\n.Ltarget:\n" + "\n".join(code) + "\n"
        prepared.append(dict(name=f"{function}-{index}", core_header=header,
                             machine_iterations=count, grouping_factor=factor,
                             assembly=assembly, pieces=pieces))
    if covered != set(loops):
        raise Unknown("uncovered Core loop")
    return result, prepared


def fit_cycles(reports):
    """Slope removes pipeline-fill cost; use total cycles, not BlockRThroughput.

    BlockRThroughput omits loop-carried dependencies. Two adjacent slopes must
    agree within 1%; the threshold is model convergence, not measured accuracy.
    """
    slopes = []
    for a,b in zip(reports, reports[1:]):
        sa, sb = a["CodeRegions"][0]["SummaryView"], b["CodeRegions"][0]["SummaryView"]
        if sb["Iterations"] <= sa["Iterations"]:
            raise Unknown("MCA iteration counts are not increasing")
        slopes.append((sb["TotalCycles"] - sa["TotalCycles"]) / (sb["Iterations"] - sa["Iterations"]))
    if len(slopes) != 2 or min(slopes) <= 0 or abs(slopes[1] / slopes[0] - 1) > .01:
        raise Unknown("MCA cycle slope has not converged")
    return slopes[-1], slopes


def model_region(region, mca, cpu, env, output):
    assembly = output / (region["name"] + ".s")
    assembly.write_text(region["assembly"])
    reports, calls = [], []
    for count in (200, 400, 800):
        command = [str(mca), "-mcpu=" + cpu, "-iterations=" + str(count), "-json", str(assembly)]
        start = time.perf_counter_ns()
        process = subprocess.run(command, env=env, capture_output=True, text=True, timeout=60)
        elapsed = time.perf_counter_ns() - start
        prefix = output / f"{region['name']}-{count}"
        prefix.with_suffix(".json").write_text(process.stdout)
        prefix.with_suffix(".stderr").write_text(process.stderr)
        if process.returncode or process.stderr:
            raise Unknown(f"MCA refused/warned about region {region['name']}: {process.stderr}")
        report = json.loads(process.stdout)
        if len(report["CodeRegions"]) != 1:
            raise Unknown("unexpected MCA region count")
        block = report["CodeRegions"][0]
        if any(i["mayLoad"] or i["mayStore"] or i["hasUnmodeledSideEffects"]
               for i in block["InstructionInfoView"]["InstructionList"]):
            raise Unknown("MCA reports memory or unmodeled side effects")
        reports.append(report)
        calls.append(dict(command=command, elapsed_ns=elapsed, output_sha256=digest(prefix.with_suffix(".json"))))
    score, slopes = fit_cycles(reports)
    return dict(cycles_per_machine_iteration=score, convergence_slopes=slopes, calls=calls,
                block_reciprocal_throughput=reports[-1]["CodeRegions"][0]["SummaryView"]["BlockRThroughput"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--ir", type=Path, required=True)
    parser.add_argument("--map", type=Path, required=True)
    parser.add_argument("--suite", type=Path, required=True)
    parser.add_argument("--mca", type=Path, required=True)
    parser.add_argument("--mca-library-path", type=Path)
    parser.add_argument("--cpu-model", default="alderlake")
    parser.add_argument("--latency-profile", type=Path, help="separately measured instruction latencies; optional")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    mapping, suite = (json.loads(p.read_text()) for p in (args.map, args.suite))
    profile = json.loads(args.latency_profile.read_text()) if args.latency_profile else None
    if profile and profile["cpu_model"] != args.cpu_model:
        parser.error("latency profile belongs to a different CPU model")
    if digest(args.binary) != mapping["binary_sha256"] or digest(args.ir) != mapping["core_ir_sha256"]:
        parser.error("region map does not identify these exact binary/Core IR inputs")
    args.output.mkdir(parents=True, exist_ok=False)
    native = subprocess.run(["objdump", "-d", "-Mintel", "--no-show-raw-insn", str(args.binary)],
                            check=True, capture_output=True, text=True, timeout=30).stdout
    (args.output / "disassembly.txt").write_text(native)
    instructions = disassemble(native)
    env = os.environ.copy()
    if args.mca_library_path:
        env["LD_LIBRARY_PATH"] = str(args.mca_library_path.resolve())
    version = subprocess.run([str(args.mca), "--version"], env=env, check=True, capture_output=True, text=True).stdout
    ir, models, predictions = args.ir.read_text(), {}, {}
    arms = suite["calibration"] + [c[a] for c in suite["cases"] for a in ("base", "candidate")]
    for arm in arms:
        key = f"{arm['function']}-{arm['n']}-{arm['seed']}"
        if key in predictions:
            continue
        try:
            old, regions = prepare(ir, arm["function"], {0: arm["n"], 1: arm["seed"]}, mapping, instructions)
            contributions = []
            for region_ in regions:
                region_["assembly"] = apply_profile(region_["assembly"], profile)
                name = region_["name"]
                if name not in models:
                    models[name] = dict(region=region_, **model_region(region_, args.mca, args.cpu_model, env, args.output))
                elif models[name]["region"]["assembly"] != region_["assembly"]:
                    raise Unknown("region assembly changed across input sizes")
                score = models[name]["cycles_per_machine_iteration"] * region_["machine_iterations"]
                contributions.append(dict(region=name, machine_iterations=region_["machine_iterations"], score=score))
            predictions[key] = dict(status="estimated", function=arm["function"], parameters=old["parameters"],
                                    cycle_score=sum(c["score"] for c in contributions),
                                    core_cycle_score=old["cycle_score"]["value"],
                                    core_weighted_work=old["weighted_work"]["value"], regions=contributions)
        except Unknown as error:
            predictions[key] = dict(status="unknown", reason=str(error))
    write(args.output / "models.json", models)
    write(args.output / "predictions.json", predictions)
    method = dict(schema="juice-machine-prototype-v1", frozen_at_ns=time.time_ns(), cpu_model=args.cpu_model,
                  mca_version=version, hashes={str(p): digest(p) for p in
                      (args.binary, args.ir, args.map, args.suite, args.mca, Path(__file__), Path(core.__file__))},
                  predictions_sha256=digest(args.output / "predictions.json"),
                  limitations=["Audited binary-specific mapping; automatic transformation mapping is not implemented.",
                               "Long register-only loops; nonzero unmapped remainder loops are refused.",
                               "Steady-state CPU cycle model excludes function setup, OS, frequency changes, caches and branch prediction.",
                               "MCA simulation is not guest execution or a timing measurement."])
    if args.mca_library_path:
        method["library_hashes"] = {str(p):digest(p) for p in sorted(args.mca_library_path.glob("lib*.so.*")) if not p.is_symlink()}
    if args.latency_profile:
        method["latency_profile"] = profile
        method["hashes"][str(args.latency_profile)] = digest(args.latency_profile)
    write(args.output / "method.json", method)
    print(json.dumps({key: value.get("cycle_score", value) for key,value in predictions.items()}, indent=2))
    return int(any(p["status"] != "estimated" for p in predictions.values()))


if __name__ == "__main__":
    raise SystemExit(main())
