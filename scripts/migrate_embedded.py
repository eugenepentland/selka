#!/usr/bin/env python3
"""Run the compiler's `fix` over live .my and embedded Markdown/Zig sources.

Usage: scripts/build-slot.sh build python3 scripts/migrate_embedded.py \
    --compiler /absolute/path/to/mylang --dry-run --report receipt.json .

No spelling rewrites are implemented here. The selected compiler runs `fix` on
isolated copies; failing or ambiguous changes never replace the original. Every
compiler invocation has a timed receipt. `extract_sources` and `collect_paths`
are also the corpus interface used by count_spellings.py.
"""
from __future__ import annotations

import argparse
import base64
from dataclasses import dataclass, field
import difflib
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import spelling_census

ROOT = Path(__file__).resolve().parents[1]
SUFFIXES = {'.my', '.md', '.zig', '.json'}
EXCLUDED_PARTS = {'.git', '.zig-cache', '.mylang-cache', 'zig-out', 'node_modules',
                  '__pycache__', 'experiments', 'generated', 'history', 'legacy'}
EXCLUDED_DIRS = ('docs/audits', 'docs/design', 'docs/adr',
                 'test/fixtures/fix-migration', 'tests/fixtures/fix-migration')
EXCLUDED_DOC = re.compile(r'(?:proposal|handoff|implementation|audit|progress|plan)(?:-|\.|$)')
INTENTIONAL_FIXTURE = re.compile(r'(?:^|[/_-])(?:reject(?:ed)?|invalid-syntax|fmt|format)(?:[/_.-]|$)')
FENCE = re.compile(r'^([ \t]*)(`{3,}|~{3,})[ \t]*(\S*)[^\r\n]*$')
ZIG_LINE = re.compile(r'^([ \t]*\\\\)([^\r\n]*)(\r\n|\n|\r)?$')
MODULE = re.compile(r'^module[ \t]+([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)[ \t]*(?:#.*)?$', re.M)
GUEST = re.compile(r'^(?:public[ \t]+|private[ \t]+|extern[ \t]+)?(?:func|def|record|domain|module|union|enum|constraint|type|class|import|const|host[ \t]+(?:func|def))\b|^@(?:requires|ensures|invariant|noalloc)\b', re.M)
REMOVED = re.compile(r'\bE_[A-Z0-9_]+_REMOVED\b')
SKIP = re.compile(r'(?:#|//)[ \t]*migrate-embedded:[ \t]*skip\b([^\r\n]*)')
EXPECT = re.compile(r'^[ \t]*#[ \t]*doc:[ \t]*expect-error[ \t]+(E_\w+)\b', re.M)


@dataclass
class SourceBlock:
    path: Path
    kind: str
    start: int  # host line indices, [start, end)
    end: int
    text: str
    prefixes: list[str] = field(default_factory=list)
    endings: list[str] = field(default_factory=list)
    scope: int = 0
    guest_path: str | None = None
    excluded: str | None = None
    unsafe: str | None = None
    expected_error: str | None = None
    removed_code: str | None = None
    census: dict | None = None
    line_map: list[int] = field(default_factory=list)  # one-based host lines for quoted sources
    host_span: tuple[int, int] | None = None  # exact JSON string-token span
    case_id: str | None = None

    @property
    def label(self) -> str:
        return f'{self.path}:{self.start + 1}'


def read_text(path: Path) -> str:
    # Path.read_text's universal-newline conversion would lose CRLF envelopes.
    return path.read_bytes().decode('utf-8')


def strip_guest(text: str) -> str:
    """Mask comments and quoted strings without changing line/character positions.

    Includes escapes, triple quotes and multiline strings. A # inside a string
    is not a comment; spelling-like text inside either is never counted.
    """
    out = list(text)
    index = 0
    while index < len(text):
        start = index
        if text[index] == '#':
            while index < len(text) and text[index] not in '\r\n':
                index += 1
        elif text[index] in ('"', "'"):
            quote = text[index]
            delimiter = quote * (3 if text.startswith(quote * 3, index) else 1)
            index += len(delimiter)
            while index < len(text):
                if text[index] == '\\':
                    index = min(index + 2, len(text))
                elif text.startswith(delimiter, index):
                    index += len(delimiter)
                    break
                else:
                    index += 1
        else:
            index += 1
            continue
        for at in range(start, index):
            if out[at] not in '\r\n':
                out[at] = ' '
    return ''.join(out)


