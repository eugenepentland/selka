#!/usr/bin/env python3
"""Reproduce PCB command-family accounting; never execute logged commands.

Usage: python3 analyze.py LOG_ROOT OUTPUT_DIRECTORY
Uses the repository's session parser; source commands stay out of saved metrics.
Families are shell-text hints, not process profiles. The two opaque script
invocations below were inspected in the fixed September 21 snapshot.
"""
import json
from pathlib import Path
import re
import subprocess
import sys
from collections import Counter
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'scripts'))
import audit_deepseek_tools as audit

PROJECT = Path('/home/epentland/ai/canopy/pcb-workbench')
CLI_SESSION = 'ff0433af-19c8-46b4-8dcd-bd073e3c1a76'

def shell_surface(command):
    """Remove common literal heredocs to avoid classifying written docs as work."""
    kept, delimiter = [], None
    for line in command.splitlines():
        if delimiter is not None:
            if line.strip() == delimiter:
                delimiter = None
            continue
        kept.append(line)
        match = re.search(r"<<-?\s*['\"]?(\w+)['\"]?", line)
        if match:
            delimiter = match.group(1)
    return '\n'.join(kept)

MY = r'(?:\bmylang|\$MYLANG|\$M|\$ML)\s+'

def family(row):
    cmd = shell_surface(row['command'])
    if row['session'] == CLI_SESSION and row['seq'] in {507, 602, 682, 732, 790}:
        return 'CLI integration scripts'
    if row['session'] == CLI_SESSION and row['seq'] == 810:
        return 'Compiler readiness polling and CLI integration'
    if row['name'] in {'ask_user_question', 'request_user_input'}:
        return 'Human input'
    if row['name'] in {'list_agents', 'wait_agent', 'wait_agents', 'wait'}:
        return 'Coordination'
    if row['name'] != 'bash':
        return 'Other tools'
    if re.search(r'(?:\./guest/gate\.sh|\b(?:sh|bash)\s+guest/gate\.sh)', cmd):
        return 'Full guest gate'
    test = bool(re.search(MY + r'test\b', cmd))
    run = bool(re.search(MY + r'(?:run|build|run-project)\b', cmd))
    if test and run:
        return 'Mylang test and run mixed'
    if test:
        return 'Mylang test'
    if run:
        return 'Mylang run/build'
    if re.search(MY + r'(?:check|check-project|list-interfaces)\b', cmd):
        return 'Mylang frontend/navigation'
    if re.search(r'\bzig\s+(?:build|test|run)\b', cmd):
        return 'Zig build/test/run'
    if re.search(r'\bsleep\s+\d', cmd):
        return 'Coordination or polling'
    if re.search(r'\b(?:grep|rg|find|cat|sed|head|tail)\b', cmd):
        return 'Read/search or mixed shell'
    return 'Other shell'

def main():
    root, output = map(Path, sys.argv[1:])
    sessions = [audit.read_session(p) for p in audit.session_files(root)]
    ids = [s['header'].get('id') for s in sessions]
    assert len(ids) == len(set(ids)) and None not in ids
    base = audit.make_report(sessions, PROJECT)
    selected = {m['id'] for m in base['manifest']}
    sessions = [s for s in sessions if s['header']['id'] in selected]
    rows = [r for s in sessions for r in s['calls']]
    starts = {(r['session'], r['background_job_id']): r for r in rows if r['background_job_id']}
    outputs = {}
    for session in sessions:
        path = Path(session['source'])
        process = subprocess.Popen(['zstd', '-dc', str(path)], stdout=subprocess.PIPE) if path.suffix == '.zstd' else None
        stream = process.stdout if process else path.open('rb')
        for line in stream:
            event = json.loads(line)
            if event.get('type') == 'tool/result':
                outputs[(session['header']['id'], event['seq'])] = audit.result_text(event['data']['message'].get('content', []))
        stream.close()
        if process:
            assert process.wait() == 0
    for row in rows:
        origin = starts.get((row['session'], row['args'].get('job_id'))) if row['name'] == 'job_output' else None
        row['family'] = family(origin or row)
        row['collection'] = origin is not None
    gates = [r for r in rows if r['family'] == 'Full guest gate']
    timeouts = [r for r in rows if r['managed_timeout']]
    changed = [r for r in rows if r['name'] == 'bash'
               and re.search(MY + r'test\b', shell_surface(r['command']))
               and 'mylang: host failure: SourceChanged' in outputs.get((r['session'], r['result_seq']), '')]
    bash = [r for r in rows if r['name'] == 'bash']
    def summary(items):
        return {**audit.summarize(items), 'coordinates': [[r['session'], r['seq']] for r in items]}
    metrics = {
        'period_start': base['period_start'], 'period_end': base['period_end'],
        'sessions': len(sessions), 'presets': dict(Counter(s['header'].get('agentPreset') for s in sessions)),
        'all_calls': audit.summarize(rows),
        'all_tool_agent_seconds': sum(audit.seconds((r['start_ms'], r['end_ms']) for r in s['calls']) for s in sessions),
        'all_tool_elapsed_union_seconds': audit.seconds((r['start_ms'], r['end_ms']) for r in rows),
        'families': audit.grouped(rows, 'family'),
        'full_gate': summary(gates), 'managed_timeouts': summary(timeouts),
        'source_changed_test_commands': summary(changed),
        'test_command_flags': {flag: summary([r for r in bash if re.search(MY+r'test\b', shell_surface(r['command'])) and flag in shell_surface(r['command'])]) for flag in ['--force', '--filter', '--report', '--no-cache']},
        'top_calls': [{**audit.public_call(r), 'family': r['family']} for r in sorted(rows, key=lambda r: r['seconds'], reverse=True)[:50]],
        'shell_latency': audit.summarize(bash),
        'notes': [
            'All completed calls included; shell coordination is a separate family, not silently excluded.',
            'Job collection time is attributed to its launch command; job lifetime is never added to tool time.',
            'Command families are heuristic whole-call labels, not per-process timings. Mixed edits and commands remain mixed.',
            'SourceChanged count includes direct test-containing bash results with the exact host-failure text; excludes messages, documentation reads and job_output.',
            'This companion reads fixed snapshots twice. Do not use live mutable logs as its input; snapshot first.',
        ],
    }
    output.mkdir(parents=True, exist_ok=True)
    (output/'metrics.json').write_text(json.dumps(metrics, indent=2)+'\n')
    (output/'session-metrics.json').write_text(json.dumps(base, indent=2)+'\n')
    for name, value in metrics['families'].items():
        print(f"{name}: {value['calls']} calls, {value['call_seconds']/60:.2f} min")
    print('gate',metrics['full_gate']['calls'],metrics['full_gate']['call_seconds'])
    print('timeouts',metrics['managed_timeouts']['calls'],metrics['managed_timeouts']['call_seconds'])
    print('SourceChanged',metrics['source_changed_test_commands']['calls'],metrics['source_changed_test_commands']['call_seconds'])

if __name__ == '__main__':
    main()
