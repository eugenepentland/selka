import collections,json,re
from pathlib import Path
work=Path(__file__).resolve().parent

def parse(side):
    counts,calls=collections.Counter(),collections.Counter();ips=collections.defaultdict(collections.Counter)
    fn=callee=None;incall=False;total=None
    for line in (work/side/'callgrind.out').read_text().splitlines():
        if line.startswith('summary: '):total=int(line.split()[1])
        elif line.startswith('fn='):fn=line[3:]
        elif line.startswith('cfn='):callee=line[4:]
        elif line.startswith('calls='):
            calls[fn,callee]+=int(line[6:].split()[0]);incall=True
        elif line.startswith('0x'):
            fields=line.split()
            if incall:incall=False
            elif len(fields)==3:
                counts[fn]+=int(fields[2]);ips[fn][int(fields[0],16)]+=int(fields[2])
    assert sum(counts.values())==total,(side,sum(counts.values()),total)
    table=json.loads((work/side/'lox.symbols.qbe-manifest.json').read_text())
    names={f['symbol']:f['name']+(' [borrow]' if f['symbol'].endswith('_rc_borrow') else '') for f in table['functions']}
    return {'total':total,'self':dict(counts),'calls':[{'caller':f,'callee':c,'count':n} for(f,c),n in calls.items()],'instructions':{f:{hex(a):n for a,n in cs.items()}for f,cs in ips.items()},'names':names}
d={s:parse(s) for s in ['control','candidate']}
delta=[{'function':f,'name':d['candidate']['names'].get(f,d['control']['names'].get(f,f)),'control':d['control']['self'].get(f,0),'candidate':d['candidate']['self'].get(f,0),'delta':d['candidate']['self'].get(f,0)-d['control']['self'].get(f,0)}for f in d['control']['self'].keys()|d['candidate']['self'].keys()];delta.sort(key=lambda x:abs(x['delta']),reverse=True)
result={'control':d['control'],'candidate':d['candidate'],'total_delta':d['candidate']['total']-d['control']['total'],'function_deltas':delta}
(work/'exact-counts.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({'total_control':d['control']['total'],'total_candidate':d['candidate']['total'],'delta':result['total_delta'],'function_deltas':delta[:30]},indent=2))