def path_exclusion(path: Path, root: Path = ROOT) -> str | None:
    try:
        relative = path.absolute().relative_to(root.absolute()).as_posix()
    except ValueError:
        # An explicitly selected external file has no repository ancestry.
        # Host directories such as TMPDIR/.cache are not source exclusions.
        relative = path.name
    parts = Path(relative).parts
    if any(part in EXCLUDED_PARTS or part.startswith('.cache') for part in parts):
        return 'experiment/history/generated/cache tree'
    if any(relative == directory or relative.startswith(directory + '/') for directory in EXCLUDED_DIRS):
        return 'design/audit/history or intentional fix fixture'
    if path.suffix == '.md' and 'docs' in parts and EXCLUDED_DOC.search(path.name):
        return 'design/history document'
    if path.suffix == '.my' and INTENTIONAL_FIXTURE.search(relative):
        return 'intentional rejected-syntax/format fixture'
    return None


def collect_paths(roots: list[Path], root: Path = ROOT, excludes: list[str] | None = None):
    """Return deterministic selected paths and separately reported exclusions."""
    selected: set[Path] = set()
    excluded: list[dict] = []
    for given in roots:
        path = given.absolute()
        if not path.exists():
            raise OSError(f'input does not exist: {given}')
        # Repository selections always retain repository-relative protection.
        # External trees are judged from the selected tree down; explicit files
        # are judged by their basename, never unrelated machine ancestors.
        selection_root = root.absolute() if path.is_relative_to(root.absolute()) else (path if path.is_dir() else path.parent)
        if path.is_dir():
            reason = path_exclusion(path, root if path.is_relative_to(root.absolute()) else path.parent)
            if reason:
                excluded.append({'path': str(path), 'reason': reason})
                continue
            candidates = []
            for directory, folders, filenames in os.walk(path, followlinks=False):
                # Prune only non-source caches. Evidence/design trees are reported
                # at directory granularity instead of enumerating tens of thousands.
                retained = []
                for folder in sorted(folders):
                    child = Path(directory) / folder
                    reason = path_exclusion(child, selection_root)
                    if reason:
                        excluded.append({'path': str(child), 'reason': reason})
                    elif child.is_symlink():
                        excluded.append({'path': str(child), 'reason': 'symlink directory'})
                    else:
                        retained.append(folder)
                folders[:] = retained
                candidates.extend(Path(directory) / name for name in filenames if Path(name).suffix in SUFFIXES)
        else:
            candidates = [path]
        for candidate in sorted(candidates):
            reason = path_exclusion(candidate, selection_root)
            if candidate.is_symlink():
                reason = 'symlink source'
            if candidate.suffix not in SUFFIXES or (candidate.suffix == '.json' and given.is_dir() and 'goldens' not in candidate.parts):
                reason = 'unsupported source shape'
            if any(fnmatch.fnmatch(candidate.as_posix(), pattern) or fnmatch.fnmatch(candidate.relative_to(root).as_posix() if candidate.is_relative_to(root) else candidate.as_posix(), pattern) for pattern in excludes or []):
                reason = 'explicit --exclude'
            if reason:
                excluded.append({'path': str(candidate), 'reason': reason})
            else:
                selected.add(candidate)
    return sorted(selected), excluded


def mark_block(block: SourceBlock, host_context: str = '') -> SourceBlock:
    explicit = SKIP.search(block.text) or SKIP.search(host_context)
    expected = EXPECT.search(block.text)
    block.expected_error = expected.group(1) if expected else None
    if explicit:
        block.excluded = 'explicit migrate-embedded skip' + explicit.group(1)
    elif expected and REMOVED.fullmatch(expected.group(1)):
        block.excluded = 'intentional removed-spelling diagnostic example: ' + expected.group(1)
        block.removed_code = expected.group(1)
    elif REMOVED.search(host_context) and re.search(r'\b(?:reject\w*|expect\w*(?:Error|Message|Alternative|Diagnostic|Code))\s*\(|\.code\s*=', host_context):
        block.excluded = 'intentional removed-spelling Zig diagnostic example'
        block.removed_code = REMOVED.search(host_context).group()
    module = MODULE.search(strip_guest(block.text))
    if module:
        block.guest_path = module.group(1).replace('.', '/') + '.my'
    return block


def bind_census(block: SourceBlock, lines: list[str], owner: int, *, markdown: bool = False) -> SourceBlock:
    """Only the immediately preceding host line can annotate this exact source."""
    try:
        target = spelling_census.host_marker(lines[owner], markdown=markdown) if owner >= 0 else None
        if target:
            target.update(metadata_path=str(block.path), metadata_line=owner + 1, binding='host-adjacent-source')
        spelling_census.attach(block, target, strip_guest(block.text))
    except (OSError, ValueError) as error:
        block.unsafe = 'invalid census metadata: ' + str(error)
        block.excluded = None
        block.removed_code = None
    return block


