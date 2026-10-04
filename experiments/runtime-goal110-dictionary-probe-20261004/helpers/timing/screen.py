from pathlib import Path
import sys,json,hashlib
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'benchmarks/runtime/expanded'));import run as expanded
runner=expanded.common
class Args:cpu=2
args=Args()
def host_counters():
    records = {}
    relative = Path('/proc/self/cgroup').read_text().strip().split('::', 1)[1]
    path = Path('/sys/fs/cgroup') / relative.lstrip('/')
    while path.is_relative_to('/sys/fs/cgroup'):
        for name in ('cpu.stat', 'cpu.max'):
            target = path / name
            if target.exists():
                records[str(target)] = target.read_text().strip()
        if path == Path('/sys/fs/cgroup'):
            break
        path = path.parent
    for name in ('cpufreq/scaling_cur_freq', 'thermal_throttle/core_throttle_count',
                 'thermal_throttle/package_throttle_count'):
        target = Path(f'/sys/devices/system/cpu/cpu{args.cpu}') / name
        if target.exists():
            records[str(target)] = target.read_text().strip()
    return records

original_invoke=runner.invoke
def witnessed_invoke(*pos,**kw):
 before=host_counters();result=original_invoke(*pos,**kw);result.update(host_before=before,host_after=host_counters());return result
runner.invoke=witnessed_invoke
runner.summarize=lambda report:[]
expanded.markdown=lambda report:'Raw samples complete; summary and bootstrap deferred until paired timing ends.\n'
a=expanded.arguments();assert a.cpu==2 and a.rounds==5 and a.warmups==1 and a.only==['dict_lookup', 'dict_lookup_str', 'dict_update', 'dict_update_str', 'set_dedup', 'mutate_nested', 'string_search'] and a.skip_build
expanded.execute(a)
report=json.loads(a.output.read_text());report['measurement_wrapper']={'path':str(Path(__file__).resolve()),'sha256':runner.digest(__file__),'behavior':'Per-invocation cgroup/frequency counters; summary/bootstrap deferred; nativeguest policy/plans/invocation unchanged.'};report['analysis_pending']=True
a.output.write_text(json.dumps(report,indent=2)+'\n')
