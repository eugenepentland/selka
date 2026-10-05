import json,sys,re,collections
from datetime import datetime
def ts(s): return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
def cat(name,inp):
    if name!='Bash':
        return {'Read':'read/search','Grep':'read/search','Glob':'read/search','Edit':'edit/write','Write':'edit/write','MultiEdit':'edit/write'}.get(name,'other tool:'+name)
    c=inp.get('command','')
    bg=inp.get('run_in_background')
    if re.search(r'build-slot\.sh\s+(gate|status)|zig build test(\s|$)|test-qbe|fmt-check',c): k='gate (full/qbe)'
    elif re.search(r'test-units|test-cli|focused_test|test-compile|-Dtest-filter',c): k='focused zig tests'
    elif re.search(r'zig build',c): k='compiler build'
    elif re.search(r'mylang\S*\s+(test|run)\b',c): k='guest tests/run'
    elif re.search(r'mylang\S*\s+build\b|build_all|emit-qbe',c): k='guest builds'
    elif re.search(r'perf |taskset|measure\.py|ladder\.py|hyperfine|fuzz|corpus_sweep',c): k='measurement/fuzz'
    elif re.search(r'zig cc|gcc|clang',c): k='C builds'
    elif re.search(r'git ',c): k='git'
    elif re.search(r'sleep|wait|until|flock|status',c): k='waiting'
    else: k='other shell'
    return k+(' [bg]' if bg else '')
def analyze(path):
    uses={}; results={}; times=[]
    for line in open(path):
        try: d=json.loads(line)
        except: continue
        t=ts(d['timestamp']); times.append(t)
        m=d.get('message') or {}
        content=m.get('content')
        if not isinstance(content,list): continue
        for c in content:
            if c.get('type')=='tool_use': uses[c['id']]=(t,c['name'],c.get('input',{}))
            elif c.get('type')=='tool_result': results[c['tool_use_id']]=t
    tot=collections.defaultdict(float); cnt=collections.Counter(); longest=[]
    tool_time=0
    for i,(t0,name,inp) in uses.items():
        if i not in results: continue
        dt=results[i]-t0; k=cat(name,inp); tot[k]+=dt; cnt[k]+=1; tool_time+=dt
        longest.append((dt,k,(inp.get('command') or inp.get('file_path') or '')[:110].replace('\n',' ')))
    wall=max(times)-min(times)
    print(f'{path.split("/")[-1][:30]}: wall {wall/3600:.2f} h, tool calls {len(uses)}, tool time {tool_time/3600:.2f} h, model/other {(wall-tool_time)/3600:.2f} h')
    for k,v in sorted(tot.items(),key=lambda x:-x[1]): print(f'   {k:26s} {v/60:7.1f} min  ({100*v/wall:4.1f}% of wall)  n={cnt[k]}')
    print('   longest calls:')
    for dt,k,c in sorted(longest,reverse=True)[:8]: print(f'     {dt/60:6.1f} min  {k:20s} {c}')
for p in sys.argv[1:]: analyze(p)
