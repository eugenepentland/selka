#!/usr/bin/env python3
"""Reuse frozen text-gap validator/paired intervals; keep all six denominators."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import statistics
import sys

HERE = Path(__file__).resolve().parent
REPORTER = Path('/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p4/experiments/text-gaps-20261012/bench/tools/report.py')
P4 = Path('/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p4/experiments/lox-eda-parity-20261013/P4/micro-regression-final-004')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    # Untimed synthesis stays off the measured CPU; no guest is launched here.
    allowed = os.sched_getaffinity(0) - {8}
    if allowed: os.sched_setaffinity(0, {min(allowed)})
    assert not (HERE / 'report.json').exists()
    sys.dont_write_bytecode = True
    source_pins = {str(p):sha(p) for p in [Path(__file__).resolve(),REPORTER,REPORTER.with_name('measure.py'),REPORTER.parents[4]/'experiments/micro-ownership-20261012/tools/report.py']}
    module_spec = importlib.util.spec_from_file_location('frozen_text_report', REPORTER)
    reporter = importlib.util.module_from_spec(module_spec); module_spec.loader.exec_module(reporter)
    completed = json.loads((HERE/'completed-receipt.json').read_text())
    assert completed['status']=='complete' and completed['scope']==6
    source_pins.update(completed['inputs'])
    cells=[]
    lines=['# C4 fresh six-cell micro comparison','', 'Ratios below1 mean lower kernel time per iteration. All comparisons use fresh matched rounds; historical samples are not pooled. Runtime, process RSS and instrumented managed memory remain separate.','', '| Case | Candidate µs | /ZigSafe | /ZigFast | /Rust | /Go | /checked baseline | /checked common |', '|---|---:|---:|---:|---:|---:|---:|---:|']
    for name, result in sorted(completed['results'].items()):
        path=Path(result['path']);assert sha(path)==result['sha256'];source_pins[str(path)]=result['sha256'];raw=json.loads(path.read_text());spec=json.loads((P4/'specs'/(name+'.json')).read_text());assert raw['spec']==spec
        source_pins.update(raw['identities']);assert raw['identities']==raw['identities_after']
        statuses=raw['arm_status'];complete=all(v['status']=='ok' for v in statuses.values()) and all(v['complete'] for v in raw['summary'].values())
        if not complete:
            expected=reporter.measure.registry.checksum(spec['case'],spec['size'],raw['iterations'],spec['seed'])
            for phase in ['pilots','warmups','samples','rss']:
                samples=[v for p in raw['pilots'] for v in p['arms']] if phase=='pilots' else raw[phase]
                for sample in samples:
                    want=reporter.measure.registry.checksum(spec['case'],spec['size'],sample['iterations'],spec['seed'])
                    reporter.previous.validate_guest(sample,spec,want)
            cells.append({'cell':name,'complete':False,'statuses':statuses,'sample_denominators':{a:len([r for r in raw['samples'] if r['arm']==a]) for a in spec['arms']},'counted':raw['counted'],'ratios':None})
            lines.append('| '+name+' | incomplete | — | — | — | — | — | — |');continue
        analyzed=reporter.analyze(path,spec,10000,True)
        analyzed.update(cell=name,complete=True,statuses=statuses,windows=len(raw['windows']),sample_denominators={a:len([r for r in raw['samples'] if r['arm']==a]) for a in spec['arms']},raw_managed={})
        for arm,value in raw['counted'].items():
            if value.get('counter_path'):
                cp=Path(value['counter_path']);assert sha(cp)==value['counter_sha256'];source_pins[str(cp)]=value['counter_sha256'];analyzed['raw_managed'][arm]=json.loads(cp.read_text())
        candidate=analyzed['arms']['checked-candidate'];comparisons=analyzed['comparisons']
        values=[]
        for other in ['zig-safe','zig-fast','rust','go','checked-baseline','checked-common']:
            r=comparisons['checked-candidate/'+other];values.append('%.3f [%.3f,%.3f]'%(r['ratio'],*r['ci95']))
        lines.append('| '+name+' | %.3f | '%(candidate['median_ns']/1000)+' | '.join(values)+' |')
        cells.append(analyzed)
    assert len(cells)==6
    lines+=['','| Case | Arm | RSS KiB median [min,max] | Managed allocations | Cumulative bytes | Managed peak bytes | Exit-live bytes | RC events |','|---|---|---:|---:|---:|---:|---:|---:|']
    for cell in cells:
        for arm, value in cell.get('arms',{}).items():
            rss=value['rss_kib'];managed=value.get('managed',{})
            lines.append('| %s | %s | %s [%s,%s] | %s | %s | %s | %s | %s |'%(cell['cell'],arm,rss['median'],rss['min'],rss['max'],managed.get('allocs','unavailable'),managed.get('cumulative_allocated_bytes','unavailable'),managed.get('peak_live_bytes','unavailable'),managed.get('live_bytes_at_exit','unavailable'),managed.get('rc_events','unavailable')))
    report={'scope':6,'completed_cells':sum(c['complete'] for c in cells),'cells':cells,'source_pins':source_pins,'method':'Pinned existing text-gap reporter.analyze;10000 paired bootstrap resamples; ratio of per-arm kernel-time medians with exploratory95%CI. All six denominators/statuses preserved, no ratios inferred from incomplete cells, no aggregate score. Managed setup-inclusive counters separate from RSS; foreign managed counters unavailable; allocator movement raw. Compilation not measured by this micro campaign.'}
    assert all(sha(p)==h for p,h in source_pins.items())
    (HERE/'report.json').write_text(json.dumps(report,indent=2)+'\n');(HERE/'REPORT.md').write_text('\n'.join(lines)+'\n')
    print('validated',report['completed_cells'],'of6cells; report published')


if __name__=='__main__':main()