def infer_zig_path(block: SourceBlock, lines: list[str], host_text: str) -> None:
    """Keep paths after F1-M deletes headers, including Project/File providers."""
    before = ''.join(line for line in lines[max(block.scope, block.start - 8):block.start]
                     if not ZIG_LINE.match(line))
    declared = re.findall(r'\b(?:const|var)\s+(\w+)\s*=\s*$', before, re.M)
    symbol = declared[-1] if declared else None
    if not symbol:
        return
    # Bind only explicit provider path/data relationships in this host scope.
    # Ordinary string literals or variable names are insufficient path evidence.
    scope_end = next((index for index in range(block.start + 1, len(lines))
                      if re.match(r'^(?:test\s|(?:pub\s+)?fn\s|const\s+\w+\s*=\s*struct\b)', lines[index])), len(lines))
    context = ''.join(lines[block.scope:scope_end])
    paths = re.findall(r'\.path\s*=\s*"([^"\n]+\.my)"\s*,\s*\.data\s*=\s*' + re.escape(symbol) + r'\b', context)
    if len(set(paths)) > 1:
        block.unsafe = 'ambiguous embedded path/data binding'
        return
    if paths:
        block.guest_path = paths[0]
        proposed = Path(block.guest_path)
        if proposed.is_absolute() or '..' in proposed.parts:
            block.unsafe = 'embedded path escapes its staged project'


def decode_zig_string(raw: str) -> str:
    """Decode Zig's string escapes without Python's unicode_escape guesses."""
    out = []
    index = 0
    simple = {'n': '\n', 'r': '\r', 't': '\t', '\\': '\\', '"': '"', "'": "'"}
    while index < len(raw):
        if raw[index] != '\\':
            out.append(raw[index])
            index += 1
            continue
        index += 1
        if index >= len(raw):
            raise ValueError('unterminated Zig string escape')
        escape = raw[index]
        if escape in simple:
            out.append(simple[escape])
            index += 1
        elif escape == 'x' and re.fullmatch(r'[0-9a-fA-F]{2}', raw[index + 1:index + 3]):
            out.append(chr(int(raw[index + 1:index + 3], 16)))
            index += 3
        elif escape == 'u' and (match := re.match(r'u\{([0-9a-fA-F]+)\}', raw[index:])):
            out.append(chr(int(match.group(1), 16)))
            index += len(match.group())
        else:
            raise ValueError(f'unsupported Zig string escape: {escape}')
    return ''.join(out)


def quoted_zig_sources(path: Path, text: str) -> list[SourceBlock]:
    """Inventory quoted guest strings too; migration reports their manual limit.

    Concatenated string tokens are one guest source. Strings in host comments,
    character literals and multiline payloads are never reinterpreted as tokens.
    A decoded guest line maps to its actual host line, even for escaped \n.
    """
    tokens = []
    index = 0
    line = 1
    line_start = 0
    while index < len(text):
        if text[index] == '\n':
            line += 1
            index += 1
            line_start = index
            continue
        if text.startswith('//', index) or (text.startswith('\\\\', index) and not text[line_start:index].strip()):
            end = text.find('\n', index)
            index = len(text) if end < 0 else end
            continue
        if text[index] not in ('"', "'"):
            index += 1
            continue
        quote = text[index]
        start = index
        index += 1
        while index < len(text) and text[index] not in (quote, '\n'):
            index += 2 if text[index] == '\\' else 1
        if index >= len(text) or text[index] != quote:
            continue
        index += 1
        if quote == '"':
            try:
                decoded = decode_zig_string(text[start + 1:index - 1])
            except ValueError:
                continue
            tokens.append((start, index, line, decoded))
    blocks = []
    position = 0
    candidate = re.compile(r'\breplace\s*\(|\b(?:bit_and|bit_or|bit_xor|shift_left|shift_right)\s*\(|\beffects\s*\(|\bnoio\b|\bnoalloc\b|;|[=!]=\s*None\b|\b(?:strings|sort)\.\w+\s*\(|\bwrap\s*\[|\bunwrap\s*\(')
    source_call = re.compile(r'\b(?:run\w*|reject\w*|check\w*|parse\w*|expect(?:Message|Alternative|Diagnostic|Code|Fixes)\w*|init|fix\w*)\s*\(\s*$|\b(?:source|text|program|input)\s*=\s*$|\.source\s*=\s*$', re.I)
    while position < len(tokens):
        chain = [tokens[position]]
        position += 1
        while position < len(tokens):
            between = re.sub(r'//[^\n]*', '', text[chain[-1][1]:tokens[position][0]])
            if not re.fullmatch(r'\s*\+\+\s*', between):
                break
            chain.append(tokens[position])
            position += 1
        guest = ''.join(token[3] for token in chain)
        before = text[max(0, chain[0][0] - 160):chain[0][0]]
        after = text[chain[-1][1]:chain[-1][1] + 160]
        masked = strip_guest(guest)
        if not (('\n' in guest and GUEST.search(masked)) or (candidate.search(masked) and source_call.search(before))):
            continue
        # Map the first character of every guest line to its contributing token.
        host_map = []
        at_line_start = True
        for _, _, host_line, decoded in chain:
            for char in decoded:
                if at_line_start:
                    host_map.append(host_line)
                    at_line_start = False
                if char == '\n':
                    at_line_start = True
        block = mark_block(SourceBlock(path, 'zig-inline', chain[0][2] - 1, chain[-1][2], guest,
                                      unsafe='manual migration: quoted Zig guest source; preserve host escapes and concatenation',
                                      line_map=host_map), before + after)
        lines = text.splitlines(keepends=True)
        bind_census(block, lines, chain[0][2] - 2)
        blocks.append(block)
    return blocks


