#!/usr/bin/env python3
"""Attribute every agent's foreground tool time, with blocking waits (until/while/
sleep loops) charged to what they waited for, judged by the log they polled.

usage: attribute_waits.py TRANSCRIPT.jsonl...   (prints the breakdown behind
time-breakdown.txt; transcripts live under ~/.claude/projects/<repo>/<session>/subagents/)
"""
import json, re, sys
from collections import defaultdict
from datetime import datetime


def ts(s):
    return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()


def target(cmd):
    c = cmd.lower()
    if re.search(r'gate|test\.log|test-qbe|fmt-check|zig build test|test-schematic|byte-io|gate_diff|guardian', c):
        return 'gate'
    if re.search(r'releasefast|install|release|prefix', c):
        return 'release-build'
    if re.search(r'bench|suite|measure|batch|matmul|raytrace|binary_trees|candidates|rt\.sh|phases|parser', c):
        return 'benchmark'
    if re.search(r'zig build|build\.log|zb\.sh|build1', c):
        return 'debug-build'
    if re.search(r'mylang test|gc-stress|lang', c):
        return 'guest-tests'
    return 'other'


def is_wait(cmd):
    return bool(re.search(r'\buntil\b|while .*(pgrep|sleep)|\bsleep \d|\bwait\b', cmd))


def category(cmd):
    rules = [
        (r'zig build test( |$)|zig build test --', 'run:full test gate'),
        (r'zig build test-qbe(\s|$)', 'run:test-qbe'),
        (r'zig build test-(schematic|byte-io|qbe-build|docs|lang)', 'run:other gate steps'),
        (r'zig build test-(units|cli)|focused_test', 'run:focused zig tests'),
        (r'ReleaseFast|install\.sh|release', 'run:release build/install'),
        (r'zig build', 'run:debug build'),
        (r'mylang(\S*)? test\b', 'run:guest tests'),
        (r'bench\.py|bench_parity|parser_bench|bench_svg|taskset|rt\.sh', 'run:benchmark'),
        (r'test_native_memory|\bcc\b', 'run:native C tests'),
        (r'mylang(\S*)? (build|run|emit-qbe|check)', 'run:guest build/run/emit'),
        (r'^\s*(cd [^;&]+[;&]+\s*)?git\b', 'git'),
    ]
    for rx, name in rules:
        if re.search(rx, cmd):
            return name
    return 'quick shell (read/grep/edit)'


def main(paths):
    agg = defaultdict(float)
    count = defaultdict(int)
    wall_total = model_total = 0.0
    for path in paths:
        events = []
        for line in open(path, errors='replace'):
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event.get('timestamp'):
                events.append(event)
        if not events:
            continue
        wall_total += ts(events[-1]['timestamp']) - ts(events[0]['timestamp'])
        uses = {}
        previous = ts(events[0]['timestamp'])
        for event in events:
            t = ts(event['timestamp'])
            content = (event.get('message') or {}).get('content')
            if event.get('type') == 'assistant':
                model_total += t - previous
                for item in content if isinstance(content, list) else []:
                    if isinstance(item, dict) and item.get('type') == 'tool_use':
                        uses[item['id']] = (t, item.get('name'), item.get('input') or {})
            elif event.get('type') == 'user' and isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get('type') == 'tool_result' and item.get('tool_use_id') in uses:
                        started, name, inp = uses.pop(item['tool_use_id'])
                        if name == 'Bash':
                            cmd = inp.get('command', '')
                            key = ('wait for:' + target(cmd)) if is_wait(cmd) else category(cmd)
                        else:
                            key = 'tool:' + name
                        agg[key] += t - started
                        count[key] += 1
            previous = t
    print(f"wall={wall_total / 3600:.1f}h model={model_total / 3600:.1f}h ({100 * model_total / wall_total:.0f}%)")
    for key, seconds in sorted(agg.items(), key=lambda kv: -kv[1]):
        if seconds > 60:
            print(f"  {key:34s} {seconds / 3600:6.2f} h  n={count[key]:5d} avg {seconds / count[key]:6.1f}s  "
                  f"({100 * seconds / wall_total:4.1f}% of wall)")


if __name__ == '__main__':
    main(sys.argv[1:])
