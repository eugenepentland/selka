#!/usr/bin/env python3
"""Checked-in reference outcomes for the guest corpora the native backend must match.

Each corpus driver used to execute every case twice: once on the bytecode
interpreter and once natively.  The interpreter is gone, so the reference side is
recorded ahead of time into ``tests/goldens/<name>.json`` and compared from
there.  ``--record`` on a driver re-runs the reference command and rewrites its
golden file; without it a case that has no recorded outcome is a hard failure
rather than a silent pass.
"""
import base64
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'tests' / 'goldens'
VERSION = 'golden-outcomes-v1'


class Missing(AssertionError):
    """A corpus case carries no recorded outcome, so the golden file is stale."""


class Outcome:
    """One recorded process result, shaped like ``subprocess.CompletedProcess``."""

    def __init__(self, returncode, stdout, stderr):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr

    def __repr__(self):
        return f'Outcome(returncode={self.returncode!r}, stdout={self.stdout!r}, stderr={self.stderr!r})'


class Reference:
    """Recorded outcomes for one named corpus, keyed by the case that produced them."""

    def __init__(self, name, record=False):
        self.name = name
        self.recording = record
        self.scrub = []
        self.path = DIRECTORY / (name + '.json')
        self.entries = {}
        if not record:
            document = json.loads(self.path.read_text())
            assert document['version'] == VERSION, (name, document['version'])
            self.entries = document['entries']

    def key(self, case):
        """Hash the case description so unrelated corpus edits keep their outcomes."""
        encoded = json.dumps(case, sort_keys=True, default=str).encode()
        return hashlib.sha256(encoded).hexdigest()[:32]

    def clean(self, data):
        """Replace volatile absolute paths so a recording is reproducible."""
        for needle, replacement in self.scrub:
            data = data.replace(needle, replacement)
        return data

    def expect(self, case, command=None, cwd=None):
        """Return the recorded outcome for one case, recording it first when asked."""
        identity = self.key(case)
        if self.recording:
            assert command is not None, case
            result = subprocess.run(list(map(str, command)), capture_output=True, timeout=300, cwd=cwd)
            self.entries[identity] = {
                'case': json.loads(json.dumps(case, default=str)),
                'returncode': result.returncode,
                'stdout': base64.b64encode(self.clean(result.stdout)).decode(),
                'stderr': base64.b64encode(self.clean(result.stderr)).decode(),
            }
        entry = self.entries.get(identity)
        if entry is None:
            raise Missing(f'{self.name}: no recorded outcome for {case!r}; rerun the driver with --record')
        return Outcome(entry['returncode'], base64.b64decode(entry['stdout']), base64.b64decode(entry['stderr']))

    def remember(self, case, produce):
        """Return recorded JSON data for one case, computing it only while recording."""
        identity = self.key(case)
        if self.recording:
            self.entries[identity] = {'case': case, 'data': produce()}
        entry = self.entries.get(identity)
        if entry is None:
            raise Missing(f'{self.name}: no recorded data for {case!r}; rerun the driver with --record')
        return entry['data']

    def save(self):
        """Write the golden file when recording; a comparison run leaves it alone."""
        if not self.recording:
            return
        DIRECTORY.mkdir(parents=True, exist_ok=True)
        document = {'version': VERSION, 'entries': self.entries}
        self.path.write_text(json.dumps(document, indent=1, sort_keys=True) + '\n')
        print(f'recorded {len(self.entries)} outcomes into {self.path.relative_to(ROOT)}')


def argument(parser):
    """Add the shared ``--record`` switch to a corpus driver's argument parser."""
    parser.add_argument('--record', action='store_true',
                        help='re-record this corpus’ reference outcomes instead of comparing')