def golden_sources(path: Path, text: str) -> list[SourceBlock]:
    """Find entries[id].case[0] while retaining exact JSON string byte spans.

    Parse the structure rather than searching for duplicate source strings. Only
    the source token is replaced; IDs/options/outcomes retain their original
    bytes, including JSON whitespace, key order and escape spelling.
    """
    document = json.loads(text)
    if not isinstance(document, dict) or not isinstance(document.get('entries'), dict):
        return []
    decoder = json.JSONDecoder()
    blocks = []

    def whitespace(index):
        while index < len(text) and text[index].isspace():
            index += 1
        return index

    def walk(index, keys):
        index = whitespace(index)
        if text[index] == '{':
            index = whitespace(index + 1)
            while text[index] != '}':
                key, index = decoder.raw_decode(text, index)
                index = walk(whitespace(index) + 1, keys + (key,))
                index = whitespace(index)
                if text[index] == ',':
                    index = whitespace(index + 1)
                else:
                    break
            return index + 1
        if text[index] == '[':
            index = whitespace(index + 1)
            item = 0
            while text[index] != ']':
                index = walk(index, keys + (item,))
                item += 1
                index = whitespace(index)
                if text[index] == ',':
                    index = whitespace(index + 1)
                else:
                    break
            return index + 1
        value, end = decoder.raw_decode(text, index)
        if len(keys) == 4 and keys[0] == 'entries' and keys[2:] == ('case', 0) and isinstance(value, str) and '\n' in value:
            host_line = text.count('\n', 0, index) + 1
            block = mark_block(SourceBlock(path, 'json', host_line - 1, host_line, value,
                                          guest_path='case.my', host_span=(index, end), case_id=keys[1],
                                          line_map=[host_line] * len(value.splitlines())))
            entry = document['entries'][keys[1]]
            options = [option for item in entry['case'][1:] if isinstance(item, list) for option in item]
            if keys[1] == '4031fd54adafc91765248f0ee1abc6ce':
                block.excluded = 'archived per-dispatch step-count case (golden_parity.retired)'
            elif '--legacy-sharing' in options:
                block.excluded = 'archived --legacy-sharing case (golden_parity.retired)'
            else:
                try:
                    stderr = base64.b64decode(entry.get('stderr', ''), validate=True)
                    if len(stderr) <= 4096 and b'R_ARENA_ESCAPE' in stderr:
                        block.excluded = 'archived R_ARENA_ESCAPE case (golden_parity.retired)'
                except (ValueError, TypeError):
                    pass
            if block.excluded and block.excluded.startswith('archived '):
                block.removed_code = None
            blocks.append(block)
        return end

    walk(0, ())
    return blocks


def golden_outcomes(text: str) -> dict:
    """Decoded golden state with source fields omitted, for immutable comparison."""
    document = json.loads(text)
    for entry in document.get('entries', {}).values():
        case = entry.get('case') if isinstance(entry, dict) else None
        if isinstance(case, list) and case and isinstance(case[0], str):
            case[0] = '<guest-source>'
    return document


