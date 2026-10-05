#!/usr/bin/env python3
"""Checked vs unchecked new-core kernels against Rust and Zig (perf stat cycles and branch misses, CPU 10).

usage: measure.py BIN_DIR RUNNER_BIN_DIR
BIN_DIR holds <kernel>_new and <kernel>_unc; RUNNER_BIN_DIR holds compute-rust, compute-zig-safe, compute-zig-fast.
"""
import random, statistics, subprocess, sys
S=sys.argv[1]; R=sys.argv[2]; CPU=10; SEED=7; ROUNDS=5
SIZES={4096:4000, 64:250000}
K={"integer_math":"int_math","float_math":"float_math","call_direct":"call_direct","branch_predictable":"branch_predictable","branch_mixed":"branch_mixed","binary_search":"binary_search"}
def run(argv):
    d=subprocess.run(["taskset","-c",str(CPU),"perf","stat","-x,","-e","cpu_core/cycles/u,cpu_core/branch-misses/u"]+argv,capture_output=True,text=True)
    if d.returncode: raise SystemExit(d.stderr)
    vals=[int(l.split(",")[0]) for l in d.stderr.splitlines() if l.split(",")[0].isdigit()]
    return d.stdout.split()[0], vals[0], vals[1]
random.seed(1)
for kern, f in K.items():
    cfg=[("new core (checked)", lambda s,i,f=f:[f"{S}/{f}_new",str(s),str(i),str(SEED)]),
         ("new core, no checks", lambda s,i,f=f:[f"{S}/{f}_unc",str(s),str(i),str(SEED)]),
         ("Rust", lambda s,i,k=kern:[f"{R}/compute-rust",k,str(s),str(i),str(SEED)]),
         ("Zig ReleaseSafe", lambda s,i,k=kern:[f"{R}/compute-zig-safe",k,str(s),str(i),str(SEED)]),
         ("Zig ReleaseFast", lambda s,i,k=kern:[f"{R}/compute-zig-fast",k,str(s),str(i),str(SEED)])]
    print(f"\n### {kern} (cycles/element; branch misses per 1000 elements)")
    print("| configuration | 4096 x 4000 | 64 x 250000 | checksum |\n|---|---:|---:|---|")
    tab={n:{} for n,_ in cfg}; sums={n:set() for n,_ in cfg}
    for size,it in SIZES.items():
        it = it//10 if kern=="binary_search" else it
        base={n:[statistics.median(x) for x in zip(*[run(m(size,1))[1:] for _ in range(3)])] for n,m in cfg}
        cyc={n:[] for n,_ in cfg}; mis={n:[] for n,_ in cfg}
        for _ in range(ROUNDS):
            order=list(cfg); random.shuffle(order)
            for n,m in order:
                c,cy,bm=run(m(size,it)); sums[n].add((size,c)); cyc[n].append(cy); mis[n].append(bm)
        for n,_ in cfg:
            el=size*it
            tab[n][size]=((statistics.median(cyc[n])-base[n][0])/el, 1000*(statistics.median(mis[n])-base[n][1])/el)
    ref=sums[cfg[0][0]]
    for n,_ in cfg:
        print(f"| {n} | {tab[n][4096][0]:.3f} ({tab[n][4096][1]:.1f}) | {tab[n][64][0]:.3f} ({tab[n][64][1]:.1f}) | {'same' if sums[n]==ref else 'DIFFERENT'} |")
    sys.stdout.flush()
