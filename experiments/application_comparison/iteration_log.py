"""Append-only, hash-chained experiment events and explicit per-task comparisons."""
import math
import os
from pathlib import Path
from datetime import datetime, timezone
from .storage import digest, locked, read_json, write_json
import json


def read(directory):
    path = Path(directory) / 'events.jsonl'
    rows = []
    previous = None
    if not path.exists():
        return rows
    with path.open() as stream:
        for line in stream:
            row = json.loads(line)
            body = {key: value for key, value in row.items() if key != 'sha256'}
            if row.get('sequence') != len(rows) or row.get('previous') != previous or digest(body) != row.get('sha256'):
                raise ValueError('iteration event chain is corrupt')
            rows.append(row)
            previous = row['sha256']
    return rows


def create(directory, metadata):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    write_json(directory / 'iteration.json', {'version': 'velocity-iteration-log-v1', 'metadata': metadata})
    append(directory, 'created', {'metadata_sha256': digest(metadata)})


def append(directory, event, data):
    directory = Path(directory)
    if not isinstance(event, str) or not event:
        raise ValueError('named event required')
    with locked(directory):
        metadata = read_json(directory / 'iteration.json')
        if metadata.get('version') != 'velocity-iteration-log-v1':
            raise ValueError('unsupported iteration')
        rows = read(directory)
        if rows and rows[0]['data']['metadata_sha256'] != digest(metadata['metadata']):
            raise ValueError('iteration metadata changed')
        body = {'sequence': len(rows), 'previous': rows[-1]['sha256'] if rows else None,
                'utc': datetime.now(timezone.utc).isoformat(), 'event': event, 'data': data}
        row = dict(body, sha256=digest(body))
        with (directory / 'events.jsonl').open('a') as stream:
            stream.write(json.dumps(row, sort_keys=True, allow_nan=False) + '\n')
            stream.flush()
            os.fsync(stream.fileno())
        return row


def compare(task, current, previous):
    """Describe historical elapsed differences without treating failures as wins."""
    for row in (current, previous):
        if row['task'] != task or row['language'] != 'my':
            raise ValueError('comparison requires the same .my task')
        seconds = row['application_seconds']
        if type(seconds) not in (int, float) or not math.isfinite(seconds) or seconds <= 0:
            raise ValueError('positive finite application time required')
        if type(row['accepted']) is not bool:
            raise ValueError('explicit acceptance required')
    result = {'task': task, 'current': current, 'previous': previous, 'causal_claim': False,
              'interpretation': 'historical task comparison; changed agents, baselines, tools and cases may affect time',
              'delta_seconds': current['application_seconds'] - previous['application_seconds'],
              'accepted_both': current['accepted'] and previous['accepted'], 'reduction_percent': None}
    if result['accepted_both']:
        result['reduction_percent'] = 100 * (1 - current['application_seconds'] / previous['application_seconds'])
    return result