def extract_sources(path: Path, text: str | None = None) -> list[SourceBlock]:
    """Extract guest code; fences, host markers, comments and other languages stay outside.

    Ordinary negative tests remain live. Only a targeted E_*_REMOVED example or
    an explicit skip directive is excluded; failures are reported by migration.
    Zig grouping uses top-level host declarations to retain provider/module
    context. Guest-shaped strings inside non-test Zig files are included too.
    """
    text = read_text(path) if text is None else text
    lines = text.splitlines(keepends=True)
    if path.suffix == '.my':
        block = mark_block(SourceBlock(path, 'my', 0, len(lines), text))
        try:
            spelling_census.attach(block, spelling_census.sidecar(path, text), strip_guest(block.text))
        except (OSError, ValueError) as error:
            block.unsafe = 'invalid census metadata: ' + str(error)
            block.excluded = None
            block.removed_code = None
        return [block]
    if path.suffix == '.json':
        return golden_sources(path, text)
    blocks = []
    index = 0
    scope = 0
    while index < len(lines):
        if path.suffix == '.md':
            opened = FENCE.match(lines[index].rstrip('\r\n'))
            if not opened:
                index += 1
                continue
            indent, marker, language = opened.groups()
            start = index + 1
            end = start
            closing = re.compile(r'^[ \t]*' + re.escape(marker[0]) + '{' + str(len(marker)) + r',}[ \t]*$')
            while end < len(lines) and not closing.match(lines[end].rstrip('\r\n')):
                end += 1
            if language in ('my', 'mylang'):
                body = lines[start:end]
                prefixes = [indent if line.startswith(indent) else '' for line in body]
                payload = ''.join(line[len(prefix):] for line, prefix in zip(body, prefixes))
                block = mark_block(SourceBlock(path, 'md', start, end, payload, prefixes, [line_ending(line) for line in body], scope=start))
                bind_census(block, lines, start - 2, markdown=True)
                if end == len(lines):
                    block.unsafe = 'unterminated Markdown fence'
                blocks.append(block)
            index = min(end + 1, len(lines))
            continue
        if path.suffix == '.zig':
            # At column zero these are host declarations, never guest lines.
            if re.match(r'^(?:test\s|(?:pub\s+)?fn\s|const\s+\w+\s*=\s*struct\b)', lines[index]):
                scope = index
            elif re.match(r'^(?:pub\s+)?(?:const|var)\s', lines[index]):
                scope = 0  # top-level source constants can form one project
            if not ZIG_LINE.match(lines[index]):
                index += 1
                continue
            start = index
            matches = []
            while index < len(lines) and (match := ZIG_LINE.match(lines[index])):
                matches.append(match)
                index += 1
            payload = '\n'.join(match.group(2) for match in matches)
            if not GUEST.search(strip_guest(payload)):
                continue  # C, shell, transcripts and LLVM IR are not guest code.
            before = ''.join(lines[max(scope, start - 5):start])
            after = ''.join(lines[index:min(len(lines), index + 5)])
            block = mark_block(SourceBlock(path, 'zig', start, index, payload,
                              [match.group(1) for match in matches],
                              [match.group(3) or '' for match in matches], scope=scope), before + after)
            bind_census(block, lines, start - 1)
            infer_zig_path(block, lines, text)
            blocks.append(block)
            continue
        break
    if path.suffix == '.zig':
        blocks.extend(quoted_zig_sources(path, text))
        blocks.sort(key=lambda block: (block.start, block.end))
        annotated = {}
        for block in blocks:
            if block.census:
                annotated.setdefault(block.census['metadata_line'], []).append(block)
        for group in annotated.values():
            if len(group) > 1:
                for block in group:
                    block.unsafe = 'invalid census metadata: annotation owns multiple guest sources'
                    block.census = None
                    block.excluded = None
                    block.removed_code = None
    return blocks


def line_ending(text: str) -> str:
    if text.endswith('\r\n'):
        return '\r\n'
    return text[-1:] if text.endswith(('\n', '\r')) else ''


def render_block(block: SourceBlock, updated: str) -> str:
    """Restore the host envelope, allowing compiler fixes to add/delete lines."""
    if updated == block.text:
        return ''  # callers keep the original host bytes
    if block.kind == 'my':
        return preserve_newlines(block.text, updated)
    if block.kind == 'json':
        return json.dumps(preserve_newlines(block.text, updated), ensure_ascii=False)
    old = block.text.splitlines()
    new = updated.splitlines()
    # A final empty Zig payload line is meaningful, unlike a final .my newline.
    if block.kind == 'zig' and block.text.endswith('\n'):
        old.append('')
    if block.kind == 'zig' and updated.endswith('\n'):
        new.append('')
    if not new and block.kind == 'zig':
        new = ['']  # the empty string literal still needs a \\ host marker
    default_prefix = block.prefixes[0] if block.prefixes else ''
    default_ending = next((ending for ending in block.endings if ending), '\n')
    if len(set(block.prefixes)) > 1 and len(old) != len(new):
        raise ValueError('changed line count with inconsistent host indentation')
    defaults = [(default_prefix, default_ending) for _ in new]
    for a, b, size in difflib.SequenceMatcher(a=old, b=new, autojunk=False).get_matching_blocks():
        for offset in range(size):
            if a + offset < len(block.prefixes):
                defaults[b + offset] = (block.prefixes[a + offset], block.endings[a + offset])
    if new and block.endings:
        defaults[-1] = (defaults[-1][0], block.endings[-1])
    # A Markdown closing fence must remain on its own line, even if the compiler
    # drops the trailing guest newline along with the last removed statement.
    return ''.join(prefix + line + ending for line, (prefix, ending) in zip(new, defaults))


