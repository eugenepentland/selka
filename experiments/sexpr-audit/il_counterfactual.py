# Counterfactual IL patcher for the 2026-09-18 runtime audit. Usage:
#   mylang emit-project-qbe e_scan.my --drop-step-checks > scan.json
#   python3 il_counterfactual.py scan.json out.json A|AB|ABC
#   mylang build e_scan.my --manifest-file=$PWD/out.json -o scan.bin --mode ReleaseFast
# A = drop every root push/restore; B = inline bytes[i] and the u8->i64 cast; C = drop position stores.
import json, re, sys
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(src))
for f in d["functions"]:
    il = f["il"]
    lines = il.split("\n")
    out = []
    i = 0
    while i < len(lines):
        L = lines[i]
        if "A" in mode and ("call $myl_native_root_push(" in L or "call $myl_qbe_root_restore(" in L):
            i += 1; continue
        if "B" in mode:
            m = re.match(r" %v(\d+) =w call \$myl_native_list_get\(l %v(\d+), l %v(\d+), l %agg(\d+)\)", L)
            if m and any(" loadub %v" in x for x in lines[i+1:i+9]):
                res, lst, idx, agg = m.groups()
                # inline: length at +0, storage at +32; unsigned compare covers negatives
                out.append(f" %len{res} =l loadl %v{lst}")
                out.append(f" %v{res} =w cultl %v{idx}, %len{res}")
                out.append(f" jnz %v{res}, @inl{res}, @inlf{res}")
                out.append(f"@inl{res}")
                out.append(f" %st{res} =l add %v{lst}, 32")
                out.append(f" %el{res} =l loadl %st{res}")
                out.append(f" %el2{res} =l add %el{res}, %v{idx}")
                out.append(f" %by{res} =l loadub %el2{res}")
                out.append(f" storeb %by{res}, %agg{agg}")
                out.append(f"@inlf{res}")
                i += 1; continue
            m = re.match(r" %v(\d+) =l call \$myl_qbe_int_cast\(l %ctx, l 0, l 1, l 64, l %v(\d+)\)", L)
            if m:
                out.append(f" %v{m.group(1)} =l copy %v{m.group(2)}")
                i += 1; continue
        if "C" in mode and re.match(r" storel \d+, %position$", L):
            i += 1; continue
        out.append(L)
        i += 1
    f["il"] = "\n".join(out)
json.dump(d, open(dst, "w"))
