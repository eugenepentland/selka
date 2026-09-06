"""Execute native aggregate allocation failures and bounded-live-storage checks."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

def invoke(argv, fail=None):
    env = os.environ.copy()
    env.pop("NATIVE_FAIL_ALLOCATION", None)
    if fail is not None:
        env["NATIVE_FAIL_ALLOCATION"] = str(fail)
    return subprocess.run([str(a) for a in argv], capture_output=True, timeout=90, env=env)

def memory(result):
    match = re.search(rb"native-memory: attempts=(\d+) peak=(\d+) live=(\d+)", result.stderr)
    assert match, (result.returncode, result.stderr)
    attempts, peak, live = map(int, match.groups())
    assert live == 0 and result.returncode != 90, result.stderr
    return attempts, peak

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", type=Path, required=True)
    parser.add_argument("--zig", required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    root = Path(__file__).resolve().parents[1]
    prefix = (root / "tests/native_memory.h").read_bytes()
    with tempfile.TemporaryDirectory(prefix="mylang-native-memory-") as tmp:
        tmp = Path(tmp)
        source = tmp / "memory.my"
        generated = tmp / "memory.c"
        executable = tmp / "memory"
        for mode in ("-O0", "-O2"):
            built = invoke([args.zig, "cc", "-std=c11", mode,
                            "-fsanitize=address,undefined", "-fno-sanitize-recover=undefined",
                            root / "tests/native_cleanup.c", "-o", executable])
            assert built.returncode == 0, ("cleanup", mode, built.stderr)
            result = invoke([executable])
            assert result.returncode == 0, ("cleanup", mode, result.stderr)
            memory(result)
        print("native cleanup: reverse locals/operands/schema, retained snapshots and 20000-level nonallocating destruction passed", flush=True)
        programs = {
            "failure": "struct R{values:[2]i64} result Small{ok:i64,err:i64} result Big{err:i64,ok:R} fn make(r:Small)->Big{return new Big.ok(new R{values:new [2]i64[try r,9]});} fn forward(r:Big)->Big{return new Big.ok(update(try r){values:new [2]i64[4,5]});} fn main()->i64{let old=new R{values:new [2]i64[7,8]};let changed=update(old){values:replace(old.values,0,9)};let bad=forward(make(new Small.err(3)));acknowledge bad;match forward(make(new Small.ok(1))){Big.ok(r)=>{return r.values[0]+changed.values[0]+old.values[0];},Big.err(e)=>{return e;}}}",
            "loop": "struct R{values:[2]i64} fn main()->i64{let mut r=new R{values:new [2]i64[0,7]};let saved=r;let mut i=0;while i<20000{r=update(r){values:replace(r.values,0,i)};i+=1;}return r.values[0]+saved.values[1];}",
            "reference": "fn select(a:i64,x:&mut []i64,b:i64)->&mut []i64 from x{borrow mut x[a..b] as selected{return selected;}} fn again(x:&mut []i64)->&mut []i64 from x{borrow mut select(1,x,3) as r{return r;}} fn main()->i64{let mut x=new [3]i64[2,3,5];let old=x;borrow mut x[0..3] as all{borrow mut again(all) as r{write_slice(r,0,9);}}return old[1]+x[1];}",
            "reference-recursive": "fn count(n:i64,x:&mut i64)->i64{if n==0{return read_ref(x);}write_ref(x,read_ref(x)+1);return count(n-1,x);} fn main()->i64{let mut x=0;borrow mut x as r{return count(40,r);}}",
            "reference-trap": "struct R{x:i64} fn main()->i64{let mut a=new [1]R[new R{x:7}];borrow mut a[0..1] as r{write_slice(r,1,new R{x:9});}return 0;}",
            "trap": "struct R{values:[2]i64} fn main()->i64{let r=new R{values:new [2]i64[0,7]};return r.values[2];}",
        }
        for name in ("buffers", "buffer-views", "allocator-capabilities", "arena-reset", "pools", "arenas"):
            programs[name] = (root / "examples" / f"{name}.my").read_text()
        programs["buffer-aggregate"] = "struct R{values:[2]i64} buffer B:R; result A{err:i64,ok:B} result S{err:i64,ok:bool} fn main(heap:allocator)->i64{match acquire_buffer<A>(heap,2){A.ok(acquired)=>{let mut b=acquired;acknowledge append_buffer<S>(b,new R{values:new [2]i64[7,8]});let saved=read_buffer(b,0);acknowledge reserve_buffer<S>(b,heap,4);acknowledge resize_buffer<S>(b,4,saved);acknowledge write_buffer<S>(b,0,new R{values:new [2]i64[9,10]});borrow mut b[0..4] as view{write_slice(view,1,new R{values:new [2]i64[11,12]});}let changed=read_buffer(b,1);acknowledge resize_buffer<S>(b,0,saved);return saved.values[0]+changed.values[0];},A.err(e)=>{return e;}}}"
        programs["arena-loop"] = "buffer B:i64;result A{ok:B,err:i64}result S{ok:bool,err:i64}fn main(heap:allocator)->i64{let mut n=0;arena heap as scratch{while n<20000{match acquire_buffer<A>(scratch,2){A.ok(acquired)=>{let mut b=acquired;acknowledge resize_buffer<S>(b,2,7);acknowledge reserve_buffer<S>(b,scratch,4);},A.err(e)=>{return e;}}acknowledge reset_arena<S>(scratch);n+=1;}}return n;}"
        programs["arena-snapshot"] = "struct R{values:[2]i64}buffer B:R;result A{ok:B,err:i64}result S{ok:bool,err:i64}fn make(heap:allocator)->R{arena heap as scratch{match acquire_buffer<A>(scratch,2){A.ok(acquired)=>{let mut b=acquired;acknowledge append_buffer<S>(b,new R{values:new [2]i64[7,8]});return read_buffer(b,0);},A.err(e)=>{return new R{values:new [2]i64[e,0]};}}}}fn main(heap:allocator)->i64{return make(heap).values[0];}"
        programs["arena-propagation"] = "buffer B:i64;result A{ok:B,err:i64}result W{ok:i64,err:i64}fn work(heap:allocator)->W{arena heap as scratch{let first=try acquire_buffer<A>(scratch,4);let second=try acquire_buffer<A>(scratch,-1);discard first;discard second;return new W.ok(9);}}fn main(heap:allocator)->i64{match work(heap){W.ok(n)=>{return n;},W.err(e)=>{return e;}}}"
        programs["pool-loop"] = "pool P(Id):i64;result A{ok:P,err:i64}result I{ok:Id,err:i64}fn main(heap:allocator)->i64{let mut n=0;while n<20000{match acquire_pool<A>(heap,1){A.ok(acquired)=>{let mut p=acquired;acknowledge insert_pool<I>(p,7);discard clear_pool(p);},A.err(e)=>{return e;}}n+=1;}return n;}"
        failures = 0
        for name, text in programs.items():
            source.write_text(text)
            emitted = invoke([compiler, "emit-c", source])
            assert emitted.returncode == 0, emitted.stderr
            generated.write_bytes(prefix + b"\n" + emitted.stdout)
            for mode in ("-O0", "-O2"):
                built = invoke([args.zig, "cc", "-std=c11", mode, "-fsanitize=address,undefined", "-fno-sanitize-recover=undefined", generated, "-o", executable])
                assert built.returncode == 0, (name, mode, built.returncode, built.stderr)
                baseline = invoke([executable])
                attempts, peak = memory(baseline)
                expected = b"20\n" if name == "failure" else b"12\n" if name == "reference" else b"40\n" if name == "reference-recursive" else b"20006\n"
                buffer_results = {"buffers": b"21\n", "buffer-views": b"19\n", "allocator-capabilities": b"3\n", "buffer-aggregate": b"18\n", "arena-reset": b"3\n", "arena-loop": b"20000\n", "arena-snapshot": b"7\n", "arena-propagation": b"1\n", "pools": b"52\n", "arenas": b"50\n", "pool-loop": b"20000\n"}
                if name in buffer_results:
                    expected = buffer_results[name]
                    vm = invoke([compiler, "run", source])
                    assert vm.returncode == 0 and vm.stdout == expected, (vm.stderr, vm.stdout)
                if name in ("trap", "reference-trap"):
                    code = b"R_INDEX_BOUNDS" if name == "trap" else b"R_SLICE_BOUNDS"
                    assert baseline.returncode == 1 and code in baseline.stderr, baseline.stderr
                else:
                    assert baseline.returncode == 0 and baseline.stdout == expected, (name, baseline.stderr, baseline.stdout)
                if name in ("loop", "arena-loop", "pool-loop"):
                    # 40,000 aggregate replacements must not accumulate live heap.
                    assert peak < 65536, peak
                if name in ("failure", "reference", "reference-recursive", "buffers", "buffer-views", "allocator-capabilities", "buffer-aggregate", "arena-reset", "arena-snapshot", "arena-propagation", "pools", "arenas"):
                    for point in range(1, attempts + 1):
                        failed = invoke([executable], point)
                        memory(failed)
                        assert failed.returncode == 2 and b"OutOfMemory" in failed.stderr, (point, failed.returncode, failed.stderr)
                        failures += 1
                    for options in (["--max-steps=8"], ["--max-frames=1"]):
                        limited = invoke([executable, *options])
                        memory(limited)
                        oracle = invoke([compiler, "run", source, *options])
                        assert limited.returncode == oracle.returncode and limited.stdout == oracle.stdout, (name, options, limited.stderr, oracle.stderr)
                        if oracle.returncode == 1:
                            code = re.search(rb"error\[(R_[A-Z_]+)\]", oracle.stderr)
                            assert code and code.group(1) in limited.stderr, (limited.stderr, oracle.stderr)
        print(f"native memory: {failures} injected allocation failures, normal/trap/budget cleanup, and bounded 20000-update/arena-reset/pool loops passed under address/undefined sanitizers at -O0/-O2")

if __name__ == "__main__":
    main()