def preserve_newlines(original: str, updated: str) -> str:
    endings = {line_ending(line) for line in original.splitlines(keepends=True)} - {''}
    if len(endings) > 1:
        if updated != original:
            raise ValueError('mixed newline styles; review instead of normalizing')
        return original
    ending = next(iter(endings), '\n')
    normalized = updated.replace('\r\n', '\n').replace('\r', '\n')
    if original.endswith(('\n', '\r')) and normalized and not normalized.endswith('\n'):
        normalized += '\n'
    if not original.endswith(('\n', '\r')):
        normalized = normalized.rstrip('\n')
    return normalized.replace('\n', ending)


def project_root(path: Path) -> Path:
    for directory in path.parents:
        if (directory / 'mylang.json').is_file():
            return directory
    return path.parent


def context_files(root: Path) -> list[Path]:
    files = []
    for directory, folders, names in os.walk(root, followlinks=False):
        folders[:] = [name for name in folders if name not in EXCLUDED_PARTS and not name.startswith('.') and not (Path(directory) / name).is_symlink()]
        for name in names:
            candidate = Path(directory) / name
            if candidate.suffix == '.my' or name in ('mylang.json', 'mylang.lock'):
                if candidate.is_symlink():
                    raise ValueError(f'project contains symlink source: {candidate}')
                files.append(candidate)
    config = root / 'mylang.json'
    if config.is_file():
        raw = json.loads(read_text(config)).get('import_policy')
        if isinstance(raw, str):
            policy = (root / raw).resolve()
            if not policy.is_relative_to(root):
                raise ValueError('import_policy escapes the staged project root')
            files.append(policy)
    return sorted(set(files))


def diagnostic_codes(stderr: str) -> list[str]:
    codes = []
    for line in stderr.splitlines():
        try:
            wire = json.loads(line)
        except ValueError:
            continue
        diagnostic = wire.get('diagnostic', {}) if isinstance(wire, dict) else {}
        code = diagnostic.get('code', '')
        # Warnings may remain in accepted guest source.
        if code.startswith('E_'):
            codes.append(code)
    return codes


