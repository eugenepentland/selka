#!/usr/bin/env python3
"""Source-bound intentional A8 witnesses; this metadata never changes a verdict."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

PREFIX = 'spelling-census:'
MARKER = re.compile(r'spelling-census:[ \t]*intentional[ \t]+(A8)[ \t]+(class|arena|escape)[ \t]+--[ \t]+([^\r\n]+)')
PATTERNS = {
    'class': re.compile(r'^\s*class\s+'),
    'arena': re.compile(r'\bwith\s+arena\s*\('),
    'escape': re.compile(r'\.escape\s*\(|(?<![\w.])escape\s*\('),
}


def validate(value: dict) -> dict:
    if not isinstance(value, dict) or set(value) != {'row', 'spelling', 'reason'}:
        raise ValueError('census target needs exactly row, spelling and reason')
    if value['row'] != 'A8' or not isinstance(value['spelling'], str) or value['spelling'] not in PATTERNS:
        raise ValueError('census target must name A8 and class, arena or escape')
    if not isinstance(value['reason'], str) or not value['reason'].strip() or any(char in value['reason'] for char in '\r\n'):
        raise ValueError('census target needs a nonempty reason')
    return dict(value)


def host_marker(line: str, *, markdown: bool = False) -> dict | None:
    if PREFIX not in line:
        return None
    stripped = line.strip()
    if markdown:
        if not (stripped.startswith('<!--') and stripped.endswith('-->')):
            raise ValueError('Markdown census annotation must be one HTML comment before its fence')
        payload = stripped[4:-3].strip()
    else:
        if '//' not in line:
            raise ValueError('Zig census annotation must be a host // comment')
        owner, payload = line.split('//', 1)
        # A trailing comment may sit on the initializer/call argument opener.
        # A standalone comment may precede an inline source token on the next line.
        if owner.strip() and not owner.rstrip().endswith(('=', '(', ',')):
            raise ValueError('Zig census annotation must own the immediately following source')
        payload = payload.strip()
    match = MARKER.fullmatch(payload)
    if match is None:
        raise ValueError('malformed source-bound census annotation')
    return validate(dict(zip(('row', 'spelling', 'reason'), match.groups())))


def sidecar(path: Path, text: str) -> dict | None:
    """Read a narrow sibling manifest, with exact input bytes and confined names."""
    manifest = path.parent / 'spelling-census.json'
    if not manifest.exists():
        return None
    if manifest.is_symlink():
        raise ValueError('census sidecar must not be a symlink')
    data = json.loads(manifest.read_text())
    if not isinstance(data, dict) or set(data) != {'version', 'sources'} or data['version'] != 'intentional-a8-v1':
        raise ValueError('invalid census sidecar version/schema')
    sources = data['sources']
    if not isinstance(sources, dict) or not sources:
        raise ValueError('census sidecar sources must be a nonempty object')
    for name, value in sources.items():
        if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_.-]*\.selka', name) or Path(name).name != name:
            raise ValueError('census sidecar names must be confined .selka basenames')
        if not isinstance(value, dict) or set(value) != {'sha256', 'target'}:
            raise ValueError('census sidecar source needs exactly sha256 and target')
        if not isinstance(value['sha256'], str) or not re.fullmatch(r'[0-9a-f]{64}', value['sha256']):
            raise ValueError('census sidecar needs an exact lowercase SHA256')
        validate(value['target'])
        named = manifest.parent / name
        if named.is_symlink() or not named.is_file():
            raise ValueError('census sidecar names must refer to regular neighboring sources')
        if hashlib.sha256(named.read_bytes()).hexdigest() != value['sha256']:
            raise ValueError(f'stale census sidecar SHA256 for {name}')
    value = sources.get(path.name)
    if value is None:
        return None
    if hashlib.sha256(text.encode()).hexdigest() != value['sha256']:
        raise ValueError(f'stale census source text for {path.name}')
    return dict(validate(value['target']), metadata_path=str(manifest), metadata_line=1, binding='sidecar-sha256')


def protects(target: dict | None, row: str, masked_line: str) -> bool:
    return bool(target and target['row'] == row and PATTERNS[target['spelling']].search(masked_line))


def attach(block, target: dict | None, masked_text: str) -> None:
    if target is None:
        return
    if not any(protects(target, 'A8', line) for line in masked_text.splitlines()):
        raise ValueError('census annotation has no matching target witness in its source')
    block.census = target
    block.excluded = 'intentional census witness: ' + target['reason']
    # Explicit selectors replace broad diagnostic inference for this source.
    block.removed_code = None
