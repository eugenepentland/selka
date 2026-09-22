#!/usr/bin/env python3
"""Run instrumented policies outside timing and verify heap/arena accounting."""
import hashlib,json,re,subprocess
from run import CASES,DOCS,MEMORY_LIMIT,OUT,REFS,ROOT,WORK,BASE,environment
STATS_ARMS = ('gc-o3', 'arena-o3')
PATTERN=re.compile(rb'MYLANG_HEAP_STATS (\{.*\})\n$')
def invoke(name,case=None,stress=False):
    binary=WORK/f'stats-{name}'; env=environment(); output=WORK/'stats.svg'; issue=WORK/'stats.issue'
    command=[str(binary),'--print-result']; output.write_bytes(b''); issue.write_bytes(b'')
    if case:
        project=BASE/'projects'/case
        env.update(MYLANG_SCHEMATIC_DECLARED='io::circuit_input,io::pinout_input,io::interface_input,io::length,io::byte,io::put,io::issue',MYLANG_SCHEMATIC_OUTPUT=str(output),MYLANG_SCHEMATIC_ISSUE=str(issue))
        env.update({f'MYLANG_SCHEMATIC_INPUT_{i}':str(project/path) for i,path in enumerate(DOCS)})
    if name.endswith('bounded'): command.append('--max-steps=100000000')
    if stress: command.append('--gc-stress')
    p=subprocess.run(command,cwd=ROOT,env=env,capture_output=True,timeout=90)
    match=PATTERN.fullmatch(p.stderr); assert p.returncode==0 and match,(name,case,stress,p)
    stats=json.loads(match.group(1)); assert stats['arena_chunks_live']==0 and stats['arena_reserved_bytes']==0
    if name.startswith('arena-') or name=='workload-arena':
        assert stats['arena_allocations']>0 and stats['arena_chunks']>0 and stats['arena_released']>0, (name, case, stress, stats)
    else: assert stats['arena_allocations']==0 and stats['arena_chunks']==0
    svg_sha = hashlib.sha256(output.read_bytes()).hexdigest() if case else None
    if case:
        assert p.stdout == b'0\n' and issue.read_bytes() == b''
        assert svg_sha == REFS[case]['mylang-o3']['svg_sha256']
    else:
        assert p.stdout == b'31064064\n'
    return {'stdout':p.stdout.decode(),'issue':issue.read_text() if case else '',
            'svg_sha256':svg_sha,'heap':stats}
def main():
    evidence={'memory_limit_bytes':int(MEMORY_LIMIT),'svg':{},'allocation_workload':{}}
    for name in STATS_ARMS:
        evidence['svg'][name]={}
        for case in CASES:
            evidence['svg'][name][case]={'normal':invoke(name,case),'gc_stress':invoke(name,case,True)}
    for policy in ('gc','arena'):
        name=f'workload-{policy}'; evidence['allocation_workload'][policy]={'normal':invoke(name),'gc_stress':invoke(name,stress=True)}
    (OUT/'heap-statistics.json').write_text(json.dumps(evidence,indent=2)+'\n')
if __name__=='__main__': main()