class Migrator:
    def __init__(self, compiler: Path, selected: set[Path], timeout: float):
        self.compiler = compiler.absolute()
        self.selected = selected
        self.timeout = timeout
        self.receipts: list[dict] = []
        self.expected: dict[Path, bytes] = {}

    def invoke(self, phase: str, target: Path, stage: Path, block: SourceBlock):
        argv = [str(self.compiler), phase, '--diagnostics=json', '--no-cache', str(target)]
        started = time.monotonic()
        receipt = {'source': block.label, 'case_id': block.case_id, 'phase': phase, 'command': argv, 'cwd': str(stage),
                   'affinity': sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else None}
        try:
            result = subprocess.run(argv, cwd=stage, capture_output=True, text=True, timeout=self.timeout)
            receipt.update(exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr)
        except (OSError, subprocess.TimeoutExpired) as error:
            receipt.update(error=str(error), exit_code=None)
            raise ValueError(f'compiler {phase} did not complete: {error}') from error
        finally:
            receipt['elapsed_seconds'] = round(time.monotonic() - started, 6)
            receipt['slow_step'] = receipt['elapsed_seconds'] > 300
            self.receipts.append(receipt)
        return result, receipt

    def fix(self, block: SourceBlock, siblings: list[SourceBlock]) -> dict:
        if block.unsafe:
            raise ValueError(block.unsafe)
        with tempfile.TemporaryDirectory(prefix='mylang-embedded-') as directory:
            stage = Path(directory)
            mapping: dict[Path, Path | SourceBlock] = {}
            if block.kind == 'my':
                root = project_root(block.path)
                for path in context_files(root):
                    copied = stage / path.relative_to(root)
                    copied.parent.mkdir(parents=True, exist_ok=True)
                    self.expected[path] = path.read_bytes()
                    copied.write_bytes(self.expected[path])
                    if path.suffix == '.my':
                        mapping[copied] = path
                target = stage / block.path.relative_to(root)
            else:
                target = stage / (block.guest_path or f'fixture_{block.start + 1}.my')
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(block.text.encode())
                # Match named sibling modules in the same provider/test scope.
                # Duplicate names are ambiguous only if the entry imports them.
                by_name: dict[str, list[SourceBlock]] = {}
                for sibling in siblings:
                    if sibling is not block and sibling.scope == block.scope and sibling.guest_path and not sibling.excluded and not sibling.unsafe:
                        by_name.setdefault(sibling.guest_path, []).append(sibling)
                imports = re.findall(r'^import\s+([\w.]+)', strip_guest(block.text), re.M)
                for name in imports:
                    candidates = by_name.get(name.replace('.', '/') + '.my', [])
                    if len(candidates) > 1:
                        raise ValueError(f'ambiguous embedded import {name}: {len(candidates)} sibling modules')
                for name, candidates in by_name.items():
                    if len(candidates) != 1 or name == target.relative_to(stage).as_posix():
                        continue
                    copied = stage / name
                    copied.parent.mkdir(parents=True, exist_ok=True)
                    copied.write_bytes(candidates[0].text.encode())
                    mapping[copied] = candidates[0]
                mapping[target] = block
            originals = {path: read_text(path) for path in stage.rglob('*.my')}
            result, receipt = self.invoke('fix', target, stage, block)
            expected = block.expected_error
            preserved_rejection = result.returncode == 1 and expected and diagnostic_codes(result.stderr) == [expected]
            if result.returncode != 0 and not preserved_rejection:
                detail = result.stderr.strip() or result.stdout.strip()
                raise ValueError(f'compiler fix exited {result.returncode}; staged edits discarded: {detail}')
            # Independently validate: an exit-zero fix/no-edit summary alone is
            # insufficient evidence that this scratch entry was checked.
            checked, check_receipt = self.invoke('check', target, stage, block)
            check_preserved = checked.returncode == 1 and expected and diagnostic_codes(checked.stderr) == [expected]
            if expected and not check_preserved:
                raise ValueError(f'compiler check no longer reports declared {expected}; expected-error source preserved for review')
            if checked.returncode != 0 and not check_preserved:
                raise ValueError(f'compiler check after fix exited {checked.returncode}; staged edits discarded: {checked.stderr.strip()}')
            receipt['validation_exit_code'] = checked.returncode
            receipt['expected_error_preserved'] = expected if check_preserved else None
            changes = {}
            for copied, original in originals.items():
                if not copied.exists():
                    raise ValueError(f'compiler deleted staged source {copied.relative_to(stage)}')
                updated = read_text(copied)
                if updated == original:
                    continue
                if copied not in mapping:
                    raise ValueError(f'compiler changed unknown staged dependency {copied.relative_to(stage)}')
                live = mapping[copied]
                if isinstance(live, SourceBlock):
                    rendered = render_block(live, updated)
                    host_text = read_text(live.path)
                    host_original = host_text[slice(*live.host_span)] if live.host_span else ''.join(host_text.splitlines(keepends=True)[live.start:live.end])
                    if rendered != host_original:
                        changes[live.host_span or (live.start, live.end)] = rendered
                elif live not in self.selected:
                    raise ValueError(f'compiler changed unselected imported source {live}; select its project too')
                else:
                    rendered = preserve_newlines(original, updated)
                    if rendered != original:
                        changes[live] = rendered
            receipt['changed_sources'] = len(changes)
            return changes


