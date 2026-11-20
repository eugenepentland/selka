#!/usr/bin/env python3
"""Inspect and explicitly collect local versioned evidence; no server admission."""
import argparse
import json
from pathlib import Path
import sys

from fuzz_campaign_store import Store, FormatError, RetentionError, DeterminismError


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache-dir', required=True, type=Path)
    commands = parser.add_subparsers(dest='command', required=True)
    gc = commands.add_parser('gc', help='dry-run by default; active stores are skipped')
    gc.add_argument('--max-bytes', type=int)
    gc.add_argument('--max-age-seconds', type=float)
    gc.add_argument('--max-entries', type=int, default=100000)
    gc.add_argument('--apply', action='store_true')
    pin = commands.add_parser('pin', help='retain cache evidence, without asserting validity')
    pin.add_argument('id')
    for field in ('success', 'corpus', 'blob'):
        pin.add_argument('--' + field, action='append', default=[])
    commands.add_parser('unpin').add_argument('id')
    commands.add_parser('clear-conflict', help='discard poisoned evidence after investigation').add_argument('key')
    args = parser.parse_args(argv)
    try:
        store = Store(args.cache_dir)
        if args.command == 'gc':
            result = store.gc(max_bytes=args.max_bytes, max_age=args.max_age_seconds,
                              max_entries=args.max_entries, dry_run=not args.apply)
        elif args.command == 'pin':
            store.pin(args.id, success=args.success, corpus=args.corpus, blobs=args.blob)
            result = {'version': 1, 'pinned': args.id}
        elif args.command == 'unpin':
            store.unpin(args.id)
            result = {'version': 1, 'unpinned': args.id}
        else:
            store.clear_conflict(args.key)
            result = {'version': 1, 'cleared_conflict': args.key}
        print(json.dumps(result, sort_keys=True))
        return 0
    except (OSError, ValueError, FormatError, RetentionError, DeterminismError) as error:
        print('cache-retention: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
