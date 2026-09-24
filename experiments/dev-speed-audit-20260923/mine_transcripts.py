#!/usr/bin/env python3
"""Where did each agent's wall time go? Pairs tool_use with tool_result by id and
classifies commands. usage: mine.py OUT.json TRANSCRIPT..."""
import json, re, sys, os
from datetime import datetime
from collections import defaultdict

def ts(s):
    return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()

CATS = [
    ('gate:test', r'zig build test( |$|\s--)(?!-)'),
    ('gate:test-qbe', r'zig build test-qbe( |$)(?!-build)'),
    ('gate:test-qbe-build', r'zig build test-qbe-build'),
    ('gate:test-schematic/byte-io', r'zig build test-(schematic|byte-io)'),
    ('focused:test-units/cli', r'zig build test-(units|cli)|focused_test\.py'),
    ('build:release-install', r'ReleaseFast'),
    ('build:test-compile', r'zig build test-compile'),
    ('build:fmt', r'zig build fmt|zig fmt'),
    ('build:other-zig-step', r'zig build test-[a-z-]+'),
    ('build:debug', r'zig build'),
    ('guest:mylang-test', r'mylang(\S*)? test\b|/mylang test\b'),
    ('bench', r'bench\.py|bench_parity|parser_bench|bench_svg|hyperfine|taskset'),
    ('guest:build/run/emit', r'mylang(\S*)? (build|run|emit-qbe|check)|/mylang (build|run|emit-qbe|check)'),
    ('native-c-tests', r'test_native_memory|\bcc\b|zig cc'),
    ('git', r'^\s*(cd [^;&]+[;&]+\s*)?git\b'),
    ('profile', r'prof\.py|perf (stat|record)|objdump|nm '),
    ('adapter-tests', r'unittest|test_adapter|pytest'),
    ('search/read-shell', r'\b(grep|rg|sed -n|cat|head|tail|ls|find|wc)\b'),
]

def classify(name, inp):
    if name != 'Bash':
        return 'tool:' + name
    cmd = inp.get('command', '')
    for cat, rx in CATS:
        if re.search(rx, cmd, re.M):
            return cat
    return 'bash:other'

def text_of(content):
    if isinstance(content, str):
        return content
    out = []
    for c in content or []:
        if isinstance(c, dict) and c.get('type') == 'text':
            out.append(c.get('text', ''))
    return '\n'.join(out)

def mine(path):
    events = []
    for line in open(path, errors='replace'):
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    events = [e for e in events if e.get('timestamp')]
    if not events:
        return None
    t0, t1 = ts(events[0]['timestamp']), ts(events[-1]['timestamp'])
    uses = {}
    per = defaultdict(lambda: {'n': 0, 's': 0.0})
    signals = defaultdict(int)
    slot_wait = 0.0
    model_s = 0.0
    prev_t = t0
    bg_launch = 0
    for e in events:
        t = ts(e['timestamp'])
        msg = e.get('message') or {}
        content = msg.get('content')
        if e.get('type') == 'assistant':
            model_s += max(0.0, t - prev_t) if prev_t else 0
            for c in content if isinstance(content, list) else []:
                if isinstance(c, dict) and c.get('type') == 'tool_use':
                    uses[c['id']] = (t, c.get('name'), c.get('input') or {})
                    if (c.get('input') or {}).get('run_in_background'):
                        bg_launch += 1
        elif e.get('type') == 'user' and isinstance(content, list):
            for c in content:
                if isinstance(c, dict) and c.get('type') == 'tool_result' and c.get('tool_use_id') in uses:
                    ut, name, inp = uses.pop(c['tool_use_id'])
                    cat = classify(name, inp)
                    per[cat]['n'] += 1
                    per[cat]['s'] += max(0.0, t - ut)
                    body = text_of(c.get('content'))
                    for m in re.finditer(r'got (build|gate) slot \d+ after (\d+)s', body):
                        slot_wait += int(m.group(2))
                    if re.search(r'DiskQuota|Disk quota exceeded', body): signals['tmp-quota'] += 1
                    if re.search(r'SIGTERM|Killed|signal 9|OutOfMemory|out of memory|oom', body, re.I): signals['killed/oom'] += 1
                    if re.search(r'error: .*compilation errors?|\d+ compilation errors', body): signals['zig-compile-error'] += 1
                    if re.search(r'guardian: run-all: \d+/\d+ failed|guardian: .* FAILED', body): signals['guardian-fail'] += 1
                    if re.search(r'Build Summary: .*failed', body): signals['build-summary-failed'] += 1
                    if re.search(r'Exit code [1-9]', body) or c.get('is_error'): signals['tool-error'] += 1
        prev_t = t
    return {'agent': os.path.basename(path), 'wall_s': t1 - t0, 'start': events[0]['timestamp'],
            'model_s': model_s, 'slot_wait_s': slot_wait, 'bg_launches': bg_launch,
            'per': dict(per), 'signals': dict(signals)}

if __name__ == '__main__':
    out = [r for r in (mine(p) for p in sys.argv[2:]) if r]
    json.dump(out, open(sys.argv[1], 'w'), indent=1)
    tot = defaultdict(lambda: {'n': 0, 's': 0.0}); sig = defaultdict(int); wall = model = slot = 0
    for r in out:
        wall += r['wall_s']; model += r['model_s']; slot += r['slot_wait_s']
        for k, v in r['per'].items():
            tot[k]['n'] += v['n']; tot[k]['s'] += v['s']
        for k, v in r['signals'].items(): sig[k] += v
    print(f"agents {len(out)}  wall {wall/3600:.1f} h  model(gaps before assistant msgs) {model/3600:.1f} h  slot-wait {slot/3600:.1f} h")
    for k, v in sorted(tot.items(), key=lambda kv: -kv[1]['s']):
        print(f"  {k:32s} n={v['n']:5d}  {v['s']/3600:6.2f} h  avg {v['s']/max(1,v['n']):7.1f} s")
    print('signals', dict(sig))