def atomic_write(path: Path, updated: bytes, expected: bytes) -> None:
    """Replace one validated source atomically, refusing concurrent source edits."""
    if path.is_symlink() or path.read_bytes() != expected:
        raise ValueError(f'source changed since staging; refusing replacement: {path}')
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.' + path.name + '.', dir=path.parent, delete=False) as output:
            temporary = Path(output.name)
            os.fchmod(output.fileno(), path.stat().st_mode & 0o777)
            output.write(updated)
            output.flush()
            os.fsync(output.fileno())
        if hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(expected).digest():
            raise ValueError(f'source changed since staging; refusing replacement: {path}')
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('roots', nargs='*', type=Path, default=[Path('.')])
    parser.add_argument('--compiler', type=Path, default=ROOT / 'zig-out/bin/mylang')
    parser.add_argument('--dry-run', '--check', action='store_true', help='run fixes in staging and report without writing')
    parser.add_argument('--report', type=Path, help='write JSON exclusions, changes, failures and command receipts')
    parser.add_argument('--exclude', action='append', default=[], help='additional path glob (repeatable)')
    parser.add_argument('--include-excluded', action='store_true', help='include protected blocks; explicitly listed files can override path exclusions')
    parser.add_argument('--timeout', type=float, default=600)
    options = parser.parse_args(argv)
    report = {'version': 'embedded-migration-v1', 'dry_run': options.dry_run, 'changes': [], 'excluded': [], 'unsafe': [], 'commands': [], 'expected_rejections': []}
    started = time.monotonic()
    try:
        selected, report['excluded'] = collect_paths(options.roots or [Path('.')], excludes=options.exclude)
        if options.include_excluded:
            # This override is deliberate and only affects explicit files.
            for path in options.roots:
                if path.is_file() and path.suffix in SUFFIXES and not path.is_symlink():
                    selected.append(path.absolute())
            selected = sorted(set(selected))
        migrator = Migrator(options.compiler, set(selected), options.timeout)
        for path in selected:
            try:
                original = read_text(path)
                blocks = extract_sources(path, original)
            except (OSError, UnicodeError, ValueError) as error:
                report['unsafe'].append({'path': str(path), 'reason': str(error)})
                continue
            host_lines = original.splitlines(keepends=True)
            replacements = {}
            conflicting = False
            for block in blocks:
                if block.excluded and not options.include_excluded:
                    report['excluded'].append({'path': str(path), 'line': block.start + 1, 'reason': block.excluded,
                                               'removed_code': block.removed_code,
                                               'case_id': block.case_id,
                                               'census': block.census,
                                               'needs_manual_setup_review': bool(block.removed_code or block.census)})
                    continue
                try:
                    changes = migrator.fix(block, blocks)
                    if block.kind == 'my':
                        for changed_path, updated in changes.items():
                            if not options.dry_run:
                                atomic_write(changed_path, updated.encode(), migrator.expected[changed_path])
                            report['changes'].append({'path': str(changed_path), 'line': 1, 'kind': 'my', 'source': block.label})
                    else:
                        for bounds, updated in changes.items():
                            if bounds in replacements and replacements[bounds] != updated:
                                conflicting = True
                                raise ValueError('different compiler entries proposed conflicting edits to the same embedded module')
                            if bounds not in replacements:
                                replacements[bounds] = updated
                                report['changes'].append({'path': str(path), 'line': original.count('\n', 0, bounds[0]) + 1 if block.kind == 'json' else bounds[0] + 1, 'kind': block.kind})
                except (OSError, ValueError) as error:
                    if block.kind != 'my':
                        conflicting = True
                    report['unsafe'].append({'path': str(path), 'line': block.start + 1, 'reason': str(error)})
            if conflicting:
                report['changes'] = [change for change in report['changes'] if change['path'] != str(path)]
                continue
            if replacements and not options.dry_run:
                if path.suffix == '.json':
                    updated_host = original
                    for (start, end), replacement in sorted(replacements.items(), reverse=True):
                        updated_host = updated_host[:start] + replacement + updated_host[end:]
                    if golden_outcomes(original) != golden_outcomes(updated_host):
                        report['unsafe'].append({'path': str(path), 'reason': 'golden IDs/options/outcomes changed; refusing write'})
                        continue
                else:
                    for (start, end), replacement in sorted(replacements.items(), reverse=True):
                        host_lines[start:end] = [replacement]
                    updated_host = ''.join(host_lines)
                try:
                    atomic_write(path, updated_host.encode(), original.encode())
                except (OSError, ValueError) as error:
                    report['unsafe'].append({'path': str(path), 'reason': str(error)})
                    report['changes'] = [change for change in report['changes'] if change['path'] != str(path)]
        report['commands'] = migrator.receipts
        report['expected_rejections'] = [
            {'source': receipt['source'], 'code': receipt['expected_error_preserved'],
             'changed_sources': receipt.get('changed_sources', 0),
             'needs_manual_setup_review': receipt.get('changed_sources', 0) == 0}
            for receipt in migrator.receipts if receipt.get('expected_error_preserved')]
    except (OSError, ValueError) as error:
        report['unsafe'].append({'reason': str(error)})
    report['elapsed_seconds'] = round(time.monotonic() - started, 6)
    if options.report:
        options.report.parent.mkdir(parents=True, exist_ok=True)
        options.report.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    for change in report['changes']:
        print(f"{change['path']}:{change['line']}: {'would change' if options.dry_run else 'changed'} {change['kind']} source")
    for failure in report['unsafe']:
        print(f"{failure.get('path', '<input>')}:{failure.get('line', 1)}: UNSAFE: {failure['reason']}", file=sys.stderr)
    for expected in report['expected_rejections']:
        print(f"{expected['source']}: expected {expected['code']} preserved; {expected['changed_sources']} changed source(s)" +
              ('; no fixes published, review remaining setup' if expected['needs_manual_setup_review'] else ''), file=sys.stderr)
    print(f"{len(report['changes'])} changed source(s), {len(report['excluded'])} explicit exclusion(s), {len(report['unsafe'])} unsafe source(s); {report['elapsed_seconds']:.3f}s", file=sys.stderr)
    return 1 if report['unsafe'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
